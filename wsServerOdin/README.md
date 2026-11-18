# wsServerOdin

A pure-Odin WebSocket server package being ported from
[Theldus/wsServer](https://github.com/Theldus/wsServer). It is kept separate
from the existing C-backed `odin-wsserver` package until the port is complete
and can replace it safely.

## Current port

The package currently provides:

- RFC 6455 HTTP upgrade validation and accept-key generation.
- A TCP listener with per-connection worker threads and dynamically tracked
  connections.
- A runtime-configurable connection limit; the default is 128 clients.
- Client frame decoding, including masking, extended lengths, fragmentation,
  and UTF-8 checks.
- Server text/binary frame sends and broadcasts, plus ping/pong and close
  control-frame handling.
- A stop path that wakes the blocking accept loop, closes live sockets, and
  joins its worker threads.

The code uses Odin's standard networking, synchronization, and threading APIs;
there are no foreign imports or C build steps. This first implementation uses
one OS thread per connected client, so its practical capacity depends on thread
stack and operating-system resources as well as `maxConnections`.

## API sketch

```odin
server: wsserver.Server
wsserver.ServerInit(
    &server,
    {address = net.IP4_Loopback, port = 6970},
    wsserver.Events{onMessage = HandleMessage},
    maxConnections = 128,
)
defer wsserver.ServerDeinit(&server)

wsserver.ServerRun(&server) // blocks until ServerStop is called
```

Callbacks receive a stable client ID; `ServerSendFrame` and
`ServerBroadcastFrame` can send messages to active IDs. Callback payload bytes
are only valid for the duration of the callback.

## Not ported yet

The implementation is an early replacement candidate, not yet wired into RIFT's
production server. Periodic ping deadlines/timeout handling, a non-thread-per-
connection event loop, richer socket error reporting, and broader protocol/load
tests remain. The current code caps connections at runtime, but it does not make
host resources unlimited; choose a cap appropriate for the deployment and test
with expected traffic.

## Check and test

From this directory, after loading the Odin environment:

```powershell
odin check . -no-entry-point
odin test .
```

The port is based on the GPL-3.0-licensed `wsServer` project. See `LICENSE`.
