# Server-Authoritative Roblox Leaderboards

A small copy-and-paste leaderboard system for Roblox games.

It uses trusted server code to publish all-time, daily, and weekly leaderboard
values, `OrderedDataStore` for global ranking, and world display boards under
`Workspace.Leaderboards`.

## What This Is

This repository is a compact Roblox leaderboard sample you can copy into
`ServerScriptService`. It is intentionally not a framework. The public integration
point is:

```lua
LeaderboardService.SetPlayerValue(player, leaderboardId, value)
```

Daily and weekly values use an explicit period-aware API:

```lua
LeaderboardService.SetPlayerPeriodValue(player, leaderboardId, period, value)
```

Optional adapter helpers are included for games that already store stats in
`state.Meta`:

```lua
LeaderboardService.UpdatePlayerFromState(player, state, leaderboardId)
LeaderboardService.UpdatePlayerFromStateAll(player, state)
```

## What Problem It Solves

Roblox clients are not trusted for final leaderboard values. This system gives
server scripts one clear publishing path while display boards render ranked data
from `OrderedDataStore`.

Clients may request gameplay actions, such as finishing a race or claiming a
reward, but server code must calculate and publish the final leaderboard value.
Do not let clients send final score, wins, level, time, or currency values to this
service.

## Architecture Overview

```text
Server gameplay code
  -> LeaderboardService.SetPlayerValue(...) or SetPlayerPeriodValue(...)
  -> period scope (AllTime, Daily, Weekly)
  -> debounced write queue and in-memory fallback cache
  -> OrderedDataStore
  -> LeaderboardDisplayService
  -> Workspace.Leaderboards display parts
```

Main files:

| File | Responsibility |
| --- | --- |
| `Bootstrap.server.lua` | Starts display discovery when the server script runs. |
| `LeaderboardDefinitions.lua` | Defines leaderboard ids, titles, store names, enabled periods, and display order. |
| `LeaderboardService.lua` | Validates server values, resolves period scopes, queues writes, reads rankings, and caches fallbacks. |
| `LeaderboardDisplayService.lua` | Finds board parts and renders generated `SurfaceGui` content. |
| `commands/CreateWorkspaceLeaderboards.lua` | Command Bar setup script for world boards. |
| `examples/ExampleStatPublisher.server.lua` | Minimal server-only publishing example. |

More detail: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Installation

1. Copy this folder into your Roblox game:

   ```text
   src/ServerScriptService/LeaderboardSystem
   ```

2. In Studio, it should look like this:

   ```text
   ServerScriptService
     LeaderboardSystem
       Bootstrap.server.lua
       LeaderboardDefinitions.lua
       LeaderboardService.lua
       LeaderboardDisplayService.lua
   ```

3. If installing manually in Studio, create a `Folder` named
   `LeaderboardSystem`. `Bootstrap.server.lua` should be a server `Script`; the
   other files should be `ModuleScript` instances with matching names.

4. Edit `LeaderboardDefinitions.lua` for your game.

5. Paste and run `commands/CreateWorkspaceLeaderboards.lua` in the Roblox Studio
   Command Bar.

6. Move the generated parts in `Workspace.Leaderboards` where you want them.

Rojo is optional for repository contributors. Roblox Studio users can install this
by copying files directly.

## Configuration

`LeaderboardDefinitions.lua` is the source of truth.

To add or remove a leaderboard, edit `DEFINITIONS_BY_ID` and keep `ORDER` in the
same file aligned with the ids you want to create and display.

| Field | Purpose |
| --- | --- |
| `Id` | Stable id used by code and the `LeaderboardId` Workspace attribute. |
| `DisplayName` | Default board title. |
| `MetaKey` | Key used by the optional `UpdatePlayerFromState` helpers. |
| `DataStoreName` | `OrderedDataStore` name. The included names are samples. |
| `Periods` | Optional list of enabled periods: `AllTime`, `Daily`, `Weekly`. |
| `SortAscending` | `false` means highest value ranks first. |
| `TopCount` | Default row count for generated boards and reads. |
| `RemoveZeroValues` | Removes zero values from the `OrderedDataStore` when true. |

Before publishing a real game, replace the sample `GenericLeaderboard_*`
`DataStoreName` values with names owned by your game.

## Publishing Trusted Values

Publish from a server `Script` only:

```lua
local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardService = require(
	ServerScriptService:WaitForChild("LeaderboardSystem"):WaitForChild("LeaderboardService")
)

local success, reason = LeaderboardService.SetPlayerValue(player, "Score", 123)
if not success then
	warn("Leaderboard update failed:", reason)
end
```

`SetPlayerValue` accepts a `Player` or positive numeric user id, a registered
leaderboard id, and a finite number. Invalid ids, invalid users, non-number
values, `NaN`, and infinite values return `false` plus a reason string.

Publish daily or weekly values explicitly:

```lua
local allTimeWins = 42
local dailyWins = 3
local weeklyWins = 8

LeaderboardService.SetPlayerValue(player, "Wins", allTimeWins)
LeaderboardService.SetPlayerPeriodValue(player, "Wins", "Daily", dailyWins)
LeaderboardService.SetPlayerPeriodValue(player, "Wins", "Weekly", weeklyWins)
```

The library rotates the DataStore used by daily and weekly boards. Your server
still owns the values. If you publish lifetime wins to a daily board, today's
daily store will rank lifetime wins.

Do not create a `RemoteEvent` that forwards client-submitted values into
`SetPlayerValue` or `SetPlayerPeriodValue`. If a client requests an action,
validate the action on the server and publish the server-owned result.

## Daily and Weekly Boards

Daily and weekly resets are implemented by changing the `OrderedDataStore` name
used for the current UTC period. The system does not delete old DataStore entries.

Store names resolve like this:

```text
AllTime: GenericLeaderboard_Wins
Daily:   GenericLeaderboard_Wins_Daily_2026-05-26
Weekly:  GenericLeaderboard_Wins_Weekly_2026-05-25
```

Daily periods reset at `00:00 UTC`. Weekly periods reset Monday at `00:00 UTC`.
The weekly suffix uses the UTC date of that Monday.

## Workspace Display Boards

Display parts must live under:

```text
Workspace
  Leaderboards
```

Required attribute:

| Attribute | Type | Purpose |
| --- | --- | --- |
| `LeaderboardId` | string | Must match a definition `Id`. |

Optional attributes:

| Attribute | Type | Default |
| --- | --- | --- |
| `LeaderboardTitle` | string | Definition `DisplayName`. |
| `LeaderboardPeriod` | string | `AllTime`; supports `AllTime`, `Daily`, `Weekly`. |
| `LeaderboardTopCount` | number | Definition `TopCount`, clamped for display. |
| `LeaderboardRefreshSeconds` | number | `120`. |
| `LeaderboardFace` | string | `Front`; supports `Front`, `Back`, `Left`, `Right`, `Top`, `Bottom`. |

Run `commands/CreateWorkspaceLeaderboards.lua` again after changing definitions.
The script updates existing boards and creates missing boards without duplicating
boards for the same `LeaderboardId` and `LeaderboardPeriod`.

## DataStore Behavior

- All-time rankings use each definition's `DataStoreName` unchanged.
- Daily and weekly rankings use UTC period suffixes on `DataStoreName`.
- Writes are debounced so repeated updates for the same player do not immediately
  create repeated DataStore writes.
- Failed writes are retried with backoff.
- Reads are cached briefly to control request pressure.
- If a DataStore read fails, display boards can temporarily show cached or recent
  in-memory values.
- On server shutdown, the service attempts a bounded flush of pending writes.

For DataStore-backed results in Studio play tests, enable:

```text
Game Settings > Security > Enable Studio Access to API Services
```

## Security Model

The trust boundary is simple:

- Server gameplay code is trusted to calculate final values.
- Client code is untrusted and must not publish final leaderboard values.
- Display boards are read-only presentation.

More detail: [`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md).

## Limitations

- This is a small sample, not a full leaderboard platform.
- It does not include client UI, admin tools, anti-cheat systems, migrations, or
  analytics.
- It does not validate whether your gameplay rules are fair; it only keeps final
  leaderboard publishing on the server.
- It does not calculate daily or weekly stats for your game. Your server must
  publish the correct period values.
- Studio DataStore behavior depends on API Services being enabled and the place
  being able to use DataStores.

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) for practical checks.

Common first checks:

- Confirm `LeaderboardSystem` is in `ServerScriptService`.
- Confirm `Workspace.Leaderboards` exists.
- Confirm each board has a valid `LeaderboardId` attribute.
- Enable Studio API Services for DataStore-backed tests.
- Publish a value from a server `Script`, not from a client.

## Roadmap

Small improvements that fit the current shape:

- Add focused Luau tests if the repository gains a test runner.
- Add more example definitions for common game stat types.
- Add an optional plain Studio setup checklist screenshot.

Out of scope for this sample: remotes for client-submitted values, a framework
rewrite, external services, or package dependencies.

## License

MIT. See [`LICENSE`](LICENSE).
