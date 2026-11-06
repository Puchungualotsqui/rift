package logicEngine

// Select one or two distinct controlled hexes with room.
Proliferate :: proc(game: ^Game, positions: []Hex) -> bool {
	if game.phase != .Acting || game.players[game.currentPlayer].faction != .Swarm || len(positions) < 1 || len(positions) > 2 do return false
	who := game.currentPlayer
	for pos, i in positions {
		if i > 0 && pos == positions[0] do return false
		if !Controls(game, who, pos) do return false
		if UnitCount(&game.board[CellIndex(game, pos)]) >= UNIT_CAP do return false
	}
	if !PayCost(&game.players[who], 1, Resources{1, 0}) do return false
	for pos in positions {game.board[CellIndex(game, pos)].units[who] += 1}
	return true
}

Reinvest :: proc(game: ^Game) -> bool {
	if game.phase != .Acting || game.players[game.currentPlayer].faction != .Corp do return false
	who := game.currentPlayer
	count := 0
	for &cell in game.board {
		if cell.structures[who] && Controls(game, who, cell.pos) do count += 1
	}
	if !PayCost(&game.players[who], 1, {}) do return false
	count = min(count, 3)
	GainResources(&game.players[who], Resources{count, count})
	return true
}

RewireRelay :: proc(game: ^Game, pos: Hex) -> bool {
	if game.phase != .Acting || game.players[game.currentPlayer].faction != .AI do return false
	who := game.currentPlayer
	if !Controls(game, who, pos) do return false
	cell := &game.board[CellIndex(game, pos)]
	if cell.relay != NO_PLAYER do return false
	if !PayCost(&game.players[who], 1, Resources{0, 1}) do return false
	cell.relay = who
	return true
}

RewireTerrain :: proc(game: ^Game, pos: Hex, terrain: Terrain) -> bool {
	if game.phase != .Acting || game.players[game.currentPlayer].faction != .AI do return false
	switch terrain {
	case .Open, .Cover, .Energy_Node, .Data_Node:
	case: return false
	}
	who := game.currentPlayer
	if IsStartHex(pos) || !Controls(game, who, pos) do return false
	if !PayCost(&game.players[who], 1, Resources{0, 1}) do return false
	game.board[CellIndex(game, pos)].terrain = terrain
	return true
}

// An enemy unit may destroy one relay free per turn.
DestroyRelay :: proc(game: ^Game, pos: Hex) -> bool {
	if game.phase != .Acting || game.relayDestroyedThisTurn do return false
	i := CellIndex(game, pos)
	if i < 0 do return false
	cell := &game.board[i]
	who := game.currentPlayer
	if cell.rift || cell.units[who] < 1 || cell.relay < 0 || cell.relay >= game.playerCount || cell.relay == who do return false
	if game.players[cell.relay].relayShield || !DestroyRelayToken(game, pos, who) do return false
	game.relayDestroyedThisTurn = true
	return true
}

// Hit and Run may enter an enemy-controlled hex and optionally Strike.
HitAndRunWithCards :: proc(game: ^Game, from, to: Hex, count: int, doStrike, capture: bool, choice: CombatChoice) -> (CombatResult, bool) {
	result: CombatResult
	if game == nil || game.playerCount < 2 || game.playerCount > MAX_PLAYERS || game.currentPlayer < 0 || game.currentPlayer >= game.playerCount do return result, false
	if game.phase != .Acting || game.players[game.currentPlayer].faction != .Nomad || count < 1 || count > 2 || !HexAdjacent(from, to) do return result, false
	copy := game^
	si, ti := CellIndex(&copy, from), CellIndex(&copy, to)
	if si < 0 || ti < 0 do return result, false
	source, target := &copy.board[si], &copy.board[ti]
	who := copy.currentPlayer
	if source.rift || target.rift || source.units[who] < count || UnitCount(target) + count > UNIT_CAP do return result, false
	defender := CombatDefender(&copy, target, who)
	enemyPresent := false
	for i in 0..<copy.playerCount {
		if i != who && (target.units[i] > 0 || target.structures[i]) do enemyPresent = true
	}
	if enemyPresent {
		if defender == NO_PLAYER || !Controls(&copy, defender, to) do return result, false
	} else if doStrike do return result, false
	if !doStrike && (choice.attackerCard != NO_CARD || choice.defenderCard != NO_CARD || choice.attackerMoveCount != 0 || choice.defenderMoveCount != 0) do return result, false
	if !PayCost(&copy.players[who], 1, {}) do return result, false
	boosted := min(count, source.boostedUnits[who])
	source.units[who] -= count
	source.boostedUnits[who] -= boosted
	target.units[who] += count
	target.boostedUnits[who] += boosted
	if doStrike {
		// The free Strike still counts for Warpath.
		copy.players[who].struckThisTurn = true
		ok: bool
		result, ok = ResolveCombatWithCards(&copy, target, target, who, defender, count, boosted, capture, choice)
		if !ok do return {}, false
	}
	game^ = copy
	return result, true
}

