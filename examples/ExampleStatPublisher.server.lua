-- Server Script example. Put this Script in ServerScriptService and replace the
-- simulated win logic with your own trusted server gameplay logic.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardService = require(
	ServerScriptService:WaitForChild("LeaderboardSystem"):WaitForChild("LeaderboardService")
)

local LEADERBOARD_ID = "Wins"
local AWARD_INTERVAL_SECONDS = 30
local SECONDS_PER_DAY = 24 * 60 * 60

-- These tables are server-owned. Do not publish client-submitted leaderboard values.
local allTimeWinsByUserId = {}
local dailyWinsByUserId = {}
local weeklyWinsByUserId = {}

local function getUtcDateKey(timestamp)
	local utcDate = os.date("!*t", timestamp or os.time())
	return string.format("%04d-%02d-%02d", utcDate.year, utcDate.month, utcDate.day)
end

local function getUtcWeekKey(timestamp)
	local safeTimestamp = timestamp or os.time()
	local utcDate = os.date("!*t", safeTimestamp)
	local daysSinceMonday = (utcDate.wday + 5) % 7
	return getUtcDateKey(safeTimestamp - (daysSinceMonday * SECONDS_PER_DAY))
end

local activeDailyKey = getUtcDateKey()
local activeWeeklyKey = getUtcWeekKey()

local function resetPeriodCountersIfNeeded()
	local currentDailyKey = getUtcDateKey()
	if currentDailyKey ~= activeDailyKey then
		activeDailyKey = currentDailyKey
		dailyWinsByUserId = {}
	end

	local currentWeeklyKey = getUtcWeekKey()
	if currentWeeklyKey ~= activeWeeklyKey then
		activeWeeklyKey = currentWeeklyKey
		weeklyWinsByUserId = {}
	end
end

local function publishWins(player)
	resetPeriodCountersIfNeeded()

	local userId = player.UserId

	local success, reason = LeaderboardService.SetPlayerValue(player, LEADERBOARD_ID, allTimeWinsByUserId[userId] or 0)
	if not success then
		warn("Failed to publish all-time wins:", userId, reason)
	end

	success, reason = LeaderboardService.SetPlayerPeriodValue(player, LEADERBOARD_ID, "Daily", dailyWinsByUserId[userId] or 0)
	if not success then
		warn("Failed to publish daily wins:", userId, reason)
	end

	success, reason = LeaderboardService.SetPlayerPeriodValue(player, LEADERBOARD_ID, "Weekly", weeklyWinsByUserId[userId] or 0)
	if not success then
		warn("Failed to publish weekly wins:", userId, reason)
	end
end

local function awardServerWin(player)
	resetPeriodCountersIfNeeded()

	local userId = player.UserId
	allTimeWinsByUserId[userId] = (allTimeWinsByUserId[userId] or 0) + 1
	dailyWinsByUserId[userId] = (dailyWinsByUserId[userId] or 0) + 1
	weeklyWinsByUserId[userId] = (weeklyWinsByUserId[userId] or 0) + 1

	publishWins(player)
end

Players.PlayerAdded:Connect(function(player)
	local userId = player.UserId
	allTimeWinsByUserId[userId] = 0
	dailyWinsByUserId[userId] = 0
	weeklyWinsByUserId[userId] = 0

	task.spawn(function()
		while player.Parent ~= nil do
			task.wait(AWARD_INTERVAL_SECONDS)

			if player.Parent ~= nil then
				awardServerWin(player)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	publishWins(player)

	local userId = player.UserId
	allTimeWinsByUserId[userId] = nil
	dailyWinsByUserId[userId] = nil
	weeklyWinsByUserId[userId] = nil
end)
