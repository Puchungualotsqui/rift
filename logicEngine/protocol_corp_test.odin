#+build !js

package logicEngine

import "core:testing"

@(test)
TestCorpHostileTakeover :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.currentPlayer = 1
	game.players[1].faction = .Corp
	game.players[1].resources = {2, 3}
	game.players[0].resources = {1, 2}
	before := game
	testing.expect(t, !ApplyCorpProtocol(&game, 3, {other = -1, resource = .Energy}))
	testing.expect(t, !ApplyCorpProtocol(&game, 3, {other = 1, resource = .Energy}))
	testing.expect(t, !ApplyCorpProtocol(&game, 3, {other = 2, resource = .Energy}))
	testing.expect(t, !ApplyCorpProtocol(&game, 3, {other = 0, resource = ResourceKind(99)}))
	testing.expect_value(t, game, before)
	testing.expect(t, ApplyCorpProtocol(&game, 3, {other = 0, resource = .Energy}))
	testing.expect_value(t, game.players[1].resources, Resources{3, 3})
	testing.expect_value(t, game.players[0].resources, Resources{0, 2})
	testing.expect_value(t, game.players[1].resourcesStolen, 1)
	testing.expect(t, !ApplyCorpProtocol(&game, 3, {other = 0, resource = .Energy}))
	testing.expect(t, ApplyCorpProtocol(&game, 3, {other = 0, resource = .Data}))
	testing.expect_value(t, game.players[1].resources, Resources{3, 4})
	testing.expect_value(t, game.players[0].resources, Resources{0, 1})
	testing.expect_value(t, game.players[1].resourcesStolen, 2)
	game.players[1].resources.data = RESOURCE_CAP
	before = game
	testing.expect(t, !ApplyCorpProtocol(&game, 3, {other = 0, resource = .Data}))
	testing.expect_value(t, game, before)
}

@(test)
TestCorpFortify :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	testing.expect(t, !ApplyCorpProtocol(&game, 4, {to = pos}))
	cell.units[0] = 1
	testing.expect(t, !ApplyCorpProtocol(&game, 4, {to = pos}))
	cell.structures[0] = true
	cell.units[1] = 1
	testing.expect(t, !ApplyCorpProtocol(&game, 4, {to = pos}))
	cell.units[1] = 0
	cell.rift = true
	testing.expect(t, !ApplyCorpProtocol(&game, 4, {to = pos}))
	cell.rift = false
	testing.expect(t, !ApplyCorpProtocol(&game, 4, {to = {4, 0}}))
	testing.expect(t, ApplyCorpProtocol(&game, 4, {to = pos}))
	testing.expect(t, cell.fortified[0] && !cell.fortified[1])
	testing.expect_value(t, CombatDefense(&game, cell, 0), 4)
}

@(test)
TestCorpFortifyDuration :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	cell.structures[0] = true
	testing.expect(t, ApplyCorpProtocol(&game, 4, {to = pos}))
	testing.expect(t, ApplyCorpProtocol(&game, 7, {to = pos}))
	testing.expect(t, EndTurn(&game))
	testing.expect(t, cell.fortified[0] && cell.shielded[0])
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, cell.fortified[0] && cell.shielded[0])
	// Resume at the Corp's next turn without cycling through scoring here.
	game.currentPlayer = 0
	game.phase = .Await_Turn
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, !cell.fortified[0] && cell.shielded[0])
}

@(test)
TestCorpDividend :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	game.players[0].resources.data = 0
	testing.expect(t, ApplyCorpProtocol(&game, 5, {}))
	testing.expect_value(t, game.players[0].resources.data, 0)
	game.board[CellIndex(&game, {0, 0})].structures[0] = true
	game.board[CellIndex(&game, {1, 0})].structures[0] = true
	game.board[CellIndex(&game, {0, 1})].structures[0] = true
	game.board[CellIndex(&game, {-1, 0})].structures[0] = true
	contested := &game.board[CellIndex(&game, {0, -1})]
	contested.structures[0], contested.units[1] = true, 1
	rift := &game.board[CellIndex(&game, {1, -1})]
	rift.structures[0], rift.rift = true, true
	testing.expect(t, ApplyCorpProtocol(&game, 5, {}))
	testing.expect_value(t, game.players[0].resources.data, 3)
	game.board[CellIndex(&game, {1, 0})].structures[0] = false
	game.board[CellIndex(&game, {0, 1})].structures[0] = false
	game.board[CellIndex(&game, {-1, 0})].structures[0] = false
	testing.expect(t, ApplyCorpProtocol(&game, 5, {}))
	testing.expect_value(t, game.players[0].resources.data, 4)
	game.players[0].resources.data = RESOURCE_CAP
	testing.expect(t, ApplyCorpProtocol(&game, 5, {}))
	testing.expect_value(t, game.players[0].resources.data, RESOURCE_CAP)
}

@(test)
TestCorpLobbyAndShareholderValue :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	player := &game.players[0]
	player.resources.data = 0
	player.deck[0], player.deck[1], player.deck[2] = 4, 5, 6
	player.deckCount = 3
	testing.expect(t, ApplyCorpProtocol(&game, 6, {}))
	testing.expect_value(t, player.handCount, 2)
	testing.expect_value(t, player.hand[0], 6)
	testing.expect_value(t, player.hand[1], 5)
	testing.expect_value(t, player.deckCount, 1)
	testing.expect(t, ApplyCorpProtocol(&game, 12, {}))
	testing.expect_value(t, player.hand[2], 4)
	testing.expect_value(t, player.deckCount, 0)
	testing.expect_value(t, player.resources.data, 1)
	testing.expect(t, ApplyCorpProtocol(&game, 6, {}))
	testing.expect(t, ApplyCorpProtocol(&game, 12, {}))
	testing.expect_value(t, player.resources.data, 2)
	player.handCount = HAND_LIMIT - 1
	player.deck[0], player.deck[1] = 7, 8
	player.deckCount = 2
	testing.expect(t, ApplyCorpProtocol(&game, 6, {}))
	testing.expect_value(t, player.handCount, HAND_LIMIT)
	testing.expect_value(t, player.hand[HAND_LIMIT - 1], 8)
	testing.expect_value(t, player.deckCount, 1)
	player.resources.data = RESOURCE_CAP
	testing.expect(t, ApplyCorpProtocol(&game, 12, {}))
	testing.expect_value(t, player.resources.data, RESOURCE_CAP)
	testing.expect_value(t, player.deckCount, 1)
}

@(test)
TestCorpRedundancy :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	testing.expect(t, !ApplyCorpProtocol(&game, 7, {to = pos}))
	cell.units[0] = 1
	testing.expect(t, !ApplyCorpProtocol(&game, 7, {to = pos}))
	cell.structures[0] = true
	cell.units[1] = 1
	testing.expect(t, !ApplyCorpProtocol(&game, 7, {to = pos}))
	cell.units[1] = 0
	cell.rift = true
	testing.expect(t, !ApplyCorpProtocol(&game, 7, {to = pos}))
	cell.rift = false
	testing.expect(t, ApplyCorpProtocol(&game, 7, {to = pos}))
	testing.expect(t, cell.shielded[0])
	before := game
	testing.expect(t, !ApplyCorpProtocol(&game, 7, {to = pos}))
	testing.expect_value(t, game, before)
	testing.expect(t, !DestroyStructure(&game, pos, 0, 1))
	testing.expect(t, cell.structures[0] && !cell.shielded[0])
	testing.expect_value(t, game.players[1].structuresDestroyed, 0)
	testing.expect(t, DestroyStructure(&game, pos, 0, 1))
	testing.expect(t, !cell.structures[0])
	testing.expect_value(t, game.players[1].structuresDestroyed, 1)
}

@(test)
TestCorpBailoutAndContract :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	game.players[0].resources = {0, RESOURCE_CAP - 1}
	testing.expect(t, ApplyCorpProtocol(&game, 8, {}))
	testing.expect_value(t, game.players[0].resources, Resources{0, RESOURCE_CAP})
	pos := Hex{0, 0}
	cell := &game.board[CellIndex(&game, pos)]
	cell.terrain = .Energy_Node
	testing.expect(t, !ApplyCorpProtocol(&game, 9, {to = pos}))
	cell.units[0] = 1
	cell.units[1] = 1
	testing.expect(t, !ApplyCorpProtocol(&game, 9, {to = pos}))
	cell.units[1] = 0
	cell.rift = true
	testing.expect(t, !ApplyCorpProtocol(&game, 9, {to = pos}))
	cell.rift = false
	cell.terrain = .Cover
	testing.expect(t, !ApplyCorpProtocol(&game, 9, {to = pos}))
	cell.terrain = .Open
	testing.expect(t, !ApplyCorpProtocol(&game, 9, {to = pos}))
	cell.terrain = .Energy_Node
	testing.expect(t, ApplyCorpProtocol(&game, 9, {to = pos}))
	testing.expect_value(t, game.players[0].resources.energy, 3)
	game.players[0].resources.energy = RESOURCE_CAP - 1
	testing.expect(t, ApplyCorpProtocol(&game, 9, {to = pos}))
	testing.expect_value(t, game.players[0].resources.energy, RESOURCE_CAP)
	cell.terrain = .Data_Node
	game.players[0].resources.data = 4
	testing.expect(t, ApplyCorpProtocol(&game, 9, {to = pos}))
	testing.expect_value(t, game.players[0].resources.data, 7)
}

@(test)
TestCorpAutomate :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	testing.expect(t, ApplyCorpProtocol(&game, 10, {}))
	testing.expect(t, game.players[0].automate)
	testing.expect(t, !game.players[1].automate)
}

@(test)
TestCorpAutomateBuildsAndExpiry :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	game.players[0].resources = {0, 0}
	pos, other := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, pos)].units[0] = 1
	game.board[CellIndex(&game, other)].units[0] = 1
	testing.expect(t, ApplyCorpProtocol(&game, 10, {}))
	testing.expect(t, !BuildUnit(&game, {2, 0}))
	testing.expect(t, game.players[0].automate)
	testing.expect(t, BuildUnit(&game, pos))
	testing.expect_value(t, game.players[0].resources, Resources{})
	testing.expect_value(t, game.players[0].ap, 2)
	testing.expect(t, !game.players[0].automate)
	testing.expect(t, !BuildUnit(&game, pos))
	testing.expect(t, ApplyCorpProtocol(&game, 10, {}))
	testing.expect(t, BuildStructure(&game, other))
	testing.expect(t, game.board[CellIndex(&game, other)].structures[0])
	testing.expect_value(t, game.players[0].resources, Resources{})
	testing.expect_value(t, game.players[0].ap, 1)
	testing.expect(t, !game.players[0].automate)
	testing.expect(t, ApplyCorpProtocol(&game, 10, {}))
	testing.expect(t, EndTurn(&game))
	testing.expect(t, !game.players[0].automate)
}

@(test)
TestCorpAudit :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.currentPlayer = 1
	game.players[1].faction = .Corp
	opponent := &game.players[0]
	opponent.hand[0], opponent.hand[1], opponent.hand[2] = 2, 4, 7
	opponent.handCount = 3
	before := game
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = -1, cardIndex = 0}))
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = 1, cardIndex = 0}))
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = 2, cardIndex = 0}))
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = 0, cardIndex = -1}))
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = 0, cardIndex = 3}))
	testing.expect_value(t, game, before)
	testing.expect(t, ApplyCorpProtocol(&game, 11, {other = 0, cardIndex = 1}))
	testing.expect_value(t, opponent.handCount, 2)
	testing.expect_value(t, opponent.hand[0], 2)
	testing.expect_value(t, opponent.hand[1], 7)
	testing.expect_value(t, opponent.discardCount, 1)
	testing.expect_value(t, opponent.discard[0], 4)
	testing.expect_value(t, opponent.cardsPlayed, 0)
	testing.expect_value(t, game.players[1].cardsPlayed, 0)
	opponent.discardCount = len(opponent.discard)
	before = game
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = 0, cardIndex = 0}))
	testing.expect_value(t, game, before)
	opponent.handCount = 0
	opponent.discardCount = 0
	testing.expect(t, !ApplyCorpProtocol(&game, 11, {other = 0, cardIndex = 0}))
}

@(test)
TestCorpMonopoly :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.playerCount = 4
	game.currentPlayer = 1
	game.players[1].faction = .Corp
	game.players[1].resources = {RESOURCE_CAP - 2, RESOURCE_CAP - 1}
	game.players[0].resources = {2, 1}
	game.players[2].resources = {0, 2}
	game.players[3].resources = {1, 0}
	before := game
	testing.expect(t, !ApplyCorpProtocol(&game, 13, {resource = ResourceKind(99)}))
	testing.expect_value(t, game, before)
	testing.expect(t, ApplyCorpProtocol(&game, 13, {resource = .Energy}))
	testing.expect_value(t, game.players[1].resources.energy, RESOURCE_CAP)
	testing.expect_value(t, game.players[0].resources.energy, 1)
	testing.expect_value(t, game.players[2].resources.energy, 0)
	testing.expect_value(t, game.players[3].resources.energy, 0)
	testing.expect_value(t, game.players[1].resourcesStolen, 2)
	testing.expect(t, ApplyCorpProtocol(&game, 13, {resource = .Data}))
	testing.expect_value(t, game.players[1].resources.data, RESOURCE_CAP)
	testing.expect_value(t, game.players[0].resources.data, 0)
	testing.expect_value(t, game.players[2].resources.data, 1)
	testing.expect_value(t, game.players[3].resources.data, 0)
	testing.expect_value(t, game.players[1].resourcesStolen, 3)
	// A full stockpile does not prevent opponents from losing resources.
	testing.expect(t, ApplyCorpProtocol(&game, 13, {resource = .Energy}))
	testing.expect_value(t, game.players[0].resources.energy, 0)
	testing.expect_value(t, game.players[1].resources.energy, RESOURCE_CAP)
	testing.expect_value(t, game.players[1].resourcesStolen, 3)
	game.players[2].resources.data = 0
	testing.expect(t, ApplyCorpProtocol(&game, 13, {resource = .Data}))
	testing.expect_value(t, game.players[1].resources.data, RESOURCE_CAP)
}

@(test)
TestCorpInvalidCards :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Corp
	for id in -1..<3 do testing.expect(t, !ApplyCorpProtocol(&game, id, {}))
	testing.expect(t, !ApplyCorpProtocol(&game, 14, {}))
	game.players[0].faction = .Swarm
	testing.expect(t, !ApplyCorpProtocol(&game, 8, {}))
	testing.expect(t, !ApplyCorpProtocol(nil, 8, {}))
	game.players[0].faction = .Corp
	game.currentPlayer = -1
	testing.expect(t, !ApplyCorpProtocol(&game, 8, {}))
	game.currentPlayer = 0
	game.playerCount = MAX_PLAYERS + 1
	testing.expect(t, !ApplyCorpProtocol(&game, 8, {}))
}
