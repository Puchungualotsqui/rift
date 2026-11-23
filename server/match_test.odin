#+build !js

package server

import logic "../logicEngine"
import "core:testing"
import "core:time"

@(test)
TestAuthoritativeMatchSetupAndActions :: proc(t: ^testing.T) {
	database: Database
	if !DatabaseInit(&database, ":memory:") {
		testing.expect(t, false)
		return
	}
	defer DatabaseDeinit(&database)

	first, firstCreated := DatabaseCreateGuestSession(&database)
	second, secondCreated := DatabaseCreateGuestSession(&database)
	if !firstCreated || !secondCreated {
		testing.expect(t, false)
		return
	}

	app := App{database = &database}
	match := Match{
		id = 1,
		maxPlayers = 2,
		playerCount = 2,
		status = .Waiting,
	}
	match.players[0].playerId = first.playerId
	match.players[1].playerId = second.playerId
	if !StartAuthoritativeMatch(&app, &match) {
		testing.expect(t, false)
		return
	}

	testing.expect_value(t, match.status, MatchStatus.Started)
	testing.expect(t, match.databaseId > 0)
	testing.expect_value(t, match.game.playerCount, 2)
	testing.expect_value(t, match.game.phase, logic.Phase.Acting)

	seat := match.game.currentPlayer
	start := match.players[seat].start
	cell := &match.game.board[logic.CellIndex(&match.game, start)]
	for player in 0..<logic.MAX_PLAYERS do cell.units[player] = 0
	cell.units[seat] = 1
	match.game.players[seat].resources = logic.Resources{logic.RESOURCE_CAP, logic.RESOURCE_CAP}

	apBefore := match.game.players[seat].ap
	data := WsClientData{
		action = "build_unit",
		to = WireHex{start.q, start.r},
	}
	applied, _, hasCombat, _, hasObservation, reason := ApplyClientGameAction(&match.game, data)
	testing.expect(t, applied)
	testing.expect(t, !hasCombat && !hasObservation)
	testing.expect_value(t, reason, "")
	testing.expect_value(t, cell.units[seat], 2)
	testing.expect_value(t, match.game.players[seat].ap, apBefore - 1)

	before := match.game
	data.action = "not_a_game_action"
	applied, _, _, _, _, reason = ApplyClientGameAction(&match.game, data)
	testing.expect(t, !applied)
	testing.expect_value(t, reason, "unknown_action")
	testing.expect_value(t, match.game, before)
}

@(test)
TestPrivateWaitingMatchExpiresAfterDisconnect :: proc(t: ^testing.T) {
	database: Database
	if !DatabaseInit(&database, ":memory:") {
		testing.expect(t, false)
		return
	}
	defer DatabaseDeinit(&database)

	app := App{database = &database}
	NetworkInit(&app.network)
	defer NetworkDeinit(&app.network)
	app.network.waitingDisconnectTimeout = 0

	match := Match{id = 1, maxPlayers = 2, playerCount = 1, status = .Waiting}
	match.players[0] = MatchPlayer{
		playerId = 1,
		disconnectedAt = time.tick_now(),
		hasDisconnectedAt = true,
	}
	append(&app.network.matches, match)

	NetworkProcessMatchDeadlines(&app, time.tick_now())
	testing.expect_value(t, len(app.network.matches), 0)
}

@(test)
TestDisconnectedCurrentPlayerForfeitsAfterGrace :: proc(t: ^testing.T) {
	database: Database
	if !DatabaseInit(&database, ":memory:") {
		testing.expect(t, false)
		return
	}
	defer DatabaseDeinit(&database)

	first, firstCreated := DatabaseCreateGuestSession(&database)
	second, secondCreated := DatabaseCreateGuestSession(&database)
	if !firstCreated || !secondCreated {
		testing.expect(t, false)
		return
	}

	app := App{database = &database}
	NetworkInit(&app.network)
	defer NetworkDeinit(&app.network)
	app.network.turnReconnectGrace = 0
	app.network.maxReconnectGrace = 0

	match := Match{id = 1, maxPlayers = 2, playerCount = 2, status = .Waiting}
	match.players[0] = MatchPlayer{playerId = first.playerId, connected = true}
	match.players[1] = MatchPlayer{playerId = second.playerId, connected = true}
	if !StartAuthoritativeMatch(&app, &match) {
		testing.expect(t, false)
		return
	}

	for &player in match.players[:match.playerCount] {
		player.connected = false
		player.connection = NO_WS_CLIENT
	}
	forfeitPlayerId := match.players[match.game.currentPlayer].playerId
	append(&app.network.matches, match)

	NetworkProcessMatchDeadlines(&app, time.tick_now())
	testing.expect_value(t, len(app.network.matches), 0)

	firstProfile, firstAuthenticated := DatabaseAuthenticate(&database, first.sessionToken)
	secondProfile, secondAuthenticated := DatabaseAuthenticate(&database, second.sessionToken)
	testing.expect(t, firstAuthenticated && secondAuthenticated)
	testing.expect_value(t, firstProfile.gamesPlayed, i64(1))
	testing.expect_value(t, secondProfile.gamesPlayed, i64(1))
	if forfeitPlayerId == first.playerId {
		testing.expect_value(t, firstProfile.wins, i64(0))
		testing.expect_value(t, secondProfile.wins, i64(1))
	} else {
		testing.expect_value(t, firstProfile.wins, i64(1))
		testing.expect_value(t, secondProfile.wins, i64(0))
	}
}
