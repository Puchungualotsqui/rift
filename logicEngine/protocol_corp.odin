package logicEngine

// Single-hex choices use to. Hostile Takeover and Audit use other; Audit uses
// cardIndex, and Hostile Takeover and Monopoly use resource.
ApplyCorpProtocol :: proc(game: ^Game, cardId: int, choice: ProtocolChoice) -> bool {
	if game == nil || game.playerCount < 1 || game.playerCount > MAX_PLAYERS ||
		game.currentPlayer < 0 || game.currentPlayer >= game.playerCount {
		return false
	}
	who := game.currentPlayer
	player := &game.players[who]
	if player.faction != .Corp do return false

	switch cardId {
	case 3: // Hostile Takeover
		if choice.other < 0 || choice.other >= game.playerCount || choice.other == who do return false
		switch choice.resource {
		case .Energy, .Data:
		case: return false
		}
		return TransferResource(game, choice.other, who, choice.resource, 1)
	case 4: // Fortify
		if !Controls(game, who, choice.to) do return false
		cell := &game.board[CellIndex(game, choice.to)]
		if !cell.structures[who] do return false
		cell.fortified[who] = true
		return true
	case 5: // Dividend
		count := 0
		for &cell in game.board {
			if cell.structures[who] && Controls(game, who, cell.pos) do count += 1
		}
		GainResources(player, Resources{0, min(count, 3)})
		return true
	case 6: // Lobby
		DrawCard(player)
		DrawCard(player)
		return true
	case 7: // Redundancy
		if !Controls(game, who, choice.to) do return false
		cell := &game.board[CellIndex(game, choice.to)]
		if !cell.structures[who] || cell.shielded[who] do return false
		cell.shielded[who] = true
		return true
	case 8: // Bailout
		GainResources(player, Resources{0, 2})
		return true
	case 9: // Contract
		if !Controls(game, who, choice.to) do return false
		cell := &game.board[CellIndex(game, choice.to)]
		switch cell.terrain {
		case .Energy_Node: GainResources(player, Resources{3, 0})
		case .Data_Node:   GainResources(player, Resources{0, 3})
		case .Open, .Cover: return false
		case: return false
		}
		return true
	case 10: // Automate
		player.automate = true
		return true
	case 11: // Audit
		if choice.other < 0 || choice.other >= game.playerCount || choice.other == who do return false
		return DiscardCard(&game.players[choice.other], choice.cardIndex)
	case 12: // Shareholder Value
		DrawCard(player)
		GainResources(player, Resources{0, 1})
		return true
	case 13: // Monopoly
		own: ^int
		switch choice.resource {
		case .Energy: own = &player.resources.energy
		case .Data:   own = &player.resources.data
		case: return false
		}
		for other in 0..<game.playerCount {
			if other == who do continue
			opponent := &game.players[other]
			available: ^int
			switch choice.resource {
			case .Energy: available = &opponent.resources.energy
			case .Data:   available = &opponent.resources.data
			case: return false
			}
			if available^ < 1 do continue
			if own^ < RESOURCE_CAP {
				if !TransferResource(game, other, who, choice.resource, 1) do return false
			} else {
				// Opponents still lose their resource when the gain is capped.
				available^ -= 1
			}
		}
		return true
	case: return false
	}
}
