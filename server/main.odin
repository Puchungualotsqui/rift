package server

import http "../odin-http"
import ws "../wsServer"
import "core:fmt"
import "core:log"
import "core:net"
import "core:os"
import "core:sync"
import "core:thread"
import "core:strings"

PORT :: 6969
DATABASE_PATH :: "rift.sqlite"

App :: struct {
	database: ^Database,
	network:  NetworkState,
}

APIError :: struct {
	code:    string `json:"code"`,
	message: string `json:"message"`,
}

AuthResponse :: struct {
	sessionToken: string `json:"session_token"`,
	playerId:     i64    `json:"player_id"`,
	displayName:  string `json:"display_name"`,
	expiresAt:    i64    `json:"expires_at"`,
}

HealthResponse :: struct {
	status: string `json:"status"`,
}

LogoutResponse :: struct {
	ok: bool `json:"ok"`,
}

main :: proc() {
	context.logger = log.create_console_logger(.Info)

	database: Database
	if !DatabaseInit(&database, DATABASE_PATH) {
		panic("Could not initialize the RIFT database")
	}
	app := App{database = &database}
	NetworkInit(&app.network)
	wsInitError := ws.ServerInit(
		&app.network.websocket,
		{address = net.IP4_Loopback, port = WS_PORT},
		ws.Events{onOpen = WsOnOpen, onClose = WsOnClose, onMessage = WsOnMessage},
		maxConnections = MAX_WS_CONNECTIONS,
		maxMessageSize = MAX_WS_MESSAGE_BYTES,
		userContext = rawptr(&app),
	)
	if wsInitError != .None {
		NetworkDeinit(&app.network)
		DatabaseDeinit(&database)
		panic("Could not initialize the WebSocket server")
	}
	wsWorker := thread.create_and_start_with_poly_data(&app, WsServerThread)
	if wsWorker == nil {
		ws.ServerDeinit(&app.network.websocket)
		NetworkDeinit(&app.network)
		DatabaseDeinit(&database)
		panic("Could not start the WebSocket server thread")
	}
	authTimeoutWorker := thread.create_and_start_with_poly_data(&app, WsAuthTimeoutThread)
	if authTimeoutWorker == nil {
		sync.lock(&app.network.mutex)
		app.network.shuttingDown = true
		sync.unlock(&app.network.mutex)
		ws.ServerStop(&app.network.websocket)
		thread.join(wsWorker)
		thread.destroy(wsWorker)
		ws.ServerDeinit(&app.network.websocket)
		NetworkDeinit(&app.network)
		DatabaseDeinit(&database)
		panic("Could not start the WebSocket auth timeout thread")
	}
	handler := http.Handler{
		user_data = &app,
		handle = HandleRequest,
	}

	server: http.Server
	http.server_shutdown_on_interrupt(&server)
	endpoint := net.Endpoint{address = net.IP4_Loopback, port = PORT}
	log.infof("Listening on http://127.0.0.1:%d", PORT)
	if err := http.listen_and_serve(&server, handler, endpoint); err != nil {
		fmt.eprintln("HTTP server stopped with error: ", err)
	}
	sync.lock(&app.network.mutex)
	app.network.shuttingDown = true
	sync.unlock(&app.network.mutex)
	ws.ServerStop(&app.network.websocket)
	thread.join(wsWorker)
	thread.destroy(wsWorker)
	thread.join(authTimeoutWorker)
	thread.destroy(authTimeoutWorker)
	ws.ServerDeinit(&app.network.websocket)
	NetworkDeinit(&app.network)
	DatabaseDeinit(&database)
	os.exit(0)
}

HandleRequest :: proc(handler: ^http.Handler, request: ^http.Request, response: ^http.Response) {
	app := cast(^App)handler.user_data
	requestLine := request.line.(http.Requestline)

	switch request.url.path {
	case "/health":
		if requestLine.method != .Get {
			SendError(response, .Method_Not_Allowed, "method_not_allowed", "Use GET for this endpoint")
			return
		}
		SendJSON(response, HealthResponse{"ok"})
	case "/auth/guest":
		if requestLine.method != .Post {
			SendError(response, .Method_Not_Allowed, "method_not_allowed", "Use POST for this endpoint")
			return
		}
		HandleGuestAuth(app, response)
	case "/me":
		if requestLine.method != .Get {
			SendError(response, .Method_Not_Allowed, "method_not_allowed", "Use GET for this endpoint")
			return
		}
		HandleMe(app, request, response)
	case "/auth/logout":
		if requestLine.method != .Post {
			SendError(response, .Method_Not_Allowed, "method_not_allowed", "Use POST for this endpoint")
			return
		}
		HandleLogout(app, request, response)
	case:
		SendError(response, .Not_Found, "not_found", "Endpoint not found")
	}
}

HandleGuestAuth :: proc(app: ^App, response: ^http.Response) {
	session, ok := DatabaseCreateGuestSession(app.database)
	if !ok {
		SendError(response, .Internal_Server_Error, "server_error", "Could not create a guest session")
		return
	}

	SendJSON(response, AuthResponse{
		sessionToken = session.sessionToken,
		playerId = session.playerId,
		displayName = session.displayName,
		expiresAt = session.expiresAt,
	}, .Created)
}

HandleMe :: proc(app: ^App, request: ^http.Request, response: ^http.Response) {
	token, hasToken := RequestSessionToken(request)
	if !hasToken {
		SendError(response, .Unauthorized, "unauthorized", "A bearer session token is required")
		return
	}

	profile, authenticated := DatabaseAuthenticate(app.database, token)
	if !authenticated {
		SendError(response, .Unauthorized, "unauthorized", "The session is invalid or expired")
		return
	}

	SendJSON(response, profile)
}

HandleLogout :: proc(app: ^App, request: ^http.Request, response: ^http.Response) {
	token, hasToken := RequestSessionToken(request)
	if !hasToken {
		SendError(response, .Unauthorized, "unauthorized", "A bearer session token is required")
		return
	}

	_, authenticated := DatabaseAuthenticate(app.database, token)
	if !authenticated {
		SendError(response, .Unauthorized, "unauthorized", "The session is invalid or expired")
		return
	}
	if !DatabaseRevokeSession(app.database, token) {
		SendError(response, .Internal_Server_Error, "server_error", "Could not revoke the session")
		return
	}

	SendJSON(response, LogoutResponse{true})
}

RequestSessionToken :: proc(request: ^http.Request) -> (token: string, ok: bool) {
	authorization, hasHeader := http.headers_get(request.headers, "authorization")
	if !hasHeader || !strings.has_prefix(authorization, "Bearer ") do return
	token = authorization[len("Bearer "):]
	if len(token) != 64 do return "", false
	return token, true
}

SendError :: proc(response: ^http.Response, status: http.Status, code, message: string) {
	SendJSON(response, APIError{code, message}, status)
}

SendJSON :: proc(response: ^http.Response, value: any, status: http.Status = .OK) {
	http.headers_set_unsafe(&response.headers, "cache-control", "no-store")
	if err := http.respond_json(response, value, status); err != nil {
		log.errorf("Could not encode HTTP JSON response: %s", err)
	}
}
