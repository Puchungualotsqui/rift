#+build !js

package logicEngine

import "core:testing"

@(test)
TestSetupAndTurns :: proc(t: ^testing.T) {
	config: SetupConfig
	config.playerCount = 2
	config.players[0].faction = .Swarm
	config.players[0].start = {-2, 0}
	config.players[1].faction = .Corp
	config.players[1].start = {2, 0}

	for i in 0..<15 {config.terrainOrder[i] = i}
	for i in 0..<12 {config.directiveOrder[i] = i}
	for i in 0..<14 {
		config.players[0].deck[i] = i
		config.players[1].deck[i] = i
	}
	game: Game
	testing.expect(t, SetupGame(&game, config))
	testing.expect_value(t, game.players[0].handCount, 3)
	testing.expect_value(t, game.players[0].hand[0], 11)
	testing.expect_value(t, game.players[0].resources, Resources{2, 1})
	testing.expect(t, BeginTurn(&game))
	testing.expect_value(t, game.players[0].resources, Resources{3, 2})
	testing.expect(t, MoveUnits(&game, {-2, 0}, {-1, 0}, 2))
	testing.expect(t, BuildUnit(&game, {-1, 0}))
	testing.expect_value(t, game.players[0].ap, 1)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, EndTurn(&game))
	testing.expect_value(t, game.phase, Phase.Score_Objective)
	testing.expect(t, !BeginTurn(&game))
	testing.expect(t, ScoreAndCompleteObjective(&game))
	testing.expect_value(t, game.currentPlayer, 1)
	testing.expect_value(t, game.round, 2)
	for _ in 2..=ROUND_COUNT {
		for _ in 0..<2 {
			testing.expect(t, BeginTurn(&game))
			testing.expect(t, EndTurn(&game))
		}
		testing.expect(t, ScoreAndCompleteObjective(&game))
	}
	testing.expect_value(t, game.phase, Phase.Finished)
	testing.expect(t, !ScoreAndCompleteObjective(&game))
}
