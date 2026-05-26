# Security Model

This repository keeps leaderboard publishing server-authoritative. It does not
try to solve every gameplay security problem; it provides a small safe pattern
for global leaderboard writes.

## Trusted Server Publishing

Only server code should call:

```lua
LeaderboardService.SetPlayerValue(player, leaderboardId, value)
```

The server should calculate the final value from trusted gameplay state. Examples
include server-owned score, win count, level, clear time, or other values the
server can verify.

## Why Clients Must Not Publish Final Values

Roblox clients can be modified by exploiters. A client-sent number should not be
treated as a final leaderboard score.

Clients may request actions, such as starting a match, claiming a reward, or
finishing a round. The server should validate the action, update server-owned
state, and then publish the final value.

Do not add a `RemoteEvent` or `RemoteFunction` that forwards a client-supplied
leaderboard value into `SetPlayerValue`.

## What This Protects Against

- Accidental client authority over global leaderboard values.
- Direct use of client-submitted final scores in `OrderedDataStore`.
- Display boards becoming a write path.
- Invalid submitted values such as unknown leaderboard ids, invalid users,
  non-number values, `NaN`, and infinite values.

## What This Does Not Protect Against

- Bugs in your server gameplay logic.
- Server scripts that publish the wrong value.
- Exploits in unrelated remotes in your game.
- Economy, inventory, matchmaking, or anti-cheat problems.
- DataStore outages, throttling, or Roblox platform behavior.

## Safe Integration Pattern

```text
Client request
  -> server validates gameplay action
  -> server updates trusted stat
  -> server calls LeaderboardService.SetPlayerValue(...)
```

The important rule is that the client request is not the leaderboard value. The
server-owned result is the value.
