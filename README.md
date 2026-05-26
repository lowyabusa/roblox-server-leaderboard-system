# Server-Authoritative Plug-and-Play Leaderboards

A small Roblox leaderboard system designed for public, copy-and-paste use.

The system is server-authoritative: your server code publishes trusted values with
`LeaderboardService.SetPlayerValue`, and world display boards read those values from
OrderedDataStores.

## What You Copy

Copy this folder into your game:

```text
src/ServerScriptService/LeaderboardSystem
```

It should end up here in Roblox Studio:

```text
ServerScriptService
  LeaderboardSystem
    Bootstrap.server.lua
    LeaderboardDefinitions.lua
    LeaderboardService.lua
    LeaderboardDisplayService.lua
```

## Quick Start

1. Copy `src/ServerScriptService/LeaderboardSystem` into `ServerScriptService`.
2. Edit `LeaderboardDefinitions.lua` for your game before publishing.
3. Open `commands/CreateWorkspaceLeaderboards.lua`.
4. Paste that script into the Roblox Studio Command Bar and run it.
5. Move the generated parts in `Workspace.Leaderboards` wherever you want.
6. Publish trusted server values with `LeaderboardService.SetPlayerValue`.

If you are installing manually in Studio, create a `Folder` named
`LeaderboardSystem` under `ServerScriptService`. `Bootstrap.server.lua` should be
a server `Script`; the other files in that folder should be `ModuleScript`
instances with matching names.

For DataStore-backed results in live servers or Studio play tests, enable:

```text
Game Settings > Security > Enable Studio Access to API Services
```

## Configure Leaderboards

`LeaderboardDefinitions.lua` is the source of truth.

Each definition has:

| Field | Purpose |
| --- | --- |
| `Id` | Stable id used by code and the `LeaderboardId` Workspace attribute. |
| `DisplayName` | Default board title. |
| `MetaKey` | Optional key for the `UpdatePlayerFromState` adapter helpers. |
| `DataStoreName` | OrderedDataStore name. Change the prefix for your own game. |
| `SortAscending` | `false` means highest value wins. `true` means lowest value wins. |
| `TopCount` | Default number of rows. |
| `RemoveZeroValues` | Removes zero values from the OrderedDataStore when true. |

Also update `ORDER` so it contains exactly the ids you want, in the order you want
the Command Bar script to create boards.

## Create World Boards

The Command Bar script creates or updates:

```text
Workspace
  Leaderboards
    Leaderboard_Score
    Leaderboard_Wins
    Leaderboard_Level
```

The script is idempotent. Running it again updates attributes and creates missing
boards, but it does not duplicate existing boards.

## Workspace Attributes

Display parts live under `Workspace.Leaderboards`.

Required attribute:

| Attribute | Type | Purpose |
| --- | --- | --- |
| `LeaderboardId` | string | Must match a definition `Id`. |

Optional attributes:

| Attribute | Type | Default |
| --- | --- | --- |
| `LeaderboardTitle` | string | Definition `DisplayName`. |
| `LeaderboardTopCount` | number | Definition `TopCount`, clamped for display. |
| `LeaderboardRefreshSeconds` | number | `120`. |
| `LeaderboardFace` | string | `Front`. Supports `Front`, `Back`, `Left`, `Right`, `Top`, `Bottom`. |

## Publish Values From Server Code

Use `SetPlayerValue` from a server Script only:

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

Do not let clients send leaderboard values directly. Clients can request gameplay
actions, but the server must decide the final value.

See `examples/ExampleStatPublisher.server.lua` for a minimal server-owned score
publisher.

## Optional State Adapter

If your game already stores stats in `state.Meta`, you can use:

```lua
LeaderboardService.UpdatePlayerFromState(player, state, "Score")
LeaderboardService.UpdatePlayerFromStateAll(player, state)
```

For new integrations, prefer `SetPlayerValue` because it is simpler and more explicit.

## Runtime Behavior

- `Bootstrap.server.lua` initializes the system automatically.
- `LeaderboardDisplayService` scans `Workspace.Leaderboards`.
- Display parts added later are registered when they have a `LeaderboardId` attribute.
- DataStore reads are cached briefly to avoid unnecessary request pressure.
- Failed writes are retried with backoff.
- If DataStore reads fail, the board can temporarily render recent in-memory values.

## Before Publishing

1. Rename sample definitions to your real leaderboard ids.
2. Change `DataStoreName` values to names owned by your game.
3. Run the Command Bar script after editing definitions.
4. Confirm API Services are enabled.
5. Test a server-side `SetPlayerValue` call in Studio.

## License

MIT. See `LICENSE`.
