-- Example server-only publisher. Put this Script in ServerScriptService, then replace
-- the session score logic with your own trusted game logic.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardService = require(
	ServerScriptService:WaitForChild("LeaderboardSystem"):WaitForChild("LeaderboardService")
)

local LEADERBOARD_ID = "Score"
local AWARD_INTERVAL_SECONDS = 30
local SCORE_PER_INTERVAL = 10

-- sessionScores is server-owned state. Clients never send leaderboard values directly.
local sessionScoresByUserId = {}

-- publishScore writes the current trusted server value to the configured leaderboard.
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

game:BindToClose(function()
	LeaderboardService.FlushPendingWrites(20)
end)
