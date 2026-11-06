package logicEngine

ObservationKind :: enum {
	None,
	Hand,
	Deck,
}

ProtocolObservation :: struct {
	kind: ObservationKind,
	owner: int,
	cardIds: [HAND_LIMIT]int,
	count: int,
}

PendingProtocol :: struct {
	cardId: int,
	other: int,
}

IsInformationalProtocol :: proc(faction: Faction, id: int) -> bool {
	switch faction {
	case .Swarm: return id == 5
	case .Corp: return id == 11
	case .AI: return id == 3 || id == 7
	case .Nomad: return false
	}
	return false
}

// Payment is committed before revealing cards. Data Spike finishes immediately;
// the other informational cards require FinishInformationalProtocol.
BeginInformationalProtocol :: proc(game: ^Game, handIndex, other: int) -> (ProtocolObservation, bool) {
	observation := ProtocolObservation{owner = NO_PLAYER}
	if game == nil || game.phase != .Acting || game.playerCount < 2 || game.playerCount > MAX_PLAYERS ||
		game.currentPlayer < 0 || game.currentPlayer >= game.playerCount {
		return observation, false
	}
	copy := game^
	player := &copy.players[copy.currentPlayer]
	if !ValidateCard(player, handIndex, .Protocol) do return observation, false
	id := player.hand[handIndex]
	if !IsInformationalProtocol(player.faction, id) do return observation, false

	switch player.faction {
	case .Swarm:
		if player.deckCount < 1 || player.deckCount > len(player.deck) do return observation, false
		observation.kind = .Deck
		observation.owner = copy.currentPlayer
		observation.count = min(player.deckCount, 2)
		for i in 0..<observation.count do observation.cardIds[i] = player.deck[player.deckCount - 1 - i]
	case .Corp:
		if !ValidOpponent(&copy, other) do return observation, false
		opponent := &copy.players[other]
		if opponent.handCount < 1 || opponent.handCount > len(opponent.hand) ||
			opponent.discardCount < 0 || opponent.discardCount >= len(opponent.discard) {
			return observation, false
		}
		observation.kind = .Hand
		observation.owner = other
		observation.count = opponent.handCount
		for i in 0..<opponent.handCount do observation.cardIds[i] = opponent.hand[i]
	case .AI:
		if id == 3 {
			if !ValidOpponent(&copy, other) do return observation, false
			opponent := &copy.players[other]
			if opponent.handCount < 0 || opponent.handCount > len(opponent.hand) do return observation, false
			observation.kind = .Hand
			observation.owner = other
			observation.count = opponent.handCount
			for i in 0..<opponent.handCount do observation.cardIds[i] = opponent.hand[i]
		} else {
			if player.deckCount < 0 || player.deckCount > len(player.deck) do return observation, false
			observation.kind = .Deck
			observation.owner = copy.currentPlayer
			if player.deckCount > 0 {
				observation.count = 1
				observation.cardIds[0] = player.deck[player.deckCount - 1]
			}
		}
	case .Nomad: return observation, false
	case: return observation, false
	}
	if !DiscardAndPayCard(player, handIndex, .Protocol) do return {}, false
	if player.faction != .AI || id != 3 {
		copy.pendingProtocol = {id, other}
		copy.phase = .Protocol_Choice
	}
	game^ = copy
	return observation, true
}

// Invalid choices leave the paid action pending and do not reveal new cards.
FinishInformationalProtocol :: proc(game: ^Game, choice: ProtocolChoice) -> bool {
	if game == nil || game.phase != .Protocol_Choice || game.playerCount < 2 || game.playerCount > MAX_PLAYERS ||
		game.currentPlayer < 0 || game.currentPlayer >= game.playerCount {
		return false
	}
	copy := game^
	player := &copy.players[copy.currentPlayer]
	id := copy.pendingProtocol.cardId
	effectChoice := choice
	effectChoice.other = copy.pendingProtocol.other
	ok := false
	switch player.faction {
	case .Swarm: if id == 5 do ok = ApplySwarmProtocol(&copy, id, effectChoice)
	case .Corp: if id == 11 do ok = ApplyCorpProtocol(&copy, id, effectChoice)
	case .AI: if id == 7 do ok = ApplyAiProtocol(&copy, id, effectChoice)
	case .Nomad:
	case:
	}
	if !ok do return false
	copy.pendingProtocol = {}
	copy.phase = .Acting
	game^ = copy
	return true
}

ValidOpponent :: proc(game: ^Game, player: int) -> bool {
	return player >= 0 && player < game.playerCount && player != game.currentPlayer
}
