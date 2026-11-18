package wsserver

import "core:testing"

@(test)
TestWebSocketAcceptKey :: proc(t: ^testing.T) {
	accept, ok := WebSocketAcceptKey("dGhlIHNhbXBsZSBub25jZQ==")
	testing.expect(t, ok)
	testing.expect_value(t, string(accept[:]), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
	_, ok = WebSocketAcceptKey("dGhlIHNhbXBsZSBub25jZQ=A")
	testing.expect(t, !ok)
	_, ok = WebSocketAcceptKey("AAAAAAAAAAAAAAAAAAAAAA==")
	testing.expect(t, ok)
	_, ok = WebSocketAcceptKey("AAAAAAAAAAAAAAAAAAAAAB==")
	testing.expect(t, !ok)
}

@(test)
TestBuildHandshakeResponse :: proc(t: ^testing.T) {
	request := "GET /game HTTP/1.1\r\nHost: localhost\r\nUpgrade: WebSocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	bytes := transmute([]byte)request
	pipelined := make([]byte, len(bytes) + 2)
	defer delete(pipelined)
	copy(pipelined, bytes)
	pipelined[len(bytes)], pipelined[len(bytes) + 1] = 0x81, 0x00

	response, consumed, err := BuildHandshakeResponse(pipelined)
	testing.expect_value(t, err, HandshakeError.None)
	testing.expect_value(t, consumed, len(bytes))
	testing.expect_value(
		t,
		string(response.bytes[:response.size]),
		"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n",
	)

	badRequest := "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 12\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
	_, _, err = BuildHandshakeResponse(transmute([]byte)badRequest)
	testing.expect_value(t, err, HandshakeError.InvalidVersion)
}

@(test)
TestDecodeClientFrame :: proc(t: ^testing.T) {
	frameBytes := [?]byte{0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58}
	payload: [16]byte
	frame, consumed, err := DecodeFrame(frameBytes[:], payload[:])
	testing.expect_value(t, err, FrameError.None)
	testing.expect_value(t, consumed, len(frameBytes))
	testing.expect(t, frame.final && frame.opcode == .Text)
	testing.expect_value(t, string(frame.payload), "Hello")

	frameBytes[1] = 0x05
	_, _, err = DecodeFrame(frameBytes[:], payload[:])
	testing.expect_value(t, err, FrameError.UnmaskedClientFrame)
}

@(test)
TestEncodeServerFrame :: proc(t: ^testing.T) {
	message := [?]byte{'H', 'e', 'l', 'l', 'o'}
	frame := Frame{final = true, opcode = .Text, payload = message[:]}
	encoded: [32]byte
	written, err := EncodeFrame(frame, encoded[:])
	testing.expect_value(t, err, FrameError.None)
	testing.expect_value(t, string(encoded[:written]), "\x81\x05Hello")

	ping := Frame{final = false, opcode = .Ping}
	_, err = EncodeFrame(ping, encoded[:])
	testing.expect_value(t, err, FrameError.InvalidControlFrame)

	invalidText := [?]byte{0xc0, 0xaf}
	_, err = EncodeFrame(Frame{final = true, opcode = .Text, payload = invalidText[:]}, encoded[:])
	testing.expect_value(t, err, FrameError.InvalidUTF8)
}

@(test)
TestExtendedLengthFrames :: proc(t: ^testing.T) {
	clientFrame: [134]byte
	clientFrame[0], clientFrame[1] = 0x82, 0xfe
	clientFrame[2], clientFrame[3] = 0, 126
	for i := 0; i < 126; i += 1 do clientFrame[8 + i] = byte(i)
	clientPayload: [126]byte
	frame, consumed, err := DecodeFrame(clientFrame[:], clientPayload[:])
	testing.expect_value(t, err, FrameError.None)
	testing.expect_value(t, consumed, len(clientFrame))
	testing.expect_value(t, len(frame.payload), 126)
	testing.expect_value(t, frame.payload[125], byte(125))

	serverPayload: [126]byte
	serverFrame: [140]byte
	written, encodeErr := EncodeFrame(Frame{final = true, opcode = .Binary, payload = serverPayload[:]}, serverFrame[:])
	testing.expect_value(t, encodeErr, FrameError.None)
	testing.expect_value(t, written, 130)
	testing.expect_value(t, serverFrame[1], byte(126))
	testing.expect_value(t, serverFrame[2], byte(0))
	testing.expect_value(t, serverFrame[3], byte(126))
}

@(test)
TestUTF8Validation :: proc(t: ^testing.T) {
	valid := [?]byte{'R', 'I', 'F', 'T', 0xf0, 0x9f, 0x8c, 0x8c}
	invalid := [?]byte{0xc0, 0xaf}
	testing.expect(t, IsValidUTF8(valid[:]))
	testing.expect(t, !IsValidUTF8(invalid[:]))
}
