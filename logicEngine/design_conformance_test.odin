#+build !js

package logicEngine

import "core:testing"

@(test)
TestScorchedEarthUsesControlAndCanDestroyEnemyRelay :: proc(t: ^testing.T) {
	game := IntegrationProtocolGame(.Nomad, 5)
	pos := Hex{0, 0}
	cell := IntegrationCell(&game, pos)
	cell.relay = 1
	choice := ProtocolChoice{to = pos, target = .Relay}
	cell.units[1] = 1
	before := game
	testing.expect(t, !PlayProtocol(&game, 1, choice))
	testing.expect_value(t, game, before)

	cell.units[1] = 0
	testing.expect(t, Controls(&game, 0, pos))
	testing.expect(t, PlayProtocol(&game, 1, choice))
	testing.expect_value(t, cell.relay, NO_PLAYER)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
}

@(test)
TestStartHexesRemainOpen :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .AI
	game.players[0].ap = 3
	game.players[0].resources = {2, 2}
	pos := START_HEXES[0]
	cell := IntegrationCell(&game, pos)
	cell.units[0] = 1
	before := game
	testing.expect(t, !RewireTerrain(&game, pos, .Energy_Node))
	testing.expect_value(t, game, before)

	game.players[0].hand[0] = 11
	game.players[0].handCount = 1
	before = game
	testing.expect(t, !PlayProtocol(&game, 0, ProtocolChoice{to = pos, terrain = .Data_Node}))
	testing.expect_value(t, game, before)
}
