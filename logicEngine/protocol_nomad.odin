package logicEngine

// Single-hex targets use to; movement uses from and to. Scorched Earth and
// Strike Team use target; Strike Team uses option, and Tribute uses other.
ApplyNomadProtocol :: proc(game: ^Game, cardId: int, choice: ProtocolChoice) -> bool {
	if game == nil || game.playerCount < 1 || game.playerCount > MAX_PLAYERS ||
		game.currentPlayer < 0 || game.currentPlayer >= game.playerCount {
		return false
	}
	who := game.currentPlayer
	player := &game.players[who]
	if player.faction != .Nomad do return false

	switch cardId {
	case 5: // Scorched Earth
		if !Controls(game, who, choice.to) do return false
		cell := &game.board[CellIndex(game, choice.to)]
		switch choice.target {
		case .Structure:
			if !cell.structures[who] do return false
			// A shield prevents destruction, but not the separate Energy gain.
			DestroyStructure(game, choice.to, who, who)
		case .Relay:
			if cell.relay == NO_PLAYER || !DestroyRelayToken(game, choice.to, who) do return false
		case: return false
		}
		GainResources(player, Resources{3, 0})
		return true
	case 6: // Smoke and Mirrors
		DrawCard(player)
		return true
	case 7: // Forage
		GainResources(player, Resources{1, 1})
		return true
	case 8: // Strike Team
		if !HexAdjacent(choice.from, choice.to) do return false
		toIndex := CellIndex(game, choice.to)
		if toIndex < 0 do return false
		to := &game.board[toIndex]
		if to.rift || UnitCount(to) >= UNIT_CAP do return false
		enemyStructure := NO_PLAYER
		for enemy in 0..<game.playerCount {
			if enemy == who do continue
			if to.units[enemy] > 0 do return false
			if !to.structures[enemy] do continue
			if enemyStructure != NO_PLAYER do return false
			enemyStructure = enemy
		}
		if !choice.option do return MoveUnitEffect(game, who, choice.from, choice.to, true)
		switch choice.target {
		case .Structure:
			if enemyStructure == NO_PLAYER do return false
			if !MoveUnitEffect(game, who, choice.from, choice.to, true) do return false
			DestroyStructure(game, choice.to, enemyStructure, who)
			return true
		case .Relay:
			if to.relay < 0 || to.relay >= game.playerCount || to.relay == who do return false
			if !MoveUnitEffect(game, who, choice.from, choice.to, true) do return false
			return DestroyRelayToken(game, choice.to, who)
		case: return false
		}
	case 9: // Flee
		if !HexAdjacent(choice.from, choice.to) do return false
		fromIndex := CellIndex(game, choice.from)
		if fromIndex < 0 || game.board[fromIndex].rift do return false
		from := &game.board[fromIndex]
		enemyPresent := false
		for enemy in 0..<game.playerCount {
			if enemy != who && from.units[enemy] > 0 do enemyPresent = true
		}
		if !enemyPresent do return false
		return MoveUnitEffect(game, who, choice.from, choice.to, false)
	case 10: // Tribute
		if choice.other < 0 || choice.other >= game.playerCount || choice.other == who do return false
		switch choice.resource {
		case .Energy, .Data:
		case: return false
		}
		if !TransferResource(game, choice.other, who, choice.resource, 1) do return false
		switch choice.resource {
		case .Energy: GainResources(player, Resources{1, 0})
		case .Data:   GainResources(player, Resources{0, 1})
		case: return false
		}
		return true
	case 11: // Warpath
		player.warpath = true
		return true
	case: return false
	}
}
