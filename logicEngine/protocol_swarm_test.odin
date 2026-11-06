#+build !js

package logicEngine

import "core:testing"

@(test)
TestSwarmSacrifice :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	player := &game.players[0]
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	player.deck[0], player.deck[1], player.deck[2] = 1, 2, 3
	player.deckCount = 3
	before := game
	testing.expect(t, !ApplySwarmProtocol(&game, 4, {to = pos}))
	testing.expect(t, !ApplySwarmProtocol(&game, 4, {to = {4, 0}}))
	testing.expect_value(t, game, before)
	cell.units[0], cell.boostedUnits[0], cell.units[1] = 2, 1, 1
	cell.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 4, {to = pos}))
	cell.rift = false
	testing.expect(t, ApplySwarmProtocol(&game, 4, {to = pos}))
	testing.expect_value(t, cell.units[0], 1)
	testing.expect_value(t, cell.boostedUnits[0], 1)
	testing.expect_value(t, player.handCount, 2)
	testing.expect_value(t, player.hand[0], 3)
	testing.expect_value(t, player.hand[1], 2)
	testing.expect_value(t, player.deckCount, 1)
	testing.expect_value(t, player.unitsDestroyed, 0)
	testing.expect_value(t, player.tokensDestroyed, 0)
	player.handCount = HAND_LIMIT - 1
	testing.expect(t, ApplySwarmProtocol(&game, 4, {to = pos}))
	testing.expect_value(t, cell.units[0], 0)
	testing.expect_value(t, cell.boostedUnits[0], 0)
	testing.expect_value(t, player.handCount, HAND_LIMIT)
	testing.expect_value(t, player.deckCount, 0)
	cell.units[0] = 1
	testing.expect(t, ApplySwarmProtocol(&game, 4, {to = pos}))
	testing.expect_value(t, player.handCount, HAND_LIMIT)
}

@(test)
TestSwarmSense :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	player := &game.players[0]
	player.deck[0], player.deck[1], player.deck[2], player.deck[3] = 1, 2, 3, 4
	player.deckCount = 4
	before := game
	testing.expect(t, !ApplySwarmProtocol(&game, 5, {cardIndex = -1}))
	testing.expect(t, !ApplySwarmProtocol(&game, 5, {cardIndex = 2}))
	testing.expect_value(t, game, before)
	testing.expect(t, ApplySwarmProtocol(&game, 5, {cardIndex = 0}))
	testing.expect_value(t, player.hand[0], 4)
	testing.expect_value(t, player.handCount, 1)
	testing.expect_value(t, player.deckCount, 3)
	testing.expect_value(t, player.deck[0], 3)
	testing.expect_value(t, player.deck[1], 1)
	testing.expect_value(t, player.deck[2], 2)

	game = before
	testing.expect(t, ApplySwarmProtocol(&game, 5, {cardIndex = 1}))
	testing.expect_value(t, player.hand[0], 3)
	testing.expect_value(t, player.deckCount, 3)
	testing.expect_value(t, player.deck[0], 4)
	testing.expect_value(t, player.deck[1], 1)
	testing.expect_value(t, player.deck[2], 2)

	player.deckCount = 1
	before = game
	testing.expect(t, !ApplySwarmProtocol(&game, 5, {cardIndex = 1}))
	testing.expect_value(t, game, before)
	testing.expect(t, ApplySwarmProtocol(&game, 5, {cardIndex = 0}))
	testing.expect_value(t, player.hand[1], 4)
	testing.expect_value(t, player.deckCount, 0)
	before = game
	testing.expect(t, !ApplySwarmProtocol(&game, 5, {cardIndex = 0}))
	testing.expect_value(t, game, before)

	player.deck[0], player.deck[1], player.deck[2] = 1, 2, 3
	player.deckCount = 3
	player.handCount = HAND_LIMIT
	testing.expect(t, ApplySwarmProtocol(&game, 5, {cardIndex = 1}))
	testing.expect_value(t, player.deckCount, 3)
	testing.expect_value(t, player.deck[0], 3)
	testing.expect_value(t, player.deck[1], 1)
	testing.expect_value(t, player.deck[2], 2)
	testing.expect_value(t, player.handCount, HAND_LIMIT)
}

@(test)
TestSwarmBurrow :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0], source.boostedUnits[0], source.units[1] = 2, 1, 1
	choice := ProtocolChoice{from = from, to = to}
	target.units[1] = 1
	before := game
	testing.expect(t, !ApplySwarmProtocol(&game, 6, choice))
	testing.expect_value(t, game, before)
	target.units[1] = 0
	target.structures[1] = true
	testing.expect(t, !ApplySwarmProtocol(&game, 6, choice))
	target.structures[1] = false
	target.units[0] = UNIT_CAP
	testing.expect(t, !ApplySwarmProtocol(&game, 6, choice))
	target.units[0] = 0
	target.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 6, choice))
	target.rift = false
	source.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 6, choice))
	source.rift = false
	testing.expect(t, !ApplySwarmProtocol(&game, 6, {from = from, to = {2, 0}}))
	testing.expect(t, !ApplySwarmProtocol(&game, 6, {from = {4, 0}, to = {3, 0}}))
	testing.expect(t, ApplySwarmProtocol(&game, 6, choice))
	testing.expect_value(t, source.units[0], 1)
	testing.expect_value(t, source.boostedUnits[0], 0)
	testing.expect_value(t, source.units[1], 1)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.boostedUnits[0], 1)
}

@(test)
TestSwarmReplicateAndHiveMind :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	testing.expect(t, !ApplySwarmProtocol(&game, 7, {to = pos}))
	testing.expect(t, !ApplySwarmProtocol(&game, 8, {to = pos}))
	cell.units[0] = 1
	cell.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 7, {to = pos}))
	testing.expect(t, !ApplySwarmProtocol(&game, 8, {to = pos}))
	cell.rift = false
	cell.units[1] = 1
	testing.expect(t, !ApplySwarmProtocol(&game, 7, {to = pos}))
	// Hive Mind can target friendly units even in a contested hex.
	testing.expect(t, ApplySwarmProtocol(&game, 8, {to = pos}))
	testing.expect_value(t, cell.boostedUnits[0], 1)
	cell.units[1] = 0
	testing.expect(t, ApplySwarmProtocol(&game, 7, {to = pos}))
	testing.expect_value(t, cell.units[0], 2)
	testing.expect_value(t, cell.boostedUnits[0], 1)
	testing.expect(t, ApplySwarmProtocol(&game, 8, {to = pos}))
	testing.expect_value(t, cell.boostedUnits[0], 2)
	testing.expect(t, ApplySwarmProtocol(&game, 7, {to = pos}))
	testing.expect(t, !ApplySwarmProtocol(&game, 7, {to = pos}))
	testing.expect_value(t, cell.units[0], UNIT_CAP)
	testing.expect_value(t, cell.boostedUnits[0], 2)
	testing.expect(t, !ApplySwarmProtocol(&game, 8, {to = {4, 0}}))
}

@(test)
TestSwarmCorrode :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .AI
	game.players[1].relayShield = true
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	target.structures[1] = true
	target.fortified[1], target.shielded[1] = true, true
	choice := ProtocolChoice{to = to, target = .Structure}
	before := game
	testing.expect(t, !ApplySwarmProtocol(&game, 9, choice))
	testing.expect_value(t, game, before)
	source.units[0] = 1
	source.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 9, choice))
	source.rift = false
	target.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 9, choice))
	target.rift = false
	testing.expect(t, !ApplySwarmProtocol(&game, 9, {to = to, target = TokenKind(99)}))
	testing.expect(t, !ApplySwarmProtocol(&game, 9, {to = from, target = .Structure}))
	testing.expect(t, ApplySwarmProtocol(&game, 9, choice))
	testing.expect(t, target.structures[1] && target.fortified[1] && !target.shielded[1])
	testing.expect_value(t, game.players[0].structuresDestroyed, 0)
	testing.expect_value(t, game.players[0].tokensDestroyed, 0)
	testing.expect(t, ApplySwarmProtocol(&game, 9, choice))
	testing.expect(t, !target.structures[1] && !target.fortified[1])
	testing.expect_value(t, game.players[0].structuresDestroyed, 1)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
	testing.expect(t, !ApplySwarmProtocol(&game, 9, choice))
	target.structures[0] = true
	testing.expect(t, !ApplySwarmProtocol(&game, 9, choice))
	target.relay = 0
	testing.expect(t, !ApplySwarmProtocol(&game, 9, {to = to, target = .Relay}))
	target.relay = 1
	testing.expect(t, ApplySwarmProtocol(&game, 9, {to = to, target = .Relay}))
	testing.expect_value(t, target.relay, NO_PLAYER)
	testing.expect_value(t, game.players[0].tokensDestroyed, 2)
	testing.expect(t, !game.relayDestroyedThisTurn)
}

@(test)
TestSwarmBrood :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	from, to := Hex{0, 0}, Hex{2, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0], source.boostedUnits[0] = 1, 1
	choice := ProtocolChoice{from = from, to = to}
	before := game
	testing.expect(t, !ApplySwarmProtocol(&game, 10, choice))
	testing.expect(t, !ApplySwarmProtocol(&game, 10, {from = from, to = from}))
	testing.expect_value(t, game, before)
	target.units[0] = UNIT_CAP
	before = game
	testing.expect(t, !ApplySwarmProtocol(&game, 10, choice))
	testing.expect_value(t, game, before)
	target.units[0] = 1
	target.units[1] = 1
	testing.expect(t, !ApplySwarmProtocol(&game, 10, choice))
	target.units[1] = 0
	target.rift = true
	testing.expect(t, !ApplySwarmProtocol(&game, 10, choice))
	target.rift = false
	testing.expect(t, ApplySwarmProtocol(&game, 10, choice))
	testing.expect_value(t, source.units[0], 2)
	testing.expect_value(t, source.boostedUnits[0], 1)
	testing.expect_value(t, target.units[0], 2)
	testing.expect_value(t, target.boostedUnits[0], 0)
}

@(test)
TestSwarmHiveMindCombatAndExpiry :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.currentPlayer = 1
	game.players[0].faction = .Corp
	game.players[1].faction = .Swarm
	game.players[1].ap = 3
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[1], target.units[0] = 2, 1
	testing.expect(t, ApplySwarmProtocol(&game, 8, {to = from}))
	result, ok := StrikeWithCards(&game, from, to, 2, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, result.attackerStrength, 4)
	testing.expect_value(t, source.boostedUnits[1], 2)
	testing.expect(t, EndTurn(&game))
	testing.expect_value(t, source.boostedUnits[1], 0)
	testing.expect_value(t, source.units[1], 2)
}

@(test)
TestSwarmEndlessAndInvalidCards :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[0].resources = {RESOURCE_CAP - 1, 3}
	testing.expect(t, ApplySwarmProtocol(&game, 11, {}))
	testing.expect_value(t, game.players[0].resources, Resources{RESOURCE_CAP, 3})
	for id in -1..<4 do testing.expect(t, !ApplySwarmProtocol(&game, id, {}))
	testing.expect(t, !ApplySwarmProtocol(&game, 12, {}))
	game.players[0].faction = .Corp
	testing.expect(t, !ApplySwarmProtocol(&game, 11, {}))
	testing.expect(t, !ApplySwarmProtocol(nil, 11, {}))
	game.players[0].faction = .Swarm
	game.currentPlayer = -1
	testing.expect(t, !ApplySwarmProtocol(&game, 11, {}))
	game.currentPlayer = 0
	game.playerCount = MAX_PLAYERS + 1
	testing.expect(t, !ApplySwarmProtocol(&game, 11, {}))
}
