package logicEngine

NO_CARD :: -1

CombatMove :: struct {
	from, to: Hex,
}

// Moves are optional, apply in array order, and must match a triggered card.
CombatChoice :: struct {
	attackerCard, defenderCard: int, // Hand indices, or NO_CARD.
	plunder: ResourceKind,
	attackerMoves, defenderMoves: [UNIT_CAP]CombatMove,
	attackerMoveCount, defenderMoveCount: int,
}

CombatResult :: struct {
	attackerStrength, defenderStrength: int,
	attackerWon: bool,
	unitDestroyed: bool,
	structureDestroyed: bool,
	captured: bool,
}

// Targets must contain pieces from only one opponent; relays alone are not targets.
CombatDefender :: proc(game: ^Game, cell: ^Cell, attacker: int) -> int {
	defender := NO_PLAYER
	for i in 0..<game.playerCount {
		if i == attacker || (cell.units[i] == 0 && !cell.structures[i]) do continue
		if defender != NO_PLAYER do return NO_PLAYER
		defender = i
	}
	return defender
}

CombatDefense :: proc(game: ^Game, target: ^Cell, defender: int) -> int {
	strength := target.units[defender] + target.boostedUnits[defender]
	if target.terrain == .Cover do strength += 1
	if target.structures[defender] {
		strength += 1
		if target.fortified[defender] do strength += 2
	}
	if game.players[defender].faction == .AI {
		for &cell in game.board {
			if cell.rift || cell.relay != defender || !HexAdjacent(cell.pos, target.pos) do continue
			strength += 1
			if game.players[defender].pulse do strength += 1
		}
	}
	return strength
}

// A card index is checked even when Counter-Intelligence suppresses its payment.
CombatCardId :: proc(player: ^Player, handIndex: int) -> (int, bool) {
	if handIndex == NO_CARD do return NO_CARD, true
	if player.handCount < 0 || player.handCount > len(player.hand) || handIndex < 0 || handIndex >= player.handCount do return NO_CARD, false
	id := player.hand[handIndex]
	card, ok := LookupCard(player.faction, id)
	if !ok || card.kind != .Combat do return NO_CARD, false
	return id, true
}

// Unit-based bonuses use participating units, except Boarding Party's hex count.
CombatCardBonus :: proc(game: ^Game, player: int, cardId: int, attacking: bool, source, target: ^Cell, attackerCount, defenderCount: int) -> int {
	if cardId == NO_CARD do return 0
	ownCount := defenderCount
	if attacking do ownCount = attackerCount
	switch game.players[player].faction {
	case .Swarm:
		switch cardId {
		case 0:
			hexCount := ownCount
			if attacking do hexCount = source.units[player]
			return min(max(hexCount - 1, 0), 2)
		case 1: if !attacking do return 2
		case 2: if attacking && attackerCount > defenderCount do return 2
		case 3:
		case:
		}
	case .Corp:
		switch cardId {
		case 0:
			if !attacking {
				if target.structures[player] do return 3
				return 2
			}
		case 1:
			count := 0
			for &cell in game.board {
				if !cell.rift && cell.structures[player] && HexAdjacent(cell.pos, target.pos) && Controls(game, player, cell.pos) do count += 1
			}
			return min(count, 2)
		case 2:
		case:
		}
	case .AI:
		switch cardId {
		case 0:
			if !attacking {
				for &cell in game.board {
					if !cell.rift && cell.relay == player && HexAdjacent(cell.pos, target.pos) do return 3
				}
				return 2
			}
		case 1:
			count := 0
			for &cell in game.board {
				if !cell.rift && cell.relay != NO_PLAYER && HexAdjacent(cell.pos, target.pos) do count += 1
			}
			return min(count, 2)
		case 2: if !attacking do return 1
		case:
		}
	case .Nomad:
		switch cardId {
		case 0: return source.units[player]
		case 1: if !attacking do return 2
		case 2:
			defender := CombatDefender(game, target, game.currentPlayer)
			if defender != NO_PLAYER && (target.structures[defender] || target.relay == defender) do return 2
		case 3, 4:
		case:
		}
	}
	return 0
}

CombatParticipants :: struct {
	units, boosted: [HEX_COUNT]int,
}

// Boosted units participate first; casualties remove unboosted participants first.
CombatRemoveUnit :: proc(game: ^Game, player, index: int, participants: ^CombatParticipants) {
	cell := &game.board[index]
	if participants.units[index] == participants.boosted[index] {
		participants.boosted[index] -= 1
		cell.boostedUnits[player] -= 1
	}
	participants.units[index] -= 1
	cell.units[player] -= 1
}

// Only original participants may move, even when other friendly units share a hex.
CombatMoveParticipant :: proc(game: ^Game, player: int, participants: ^CombatParticipants, move: CombatMove, capture, trackDestination: bool) -> bool {
	fromIndex, toIndex := CellIndex(game, move.from), CellIndex(game, move.to)
	if fromIndex < 0 || toIndex < 0 || participants.units[fromIndex] < 1 do return false
	from, to := &game.board[fromIndex], &game.board[toIndex]
	fromBoost, toBoost := from.boostedUnits[player], to.boostedUnits[player]
	boosted := 0
	if participants.boosted[fromIndex] > 0 do boosted = 1
	if !MoveUnitEffect(game, player, move.from, move.to, capture) do return false
	from.boostedUnits[player] = fromBoost - boosted
	to.boostedUnits[player] = toBoost + boosted
	participants.units[fromIndex] -= 1
	participants.boosted[fromIndex] -= boosted
	if trackDestination {
		participants.units[toIndex] += 1
		participants.boosted[toIndex] += boosted
	}
	return true
}

CombatMoveLimit :: proc(faction: Faction, cardId: int, attacking, won: bool) -> int {
	if faction == .Swarm && cardId == 3 && attacking && won do return UNIT_CAP
	if faction == .AI && cardId == 2 && !won do return 1
	if faction == .Nomad && cardId == 3 do return 1
	return 0
}

CombatApplyMoves :: proc(game: ^Game, player: int, participants: ^CombatParticipants, moves: [UNIT_CAP]CombatMove, count, limit: int) -> bool {
	if count < 0 || count > limit || count > len(moves) do return false
	for i in 0..<count {
		if !CombatMoveParticipant(game, player, participants, moves[i], false, false) do return false
	}
	return true
}

// If neither resource can be transferred, Plunder has no effect.
CombatPlunder :: proc(game: ^Game, attacker, defender: int, resource: ResourceKind) -> bool {
	from, to := &game.players[defender], &game.players[attacker]
	energyAvailable := from.resources.energy > 0 && to.resources.energy < RESOURCE_CAP
	dataAvailable := from.resources.data > 0 && to.resources.data < RESOURCE_CAP
	switch resource {
	case .Energy:
		if energyAvailable do return TransferResource(game, defender, attacker, resource, 1)
	case .Data:
		if dataAvailable do return TransferResource(game, defender, attacker, resource, 1)
	case: return false
	}
	return !energyAvailable && !dataAvailable
}

// Source equals target for Hit and Run, after its movement has been applied.
ResolveCombatWithCards :: proc(game: ^Game, source, target: ^Cell, attacker, defender, count, boostedCount: int, capture: bool, choice: CombatChoice) -> (CombatResult, bool) {
	result: CombatResult
	attackerId, attackerOk := CombatCardId(&game.players[attacker], choice.attackerCard)
	defenderId, defenderOk := CombatCardId(&game.players[defender], choice.defenderCard)
	if !attackerOk || !defenderOk do return result, false
	counter := game.players[defender].faction == .Corp && defenderId == 2
	suppressedDefender := attackerId != NO_CARD && defenderId != NO_CARD && !counter
	if suppressedDefender do defenderId = NO_CARD
	if defenderId != NO_CARD && !DiscardAndPayCard(&game.players[defender], choice.defenderCard, .Combat) do return result, false
	if counter {
		attackerId = NO_CARD
	} else if attackerId != NO_CARD {
		// Counter-Intelligence cannot prevent its own reveal.
		if game.players[attacker].faction == .Corp && attackerId == 2 do return result, false
		if !DiscardAndPayCard(&game.players[attacker], choice.attackerCard, .Combat) do return result, false
	}

	si, ti := CellIndex(game, source.pos), CellIndex(game, target.pos)
	attacking, defending: CombatParticipants
	attacking.units[si] = count
	attacking.boosted[si] = boostedCount
	defending.units[ti] = target.units[defender]
	defending.boosted[ti] = target.boostedUnits[defender]
	result.attackerStrength = count + attacking.boosted[si]
	result.defenderStrength = CombatDefense(game, target, defender)
	result.attackerStrength += CombatCardBonus(game, attacker, attackerId, true, source, target, count, defending.units[ti])
	result.defenderStrength += CombatCardBonus(game, defender, defenderId, false, source, target, count, defending.units[ti])
	result.attackerWon = result.attackerStrength > result.defenderStrength

	winner := defender
	if result.attackerWon {
		winner = attacker
		if defending.units[ti] > 0 {
			CombatRemoveUnit(game, defender, ti, &defending)
			result.unitDestroyed = true
		}
		if defending.units[ti] == 0 && capture {
			if si != ti {
				move := CombatMove{source.pos, target.pos}
				if !CombatMoveParticipant(game, attacker, &attacking, move, true, true) do return {}, false
			}
			result.captured = true
			// A shield can leave the structure in the now-contested hex.
			if target.structures[defender] do result.structureDestroyed = DestroyStructure(game, target.pos, defender, attacker)
		}
	} else {
		CombatRemoveUnit(game, attacker, si, &attacking)
		result.unitDestroyed = true
	}
	game.players[winner].combatWins += 1
	game.players[winner].roundCombatWins += 1
	if result.unitDestroyed {
		game.players[winner].unitsDestroyed += 1
		game.players[winner].tokensDestroyed += 1
	}
	// Plunder names the defender as its source, so it only triggers for an attacker.
	if result.attackerWon && game.players[attacker].faction == .Nomad && attackerId == 4 {
		if !CombatPlunder(game, attacker, defender, choice.plunder) do return {}, false
	}

	// Defender moves first; suppressed cards have no movement effect.
	if !suppressedDefender {
		defenderLimit := CombatMoveLimit(game.players[defender].faction, defenderId, false, !result.attackerWon)
		if !CombatApplyMoves(game, defender, &defending, choice.defenderMoves, choice.defenderMoveCount, defenderLimit) do return {}, false
	}
	if !counter {
		attackerLimit := CombatMoveLimit(game.players[attacker].faction, attackerId, true, result.attackerWon)
		if !CombatApplyMoves(game, attacker, &attacking, choice.attackerMoves, choice.attackerMoveCount, attackerLimit) do return {}, false
	}
	return result, true
}

// Success indicates legality, not victory. Invalid choices leave the game unchanged.
StrikeWithCards :: proc(game: ^Game, from, to: Hex, count: int, capture: bool, choice: CombatChoice) -> (CombatResult, bool) {
	result: CombatResult
	if game == nil || game.playerCount < 2 || game.playerCount > MAX_PLAYERS || game.currentPlayer < 0 || game.currentPlayer >= game.playerCount do return result, false
	if game.phase != .Acting || count < 1 || !HexAdjacent(from, to) do return result, false
	copy := game^
	si, ti := CellIndex(&copy, from), CellIndex(&copy, to)
	if si < 0 || ti < 0 do return result, false
	source, target := &copy.board[si], &copy.board[ti]
	attacker := copy.currentPlayer
	if source.rift || target.rift || source.units[attacker] < count do return result, false
	defender := CombatDefender(&copy, target, attacker)
	if defender == NO_PLAYER do return result, false
	player := &copy.players[attacker]
	ap := 1
	if player.warpath && !player.struckThisTurn do ap = 0
	if !PayCost(player, ap, {}) do return result, false
	player.struckThisTurn = true
	ok: bool
	result, ok = ResolveCombatWithCards(&copy, source, target, attacker, defender, count, min(count, source.boostedUnits[attacker]), capture, choice)
	if !ok do return {}, false
	game^ = copy
	return result, true
}

