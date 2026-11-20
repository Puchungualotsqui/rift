# RIFT server

The server provides an HTTP and SQLite authentication foundation plus an
in-memory WebSocket lobby and authoritative match lifecycle backed by
`logicEngine`. Guest sessions, profile lookup, logout, matchmaking, private
matches, ready checks, game actions, and match-result persistence are supported.
Steam verification and account linking are not wired in yet.

## Run

Run these from this directory:

```powershell
.\check.ps1
.\build.ps1
.\run.ps1
```

The scripts load `C:\BuildTools\devcmd.ps1` and check/build the server. Its
WebSocket transport is pure Odin and requires no C, MinGW, CMake, or WSL setup.
RIFT configures `MAX_WS_CONNECTIONS` to `0`, so there is no application-level
WebSocket connection cap. The operating system, available memory, and current
one-thread-per-client transport still impose practical limits; this is not a
safe high-thousands connection target without an event-driven I/O model and load
testing.

The process listens on HTTP at `127.0.0.1:6969` and WebSocket at
`127.0.0.1:6970`, and creates `rift.sqlite` in the working directory. The
WebSocket listener uses the pure-Odin `wsServer` package on a separate port.
Put both listeners behind a TLS-terminating reverse proxy before exposing them
to clients; neither listener provides TLS.

## Endpoints

- `GET /health` — liveness response.
- `POST /auth/guest` — create a guest identity and 24-hour web session.
- `GET /me` — return the authenticated player's profile and basic stats.
- `POST /auth/logout` — revoke the authenticated session.

Authenticated HTTP endpoints require `Authorization: Bearer <session_token>`.
Session tokens are 256-bit values from the operating system cryptographic
random source. Database writes use prepared statements and transactions. The
SQLite connection and shared network state are mutex-protected. WebSocket
handling currently holds the shared network lock during database work and
socket writes, so a slow peer can delay unrelated clients; keep the connection
cap modest until I/O is decoupled and the server is load-tested.

## WebSocket

Connect to `/` on port `6970` over `ws://` locally or `wss://` behind the
reverse proxy. The first JSON message must authenticate the connection:

```json
{"op":"auth","seq":0,"data":{"token":"<session_token>"}}
```

Every client message uses `{ "op", "seq", "data" }`; `seq` must increase
for each connection. The server validates the session on every message. Client
messages are JSON text frames only, limited to 16 KiB. Connections that do not
authenticate within 10 seconds are closed; messages from an unauthenticated or
expired session are rejected.

Supported client operations:

- `lobby.join`, `lobby.leave` — enter or leave the public two-player queue.
  Two queued players immediately start a match.
- `match.create` with `data.max_players` (2–4), `match.join` with
  `data.match_id`, and `match.ready` with `data.ready` — create and join a
  private match; all seats must be ready before the game starts.
- `game.action` — submit a logic-engine action, including the current `round`
  and the expected `ap_spent`. Supported action names are `move`, `move_via`,
  `harvest`, `build_unit`, `build_structure`, `proliferate`, `reinvest`,
  `rewire_relay`, `rewire_terrain`, `destroy_relay`, `protocol`,
  `protocol_begin`, `protocol_finish`, `strike`, and `hit_and_run`. Payload
  fields for each action are validated by the engine.
- `game.end_turn`, `game.forfeit`, and match-only `chat` (`data.text`, up to
  500 bytes).

The server emits `auth.ok`, lobby/match updates, `match.start`, `match.state`,
per-player `game.hidden`, action acknowledgements/errors, combat reveals,
observations, chat, and `match.end`. Public match state excludes hands and
secret directives. The server generates the match seed and faction/setup
assignment, delegates action validation and mutation to `logicEngine`, and
persists participant scores and player stats when the match finishes. Match
and lobby state are currently in memory and are lost on process restart.

## Tests

```powershell
. C:\BuildTools\devcmd.ps1
odin test .
```
