#+build !js

package server

import logic "../logicEngine"
import "core:testing"

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
