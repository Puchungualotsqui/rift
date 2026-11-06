#+build !js

package logicEngine

import "core:testing"

@(test)
TestAiDataSpike :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.currentPlayer = 1
	game.players[1].faction = .AI
	game.players[0].hand[0], game.players[0].hand[1] = 4, 7
	game.players[0].handCount = 2
	before := game
	testing.expect(t, ApplyAiProtocol(&game, 3, {other = 0}))
	testing.expect_value(t, game, before)
	testing.expect(t, !ApplyAiProtocol(&game, 3, {other = -1}))
	testing.expect(t, !ApplyAiProtocol(&game, 3, {other = 1}))
	testing.expect(t, !ApplyAiProtocol(&game, 3, {other = 2}))
	testing.expect_value(t, game, before)
}

@(test)
TestAiReroute :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.relay = 0
	choice := ProtocolChoice{from = from, to = to}
	testing.expect(t, !ApplyAiProtocol(&game, 4, choice))
	target.units[0] = 1
	target.relay = 1
	testing.expect(t, !ApplyAiProtocol(&game, 4, choice))
	target.relay = NO_PLAYER
	target.rift = true
	testing.expect(t, !ApplyAiProtocol(&game, 4, choice))
	target.rift = false
	source.rift = true
	testing.expect(t, !ApplyAiProtocol(&game, 4, choice))
	source.rift = false
	testing.expect(t, !ApplyAiProtocol(&game, 4, {from = from, to = {2, 0}}))
	testing.expect(t, ApplyAiProtocol(&game, 4, choice))
	testing.expect_value(t, source.relay, NO_PLAYER)
	testing.expect_value(t, target.relay, 0)
	testing.expect(t, !ApplyAiProtocol(&game, 4, choice))
}

@(test)
TestAiCascade :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	player := &game.players[0]
	player.deck[0], player.deck[1], player.deck[2], player.deck[3] = 3, 4, 5, 6
	player.deckCount = 4
	testing.expect(t, ApplyAiProtocol(&game, 5, {}))
	testing.expect_value(t, player.handCount, 0)
	game.board[0].relay = 0
	game.board[1].relay = 0
	game.board[2].relay = 0
	game.board[3].relay = 1
	testing.expect(t, ApplyAiProtocol(&game, 5, {}))
	testing.expect_value(t, player.handCount, 2)
	testing.expect_value(t, player.hand[0], 6)
	testing.expect_value(t, player.hand[1], 5)
	testing.expect_value(t, player.deckCount, 2)
	player.handCount = HAND_LIMIT - 1
	testing.expect(t, ApplyAiProtocol(&game, 5, {}))
	testing.expect_value(t, player.handCount, HAND_LIMIT)
	testing.expect_value(t, player.deckCount, 1)
	player.handCount = 0
	player.deckCount = 0
	testing.expect(t, ApplyAiProtocol(&game, 5, {}))
	testing.expect_value(t, player.handCount, 0)
	player.deckCount = 1
	game.board[0].rift = true
	game.board[1].relay = NO_PLAYER
	game.board[2].relay = NO_PLAYER
	testing.expect(t, ApplyAiProtocol(&game, 5, {}))
	testing.expect_value(t, player.handCount, 0)
	game.board[0].rift = false
	testing.expect(t, ApplyAiProtocol(&game, 5, {}))
	testing.expect_value(t, player.handCount, 1)
}

@(test)
TestAiOverride :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	game.players[1].hand[0], game.players[1].hand[1], game.players[1].hand[2] = 3, 5, 8
	game.players[1].handCount = 3
	expected := game
	index := RandomIndex(&expected, 3)
	discarded := expected.players[1].hand[index]
	testing.expect(t, DiscardCard(&expected.players[1], index))
	testing.expect(t, ApplyAiProtocol(&game, 6, {other = 1, cardIndex = -100}))
	testing.expect_value(t, game.players[1].discard[0], discarded)
	testing.expect_value(t, game.players[1].handCount, 2)
	testing.expect_value(t, game.players[1].discardCount, 1)
	testing.expect_value(t, game, expected)

	before := game
	testing.expect(t, !ApplyAiProtocol(&game, 6, {other = 0}))
	testing.expect(t, !ApplyAiProtocol(&game, 6, {other = 2}))
	testing.expect_value(t, game, before)
	game.players[1].handCount = 0
	before = game
	testing.expect(t, !ApplyAiProtocol(&game, 6, {other = 1}))
	testing.expect_value(t, game, before)
	game.players[1].handCount = 1
	game.players[1].discardCount = len(game.players[1].discard)
	before = game
	testing.expect(t, !ApplyAiProtocol(&game, 6, {other = 1}))
	testing.expect_value(t, game, before)
}

@(test)
TestAiPing :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	player := &game.players[0]
	player.deck[0], player.deck[1], player.deck[2] = 10, 11, 12
	player.deckCount = 3
	testing.expect(t, ApplyAiProtocol(&game, 7, {option = true}))
	testing.expect_value(t, player.hand[0], 11)
	testing.expect_value(t, player.deckCount, 2)
	testing.expect_value(t, player.deck[0], 12)
	testing.expect_value(t, player.deck[1], 10)
	testing.expect(t, ApplyAiProtocol(&game, 7, {option = false}))
	testing.expect_value(t, player.hand[1], 10)
	player.handCount = HAND_LIMIT
	player.deck[0], player.deck[1], player.deck[2] = 1, 2, 3
	player.deckCount = 3
	testing.expect(t, ApplyAiProtocol(&game, 7, {option = true}))
	testing.expect_value(t, player.deckCount, 3)
	testing.expect_value(t, player.deck[0], 3)
	testing.expect_value(t, player.deck[2], 2)
	player.deckCount = 0
	testing.expect(t, ApplyAiProtocol(&game, 7, {option = true}))
	player.handCount = 0
	player.deck[0] = 7
	player.deckCount = 1
	testing.expect(t, ApplyAiProtocol(&game, 7, {option = true}))
	testing.expect_value(t, player.hand[0], 7)
	testing.expect_value(t, player.deckCount, 0)
}

@(test)
TestAiMesh :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	testing.expect(t, !ApplyAiProtocol(&game, 8, {to = pos}))
	cell.units[0] = 1
	cell.relay = 1
	testing.expect(t, !ApplyAiProtocol(&game, 8, {to = pos}))
	cell.relay = NO_PLAYER
	cell.rift = true
	testing.expect(t, !ApplyAiProtocol(&game, 8, {to = pos}))
	cell.rift = false
	testing.expect(t, ApplyAiProtocol(&game, 8, {to = pos}))
	testing.expect_value(t, cell.relay, 0)
	testing.expect(t, !ApplyAiProtocol(&game, 8, {to = pos}))
}

@(test)
TestAiRelayShield :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	testing.expect(t, ApplyAiProtocol(&game, 9, {}))
	testing.expect(t, game.players[0].relayShield)
	testing.expect(t, !game.players[1].relayShield)
}

@(test)
TestAiFork :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	game.players[0].resources = {5, 5}
	pos := Hex{0, 0}
	center := &game.board[CellIndex(&game, pos)]
	center.units[0] = 1
	center.relay = 0
	game.board[CellIndex(&game, Hex{1, 0})].relay = 0
	game.board[CellIndex(&game, Hex{0, 1})].relay = 0
	game.board[CellIndex(&game, Hex{-1, 1})].relay = 0
	testing.expect(t, !ApplyAiProtocol(&game, 10, {to = {2, 0}, resource = .Energy}))
	testing.expect(t, !ApplyAiProtocol(&game, 10, {to = pos, resource = ResourceKind(99)}))
	testing.expect(t, ApplyAiProtocol(&game, 10, {to = pos, resource = .Energy}))
	testing.expect_value(t, game.players[0].resources, Resources{7, 5})
	testing.expect(t, ApplyAiProtocol(&game, 10, {to = pos, resource = .Data}))
	testing.expect_value(t, game.players[0].resources, Resources{7, 7})
	testing.expect(t, ApplyAiProtocol(&game, 10, {to = pos, resource = .Energy}))
	testing.expect_value(t, game.players[0].resources.energy, RESOURCE_CAP)
	game.board[CellIndex(&game, Hex{1, 0})].rift = true
	game.board[CellIndex(&game, Hex{0, 1})].relay = 1
	game.board[CellIndex(&game, Hex{-1, 1})].relay = NO_PLAYER
	game.players[0].resources.data = 0
	testing.expect(t, ApplyAiProtocol(&game, 10, {to = pos, resource = .Data}))
	testing.expect_value(t, game.players[0].resources.data, 0)
}

@(test)
TestAiCompile :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	game.players[0].resources = {0, 0}
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	testing.expect(t, !ApplyAiProtocol(&game, 11, {to = pos, terrain = .Cover}))
	cell.units[0] = 1
	testing.expect(t, !ApplyAiProtocol(&game, 11, {to = pos, terrain = Terrain(99)}))
	testing.expect(t, !ApplyAiProtocol(&game, 11, {to = pos, terrain = .Open}))
	testing.expect(t, ApplyAiProtocol(&game, 11, {to = pos, terrain = .Energy_Node}))
	testing.expect_value(t, cell.terrain, Terrain.Energy_Node)
	testing.expect_value(t, game.players[0].resources, Resources{1, 0})
	testing.expect(t, !ApplyAiProtocol(&game, 11, {to = pos, terrain = .Energy_Node}))
	testing.expect(t, ApplyAiProtocol(&game, 11, {to = pos, terrain = .Data_Node}))
	testing.expect_value(t, game.players[0].resources, Resources{1, 1})
	testing.expect(t, ApplyAiProtocol(&game, 11, {to = pos, terrain = .Cover}))
	testing.expect_value(t, game.players[0].resources, Resources{1, 1})
	game.players[0].resources.energy = RESOURCE_CAP
	testing.expect(t, ApplyAiProtocol(&game, 11, {to = pos, terrain = .Energy_Node}))
	testing.expect_value(t, game.players[0].resources.energy, RESOURCE_CAP)
}

@(test)
TestAiPulseAndInvalidCards :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	testing.expect(t, ApplyAiProtocol(&game, 12, {}))
	testing.expect(t, game.players[0].pulse)
	testing.expect(t, !game.players[1].pulse)
	for id in -1..<3 do testing.expect(t, !ApplyAiProtocol(&game, id, {}))
	testing.expect(t, !ApplyAiProtocol(&game, 13, {}))
	game.players[0].faction = .Nomad
	testing.expect(t, !ApplyAiProtocol(&game, 12, {}))
	testing.expect(t, !ApplyAiProtocol(nil, 12, {}))
}
