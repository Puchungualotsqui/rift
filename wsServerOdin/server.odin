package wsserver

import "core:net"
import "base:runtime"
import "core:sync"
import "core:thread"
import "core:time"

MAX_HANDSHAKE_SIZE :: 16 * 1024
DEFAULT_MAX_CONNECTIONS :: 128 // maxConnections = 0 disables the cap
DEFAULT_MAX_MESSAGE_SIZE :: 64 * 1024
DEFAULT_HANDSHAKE_TIMEOUT :: 5 * time.Second
DEFAULT_CLOSE_TIMEOUT :: 500 * time.Millisecond
DEFAULT_SEND_TIMEOUT :: 5 * time.Second

ClientID :: distinct u64

ConnectionState :: enum {
	Connecting,
	Open,
	Closing,
	Closed,
}

ServerError :: enum {
	None,
	InvalidConfiguration,
	AlreadyRunning,
	ListenFailed,
	AcceptFailed,
	ThreadCreationFailed,
}

Events :: struct {
	onOpen:    proc(server: ^Server, client: ClientID),
	onClose:   proc(server: ^Server, client: ClientID),
	onMessage: proc(server: ^Server, client: ClientID, opcode: Opcode, payload: []byte),
}

Server :: struct {
	endpoint:         net.Endpoint,
	allocator:        runtime.Allocator,
	maxConnections:   int, // 0 disables the active connection cap
	maxFrameSize:     int,
	maxMessageSize:   int,
	handshakeTimeout: time.Duration,
	closeTimeout:     time.Duration,
	sendTimeout:      time.Duration,
	userContext:      rawptr,
	events:           Events,
	mutex:            sync.Mutex,
	connections:      map[ClientID]^Connection,
	connectionPool:   ConnectionPool,
	workers:          [dynamic]^thread.Thread,
	listener:         net.TCP_Socket,
	nextClientID:     u64,
	isRunning:        bool,
	stopping:         bool,
}

ConnectionPool :: struct {
	allocator: runtime.Allocator,
	mutex:     sync.Mutex,
	available: [dynamic]^Connection,
}

Connection :: struct {
	server:         ^Server,
	id:             ClientID,
	socket:         net.TCP_Socket,
	remoteEndpoint: net.Endpoint,
	userContext:    rawptr,
	state:          ConnectionState,
	handshakeTimer: ^thread.Thread,
	closeTimer:     ^thread.Thread,
	sendMutex:      sync.Mutex,
	pingMutex:      sync.Mutex,
	currentPingID:  i32,
	lastPongID:     i32,
	maxFrameSize:   int,
	maxMessageSize: int,
}

SocketReader :: struct {
	socket: net.TCP_Socket,
	buffer: [4096]byte,
	start:  int,
	end:    int,
}

ServerInit :: proc(server: ^Server, endpoint: net.Endpoint, events: Events, maxConnections: int = DEFAULT_MAX_CONNECTIONS, maxMessageSize: int = DEFAULT_MAX_MESSAGE_SIZE, handshakeTimeout: time.Duration = DEFAULT_HANDSHAKE_TIMEOUT, closeTimeout: time.Duration = DEFAULT_CLOSE_TIMEOUT, sendTimeout: time.Duration = DEFAULT_SEND_TIMEOUT, userContext: rawptr = nil) -> ServerError {
	if maxConnections < 0 || maxMessageSize < 1 || maxMessageSize > MAX_FRAME_LENGTH || handshakeTimeout <= 0 || closeTimeout <= 0 || sendTimeout < 0 do return .InvalidConfiguration

	server^ = {}
	server.endpoint = endpoint
	server.allocator = context.allocator
	server.maxConnections = maxConnections
	server.maxFrameSize = max(maxMessageSize, 125)
	server.maxMessageSize = maxMessageSize
	server.handshakeTimeout = handshakeTimeout
	server.closeTimeout = closeTimeout
	server.sendTimeout = sendTimeout
	server.userContext = userContext
	server.events = events
	initialCapacity := DEFAULT_MAX_CONNECTIONS
	if maxConnections > 0 do initialCapacity = min(maxConnections, DEFAULT_MAX_CONNECTIONS)
	server.connections = make(map[ClientID]^Connection, initialCapacity, context.allocator)
	ConnectionPoolInit(&server.connectionPool, context.allocator, initialCapacity)
	server.workers = make([dynamic]^thread.Thread, 0, initialCapacity, context.allocator)
	server.nextClientID = 1
	return .None
}

ServerDeinit :: proc(server: ^Server) {
	assert(!server.isRunning && len(server.connections) == 0)
	ConnectionPoolDeinit(&server.connectionPool)
	delete(server.connections)
	delete(server.workers)
	server^ = {}
}

ConnectionPoolInit :: proc(pool: ^ConnectionPool, allocator: runtime.Allocator, initialCapacity: int) {
	assert(initialCapacity >= 0)
	pool^ = {}
	pool.allocator = allocator
	pool.available = make([dynamic]^Connection, 0, initialCapacity, allocator)
}

ConnectionPoolAcquire :: proc(pool: ^ConnectionPool) -> ^Connection {
	sync.lock(&pool.mutex)
	if len(pool.available) > 0 {
		lastIndex := len(pool.available) - 1
		connection := pool.available[lastIndex]
		unordered_remove(&pool.available, lastIndex)
		sync.unlock(&pool.mutex)
		return connection
	}
	sync.unlock(&pool.mutex)
	return new(Connection, pool.allocator)
}

ConnectionPoolRelease :: proc(pool: ^ConnectionPool, connection: ^Connection) {
	connection^ = {}
	sync.lock(&pool.mutex)
	append(&pool.available, connection)
	sync.unlock(&pool.mutex)
}

ConnectionPoolDeinit :: proc(pool: ^ConnectionPool) {
	for connection in pool.available do free(connection, pool.allocator)
	delete(pool.available)
	pool^ = {}
}

ServerRun :: proc(server: ^Server) -> ServerError {
	sync.lock(&server.mutex)
	if server.isRunning {
		sync.unlock(&server.mutex)
		return .AlreadyRunning
	}
	server.stopping = false
	server.isRunning = true
	sync.unlock(&server.mutex)

	listener, listenError := net.listen_tcp(server.endpoint)
	if listenError != nil {
		sync.lock(&server.mutex)
		server.isRunning = false
		sync.unlock(&server.mutex)
		return .ListenFailed
	}
	boundEndpoint, boundError := net.bound_endpoint(listener)
	if boundError != nil {
		net.close(listener)
		sync.lock(&server.mutex)
		server.isRunning = false
		sync.unlock(&server.mutex)
		return .ListenFailed
	}

	sync.lock(&server.mutex)
	if server.stopping {
		server.isRunning = false
		sync.unlock(&server.mutex)
		net.close(listener)
		return .None
	}
	server.endpoint = boundEndpoint
	server.listener = listener
	sync.unlock(&server.mutex)

	result := ServerError.None
	for {
		sync.lock(&server.mutex)
		stopping := server.stopping
		sync.unlock(&server.mutex)
		if stopping do break

		clientSocket, remoteEndpoint, acceptError := net.accept_tcp(listener)
		if acceptError != nil {
			sync.lock(&server.mutex)
			stopping = server.stopping
			sync.unlock(&server.mutex)
			if !stopping do result = .AcceptFailed
			break
		}

		if server.sendTimeout > 0 {
			if optionError := net.set_option(clientSocket, .Send_Timeout, server.sendTimeout); optionError != nil {
				net.close(clientSocket)
				continue
			}
		}

		ServerReapWorkers(server)
		sync.lock(&server.mutex)
		if server.stopping || (server.maxConnections > 0 && len(server.connections) >= server.maxConnections) {
			sync.unlock(&server.mutex)
			net.close(clientSocket)
			continue
		}

		connection := ConnectionPoolAcquire(&server.connectionPool)
		connection.server = server
		connection.socket = clientSocket
		connection.remoteEndpoint = remoteEndpoint
		connection.state = .Connecting
		connection.currentPingID = -1
		connection.lastPongID = -1
		connection.maxFrameSize = server.maxFrameSize
		connection.maxMessageSize = server.maxMessageSize
		connection.id = ClientID(server.nextClientID)
		server.nextClientID += 1
		if server.nextClientID == 0 do server.nextClientID = 1
		server.connections[connection.id] = connection

		connection.handshakeTimer = thread.create_and_start_with_data(rawptr(connection), ConnectionHandshakeTimeoutThread)
		if connection.handshakeTimer == nil {
			delete_key(&server.connections, connection.id)
			sync.unlock(&server.mutex)
			net.close(clientSocket)
			ConnectionPoolRelease(&server.connectionPool, connection)
			continue
		}

		worker := thread.create_and_start_with_data(rawptr(connection), ServerConnectionThread)
		if worker == nil {
			ConnectionShutdown(connection)
			ConnectionJoinHandshakeTimer(connection)
			delete_key(&server.connections, connection.id)
			ConnectionPoolRelease(&server.connectionPool, connection)
			sync.unlock(&server.mutex)
			continue
		}
		append(&server.workers, worker)
		sync.unlock(&server.mutex)
	}

	if result != .None do ServerStop(server)
	ServerCloseListener(server)
	for worker in server.workers {
		thread.join(worker)
		thread.destroy(worker)
	}
	clear(&server.workers)

	sync.lock(&server.mutex)
	server.isRunning = false
	sync.unlock(&server.mutex)
	return result
}

ServerStop :: proc(server: ^Server) {
	sync.lock(&server.mutex)
	server.stopping = true
	listener := server.listener
	endpoint := server.endpoint
	for _, connection in server.connections do ConnectionShutdown(connection)
	sync.unlock(&server.mutex)

	if listener != 0 {
		wakeSocket, wakeError := net.dial_tcp_from_endpoint(ServerWakeEndpoint(endpoint))
		if wakeError == nil do net.close(wakeSocket)
	}
	ServerCloseListener(server)
}

ServerWakeEndpoint :: proc(endpoint: net.Endpoint) -> net.Endpoint {
	wakeEndpoint := endpoint
	switch address in endpoint.address {
	case net.IP4_Address:
		if address == net.IP4_Any do wakeEndpoint.address = net.IP4_Loopback
	case net.IP6_Address:
		if address == net.IP6_Any do wakeEndpoint.address = net.IP6_Loopback
	}
	return wakeEndpoint
}

ServerCloseListener :: proc(server: ^Server) {
	sync.lock(&server.mutex)
	listener := server.listener
	server.listener = 0
	sync.unlock(&server.mutex)
	if listener != 0 do net.close(listener)
}

ServerReapWorkers :: proc(server: ^Server) {
	sync.lock(&server.mutex)
	index := 0
	for index < len(server.workers) {
		worker := server.workers[index]
		if thread.is_done(worker) {
			thread.destroy(worker)
			ordered_remove(&server.workers, index)
		} else {
			index += 1
		}
	}
	sync.unlock(&server.mutex)
}

ServerGetContext :: proc(server: ^Server) -> rawptr {
	return server.userContext
}

ServerGetClientEndpoint :: proc(server: ^Server, client: ClientID) -> (endpoint: net.Endpoint, found: bool) {
	sync.lock(&server.mutex)
	connection, connectionFound := server.connections[client]
	if connectionFound do endpoint = connection.remoteEndpoint
	sync.unlock(&server.mutex)
	found = connectionFound
	return
}

ServerGetClientState :: proc(server: ^Server, client: ClientID) -> (state: ConnectionState, found: bool) {
	state = .Closed
	sync.lock(&server.mutex)
	connection, connectionFound := server.connections[client]
	if connectionFound {
		sync.lock(&connection.sendMutex)
		state = connection.state
		sync.unlock(&connection.sendMutex)
	}
	sync.unlock(&server.mutex)
	found = connectionFound
	return
}

ServerSetConnectionContext :: proc(server: ^Server, client: ClientID, userContext: rawptr) -> bool {
	sync.lock(&server.mutex)
	connection, found := server.connections[client]
	if found do connection.userContext = userContext
	sync.unlock(&server.mutex)
	return found
}

ServerGetConnectionContext :: proc(server: ^Server, client: ClientID) -> (userContext: rawptr, found: bool) {
	sync.lock(&server.mutex)
	connection, connectionFound := server.connections[client]
	if connectionFound do userContext = connection.userContext
	sync.unlock(&server.mutex)
	found = connectionFound
	return
}

ServerSendFrame :: proc(server: ^Server, client: ClientID, opcode: Opcode, payload: []byte) -> bool {
	if opcode != .Text && opcode != .Binary && !IsControlOpcode(opcode) do return false
	if IsControlOpcode(opcode) {
		if len(payload) > 125 do return false
	} else if len(payload) > server.maxMessageSize {
		return false
	}

	sync.lock(&server.mutex)
	connection, found := server.connections[client]
	if !found {
		sync.unlock(&server.mutex)
		return false
	}
	sync.lock(&connection.sendMutex)
	sync.unlock(&server.mutex)
	if connection.state != .Open {
		sync.unlock(&connection.sendMutex)
		return false
	}
	if opcode == .Close {
		sent := ConnectionStartCloseLocked(connection, payload)
		sync.unlock(&connection.sendMutex)
		return sent
	}
	sent := ConnectionWriteFrameLocked(connection, opcode, payload)
	sync.unlock(&connection.sendMutex)
	return sent
}

ServerCloseClient :: proc(server: ^Server, client: ClientID) -> bool {
	closeCode := [?]byte{0x03, 0xe8}
	sync.lock(&server.mutex)
	connection, found := server.connections[client]
	if !found {
		sync.unlock(&server.mutex)
		return false
	}
	sync.lock(&connection.sendMutex)
	sync.unlock(&server.mutex)
	sent := ConnectionStartCloseLocked(connection, closeCode[:])
	sync.unlock(&connection.sendMutex)
	return sent
}

ServerBroadcastFrame :: proc(server: ^Server, opcode: Opcode, payload: []byte) -> int {
	if (opcode != .Text && opcode != .Binary) || len(payload) > server.maxMessageSize do return 0

	sync.lock(&server.mutex)
	clientIDs := make([dynamic]ClientID, 0, len(server.connections), context.temp_allocator)
	for clientID in server.connections do append(&clientIDs, clientID)
	sync.unlock(&server.mutex)
	defer delete(clientIDs)

	sent := 0
	for clientID in clientIDs {
		if ServerSendFrame(server, clientID, opcode, payload) do sent += 1
	}
	return sent
}

ConnectionWriteFrameLocked :: proc(connection: ^Connection, opcode: Opcode, payload: []byte) -> bool {
	if connection.state == .Closed do return false
	encoded := make([]byte, len(payload) + 10, context.temp_allocator)
	defer delete(encoded, context.temp_allocator)
	written, encodeError := EncodeFrame(Frame{final = true, opcode = opcode, payload = payload}, encoded)
	if encodeError != .None do return false
	if !SocketSendAll(connection.socket, encoded[:written]) {
		ConnectionShutdownLocked(connection)
		return false
	}
	return true
}

SocketSendAll :: proc(socket: net.TCP_Socket, data: []byte) -> bool {
	sentTotal := 0
	for sentTotal < len(data) {
		sent, sendError := net.send_tcp(socket, data[sentTotal:])
		if sendError != nil || sent <= 0 || sent > len(data) - sentTotal do return false
		sentTotal += sent
	}
	return true
}

ConnectionStartCloseLocked :: proc(connection: ^Connection, payload: []byte) -> bool {
	if connection.state != .Open do return false
	connection.state = .Closing
	if !ConnectionWriteFrameLocked(connection, .Close, payload) {
		ConnectionShutdownLocked(connection)
		return false
	}
	closeTimer := thread.create_and_start_with_data(rawptr(connection), ConnectionCloseTimeoutThread)
	if closeTimer == nil {
		ConnectionShutdownLocked(connection)
		return false
	}
	connection.closeTimer = closeTimer
	return true
}

ConnectionHandshakeTimeoutThread :: proc(data: rawptr) {
	connection := cast(^Connection)data
	remaining := connection.server.handshakeTimeout
	pollInterval := 10 * time.Millisecond
	for remaining > 0 {
		delay := min(remaining, pollInterval)
		time.sleep(delay)
		remaining -= delay
		sync.lock(&connection.sendMutex)
		if connection.state != .Connecting {
			sync.unlock(&connection.sendMutex)
			return
		}
		if remaining <= 0 do ConnectionShutdownLocked(connection)
		sync.unlock(&connection.sendMutex)
	}
}

ConnectionJoinHandshakeTimer :: proc(connection: ^Connection) {
	handshakeTimer := connection.handshakeTimer
	if handshakeTimer != nil {
		thread.join(handshakeTimer)
		thread.destroy(handshakeTimer)
		connection.handshakeTimer = nil
	}
}

ConnectionCloseTimeoutThread :: proc(data: rawptr) {
	connection := cast(^Connection)data
	remaining := connection.server.closeTimeout
	pollInterval := 10 * time.Millisecond
	for remaining > 0 {
		delay := min(remaining, pollInterval)
		time.sleep(delay)
		remaining -= delay
		sync.lock(&connection.sendMutex)
		if connection.state != .Closing {
			sync.unlock(&connection.sendMutex)
			return
		}
		if remaining <= 0 do ConnectionShutdownLocked(connection)
		sync.unlock(&connection.sendMutex)
	}
}

ConnectionJoinCloseTimer :: proc(connection: ^Connection) {
	closeTimer := connection.closeTimer
	if closeTimer != nil {
		thread.join(closeTimer)
		thread.destroy(closeTimer)
		connection.closeTimer = nil
	}
}

ConnectionShutdown :: proc(connection: ^Connection) {
	sync.lock(&connection.sendMutex)
	ConnectionShutdownLocked(connection)
	sync.unlock(&connection.sendMutex)
}

ConnectionShutdownLocked :: proc(connection: ^Connection) {
	if connection.state != .Closed {
		connection.state = .Closed
		_ = net.shutdown(connection.socket, .Both)
		net.close(connection.socket)
		connection.socket = 0
	}
}

ServerPing :: proc(server: ^Server, client: ClientID, threshold: int) -> bool {
	if threshold <= 0 do return false

	sync.lock(&server.mutex)
	connection, found := server.connections[client]
	if !found {
		sync.unlock(&server.mutex)
		return false
	}
	sync.lock(&connection.pingMutex)
	sync.unlock(&server.mutex)
	sync.lock(&connection.sendMutex)
	if connection.state != .Open {
		sync.unlock(&connection.sendMutex)
		sync.unlock(&connection.pingMutex)
		return false
	}
	if connection.currentPingID == i32(0x7fffffff) {
		ConnectionShutdownLocked(connection)
		sync.unlock(&connection.sendMutex)
		sync.unlock(&connection.pingMutex)
		return false
	}

	connection.currentPingID += 1
	pingID := u32(connection.currentPingID)
	payload := [?]byte{
		byte(pingID >> 24),
		byte(pingID >> 16),
		byte(pingID >> 8),
		byte(pingID),
	}
	sent := ConnectionWriteFrameLocked(connection, .Ping, payload[:])
	if !sent || i64(connection.currentPingID) - i64(connection.lastPongID) > i64(threshold) {
		ConnectionShutdownLocked(connection)
	}
	sync.unlock(&connection.sendMutex)
	sync.unlock(&connection.pingMutex)
	return sent
}

ServerPingAll :: proc(server: ^Server, threshold: int) -> int {
	if threshold <= 0 do return 0

	sync.lock(&server.mutex)
	clientIDs := make([]ClientID, len(server.connections), context.temp_allocator)
	clientCount := 0
	for clientID in server.connections {
		clientIDs[clientCount] = clientID
		clientCount += 1
	}
	sync.unlock(&server.mutex)
	defer delete(clientIDs, context.temp_allocator)

	sent := 0
	for clientID in clientIDs {
		if ServerPing(server, clientID, threshold) do sent += 1
	}
	return sent
}

ConnectionRecordPong :: proc(connection: ^Connection, payload: []byte) {
	if len(payload) != 4 || payload[0] & 0x80 != 0 do return

	pongID := i32(u32(payload[0]) << 24 | u32(payload[1]) << 16 | u32(payload[2]) << 8 | u32(payload[3]))
	sync.lock(&connection.pingMutex)
	if pongID <= connection.currentPingID do connection.lastPongID = pongID
	sync.unlock(&connection.pingMutex)
}

ServerRemoveConnection :: proc(connection: ^Connection) {
	server := connection.server
	sync.lock(&server.mutex)
	sync.lock(&connection.pingMutex)
	sync.lock(&connection.sendMutex)
	delete_key(&server.connections, connection.id)
	sync.unlock(&connection.sendMutex)
	sync.unlock(&connection.pingMutex)
	sync.unlock(&server.mutex)
}

SocketReaderReadExact :: proc(reader: ^SocketReader, destination: []byte) -> bool {
	position := 0
	for position < len(destination) {
		if reader.start == reader.end {
			received, receiveError := net.recv_tcp(reader.socket, reader.buffer[:])
			if receiveError != nil || received == 0 do return false
			reader.start = 0
			reader.end = received
		}
		available := reader.end - reader.start
		amount := min(available, len(destination) - position)
		copy(destination[position:position + amount], reader.buffer[reader.start:reader.start + amount])
		reader.start += amount
		position += amount
	}
	return true
}

SocketReaderReadHandshake :: proc(reader: ^SocketReader) -> (request: [MAX_HANDSHAKE_SIZE]byte, size: int, ok: bool) {
	for size < len(request) {
		if !SocketReaderReadExact(reader, request[size:size + 1]) do return request, 0, false
		size += 1
		if size >= 4 && request[size - 4] == '\r' && request[size - 3] == '\n' && request[size - 2] == '\r' && request[size - 1] == '\n' do return request, size, true
	}
	return request, 0, false
}

SocketReaderReadFrame :: proc(reader: ^SocketReader, maxFrameSize: int) -> (frame: Frame, storage: []byte, err: FrameError, readOK: bool) {
	prefix: [10]byte
	if !SocketReaderReadExact(reader, prefix[:2]) do return frame, nil, .NeedMoreData, false
	first, second := prefix[0], prefix[1]
	if first & 0x70 != 0 do return frame, nil, .InvalidReservedBits, true
	if _, validOpcode := DecodeOpcode(first & 0x0f); !validOpcode do return frame, nil, .InvalidOpcode, true
	if second & 0x80 == 0 do return frame, nil, .UnmaskedClientFrame, true

	final := first & 0x80 != 0
	opcode, _ := DecodeOpcode(first & 0x0f)
	length := u64(second & 0x7f)
	headerSize := 2
	if length == 126 {
		if !SocketReaderReadExact(reader, prefix[2:4]) do return frame, nil, .NeedMoreData, false
		length = u64(prefix[2]) << 8 | u64(prefix[3])
		if length < 126 do return frame, nil, .InvalidLength, true
		headerSize = 4
	} else if length == 127 {
		if !SocketReaderReadExact(reader, prefix[2:10]) do return frame, nil, .NeedMoreData, false
		if prefix[2] & 0x80 != 0 do return frame, nil, .InvalidLength, true
		length = 0
		for i := 2; i < 10; i += 1 do length = (length << 8) | u64(prefix[i])
		if length <= 0xffff do return frame, nil, .InvalidLength, true
		headerSize = 10
	}
	if IsControlOpcode(opcode) && (!final || length > 125) do return frame, nil, .InvalidControlFrame, true
	if length > u64(maxFrameSize) do return frame, nil, .FrameTooLarge, true
	if opcode == .Close && length == 1 do return frame, nil, .InvalidCloseFrame, true

	frameSize := headerSize + 4 + int(length)
	storage = make([]byte, frameSize, context.temp_allocator)
	copy(storage[:headerSize], prefix[:headerSize])
	if !SocketReaderReadExact(reader, storage[headerSize:]) {
		delete(storage, context.temp_allocator)
		return frame, nil, .NeedMoreData, false
	}
	payloadOffset := headerSize + 4
	frame, _, err = DecodeFrame(storage, storage[payloadOffset:])
	return frame, storage, err, true
}

ServerConnectionThread :: proc(data: rawptr) {
	connection := cast(^Connection)data
	opened := false
	defer {
		ConnectionShutdown(connection)
		ConnectionJoinHandshakeTimer(connection)
		ConnectionJoinCloseTimer(connection)
		if opened && connection.server.events.onClose != nil do connection.server.events.onClose(connection.server, connection.id)
		server := connection.server
		ServerRemoveConnection(connection)
		ConnectionPoolRelease(&server.connectionPool, connection)
	}

	reader := SocketReader{socket = connection.socket}
	request, requestSize, handshakeReadOK := SocketReaderReadHandshake(&reader)
	if !handshakeReadOK do return
	if reader.start != reader.end do return
	response, consumed, handshakeError := BuildHandshakeResponse(request[:requestSize])
	if handshakeError != .None || consumed != requestSize do return
	sync.lock(&connection.sendMutex)
	handshakeSent := connection.state == .Connecting && SocketSendAll(connection.socket, response.bytes[:response.size])
	if handshakeSent do connection.state = .Open
	sync.unlock(&connection.sendMutex)
	if !handshakeSent do return
	ConnectionJoinHandshakeTimer(connection)

	opened = true
	if connection.server.events.onOpen != nil do connection.server.events.onOpen(connection.server, connection.id)

	fragment: [dynamic]byte
	defer delete(fragment)
	fragmentOpcode: Opcode = .Continuation
	fragmentActive := false
	for {
		frame, storage, frameError, readOK := SocketReaderReadFrame(&reader, connection.maxFrameSize)
		if !readOK {
			if storage != nil do delete(storage, context.temp_allocator)
			break
		}
		if frameError != .None {
			closeCode := u16(1002)
			if frameError == .FrameTooLarge do closeCode = 1009
			if frameError == .InvalidUTF8 do closeCode = 1007
			frameComplete := storage != nil
			ConnectionSendClose(connection, closeCode, waitForPeer = frameComplete)
			if storage != nil do delete(storage, context.temp_allocator)
			if !frameComplete do break
			continue
		}
		continueReading := ConnectionHandleFrame(connection, frame, &fragment, &fragmentOpcode, &fragmentActive)
		if storage != nil do delete(storage, context.temp_allocator)
		if !continueReading do break
	}
}

ConnectionSendClose :: proc(connection: ^Connection, code: u16, waitForPeer: bool = true) {
	payload := [?]byte{byte(code >> 8), byte(code)}
	sync.lock(&connection.sendMutex)
	if connection.state == .Open {
		if waitForPeer {
			_ = ConnectionStartCloseLocked(connection, payload[:])
		} else {
			connection.state = .Closing
			_ = ConnectionWriteFrameLocked(connection, .Close, payload[:])
		}
	}
	sync.unlock(&connection.sendMutex)
}

ConnectionReplyClose :: proc(connection: ^Connection, payload: []byte) {
	sync.lock(&connection.sendMutex)
	if connection.state == .Open {
		connection.state = .Closing
		_ = ConnectionWriteFrameLocked(connection, .Close, payload)
	}
	sync.unlock(&connection.sendMutex)
}

ConnectionSendPong :: proc(connection: ^Connection, payload: []byte) -> bool {
	sync.lock(&connection.sendMutex)
	if connection.state != .Open && connection.state != .Closing {
		sync.unlock(&connection.sendMutex)
		return false
	}
	sent := ConnectionWriteFrameLocked(connection, .Pong, payload)
	sync.unlock(&connection.sendMutex)
	return sent
}

ConnectionHandleFrame :: proc(connection: ^Connection, frame: Frame, fragment: ^[dynamic]byte, fragmentOpcode: ^Opcode, fragmentActive: ^bool) -> bool {
	server := connection.server
	sync.lock(&connection.sendMutex)
	state := connection.state
	sync.unlock(&connection.sendMutex)
	if state == .Closed do return false
	if state == .Closing {
		switch frame.opcode {
		case .Ping:
			return ConnectionSendPong(connection, frame.payload)
		case .Pong:
			ConnectionRecordPong(connection, frame.payload)
			return true
		case .Close:
			ConnectionReplyClose(connection, frame.payload)
			return false
		case .Continuation, .Text, .Binary:
			return true
		}
	}
	switch frame.opcode {
	case .Text, .Binary:
		if fragmentActive^ {
			ConnectionSendClose(connection, 1002)
			return true
		}
		if len(frame.payload) > connection.maxMessageSize {
			ConnectionSendClose(connection, 1009)
			return true
		}
		if frame.final {
			if server.events.onMessage != nil do server.events.onMessage(server, connection.id, frame.opcode, frame.payload)
			return true
		}
		fragmentOpcode^ = frame.opcode
		fragmentActive^ = true
		append(fragment, ..frame.payload)
	case .Continuation:
		if !fragmentActive^ {
			ConnectionSendClose(connection, 1002)
			return true
		}
		if len(fragment^) + len(frame.payload) > connection.maxMessageSize {
			ConnectionSendClose(connection, 1009)
			return true
		}
		append(fragment, ..frame.payload)
		if frame.final {
			if fragmentOpcode^ == .Text && !IsValidUTF8(fragment^[:]) {
				ConnectionSendClose(connection, 1007)
				return true
			}
			if server.events.onMessage != nil do server.events.onMessage(server, connection.id, fragmentOpcode^, fragment^[:])
			clear(fragment)
			fragmentActive^ = false
		}
	case .Ping:
		if !ServerSendFrame(server, connection.id, .Pong, frame.payload) do return false
	case .Pong:
		ConnectionRecordPong(connection, frame.payload)
	case .Close:
		ConnectionReplyClose(connection, frame.payload)
		return false
	}
	return true
}
