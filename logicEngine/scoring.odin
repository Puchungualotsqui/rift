package logicEngine

// Directive IDs are the zero-based indices of the cards in DESIGN.md.
DIRECTIVE_COUNT :: 12
OBJECTIVE_VP :: 2
DIRECTIVE_VP :: 2

ScoringStats :: struct {
	controlled:           int,
	developed:            int,
	resourceNodes:       int,
	units:                int,
	structures:           int,
	relays:               int,
	largestRelayNetwork: int,
	innerRing:           bool,
	outerRing:           bool,
	center:               bool,
}

// Count active hexes; development requires control, not token ownership.
CalculateScoringStats :: proc(game: ^Game, player: int) -> ScoringStats {
	stats: ScoringStats
	if game == nil || player < 0 || player >= game.playerCount || player >= MAX_PLAYERS do return stats
	for &cell in game.board {
		if cell.rift do continue
		stats.units += cell.units[player]
		if cell.structures[player] do stats.structures += 1
		if cell.relay == player && game.players[player].faction == .AI do stats.relays += 1
		if !Controls(game, player, cell.pos) do continue
		stats.controlled += 1
		node := cell.terrain == .Energy_Node || cell.terrain == .Data_Node
		if node do stats.resourceNodes += 1
		if node || HasStructure(&cell) || cell.relay != NO_PLAYER do stats.developed += 1
		switch HexDistance(cell.pos, Hex{}) {
		case 0: stats.center = true
		case 1: stats.innerRing = true
		case 2: stats.outerRing = true
		}
	}

	// Relay thresholds apply to one connected network.
	visited: [HEX_COUNT]bool
	for i in 0..<HEX_COUNT {
		cell := &game.board[i]
		if visited[i] || cell.rift || cell.relay != player || game.players[player].faction != .AI do continue
		queue: [HEX_COUNT]int
		queue[0] = i
		visited[i] = true
		head, count := 0, 1
		for head < count {
			current := queue[head]
			head += 1
			for j in 0..<HEX_COUNT {
				next := &game.board[j]
				if !visited[j] && !next.rift && next.relay == player &&
					HexAdjacent(game.board[current].pos, next.pos) {
					visited[j] = true
					queue[count] = j
					count += 1
				}
			}
		}
		stats.largestRelayNetwork = max(stats.largestRelayNetwork, count)
	}
	return stats
}

ObjectiveMet :: proc(game: ^Game, player, round: int) -> bool {
	if game == nil || player < 0 || player >= game.playerCount || player >= MAX_PLAYERS do return false
	p := &game.players[player]
	stats := CalculateScoringStats(game, player)
	switch round {
	case 1: return stats.controlled >= 2
	case 2: return p.resources.energy + p.resources.data >= 5
	case 3: return stats.developed >= 2
	case 4: return p.roundCombatWins >= 1
	case 5: return stats.units >= 4
	case 6:
		threshold := 4
		if game.playerCount == 2 do threshold = 3
		return stats.controlled >= threshold
	}
	return false
}

// Advancing the phase prevents scoring a round twice.
ScoreAndCompleteObjective :: proc(game: ^Game) -> bool {
	if game == nil || game.phase != .Score_Objective || game.round < 1 ||
		game.round > ROUND_COUNT || game.playerCount < 2 || game.playerCount > MAX_PLAYERS {
		return false
	}
	for player in 0..<game.playerCount {
		if ObjectiveMet(game, player, game.round) {
			game.players[player].publicVp += OBJECTIVE_VP
			game.players[player].objectivesScored += 1
		}
	}
	return AdvanceRound(game)
}

DirectiveMet :: proc(game: ^Game, player, directive: int) -> bool {
	if game == nil || player < 0 || player >= game.playerCount || player >= MAX_PLAYERS do return false
	p := &game.players[player]
	stats := CalculateScoringStats(game, player)
	switch directive {
	case 0:  return p.combatWins >= 3
	case 1:  return p.unitsDestroyed >= 3
	case 2:  return p.tokensDestroyed >= 2
	case 3:  return stats.controlled >= 5
	case 4:  return p.resources.energy + p.resources.data >= 6
	case 5:  return stats.developed >= 2
	case 6:  return stats.resourceNodes >= 2
	case 7:  return stats.units >= 5
	case 8:  return p.cardsPlayed >= 6
	case 9:  return stats.innerRing && stats.outerRing
	case 10: return p.objectivesScored >= 3
	case 11: return stats.center
	}
	return false
}

FactionVp :: proc(game: ^Game, player: int) -> int {
	if game == nil || player < 0 || player >= game.playerCount || player >= MAX_PLAYERS do return 0
	p := &game.players[player]
	stats := CalculateScoringStats(game, player)
	switch p.faction {
	case .Swarm:
		divisor := 2
		if game.playerCount == 2 do divisor = 3
		return stats.units / divisor + stats.controlled
	case .Corp:
		divisor := 3
		if game.playerCount == 2 do divisor = 4
		return 2 * stats.structures + (p.resources.energy + p.resources.data) / divisor
	case .AI:
		vp := stats.relays
		first, second := 3, 5
		if game.playerCount == 2 do first, second = 4, 6
		if stats.largestRelayNetwork >= first do vp += 2
		if stats.largestRelayNetwork >= second do vp += 2
		return vp
	case .Nomad:
		divisor := 3
		if game.playerCount == 2 do divisor = 2
		return p.unitsDestroyed + p.structuresDestroyed + p.resourcesStolen / divisor
	}
	return 0
}

PlayerScore :: struct {
	publicVp:           int,
	factionVp:          int,
	directivesCompleted: int,
	directiveVp:        int,
	totalVp:            int,
	resources:           int,
}

FinalScores :: struct {
	players: [MAX_PLAYERS]PlayerScore,
	winners: [MAX_PLAYERS]bool,
	winnerCount: int,
}

// Positive means a wins, negative means b wins, zero means a shared victory.
CompareScores :: proc(a, b: PlayerScore) -> int {
	if a.totalVp != b.totalVp do return a.totalVp - b.totalVp
	if a.publicVp != b.publicVp do return a.publicVp - b.publicVp
	if a.directivesCompleted != b.directivesCompleted do return a.directivesCompleted - b.directivesCompleted
	if a.factionVp != b.factionVp do return a.factionVp - b.factionVp
	return a.resources - b.resources
}

// Scoring is repeatable; invalid input leaves out unchanged.
CalculateFinalScores :: proc(game: ^Game, out: ^FinalScores) -> bool {
	if game == nil || out == nil || game.phase != .Finished ||
		game.playerCount < 2 || game.playerCount > MAX_PLAYERS {
		return false
	}
	result: FinalScores
	for i in 0..<game.playerCount {
		p := &game.players[i]
		if p.directiveCount < 0 || p.directiveCount > len(p.directives) do return false
		score := &result.players[i]
		score.publicVp = p.publicVp
		score.factionVp = FactionVp(game, i)
		score.resources = p.resources.energy + p.resources.data
		for j in 0..<p.directiveCount {
			id := p.directives[j]
			if id < 0 || id >= DIRECTIVE_COUNT do return false
			if DirectiveMet(game, i, id) do score.directivesCompleted += 1
		}
		score.directiveVp = score.directivesCompleted * DIRECTIVE_VP
		score.totalVp = score.publicVp + score.factionVp + score.directiveVp
	}
	best := 0
	for i in 1..<game.playerCount {
		if CompareScores(result.players[i], result.players[best]) > 0 do best = i
	}
	for i in 0..<game.playerCount {
		if CompareScores(result.players[i], result.players[best]) == 0 {
			result.winners[i] = true
			result.winnerCount += 1
		}
	}
	out^ = result
	return true
}
