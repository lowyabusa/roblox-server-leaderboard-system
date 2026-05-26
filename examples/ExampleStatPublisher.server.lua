-- Server Script example. Put this Script in ServerScriptService and replace the
-- score increment with your own trusted server gameplay logic.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardService = require(
	ServerScriptService:WaitForChild("LeaderboardSystem"):WaitForChild("LeaderboardService")
)

local LEADERBOARD_ID = "Score"
local AWARD_INTERVAL_SECONDS = 30
local SCORE_PER_INTERVAL = 10

-- This table is server-owned. Do not publish client-submitted leaderboard values.
local sessionScoresByUserId = {}

local function publishScore(player)
	local score = sessionScoresByUserId[player.UserId] or 0
	local success, reason = LeaderboardService.SetPlayerValue(player, LEADERBOARD_ID, score)
	if not success then
		warn("Failed to publish leaderboard score:", player.UserId, reason)
	end
end

Players.PlayerAdded:Connect(function(player)
	sessionScoresByUserId[player.UserId] = 0

	task.spawn(function()
		while player.Parent ~= nil do
			task.wait(AWARD_INTERVAL_SECONDS)

			if player.Parent ~= nil then
				sessionScoresByUserId[player.UserId] += SCORE_PER_INTERVAL
				publishScore(player)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	publishScore(player)
	sessionScoresByUserId[player.UserId] = nil
end)
