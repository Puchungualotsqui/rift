#+build !js

package logicEngine

import "core:testing"

@(test)
TestSeededSetupShuffle :: proc(t: ^testing.T) {
	first := IntegrationSetup()
	second := first
	testing.expect(t, PrepareShuffledSetup(&first, 42))
	testing.expect(t, PrepareShuffledSetup(&second, 42))
	testing.expect_value(t, first, second)
	testing.expect(t, ValidPermutation(first.terrainOrder[:]))
	testing.expect(t, ValidPermutation(first.directiveOrder[:]))
	for i in 0..<first.playerCount {
		size := FactionDeckSize(first.players[i].faction)
		testing.expect(t, ValidPermutation(first.players[i].deck[:size]))
	}
	testing.expect(t, first.firstPlayer >= 0 && first.firstPlayer < first.playerCount)
	game: Game
	testing.expect(t, SetupGame(&game, first))
	invalid := first
	invalid.players[1].faction = invalid.players[0].faction
	before := invalid
	testing.expect(t, !PrepareShuffledSetup(&invalid, 42))
	testing.expect_value(t, invalid, before)
}

@(test)
TestTwoPlayerRiftsAndTerrain :: proc(t: ^testing.T) {
	config := IntegrationSetup()
	config.playerCount = 2
	config.players[0].start = {-2, 0}
	config.players[1].start = {2, 0}
	rifts, count, ok := SelectRifts(config)
	testing.expect(t, ok)
	testing.expect_value(t, count, 6)
	expected := [?]Hex{{0, -2}, {0, 2}, {-1, 2}, {1, -2}, {-2, 2}, {2, -2}}
	testing.expect_value(t, rifts, expected)
	game: Game
	testing.expect(t, SetupGame(&game, config))
	active, riftTotal, terrainTotal := 0, 0, 0
	for &cell in game.board {
		if cell.rift {
			riftTotal += 1
		} else {
			active += 1
			if !IsStartHex(cell.pos) do terrainTotal += 1
		}
	}
	testing.expect_value(t, active, 13)
	testing.expect_value(t, riftTotal, 6)
	testing.expect_value(t, terrainTotal, 11)
}

@(test)
TestThreePlayerRiftsLeaveNeutralStartActive :: proc(t: ^testing.T) {
	config := IntegrationSetup()
	config.playerCount = 3
	rifts, count, ok := SelectRifts(config)
	testing.expect(t, ok)
	testing.expect_value(t, count, 3)
	expected := [?]Hex{{-1, 2}, {-2, 2}, {2, -2}, {}, {}, {}}
	testing.expect_value(t, rifts, expected)
	game: Game
	testing.expect(t, SetupGame(&game, config))
	neutral := &game.board[CellIndex(&game, Hex{0, 2})]
	testing.expect(t, !neutral.rift)
	testing.expect_value(t, neutral.terrain, Terrain.Open)
	testing.expect_value(t, UnitCount(neutral), 0)
	active := 0
	for &cell in game.board do if !cell.rift do active += 1
	testing.expect_value(t, active, 16)
}

CheckActiveBoardConnected :: proc(t: ^testing.T, game: ^Game) {
	seen: [HEX_COUNT]bool
	queue: [HEX_COUNT]int
	first := -1
	active := 0
	for &cell, i in game.board {
		if cell.rift do continue
		active += 1
		if first < 0 do first = i
	}
	testing.expect(t, first >= 0)
	if first < 0 do return
	queue[0], seen[first] = first, true
	count, head := 1, 0
	for head < count {
		current := queue[head]
		head += 1
		for &cell, i in game.board {
			if cell.rift || seen[i] || !HexAdjacent(cell.pos, game.board[current].pos) do continue
			seen[i] = true
			queue[count] = i
			count += 1
		}
	}
	testing.expect_value(t, count, active)
}

@(test)
TestRiftLayoutsRemainConnected :: proc(t: ^testing.T) {
	starts := START_HEXES
	for unused in 0..<len(starts) {
		config := IntegrationSetup()
		config.playerCount = 3
		player := 0
		for i in 0..<len(starts) {
			if i == unused do continue
			config.players[player].start = starts[i]
			player += 1
		}
		game: Game
		testing.expect(t, SetupGame(&game, config))
		CheckActiveBoardConnected(t, &game)
	}
	for pair in 0..<2 {
		config := IntegrationSetup()
		config.playerCount = 2
		config.players[0].start = starts[pair]
		config.players[1].start = starts[pair + 2]
		game: Game
		testing.expect(t, SetupGame(&game, config))
		CheckActiveBoardConnected(t, &game)
	}
}

@(test)
TestRiftSelectionRejectsInvalidStarts :: proc(t: ^testing.T) {
	config := IntegrationSetup()
	config.playerCount = 2
	config.players[1].start = config.players[0].start
	_, count, ok := SelectRifts(config)
	testing.expect(t, !ok)
	testing.expect_value(t, count, 0)
	config.players[1].start = {0, -2}
	_, count, ok = SelectRifts(config)
	testing.expect(t, !ok)
	testing.expect_value(t, count, 0)
	config.playerCount = 5
	_, count, ok = SelectRifts(config)
	testing.expect(t, !ok)
	testing.expect_value(t, count, 0)
	config = IntegrationSetup()
	_, count, ok = SelectRifts(config)
	testing.expect(t, ok)
	testing.expect_value(t, count, 0)
}
