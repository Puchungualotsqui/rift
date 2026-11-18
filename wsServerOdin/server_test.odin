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
TestServerHandshakeAndEcho :: proc(t: ^testing.T) {
	server: Server
	initError := ServerInit(
		&server,
		{address = net.IP4_Loopback, port = 0},
		Events{onMessage = TestEchoMessage},
		maxConnections = 4,
		maxMessageSize = 1024,
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
}
