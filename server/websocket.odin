package server

import logic "../logicEngine"
import ws "../wsServer"
import "core:encoding/json"

import "core:log"
import "core:strings"
import "core:sync"
import "core:time"

WS_PORT :: 6970
MAX_WS_CONNECTIONS :: 0
MAX_WS_MESSAGE_BYTES :: 16 * 1024
MAX_CHAT_BYTES :: 500
WS_AUTH_TIMEOUT :: 10 * time.Second
WS_AUTH_TIMEOUT_CHECK_INTERVAL :: 250 * time.Millisecond

LobbyUpdateWire :: struct {
	players: []LobbyPlayerWire `json:"players"`,
}

WsServerThread :: proc(app: ^App) {
	log.infof("WebSocket listener starting on 127.0.0.1:%d", WS_PORT)
	result := ws.ServerRun(&app.network.websocket)
	if result != .None do log.errorf("WebSocket listener stopped with status %v", result)
}

WsAuthTimeoutThread :: proc(app: ^App) {
	clients := make([dynamic]WsClient, 0, ws.DEFAULT_MAX_CONNECTIONS, app.network.allocator)
	defer delete(clients)
	for {
		time.sleep(WS_AUTH_TIMEOUT_CHECK_INTERVAL)
		clear(&clients)
		now := time.tick_now()
		sync.lock(&app.network.mutex)
		if app.network.shuttingDown {
			sync.unlock(&app.network.mutex)
			return
		}
		NetworkProcessMatchDeadlines(app, now)
		for client, connection in app.network.connections {
			elapsed := time.tick_diff(connection.openedAt, now)
			if !connection.authenticated && !connection.authTimedOut && elapsed >= app.network.authTimeout do append(&clients, client)
		}
		for client in clients {
			connection, exists := app.network.connections[client]
			if exists && !connection.authenticated {
				connection.authTimedOut = true
				app.network.connections[client] = connection
			}
		}
		sync.unlock(&app.network.mutex)
		for client in clients do WsCloseClient(client)
	}
}

NetworkStartReconnectGrace :: proc(network: ^NetworkState, match: ^Match, now: time.Tick) {
	if match.status != .Started || match.game.phase != .Acting do return
	seat := match.game.currentPlayer
	if seat < 0 || seat >= match.playerCount do return
	player := &match.players[seat]
	if player.connected || player.reconnectGraceActive do return

	remaining := network.maxReconnectGrace - player.reconnectGraceSpent
	if remaining < 0 do remaining = 0
	duration := network.turnReconnectGrace
	if duration > remaining do duration = remaining
	player.reconnectGraceStartedAt = now
	player.reconnectGraceDuration = duration
	player.reconnectGraceActive = true
}

NetworkAccountReconnectGrace :: proc(network: ^NetworkState, player: ^MatchPlayer, now: time.Tick) {
	if !player.reconnectGraceActive do return
	elapsed := time.tick_diff(player.reconnectGraceStartedAt, now)
	if elapsed > player.reconnectGraceDuration do elapsed = player.reconnectGraceDuration
	player.reconnectGraceSpent += elapsed
	if player.reconnectGraceSpent > network.maxReconnectGrace do player.reconnectGraceSpent = network.maxReconnectGrace
	player.reconnectGraceActive = false
}

NetworkProcessMatchDeadlines :: proc(app: ^App, now: time.Tick) {
	network := &app.network
	matchIndex := 0
	for matchIndex < len(network.matches) {
		match := &network.matches[matchIndex]
		switch match.status {
		case .Waiting:
			removedPlayer := false
			seat := 0
			for seat < match.playerCount {
				player := &match.players[seat]
				if player.hasDisconnectedAt && time.tick_diff(player.disconnectedAt, now) >= network.waitingDisconnectTimeout {
					if len(player.displayName) > 0 do delete(player.displayName, network.allocator)
					for move := seat; move < match.playerCount - 1; move += 1 {
						match.players[move] = match.players[move + 1]
					}
					match.playerCount -= 1
					match.players[match.playerCount] = {}
					removedPlayer = true
				} else {
					seat += 1
				}
			}
			if removedPlayer {
				if match.playerCount == 0 {
					unordered_remove(&network.matches, matchIndex)
					continue
				}
				NetworkSendReadyUpdate(match, NO_WS_CLIENT, 0)
			}
		case .Started:
			NetworkStartReconnectGrace(network, match, now)
			seat := match.game.currentPlayer
			if seat >= 0 && seat < match.playerCount {
				player := &match.players[seat]
				if !player.connected && player.reconnectGraceActive &&
					time.tick_diff(player.reconnectGraceStartedAt, now) >= player.reconnectGraceDuration {
					forfeitBy := player.playerId
					before := match.game
					match.game.phase = .Finished
					if !NetworkFinalizeMatch(app, matchIndex, forfeitBy, NO_WS_CLIENT, 0) {
						match.game = before
						if !player.reconnectGraceFailureLogged {
							log.errorf("Could not finalize match %d after player %d reconnect grace expired", match.id, forfeitBy)
							player.reconnectGraceFailureLogged = true
						}
					} else {
						continue
					}
				}
			}
		case .Finished:
		}
		matchIndex += 1
	}
}

WsSend :: proc(client: WsClient, op: string, seq: i64, data: $T) {
	envelope := ServerEnvelope(T){
		op = op,
		seq = seq,
		ts = time.to_unix_seconds(time.now()),
		data = data,
	}
	payload, err := json.marshal(envelope, allocator = context.temp_allocator)
	if err != nil {
		log.errorf("Could not encode WebSocket %s message: %s", op, err)
		return
	}
	if !ws.ServerSendFrame(client.server, client.id, .Text, payload) do log.warnf("Could not send WebSocket %s message", op)
}

WsSendError :: proc(client: WsClient, seq: i64, code, message: string) {
	WsSend(client, "error", seq, GenericErrorWire{code, message})
}

WsSendActionError :: proc(client: WsClient, seq: i64, reason: string) {
	WsSend(client, "game.action_err", seq, ActionErrorWire{seq, reason})
}

WsCloseClient :: proc(client: WsClient) {
	if !ws.ServerCloseClient(client.server, client.id) do log.warnf("Could not begin WebSocket close for client %d", u64(client.id))
}

WsOnOpen :: proc(server: ^ws.Server, clientID: ws.ClientID) {
	app := cast(^App)ws.ServerGetContext(server)
	client := WsClient{server = server, id = clientID}
	sync.lock(&app.network.mutex)
	app.network.connections[client] = WsConnection{openedAt = time.tick_now(), lastSequence = -1}
	sync.unlock(&app.network.mutex)
}

WsOnClose :: proc(server: ^ws.Server, clientID: ws.ClientID) {
	app := cast(^App)ws.ServerGetContext(server)
	client := WsClient{server = server, id = clientID}
	sync.lock(&app.network.mutex)

	connection, exists := app.network.connections[client]
	if !exists {
		sync.unlock(&app.network.mutex)
		return
	}

	if connection.authenticated {
		NetworkRemoveLobbyPlayer(&app.network, connection.playerId, client)
		matchIndex := NetworkPlayerMatchIndex(&app.network, connection.playerId)
		if matchIndex >= 0 {
			match := &app.network.matches[matchIndex]
			seat := NetworkMatchPlayerIndex(match, connection.playerId)
			if seat >= 0 && match.players[seat].connection == client {
				player := &match.players[seat]
				player.connected = false
				player.connection = NO_WS_CLIENT
				player.disconnectedAt = time.tick_now()
				player.hasDisconnectedAt = true
				if match.status == .Waiting {
					player.ready = false
					NetworkSendReadyUpdate(match, NO_WS_CLIENT, 0)
				} else if match.status == .Started {
					NetworkStartReconnectGrace(&app.network, match, time.tick_now())
					NetworkSendMatchState(match, NO_WS_CLIENT, 0)
				}
			}
		}
		if len(connection.sessionToken) > 0 do delete(connection.sessionToken, app.network.allocator)
		if len(connection.displayName) > 0 do delete(connection.displayName, app.network.allocator)
		NetworkBroadcastLobbyUpdate(&app.network)
	}
	delete_key(&app.network.connections, client)
	sync.unlock(&app.network.mutex)
}

WsOnMessage :: proc(server: ^ws.Server, clientID: ws.ClientID, opcode: ws.Opcode, message: []byte) {
	app := cast(^App)ws.ServerGetContext(server)
	client := WsClient{server = server, id = clientID}
	if opcode != .Text {
		WsSendError(client, 0, "invalid_frame", "Only text JSON frames are supported")
		WsCloseClient(client)
		return
	}
	if len(message) == 0 || len(message) > MAX_WS_MESSAGE_BYTES {
		WsSendError(client, 0, "invalid_message_size", "WebSocket message size is invalid")
		WsCloseClient(client)
		return
	}

	request: WsClientMessage
	request.data.attackerCard = logic.NO_CARD
	request.data.defenderCard = logic.NO_CARD
	if err := json.unmarshal(message, &request, allocator = context.temp_allocator); err != nil {
		WsSendError(client, 0, "invalid_json", "Message must be a valid RIFT JSON envelope")
		return
	}
	if request.seq < 0 || request.op == "" {
		WsSendError(client, request.seq, "invalid_envelope", "Message requires an op and non-negative seq")
		return
	}

	sync.lock(&app.network.mutex)
	defer sync.unlock(&app.network.mutex)
	if app.network.shuttingDown {
		WsSendError(client, request.seq, "server_shutting_down", "The server is shutting down")
		return
	}
	connection, exists := app.network.connections[client]
	if !exists {
		WsSendError(client, request.seq, "unknown_connection", "Connection state is unavailable")
		WsCloseClient(client)
		return
	}
	if connection.authTimedOut do return
	if request.seq <= connection.lastSequence {
		WsSendError(client, request.seq, "stale_sequence", "seq must increase for every client message")
		return
	}
	connection.lastSequence = request.seq
	app.network.connections[client] = connection

	if request.op == "auth" {
		if connection.authenticated {
			WsSendError(client, request.seq, "already_authenticated", "Connection is already authenticated")
			return
		}
		if len(request.data.token) != 64 {
			WsSendError(client, request.seq, "unauthorized", "A valid session token is required")
			WsCloseClient(client)
			return
		}
		profile, authenticated := DatabaseAuthenticate(app.database, request.data.token)
		if !authenticated {
			WsSendError(client, request.seq, "unauthorized", "The session is invalid or expired")
			WsCloseClient(client)
			return
		}
		connection.authenticated = true
		connection.playerId = profile.playerId
		connection.sessionToken = strings.clone(request.data.token, app.network.allocator)
		connection.displayName = strings.clone(profile.displayName, app.network.allocator)
		app.network.connections[client] = connection
		WsSend(client, "auth.ok", request.seq, AuthOkWire{profile.playerId, profile.displayName})
		NetworkAttachPlayer(app, client, &connection)
		return
	}

	if !connection.authenticated {
		WsSendError(client, request.seq, "unauthorized", "Send auth with a valid bearer token first")
		return
	}
	if _, authenticated := DatabaseAuthenticate(app.database, connection.sessionToken); !authenticated {
		WsSendError(client, request.seq, "unauthorized", "The session is invalid or expired")
		WsCloseClient(client)
		return
	}
	app.network.connections[client] = connection

	switch request.op {
	case "lobby.join":
		NetworkLobbyJoin(app, client, &connection, request.seq)
	case "lobby.leave":
		NetworkRemoveLobbyPlayer(&app.network, connection.playerId, client)
		connection.matchId = 0
		app.network.connections[client] = connection
		NetworkBroadcastLobbyUpdate(&app.network)
	case "match.create":
		NetworkMatchCreate(app, client, &connection, request.data, request.seq)
	case "match.join":
		NetworkMatchJoin(app, client, &connection, request.data.matchId, request.seq)
	case "match.ready":
		NetworkMatchReady(app, client, &connection, request.data.ready, request.seq)
	case "game.action":
		NetworkGameAction(app, client, &connection, request.data, request.seq)
	case "game.end_turn":
		NetworkEndTurn(app, client, &connection, request.seq)

	case "game.forfeit":
		NetworkForfeit(app, client, &connection, request.seq)
	case "chat":
		NetworkChat(&app.network, client, &connection, request.data.text, request.seq)
	case:
		WsSendError(client, request.seq, "unknown_op", "Unsupported WebSocket operation")
	}
}

NetworkAttachPlayer :: proc(app: ^App, client: WsClient, connection: ^WsConnection) {
	network := &app.network
	NetworkProcessMatchDeadlines(app, time.tick_now())
	for i in 0..<len(network.lobby) {
		if network.lobby[i].playerId == connection.playerId {
			network.lobby[i].connection = client
		}
	}
	matchIndex := NetworkPlayerMatchIndex(network, connection.playerId)
	if matchIndex >= 0 {
		match := &network.matches[matchIndex]
		seat := NetworkMatchPlayerIndex(match, connection.playerId)
		if seat >= 0 {
			player := &match.players[seat]
			graceExpired := player.reconnectGraceActive &&
				time.tick_diff(player.reconnectGraceStartedAt, time.tick_now()) >= player.reconnectGraceDuration
			if !graceExpired {
				if player.reconnectGraceActive do NetworkAccountReconnectGrace(network, player, time.tick_now())
				player.connection = client
				player.connected = true
				player.hasDisconnectedAt = false
				player.reconnectGraceActive = false
				connection.matchId = match.id
				network.connections[client] = connection^
				if match.status == .Started {
					WsSend(client, "match.start", 0, BuildMatchStartWire(match))
					NetworkSendMatchState(match, NO_WS_CLIENT, 0)
				} else {
					NetworkSendReadyUpdate(match, NO_WS_CLIENT, 0)
				}
			}
		}
	}
	NetworkBroadcastLobbyUpdate(network)
}

NetworkLobbyJoin :: proc(app: ^App, client: WsClient, connection: ^WsConnection, seq: i64) {
	network := &app.network
	if NetworkPlayerMatchIndex(network, connection.playerId) >= 0 {
		WsSendError(client, seq, "already_in_match", "Leave the current match before joining matchmaking")
		return
	}
	for entry in network.lobby {
		if entry.playerId == connection.playerId {
			WsSend(client, "lobby.update", seq, NetworkLobbyUpdate(network))
			return
		}
	}
	if len(network.lobby) >= MAX_LOBBY_PLAYERS {
		WsSendError(client, seq, "lobby_full", "Matchmaking queue is full")
		return
	}
	append(&network.lobby, LobbyEntry{connection.playerId, strings.clone(connection.displayName, network.allocator), client})
	NetworkBroadcastLobbyUpdate(network)
	if len(network.lobby) >= 2 {
		NetworkStartQueuedMatch(app, client, seq)
	}
}

NetworkStartQueuedMatch :: proc(app: ^App, sourceClient: WsClient, seq: i64) {
	network := &app.network
	if len(network.lobby) < 2 do return
	first, second := network.lobby[0], network.lobby[1]
	match := Match{
		id = network.nextMatchId,
		maxPlayers = 2,
		playerCount = 2,
		status = .Waiting,
	}
	network.nextMatchId += 1
	match.players[0] = MatchPlayer{
		playerId = first.playerId,
		displayName = strings.clone(first.displayName, network.allocator),
		connection = first.connection,
		connected = true,
		ready = true,
	}
	match.players[1] = MatchPlayer{
		playerId = second.playerId,
		displayName = strings.clone(second.displayName, network.allocator),
		connection = second.connection,
		connected = true,
		ready = true,
	}
	append(&network.matches, match)
	matchIndex := len(network.matches) - 1
	if len(network.lobby[1].displayName) > 0 do delete(network.lobby[1].displayName, network.allocator)
	unordered_remove(&network.lobby, 1)
	if len(network.lobby[0].displayName) > 0 do delete(network.lobby[0].displayName, network.allocator)
	unordered_remove(&network.lobby, 0)
	NetworkSetConnectionMatch(network, first.connection, match.id)
	NetworkSetConnectionMatch(network, second.connection, match.id)
	NetworkBroadcastLobbyUpdate(network)

	matchPtr := &network.matches[matchIndex]
	if !StartAuthoritativeMatch(app, matchPtr) {
		NetworkSendMatchError(matchPtr, sourceClient, "match_setup_failed", "Could not initialize the authoritative match", seq)
		return
	}
	NetworkSendMatchStart(matchPtr)
}

NetworkMatchCreate :: proc(app: ^App, client: WsClient, connection: ^WsConnection, data: WsClientData, seq: i64) {
	network := &app.network
	if data.maxPlayers < 2 || data.maxPlayers > logic.MAX_PLAYERS {
		WsSendError(client, seq, "invalid_player_count", "max_players must be between 2 and 4")
		return
	}
	if NetworkPlayerMatchIndex(network, connection.playerId) >= 0 || NetworkLobbyIndex(network, connection.playerId) >= 0 {
		WsSendError(client, seq, "already_queued", "Leave the current queue or match first")
		return
	}
	match := Match{
		id = network.nextMatchId,
		maxPlayers = data.maxPlayers,
		playerCount = 1,
		status = .Waiting,
	}
	network.nextMatchId += 1
	match.players[0] = MatchPlayer{
		playerId = connection.playerId,
		displayName = strings.clone(connection.displayName, network.allocator),
		connection = client,
		connected = true,
	}
	append(&network.matches, match)
	connection.matchId = match.id
	network.connections[client] = connection^
	WsSend(client, "match.created", seq, MatchIdWire{match.id})
	NetworkSendReadyUpdate(&network.matches[len(network.matches) - 1], NO_WS_CLIENT, 0)
}

NetworkMatchJoin :: proc(app: ^App, client: WsClient, connection: ^WsConnection, matchId: i64, seq: i64) {
	network := &app.network
	if NetworkPlayerMatchIndex(network, connection.playerId) >= 0 || NetworkLobbyIndex(network, connection.playerId) >= 0 {
		WsSendError(client, seq, "already_queued", "Leave the current queue or match first")
		return
	}
	matchIndex := NetworkMatchIndex(network, matchId)
	if matchIndex < 0 {
		WsSendError(client, seq, "match_not_found", "Waiting match not found")
		return
	}
	match := &network.matches[matchIndex]
	if match.status != .Waiting || match.playerCount >= match.maxPlayers {
		WsSendError(client, seq, "match_unavailable", "Match is no longer accepting players")
		return
	}
	match.players[match.playerCount] = MatchPlayer{
		playerId = connection.playerId,
		displayName = strings.clone(connection.displayName, network.allocator),
		connection = client,
		connected = true,
	}
	match.playerCount += 1
	connection.matchId = match.id
	network.connections[client] = connection^
	WsSend(client, "match.joined", seq, MatchIdWire{match.id})
	NetworkSendReadyUpdate(match, NO_WS_CLIENT, 0)
}

NetworkMatchReady :: proc(app: ^App, client: WsClient, connection: ^WsConnection, ready: bool, seq: i64) {
	matchIndex := NetworkMatchIndex(&app.network, connection.matchId)
	if matchIndex < 0 {
		WsSendError(client, seq, "not_in_match", "Join a private match before readying")
		return
	}
	match := &app.network.matches[matchIndex]
	if match.status != .Waiting {
		WsSendError(client, seq, "match_started", "The match has already started")
		return
	}
	seat := NetworkMatchPlayerIndex(match, connection.playerId)
	if seat < 0 || match.players[seat].connection != client {
		WsSendError(client, seq, "not_match_connection", "This connection does not own the match seat")
		return
	}
	match.players[seat].ready = ready
	NetworkSendReadyUpdate(match, client, seq)
	if match.playerCount != match.maxPlayers do return
	for player in match.players[:match.playerCount] {
		if !player.connected || !player.ready do return
	}
	if !StartAuthoritativeMatch(app, match) {
		NetworkSendMatchError(match, client, "match_setup_failed", "Could not initialize the authoritative match", seq)
		return
	}
	NetworkSendMatchStart(match)
}

NetworkSendMatchStart :: proc(match: ^Match) {
	payload := BuildMatchStartWire(match)
	for player in match.players[:match.playerCount] {
		if !player.connected do continue
		WsSend(player.connection, "match.start", 0, payload)
	}
	NetworkSendMatchState(match, NO_WS_CLIENT, 0)
}

NetworkSendMatchState :: proc(match: ^Match, sourceClient: WsClient, sourceSeq: i64) {
	publicState := BuildPublicGameState(match)
	turnPlayer := i64(0)
	if match.game.currentPlayer >= 0 && match.game.currentPlayer < match.playerCount {
		turnPlayer = match.players[match.game.currentPlayer].playerId
	}
	payload := MatchStateWire{match.game.round, turnPlayer, publicState}
	for player, playerIndex in match.players[:match.playerCount] {
		if !player.connected do continue
		seq := i64(0)
		if player.connection == sourceClient do seq = sourceSeq
		WsSend(player.connection, "match.state", seq, payload)
		NetworkSendHidden(match, playerIndex, seq)
	}
}

NetworkSendHidden :: proc(match: ^Match, seat: int, seq: i64) {
	if seat < 0 || seat >= match.playerCount || !match.players[seat].connected do return
	player := &match.game.players[seat]
	hand := make([]int, player.handCount, context.temp_allocator)
	for i in 0..<player.handCount do hand[i] = player.hand[i]
	directives := make([]int, player.directiveCount, context.temp_allocator)
	for i in 0..<player.directiveCount do directives[i] = player.directives[i]
	WsSend(match.players[seat].connection, "game.hidden", seq, GameHiddenWire{hand, directives})
}

NetworkSendReadyUpdate :: proc(match: ^Match, sourceClient: WsClient, sourceSeq: i64) {
	players := make([]ReadyPlayerWire, match.playerCount, context.temp_allocator)
	for player, i in match.players[:match.playerCount] {
		players[i] = ReadyPlayerWire{player.playerId, player.ready}
	}
	payload := ReadyUpdateWire{match.id, players}
	for player in match.players[:match.playerCount] {
		if player.connected {
			seq := i64(0)
			if player.connection == sourceClient do seq = sourceSeq
			WsSend(player.connection, "match.ready_update", seq, payload)
		}
	}
}

NetworkSendMatchError :: proc(match: ^Match, sourceClient: WsClient, code, message: string, sourceSeq: i64) {
	for player in match.players[:match.playerCount] {
		if player.connected {
			seq := i64(0)
			if player.connection == sourceClient do seq = sourceSeq
			WsSendError(player.connection, seq, code, message)
		}
	}
}

NetworkGameAction :: proc(app: ^App, client: WsClient, connection: ^WsConnection, data: WsClientData, seq: i64) {
	matchIndex := NetworkMatchIndex(&app.network, connection.matchId)
	if matchIndex < 0 {
		WsSendActionError(client, seq, "not_in_match")
		return
	}
	match := &app.network.matches[matchIndex]
	if match.status != .Started {
		WsSendActionError(client, seq, "match_not_started")
		return
	}
	seat := NetworkMatchPlayerIndex(match, connection.playerId)
	if seat < 0 || !match.players[seat].connected || match.players[seat].connection != client {
		WsSendActionError(client, seq, "not_match_connection")
		return
	}
	if data.round != match.game.round {
		WsSendActionError(client, seq, "stale_round")
		return
	}
	if match.game.currentPlayer != seat {
		WsSendActionError(client, seq, "not_your_turn")
		return
	}

	before := match.game
	candidate := before
	ok, combat, hasCombat, observation, hasObservation, reason := ApplyClientGameAction(&candidate, data)
	if !ok {
		WsSendActionError(client, seq, reason)
		return
	}
	apSpent := before.players[seat].ap - candidate.players[seat].ap
	if data.apSpent < 0 || data.apSpent != apSpent {
		WsSendActionError(client, seq, "ap_spent_mismatch")
		return
	}

	attackerCardId, defenderCardId := logic.NO_CARD, logic.NO_CARD
	if hasCombat {
		attackerCardId = CombatCardIdAt(&before, seat, data.attackerCard)
		to := WireHexToLogic(data.to)
		targetIndex := logic.CellIndex(&before, to)
		if targetIndex >= 0 {
			defender := logic.CombatDefender(&before, &before.board[targetIndex], seat)
			if defender >= 0 do defenderCardId = CombatCardIdAt(&before, defender, data.defenderCard)
		}
	}
	match.game = candidate
	WsSend(client, "game.action_ok", seq, ActionAckWire{seq})
	if hasCombat && (data.action == "strike" || data.doStrike) {
		WsSendMatchReveal(match, combat, attackerCardId, defenderCardId)
	}
	if hasObservation {
		WsSend(client, "game.observation", seq, BuildGameObservationWire(observation, match))
	}
	NetworkSendMatchState(match, client, seq)
}

CombatCardIdAt :: proc(game: ^logic.Game, seat, handIndex: int) -> int {
	if seat < 0 || seat >= game.playerCount || handIndex < 0 || handIndex >= game.players[seat].handCount do return logic.NO_CARD
	return game.players[seat].hand[handIndex]
}

WsSendMatchReveal :: proc(match: ^Match, combat: logic.CombatResult, attackerCardId, defenderCardId: int) {
	payload := RevealWire{
		combat = CombatWire{
			attackerStrength = combat.attackerStrength,
			defenderStrength = combat.defenderStrength,
			attackerWon = combat.attackerWon,
			unitDestroyed = combat.unitDestroyed,
			structureDestroyed = combat.structureDestroyed,
			captured = combat.captured,
		},
		attackerCardId = attackerCardId,
		defenderCardId = defenderCardId,
	}
	for player in match.players[:match.playerCount] {
		if player.connected do WsSend(player.connection, "game.reveal", 0, payload)
	}
}

NetworkEndTurn :: proc(app: ^App, client: WsClient, connection: ^WsConnection, seq: i64) {
	matchIndex := NetworkMatchIndex(&app.network, connection.matchId)
	if matchIndex < 0 {
		WsSendError(client, seq, "not_in_match", "No match is active on this connection")
		return
	}
	match := &app.network.matches[matchIndex]
	seat := NetworkMatchPlayerIndex(match, connection.playerId)
	if match.status != .Started || seat < 0 || !match.players[seat].connected || match.players[seat].connection != client {
		WsSendError(client, seq, "match_unavailable", "This connection cannot end the match turn")
		return
	}
	if match.game.currentPlayer != seat {
		WsSendError(client, seq, "not_your_turn", "Only the current player may end their turn")
		return
	}

	before := match.game
	candidate := before
	if !logic.EndTurn(&candidate) {
		WsSendError(client, seq, "invalid_phase", "The game is not in an active turn")
		return
	}
	if candidate.phase == .Score_Objective && !logic.ScoreAndCompleteObjective(&candidate) {
		WsSendError(client, seq, "objective_error", "Could not complete the round objective")
		return
	}
	if candidate.phase == .Await_Turn && !logic.BeginTurn(&candidate) {
		WsSendError(client, seq, "turn_error", "Could not begin the next player's turn")
		return
	}
	match.game = candidate
	if match.game.phase == .Finished {
		if !NetworkFinalizeMatch(app, matchIndex, 0, client, seq) {
			match.game = before
			WsSendError(client, seq, "persistence_error", "Could not persist the completed match")
			return
		}
		return
	}
	NetworkStartReconnectGrace(&app.network, match, time.tick_now())
	WsSend(client, "game.action_ok", seq, ActionAckWire{seq})
	NetworkSendMatchState(match, client, seq)
}

NetworkForfeit :: proc(app: ^App, client: WsClient, connection: ^WsConnection, seq: i64) {
	matchIndex := NetworkMatchIndex(&app.network, connection.matchId)
	if matchIndex < 0 {
		WsSendError(client, seq, "not_in_match", "No match is active on this connection")
		return
	}
	match := &app.network.matches[matchIndex]
	seat := NetworkMatchPlayerIndex(match, connection.playerId)
	if match.status != .Started || seat < 0 || !match.players[seat].connected || match.players[seat].connection != client {
		WsSendError(client, seq, "match_unavailable", "This connection cannot forfeit the match")
		return
	}
	before := match.game
	match.game.phase = .Finished
	if !NetworkFinalizeMatch(app, matchIndex, connection.playerId, client, seq) {
		match.game = before
		WsSendError(client, seq, "persistence_error", "Could not persist the forfeited match")
		return
	}
}

NetworkFinalizeMatch :: proc(app: ^App, matchIndex: int, forfeitBy: i64, sourceClient: WsClient, sourceSeq: i64) -> bool {
	match := &app.network.matches[matchIndex]
	scores: logic.FinalScores
	if !logic.CalculateFinalScores(&match.game, &scores) do return false

	if forfeitBy != 0 {
		for i in 0..<match.playerCount do scores.winners[i] = false
		forfeitingSeat := NetworkMatchPlayerIndex(match, forfeitBy)
		if forfeitingSeat < 0 do return false
		best := -1
		for i in 0..<match.playerCount {
			if i == forfeitingSeat do continue
			if best < 0 || logic.CompareScores(scores.players[i], scores.players[best]) > 0 do best = i
		}
		if best < 0 do return false
		for i in 0..<match.playerCount {
			if i != forfeitingSeat && logic.CompareScores(scores.players[i], scores.players[best]) == 0 {
				scores.winners[i] = true
				scores.winnerCount += 1
			}
		}
	}

	winnerPlayerId: i64
	winnerCount := 0
	winners := make([dynamic]i64, 0, match.playerCount, context.temp_allocator)
	results := make([]DatabaseMatchPlayerResult, match.playerCount, context.temp_allocator)
	breakdown := make([]VpBreakdownWire, match.playerCount, context.temp_allocator)
	for i in 0..<match.playerCount {
		score := scores.players[i]
		if scores.winners[i] {
			if winnerCount == 0 do winnerPlayerId = match.players[i].playerId
			winnerCount += 1
			append(&winners, match.players[i].playerId)
		}
		results[i] = DatabaseMatchPlayerResult{
			playerId = match.players[i].playerId,
			faction = FactionName(match.players[i].faction),
			publicVp = score.publicVp,
			factionVp = score.factionVp,
			directiveVp = score.directiveVp,
			totalVp = score.totalVp,
			winner = scores.winners[i],
		}
		breakdown[i] = VpBreakdownWire{
			playerId = match.players[i].playerId,
			publicVp = score.publicVp,
			factionVp = score.factionVp,
			directivesCompleted = score.directivesCompleted,
			directiveVp = score.directiveVp,
			totalVp = score.totalVp,
		}
	}
	if winnerCount == 0 || !DatabaseFinishMatch(app.database, match.databaseId, winnerPlayerId, results) do return false

	if sourceClient != NO_WS_CLIENT do WsSend(sourceClient, "game.action_ok", sourceSeq, ActionAckWire{sourceSeq})
	payload := MatchEndWire{match.id, winnerPlayerId, winners[:], forfeitBy, breakdown}
	match.status = .Finished
	for player in match.players[:match.playerCount] {
		if player.connected do WsSend(player.connection, "match.end", 0, payload)
		NetworkSetConnectionMatch(&app.network, player.connection, 0)
		if len(player.displayName) > 0 do delete(player.displayName, app.network.allocator)
	}
	unordered_remove(&app.network.matches, matchIndex)
	return true
}

NetworkChat :: proc(network: ^NetworkState, client: WsClient, connection: ^WsConnection, text: string, seq: i64) {
	if len(text) < 1 || len(text) > MAX_CHAT_BYTES {
		WsSendError(client, seq, "invalid_chat", "Chat text must be 1 to 500 bytes")
		return
	}
	matchIndex := NetworkMatchIndex(network, connection.matchId)
	if matchIndex < 0 {
		WsSendError(client, seq, "not_in_match", "Chat is only available in a match")
		return
	}
	match := &network.matches[matchIndex]
	seat := NetworkMatchPlayerIndex(match, connection.playerId)
	if match.status != .Started || seat < 0 || match.players[seat].connection != client {
		WsSendError(client, seq, "match_unavailable", "Chat is only available to match participants")
		return
	}
	payload := ChatWire{connection.playerId, text}
	for player in match.players[:match.playerCount] {
		if player.connected {
			replySeq := i64(0)
			if player.connection == client do replySeq = seq
			WsSend(player.connection, "chat", replySeq, payload)
		}
	}
}

NetworkLobbyUpdate :: proc(network: ^NetworkState) -> LobbyUpdateWire {
	players := make([]LobbyPlayerWire, len(network.lobby), context.temp_allocator)
	for entry, i in network.lobby do players[i] = LobbyPlayerWire{entry.playerId, entry.displayName}
	return LobbyUpdateWire{players}
}

NetworkBroadcastLobbyUpdate :: proc(network: ^NetworkState) {
	payload := NetworkLobbyUpdate(network)
	for entry in network.lobby do WsSend(entry.connection, "lobby.update", 0, payload)
}

NetworkRemoveLobbyPlayer :: proc(network: ^NetworkState, playerId: i64, client: WsClient) {
	for i := len(network.lobby) - 1; i >= 0; i -= 1 {
		if network.lobby[i].playerId == playerId && network.lobby[i].connection == client {
			if len(network.lobby[i].displayName) > 0 do delete(network.lobby[i].displayName, network.allocator)
			unordered_remove(&network.lobby, i)
		}
	}
}

NetworkLobbyIndex :: proc(network: ^NetworkState, playerId: i64) -> int {
	for entry, i in network.lobby do if entry.playerId == playerId do return i
	return -1
}

NetworkSetConnectionMatch :: proc(network: ^NetworkState, client: WsClient, matchId: i64) {
	if client == NO_WS_CLIENT do return
	connection, exists := network.connections[client]
	if exists {
		connection.matchId = matchId
		network.connections[client] = connection
	}
}

NetworkMatchIndex :: proc(network: ^NetworkState, matchId: i64) -> int {
	for match, i in network.matches do if match.id == matchId do return i
	return -1
}

NetworkPlayerMatchIndex :: proc(network: ^NetworkState, playerId: i64) -> int {
	for i in 0..<len(network.matches) {
		match := &network.matches[i]
		if match.status == .Finished do continue
		if NetworkMatchPlayerIndex(match, playerId) >= 0 do return i
	}
	return -1
}

NetworkMatchPlayerIndex :: proc(match: ^Match, playerId: i64) -> int {
	for player, i in match.players[:match.playerCount] do if player.playerId == playerId do return i
	return -1
}
