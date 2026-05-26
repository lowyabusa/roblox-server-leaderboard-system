# Troubleshooting

Use this checklist when boards do not show the values you expect.

## Boards Do Not Update

- Confirm `LeaderboardSystem` is copied into `ServerScriptService`.
- Confirm `Bootstrap.server.lua` is a server `Script`, not a `ModuleScript`.
- Confirm the board part is under `Workspace.Leaderboards`.
- Confirm the board part has a `LeaderboardId` attribute that matches a
  configured definition id.
- Confirm `LeaderboardPeriod`, if set, is `AllTime`, `Daily`, or `Weekly`.
- Confirm a server `Script` is calling `LeaderboardService.SetPlayerValue` or
  `LeaderboardService.SetPlayerPeriodValue`.
- Wait for the display refresh interval or call `RefreshDisplayPart` from server
  code while debugging.

## API Services Disabled

DataStore-backed tests in Studio require:

```text
Game Settings > Security > Enable Studio Access to API Services
```

If API Services are disabled, display boards may show a fallback message or only
recent in-memory values from the current server session.

## Wrong LeaderboardId Attribute

`LeaderboardId` must exactly match a configured definition `Id`, such as
`Score`, `Wins`, or `Level`.

Check spelling and capitalization. `score` and `Score` are different ids.

## Wrong LeaderboardPeriod Attribute

`LeaderboardPeriod` is optional. Missing or blank means `AllTime`.

If it is set, it must be one of:

```text
AllTime
Daily
Weekly
```

The selected period must also be listed in that definition's `Periods` table.

## DataStore Names Not Changed

The included `GenericLeaderboard_*` names are samples. Before using this in a
real game, change each `DataStoreName` in `LeaderboardDefinitions.lua` to a name
owned by your game.

After changing definitions, rerun `commands/CreateWorkspaceLeaderboards.lua` in
the Command Bar so generated board attributes are updated.

Daily and weekly DataStores append UTC period suffixes to `DataStoreName`. The
all-time store keeps the exact configured `DataStoreName`.

## Daily Or Weekly Board Shows Lifetime Values

The library rotates the store used by daily and weekly boards. It does not know
which stat in your game is daily or weekly.

Publish separate server-owned values:

```lua
LeaderboardService.SetPlayerValue(player, "Wins", allTimeWins)
LeaderboardService.SetPlayerPeriodValue(player, "Wins", "Daily", dailyWins)
LeaderboardService.SetPlayerPeriodValue(player, "Wins", "Weekly", weeklyWins)
```

If you pass `allTimeWins` to the daily API, today's daily store will rank
lifetime wins.

## UTC Reset Timing

Daily boards switch to a new store at `00:00 UTC`. Weekly boards switch Monday
at `00:00 UTC`.

If your game wants a local-time reset, convert your own gameplay stat on the
server before publishing. This library uses UTC so every Roblox server resolves
the same store name globally.

## Values Are Zero Or Removed

Definitions use `RemoveZeroValues = true` by default. A published value of `0`
removes that user from the `OrderedDataStore` for that leaderboard.

If zero should appear as a real ranked value for your game, set
`RemoveZeroValues = false` for that definition.

## Studio Test Behavior

Studio DataStore behavior depends on API Services, the place configuration, and
Roblox request budgets. Failed writes retry with backoff, and reads may use a
cached or in-memory fallback.

For a simple test, run a server `Script` like:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local LeaderboardService = require(
	ServerScriptService:WaitForChild("LeaderboardSystem"):WaitForChild("LeaderboardService")
)

Players.PlayerAdded:Connect(function(player)
	local success, reason = LeaderboardService.SetPlayerValue(player, "Score", 100)
	if not success then
		warn("Leaderboard test write failed:", reason)
	end
end)
```

## Display Board Missing From Workspace.Leaderboards

Run `commands/CreateWorkspaceLeaderboards.lua` from the Roblox Studio Command Bar
after copying `LeaderboardSystem` into `ServerScriptService`.

The script creates:

```text
Workspace
  Leaderboards
    Leaderboard_Score
    Leaderboard_Score_Daily
    Leaderboard_Score_Weekly
    Leaderboard_Wins
    Leaderboard_Wins_Daily
    Leaderboard_Wins_Weekly
    Leaderboard_Level
    Leaderboard_Level_Daily
    Leaderboard_Level_Weekly
```

It is safe to run again. Existing boards are updated instead of duplicated for
the same `LeaderboardId` and `LeaderboardPeriod`.
