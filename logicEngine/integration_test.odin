#+build !js

package logicEngine

import "core:testing"

// A small, deterministic position for action-level integration tests.
IntegrationGame :: proc() -> Game {
	game: Game
	game.playerCount = 2
	game.round = 1
	game.phase = .Acting
	game.randomState = 1
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	for i in 0..<game.playerCount {
		game.players[i].ap = 3
		game.players[i].resources = {3, 6}
	}
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

IntegrationCell :: proc(game: ^Game, pos: Hex) -> ^Cell {
	return &game.board[CellIndex(game, pos)]
}

IntegrationProtocolGame :: proc(faction: Faction, id: int) -> Game {
	game := IntegrationGame()
	player := &game.players[0]
	player.faction = faction
	game.players[1].faction = .Swarm
	if faction == .Swarm do game.players[1].faction = .Corp
	player.hand = {0, id, 1, 0, 0}
	player.handCount = 3
	player.discard[0] = FactionDeckSize(faction) - 1
	if player.discard[0] == id do player.discard[0] -= 1
	player.discardCount = 1
	player.cardsPlayed = 1
	for card in 2..<FactionDeckSize(faction) {
		if card == id || card == player.discard[0] do continue
		player.deck[player.deckCount] = card
		player.deckCount += 1
		if player.deckCount == 4 do break
	}
	game.players[1].resources = {3, 3}
	game.players[1].hand = {0, 1, 2, 0, 0}
	game.players[1].handCount = 3
	IntegrationCell(&game, {0, 0}).units[0] = 2
	IntegrationCell(&game, {1, 0}).units[0] = 1
	return game
}

// Costs are specified independently of the catalog; draws occur after discard.
IntegrationPlay :: proc(t: ^testing.T, game: ^Game, id, cost, energyGain, dataGain, draws: int, choice: ProtocolChoice) {
	previousDiscard := game.players[0].discard[0]
	if IsInformationalProtocol(game.players[0].faction, id) {
		_, ok := BeginInformationalProtocol(game, 1, choice.other)
		testing.expect(t, ok)
		if game.phase == .Protocol_Choice do testing.expect(t, FinishInformationalProtocol(game, choice))
	} else {
		testing.expect(t, PlayProtocol(game, 1, choice))
	}
	p := &game.players[0]
	testing.expect_value(t, p.ap, 2)
	testing.expect_value(t, p.resources, Resources{3 + energyGain, 6 - cost + dataGain})
	testing.expect_value(t, p.discardCount, 2)
	testing.expect_value(t, p.discard[0], previousDiscard)
	testing.expect_value(t, p.discard[1], id)
	testing.expect_value(t, p.cardsPlayed, 2)
	testing.expect_value(t, p.handCount, 2 + draws)
	testing.expect_value(t, p.hand[0], 0)
	testing.expect_value(t, p.hand[1], 1)
	if draws == 0 do testing.expect_value(t, p.hand[2], 0)
	testing.expect_value(t, p.deckCount, 4 - draws)
}

@(test)
TestIntegrationSwarmProtocolDispatch :: proc(t: ^testing.T) {
	costs := [?]int{0, 0, 1, 1, 1, 2, 2, 0}
	for id in 4..=11 {
		game := IntegrationProtocolGame(.Swarm, id)
		from, to := Hex{0, 0}, Hex{1, 0}
		source, target := IntegrationCell(&game, from), IntegrationCell(&game, to)
		choice := ProtocolChoice{from = from, to = to}
		draws, energy := 0, 0
		switch id {
		case 4:
			choice.to = from
			draws = 2
		case 5:
			choice.cardIndex = 1
			draws = 1
		case 6:
			source.boostedUnits[0] = 1
		case 7:
		case 8:
			choice.to = from
		case 9:
			target.structures[1] = true
			choice.target = .Structure
		case 10:
		case 11:
			energy = 2
		}
		IntegrationPlay(t, &game, id, costs[id - 4], energy, 0, draws, choice)
		switch id {
		case 4:
			testing.expect_value(t, source.units[0], 1)
			testing.expect_value(t, game.players[0].hand[2], 6)
			testing.expect_value(t, game.players[0].hand[3], 5)
		case 5:
			testing.expect_value(t, game.players[0].hand[2], 4)
			testing.expect_value(t, game.players[0].deck[0], 6)
		case 6:
			testing.expect_value(t, source.units[0], 1)
			testing.expect_value(t, target.units[0], 2)
			testing.expect_value(t, target.boostedUnits[0], 1)
		case 7:
			testing.expect_value(t, target.units[0], 2)
		case 8:
			testing.expect_value(t, source.boostedUnits[0], 2)
		case 9:
			testing.expect(t, !target.structures[1])
			testing.expect_value(t, game.players[0].structuresDestroyed, 1)
			testing.expect_value(t, game.players[0].tokensDestroyed, 1)
		case 10:
			testing.expect_value(t, source.units[0], 3)
			testing.expect_value(t, target.units[0], 2)
		case 11:
			testing.expect_value(t, game.players[0].resources.energy, 5)
		}
	}
}

@(test)
TestIntegrationCorpProtocolDispatch :: proc(t: ^testing.T) {
	costs := [?]int{2, 1, 0, 1, 2, 0, 1, 1, 1, 1, 2}
	for id in 3..=13 {
		game := IntegrationProtocolGame(.Corp, id)
		from := Hex{0, 0}
		cell := IntegrationCell(&game, from)
		choice := ProtocolChoice{to = from, other = 1, resource = .Energy, cardIndex = 1}
		draws, energy, data := 0, 0, 0
		switch id {
		case 3: energy = 1
		case 4: cell.structures[0] = true
		case 5:
			cell.structures[0] = true
			data = 1
		case 6: draws = 2
		case 7: cell.structures[0] = true
		case 8: data = 2
		case 9:
			cell.terrain = .Energy_Node
			energy = 3
		case 10:
		case 11:
		case 12:
			draws = 1
			data = 1
		case 13: energy = 1
		}
		IntegrationPlay(t, &game, id, costs[id - 3], energy, data, draws, choice)
		switch id {
		case 3, 13:
			testing.expect_value(t, game.players[1].resources.energy, 2)
			testing.expect_value(t, game.players[0].resourcesStolen, 1)
		case 4: testing.expect(t, cell.fortified[0])
		case 5: testing.expect_value(t, game.players[0].resources.data, 7)
		case 6:
			testing.expect_value(t, game.players[0].hand[2], 5)
			testing.expect_value(t, game.players[0].hand[3], 4)
		case 7: testing.expect(t, cell.shielded[0])
		case 8: testing.expect_value(t, game.players[0].resources.data, 8)
		case 9: testing.expect_value(t, game.players[0].resources.energy, 6)
		case 10: testing.expect(t, game.players[0].automate)
		case 11:
			testing.expect_value(t, game.players[1].handCount, 2)
			testing.expect_value(t, game.players[1].hand[1], 2)
			testing.expect_value(t, game.players[1].discard[0], 1)
			testing.expect_value(t, game.players[1].discardCount, 1)
			testing.expect_value(t, game.players[1].cardsPlayed, 0)
		case 12: testing.expect_value(t, game.players[0].hand[2], 5)
		}
	}
}

@(test)
TestIntegrationAiProtocolDispatch :: proc(t: ^testing.T) {
	costs := [?]int{1, 1, 0, 2, 0, 1, 1, 1, 2, 0}
	for id in 3..=12 {
		game := IntegrationProtocolGame(.AI, id)
		from, to := Hex{0, 0}, Hex{1, 0}
		source, target := IntegrationCell(&game, from), IntegrationCell(&game, to)
		choice := ProtocolChoice{from = from, to = to, other = 1, resource = .Energy}
		draws, energy, data := 0, 0, 0
		switch id {
		case 3:
		case 4: source.relay = 0
		case 5:
			source.relay, target.relay = 0, 0
			draws = 2
		case 6:
		case 7:
			choice.option = true
			draws = 1
		case 8:
		case 9:
		case 10:
			choice.to = from
			target.relay = 0
			IntegrationCell(&game, {-1, 0}).relay = 0
			energy = 2
		case 11:
			choice.to = from
			choice.terrain = .Data_Node
			data = 1
		case 12:
		}
		IntegrationPlay(t, &game, id, costs[id - 3], energy, data, draws, choice)
		switch id {
		case 3:
			testing.expect_value(t, game.players[1].handCount, 3)
			testing.expect_value(t, game.players[1].discardCount, 0)
		case 4:
			testing.expect_value(t, source.relay, NO_PLAYER)
			testing.expect_value(t, target.relay, 0)
		case 5:
			testing.expect_value(t, game.players[0].hand[2], 6)
			testing.expect_value(t, game.players[0].hand[3], 4)
		case 6:
			testing.expect_value(t, game.players[1].handCount, 2)
			testing.expect_value(t, game.players[1].discardCount, 1)
			testing.expect(t, game.randomState != 1)
		case 7:
			testing.expect_value(t, game.players[0].hand[2], 4)
			testing.expect_value(t, game.players[0].deck[0], 5)
		case 8: testing.expect_value(t, target.relay, 0)
		case 9: testing.expect(t, game.players[0].relayShield)
		case 10: testing.expect_value(t, game.players[0].resources.energy, 5)
		case 11: testing.expect_value(t, source.terrain, Terrain.Data_Node)
		case 12: testing.expect(t, game.players[0].pulse)
		}
	}
}

@(test)
TestIntegrationNomadProtocolDispatch :: proc(t: ^testing.T) {
	costs := [?]int{1, 0, 1, 1, 0, 2, 2}
	for id in 5..=11 {
		game := IntegrationProtocolGame(.Nomad, id)
		from, to := Hex{0, 0}, Hex{1, 0}
		source, target := IntegrationCell(&game, from), IntegrationCell(&game, to)
		choice := ProtocolChoice{from = from, to = to, other = 1, resource = .Energy}
		draws, energy, data := 0, 0, 0
		switch id {
		case 5:
			choice.to = from
			choice.target = .Structure
			source.structures[0] = true
			energy = 3
		case 6: draws = 1
		case 7: energy, data = 1, 1
		case 8:
			choice.option = true
			choice.target = .Structure
			target.structures[1] = true
		case 9: source.units[1] = 1
		case 10: energy = 2
		case 11:
		}
		IntegrationPlay(t, &game, id, costs[id - 5], energy, data, draws, choice)
		switch id {
		case 5: testing.expect(t, !source.structures[0])
		case 6: testing.expect_value(t, game.players[0].hand[2], 5)
		case 7: testing.expect_value(t, game.players[0].resources, Resources{4, 6})
		case 8:
			testing.expect(t, !target.structures[1])
			testing.expect_value(t, source.units[0], 1)
			testing.expect_value(t, target.units[0], 2)
			testing.expect_value(t, game.players[0].structuresDestroyed, 1)
		case 9:
			testing.expect_value(t, source.units[0], 1)
			testing.expect_value(t, target.units[0], 2)
			testing.expect_value(t, source.units[1], 1)
		case 10:
			testing.expect_value(t, game.players[1].resources.energy, 2)
			testing.expect_value(t, game.players[0].resourcesStolen, 1)
		case 11: testing.expect(t, game.players[0].warpath)
		}
	}
}

IntegrationReject :: proc(t: ^testing.T, game: ^Game, index: int, choice: ProtocolChoice) {
	before := game^
	testing.expect(t, !PlayProtocol(game, index, choice))
	testing.expect_value(t, game^, before)
}

@(test)
TestIntegrationProtocolValidationAndRollback :: proc(t: ^testing.T) {
	testing.expect(t, !PlayProtocol(nil, 0, {}))
	base := IntegrationProtocolGame(.Swarm, 10)
	choice := ProtocolChoice{from = {0, 0}, to = {1, 0}}
	IntegrationReject(t, &base, -1, choice)
	IntegrationReject(t, &base, 3, choice)
	IntegrationReject(t, &base, 0, choice) // Combat card.
	trial := base
	trial.phase = .Await_Turn
	IntegrationReject(t, &trial, 1, choice)
	trial = base
	trial.currentPlayer = 2
	IntegrationReject(t, &trial, 1, choice)
	trial = base
	trial.playerCount = 1
	IntegrationReject(t, &trial, 1, choice)
	trial = base
	trial.players[0].ap = 0
	IntegrationReject(t, &trial, 1, choice)
	trial = base
	trial.players[0].resources.data = 1
	IntegrationReject(t, &trial, 1, choice)
	trial = base
	trial.players[0].discardCount = len(trial.players[0].discard)
	IntegrationReject(t, &trial, 1, choice)
	trial = base
	trial.players[0].hand[1] = FactionDeckSize(.Swarm)
	IntegrationReject(t, &trial, 1, choice)

	// Each faction rejects an illegal effect after card payment on the copy.
	IntegrationReject(t, &base, 1, {from = {0, 0}, to = {0, 0}})
	trial = IntegrationProtocolGame(.Corp, 11)
	IntegrationReject(t, &trial, 1, {other = 1, cardIndex = 3})
	trial = IntegrationProtocolGame(.AI, 11)
	IntegrationReject(t, &trial, 1, {to = {0, 0}, terrain = .Open})
	trial = IntegrationProtocolGame(.Nomad, 8)
	target := IntegrationCell(&trial, {1, 0})
	target.structures[1], target.shielded[1] = true, true
	testing.expect(t, PlayProtocol(&trial, 1, {from = {0, 0}, to = {1, 0}, target = .Structure, option = true}))
	// The move succeeds; Redundancy absorbs destruction and consumes its shield.
	testing.expect(t, target.structures[1] && !target.shielded[1])
	testing.expect_value(t, IntegrationCell(&trial, {0, 0}).units[0], 1)
	testing.expect_value(t, target.units[0], 2)
	testing.expect_value(t, trial.players[0].structuresDestroyed, 0)
}

@(test)
TestIntegrationProtocolDiscardBeforeDraw :: proc(t: ^testing.T) {
	game := IntegrationProtocolGame(.Swarm, 4)
	game.players[0].hand = {0, 4, 1, 2, 3}
	game.players[0].handCount = HAND_LIMIT
	game.players[0].deck[0], game.players[0].deck[1], game.players[0].deck[2], game.players[0].deck[3] = 5, 6, 7, 8
	testing.expect(t, PlayProtocol(&game, 1, {to = {0, 0}}))
	p := &game.players[0]
	testing.expect_value(t, p.handCount, HAND_LIMIT)
	testing.expect_value(t, p.hand, [HAND_LIMIT]int{0, 1, 2, 3, 8})
	testing.expect_value(t, p.deckCount, 3)
	testing.expect_value(t, p.discard[1], 4)
	testing.expect_value(t, p.ap, 2)
	testing.expect_value(t, IntegrationCell(&game, {0, 0}).units[0], 1)
}

@(test)
TestIntegrationOverrideDeterminismAndRollback :: proc(t: ^testing.T) {
	game := IntegrationProtocolGame(.AI, 6)
	game.players[1].hand = {0, 1, 2, 3, 0}
	game.players[1].handCount = 4
	control := game
	// Override validates the target before sampling; failures must preserve the seed.
	IntegrationReject(t, &game, 1, {other = 0})
	game.players[1].handCount = 0
	IntegrationReject(t, &game, 1, {other = 1})
	game.players[1].handCount = 4
	game.players[1].discardCount = len(game.players[1].discard)
	IntegrationReject(t, &game, 1, {other = 1})
	game.players[1].discardCount = 0
	testing.expect_value(t, game, control)
	testing.expect(t, PlayProtocol(&game, 1, {other = 1, cardIndex = -100}))
	testing.expect(t, PlayProtocol(&control, 1, {other = 1, cardIndex = 999}))
	testing.expect_value(t, game, control)
	// Seed 1 selects index 0 of four; cardIndex is not used by Override.
	testing.expect_value(t, game.randomState, u64(1082269761))
	testing.expect_value(t, game.players[1].discard[0], 0)
	testing.expect_value(t, game.players[1].hand, [HAND_LIMIT]int{1, 2, 3, 0, 0})
	testing.expect_value(t, game.players[1].handCount, 3)
	testing.expect_value(t, game.players[1].cardsPlayed, 0)
	testing.expect_value(t, game.players[0].resources.data, 4)
	testing.expect_value(t, game.players[0].ap, 2)
	testing.expect_value(t, game.players[0].discard[1], 6)
}

@(test)
TestIntegrationAutomateBuildActions :: proc(t: ^testing.T) {
	for structure in ([?]bool{false, true}) {
		game := IntegrationProtocolGame(.Corp, 10)
		game.players[0].resources = {0, 1}
		testing.expect(t, PlayProtocol(&game, 1, {}))
		testing.expect(t, game.players[0].automate)
		testing.expect_value(t, game.players[0].resources, Resources{})
		before := game
		if structure {
			testing.expect(t, !BuildStructure(&game, {2, -2}))
		} else {
			testing.expect(t, !BuildUnit(&game, {2, -2}))
		}
		testing.expect_value(t, game, before)
		if structure {
			testing.expect(t, BuildStructure(&game, {1, 0}))
			testing.expect(t, IntegrationCell(&game, {1, 0}).structures[0])
		} else {
			testing.expect(t, BuildUnit(&game, {0, 0}))
			testing.expect_value(t, IntegrationCell(&game, {0, 0}).units[0], 3)
		}
		testing.expect(t, !game.players[0].automate)
		testing.expect_value(t, game.players[0].resources, Resources{})
		testing.expect_value(t, game.players[0].ap, 1)
		before = game
		if structure {
			testing.expect(t, !BuildStructure(&game, {0, 0}))
		} else {
			testing.expect(t, !BuildUnit(&game, {1, 0}))
		}
		testing.expect_value(t, game, before)
	}
}

@(test)
TestIntegrationTemporaryEffectsAcrossTurns :: proc(t: ^testing.T) {
	game := IntegrationGame()
	game.playerCount = 4
	game.players[0].faction = .Swarm
	game.players[1].faction = .Corp
	game.players[2].faction = .AI
	game.players[3].faction = .Nomad
	for i in 0..<4 do game.players[i].resources = {3, 6}
	game.players[0].hand[0], game.players[0].handCount = 8, 1
	game.players[1].hand = {4, 7, 10, 0, 0}
	game.players[1].handCount = 3
	game.players[2].hand[0], game.players[2].hand[1], game.players[2].handCount = 9, 12, 2
	game.players[3].hand[0], game.players[3].handCount = 11, 1
	swarm := IntegrationCell(&game, {0, 0})
	moved := IntegrationCell(&game, {-1, 0})
	corp := IntegrationCell(&game, {0, 1})
	ai := IntegrationCell(&game, {1, 0})
	swarm.units[0] = 2
	corp.structures[1] = true
	ai.units[2] = 1
	IntegrationCell(&game, {2, 0}).relay = 2

	testing.expect(t, PlayProtocol(&game, 0, {to = {0, 0}}))
	testing.expect_value(t, swarm.boostedUnits[0], 2)
	testing.expect(t, MoveUnits(&game, {0, 0}, {-1, 0}, 1))
	testing.expect_value(t, moved.boostedUnits[0], 1)
	testing.expect(t, EndTurn(&game))
	testing.expect_value(t, swarm.boostedUnits[0], 0)
	testing.expect_value(t, moved.boostedUnits[0], 0)
	testing.expect_value(t, moved.units[0], 1)

	testing.expect(t, BeginTurn(&game))
	testing.expect(t, PlayProtocol(&game, 0, {to = {0, 1}})) // Fortify.
	testing.expect(t, PlayProtocol(&game, 0, {to = {0, 1}})) // Redundancy.
	testing.expect(t, PlayProtocol(&game, 0, {})) // Automate.
	testing.expect(t, corp.fortified[1] && corp.shielded[1] && game.players[1].automate)
	testing.expect_value(t, CombatDefense(&game, corp, 1), 3)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, corp.fortified[1] && corp.shielded[1] && !game.players[1].automate)

	testing.expect(t, BeginTurn(&game))
	testing.expect_value(t, CombatDefense(&game, ai, 2), 2)
	testing.expect(t, PlayProtocol(&game, 0, {})) // Relay Shield.
	testing.expect(t, PlayProtocol(&game, 0, {})) // Pulse.
	testing.expect(t, game.players[2].relayShield && game.players[2].pulse)
	testing.expect_value(t, CombatDefense(&game, ai, 2), 3)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, game.players[2].relayShield && !game.players[2].pulse)
	testing.expect_value(t, CombatDefense(&game, ai, 2), 2)
	testing.expect(t, corp.fortified[1] && corp.shielded[1])

	testing.expect(t, BeginTurn(&game))
	testing.expect(t, PlayProtocol(&game, 0, {})) // Warpath.
	testing.expect(t, game.players[3].warpath)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, !game.players[3].warpath)
	testing.expect(t, ScoreAndCompleteObjective(&game))
	testing.expect_value(t, game.currentPlayer, 1)
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, !corp.fortified[1] && corp.shielded[1])
	testing.expect_value(t, CombatDefense(&game, corp, 1), 1)
	testing.expect(t, game.players[2].relayShield)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, !game.players[2].relayShield)
	testing.expect(t, corp.shielded[1])
}

@(test)
TestIntegrationRelayShieldAndCardDestruction :: proc(t: ^testing.T) {
	game := IntegrationGame()
	game.players[0].faction = .AI
	game.players[1].faction = .Swarm
	game.players[0].hand[0], game.players[0].handCount = 9, 1
	game.players[1].hand[0], game.players[1].handCount = 9, 1
	protected, cardTarget, spare := Hex{0, 0}, Hex{1, 0}, Hex{0, 1}
	IntegrationCell(&game, protected).relay = 0
	IntegrationCell(&game, cardTarget).relay = 0
	IntegrationCell(&game, spare).relay = 0
	IntegrationCell(&game, protected).units[1] = 1
	IntegrationCell(&game, spare).units[1] = 1
	testing.expect(t, PlayProtocol(&game, 0, {}))
	testing.expect(t, EndTurn(&game))
	testing.expect(t, BeginTurn(&game))
	before := game
	testing.expect(t, !DestroyRelay(&game, protected))
	testing.expect_value(t, game, before)
	testing.expect(t, PlayProtocol(&game, 0, {to = cardTarget, target = .Relay}))
	testing.expect_value(t, IntegrationCell(&game, cardTarget).relay, NO_PLAYER)
	testing.expect_value(t, game.players[1].tokensDestroyed, 1)
	testing.expect(t, game.players[0].relayShield && !game.relayDestroyedThisTurn)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, ScoreAndCompleteObjective(&game))
	// The opponent starts the next round; protection has not yet expired.
	testing.expect_value(t, game.currentPlayer, 1)
	testing.expect(t, BeginTurn(&game))
	before = game
	testing.expect(t, !DestroyRelay(&game, protected))
	testing.expect_value(t, game, before)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, !game.players[0].relayShield)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, ScoreAndCompleteObjective(&game))
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, EndTurn(&game))
	testing.expect(t, BeginTurn(&game))
	testing.expect(t, DestroyRelay(&game, protected))
	testing.expect_value(t, IntegrationCell(&game, protected).relay, NO_PLAYER)
	testing.expect_value(t, game.players[1].tokensDestroyed, 2)
	testing.expect_value(t, game.players[1].ap, 3)
	testing.expect(t, game.relayDestroyedThisTurn)
	before = game
	testing.expect(t, !DestroyRelay(&game, spare))
	testing.expect_value(t, game, before)
}

@(test)
TestIntegrationRedundancyCorrodeAndStrikeWithCards :: proc(t: ^testing.T) {
	game := IntegrationGame()
	game.players[0].faction = .Corp
	game.players[1].faction = .Swarm
	game.players[0].hand[0], game.players[0].handCount = 7, 1
	game.players[1].hand[0], game.players[1].handCount = 9, 1
	from, to := Hex{0, 0}, Hex{1, 0}
	IntegrationCell(&game, from).units[1] = 3
	structure := IntegrationCell(&game, to)
	structure.structures[0] = true
	testing.expect(t, PlayProtocol(&game, 0, {to = to}))
	testing.expect(t, structure.shielded[0])
	testing.expect(t, EndTurn(&game))
	testing.expect(t, BeginTurn(&game))

	// Combat capture consumes the same shield, leaving a contested structure.
	combat := game
	result, ok := StrikeWithCards(&combat, from, to, 3, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured && !result.structureDestroyed)
	combatTarget := IntegrationCell(&combat, to)
	testing.expect(t, combatTarget.structures[0] && !combatTarget.shielded[0])
	testing.expect_value(t, combatTarget.units[1], 1)
	testing.expect(t, !Controls(&combat, 0, to) && !Controls(&combat, 1, to))
	testing.expect_value(t, combat.players[1].tokensDestroyed, 0)
	result, ok = StrikeWithCards(&combat, from, to, 2, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured && result.structureDestroyed)
	testing.expect(t, !combatTarget.structures[0])
	testing.expect_value(t, combat.players[1].structuresDestroyed, 1)
	testing.expect_value(t, combat.players[1].tokensDestroyed, 1)

	testing.expect(t, PlayProtocol(&game, 0, {to = to, target = .Structure}))
	testing.expect(t, structure.structures[0] && !structure.shielded[0])
	testing.expect_value(t, game.players[1].structuresDestroyed, 0)
	testing.expect_value(t, game.players[1].tokensDestroyed, 0)
	result, ok = StrikeWithCards(&game, from, to, 2, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured && result.structureDestroyed)
	testing.expect(t, !structure.structures[0])
	testing.expect_value(t, structure.units[1], 1)
	testing.expect_value(t, game.players[1].structuresDestroyed, 1)
	testing.expect_value(t, game.players[1].tokensDestroyed, 1)
	testing.expect_value(t, game.players[1].discard[0], 9)
	testing.expect_value(t, game.players[1].ap, 1)
}

@(test)
TestIntegrationWarpathMovementAndStrikes :: proc(t: ^testing.T) {
	game := IntegrationGame()
	game.players[0].faction = .Nomad
	game.players[0].hand[0], game.players[0].handCount = 11, 1
	from, via, to, defender := Hex{-1, 0}, Hex{0, 0}, Hex{1, 0}, Hex{2, 0}
	source := IntegrationCell(&game, from)
	middle := IntegrationCell(&game, via)
	destination := IntegrationCell(&game, to)
	target := IntegrationCell(&game, defender)
	source.units[0], source.boostedUnits[0] = 3, 1
	middle.units[1] = 1
	target.units[1], target.structures[1] = 1, true
	before := game
	testing.expect(t, !MoveUnitsVia(&game, from, via, to, 2))
	testing.expect(t, !MoveUnits(&game, from, via, 1))
	testing.expect_value(t, game, before)
	testing.expect(t, PlayProtocol(&game, 0, {}))
	testing.expect_value(t, game.players[0].resources.data, 4)
	testing.expect_value(t, game.players[0].ap, 2)
	before = game
	testing.expect(t, !MoveUnitsVia(&game, from, {-1, 1}, {0, 1}, 1)) // Empty path.
	testing.expect_value(t, game, before)
	destination.units[1] = 1
	before = game
	testing.expect(t, !MoveUnitsVia(&game, from, via, to, 2)) // Occupied destination.
	testing.expect_value(t, game, before)
	destination.units[1] = 0
	testing.expect(t, MoveUnitsVia(&game, from, via, to, 2))
	testing.expect_value(t, source.units[0], 1)
	testing.expect_value(t, destination.units[0], 2)
	testing.expect_value(t, destination.boostedUnits[0], 1)
	testing.expect_value(t, middle.units[1], 1)
	testing.expect_value(t, game.players[0].ap, 1)
	before = game
	_, ok := StrikeWithCards(&game, to, defender, 2, false, {attackerCard = 99, defenderCard = NO_CARD})
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	result: CombatResult
	result, ok = StrikeWithCards(&game, to, defender, 2, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.unitDestroyed && !result.captured)
	testing.expect_value(t, result.attackerStrength, 3)
	testing.expect_value(t, result.defenderStrength, 2)
	testing.expect(t, game.players[0].struckThisTurn)
	testing.expect_value(t, game.players[0].ap, 1) // First Strike was free.
	result, ok = StrikeWithCards(&game, to, defender, 2, true, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon && result.captured && result.structureDestroyed)
	testing.expect_value(t, game.players[0].ap, 0)
	before = game
	_, ok = StrikeWithCards(&game, to, via, 1, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, !ok)
	testing.expect_value(t, game, before)
	testing.expect(t, EndTurn(&game))
	testing.expect(t, !game.players[0].warpath && !game.players[0].struckThisTurn)
	testing.expect_value(t, destination.boostedUnits[0], 0)
	testing.expect_value(t, target.boostedUnits[0], 0)
}

@(test)
TestIntegrationWarpathAfterStrikeIsNotFree :: proc(t: ^testing.T) {
	game := IntegrationGame()
	game.players[0].faction = .Nomad
	game.players[0].hand[0], game.players[0].handCount = 11, 1
	IntegrationCell(&game, {0, 0}).units[0] = 3
	target := IntegrationCell(&game, {1, 0})
	target.units[1], target.structures[1] = 1, true
	result, ok := StrikeWithCards(&game, {0, 0}, {1, 0}, 3, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, game.players[0].ap, 2)
	testing.expect(t, PlayProtocol(&game, 0, {}))
	testing.expect(t, game.players[0].struckThisTurn && game.players[0].warpath)
	testing.expect_value(t, game.players[0].ap, 1)
	result, ok = StrikeWithCards(&game, {0, 0}, {1, 0}, 3, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
	testing.expect(t, ok && result.attackerWon)
	testing.expect_value(t, game.players[0].ap, 0)
}

IntegrationSetup :: proc() -> SetupConfig {
	config: SetupConfig
	config.playerCount = 4
	config.firstPlayer = 1
	config.randomSeed = 123
	config.players[0].faction, config.players[0].start = .Swarm, {-2, 0}
	config.players[1].faction, config.players[1].start = .Corp, {0, -2}
	config.players[2].faction, config.players[2].start = .AI, {2, 0}
	config.players[3].faction, config.players[3].start = .Nomad, {0, 2}
	for i in 0..<15 do config.terrainOrder[i] = i
	for i in 0..<12 do config.directiveOrder[i] = i
	for p in 0..<4 {
		for id in 0..<FactionDeckSize(config.players[p].faction) do config.players[p].deck[id] = id
	}
	return config
}

@(test)
TestIntegrationSixRoundsToFinalScores :: proc(t: ^testing.T) {
	game: Game
	testing.expect(t, SetupGame(&game, IntegrationSetup()))
	testing.expect_value(t, game.round, 1)
	testing.expect_value(t, game.phase, Phase.Await_Turn)
	testing.expect_value(t, game.currentPlayer, 1)
	testing.expect_value(t, game.players[0].handCount, 3)
	testing.expect_value(t, game.players[1].directives[0], 0)
	testing.expect_value(t, game.players[2].directives[0], 2)
	testing.expect_value(t, game.players[3].directives[0], 4)
	testing.expect_value(t, game.players[3].directiveCount, 3)
	testing.expect_value(t, game.players[0].directives[0], 7)
	unavailable := FinalScores{winnerCount = 99}
	testing.expect(t, !CalculateFinalScores(&game, &unavailable))
	testing.expect_value(t, unavailable.winnerCount, 99)

	expectedPublic := [?][4]int{
		{2, 2, 2, 2},
		{4, 4, 4, 4},
		{6, 6, 6, 6},
		{8, 6, 6, 6},
		{10, 8, 8, 8},
		{12, 10, 10, 10},
	}
	for round in 1..=ROUND_COUNT {
		first := round % 4
		testing.expect_value(t, game.round, round)
		testing.expect_value(t, game.firstPlayer, first)
		for offset in 0..<4 {
			who := (first + offset) % 4
			testing.expect_value(t, game.currentPlayer, who)
			testing.expect_value(t, game.phase, Phase.Await_Turn)
			testing.expect(t, BeginTurn(&game))
			testing.expect_value(t, game.players[who].ap, 3)
			switch round {
			case 1:
				switch who {
				case 0:
					testing.expect(t, MoveUnits(&game, {-2, 0}, {-1, 0}, 2))
					testing.expect(t, BuildUnit(&game, {-1, 0}))
				case 1:
					testing.expect(t, MoveUnits(&game, {0, -2}, {0, -1}, 1))
					testing.expect(t, BuildStructure(&game, {0, -1}))
				case 2:
					testing.expect(t, MoveUnits(&game, {2, 0}, {1, 0}, 1))
					testing.expect(t, RewireRelay(&game, {1, 0}))
				case 3:
					testing.expect(t, MoveUnits(&game, {0, 2}, {0, 1}, 1))
					testing.expect(t, BuildUnit(&game, {0, 1}))
				}
			case 2:
			case 3:
				switch who {
				case 0:
					testing.expect(t, MoveUnits(&game, {-2, 0}, {-2, 1}, 1))
					testing.expect(t, MoveUnits(&game, {-2, 1}, {-2, 2}, 1))
					testing.expect(t, BuildUnit(&game, {-2, 2}))
				case 3:
					testing.expect(t, MoveUnits(&game, {0, 2}, {-1, 2}, 1))
					testing.expect(t, BuildStructure(&game, {0, 1}))
				case:
				}
			case 4:
				if who == 0 {
					result, ok := StrikeWithCards(&game, {-2, 2}, {-1, 2}, 2, false, CombatChoice{attackerCard = NO_CARD, defenderCard = NO_CARD})
					testing.expect(t, ok && result.attackerWon && result.unitDestroyed)
					testing.expect_value(t, game.players[0].roundCombatWins, 1)
				}
			case 5:
				switch who {
				case 1:
					testing.expect(t, BuildUnit(&game, {0, -2}))
					testing.expect(t, BuildUnit(&game, {0, -1}))
				case 2:
					testing.expect(t, BuildUnit(&game, {1, 0}))
					testing.expect(t, BuildUnit(&game, {1, 0}))
					testing.expect(t, BuildUnit(&game, {2, 0}))
				case 3:
					testing.expect(t, BuildUnit(&game, {0, 1}))
					testing.expect(t, MoveUnits(&game, {0, 1}, {0, 2}, 1))
					testing.expect(t, BuildUnit(&game, {0, 2}))
				case:
				}
			case 6:
				switch who {
				case 0:
					testing.expect(t, MoveUnits(&game, {-1, 0}, {0, 0}, 2))
					testing.expect(t, MoveUnits(&game, {0, 0}, {1, -1}, 1))
				case 1:
					testing.expect(t, MoveUnits(&game, {0, -2}, {1, -2}, 1))
					testing.expect(t, MoveUnits(&game, {0, -1}, {-1, -1}, 1))
				case 2:
					testing.expect(t, MoveUnits(&game, {1, 0}, {2, -1}, 2))
					testing.expect(t, MoveUnits(&game, {2, -1}, {2, -2}, 1))
				case 3:
					testing.expect(t, MoveUnits(&game, {0, 1}, {-1, 1}, 1))
					testing.expect(t, MoveUnits(&game, {0, 2}, {-1, 2}, 1))
				}
			}
			testing.expect(t, EndTurn(&game))
			testing.expect_value(t, game.turnsTaken, offset + 1)
		}
		testing.expect_value(t, game.phase, Phase.Score_Objective)
		for p in 0..<4 {
			met := round != 4 || p == 0
			testing.expect_value(t, ObjectiveMet(&game, p, round), met)
		}
		testing.expect(t, ScoreAndCompleteObjective(&game))
		for p in 0..<4 {
			testing.expect_value(t, game.players[p].publicVp, expectedPublic[round - 1][p])
			testing.expect_value(t, game.players[p].objectivesScored, expectedPublic[round - 1][p] / OBJECTIVE_VP)
			if round < ROUND_COUNT do testing.expect_value(t, game.players[p].roundCombatWins, 0)
		}
		before := game
		testing.expect(t, !ScoreAndCompleteObjective(&game))
		testing.expect_value(t, game, before)
	}
	testing.expect_value(t, game.phase, Phase.Finished)
	scores: FinalScores
	testing.expect(t, CalculateFinalScores(&game, &scores))
	testing.expect_value(t, scores.players[0], PlayerScore{publicVp = 12, factionVp = 6, directivesCompleted = 1, directiveVp = 2, totalVp = 20, resources = 15})
	testing.expect_value(t, scores.players[1], PlayerScore{publicVp = 10, factionVp = 8, directivesCompleted = 0, directiveVp = 0, totalVp = 18, resources = 12})
	testing.expect_value(t, scores.players[2], PlayerScore{publicVp = 10, factionVp = 2, directivesCompleted = 0, directiveVp = 0, totalVp = 12, resources = 9})
	testing.expect_value(t, scores.players[3], PlayerScore{publicVp = 10, factionVp = 0, directivesCompleted = 3, directiveVp = 6, totalVp = 16, resources = 8})
	testing.expect_value(t, scores.winnerCount, 1)
	testing.expect_value(t, scores.winners, [MAX_PLAYERS]bool{true, false, false, false})
	before := game
	again: FinalScores
	testing.expect(t, CalculateFinalScores(&game, &again))
	testing.expect_value(t, again, scores)
	testing.expect(t, !BeginTurn(&game))
	testing.expect(t, !EndTurn(&game))
	testing.expect_value(t, game, before)
}
