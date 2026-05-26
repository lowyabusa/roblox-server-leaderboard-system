local LeaderboardDefinitions = {}

local MIN_TOP_COUNT = 1
local MAX_TOP_COUNT = 100

-- Add or remove leaderboards here, then keep ORDER in the display order you want.
-- DataStoreName values are samples. Replace them with names owned by your game before publishing.
local DEFINITIONS_BY_ID = {
	Score = {
		Id = "Score",
		DisplayName = "Top Score",
		MetaKey = "Score",
		DataStoreName = "GenericLeaderboard_Score",
		SortAscending = false,
		TopCount = 10,
		RemoveZeroValues = true,
	},

	Wins = {
		Id = "Wins",
		DisplayName = "Most Wins",
		MetaKey = "Wins",
		DataStoreName = "GenericLeaderboard_Wins",
		SortAscending = false,
		TopCount = 10,
		RemoveZeroValues = true,
	},

	Level = {
		Id = "Level",
		DisplayName = "Highest Level",
		MetaKey = "Level",
		DataStoreName = "GenericLeaderboard_Level",
		SortAscending = false,
		TopCount = 10,
		RemoveZeroValues = true,
	},
}

local ORDER = {
	"Score",
	"Wins",
	"Level",
}

local function copyDefinition(definition)
	if type(definition) ~= "table" then
		return nil
	end

	return table.clone(definition)
end

local function sanitizeLeaderboardId(leaderboardId)
	if type(leaderboardId) ~= "string" or leaderboardId == "" then
		return nil
	end

	return leaderboardId
end

local function toFiniteNumber(value)
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
		return nil
	end

	return numberValue
end

local function normalizeWholeNumber(value)
	local numberValue = toFiniteNumber(value)
	if numberValue == nil then
		return 0
	end

	return math.max(0, math.floor(numberValue))
end

function LeaderboardDefinitions.NormalizeTopCount(value, fallback, maxCount)
	local safeMaxCount = normalizeWholeNumber(maxCount)
	if safeMaxCount <= 0 or safeMaxCount > MAX_TOP_COUNT then
		safeMaxCount = MAX_TOP_COUNT
	end

	local safeValue = normalizeWholeNumber(value)
	if safeValue <= 0 then
		safeValue = normalizeWholeNumber(fallback)
	end
	if safeValue <= 0 then
		safeValue = MIN_TOP_COUNT
	end

	return math.min(math.max(safeValue, MIN_TOP_COUNT), safeMaxCount)
end

function LeaderboardDefinitions.GetDefinition(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	if safeLeaderboardId == nil then
		return nil
	end

	return copyDefinition(DEFINITIONS_BY_ID[safeLeaderboardId])
end

function LeaderboardDefinitions.IsRegistered(leaderboardId)
	local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
	return safeLeaderboardId ~= nil and DEFINITIONS_BY_ID[safeLeaderboardId] ~= nil
end

function LeaderboardDefinitions.GetOrderedDefinitions()
	local result = {}

	for _, leaderboardId in ipairs(ORDER) do
		local definition = DEFINITIONS_BY_ID[leaderboardId]
		if definition ~= nil then
			result[#result + 1] = copyDefinition(definition)
		end
	end

	return result
end

function LeaderboardDefinitions.GetAllDefinitions()
	local result = {}

	for leaderboardId, definition in pairs(DEFINITIONS_BY_ID) do
		result[leaderboardId] = copyDefinition(definition)
	end

	return result
end

function LeaderboardDefinitions.GetRegisteredIds()
	local result = {}

	for _, leaderboardId in ipairs(ORDER) do
		if DEFINITIONS_BY_ID[leaderboardId] ~= nil then
			result[#result + 1] = leaderboardId
		end
	end

	return result
end

function LeaderboardDefinitions.ValidateDefinition(definition)
	if type(definition) ~= "table" then
		return false, "InvalidDefinition"
	end

	if type(definition.Id) ~= "string" or definition.Id == "" then
		return false, "MissingId"
	end

	if type(definition.DisplayName) ~= "string" or definition.DisplayName == "" then
		return false, "MissingDisplayName"
	end

	if type(definition.MetaKey) ~= "string" or definition.MetaKey == "" then
		return false, "MissingMetaKey"
	end

	if type(definition.DataStoreName) ~= "string" or definition.DataStoreName == "" then
		return false, "MissingDataStoreName"
	end

	if type(definition.SortAscending) ~= "boolean" then
		return false, "InvalidSortAscending"
	end

	if type(definition.TopCount) ~= "number"
		or toFiniteNumber(definition.TopCount) == nil
		or definition.TopCount < MIN_TOP_COUNT
		or definition.TopCount > MAX_TOP_COUNT
		or definition.TopCount ~= math.floor(definition.TopCount)
	then
		return false, "InvalidTopCount"
	end

	if type(definition.RemoveZeroValues) ~= "boolean" then
		return false, "InvalidRemoveZeroValues"
	end

	return true, nil
end

function LeaderboardDefinitions.ValidateAll()
	local seenById = {}

	for _, leaderboardId in ipairs(ORDER) do
		local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
		if safeLeaderboardId == nil then
			return false, "OrderContainsInvalidId"
		end

		if seenById[safeLeaderboardId] then
			return false, safeLeaderboardId .. ":DuplicateOrderId"
		end
		seenById[safeLeaderboardId] = true

		local definition = DEFINITIONS_BY_ID[safeLeaderboardId]
		if type(definition) ~= "table" then
			return false, safeLeaderboardId .. ":MissingDefinition"
		end

		if definition.Id ~= safeLeaderboardId then
			return false, safeLeaderboardId .. ":DefinitionIdMismatch"
		end

		local success, reason = LeaderboardDefinitions.ValidateDefinition(definition)
		if not success then
			return false, safeLeaderboardId .. ":" .. tostring(reason)
		end
	end

	for leaderboardId, definition in pairs(DEFINITIONS_BY_ID) do
		local safeLeaderboardId = sanitizeLeaderboardId(leaderboardId)
		if safeLeaderboardId == nil then
			return false, "DefinitionsContainInvalidId"
		end

		if not seenById[safeLeaderboardId] then
			return false, safeLeaderboardId .. ":MissingFromOrder"
		end

		if type(definition) ~= "table" or definition.Id ~= safeLeaderboardId then
			return false, safeLeaderboardId .. ":DefinitionIdMismatch"
		end
	end

	return true, nil
end

return LeaderboardDefinitions
