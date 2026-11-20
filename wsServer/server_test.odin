package wsserver


import "core:net"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

TestEchoMessage :: proc(server: ^Server, client: ClientID, opcode: Opcode, payload: []byte) {
	_ = ServerSendFrame(server, client, opcode, payload)
}

TestRunServer :: proc(server: ^Server) {
	_ = ServerRun(server)
}

TestRecordCloseCallback :: proc(server: ^Server, client: ClientID) {
	_ = client
	called := cast(^bool)ServerGetContext(server)
	if called != nil do called^ = true
}

TestServerClientID :: proc(server: ^Server) -> (client: ClientID, found: bool) {
	sync.lock(&server.mutex)
	for clientID in server.connections {
		client = clientID
		found = true
		break
	}
	sync.unlock(&server.mutex)
	return
}

TestServerPingState :: proc(server: ^Server, client: ClientID) -> (current, last: i32, found: bool) {
	sync.lock(&server.mutex)
	connection, connectionFound := server.connections[client]
	if connectionFound {
		sync.lock(&connection.pingMutex)
		current = connection.currentPingID
		last = connection.lastPongID
		sync.unlock(&connection.pingMutex)
	}
	sync.unlock(&server.mutex)
	found = connectionFound
	return
}

@(test)
TestServerWakeEndpoint :: proc(t: ^testing.T) {
	ipv4 := ServerWakeEndpoint({address = net.IP4_Any, port = 8080})
	testing.expect_value(t, ipv4, net.Endpoint{address = net.IP4_Loopback, port = 8080})
	ipv6 := ServerWakeEndpoint({address = net.IP6_Any, port = 8080})
	testing.expect_value(t, ipv6, net.Endpoint{address = net.IP6_Loopback, port = 8080})
	bound := ServerWakeEndpoint({address = net.IP4_Address{10, 0, 0, 4}, port = 8080})
	testing.expect_value(t, bound, net.Endpoint{address = net.IP4_Address{10, 0, 0, 4}, port = 8080})
}

@(test)
TestConnectionPoolReusesAndResetsRecords :: proc(t: ^testing.T) {
	server: Server
	initError := ServerInit(&server, {address = net.IP4_Loopback, port = 0}, {}, maxConnections = 0)
	testing.expect_value(t, initError, ServerError.None)
	if initError != .None do return
	defer ServerDeinit(&server)

	connection := ConnectionPoolAcquire(&server.connectionPool)
	testing.expect(t, connection != nil)
	if connection == nil do return
	connection.id = ClientID(42)
	connection.userContext = rawptr(&server)
	connection.socket = 5
	ConnectionPoolRelease(&server.connectionPool, connection)

	reused := ConnectionPoolAcquire(&server.connectionPool)
	testing.expect_value(t, reused, connection)
	testing.expect_value(t, reused.id, ClientID(0))
	testing.expect_value(t, reused.userContext, rawptr(nil))
	testing.expect_value(t, reused.socket, net.TCP_Socket(0))
	ConnectionPoolRelease(&server.connectionPool, reused)
}

@(test)
TestServerUnlimitedConnectionLimit :: proc(t: ^testing.T) {
	server: Server
	initError := ServerInit(
		&server,
		{address = net.IP4_Loopback, port = 0},
		{},
		maxConnections = 0,
		handshakeTimeout = 2 * time.Second,
		sendTimeout = time.Second,
	)
	testing.expect_value(t, initError, ServerError.None)
	if initError != .None do return

	worker := thread.create_and_start_with_poly_data(&server, TestRunServer)
	testing.expect(t, worker != nil)
	if worker == nil {
		ServerDeinit(&server)
		return
	}
	defer {
		ServerStop(&server)
		thread.join(worker)
		thread.destroy(worker)
		ServerDeinit(&server)
	}

	port: int
	for _ in 0..<1000 {
		sync.lock(&server.mutex)
		port = server.endpoint.port
		isRunning := server.isRunning
		sync.unlock(&server.mutex)
		if isRunning && port != 0 do break
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, port != 0)
	if port == 0 do return

	clients: [2]net.TCP_Socket
	defer {
		for client in clients { if client != 0 do net.close(client) }
	}
	for i in 0..<len(clients) {
		client, dialError := net.dial_tcp_from_endpoint({net.IP4_Loopback, port})
		testing.expect(t, dialError == nil)
		if dialError != nil do return
		clients[i] = client
	}

	activeCount := 0
	for _ in 0..<1000 {
		sync.lock(&server.mutex)
		activeCount = len(server.connections)
		sync.unlock(&server.mutex)
		if activeCount == len(clients) do break
		time.sleep(1 * time.Millisecond)
	}
	testing.expect_value(t, activeCount, len(clients))
}

@(test)
TestServerHandshakeTimeoutReleasesCapacity :: proc(t: ^testing.T) {
	server: Server
	initError := ServerInit(
		&server,
		{address = net.IP4_Loopback, port = 0},
		{},
		maxConnections = 1,
		handshakeTimeout = 50 * time.Millisecond,
		sendTimeout = time.Second,
	)
	testing.expect_value(t, initError, ServerError.None)
	if initError != .None do return
	worker := thread.create_and_start_with_poly_data(&server, TestRunServer)
	testing.expect(t, worker != nil)
	if worker == nil {
		ServerDeinit(&server)
		return
	}
	defer {
		ServerStop(&server)
		thread.join(worker)
		thread.destroy(worker)
		ServerDeinit(&server)
	}

	port: int
	for _ in 0..<1000 {
		sync.lock(&server.mutex)
		port = server.endpoint.port
		isRunning := server.isRunning
		sync.unlock(&server.mutex)
		if isRunning && port != 0 do break
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, port != 0)
	if port == 0 do return

	partialClient, dialError := net.dial_tcp_from_endpoint({net.IP4_Loopback, port})
	testing.expect(t, dialError == nil)
	if dialError != nil do return
	defer net.close(partialClient)
	partialRequest := "GET / HTTP/1.1\r\nHost: localhost\r\n"
	testing.expect(t, SocketSendAll(partialClient, transmute([]byte)partialRequest))

	connectionSeen := false
	for _ in 0..<1000 {
		_, connectionSeen = TestServerClientID(&server)
		if connectionSeen do break
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, connectionSeen)
	connectionRemoved := false
	for _ in 0..<1000 {
		_, found := TestServerClientID(&server)
		if !found {
			connectionRemoved = true
			break
		}
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, connectionRemoved)

	validClient, validDialError := net.dial_tcp_from_endpoint({net.IP4_Loopback, port})
	testing.expect(t, validDialError == nil)
	if validDialError != nil do return
	defer net.close(validClient)
	validRequest := "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	testing.expect(t, SocketSendAll(validClient, transmute([]byte)validRequest))
	validReader := SocketReader{socket = validClient}
	handshakeResponse: [160]byte
	expectedHandshake := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
	testing.expect(t, SocketReaderReadExact(&validReader, handshakeResponse[:len(expectedHandshake)]))
	testing.expect_value(t, string(handshakeResponse[:len(expectedHandshake)]), expectedHandshake)
}

@(test)
TestServerCloseHandshake :: proc(t: ^testing.T) {
	server: Server
	closeCallbackCalled := false
	initError := ServerInit(
		&server,
		{address = net.IP4_Loopback, port = 0},
		Events{onClose = TestRecordCloseCallback},
		closeTimeout = 250 * time.Millisecond,
		userContext = rawptr(&closeCallbackCalled),
	)
	testing.expect_value(t, initError, ServerError.None)
	if initError != .None do return
	worker := thread.create_and_start_with_poly_data(&server, TestRunServer)
	testing.expect(t, worker != nil)
	if worker == nil {
		ServerDeinit(&server)
		return
	}
	defer {
		ServerStop(&server)
		thread.join(worker)
		thread.destroy(worker)
		ServerDeinit(&server)
	}

	port: int
	for _ in 0..<1000 {
		sync.lock(&server.mutex)
		port = server.endpoint.port
		isRunning := server.isRunning
		sync.unlock(&server.mutex)
		if isRunning && port != 0 do break
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, port != 0)
	if port == 0 do return

	client, dialError := net.dial_tcp_from_endpoint({net.IP4_Loopback, port})
	testing.expect(t, dialError == nil)
	if dialError != nil do return
	defer net.close(client)

	request := "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	if !SocketSendAll(client, transmute([]byte)request) {
		testing.expect(t, false)
		return
	}
	clientReader := SocketReader{socket = client}
	handshakeResponse: [160]byte
	expectedHandshake := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
	testing.expect(t, SocketReaderReadExact(&clientReader, handshakeResponse[:len(expectedHandshake)]))
	testing.expect_value(t, string(handshakeResponse[:len(expectedHandshake)]), expectedHandshake)

	clientID, foundClient := TestServerClientID(&server)
	testing.expect(t, foundClient)
	if !foundClient do return
	testing.expect(t, ServerCloseClient(&server, clientID))
	serverClose: [4]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, serverClose[:]))
	testing.expect_value(t, serverClose, [?]byte{0x88, 0x02, 0x03, 0xe8})

	maskedPing := [?]byte{0x89, 0x81, 0, 0, 0, 0, '?'}
	testing.expect(t, SocketSendAll(client, maskedPing[:]))
	pongFrame: [3]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, pongFrame[:]))
	testing.expect_value(t, pongFrame, [?]byte{0x8a, 0x01, '?'})

	maskedClose := [?]byte{0x88, 0x82, 0x11, 0x22, 0x33, 0x44, 0x12, 0xca}
	testing.expect(t, SocketSendAll(client, maskedClose[:]))
	duplicateClose: [4]byte
	testing.expect(t, !SocketReaderReadExact(&clientReader, duplicateClose[:]))

	connectionRemoved := false
	for _ in 0..<1000 {
		_, found := ServerGetClientState(&server, clientID)
		if !found {
			connectionRemoved = true
			break
		}
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, connectionRemoved)
	testing.expect(t, closeCallbackCalled)
}

@(test)
TestServerHandshakeEchoAndPing :: proc(t: ^testing.T) {
	server: Server
	serverContextValue := 42
	initError := ServerInit(
		&server,
		{address = net.IP4_Loopback, port = 0},
		Events{onMessage = TestEchoMessage},
		maxConnections = 4,
		maxMessageSize = 1024,
		closeTimeout = 50 * time.Millisecond,
		sendTimeout = time.Second,
		userContext = rawptr(&serverContextValue),
	)
	testing.expect_value(t, initError, ServerError.None)
	worker := thread.create_and_start_with_poly_data(&server, TestRunServer)
	testing.expect(t, worker != nil)
	if worker == nil {
		ServerDeinit(&server)
		return
	}
	defer {
		ServerStop(&server)
		thread.join(worker)
		thread.destroy(worker)
		ServerDeinit(&server)
	}

	port: int
	for _ in 0..<1000 {
		sync.lock(&server.mutex)
		port = server.endpoint.port
		isRunning := server.isRunning
		sync.unlock(&server.mutex)
		if isRunning && port != 0 do break
		time.sleep(1 * time.Millisecond)
	}

	testing.expect(t, port != 0)
	if port == 0 do return

	client, dialError := net.dial_tcp_from_endpoint({net.IP4_Loopback, port})

	testing.expect(t, dialError == nil)
	if dialError != nil do return
	defer net.close(client)

	request := "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	_, sendError := net.send_tcp(client, transmute([]byte)request)

	testing.expect(t, sendError == nil)
	if sendError != nil do return

	clientReader := SocketReader{socket = client}
	handshakeResponse: [160]byte
	expectedHandshake := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
	testing.expect(t, SocketReaderReadExact(&clientReader, handshakeResponse[:len(expectedHandshake)]))

	testing.expect_value(t, string(handshakeResponse[:len(expectedHandshake)]), expectedHandshake)

	firstFragment := [?]byte{0x01, 0x82, 0, 0, 0, 0, 'R', 'I'}
	pingFrame := [?]byte{0x89, 0x81, 0, 0, 0, 0, '?'}
	lastFragment := [?]byte{0x80, 0x82, 0, 0, 0, 0, 'F', 'T'}
	_, sendError = net.send_tcp(client, firstFragment[:])
	testing.expect(t, sendError == nil)
	if sendError != nil do return
	_, sendError = net.send_tcp(client, pingFrame[:])
	testing.expect(t, sendError == nil)
	if sendError != nil do return
	_, sendError = net.send_tcp(client, lastFragment[:])
	testing.expect(t, sendError == nil)
	if sendError != nil do return

	pongFrame: [3]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, pongFrame[:]))
	testing.expect_value(t, pongFrame, [?]byte{0x8a, 0x01, '?'})
	echoedFrame: [6]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, echoedFrame[:]))
	testing.expect_value(t, echoedFrame, [?]byte{0x81, 0x04, 'R', 'I', 'F', 'T'})

	clientID, foundClient := TestServerClientID(&server)
	testing.expect(t, foundClient)
	if !foundClient do return

	testing.expect_value(t, ServerGetContext(&server), rawptr(&serverContextValue))
	remoteEndpoint, endpointFound := ServerGetClientEndpoint(&server, clientID)
	testing.expect(t, endpointFound)
	testing.expect_value(t, remoteEndpoint.address, net.IP4_Address{127, 0, 0, 1})
	testing.expect(t, remoteEndpoint.port != 0)
	state, stateFound := ServerGetClientState(&server, clientID)
	testing.expect(t, stateFound)
	testing.expect_value(t, state, ConnectionState.Open)

	connectionContextValue := 84
	testing.expect(t, ServerSetConnectionContext(&server, clientID, rawptr(&connectionContextValue)))
	connectionContext, contextFound := ServerGetConnectionContext(&server, clientID)
	testing.expect(t, contextFound)
	testing.expect_value(t, connectionContext, rawptr(&connectionContextValue))

	testing.expect(t, ServerPing(&server, clientID, 1))
	serverPing: [6]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, serverPing[:]))
	testing.expect_value(t, serverPing, [?]byte{0x89, 0x04, 0, 0, 0, 0})
	currentPingID, lastPongID, pingStateFound := TestServerPingState(&server, clientID)
	testing.expect(t, pingStateFound)
	testing.expect_value(t, currentPingID, i32(0))
	testing.expect_value(t, lastPongID, i32(-1))

	maskedPong := [?]byte{0x8a, 0x84, 0x17, 0x2a, 0x3b, 0x4c, 0x17, 0x2a, 0x3b, 0x4c}
	_, sendError = net.send_tcp(client, maskedPong[:])
	testing.expect(t, sendError == nil)
	if sendError != nil do return
	for _ in 0..<1000 {
		currentPingID, lastPongID, pingStateFound = TestServerPingState(&server, clientID)
		if pingStateFound && lastPongID == 0 do break
		time.sleep(1 * time.Millisecond)
	}
	testing.expect_value(t, currentPingID, i32(0))
	testing.expect_value(t, lastPongID, i32(0))

	testing.expect_value(t, ServerPingAll(&server, 1), 1)
	secondPing: [6]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, secondPing[:]))
	testing.expect_value(t, secondPing, [?]byte{0x89, 0x04, 0, 0, 0, 1})
	currentPingID, lastPongID, pingStateFound = TestServerPingState(&server, clientID)
	testing.expect(t, pingStateFound)
	testing.expect_value(t, currentPingID, i32(1))
	testing.expect_value(t, lastPongID, i32(0))

	testing.expect(t, ServerCloseClient(&server, clientID))
	state, stateFound = ServerGetClientState(&server, clientID)
	testing.expect(t, stateFound)
	testing.expect_value(t, state, ConnectionState.Closing)
	closeFrame: [4]byte
	testing.expect(t, SocketReaderReadExact(&clientReader, closeFrame[:]))
	testing.expect_value(t, closeFrame, [?]byte{0x88, 0x02, 0x03, 0xe8})

	connectionRemoved := false
	for _ in 0..<1000 {
		_, stateFound = ServerGetClientState(&server, clientID)
		if !stateFound {
			connectionRemoved = true
			break
		}
		time.sleep(1 * time.Millisecond)
	}
	testing.expect(t, connectionRemoved)
	connectionContext, contextFound = ServerGetConnectionContext(&server, clientID)
	testing.expect(t, !contextFound)
	testing.expect_value(t, connectionContext, rawptr(nil))
}
