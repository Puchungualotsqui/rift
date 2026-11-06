package logicEngine

// The board artwork does not specify coordinates; these are four opposite-pair
// starting spaces. Rifts and shuffled orders must be selected by the caller.
START_HEXES :: [?]Hex{{-2, 0}, {0, -2}, {2, 0}, {0, 2}}
TERRAIN_POOL :: [?]Terrain{
	.Energy_Node, .Energy_Node, .Energy_Node, .Energy_Node,
	.Data_Node, .Data_Node, .Data_Node, .Data_Node,
	.Cover, .Cover, .Cover, .Cover,
	.Open, .Open, .Open,
}

SetupPlayer :: struct {
	faction: Faction,
	start:   Hex,
	deck:    [14]int, // Permutation of 0..<FactionDeckSize(faction), drawn from the end.
}

SetupConfig :: struct {
	playerCount: int,
	players:      [MAX_PLAYERS]SetupPlayer,
	firstPlayer: int,
	randomSeed: u64,
	terrainOrder:   [15]int, // Permutation of terrain-pool indices.
	directiveOrder: [12]int, // Permutation of directive IDs.
}

FactionDeckSize :: proc(faction: Faction) -> int {
	switch faction {
	case .Swarm: return 12
	case .Corp:  return 14
	case .AI:    return 13
	case .Nomad: return 12
	}
	return 0
}

IsStartHex :: proc(pos: Hex) -> bool {
	for start in START_HEXES {
		if start == pos do return true
	}
	return false
}

ValidPermutation :: proc(values: []int) -> bool {
	for value, i in values {
		if value < 0 || value >= len(values) do return false
		for j in 0..<i {
			if values[j] == value do return false
		}
	}
	return true
}

RiftCandidate :: struct {
	pos: Hex,
	separation: int,
}

// Select farthest outer hexes; ties use q-then-r board order.
SelectRifts :: proc(config: SetupConfig) -> ([6]Hex, int, bool) {
	rifts: [6]Hex
	if config.playerCount < 2 || config.playerCount > MAX_PLAYERS do return rifts, 0, false
	for i in 0..<config.playerCount {
		if !IsStartHex(config.players[i].start) do return rifts, 0, false
		for j in 0..<i do if config.players[i].start == config.players[j].start do return rifts, 0, false
	}
	if config.playerCount == 2 && HexDistance(config.players[0].start, config.players[1].start) != 4 do return rifts, 0, false
	riftCount := (4 - config.playerCount) * 3
	forcedCount := 0
	if config.playerCount == 2 {
		for start in START_HEXES {
			selected := false
			for i in 0..<config.playerCount do if config.players[i].start == start do selected = true
			if !selected {
				rifts[forcedCount] = start
				forcedCount += 1
			}
		}
	}

	candidates: [12]RiftCandidate
	candidateCount := 0
	for q in -BOARD_RADIUS..=BOARD_RADIUS {
		for r in -BOARD_RADIUS..=BOARD_RADIUS {
			pos := Hex{q, r}
			if HexDistance(pos, Hex{}) != BOARD_RADIUS || IsStartHex(pos) do continue
			separation := BOARD_RADIUS * 2
			for i in 0..<config.playerCount do separation = min(separation, HexDistance(pos, config.players[i].start))
			candidates[candidateCount] = {pos, separation}
			candidateCount += 1
		}
	}

	needed := riftCount - forcedCount
	selectedCandidates: [12]bool
	for _ in 0..<needed {
		best := -1
		for i in 0..<candidateCount {
			if selectedCandidates[i] do continue
			if best < 0 || candidates[i].separation > candidates[best].separation do best = i
		}
		if best < 0 do return {}, 0, false
		selectedCandidates[best] = true
		rifts[forcedCount] = candidates[best].pos
		forcedCount += 1
	}
	return rifts, riftCount, true
}

// On failure, out is unchanged. Terrain is dealt in board array order;
// directives are dealt in clockwise order starting with the first player.
SetupGame :: proc(out: ^Game, config: SetupConfig) -> bool {
	if out == nil || config.playerCount < 2 || config.playerCount > 4 ||
		config.firstPlayer < 0 || config.firstPlayer >= config.playerCount {
		return false
	}
	orders := config
	if !ValidPermutation(orders.terrainOrder[:]) ||
		!ValidPermutation(orders.directiveOrder[:]) {
		return false
	}

	for i in 0..<config.playerCount {
		p := config.players[i]
		size := FactionDeckSize(p.faction)
		if size == 0 || !IsStartHex(p.start) || !ValidPermutation(p.deck[:size]) do return false
		for j in 0..<i {
			if p.faction == config.players[j].faction || p.start == config.players[j].start do return false
		}
	}
	if config.playerCount == 2 &&
		HexDistance(config.players[0].start, config.players[1].start) != 4 {
		return false
	}

	rifts, riftCount, validRifts := SelectRifts(config)
	if !validRifts do return false

	game: Game
	game.randomState = config.randomSeed
	game.playerCount = config.playerCount
	game.firstPlayer = config.firstPlayer
	game.currentPlayer = config.firstPlayer
	game.round = 1
	game.phase = .Await_Turn
	index := 0
	terrainIndex := 0
	terrainPool := TERRAIN_POOL
	for q in -BOARD_RADIUS..=BOARD_RADIUS {
		for r in -BOARD_RADIUS..=BOARD_RADIUS {
			pos := Hex{q, r}
			if !HexValid(pos) do continue
			cell := &game.board[index]
			cell.pos = pos
			cell.relay = NO_PLAYER
			for j in 0..<riftCount {
				if rifts[j] == pos do cell.rift = true
			}
			if !cell.rift && !IsStartHex(pos) {
				cell.terrain = terrainPool[config.terrainOrder[terrainIndex]]
				terrainIndex += 1
			}
			index += 1
		}
	}

	directiveIndex := 0
	for offset in 0..<config.playerCount {
		i := (config.firstPlayer + offset) % config.playerCount
		p := &game.players[i]
		p.faction = config.players[i].faction
		p.deck = config.players[i].deck
		p.deckCount = FactionDeckSize(p.faction)
		p.directiveCount = 2
		cell := &game.board[CellIndex(&game, config.players[i].start)]
		switch p.faction {
		case .Swarm:
			p.resources = {2, 1}
			cell.units[i] = 3
		case .Corp:
			p.resources = {2, 2}
			cell.units[i] = 2
			cell.structures[i] = true
		case .AI:
			p.resources = {2, 2}
			cell.units[i] = 1
			cell.relay = i
		case .Nomad:
			p.resources = {1, 1}
			cell.units[i] = 2
			p.directiveCount = 3
		}
		for j in 0..<p.directiveCount {
			p.directives[j] = config.directiveOrder[directiveIndex]
			directiveIndex += 1
		}
		for _ in 0..<3 {DrawCard(p)}
	}
	out^ = game
	return true
}
