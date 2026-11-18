package wsserver

import sha1 "core:crypto/legacy/sha1"

WEBSOCKET_GUID :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_FRAME_LENGTH :: 16 * 1024 * 1024

Opcode :: enum u8 {
	Continuation = 0x0,
	Text         = 0x1,
	Binary       = 0x2,
	Close        = 0x8,
	Ping         = 0x9,
	Pong         = 0xa,
}

FrameError :: enum {
	None,
	NeedMoreData,
	NeedMoreBuffer,
	InvalidOpcode,
	InvalidReservedBits,
	UnmaskedClientFrame,
	InvalidLength,
	FrameTooLarge,
	InvalidControlFrame,
	InvalidCloseFrame,
	InvalidUTF8,
}

HandshakeError :: enum {
	None,
	IncompleteRequest,
	InvalidRequestLine,
	MalformedHeader,
	MissingRequiredHeader,
	InvalidUpgrade,
	InvalidVersion,
	InvalidKey,
}

Frame :: struct {
	final:   bool,
	opcode:  Opcode,
	payload: []byte,
}

HandshakeResponse :: struct {
	bytes: [256]byte,
	size:  int,
}

Base64Value :: proc(value: byte) -> (decoded: byte, ok: bool) {
	switch value {
	case 'A'..='Z':
		return value - 'A', true
	case 'a'..='z':
		return value - 'a' + 26, true
	case '0'..='9':
		return value - '0' + 52, true
	case '+':
		return 62, true
	case '/':
		return 63, true
	case:
		return 0, false
	}
}

WebSocketAcceptKey :: proc(key: string) -> (accept: [28]byte, ok: bool) {
	if len(key) != 24 || key[22] != '=' || key[23] != '=' do return

	for i := 0; i < 22; i += 1 {
		_, valid := Base64Value(key[i])
		if !valid do return
	}
	lastValue, valid := Base64Value(key[21])
	if !valid || lastValue & 0x0f != 0 do return

	input: [60]byte
	guid := WEBSOCKET_GUID
	for i := 0; i < len(key); i += 1 do input[i] = key[i]
	for i := 0; i < len(guid); i += 1 do input[len(key) + i] = guid[i]

	digest: [sha1.DIGEST_SIZE]byte
	hash: sha1.Context
	sha1.init(&hash)
	sha1.update(&hash, input[:])
	sha1.final(&hash, digest[:])

	alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	out := 0
	for i := 0; i < len(digest); i += 3 {
		remaining := len(digest) - i
		first := digest[i]
		second: byte = 0
		third: byte = 0
		if remaining > 1 do second = digest[i + 1]
		if remaining > 2 do third = digest[i + 2]

		accept[out] = alphabet[first >> 2]
		accept[out + 1] = alphabet[((first & 0x03) << 4) | (second >> 4)]
		accept[out + 2] = remaining > 1 ? alphabet[((second & 0x0f) << 2) | (third >> 6)] : '='
		accept[out + 3] = remaining > 2 ? alphabet[third & 0x3f] : '='
		out += 4
	}
	return accept, true
}

AsciiEqualCaseInsensitive :: proc(left: []byte, right: string) -> bool {
	if len(left) != len(right) do return false
	for i in 0..<len(left) {
		a, b := left[i], right[i]
		if a >= 'A' && a <= 'Z' do a += 'a' - 'A'
		if b >= 'A' && b <= 'Z' do b += 'a' - 'A'
		if a != b do return false
	}
	return true
}

TrimHeaderValue :: proc(value: []byte) -> []byte {
	start, end := 0, len(value)
	for start < end && (value[start] == ' ' || value[start] == '\t') do start += 1
	for end > start && (value[end - 1] == ' ' || value[end - 1] == '\t') do end -= 1
	return value[start:end]
}

FindCRLF :: proc(data: []byte, start: int) -> (position: int, found: bool) {
	for i := start; i + 1 < len(data); i += 1 {
		if data[i] == '\r' && data[i + 1] == '\n' do return i, true
	}
	return 0, false
}


HeaderHasToken :: proc(value: []byte, token: string) -> bool {
	start := 0
	for start <= len(value) {
		end := start
		for end < len(value) && value[end] != ',' do end += 1
		if AsciiEqualCaseInsensitive(TrimHeaderValue(value[start:end]), token) do return true
		if end == len(value) do break
		start = end + 1
	}
	return false
}

AppendResponseText :: proc(response: ^HandshakeResponse, value: string) -> bool {
	if response.size + len(value) > len(response.bytes) do return false
	for i := 0; i < len(value); i += 1 do response.bytes[response.size + i] = value[i]
	response.size += len(value)
	return true
}

BuildHandshakeResponse :: proc(request: []byte) -> (response: HandshakeResponse, consumed: int, err: HandshakeError) {
	lineEnd, complete := FindCRLF(request, 0)
	if !complete do return response, 0, .IncompleteRequest
	requestLine := request[:lineEnd]
	firstSpace, secondSpace := -1, -1
	for ch, i in requestLine {
		if ch == ' ' {
			if firstSpace < 0 {
				firstSpace = i
			} else {
				secondSpace = i
				break
			}
		}
	}
	if firstSpace <= 0 || secondSpace <= firstSpace + 1 || secondSpace == len(requestLine) - 1 do return response, 0, .InvalidRequestLine
	if !AsciiEqualCaseInsensitive(requestLine[:firstSpace], "GET") || !AsciiEqualCaseInsensitive(requestLine[secondSpace + 1:], "HTTP/1.1") do return response, 0, .InvalidRequestLine

	required: [5][]byte
	found: [5]bool
	duplicate: [5]bool
	headerNames := [?]string{"Host", "Upgrade", "Connection", "Sec-WebSocket-Version", "Sec-WebSocket-Key"}
	position := lineEnd + 2
	for {
		headerEnd, hasHeaderEnd := FindCRLF(request, position)
		if !hasHeaderEnd do return response, 0, .IncompleteRequest
		if headerEnd == position {
			consumed = headerEnd + 2
			break
		}
		line := request[position:headerEnd]
		colon := -1
		for ch, i in line {
			if ch == ':' {
				colon = i
				break
			}
		}
		if colon <= 0 do return response, 0, .MalformedHeader
		for i in 0..<len(headerNames) {
			if AsciiEqualCaseInsensitive(line[:colon], headerNames[i]) {
				if found[i] {
					duplicate[i] = true
				} else {
					required[i] = TrimHeaderValue(line[colon + 1:])
					found[i] = true
				}
			}
		}
		position = headerEnd + 2
	}

	for i := 0; i < len(found); i += 1 {
		if !found[i] || duplicate[i] do return response, 0, .MissingRequiredHeader
	}
	if len(required[0]) == 0 || !AsciiEqualCaseInsensitive(required[1], "websocket") || !HeaderHasToken(required[2], "Upgrade") do return response, 0, .InvalidUpgrade
	if string(required[3]) != "13" do return response, 0, .InvalidVersion
	accept, keyValid := WebSocketAcceptKey(string(required[4]))
	if !keyValid do return response, 0, .InvalidKey

	if !AppendResponseText(&response, "HTTP/1.1 101 Switching Protocols\r\n") ||
		!AppendResponseText(&response, "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ") {
		return response, 0, .MalformedHeader
	}
	if response.size + len(accept) + 4 > len(response.bytes) do return response, 0, .MalformedHeader
	copy(response.bytes[response.size:], accept[:])
	response.size += len(accept)
	_ = AppendResponseText(&response, "\r\n\r\n")
	return response, consumed, .None
}

DecodeOpcode :: proc(value: byte) -> (opcode: Opcode, ok: bool) {
	switch value {
	case 0x0: return .Continuation, true
	case 0x1: return .Text, true
	case 0x2: return .Binary, true
	case 0x8: return .Close, true
	case 0x9: return .Ping, true
	case 0xa: return .Pong, true
	case: return .Continuation, false
	}
}

IsControlOpcode :: proc(opcode: Opcode) -> bool {
	return opcode == .Close || opcode == .Ping || opcode == .Pong
}

ValidCloseCode :: proc(code: u16) -> bool {
	if code >= 3000 && code <= 4999 do return true
	return code == 1000 || code == 1001 || code == 1002 || code == 1003 ||
		code == 1007 || code == 1008 || code == 1009 || code == 1010 ||
		code == 1011 || code == 1012 || code == 1013 || code == 1014
}

DecodeFrame :: proc(data, payloadBuffer: []byte) -> (frame: Frame, consumed: int, err: FrameError) {
	if len(data) < 2 do return frame, 0, .NeedMoreData
	first, second := data[0], data[1]
	if first & 0x70 != 0 do return frame, 0, .InvalidReservedBits
	opcode, validOpcode := DecodeOpcode(first & 0x0f)
	if !validOpcode do return frame, 0, .InvalidOpcode
	final := first & 0x80 != 0
	if second & 0x80 == 0 do return frame, 0, .UnmaskedClientFrame

	length := u64(second & 0x7f)
	headerSize := 2
	if length == 126 {
		if len(data) < 4 do return frame, 0, .NeedMoreData
		length = u64(data[2]) << 8 | u64(data[3])
		if length < 126 do return frame, 0, .InvalidLength
		headerSize = 4
	} else if length == 127 {
		if len(data) < 10 do return frame, 0, .NeedMoreData
		if data[2] & 0x80 != 0 do return frame, 0, .InvalidLength
		length = 0
		for i := 2; i < 10; i += 1 do length = (length << 8) | u64(data[i])
		if length <= 0xffff do return frame, 0, .InvalidLength
		headerSize = 10
	}
	if length > MAX_FRAME_LENGTH do return frame, 0, .FrameTooLarge
	if IsControlOpcode(opcode) && (!final || length > 125) do return frame, 0, .InvalidControlFrame
	if opcode == .Close && length == 1 do return frame, 0, .InvalidCloseFrame
	if len(data) < headerSize + 4 do return frame, 0, .NeedMoreData
	if length > u64(len(data) - headerSize - 4) do return frame, 0, .NeedMoreData
	if length > u64(len(payloadBuffer)) do return frame, 0, .NeedMoreBuffer

	maskOffset := headerSize
	payloadOffset := maskOffset + 4
	payloadSize := int(length)
	mask := data[maskOffset:payloadOffset]
	for i := 0; i < payloadSize; i += 1 {
		payloadBuffer[i] = data[payloadOffset + i] ~ mask[i & 3]
	}

	payload := payloadBuffer[:payloadSize]
	if opcode == .Text && final && !IsValidUTF8(payload) do return frame, 0, .InvalidUTF8
	if opcode == .Close && payloadSize >= 2 {
		closeCode := u16(payload[0]) << 8 | u16(payload[1])
		if !ValidCloseCode(closeCode) || (payloadSize > 2 && !IsValidUTF8(payload[2:])) do return frame, 0, .InvalidCloseFrame
	}

	frame = Frame{final = final, opcode = opcode, payload = payload}
	consumed = payloadOffset + payloadSize
	return frame, consumed, .None
}

EncodeFrame :: proc(frame: Frame, destination: []byte) -> (written: int, err: FrameError) {
	switch frame.opcode {
	case .Continuation, .Text, .Binary, .Close, .Ping, .Pong:
	case:
		return 0, .InvalidOpcode
	}
	payloadSize := len(frame.payload)
	if payloadSize > MAX_FRAME_LENGTH do return 0, .FrameTooLarge
	if IsControlOpcode(frame.opcode) && (!frame.final || payloadSize > 125) do return 0, .InvalidControlFrame
	if frame.opcode == .Close {
		if payloadSize == 1 do return 0, .InvalidCloseFrame
		if payloadSize >= 2 {
			closeCode := u16(frame.payload[0]) << 8 | u16(frame.payload[1])
			if !ValidCloseCode(closeCode) || (payloadSize > 2 && !IsValidUTF8(frame.payload[2:])) do return 0, .InvalidCloseFrame
		}
	}
	if frame.opcode == .Text && frame.final && !IsValidUTF8(frame.payload) do return 0, .InvalidUTF8

	headerSize := 2
	if payloadSize >= 126 && payloadSize <= 0xffff do headerSize = 4
	if payloadSize > 0xffff do headerSize = 10
	if len(destination) < headerSize + payloadSize do return 0, .NeedMoreBuffer

	destination[0] = (frame.final ? 0x80 : 0) | byte(frame.opcode)
	if payloadSize < 126 {
		destination[1] = byte(payloadSize)
	} else if payloadSize <= 0xffff {
		destination[1] = 126
		destination[2] = byte(payloadSize >> 8)
		destination[3] = byte(payloadSize)
	} else {
		destination[1] = 127
		for i := 0; i < 8; i += 1 do destination[2 + i] = byte(u64(payloadSize) >> u64(56 - 8 * i))
	}
	copy(destination[headerSize:], frame.payload)
	return headerSize + payloadSize, .None
}

IsValidUTF8 :: proc(data: []byte) -> bool {
	for i := 0; i < len(data); {
		first := data[i]
		if first <= 0x7f {
			i += 1
			continue
		}
		if first >= 0xc2 && first <= 0xdf {
			if i + 1 >= len(data) || data[i + 1] < 0x80 || data[i + 1] > 0xbf do return false
			i += 2
			continue
		}
		if first >= 0xe0 && first <= 0xef {
			if i + 2 >= len(data) do return false
			second, third := data[i + 1], data[i + 2]
			if third < 0x80 || third > 0xbf do return false
			if first == 0xe0 {
				if second < 0xa0 || second > 0xbf do return false
			} else if first == 0xed {
				if second < 0x80 || second > 0x9f do return false
			} else if second < 0x80 || second > 0xbf {
				return false
			}
			i += 3
			continue
		}
		if first >= 0xf0 && first <= 0xf4 {
			if i + 3 >= len(data) do return false
			second, third, fourth := data[i + 1], data[i + 2], data[i + 3]
			if third < 0x80 || third > 0xbf || fourth < 0x80 || fourth > 0xbf do return false
			if first == 0xf0 {
				if second < 0x90 || second > 0xbf do return false
			} else if first == 0xf4 {
				if second < 0x80 || second > 0x8f do return false
			} else if second < 0x80 || second > 0xbf {
				return false
			}
			i += 4
			continue
		}
		return false
	}
	return true
}
