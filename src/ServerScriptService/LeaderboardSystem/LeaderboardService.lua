local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local LeaderboardDefinitions = require(script.Parent:WaitForChild("LeaderboardDefinitions"))

local LeaderboardService = {}

-- Default read sizes and cache/write timings keep DataStore traffic predictable.
local DEFAULT_TOP_COUNT = 10
local MAX_TOP_COUNT = 100

local SNAPSHOT_CACHE_SECONDS = 60
local STALE_SNAPSHOT_CACHE_SECONDS = 300

local SHUTDOWN_FLUSH_SECONDS = 20

local WRITE_DEBOUNCE_SECONDS = 8
local WRITE_RETRY_BASE_SECONDS = 3
local WRITE_RETRY_MAX_SECONDS = 120
local WRITE_QUEUE_POLL_SECONDS = 1

local NAME_RETRY_SECONDS = 300

local DATASTORE_READ_REQUEST_TYPE = Enum.DataStoreRequestType.GetSortedAsync
local DATASTORE_WRITE_REQUEST_TYPE = Enum.DataStoreRequestType.SetIncrementSortedAsync

-- orderedStoresById caches OrderedDataStore handles by leaderboard id.
local orderedStoresById = {}

-- memoryValuesByLeaderboardId keeps the latest server-submitted values available for fallback rendering.
local memoryValuesByLeaderboardId = {}

-- lastSubmittedValuesByLeaderboardId prevents repeat writes for unchanged values.
local lastSubmittedValuesByLeaderboardId = {}

-- pendingWritesByLeaderboardId is the debounced write queue keyed by leaderboard id and user id.
local pendingWritesByLeaderboardId = {}

-- snapshotCacheByKey stores recent DataStore snapshots so displays can refresh without over-reading.
local snapshotCacheByKey = {}

-- Player name caches avoid repeated GetNameFromUserIdAsync calls.
local nameCacheByUserId = {}
local nameRetryAfterByUserId = {}
local pendingNameLookupsByUserId = {}

local isInitialized = false
local writeQueueRunning = false
local shutdownFlushRegistered = false

local function toFiniteNumber(value)
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
		return nil
	end

	return numberValue
end

local function sanitizeWholeNumber(value)
	local numberValue = toFiniteNumber(value)
	if numberValue == nil then
		return 0
	end

	return math.max(0, math.floor(numberValue))
end

local function sanitizeSubmittedValue(value)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	return math.max(0, math.floor(value))
end

local function sanitizeLeaderboardId(value)
	if type(value) ~= "string" or value == "" then
		return nil
	end

	return value
end

local function getPublicDefinition(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return nil, "InvalidLeaderboardId"
	end

	local definition = LeaderboardDefinitions.GetDefinition(safeLeaderboardId)
	if type(definition) ~= "table" then
		return nil, "UnknownLeaderboard"
	end

	return definition, nil
end

local function sanitizeTopCount(value, fallback)
	return LeaderboardDefinitions.NormalizeTopCount(value, fallback or DEFAULT_TOP_COUNT, MAX_TOP_COUNT)
end

local function sanitizeUserId(value)
	local userId = toFiniteNumber(value)
	if userId == nil then
		return nil
	end

	userId = math.floor(userId)
	if userId <= 0 then
		return nil
	end

	return userId
end

local function getUserIdFromPlayerOrUserId(playerOrUserId)
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end

	return sanitizeUserId(playerOrUserId)
end

local function getDefinition(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return nil
	end

	return LeaderboardDefinitions.GetDefinition(safeLeaderboardId)
end

local function getMemoryBucket(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return nil
	end

	local bucket = memoryValuesByLeaderboardId[safeLeaderboardId]
	if type(bucket) ~= "table" then
		bucket = {}
		memoryValuesByLeaderboardId[safeLeaderboardId] = bucket
	end

	return bucket
end

local function getLastSubmittedBucket(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return nil
	end

	local bucket = lastSubmittedValuesByLeaderboardId[safeLeaderboardId]
	if type(bucket) ~= "table" then
		bucket = {}
		lastSubmittedValuesByLeaderboardId[safeLeaderboardId] = bucket
	end

	return bucket
end

local function getPendingWriteBucket(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return nil
	end

	local bucket = pendingWritesByLeaderboardId[safeLeaderboardId]
	if type(bucket) ~= "table" then
		bucket = {}
		pendingWritesByLeaderboardId[safeLeaderboardId] = bucket
	end

	return bucket
end

local function getSnapshotCacheKey(leaderboardId, limit)
	return tostring(leaderboardId) .. ":" .. tostring(sanitizeTopCount(limit))
end

local function copyRows(rows)
	local result = {}
	if type(rows) ~= "table" then
		return result
	end

	for index, row in ipairs(rows) do
		if type(row) == "table" then
			result[index] = {
				Rank = row.Rank,
				UserId = row.UserId,
				PlayerName = row.PlayerName,
				Value = row.Value,
			}
		end
	end

	return result
end

local function copySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return nil
	end

	return {
		LeaderboardId = snapshot.LeaderboardId,
		DisplayName = snapshot.DisplayName,
		GeneratedAt = snapshot.GeneratedAt,
		Rows = copyRows(snapshot.Rows),
		Error = snapshot.Error,
		Stale = snapshot.Stale == true,
		Source = snapshot.Source,
		Limit = snapshot.Limit,
	}
end

local function clearSnapshotCache(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return
	end

	local prefix = safeLeaderboardId .. ":"
	for cacheKey in pairs(snapshotCacheByKey) do
		if string.sub(cacheKey, 1, #prefix) == prefix then
			snapshotCacheByKey[cacheKey] = nil
		end
	end
end

local function clearAllSnapshotCache()
	for cacheKey in pairs(snapshotCacheByKey) do
		snapshotCacheByKey[cacheKey] = nil
	end
end

local function getFlushTimeout(timeoutSeconds)
	local timeout = toFiniteNumber(timeoutSeconds)
	if timeout == nil then
		return 30
	end

	return math.max(0, timeout)
end

local function registerShutdownFlush()
	if shutdownFlushRegistered then
		return
	end

	shutdownFlushRegistered = true

	game:BindToClose(function()
		local success, err = pcall(function()
			LeaderboardService.FlushPendingWrites(SHUTDOWN_FLUSH_SECONDS)
		end)

		if not success then
			warn("LeaderboardService shutdown flush failed:", err)
		end
	end)
end

local function hasDataStoreBudget(requestType)
	local success, budgetOrError = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)

	if not success then
		warn("LeaderboardService GetRequestBudgetForRequestType failed:", requestType, budgetOrError)
		return true
	end

	return (tonumber(budgetOrError) or 0) > 0
end

local function getOrderedStore(definition)
	if type(definition) ~= "table" then
		return nil
	end

	local leaderboardId = definition.Id
	if type(leaderboardId) ~= "string" or leaderboardId == "" then
		return nil
	end

	local existingStore = orderedStoresById[leaderboardId]
	if existingStore ~= nil then
		return existingStore
	end

	local success, storeOrError = pcall(function()
		return DataStoreService:GetOrderedDataStore(definition.DataStoreName)
	end)

	if not success then
		warn("LeaderboardService GetOrderedDataStore failed:", leaderboardId, storeOrError)
		return nil
	end

	orderedStoresById[leaderboardId] = storeOrError
	return storeOrError
end

local function getPlayerName(userId)
	local safeUserId = sanitizeUserId(userId)
	if safeUserId == nil then
		return "Unknown"
	end

	local cachedName = nameCacheByUserId[safeUserId]
	if type(cachedName) == "string" and cachedName ~= "" then
		return cachedName
	end

	local onlinePlayer = Players:GetPlayerByUserId(safeUserId)
	if onlinePlayer then
		nameCacheByUserId[safeUserId] = onlinePlayer.Name
		return onlinePlayer.Name
	end

	local retryAfter = nameRetryAfterByUserId[safeUserId]
	if type(retryAfter) ~= "number" or os.clock() >= retryAfter then
		if pendingNameLookupsByUserId[safeUserId] ~= true then
			pendingNameLookupsByUserId[safeUserId] = true

			task.spawn(function()
				local success, nameOrError = pcall(function()
					return Players:GetNameFromUserIdAsync(safeUserId)
				end)

				pendingNameLookupsByUserId[safeUserId] = nil

				if success and type(nameOrError) == "string" and nameOrError ~= "" then
					nameCacheByUserId[safeUserId] = nameOrError
					nameRetryAfterByUserId[safeUserId] = nil
					clearAllSnapshotCache()
					return
				end

				nameRetryAfterByUserId[safeUserId] = os.clock() + NAME_RETRY_SECONDS
				warn("LeaderboardService GetNameFromUserIdAsync failed:", safeUserId, nameOrError)
			end)
		end
	end

	return "User_" .. tostring(safeUserId)
end

local function buildRowsFromMemory(leaderboardId, definition, limit)
	local bucket = getMemoryBucket(leaderboardId)
	local rows = {}

	if type(bucket) ~= "table" or type(definition) ~= "table" then
		return rows
	end

	for userId, value in pairs(bucket) do
		local safeUserId = sanitizeUserId(userId)
		if safeUserId ~= nil then
			rows[#rows + 1] = {
				UserId = safeUserId,
				Value = sanitizeWholeNumber(value),
			}
		end
	end

	local ascending = definition.SortAscending == true
	table.sort(rows, function(a, b)
		if a.Value == b.Value then
			return a.UserId < b.UserId
		end

		if ascending then
			return a.Value < b.Value
		end

		return a.Value > b.Value
	end)

	local result = {}
	local safeLimit = sanitizeTopCount(limit, definition.TopCount)

	for index = 1, math.min(#rows, safeLimit) do
		local row = rows[index]

		result[#result + 1] = {
			Rank = index,
			UserId = row.UserId,
			PlayerName = getPlayerName(row.UserId),
			Value = row.Value,
		}
	end

	return result
end

local function setMemoryValue(leaderboardId, userId, value, removeZeroValues)
	local bucket = getMemoryBucket(leaderboardId)
	if type(bucket) ~= "table" then
		return
	end

	local safeUserId = sanitizeUserId(userId)
	if safeUserId == nil then
		return
	end

	local safeValue = sanitizeWholeNumber(value)

	if safeValue <= 0 and removeZeroValues == true then
		bucket[safeUserId] = nil
		return
	end

	bucket[safeUserId] = safeValue
end

local function getRetryDelay(attemptCount)
	local safeAttemptCount = math.max(1, sanitizeWholeNumber(attemptCount))
	local delay = WRITE_RETRY_BASE_SECONDS * (2 ^ math.min(safeAttemptCount - 1, 6))
	return math.min(delay, WRITE_RETRY_MAX_SECONDS)
end

local function hasPendingWrites()
	for _, bucket in pairs(pendingWritesByLeaderboardId) do
		if type(bucket) == "table" and next(bucket) ~= nil then
			return true
		end
	end

	return false
end

local function processWriteJob(leaderboardId, userId, job, forceDue)
	if type(job) ~= "table" then
		return true
	end

	if job.InFlight == true then
		return false
	end

	local now = os.clock()
	if forceDue ~= true and now < (tonumber(job.NextAttemptAt) or 0) then
		return false
	end

	if not hasDataStoreBudget(DATASTORE_WRITE_REQUEST_TYPE) then
		job.LastError = "WriteBudgetUnavailable"
		job.NextAttemptAt = now + WRITE_QUEUE_POLL_SECONDS
		return false
	end

	job.InFlight = true
	local writeVersion = sanitizeWholeNumber(job.Version)
	local definition = job.Definition
	local safeValue = sanitizeWholeNumber(job.Value)
	local removeZeroValues = job.RemoveZeroValues == true
	local key = tostring(userId)
	local store = getOrderedStore(definition)
	if not store then
		if sanitizeWholeNumber(job.Version) == writeVersion then
			job.AttemptCount = sanitizeWholeNumber(job.AttemptCount) + 1
			job.LastError = "OrderedDataStoreUnavailable"
			job.NextAttemptAt = now + getRetryDelay(job.AttemptCount)
		end

		job.InFlight = false
		return false
	end

	local success, err = pcall(function()
		if safeValue <= 0 and removeZeroValues then
			store:RemoveAsync(key)
		else
			store:SetAsync(key, safeValue)
		end
	end)

	if success then
		setMemoryValue(leaderboardId, userId, safeValue, removeZeroValues)
		clearSnapshotCache(leaderboardId)
		job.InFlight = false

		return sanitizeWholeNumber(job.Version) == writeVersion
	end

	if sanitizeWholeNumber(job.Version) == writeVersion then
		job.AttemptCount = sanitizeWholeNumber(job.AttemptCount) + 1
		job.LastError = "WriteFailed"
		job.NextAttemptAt = now + getRetryDelay(job.AttemptCount)
	end

	job.InFlight = false
	warn("LeaderboardService write failed:", leaderboardId, userId, err)
	return false
end

local function processPendingWrites(forceDue)
	for leaderboardId, bucket in pairs(pendingWritesByLeaderboardId) do
		if type(bucket) == "table" then
			for userId, job in pairs(bucket) do
				if processWriteJob(leaderboardId, userId, job, forceDue) then
					bucket[userId] = nil
				end
			end

			if next(bucket) == nil then
				pendingWritesByLeaderboardId[leaderboardId] = nil
			end
		else
			pendingWritesByLeaderboardId[leaderboardId] = nil
		end
	end
end

local function startWriteQueue()
	if writeQueueRunning then
		return
	end

	writeQueueRunning = true

	task.spawn(function()
		while hasPendingWrites() do
			processPendingWrites(false)
			task.wait(WRITE_QUEUE_POLL_SECONDS)
		end

		writeQueueRunning = false

		if hasPendingWrites() then
			startWriteQueue()
		end
	end)
end

local function queueWrite(definition, userId, value)
	local leaderboardId = definition.Id
	local safeValue = sanitizeWholeNumber(value)
	local removeZeroValues = definition.RemoveZeroValues == true

	setMemoryValue(leaderboardId, userId, safeValue, removeZeroValues)

	local pendingBucket = getPendingWriteBucket(leaderboardId)
	if type(pendingBucket) ~= "table" then
		return false, "InvalidLeaderboard"
	end

	local submittedBucket = getLastSubmittedBucket(leaderboardId)
	if type(submittedBucket) == "table" and pendingBucket[userId] == nil and submittedBucket[userId] == safeValue then
		return true, nil
	end

	if type(submittedBucket) == "table" then
		submittedBucket[userId] = safeValue
	end

	local now = os.clock()
	local existingJob = pendingBucket[userId]
	if type(existingJob) == "table" and sanitizeWholeNumber(existingJob.Value) == safeValue and existingJob.RemoveZeroValues == removeZeroValues then
		return true, nil
	end

	if type(existingJob) == "table" then
		existingJob.Definition = definition
		existingJob.Value = safeValue
		existingJob.RemoveZeroValues = removeZeroValues
		existingJob.AttemptCount = 0
		existingJob.LastError = nil
		existingJob.NextAttemptAt = now + WRITE_DEBOUNCE_SECONDS
		existingJob.Version = sanitizeWholeNumber(existingJob.Version) + 1
	else
		pendingBucket[userId] = {
			Definition = definition,
			Value = safeValue,
			RemoveZeroValues = removeZeroValues,
			AttemptCount = 0,
			LastError = nil,
			NextAttemptAt = now + WRITE_DEBOUNCE_SECONDS,
			Version = 1,
		}
	end

	startWriteQueue()
	return true, nil
end

function LeaderboardService.Init()
	if isInitialized then
		return true
	end

	local definitionsValid, reason = LeaderboardDefinitions.ValidateAll()
	if not definitionsValid then
		error("LeaderboardService invalid definitions: " .. tostring(reason))
	end

	for _, definition in ipairs(LeaderboardDefinitions.GetOrderedDefinitions()) do
		getMemoryBucket(definition.Id)
	end

	isInitialized = true
	registerShutdownFlush()

	return true
end

function LeaderboardService.GetRegisteredLeaderboardIds()
	return LeaderboardDefinitions.GetRegisteredIds()
end

function LeaderboardService.GetDefinition(leaderboardId)
	return getDefinition(leaderboardId)
end

function LeaderboardService.GetValueFromState(state, leaderboardId)
	local definition = getDefinition(leaderboardId)
	if type(definition) ~= "table" then
		return 0
	end

	if type(state) ~= "table" or type(state.Meta) ~= "table" then
		return 0
	end

	return sanitizeWholeNumber(state.Meta[definition.MetaKey])
end

function LeaderboardService.SetPlayerValue(playerOrUserId, leaderboardId, value)
	local definition, definitionReason = getPublicDefinition(leaderboardId)
	if type(definition) ~= "table" then
		return false, definitionReason
	end

	local userId = getUserIdFromPlayerOrUserId(playerOrUserId)
	if userId == nil then
		return false, "InvalidUserId"
	end

	local safeValue = sanitizeSubmittedValue(value)
	if safeValue == nil then
		return false, "InvalidValue"
	end

	LeaderboardService.Init()

	return queueWrite(definition, userId, safeValue)
end

function LeaderboardService.UpdatePlayerFromState(player, state, leaderboardId)
	local definition, definitionReason = getPublicDefinition(leaderboardId)
	if type(definition) ~= "table" then
		return false, definitionReason
	end

	local value = 0
	if type(state) == "table" and type(state.Meta) == "table" and state.Meta[definition.MetaKey] ~= nil then
		value = state.Meta[definition.MetaKey]
	end

	return LeaderboardService.SetPlayerValue(player, definition.Id, value)
end

function LeaderboardService.UpdatePlayerFromStateAll(player, state)
	LeaderboardService.Init()

	local results = {}

	for _, definition in ipairs(LeaderboardDefinitions.GetOrderedDefinitions()) do
		local success, reason = LeaderboardService.UpdatePlayerFromState(player, state, definition.Id)
		results[definition.Id] = {
			Success = success == true,
			Reason = reason,
		}
	end

	return results
end

function LeaderboardService.BuildSnapshot(leaderboardId, limit)
	LeaderboardService.Init()

	local definition, definitionReason = getPublicDefinition(leaderboardId)
	if type(definition) ~= "table" then
		return {
			LeaderboardId = tostring(leaderboardId or ""),
			DisplayName = tostring(leaderboardId or ""),
			GeneratedAt = os.time(),
			Rows = {},
			Error = definitionReason,
			Stale = false,
			Source = "Unavailable",
			Limit = 0,
		}
	end

	local safeLimit = sanitizeTopCount(limit, definition.TopCount)
	local cacheKey = getSnapshotCacheKey(definition.Id, safeLimit)
	local now = os.clock()
	local cachedSnapshotEntry = snapshotCacheByKey[cacheKey]

	if type(cachedSnapshotEntry) == "table" and now - (cachedSnapshotEntry.CachedAt or 0) <= SNAPSHOT_CACHE_SECONDS then
		return copySnapshot(cachedSnapshotEntry.Snapshot)
	end

	local store = getOrderedStore(definition)
	local rows = nil
	local errorReason = nil

	if store then
		if hasDataStoreBudget(DATASTORE_READ_REQUEST_TYPE) then
			local success, pagesOrError = pcall(function()
				return store:GetSortedAsync(definition.SortAscending == true, safeLimit)
			end)

			if success and pagesOrError then
				rows = {}

				local page = pagesOrError:GetCurrentPage()
				for index, entry in ipairs(page) do
					local userId = sanitizeUserId(entry.key)
					local value = sanitizeWholeNumber(entry.value)

					if userId ~= nil then
						rows[#rows + 1] = {
							Rank = index,
							UserId = userId,
							PlayerName = getPlayerName(userId),
							Value = value,
						}
					end
				end
			else
				errorReason = "ReadFailed"
				warn("LeaderboardService BuildSnapshot failed:", definition.Id, pagesOrError)
			end
		else
			errorReason = "ReadBudgetUnavailable"
		end
	else
		errorReason = "OrderedDataStoreUnavailable"
	end

	if rows ~= nil then
		local snapshot = {
			LeaderboardId = definition.Id,
			DisplayName = definition.DisplayName,
			GeneratedAt = os.time(),
			Rows = rows,
			Error = nil,
			Stale = false,
			Source = "DataStore",
			Limit = safeLimit,
		}

		snapshotCacheByKey[cacheKey] = {
			Snapshot = copySnapshot(snapshot),
			CachedAt = now,
		}

		return snapshot
	end

	if type(cachedSnapshotEntry) == "table" and now - (cachedSnapshotEntry.CachedAt or 0) <= STALE_SNAPSHOT_CACHE_SECONDS then
		local staleSnapshot = copySnapshot(cachedSnapshotEntry.Snapshot)
		if staleSnapshot ~= nil then
			staleSnapshot.GeneratedAt = os.time()
			staleSnapshot.Error = errorReason
			staleSnapshot.Stale = true
			staleSnapshot.Source = "CachedDataStore"
			return staleSnapshot
		end
	end

	local memoryRows = buildRowsFromMemory(definition.Id, definition, safeLimit)
	if #memoryRows > 0 then
		return {
			LeaderboardId = definition.Id,
			DisplayName = definition.DisplayName,
			GeneratedAt = os.time(),
			Rows = memoryRows,
			Error = errorReason,
			Stale = false,
			Source = "Memory",
			Limit = safeLimit,
		}
	end

	return {
		LeaderboardId = definition.Id,
		DisplayName = definition.DisplayName,
		GeneratedAt = os.time(),
		Rows = {},
		Error = errorReason,
		Stale = false,
		Source = "Unavailable",
		Limit = safeLimit,
	}
end

function LeaderboardService.FlushPendingWrites(timeoutSeconds)
	LeaderboardService.Init()

	local deadline = os.clock() + getFlushTimeout(timeoutSeconds)
	while hasPendingWrites() and os.clock() < deadline do
		processPendingWrites(true)

		if hasPendingWrites() then
			task.wait(0.5)
		end
	end

	return not hasPendingWrites()
end

return LeaderboardService
