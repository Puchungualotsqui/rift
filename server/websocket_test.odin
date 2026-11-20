#+build !js

package server

import ws "../wsServerOdin"
import "core:encoding/json"
import "core:net"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

WS_TEST_MAX_FRAME_SIZE :: 32 * 1024

WsTestOp :: enum {
	Unknown,
	AuthOK,
	Error,
	Close,
	LobbyUpdate,
	MatchStart,
	MatchState,
	GameHidden,
	ActionOK,
}

WsTestEnvelope :: struct {
	op:  string `json:"op"`,
	seq: i64    `json:"seq"`,
}

WsTestClient :: struct {
	socket: net.TCP_Socket,
	reader: ws.SocketReader,
}

WsTestServer :: struct {
	app:                 App,
	serverWorker:        ^thread.Thread,
	authTimeoutWorker:   ^thread.Thread,
}

WsTestStartServer :: proc(t: ^testing.T, testServer: ^WsTestServer, database: ^Database) -> bool {
	testServer.app = App{database = database}
	NetworkInit(&testServer.app.network)
	testServer.app.network.authTimeout = time.Second

	initError := ws.ServerInit(
		&testServer.app.network.websocket,
		{address = net.IP4_Loopback, port = 0},
		ws.Events{onOpen = WsOnOpen, onClose = WsOnClose, onMessage = WsOnMessage},
		maxConnections = MAX_WS_CONNECTIONS,
		maxMessageSize = MAX_WS_MESSAGE_BYTES,
		sendTimeout = time.Second,
		userContext = rawptr(&testServer.app),
	)
	testing.expect_value(t, initError, ws.ServerError.None)
	if initError != .None {
		NetworkDeinit(&testServer.app.network)
		return false
	}

	testServer.serverWorker = thread.create_and_start_with_poly_data(&testServer.app, WsServerThread)
	testing.expect(t, testServer.serverWorker != nil)
	if testServer.serverWorker == nil {
		ws.ServerDeinit(&testServer.app.network.websocket)
		NetworkDeinit(&testServer.app.network)
		return false
	}
	testServer.authTimeoutWorker = thread.create_and_start_with_poly_data(&testServer.app, WsAuthTimeoutThread)
	testing.expect(t, testServer.authTimeoutWorker != nil)
	if testServer.authTimeoutWorker == nil {
		WsTestStopServer(testServer)
		return false
	}
	return true
}

WsTestStopServer :: proc(testServer: ^WsTestServer) {
	if testServer.serverWorker == nil do return
	sync.lock(&testServer.app.network.mutex)
	testServer.app.network.shuttingDown = true
	sync.unlock(&testServer.app.network.mutex)
	ws.ServerStop(&testServer.app.network.websocket)
	thread.join(testServer.serverWorker)
	thread.destroy(testServer.serverWorker)
	testServer.serverWorker = nil
	if testServer.authTimeoutWorker != nil {
		thread.join(testServer.authTimeoutWorker)
		thread.destroy(testServer.authTimeoutWorker)
		testServer.authTimeoutWorker = nil
	}
	ws.ServerDeinit(&testServer.app.network.websocket)
	NetworkDeinit(&testServer.app.network)
}

WsTestWaitForPort :: proc(server: ^ws.Server) -> int {
	for _ in 0..<1000 {
		sync.lock(&server.mutex)
		port := server.endpoint.port
		isRunning := server.isRunning
		sync.unlock(&server.mutex)
		if isRunning && port != 0 do return port
		time.sleep(time.Millisecond)
	}
	return 0
}

WsTestConnect :: proc(t: ^testing.T, port: int) -> (client: WsTestClient, ok: bool) {
	socket, dialError := net.dial_tcp_from_endpoint({net.IP4_Loopback, port})
	testing.expect(t, dialError == nil)
	if dialError != nil do return
	if optionError := net.set_option(socket, .Receive_Timeout, 3 * time.Second); optionError != nil {
		net.close(socket)
		testing.expect(t, false)
		return
	}

	client = WsTestClient{socket = socket, reader = ws.SocketReader{socket = socket}}
	request := "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	if !ws.SocketSendAll(socket, transmute([]byte)request) {
		net.close(socket)
		testing.expect(t, false)
		return {}, false
	}
	response, responseSize, responseOK := ws.SocketReaderReadHandshake(&client.reader)
	testing.expect(t, responseOK)
	if !responseOK {
		net.close(socket)
		return {}, false
	}
	expected := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
	testing.expect_value(t, string(response[:responseSize]), expected)
	return client, true
}

WsTestSendText :: proc(socket: net.TCP_Socket, text: string) -> bool {
	if len(text) > 125 do return false
	frame: [131]byte
	mask := [?]byte{0x12, 0x34, 0x56, 0x78}
	frame[0] = 0x81
	frame[1] = 0x80 | byte(len(text))
	for i in 0..<4 do frame[2 + i] = mask[i]
	for i in 0..<len(text) do frame[6 + i] = text[i] ~ mask[i % 4]
	return ws.SocketSendAll(socket, frame[:6 + len(text)])
}

WsTestSendAuth :: proc(client: ^WsTestClient, token: string) -> bool {
	prefix := `{"op":"auth","seq":0,"data":{"token":"`
	suffix := `"}}`
	message: [128]byte
	position := 0
	for i in 0..<len(prefix) {
		message[position] = prefix[i]
		position += 1
	}
	for i in 0..<len(token) {
		message[position] = token[i]
		position += 1
	}
	for i in 0..<len(suffix) {
		message[position] = suffix[i]
		position += 1
	}
	return WsTestSendText(client.socket, string(message[:position]))
}

WsTestReadOp :: proc(reader: ^ws.SocketReader) -> (op: WsTestOp, seq: i64, ok: bool) {
	prefix: [2]byte
	if !ws.SocketReaderReadExact(reader, prefix[:]) do return .Unknown, 0, false
	if prefix[1] & 0x80 != 0 do return .Unknown, 0, false

	length := u64(prefix[1] & 0x7f)
	if length == 126 {
		extended: [2]byte
		if !ws.SocketReaderReadExact(reader, extended[:]) do return .Unknown, 0, false
		length = u64(extended[0]) << 8 | u64(extended[1])
	} else if length == 127 {
		extended: [8]byte
		if !ws.SocketReaderReadExact(reader, extended[:]) do return .Unknown, 0, false
		length = 0
		for i in 0..<len(extended) do length = (length << 8) | u64(extended[i])
	}
	if length > WS_TEST_MAX_FRAME_SIZE do return .Unknown, 0, false

	payload: [WS_TEST_MAX_FRAME_SIZE]byte
	if !ws.SocketReaderReadExact(reader, payload[:int(length)]) do return .Unknown, 0, false
	if prefix[0] & 0x0f == 0x8 do return .Close, 0, true
	if prefix[0] & 0x0f != 0x1 do return .Unknown, 0, true

	envelope: WsTestEnvelope
	if err := json.unmarshal(payload[:int(length)], &envelope, allocator = context.temp_allocator); err != nil do return .Unknown, 0, false
	switch envelope.op {
	case "auth.ok":
		op = .AuthOK
	case "error":
		op = .Error
	case "lobby.update":
		op = .LobbyUpdate
	case "match.start":
		op = .MatchStart
	case "match.state":
		op = .MatchState
	case "game.hidden":
		op = .GameHidden
	case "game.action_ok":
		op = .ActionOK
	case:
		op = .Unknown
	}
	return op, envelope.seq, true
}

WsTestWaitForOp :: proc(reader: ^ws.SocketReader, expected: WsTestOp) -> bool {
	for _ in 0..<64 {
		op, _, ok := WsTestReadOp(reader)
		if !ok do return false
		if op == expected do return true
		if op == .Close do return false
	}
	return false
}

@(test)
TestWebSocketAuthTimeoutAndAuthoritativeMatchLifecycle :: proc(t: ^testing.T) {
	database: Database
	if !DatabaseInit(&database, ":memory:") {
		testing.expect(t, false)
		return
	}

	testServer: WsTestServer
	if !WsTestStartServer(t, &testServer, &database) {
		DatabaseDeinit(&database)
		return
	}
	defer {
		WsTestStopServer(&testServer)
		DatabaseDeinit(&database)
	}

	port := WsTestWaitForPort(&testServer.app.network.websocket)
	testing.expect(t, port != 0)
	if port == 0 do return

	invalidClient, invalidConnected := WsTestConnect(t, port)
	testing.expect(t, invalidConnected)
	if !invalidConnected do return
	defer net.close(invalidClient.socket)

	invalidToken := "0000000000000000000000000000000000000000000000000000000000000000"
	testing.expect_value(t, len(invalidToken), 64)
	invalidAuthSent := WsTestSendAuth(&invalidClient, invalidToken)
	testing.expect(t, invalidAuthSent)
	if !invalidAuthSent do return

	invalidAuthRejected := WsTestWaitForOp(&invalidClient.reader, .Error)
	testing.expect(t, invalidAuthRejected)
	if !invalidAuthRejected do return

	invalidAuthClosed := WsTestWaitForOp(&invalidClient.reader, .Close)
	testing.expect(t, invalidAuthClosed)
	if !invalidAuthClosed do return


	timeoutClient, timeoutConnected := WsTestConnect(t, port)
	testing.expect(t, timeoutConnected)
	if !timeoutConnected do return
	defer net.close(timeoutClient.socket)

	if !WsTestWaitForOp(&timeoutClient.reader, .Close) {
		testing.expect(t, false)
		return
	}


	first, firstCreated := DatabaseCreateGuestSession(&database)
	second, secondCreated := DatabaseCreateGuestSession(&database)

	testing.expect(t, firstCreated && secondCreated)
	if !firstCreated || !secondCreated do return

	firstClient, firstConnected := WsTestConnect(t, port)

	testing.expect(t, firstConnected)
	if !firstConnected do return
	defer net.close(firstClient.socket)
	secondClient, secondConnected := WsTestConnect(t, port)

	testing.expect(t, secondConnected)
	if !secondConnected do return
	defer net.close(secondClient.socket)


	if !WsTestSendAuth(&firstClient, first.sessionToken) || !WsTestSendAuth(&secondClient, second.sessionToken) ||
		!WsTestWaitForOp(&firstClient.reader, .AuthOK) || !WsTestWaitForOp(&secondClient.reader, .AuthOK) {
		testing.expect(t, false)
		return
	}

	if !WsTestSendText(firstClient.socket, `{"op":"lobby.join","seq":1,"data":{}}`) ||
		!WsTestSendText(secondClient.socket, `{"op":"lobby.join","seq":1,"data":{}}`) ||
		!WsTestWaitForOp(&firstClient.reader, .MatchStart) || !WsTestWaitForOp(&secondClient.reader, .MatchStart) ||
		!WsTestWaitForOp(&firstClient.reader, .MatchState) || !WsTestWaitForOp(&secondClient.reader, .MatchState) ||
		!WsTestWaitForOp(&firstClient.reader, .GameHidden) || !WsTestWaitForOp(&secondClient.reader, .GameHidden) {
		testing.expect(t, false)
		return
	}

	sync.lock(&testServer.app.network.mutex)

	matchCount := len(testServer.app.network.matches)
	started := matchCount == 1 && testServer.app.network.matches[0].status == .Started
	currentSeat := -1
	currentPlayerId: i64
	if started {
		currentSeat = testServer.app.network.matches[0].game.currentPlayer
		if currentSeat >= 0 && currentSeat < testServer.app.network.matches[0].playerCount {
			currentPlayerId = testServer.app.network.matches[0].players[currentSeat].playerId
		}
	}
	sync.unlock(&testServer.app.network.mutex)

	testing.expect(t, started)
	testing.expect(t, currentPlayerId == first.playerId || currentPlayerId == second.playerId)
	if !started || currentPlayerId == 0 do return

	actor := &firstClient
	peer := &secondClient
	if currentPlayerId == second.playerId {
		actor = &secondClient
		peer = &firstClient
	}
	turnMessage := `{"op":"game.end_turn","seq":2,"data":{}}`

	if !WsTestSendText(actor.socket, turnMessage) || !WsTestWaitForOp(&actor.reader, .ActionOK) ||
		!WsTestWaitForOp(&actor.reader, .MatchState) || !WsTestWaitForOp(&peer.reader, .MatchState) ||
		!WsTestWaitForOp(&actor.reader, .GameHidden) || !WsTestWaitForOp(&peer.reader, .GameHidden) {
		testing.expect(t, false)
		return
	}
}
