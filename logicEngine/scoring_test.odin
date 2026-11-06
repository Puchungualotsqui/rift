#+build !js

package logicEngine

import "core:testing"

ScoringTestGame :: proc() -> Game {
	game: Game
	game.playerCount = 4
	game.round = 1
	game.phase = .Score_Objective
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	game.players[2].faction = .AI
	game.players[3].faction = .Nomad
	i := 0
	for q in -BOARD_RADIUS..=BOARD_RADIUS {
		for r in -BOARD_RADIUS..=BOARD_RADIUS {
			pos := Hex{q, r}
			if !HexValid(pos) do continue
			game.board[i].pos = pos
			game.board[i].relay = NO_PLAYER
			i += 1
		}
	}
	return game
}

ScoringTestCell :: proc(game: ^Game, pos: Hex) -> ^Cell {
	return &game.board[CellIndex(game, pos)]
}

@(test)
TestGlobalObjectivesAndPhase :: proc(t: ^testing.T) {
	game := ScoringTestGame()
	a := ScoringTestCell(&game, {0, 0})
	b := ScoringTestCell(&game, {1, 0})
	c := ScoringTestCell(&game, {2, 0})
	a.units[0] = 2
	b.units[0] = 1
	c.units[0] = 1
	a.terrain = .Energy_Node
	b.structures[0] = true
	game.players[0].resources = {2, 3}
	game.players[0].roundCombatWins = 1
	for round in 1..=5 {testing.expect(t, ObjectiveMet(&game, 0, round))}
	testing.expect(t, !ObjectiveMet(&game, 0, 6))
	game.playerCount = 2
	testing.expect(t, ObjectiveMet(&game, 0, 6))
	game.playerCount = 4
	testing.expect(t, !ObjectiveMet(&game, 0, 0))
	testing.expect(t, !ObjectiveMet(&game, 0, 7))

	// Multiple players score independently, and advancing resets round wins.
	ScoringTestCell(&game, {-1, 0}).units[1] = 1
	ScoringTestCell(&game, {-2, 0}).units[1] = 1
	testing.expect(t, ScoreAndCompleteObjective(&game))
	testing.expect_value(t, game.players[0].publicVp, 2)
	testing.expect_value(t, game.players[1].publicVp, 2)
	testing.expect_value(t, game.players[0].objectivesScored, 1)
	testing.expect_value(t, game.players[0].roundCombatWins, 0)
	testing.expect_value(t, game.round, 2)
	testing.expect_value(t, game.phase, Phase.Await_Turn)
	testing.expect(t, !ScoreAndCompleteObjective(&game))
	testing.expect_value(t, game.players[0].publicVp, 2)
}

@(test)
TestObjectiveBoundariesAndSharedControl :: proc(t: ^testing.T) {
	game := ScoringTestGame()
	for round in 1..=6 {testing.expect(t, !ObjectiveMet(&game, 0, round))}
	game.players[0].resources = {2, 2}
	testing.expect(t, !ObjectiveMet(&game, 0, 2))
	game.players[0].roundCombatWins = 1
	game.players[0].combatWins = 0
	testing.expect(t, ObjectiveMet(&game, 0, 4))
	game.players[0].roundCombatWins = 0
	game.players[0].combatWins = 2
	testing.expect(t, !ObjectiveMet(&game, 0, 4))

	cell := ScoringTestCell(&game, {0, 0})
	cell.units[0] = 1
	cell.units[1] = 1
	cell.relay = 2
	testing.expect(t, !Controls(&game, 0, cell.pos))
	testing.expect(t, Controls(&game, 2, cell.pos))
	testing.expect_value(t, CalculateScoringStats(&game, 2).developed, 1)
	cell.units[1] = 0
	testing.expect(t, Controls(&game, 0, cell.pos))
	testing.expect_value(t, CalculateScoringStats(&game, 0).developed, 1)
	cell.rift = true
	testing.expect_value(t, CalculateScoringStats(&game, 0).controlled, 0)
	testing.expect_value(t, CalculateScoringStats(&game, 2).relays, 0)
}

@(test)
TestDirectives :: proc(t: ^testing.T) {
	game := ScoringTestGame()
	p := &game.players[0]
	p.combatWins = 3
	p.unitsDestroyed = 3
	p.tokensDestroyed = 2
	p.resources = {3, 3}
	p.cardsPlayed = 6
	p.objectivesScored = 3
	positions := [?]Hex{{0, 0}, {1, 0}, {2, 0}, {0, 1}, {0, 2}}
	for pos in positions {ScoringTestCell(&game, pos).units[0] = 1}
	ScoringTestCell(&game, {1, 0}).terrain = .Energy_Node
	ScoringTestCell(&game, {2, 0}).terrain = .Data_Node
	for id in 0..<DIRECTIVE_COUNT {testing.expect(t, DirectiveMet(&game, 0, id))}
	testing.expect(t, !DirectiveMet(&game, 0, -1))
	testing.expect(t, !DirectiveMet(&game, 0, DIRECTIVE_COUNT))

	p.combatWins = 2
	p.unitsDestroyed = 2
	p.tokensDestroyed = 1
	p.resources = {2, 3}
	p.cardsPlayed = 5
	p.objectivesScored = 2
	for id in ([?]int{0, 1, 2, 4, 8, 10}) {testing.expect(t, !DirectiveMet(&game, 0, id))}
	ScoringTestCell(&game, {0, 0}).rift = true
	ScoringTestCell(&game, {2, 0}).rift = true
	ScoringTestCell(&game, {0, 2}).rift = true
	for id in ([?]int{3, 5, 6, 7, 9, 11}) {testing.expect(t, !DirectiveMet(&game, 0, id))}
}

@(test)
TestFactionScoringAndNetworks :: proc(t: ^testing.T) {
	game := ScoringTestGame()
	ScoringTestCell(&game, {-2, 0}).units[0] = 3
	ScoringTestCell(&game, {-1, 0}).units[0] = 2
	testing.expect_value(t, FactionVp(&game, 0), 4)
	ScoringTestCell(&game, {1, 0}).structures[1] = true
	ScoringTestCell(&game, {2, 0}).structures[1] = true
	game.players[1].resources = {4, 4}
	testing.expect_value(t, FactionVp(&game, 1), 6)
	game.players[3].unitsDestroyed = 3
	game.players[3].structuresDestroyed = 2
	game.players[3].tokensDestroyed = 9
	game.players[3].resourcesStolen = 8
	testing.expect_value(t, FactionVp(&game, 3), 7)

	for pos in ([?]Hex{{-2, 2}, {-1, 1}, {0, 0}}) {ScoringTestCell(&game, pos).relay = 2}
	ScoringTestCell(&game, {2, -2}).relay = 2
	ScoringTestCell(&game, {2, 0}).relay = 2
	testing.expect_value(t, CalculateScoringStats(&game, 2).largestRelayNetwork, 3)
	testing.expect_value(t, FactionVp(&game, 2), 7)
	ScoringTestCell(&game, {1, -1}).relay = 2
	testing.expect_value(t, CalculateScoringStats(&game, 2).largestRelayNetwork, 5)
	testing.expect_value(t, FactionVp(&game, 2), 10)
	// An enemy can control the same hex as the AI relay; it still develops it.
	testing.expect(t, Controls(&game, 1, Hex{2, 0}))
	testing.expect(t, Controls(&game, 2, Hex{2, 0}))
	testing.expect(t, CalculateScoringStats(&game, 1).developed >= 1)
	ScoringTestCell(&game, {1, -1}).rift = true
	testing.expect_value(t, CalculateScoringStats(&game, 2).largestRelayNetwork, 3)
}

@(test)
TestTwoPlayerFactionScoring :: proc(t: ^testing.T) {
	game := ScoringTestGame()
	game.playerCount = 2
	cell := ScoringTestCell(&game, {0, 0})
	cell.units[0] = 2
	testing.expect_value(t, FactionVp(&game, 0), 1)
	game.players[0].faction = .Corp
	cell.structures[0] = true
	game.players[0].resources = {3, 3}
	testing.expect_value(t, FactionVp(&game, 0), 3)
	game.players[0].faction = .Nomad
	game.players[0].unitsDestroyed = 1
	game.players[0].structuresDestroyed = 1
	game.players[0].resourcesStolen = 5
	testing.expect_value(t, FactionVp(&game, 0), 4)
	game.players[0].faction = .AI
	positions := [?]Hex{{0, 0}, {1, 0}, {2, 0}, {1, -1}, {0, -1}, {-1, 0}}
	for pos, i in positions {
		ScoringTestCell(&game, pos).relay = 0
		if i == 2 do testing.expect_value(t, FactionVp(&game, 0), 3)
		if i == 3 do testing.expect_value(t, FactionVp(&game, 0), 6)
		if i == 4 do testing.expect_value(t, FactionVp(&game, 0), 7)
		if i == 5 do testing.expect_value(t, FactionVp(&game, 0), 10)
	}
}

@(test)
TestFinalScoringAndTiebreaks :: proc(t: ^testing.T) {
	game := ScoringTestGame()
	game.playerCount = 2
	game.round = 6
	for pos in ([?]Hex{{0, 0}, {1, 0}, {2, 0}}) {ScoringTestCell(&game, pos).units[0] = 1}
	game.players[0].directives[0] = 11
	game.players[0].directiveCount = 1
	game.players[0].objectivesScored = 2
	testing.expect(t, ScoreAndCompleteObjective(&game))
	testing.expect_value(t, game.phase, Phase.Finished)
	testing.expect_value(t, game.players[0].objectivesScored, 3)
	result: FinalScores
	testing.expect(t, CalculateFinalScores(&game, &result))
	testing.expect_value(t, result.players[0].publicVp, 2)
	testing.expect_value(t, result.players[0].factionVp, 4)
	testing.expect_value(t, result.players[0].directiveVp, 2)
	testing.expect_value(t, result.players[0].totalVp, 8)
	testing.expect(t, result.winners[0])
	testing.expect_value(t, result.winnerCount, 1)
	testing.expect(t, CalculateFinalScores(&game, &result))
	testing.expect_value(t, game.players[0].publicVp, 2)

	base := PlayerScore{totalVp = 10, publicVp = 2, directivesCompleted = 1, factionVp = 6, resources = 3}
	other := base
	testing.expect_value(t, CompareScores(base, other), 0)
	other.resources = 2
	testing.expect(t, CompareScores(base, other) > 0)
	other.factionVp = 7
	testing.expect(t, CompareScores(base, other) < 0)
	other.directivesCompleted = 0
	testing.expect(t, CompareScores(base, other) > 0)
	other.publicVp = 3
	testing.expect(t, CompareScores(base, other) < 0)
	other.totalVp = 9
	testing.expect(t, CompareScores(base, other) > 0)

	game.players[0] = {}
	game.players[1] = {}
	game.players[1].faction = .Swarm
	for &cell in game.board {cell.units[0] = 0}
	testing.expect(t, CalculateFinalScores(&game, &result))
	testing.expect_value(t, result.winnerCount, 2)
	testing.expect(t, result.winners[0] && result.winners[1])
	game.players[0].directiveCount = 1
	game.players[0].directives[0] = DIRECTIVE_COUNT
	result.winnerCount = 99
	testing.expect(t, !CalculateFinalScores(&game, &result))
	testing.expect_value(t, result.winnerCount, 99)
}
