# RIFT server

The initial server package provides the HTTP and SQLite authentication foundation.
It currently supports guest sessions, profile lookup, logout, and health checks.
The authoritative match engine, Steam verification, and WebSocket lobby/game
protocol are not wired in yet.

## Run

Run Odin commands from this directory. On Windows, initialize the supplied
Build Tools environment first:

```powershell
. C:\BuildTools\devcmd.ps1
odin run .
```

The process listens on `127.0.0.1:6969` and creates `rift.sqlite` in the
working directory. Put it behind a TLS-terminating reverse proxy before
exposing it to clients; the HTTP listener itself does not provide TLS.

## Endpoints

- `GET /health` — liveness response.
- `POST /auth/guest` — create a guest identity and 24-hour web session.
- `GET /me` — return the authenticated player's profile and basic stats.
- `POST /auth/logout` — revoke the authenticated session.

Authenticated endpoints require `Authorization: Bearer <session_token>`.
Session tokens are 256-bit values from the operating system cryptographic
random source. Database writes use prepared statements and guest account
creation is transactional. The SQLite connection is mutex-protected because
the HTTP package services requests from multiple threads.

## Tests

```powershell
. C:\BuildTools\devcmd.ps1
odin test .
```
