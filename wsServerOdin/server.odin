package wsserver

import "core:net"
import "base:runtime"
import "core:sync"
import "core:thread"

MAX_HANDSHAKE_SIZE :: 16 * 1024
DEFAULT_MAX_CONNECTIONS :: 128
DEFAULT_MAX_MESSAGE_SIZE :: MAX_FRAME_LENGTH

ClientID :: distinct u64

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
	endpoint:        net.Endpoint,
	allocator:       runtime.Allocator,
	maxConnections:  int,
	maxFrameSize:    int,
	maxMessageSize:  int,
	events:          Events,
	mutex:           sync.Mutex,
	connections:     map[ClientID]^Connection,
	workers:         [dynamic]^thread.Thread,
	listener:        net.TCP_Socket,
	nextClientID:    u64,
	isRunning:       bool,
	stopping:        bool,
}

Connection :: struct {
	server:         ^Server,
	id:             ClientID,
	socket:         net.TCP_Socket,
	sendMutex:      sync.Mutex,
	closed:         bool,
	maxFrameSize:   int,
	maxMessageSize: int,
}

SocketReader :: struct {
	socket: net.TCP_Socket,
	buffer: [4096]byte,
	start:  int,
	end:    int,
}

ServerInit :: proc(server: ^Server, endpoint: net.Endpoint, events: Events, maxConnections: int = DEFAULT_MAX_CONNECTIONS, maxMessageSize: int = DEFAULT_MAX_MESSAGE_SIZE) -> ServerError {
	if maxConnections < 1 || maxMessageSize < 1 || maxMessageSize > MAX_FRAME_LENGTH do return .InvalidConfiguration

	server^ = {}
	server.endpoint = endpoint
	server.allocator = context.allocator
	server.maxConnections = maxConnections
	server.maxFrameSize = max(maxMessageSize, 125)
	server.maxMessageSize = maxMessageSize
	server.events = events
	server.connections = make(map[ClientID]^Connection, maxConnections, context.allocator)
	server.workers = make([dynamic]^thread.Thread, 0, maxConnections, context.allocator)
	server.nextClientID = 1
	return .None
}

ServerDeinit :: proc(server: ^Server) {
	assert(!server.isRunning && len(server.connections) == 0)
	delete(server.connections)
	delete(server.workers)
	server^ = {}
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

		clientSocket, _, acceptError := net.accept_tcp(listener)
		if acceptError != nil {
			sync.lock(&server.mutex)
			stopping = server.stopping
			sync.unlock(&server.mutex)
			if !stopping do result = .AcceptFailed
			break
		}

		ServerReapWorkers(server)
		sync.lock(&server.mutex)
		if server.stopping || len(server.connections) >= server.maxConnections {
			sync.unlock(&server.mutex)
			net.close(clientSocket)
			continue
		}

		connection := new(Connection, server.allocator)
		connection.server = server
		connection.socket = clientSocket
		connection.maxFrameSize = server.maxFrameSize
		connection.maxMessageSize = server.maxMessageSize
		connection.id = ClientID(server.nextClientID)
		server.nextClientID += 1
		if server.nextClientID == 0 do server.nextClientID = 1
		server.connections[connection.id] = connection

		worker := thread.create_and_start_with_data(rawptr(connection), ServerConnectionThread)
		if worker == nil {
			delete_key(&server.connections, connection.id)
			sync.unlock(&server.mutex)
			net.close(clientSocket)
			free(connection, server.allocator)
			result = .ThreadCreationFailed
			break
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
	defer sync.unlock(&connection.sendMutex)
	return ConnectionWriteFrameLocked(connection, opcode, payload)
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
	if connection.closed do return false
	encoded := make([]byte, len(payload) + 10, context.temp_allocator)
	defer delete(encoded, context.temp_allocator)
	written, encodeError := EncodeFrame(Frame{final = true, opcode = opcode, payload = payload}, encoded)
	if encodeError != .None do return false
	sent, sendError := net.send_tcp(connection.socket, encoded[:written])
	return sendError == nil && sent == written
}

ConnectionShutdown :: proc(connection: ^Connection) {
	sync.lock(&connection.sendMutex)
	if !connection.closed {
		connection.closed = true
		net.close(connection.socket)
		connection.socket = 0
	}
	sync.unlock(&connection.sendMutex)
}

ServerRemoveConnection :: proc(connection: ^Connection) {
	server := connection.server
	sync.lock(&server.mutex)
	delete_key(&server.connections, connection.id)
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
		ServerRemoveConnection(connection)
		if opened && connection.server.events.onClose != nil do connection.server.events.onClose(connection.server, connection.id)
		free(connection, connection.server.allocator)
	}

	reader := SocketReader{socket = connection.socket}
	request, requestSize, handshakeReadOK := SocketReaderReadHandshake(&reader)
	if !handshakeReadOK do return
	response, consumed, handshakeError := BuildHandshakeResponse(request[:requestSize])
	if handshakeError != .None || consumed != requestSize do return
	sent, sendError := net.send_tcp(connection.socket, response.bytes[:response.size])
	if sendError != nil || sent != response.size do return

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
			ConnectionSendClose(connection, closeCode)
			if storage != nil do delete(storage, context.temp_allocator)
			break
		}
		continueReading := ConnectionHandleFrame(connection, frame, &fragment, &fragmentOpcode, &fragmentActive)
		if storage != nil do delete(storage, context.temp_allocator)
		if !continueReading do break
	}
}

ConnectionSendClose :: proc(connection: ^Connection, code: u16) {
	payload := [?]byte{byte(code >> 8), byte(code)}
	_ = ServerSendFrame(connection.server, connection.id, .Close, payload[:])
}

ConnectionHandleFrame :: proc(connection: ^Connection, frame: Frame, fragment: ^[dynamic]byte, fragmentOpcode: ^Opcode, fragmentActive: ^bool) -> bool {
	server := connection.server
	switch frame.opcode {
	case .Text, .Binary:
		if fragmentActive^ {
			ConnectionSendClose(connection, 1002)
			return false
		}
		if len(frame.payload) > connection.maxMessageSize {
			ConnectionSendClose(connection, 1009)
			return false
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
			return false
		}
		if len(fragment^) + len(frame.payload) > connection.maxMessageSize {
			ConnectionSendClose(connection, 1009)
			return false
		}
		append(fragment, ..frame.payload)
		if frame.final {
			if fragmentOpcode^ == .Text && !IsValidUTF8(fragment^[:]) {
				ConnectionSendClose(connection, 1007)
				return false
			}
			if server.events.onMessage != nil do server.events.onMessage(server, connection.id, fragmentOpcode^, fragment^[:])
			clear(fragment)
			fragmentActive^ = false
		}
	case .Ping:
		if !ServerSendFrame(server, connection.id, .Pong, frame.payload) do return false
	case .Pong:
	case .Close:
		_ = ServerSendFrame(server, connection.id, .Close, frame.payload)
		return false
	}
	return true
}
