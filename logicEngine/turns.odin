package logicEngine

// Drawing from an empty deck or into a full hand has no effect.
DrawCard :: proc(player: ^Player) -> bool {
	if player.deckCount <= 0 || player.handCount >= HAND_LIMIT do return false
	player.deckCount -= 1
	player.hand[player.handCount] = player.deck[player.deckCount]
	player.handCount += 1
	return true
}

GainResources :: proc(player: ^Player, amount: Resources) {
	if amount.energy > 0 do player.resources.energy = min(RESOURCE_CAP, player.resources.energy + amount.energy)
	if amount.data > 0 do player.resources.data = min(RESOURCE_CAP, player.resources.data + amount.data)
}

// Costs are atomic; validate actions before spending.
PayCost :: proc(player: ^Player, ap: int, cost: Resources) -> bool {
	if ap < 0 || cost.energy < 0 || cost.data < 0 || player.ap < ap ||
		player.resources.energy < cost.energy || player.resources.data < cost.data {
		return false
	}
	player.ap -= ap
	player.resources.energy -= cost.energy
	player.resources.data -= cost.data
	return true
}

BeginTurn :: proc(game: ^Game) -> bool {
	if game.phase != .Await_Turn do return false
	player := &game.players[game.currentPlayer]
	player.relayShield = false
	for &cell in game.board do cell.fortified[game.currentPlayer] = false
	income := Resources{1, 1}
	for &cell in game.board {
		if !Controls(game, game.currentPlayer, cell.pos) do continue
		switch cell.terrain {
		case .Energy_Node: income.energy += 1
		case .Data_Node:   income.data += 1
		case .Open, .Cover:
		}
	}
	GainResources(player, income)
	DrawCard(player)
	player.ap = 3
	game.relayDestroyedThisTurn = false
	game.phase = .Acting
	return true
}

// A player may end early; unspent AP is lost. Scoring is deliberately a
// separate phase so objective logic can award VP before the next round starts.
EndTurn :: proc(game: ^Game) -> bool {
	if game.phase != .Acting do return false
	who := game.currentPlayer
	player := &game.players[who]
	player.ap = 0
	player.automate = false
	player.pulse = false
	player.warpath = false
	player.struckThisTurn = false
	for &cell in game.board do cell.boostedUnits[who] = 0
	game.turnsTaken += 1
	if game.turnsTaken == game.playerCount {
		game.phase = .Score_Objective
	} else {
		game.currentPlayer = (game.currentPlayer + 1) % game.playerCount
		game.phase = .Await_Turn
	}
	return true
}

// Advance after scoring the current round. Use ScoreAndCompleteObjective.
AdvanceRound :: proc(game: ^Game) -> bool {
	if game.phase != .Score_Objective do return false
	if game.round == ROUND_COUNT {
		game.phase = .Finished
		return true
	}
	game.round += 1
	game.firstPlayer = (game.firstPlayer + 1) % game.playerCount
	game.currentPlayer = game.firstPlayer
	game.turnsTaken = 0
	for i in 0..<game.playerCount {game.players[i].roundCombatWins = 0}
	game.phase = .Await_Turn
	return true
}

Harvest :: proc(game: ^Game, pos: Hex) -> bool {
	if game.phase != .Acting do return false
	who := game.currentPlayer
	p := &game.players[who]
	if p.faction == .Nomad || !Controls(game, who, pos) do return false
	cell := &game.board[CellIndex(game, pos)]
	income: Resources
	switch cell.terrain {
	case .Energy_Node: income.energy = 2
	case .Data_Node:   income.data = 2
	case .Open, .Cover: return false
	}
	if !PayCost(p, 1, {}) do return false
	GainResources(p, income)
	return true
}

BuildUnit :: proc(game: ^Game, pos: Hex) -> bool {
	if game.phase != .Acting do return false
	who := game.currentPlayer
	if !Controls(game, who, pos) do return false
	cell := &game.board[CellIndex(game, pos)]
	if UnitCount(cell) >= UNIT_CAP do return false
	p := &game.players[who]
	cost := Resources{1, 0}
	switch p.faction {
	case .Corp: cost = {2, 0}
	case .AI:   cost = {0, 2}
	case .Swarm, .Nomad:
	}
	if p.automate do cost = {}
	if !PayCost(p, 1, cost) do return false
	p.automate = false
	cell.units[who] += 1
	return true
}

BuildStructure :: proc(game: ^Game, pos: Hex) -> bool {
	if game.phase != .Acting do return false
	who := game.currentPlayer
	if !Controls(game, who, pos) do return false
	p := &game.players[who]
	cell := &game.board[CellIndex(game, pos)]
	if p.faction == .Swarm || HasStructure(cell) do return false
	cost := Resources{0, 2}
	if p.faction == .Nomad {
		if cell.terrain == .Energy_Node || cell.terrain == .Data_Node do return false
		cost = {3, 0}
	}
	if p.automate do cost = {}
	if !PayCost(p, 1, cost) do return false
	p.automate = false
	cell.structures[who] = true
	return true
}

MoveUnits :: proc(game: ^Game, from, to: Hex, count: int) -> bool {
	if game.phase != .Acting || count < 1 || count > 2 || !HexAdjacent(from, to) do return false
	sourceIndex := CellIndex(game, from)
	targetIndex := CellIndex(game, to)
	if sourceIndex < 0 || targetIndex < 0 do return false
	source := &game.board[sourceIndex]
	target := &game.board[targetIndex]
	who := game.currentPlayer
	if source.rift || target.rift || source.units[who] < count ||
		UnitCount(target) + count > UNIT_CAP {
		return false
	}
	for enemy in 0..<game.playerCount {
		if enemy != who && (target.units[enemy] > 0 || target.structures[enemy]) do return false
	}
	if !PayCost(&game.players[who], 1, {}) do return false
	boosted := min(count, source.boostedUnits[who])
	source.units[who] -= count
	source.boostedUnits[who] -= boosted
	target.units[who] += count
	target.boostedUnits[who] += boosted
	return true
}

// Warpath permits a two-step move through an occupied intermediate hex.
MoveUnitsVia :: proc(game: ^Game, from, via, to: Hex, count: int) -> bool {
	if game == nil || game.phase != .Acting || !game.players[game.currentPlayer].warpath || count < 1 || count > 2 || from == to || !HexAdjacent(from, via) || !HexAdjacent(via, to) do return false
	si, vi, ti := CellIndex(game, from), CellIndex(game, via), CellIndex(game, to)
	if si < 0 || vi < 0 || ti < 0 do return false
	source, middle, target := &game.board[si], &game.board[vi], &game.board[ti]
	who := game.currentPlayer
	if source.rift || middle.rift || target.rift || source.units[who] < count || UnitCount(target) + count > UNIT_CAP do return false
	enemyOnPath := false
	for enemy in 0..<game.playerCount {
		if enemy == who do continue
		if middle.units[enemy] > 0 do enemyOnPath = true
		if target.units[enemy] > 0 || target.structures[enemy] do return false
	}
	if !enemyOnPath || !PayCost(&game.players[who], 1, {}) do return false
	boosted := min(count, source.boostedUnits[who])
	source.units[who] -= count
	source.boostedUnits[who] -= boosted
	target.units[who] += count
	target.boostedUnits[who] += boosted
	return true
}

