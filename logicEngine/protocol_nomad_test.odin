#+build !js

package logicEngine

import "core:testing"

@(test)
TestNomadScorchedEarth :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[0].resources.energy = 4
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	choice := ProtocolChoice{to = pos, target = .Structure}
	testing.expect(t, !ApplyNomadProtocol(&game, 5, choice))
	cell.structures[1] = true
	testing.expect(t, !ApplyNomadProtocol(&game, 5, choice))
	cell.structures[1] = false
	cell.units[0] = 1
	cell.structures[0] = true
	cell.rift = true
	testing.expect(t, !ApplyNomadProtocol(&game, 5, choice))
	cell.rift = false
	testing.expect(t, !ApplyNomadProtocol(&game, 5, {to = pos, target = TokenKind(99)}))
	cell.shielded[0] = true
	testing.expect(t, ApplyNomadProtocol(&game, 5, choice))
	testing.expect(t, cell.structures[0] && !cell.shielded[0])
	testing.expect_value(t, game.players[0].resources.energy, 7)
	testing.expect(t, ApplyNomadProtocol(&game, 5, choice))
	testing.expect(t, !cell.structures[0])
	testing.expect_value(t, game.players[0].resources.energy, RESOURCE_CAP)
	testing.expect_value(t, game.players[0].structuresDestroyed, 0)
	testing.expect_value(t, game.players[0].tokensDestroyed, 0)
	game.players[0].resources.energy = 0
	cell.relay = 1
	testing.expect(t, ApplyNomadProtocol(&game, 5, {to = pos, target = .Relay}))
	testing.expect_value(t, cell.relay, NO_PLAYER)
	testing.expect_value(t, game.players[0].resources.energy, 3)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
}

@(test)
TestNomadSmokeAndMirrors :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	player := &game.players[0]
	player.deck[0], player.deck[1] = 3, 4
	player.deckCount = 2
	testing.expect(t, ApplyNomadProtocol(&game, 6, {}))
	testing.expect_value(t, player.handCount, 1)
	testing.expect_value(t, player.hand[0], 4)
	player.handCount = HAND_LIMIT
	testing.expect(t, ApplyNomadProtocol(&game, 6, {}))
	testing.expect_value(t, player.deckCount, 1)
	player.handCount = 0
	player.deckCount = 0
	testing.expect(t, ApplyNomadProtocol(&game, 6, {}))
	testing.expect_value(t, player.handCount, 0)
}

@(test)
TestNomadForage :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[0].resources = {RESOURCE_CAP - 1, RESOURCE_CAP}
	testing.expect(t, ApplyNomadProtocol(&game, 7, {}))
	testing.expect_value(t, game.players[0].resources, Resources{RESOURCE_CAP, RESOURCE_CAP})
}

@(test)
TestNomadStrikeTeamStructure :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0] = 2
	source.boostedUnits[0] = 1
	target.structures[1] = true
	choice := ProtocolChoice{from = from, to = to, target = .Structure}
	before := game
	declined := game
	testing.expect(t, ApplyNomadProtocol(&declined, 8, choice))
	testing.expect(t, declined.board[CellIndex(&declined, to)].structures[1])
	testing.expect_value(t, declined.board[CellIndex(&declined, to)].units[0], 1)
	testing.expect_value(t, game, before)
	choice.option = true
	target.relay = 1
	target.shielded[1] = true
	trial := game
	testing.expect(t, ApplyNomadProtocol(&trial, 8, choice))
	trialSource, trialTarget := &trial.board[CellIndex(&trial, from)], &trial.board[CellIndex(&trial, to)]
	testing.expect(t, trialTarget.structures[1] && !trialTarget.shielded[1])
	testing.expect_value(t, trialSource.units[0], 1)
	testing.expect_value(t, trialTarget.units[0], 1)
	target.shielded[1] = false
	testing.expect(t, ApplyNomadProtocol(&game, 8, choice))
	testing.expect(t, !target.structures[1])
	testing.expect_value(t, target.relay, 1)
	testing.expect_value(t, source.units[0], 1)
	testing.expect_value(t, source.boostedUnits[0], 0)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.boostedUnits[0], 1)
	testing.expect_value(t, game.players[0].structuresDestroyed, 1)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)

	game = CombatTestGame()
	game.players[0].faction = .Nomad
	source = &game.board[CellIndex(&game, from)]
	target = &game.board[CellIndex(&game, to)]
	source.units[0] = 1
	target.structures[1], target.relay = true, 1
	choice = {from = from, to = to, option = true, target = .Relay}
	testing.expect(t, ApplyNomadProtocol(&game, 8, choice))
	testing.expect(t, target.structures[1])
	testing.expect_value(t, target.relay, NO_PLAYER)
}

@(test)
TestNomadStrikeTeamRelayAndMovement :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .AI
	game.players[1].relayShield = true
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0] = 2
	target.relay = 1
	choice := ProtocolChoice{from = from, to = to}
	declined := game
	testing.expect(t, ApplyNomadProtocol(&declined, 8, choice))
	testing.expect_value(t, declined.board[CellIndex(&declined, to)].relay, 1)
	testing.expect_value(t, declined.board[CellIndex(&declined, to)].units[0], 1)
	testing.expect_value(t, declined.board[CellIndex(&declined, from)].units[0], 1)
	choice.option = true
	choice.target = .Relay
	testing.expect(t, ApplyNomadProtocol(&game, 8, choice))
	testing.expect_value(t, target.relay, NO_PLAYER)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
	testing.expect(t, !game.relayDestroyedThisTurn)
	testing.expect(t, !ApplyNomadProtocol(&game, 8, choice))

	target.units[1] = 1
	testing.expect(t, !ApplyNomadProtocol(&game, 8, {from = from, to = to}))
	target.units[1] = 0
	target.units[0] = UNIT_CAP
	testing.expect(t, !ApplyNomadProtocol(&game, 8, {from = from, to = to}))
	target.units[0] = 0
	target.rift = true
	testing.expect(t, !ApplyNomadProtocol(&game, 8, {from = from, to = to}))
	target.rift = false
	testing.expect(t, !ApplyNomadProtocol(&game, 8, {from = from, to = {2, 0}}))
	testing.expect(t, !ApplyNomadProtocol(&game, 8, {from = from, to = to, option = true, target = TokenKind(99)}))
}

@(test)
TestNomadFlee :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0] = 1
	source.boostedUnits[0] = 1
	choice := ProtocolChoice{from = from, to = to}
	testing.expect(t, !ApplyNomadProtocol(&game, 9, choice))
	source.structures[1] = true
	testing.expect(t, !ApplyNomadProtocol(&game, 9, choice))
	source.units[1] = 1
	target.units[1] = 1
	testing.expect(t, !ApplyNomadProtocol(&game, 9, choice))
	target.units[1] = 0
	target.structures[1] = true
	testing.expect(t, !ApplyNomadProtocol(&game, 9, choice))
	target.structures[1] = false
	testing.expect(t, !ApplyNomadProtocol(&game, 9, {from = from, to = {2, 0}}))
	testing.expect(t, ApplyNomadProtocol(&game, 9, choice))
	testing.expect_value(t, source.units[0], 0)
	testing.expect_value(t, source.boostedUnits[0], 0)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.boostedUnits[0], 1)
	testing.expect_value(t, source.units[1], 1)
}

@(test)
TestNomadTribute :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[0].resources = {0, 0}
	game.players[1].resources = {1, 2}
	testing.expect(t, !ApplyNomadProtocol(&game, 10, {other = 0, resource = .Energy}))
	testing.expect(t, !ApplyNomadProtocol(&game, 10, {other = 2, resource = .Energy}))
	testing.expect(t, !ApplyNomadProtocol(&game, 10, {other = 1, resource = ResourceKind(99)}))
	testing.expect(t, ApplyNomadProtocol(&game, 10, {other = 1, resource = .Energy}))
	testing.expect_value(t, game.players[0].resources, Resources{2, 0})
	testing.expect_value(t, game.players[1].resources, Resources{0, 2})
	testing.expect_value(t, game.players[0].resourcesStolen, 1)
	testing.expect(t, !ApplyNomadProtocol(&game, 10, {other = 1, resource = .Energy}))
	game.players[0].resources.data = RESOURCE_CAP - 1
	testing.expect(t, ApplyNomadProtocol(&game, 10, {other = 1, resource = .Data}))
	testing.expect_value(t, game.players[0].resources.data, RESOURCE_CAP)
	testing.expect_value(t, game.players[1].resources.data, 1)
	testing.expect_value(t, game.players[0].resourcesStolen, 2)
	before := game
	testing.expect(t, !ApplyNomadProtocol(&game, 10, {other = 1, resource = .Data}))
	testing.expect_value(t, game, before)
}

@(test)
TestNomadWarpathAndInvalidCards :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[0].struckThisTurn = true
	testing.expect(t, ApplyNomadProtocol(&game, 11, {}))
	testing.expect(t, game.players[0].warpath && game.players[0].struckThisTurn)
	testing.expect(t, !game.players[1].warpath)
	for id in -1..<5 do testing.expect(t, !ApplyNomadProtocol(&game, id, {}))
	testing.expect(t, !ApplyNomadProtocol(&game, 12, {}))
	game.players[0].faction = .AI
	testing.expect(t, !ApplyNomadProtocol(&game, 11, {}))
	testing.expect(t, !ApplyNomadProtocol(nil, 11, {}))
}
