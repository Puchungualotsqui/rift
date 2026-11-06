#+build !js

package logicEngine

import "core:testing"

CombatTestGame :: proc() -> Game {
	game: Game
	game.playerCount = 2
	game.phase = .Acting
	game.players[0].ap = 3
	game.players[0].resources = {8, 8}
	game.players[1].resources = {8, 8}
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

@(test)
TestStrikeAndCapture :: proc(t: ^testing.T) {
	game := CombatTestGame()
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0] = 3
	target.units[1] = 1
	target.structures[1] = true
	result, ok := StrikeWithCards(&game, from, to, 3, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured)
	testing.expect_value(t, result.attackerStrength, 3)
	testing.expect_value(t, result.defenderStrength, 2)
	testing.expect_value(t, source.units[0], 2)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.units[1], 0)
	testing.expect(t, !target.structures[1])
	testing.expect_value(t, game.players[0].ap, 2)
	testing.expect_value(t, game.players[0].combatWins, 1)
	testing.expect_value(t, game.players[0].roundCombatWins, 1)
	testing.expect_value(t, game.players[0].unitsDestroyed, 1)
	testing.expect_value(t, game.players[0].structuresDestroyed, 1)
	testing.expect_value(t, game.players[0].tokensDestroyed, 2)
}

@(test)
TestDefenseTieAndAtomicFailure :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[1].faction = .AI
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0] = 3
	target.units[1] = 1
	target.terrain = .Cover
	game.board[CellIndex(&game, Hex{1, -1})].relay = 1
	_, ok := StrikeWithCards(&game, from, to, 4, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, !ok)
	testing.expect_value(t, game.players[0].ap, 3)
	result, legal := StrikeWithCards(&game, from, to, 3, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, legal && !result.attackerWon && !result.captured)
	testing.expect_value(t, result.defenderStrength, 3)
	testing.expect_value(t, source.units[0], 2)
	testing.expect_value(t, target.units[1], 1)
	testing.expect_value(t, game.players[1].combatWins, 1)
	testing.expect_value(t, game.players[1].tokensDestroyed, 1)
}

@(test)
TestStructureOnlyAndDeclinedCapture :: proc(t: ^testing.T) {
	game := CombatTestGame()
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 3
	target := &game.board[CellIndex(&game, to)]
	target.units[1] = 1
	target.structures[1] = true
	result, ok := StrikeWithCards(&game, from, to, 3, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && !result.captured)
	testing.expect(t, target.structures[1])
	result, ok = StrikeWithCards(&game, from, to, 3, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured && result.structureDestroyed)
	testing.expect(t, !result.unitDestroyed && !target.structures[1])
	testing.expect_value(t, game.players[0].ap, 1)
	testing.expect_value(t, game.players[0].combatWins, 2)
	testing.expect_value(t, game.players[0].structuresDestroyed, 1)
}

@(test)
TestFactionActions :: proc(t: ^testing.T) {
	game := CombatTestGame()
	a, b := Hex{0, 0}, Hex{1, 0}
	ca, cb := &game.board[CellIndex(&game, a)], &game.board[CellIndex(&game, b)]
	game.players[0].faction = .Swarm
	ca.units[0] = 1
	cb.units[0] = 1
	duplicate := [?]Hex{a, a}
	testing.expect(t, !Proliferate(&game, duplicate[:]))
	testing.expect_value(t, game.players[0].ap, 3)
	positions := [?]Hex{a, b}
	testing.expect(t, Proliferate(&game, positions[:]))
	testing.expect_value(t, ca.units[0], 2)
	testing.expect_value(t, cb.units[0], 2)
	testing.expect_value(t, game.players[0].resources.energy, 7)
	game.players[0].faction = .Corp
	game.players[0].resources = {6, 6}
	ca.structures[0] = true
	cb.structures[0] = true
	testing.expect(t, Reinvest(&game))
	testing.expect_value(t, game.players[0].resources, Resources{8, 8})
	game.players[0].faction = .AI
	testing.expect(t, RewireRelay(&game, a))
	testing.expect_value(t, ca.relay, 0)
	testing.expect_value(t, game.players[0].resources.data, 7)
	testing.expect(t, !RewireRelay(&game, b)) // No AP left.
	game.players[0].ap = 1
	testing.expect(t, RewireTerrain(&game, b, .Cover))
	testing.expect_value(t, cb.terrain, Terrain.Cover)
}

@(test)
TestDestroyRelayOncePerTurn :: proc(t: ^testing.T) {
	game := CombatTestGame()
	a, b := Hex{0, 0}, Hex{1, 0}
	first := &game.board[CellIndex(&game, a)]
	second := &game.board[CellIndex(&game, b)]
	first.units[0] = 1
	first.relay = 1
	second.units[0] = 1
	second.relay = 1
	testing.expect(t, DestroyRelay(&game, a))
	testing.expect_value(t, first.relay, NO_PLAYER)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
	testing.expect_value(t, game.players[0].ap, 3)
	testing.expect(t, !DestroyRelay(&game, b))
	testing.expect_value(t, second.relay, 1)
	game.phase = .Await_Turn
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, DestroyRelay(&game, b))
}

@(test)
TestHitAndRunWithCards :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	from, to := Hex{0, 0}, Hex{1, 0}
	source, target := &game.board[CellIndex(&game, from)], &game.board[CellIndex(&game, to)]
	source.units[0] = 2
	target.units[1] = 1
	withoutStrike := game
	_, ok := HitAndRunWithCards(&withoutStrike, from, to, 2, false, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok)
	testing.expect_value(t, withoutStrike.board[CellIndex(&withoutStrike, to)].units[0], 2)
	testing.expect_value(t, withoutStrike.board[CellIndex(&withoutStrike, to)].units[1], 1)
	testing.expect_value(t, withoutStrike.players[0].combatWins, 0)
	testing.expect_value(t, withoutStrike.players[0].ap, 2)
	withoutStrike.players[0].hand[0] = 9 // Flee
	withoutStrike.players[0].handCount = 1
	testing.expect(t, PlayProtocol(&withoutStrike, 0, {from = to, to = from}))
	testing.expect_value(t, withoutStrike.board[CellIndex(&withoutStrike, from)].units[0], 1)
	result, legal := HitAndRunWithCards(&game, from, to, 2, true, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, legal && result.attackerWon && result.captured)
	testing.expect_value(t, source.units[0], 0)
	testing.expect_value(t, target.units[0], 2)
	testing.expect_value(t, target.units[1], 0)
	testing.expect_value(t, game.players[0].ap, 2)
}

@(test)
TestHitAndRunCapacityAndTie :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0] = 2
	target.units[1] = 2
	_, ok := HitAndRunWithCards(&game, from, to, 2, true, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, !ok)
	testing.expect_value(t, game.players[0].ap, 3)
	testing.expect_value(t, source.units[0], 2)
	target.units[1] = 1
	target.terrain = .Cover
	result, legal := HitAndRunWithCards(&game, from, to, 2, true, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, legal && !result.attackerWon)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.units[1], 1)
	testing.expect_value(t, game.players[1].unitsDestroyed, 1)
	testing.expect_value(t, game.players[0].ap, 2)
}

CombatGiveCard :: proc(game: ^Game, player, cardId: int) {
	game.players[player].hand[0] = cardId
	game.players[player].handCount = 1
}

CombatStrengthCase :: struct {
	faction: Faction,
	cardId: int,
	attacking: bool,
	strength: int,
	defenderStructure: bool,
	adjacentRelays, adjacentStructures: int,
}

@(test)
TestCombatCardStrengths :: proc(t: ^testing.T) {
	cases := [?]CombatStrengthCase{
		{.Swarm, 0, true,  3, false, 0, 0}, // Overwhelm
		{.Swarm, 1, false, 3, false, 0, 0}, // Chitin
		{.Swarm, 2, true,  4, false, 0, 0}, // Rush
		{.Corp,  0, false, 5, true,  0, 0}, // Ablative Plating
		{.Corp,  1, true,  4, false, 0, 2}, // Security Detail
		{.AI,    0, false, 5, false, 1, 0}, // Firewall
		{.AI,    1, true,  4, false, 2, 0}, // Feedback Loop
		{.AI,    2, false, 2, false, 0, 0}, // Ghost Protocol
		{.Nomad, 0, true,  4, false, 0, 0}, // Boarding Party
		{.Nomad, 1, false, 3, false, 0, 0}, // Evasive Maneuvers
		{.Nomad, 2, true,  4, true,  0, 0}, // Ambush
	}
	from, to := Hex{0, 0}, Hex{1, 0}
	adjacent := [?]Hex{{1, -1}, {0, 1}}
	for test in cases {
		game := CombatTestGame()
		game.players[0].faction = .Swarm
		game.players[1].faction = .Corp
		owner := 1
		choice := CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD}
		if test.attacking {
			owner = 0
			choice.attackerCard = 0
			if test.faction == .Corp do game.players[1].faction = .Swarm
		} else {
			choice.defenderCard = 0
			if test.faction == .Swarm do game.players[0].faction = .Corp
		}
		game.players[owner].faction = test.faction
		CombatGiveCard(&game, owner, test.cardId)
		game.board[CellIndex(&game, from)].units[0] = 2
		target := &game.board[CellIndex(&game, to)]
		target.units[1] = 1
		target.structures[1] = test.defenderStructure
		for i in 0..<test.adjacentRelays {game.board[CellIndex(&game, adjacent[i])].relay = owner}
		for i in 0..<test.adjacentStructures {game.board[CellIndex(&game, adjacent[i])].structures[owner] = true}
		result, ok := StrikeWithCards(&game, from, to, 2, false, choice)
		testing.expect(t, ok)
		if test.attacking {
			testing.expect_value(t, result.attackerStrength, test.strength)
		} else {
			testing.expect_value(t, result.defenderStrength, test.strength)
		}
		testing.expect_value(t, game.players[owner].cardsPlayed, 1)
		testing.expect_value(t, game.players[owner].discardCount, 1)
		testing.expect_value(t, game.players[owner].handCount, 0)
	}
}

@(test)
TestBothCombatCards :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .AI
	CombatGiveCard(&game, 0, 2) // Rush
	CombatGiveCard(&game, 1, 0) // Firewall
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	game.board[CellIndex(&game, Hex{1, -1})].relay = 1
	result, ok := StrikeWithCards(&game, from, to, 2, false, {attackerCard = 0, defenderCard = 0})
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, result.attackerStrength, 4)
	testing.expect_value(t, result.defenderStrength, 2)
	testing.expect_value(t, game.players[0].resources.data, 7)
	testing.expect_value(t, game.players[1].resources.data, 8)
	testing.expect_value(t, game.players[0].cardsPlayed, 1)
	testing.expect_value(t, game.players[1].cardsPlayed, 0)
}

@(test)
TestCounterIntelligence :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	game.players[0].resources.data = 0
	CombatGiveCard(&game, 0, 2) // Rush cannot be paid, but is suppressed.
	CombatGiveCard(&game, 1, 2) // Counter-Intelligence
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	result, ok := StrikeWithCards(&game, from, to, 2, false, {attackerCard = 0, defenderCard = 0})
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, result.attackerStrength, 2)
	testing.expect_value(t, game.players[0].handCount, 1)
	testing.expect_value(t, game.players[0].cardsPlayed, 0)
	testing.expect_value(t, game.players[0].resources.data, 0)
	testing.expect_value(t, game.players[1].cardsPlayed, 1)
}

@(test)
TestFrenzyMovesParticipants :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	CombatGiveCard(&game, 0, 3)
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	source.units[0], source.boostedUnits[0] = 3, 2
	game.board[CellIndex(&game, to)].units[1] = 1
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD, attackerMoveCount = 3}
	choice.attackerMoves[0] = {from, {-1, 0}}
	choice.attackerMoves[1] = {from, {0, -1}}
	choice.attackerMoves[2] = {to, {2, 0}}
	result, ok := StrikeWithCards(&game, from, to, 3, true, choice)
	testing.expect(t, ok && result.attackerWon && result.captured)
	testing.expect_value(t, game.board[CellIndex(&game, Hex{-1, 0})].boostedUnits[0], 1)
	testing.expect_value(t, game.board[CellIndex(&game, Hex{0, -1})].boostedUnits[0], 0)
	testing.expect_value(t, game.board[CellIndex(&game, Hex{2, 0})].boostedUnits[0], 1)
	testing.expect_value(t, source.units[0], 0)
	testing.expect_value(t, game.board[CellIndex(&game, to)].units[0], 0)
}

@(test)
TestFrenzyPreservesUncommittedBoost :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .AI
	CombatGiveCard(&game, 0, 3)
	from, to, destination := Hex{0, 0}, Hex{1, 0}, Hex{2, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	target := &game.board[CellIndex(&game, to)]
	target.units[0], target.boostedUnits[0], target.units[1] = 1, 1, 1
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD, attackerMoveCount = 1}
	choice.attackerMoves[0] = {to, destination}
	result, ok := StrikeWithCards(&game, from, to, 2, true, choice)
	testing.expect(t, ok && result.attackerWon && result.captured)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.boostedUnits[0], 1)
	testing.expect_value(t, game.board[CellIndex(&game, destination)].units[0], 1)
	testing.expect_value(t, game.board[CellIndex(&game, destination)].boostedUnits[0], 0)
}

@(test)
TestGhostAndSmokeMovement :: proc(t: ^testing.T) {
	from, to, destination := Hex{0, 0}, Hex{1, 0}, Hex{2, 0}
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .AI
	CombatGiveCard(&game, 1, 2) // Ghost Protocol
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0], source.boostedUnits[0] = 3, 2
	target.units[1], target.boostedUnits[1] = 2, 1
	choice := CombatChoice{attackerCard = NO_CARD, defenderCard = 0, defenderMoveCount = 1}
	choice.defenderMoves[0] = {to, destination}
	result, ok := StrikeWithCards(&game, from, to, 3, false, choice)
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, game.board[CellIndex(&game, destination)].units[1], 1)
	testing.expect_value(t, game.board[CellIndex(&game, destination)].boostedUnits[1], 1)
	testing.expect_value(t, target.boostedUnits[1], 0)

	game = CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Nomad
	CombatGiveCard(&game, 1, 3) // Smoke Screen
	game.board[CellIndex(&game, from)].units[0] = 2
	target = &game.board[CellIndex(&game, to)]
	target.units[1], target.terrain = 1, .Cover
	result, ok = StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, ok && !result.attackerWon)
	testing.expect_value(t, game.board[CellIndex(&game, destination)].units[1], 1)
}

@(test)
TestPlunder :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .AI
	game.players[0].resources.energy = 4
	game.players[1].resources.energy = 5
	CombatGiveCard(&game, 0, 4)
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	result, ok := StrikeWithCards(&game, from, to, 2, false, {attackerCard = 0, defenderCard = NO_CARD, plunder = .Energy})
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, game.players[0].resources.energy, 5)
	testing.expect_value(t, game.players[1].resources.energy, 4)
	testing.expect_value(t, game.players[0].resourcesStolen, 1)
	testing.expect_value(t, game.players[0].resources.data, 7)
}

@(test)
TestCombatChoiceAtomicFailure :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	CombatGiveCard(&game, 0, 3) // Frenzy
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD, attackerMoveCount = 1}
	choice.attackerMoves[0] = {from, {2, 0}} // Not adjacent.
	before := game
	_, ok := StrikeWithCards(&game, from, to, 2, true, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	choice.attackerMoves[0] = {from, {-1, 0}}
	choice.defenderCard = 0 // Defender has no card.
	_, ok = StrikeWithCards(&game, from, to, 2, true, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
}

@(test)
TestShieldedStructureOnlyCombat :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0], source.boostedUnits[0] = 3, 3
	target.structures[1], target.fortified[1], target.shielded[1] = true, true, true
	result, ok := StrikeWithCards(&game, from, to, 3, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured && !result.structureDestroyed)
	testing.expect(t, target.structures[1] && target.fortified[1] && !target.shielded[1])
	testing.expect_value(t, result.defenderStrength, 3)
	testing.expect_value(t, target.boostedUnits[0], 1)
	testing.expect_value(t, game.players[0].structuresDestroyed, 0)
	result, ok = StrikeWithCards(&game, from, to, 2, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.structureDestroyed)
	testing.expect(t, !target.structures[1])
	testing.expect_value(t, game.players[0].structuresDestroyed, 1)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
}

@(test)
TestCombatPersistentDefense :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[1].faction = .AI
	game.players[1].pulse = true
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	target := &game.board[CellIndex(&game, to)]
	source.units[0], source.boostedUnits[0] = 3, 3
	target.units[1], target.boostedUnits[1] = 2, 1
	target.terrain, target.structures[1], target.fortified[1] = .Cover, true, true
	game.board[CellIndex(&game, Hex{1, -1})].relay = 1
	game.board[CellIndex(&game, Hex{0, 1})].relay = 1
	result, ok := StrikeWithCards(&game, from, to, 3, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && !result.attackerWon)
	testing.expect_value(t, result.attackerStrength, 6)
	testing.expect_value(t, result.defenderStrength, 11)
	testing.expect_value(t, source.boostedUnits[0], 2)
}

@(test)
TestHitAndRunCardsAndWarpath :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .Corp
	game.players[0].warpath = true
	game.players[0].ap = 1
	CombatGiveCard(&game, 0, 0) // Boarding Party
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	source.units[0], source.boostedUnits[0] = 2, 1
	game.board[CellIndex(&game, to)].units[1] = 1
	result, ok := HitAndRunWithCards(&game, from, to, 2, true, true, {attackerCard = 0, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured)
	testing.expect_value(t, result.attackerStrength, 5)
	testing.expect_value(t, game.board[CellIndex(&game, to)].boostedUnits[0], 1)
	testing.expect(t, game.players[0].struckThisTurn)
	testing.expect_value(t, game.players[0].ap, 0)
	game.board[CellIndex(&game, Hex{2, 0})].units[1] = 1
	before := game
	_, ok = StrikeWithCards(&game, to, {2, 0}, 2, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
}

@(test)
TestHitAndRunPreservesUncommittedBoost :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .AI
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 1
	target := &game.board[CellIndex(&game, to)]
	target.units[0], target.boostedUnits[0], target.units[1], target.relay = 1, 1, 1, 1
	result, ok := HitAndRunWithCards(&game, from, to, 1, true, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && !result.attackerWon)
	testing.expect_value(t, result.attackerStrength, 1)
	testing.expect_value(t, target.units[0], 1)
	testing.expect_value(t, target.boostedUnits[0], 1)
}

@(test)
TestWarpathFreeStrikeAndRelayShield :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .AI
	game.players[0].warpath = true
	game.players[0].ap = 0
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	_, ok := StrikeWithCards(&game, from, to, 2, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && game.players[0].struckThisTurn)
	testing.expect_value(t, game.players[0].ap, 0)
	cell := &game.board[CellIndex(&game, from)]
	cell.relay = 1
	game.players[1].relayShield = true
	testing.expect(t, !DestroyRelay(&game, from))
	testing.expect(t, !game.relayDestroyedThisTurn && cell.relay == 1)
	game.players[1].relayShield = false
	testing.expect(t, DestroyRelay(&game, from))
	testing.expect_value(t, cell.relay, NO_PLAYER)
}

@(test)
TestCombatCardsInvalidChoices :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	CombatGiveCard(&game, 0, 4) // Protocol, not Combat.
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD}
	before := game
	_, ok := StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	game.players[0].hand[0] = 2 // Rush costs 1 Data.
	game.players[0].resources.data = 0
	before = game
	_, ok = StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	game.players[0].faction = .Corp
	game.players[0].hand[0] = 2 // Counter-Intelligence is defender-only.
	before = game
	_, ok = StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
}

@(test)
TestFrenzyCannotMoveUncommittedUnits :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	CombatGiveCard(&game, 0, 3)
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 3
	game.board[CellIndex(&game, to)].units[1] = 1
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD, attackerMoveCount = 3}
	choice.attackerMoves[0] = {from, {-1, 0}}
	choice.attackerMoves[1] = {from, {0, -1}}
	choice.attackerMoves[2] = {from, {-1, 1}}
	before := game
	_, ok := StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
}

@(test)
TestPlunderAvailability :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .AI
	game.players[0].resources.energy = 4
	game.players[1].resources.energy = 0
	CombatGiveCard(&game, 0, 4)
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 2
	game.board[CellIndex(&game, to)].units[1] = 1
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD, plunder = .Energy}
	before := game
	_, ok := StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	choice.plunder = .Data
	_, ok = StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, ok)
	testing.expect_value(t, game.players[0].resources.data, 8)
	testing.expect_value(t, game.players[1].resources.data, 7)
	testing.expect_value(t, game.players[0].resourcesStolen, 1)

	game = before
	game.players[1].resources.data = 0
	choice.plunder = .Energy
	_, ok = StrikeWithCards(&game, from, to, 2, false, choice)
	testing.expect(t, ok)
	testing.expect_value(t, game.players[0].resourcesStolen, 0)
}

@(test)
TestHitAndRunChoiceRollback :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Nomad
	game.players[1].faction = .Corp
	CombatGiveCard(&game, 0, 3) // Smoke Screen
	from, to := Hex{0, 0}, Hex{1, 0}
	source := &game.board[CellIndex(&game, from)]
	source.units[0], source.boostedUnits[0] = 2, 1
	game.board[CellIndex(&game, to)].units[1] = 1
	choice := CombatChoice{attackerCard = 0, defenderCard = NO_CARD, attackerMoveCount = 1}
	choice.attackerMoves[0] = {to, {-2, 0}} // Not adjacent after movement.
	before := game
	_, ok := HitAndRunWithCards(&game, from, to, 2, true, true, choice)
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
}

@(test)
TestShieldAfterDefenderCasualty :: proc(t: ^testing.T) {
	game := CombatTestGame()
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	from, to := Hex{0, 0}, Hex{1, 0}
	game.board[CellIndex(&game, from)].units[0] = 3
	target := &game.board[CellIndex(&game, to)]
	target.units[1], target.structures[1], target.shielded[1] = 1, true, true
	result, ok := StrikeWithCards(&game, from, to, 3, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.unitDestroyed && result.captured)
	testing.expect(t, target.structures[1] && !target.shielded[1] && !result.structureDestroyed)
	testing.expect_value(t, game.players[0].unitsDestroyed, 1)
	testing.expect_value(t, game.players[0].tokensDestroyed, 1)
	testing.expect_value(t, game.players[0].structuresDestroyed, 0)
}
