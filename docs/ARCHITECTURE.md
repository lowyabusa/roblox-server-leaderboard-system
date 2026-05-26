# Architecture

This system is a small server-authoritative Roblox leaderboard sample. It keeps
leaderboard publishing on the server, stores rankings in `OrderedDataStore`, and
renders world boards from `Workspace.Leaderboards`.

## System Ownership Boundaries

| Area | Owner | Notes |
| --- | --- | --- |
| Gameplay stat calculation | Your server gameplay scripts | The game decides final values. |
| Publishing API | `LeaderboardService` | Accepts trusted server values through `SetPlayerValue`. |
| Definition registry | `LeaderboardDefinitions` | Stores ids, titles, store names, row counts, and order. |
| DataStore persistence | `LeaderboardService` | Uses `OrderedDataStore` with debounce, retry, and cache behavior. |
| World display rendering | `LeaderboardDisplayService` | Builds generated `SurfaceGui` content for board parts. |
| Board creation | Command Bar script | Creates or updates parts under `Workspace.Leaderboards`. |

## Data Flow

```text
Server gameplay code
  -> LeaderboardService.SetPlayerValue(player, leaderboardId, value)
  -> write queue and in-memory fallback cache
  -> OrderedDataStore
  -> LeaderboardDisplayService
  -> Workspace.Leaderboards display boards
```

The trusted publishing path starts in server code. Clients may request gameplay
actions, but the server calculates the final value and calls
`LeaderboardService.SetPlayerValue`.

Display boards do not accept values. They read snapshots through
`LeaderboardService.BuildSnapshot` and render the returned rows.

## Module Responsibilities

| Module | Responsibility |
| --- | --- |
| `Bootstrap.server.lua` | Requires `LeaderboardDisplayService` and starts the system when the server script runs. |
| `LeaderboardDefinitions.lua` | Defines the leaderboard registry, display order, validation, and helper accessors. |
| `LeaderboardService.lua` | Validates server-submitted values, queues writes, handles retries, reads rankings, caches snapshots, and flushes pending writes on shutdown. |
| `LeaderboardDisplayService.lua` | Watches `Workspace.Leaderboards`, registers parts with `LeaderboardId`, refreshes snapshots, and generates `SurfaceGui` UI. |
| `CreateWorkspaceLeaderboards.lua` | Command Bar setup script that creates or updates display boards from definitions. |
| `ExampleStatPublisher.server.lua` | Minimal example of server-owned stat state publishing through `SetPlayerValue`. |

## Trust Boundary

- Server code is trusted to calculate and publish final leaderboard values.
- Client code is untrusted and must not publish final leaderboard values.
- Display boards are read-only presentation.
- `LeaderboardId` attributes select which registered leaderboard a board displays;
  they do not create a trusted write path.

## Failure Behavior

- Writes are debounced per leaderboard and user id.
- Failed writes stay queued and retry with exponential backoff.
- DataStore request budget is checked before reads and writes.
- Recent successful DataStore reads are cached briefly.
- If a fresh read fails, the service can use a stale cached snapshot or recent
  in-memory values submitted during the current server session.
- Empty or unavailable boards render a temporary fallback message instead of
  crashing the refresh loop.
- On shutdown, the service attempts a bounded flush of pending writes.
