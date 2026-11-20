# wsServerOdin

A pure-Odin WebSocket server package ported from
[Theldus/wsServer](https://github.com/Theldus/wsServer). RIFT's server uses this
package directly; it has no C-backed transport dependency.

## Features

The package currently provides:

- RFC 6455 HTTP upgrade validation and accept-key generation.
- A TCP listener with per-connection worker threads and dynamically tracked
  connections.
- A dynamically growing, reusable pool of connection records and a
  runtime-configurable active connection limit. The default is 128 clients;
  configure `maxConnections = 0` to disable the application-level limit. The
  default message limit is 64 KiB per connection.
- A bounded HTTP handshake deadline; incomplete handshakes release their slot.
- Client frame decoding, including masking, extended lengths, fragmentation,
  and UTF-8 checks.
- Server text/binary frame sends and broadcasts, plus ping/pong and close
  control-frame handling. `ServerPing` and `ServerPingAll` send caller-driven
  keepalives and close clients that exceed the configured missed-pong threshold.
- Client metadata APIs for peer endpoints, connection state, and server/connection
  context pointers.
- `ServerCloseClient` sends a normal WebSocket close frame and waits for the peer
  response up to the configured close timeout.
- Optional TCP send timeout and complete-write handling for frames and handshakes.
- A stop path that wakes the blocking accept loop, closes live sockets, and
  joins its worker threads.

The code uses Odin's standard networking, synchronization, and threading APIs;
there are no foreign imports or C build steps. Connection records are allocated
only as concurrency grows, returned to the pool on disconnect, and freed when
the server is deinitialized. Setting `maxConnections` to zero disables only the
package's active-connection cap; available memory, OS socket limits, and thread
resources remain practical limits. This implementation still uses one OS
thread per connected client, so disabling the cap does not make very high
connection counts safe.

## API sketch

```odin
server: wsserver.Server
wsserver.ServerInit(
    &server,
    {address = net.IP4_Loopback, port = 6970},
    wsserver.Events{onMessage = HandleMessage},
    maxConnections = 128, // use 0 to disable the package cap
    maxMessageSize = 64 * 1024,
    handshakeTimeout = 5 * time.Second,
    closeTimeout = 500 * time.Millisecond,
    sendTimeout = 5 * time.Second,
    userContext = rawptr(&application),
)
defer wsserver.ServerDeinit(&server)

wsserver.ServerRun(&server) // blocks until ServerStop is called
```

Callbacks receive a stable client ID; `ServerSendFrame` and
`ServerBroadcastFrame` can send messages to active IDs. Use
`ServerGetClientEndpoint`, `ServerGetClientState`, and
`ServerGetConnectionContext` / `ServerSetConnectionContext` to inspect a client.
`ServerGetContext` returns the application pointer supplied to `ServerInit`.
Keep context pointees alive for as long as the server or connection can access
them. Client lookup APIs return `found = false` after the connection is removed.

`ServerCloseClient` performs a normal close handshake; `closeTimeout` defaults
to 500 ms. Incomplete HTTP handshakes are closed after `handshakeTimeout`
(default 5 s). The default `sendTimeout` is 5 s; set it to zero to disable the
socket send timeout. `ServerPing` and `ServerPingAll` send four-byte big-endian
ping IDs and close clients that
exceed the missed-pong threshold. Ping scheduling is intentionally left to the
caller; there is no periodic timer. Callback payload bytes are only valid for the
duration of the callback. `ServerRun` blocks; run it on a caller-created thread
if the application needs a nonblocking start.

## Known limitations

RIFT currently configures a cap of 32 clients. The package supports setting
`maxConnections` to zero to disable that admission cap, but each connected client
still uses an OS thread, so this is not a high-scale event loop and an unlimited
setting is not a safe way to target thousands of clients. Ping scheduling is
caller-driven. Autobahn/fuzz coverage and broader concurrency/load testing are
still needed before claiming production readiness.

## Check and test

From this directory, after loading the Odin environment:

```powershell
odin check . -no-entry-point
odin test .
```

The port is based on the GPL-3.0-licensed `wsServer` project. See `LICENSE`.
