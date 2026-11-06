package logicEngine

// Single-hex choices use to; Reroute uses from and to. Data Spike and
// Override use other; Ping uses option to put the top card on the bottom.
ApplyAiProtocol :: proc(game: ^Game, cardId: int, choice: ProtocolChoice) -> bool {
	if game == nil || game.playerCount < 1 || game.playerCount > MAX_PLAYERS ||
		game.currentPlayer < 0 || game.currentPlayer >= game.playerCount {
		return false
	}
	who := game.currentPlayer
	player := &game.players[who]
	if player.faction != .AI do return false

	switch cardId {
	case 3: // Data Spike: the caller can inspect the chosen opponent's hand.
		return choice.other >= 0 && choice.other < game.playerCount && choice.other != who
	case 4: // Reroute
		if !HexAdjacent(choice.from, choice.to) do return false
		fromIndex := CellIndex(game, choice.from)
		toIndex := CellIndex(game, choice.to)
		if fromIndex < 0 || toIndex < 0 do return false
		from, to := &game.board[fromIndex], &game.board[toIndex]
		if from.rift || from.relay != who || to.relay != NO_PLAYER || !Controls(game, who, choice.to) do return false
		from.relay = NO_PLAYER
		to.relay = who
		return true
	case 5: // Cascade
		count := 0
		for &cell in game.board {
			if !cell.rift && cell.relay == who do count += 1
		}
		for _ in 0..<min(count, 2) do DrawCard(player)
		return true
	case 6: // Override
		if choice.other < 0 || choice.other >= game.playerCount || choice.other == who do return false
		opponent := &game.players[choice.other]
		if opponent.handCount <= 0 || opponent.handCount > len(opponent.hand) ||
			opponent.discardCount < 0 || opponent.discardCount >= len(opponent.discard) {
			return false
		}
		return DiscardCard(opponent, RandomIndex(game, opponent.handCount))
	case 7: // Ping
		if player.deckCount < 0 || player.deckCount > len(player.deck) do return false
		if choice.option && player.deckCount > 1 {
			top := player.deck[player.deckCount - 1]
			for i := player.deckCount - 1; i > 0; i -= 1 {
				player.deck[i] = player.deck[i - 1]
			}
			player.deck[0] = top
		}
		DrawCard(player)
		return true
	case 8: // Mesh
		if !Controls(game, who, choice.to) do return false
		cell := &game.board[CellIndex(game, choice.to)]
		if cell.relay != NO_PLAYER do return false
		cell.relay = who
		return true
	case 9: // Relay Shield
		player.relayShield = true
		return true
	case 10: // Fork
		if !Controls(game, who, choice.to) do return false
		switch choice.resource {
		case .Energy, .Data:
		case: return false
		}
		count := 0
		for &cell in game.board {
			if !cell.rift && cell.relay == who && HexAdjacent(cell.pos, choice.to) do count += 1
		}
		count = min(count, 2)
		switch choice.resource {
		case .Energy: GainResources(player, Resources{count, 0})
		case .Data:   GainResources(player, Resources{0, count})
		case: return false
		}
		return true
	case 11: // Compile
		if IsStartHex(choice.to) || !Controls(game, who, choice.to) do return false
		switch choice.terrain {
		case .Open, .Cover, .Energy_Node, .Data_Node:
		case: return false
		}
		cell := &game.board[CellIndex(game, choice.to)]
		if cell.terrain == choice.terrain do return false
		cell.terrain = choice.terrain
		switch choice.terrain {
		case .Energy_Node: GainResources(player, Resources{1, 0})
		case .Data_Node:   GainResources(player, Resources{0, 1})
		case .Open, .Cover:
		case: return false
		}
		return true
	case 12: // Pulse
		player.pulse = true
		return true
	case: return false
	}
}
