-- Server bootstrap: starts the leaderboard system when this Script runs in ServerScriptService.
local LeaderboardDisplayService = require(script.Parent:WaitForChild("LeaderboardDisplayService"))

local success, err = pcall(function()
	LeaderboardDisplayService.Init()
end)

if not success then
	warn("LeaderboardSystem bootstrap failed:", err)
end
