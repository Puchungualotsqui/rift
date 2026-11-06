package logicEngine

// Single-hex choices use to; Burrow and Brood use from and to. Corrode uses
// target, and Swarm Sense uses cardIndex as an offset from the top of the deck.
ApplySwarmProtocol :: proc(game: ^Game, cardId: int, choice: ProtocolChoice) -> bool {
	if game == nil || game.playerCount < 1 || game.playerCount > MAX_PLAYERS ||
		game.currentPlayer < 0 || game.currentPlayer >= game.playerCount {
		return false
	}
	who := game.currentPlayer
	player := &game.players[who]
	if player.faction != .Swarm do return false

	switch cardId {
	case 4: // Sacrifice
		i := CellIndex(game, choice.to)
		if i < 0 || game.board[i].rift || game.board[i].units[who] < 1 do return false
		cell := &game.board[i]
		cell.units[who] -= 1
		if cell.boostedUnits[who] > cell.units[who] do cell.boostedUnits[who] -= 1
		DrawCard(player)
		DrawCard(player)
		return true
	case 5: // Swarm Sense
		if player.deckCount < 1 || player.deckCount > len(player.deck) ||
			choice.cardIndex < 0 || choice.cardIndex > 1 || choice.cardIndex >= player.deckCount {
			return false
		}
		if player.deckCount > 1 {
			otherIndex := player.deckCount - 2 + choice.cardIndex
			other := player.deck[otherIndex]
			for i := otherIndex; i > 0; i -= 1 {
				player.deck[i] = player.deck[i - 1]
			}
			player.deck[0] = other
		}
		DrawCard(player)
		return true
	case 6: // Burrow
		if !HexAdjacent(choice.from, choice.to) do return false
		return MoveUnitEffect(game, who, choice.from, choice.to, false)
	case 7: // Replicate
		if !Controls(game, who, choice.to) do return false
		cell := &game.board[CellIndex(game, choice.to)]
		if UnitCount(cell) >= UNIT_CAP do return false
		cell.units[who] += 1
		return true
	case 8: // Hive Mind
		i := CellIndex(game, choice.to)
		if i < 0 || game.board[i].rift || game.board[i].units[who] < 1 do return false
		cell := &game.board[i]
		cell.boostedUnits[who] = cell.units[who]
		return true
	case 9: // Corrode
		i := CellIndex(game, choice.to)
		if i < 0 || game.board[i].rift do return false
		adjacent := false
		for &cell in game.board {
			if !cell.rift && cell.units[who] > 0 && HexAdjacent(cell.pos, choice.to) do adjacent = true
		}
		if !adjacent do return false
		cell := &game.board[i]
		switch choice.target {
		case .Structure:
			owner := NO_PLAYER
			for enemy in 0..<game.playerCount {
				if enemy == who || !cell.structures[enemy] do continue
				if owner != NO_PLAYER do return false
				owner = enemy
			}
			if owner == NO_PLAYER do return false
			// A shield absorbs the destruction without invalidating the effect.
			DestroyStructure(game, choice.to, owner, who)
			return true
		case .Relay:
			if cell.relay < 0 || cell.relay >= game.playerCount || cell.relay == who do return false
			return DestroyRelayToken(game, choice.to, who)
		case: return false
		}
	case 10: // Brood
		if choice.from == choice.to || !Controls(game, who, choice.from) || !Controls(game, who, choice.to) do return false
		from := &game.board[CellIndex(game, choice.from)]
		to := &game.board[CellIndex(game, choice.to)]
		if UnitCount(from) >= UNIT_CAP || UnitCount(to) >= UNIT_CAP do return false
		from.units[who] += 1
		to.units[who] += 1
		return true
	case 11: // Endless
		GainResources(player, Resources{2, 0})
		return true
	case: return false
	}
}
