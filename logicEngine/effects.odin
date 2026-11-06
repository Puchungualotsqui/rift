package logicEngine

ResourceKind :: enum {
	Energy,
	Data,
}

TokenKind :: enum {
	Structure,
	Relay,
}

ProtocolChoice :: struct {
	from, to: Hex,
	other: int,
	resource: ResourceKind,
	terrain: Terrain,
	target: TokenKind,
	cardIndex: int,
	option: bool,
}

// Resolve the entire protocol on a copy; invalid effects spend nothing.
PlayProtocol :: proc(game: ^Game, handIndex: int, choice: ProtocolChoice) -> bool {
	if game == nil || game.playerCount < 2 || game.playerCount > MAX_PLAYERS || game.currentPlayer < 0 || game.currentPlayer >= game.playerCount || game.phase != .Acting do return false
	copy := game^
	player := &copy.players[copy.currentPlayer]
	if !ValidateCard(player, handIndex, .Protocol) do return false
	id := player.hand[handIndex]
	if IsInformationalProtocol(player.faction, id) do return false
	if !DiscardAndPayCard(player, handIndex, .Protocol) do return false
	ok := false
	switch player.faction {
	case .Swarm: ok = ApplySwarmProtocol(&copy, id, choice)
	case .Corp: ok = ApplyCorpProtocol(&copy, id, choice)
	case .AI: ok = ApplyAiProtocol(&copy, id, choice)
	case .Nomad: ok = ApplyNomadProtocol(&copy, id, choice)
	case: return false
	}
	if !ok do return false
	game^ = copy
	return true
}

// A shield prevents one destruction attempt, including card effects.
DestroyStructure :: proc(game: ^Game, pos: Hex, owner, actor: int) -> bool {
	if owner < 0 || owner >= game.playerCount do return false
	i := CellIndex(game, pos)
	if i < 0 || game.board[i].rift || !game.board[i].structures[owner] do return false
	cell := &game.board[i]
	if cell.shielded[owner] {
		cell.shielded[owner] = false
		return false
	}
	cell.structures[owner] = false
	cell.fortified[owner] = false
	if actor >= 0 && actor < game.playerCount && actor != owner {
		game.players[actor].structuresDestroyed += 1
		game.players[actor].tokensDestroyed += 1
	}
	return true
}

DestroyRelayToken :: proc(game: ^Game, pos: Hex, actor: int) -> bool {
	i := CellIndex(game, pos)
	if i < 0 || game.board[i].rift do return false
	cell := &game.board[i]
	owner := cell.relay
	if owner < 0 || owner >= game.playerCount do return false
	cell.relay = NO_PLAYER
	if actor >= 0 && actor < game.playerCount && actor != owner do game.players[actor].tokensDestroyed += 1
	return true
}

TransferResource :: proc(game: ^Game, from, to: int, resource: ResourceKind, amount: int) -> bool {
	if from < 0 || from >= game.playerCount || to < 0 || to >= game.playerCount || from == to || amount < 1 do return false
	source, target: ^int
	switch resource {
	case .Energy:
		source, target = &game.players[from].resources.energy, &game.players[to].resources.energy
	case .Data:
		source, target = &game.players[from].resources.data, &game.players[to].resources.data
	case: return false
	}
	if source^ < amount || target^ + amount > RESOURCE_CAP do return false
	source^ -= amount
	target^ += amount
	game.players[to].resourcesStolen += amount
	return true
}

// Move a unit without paying AP, carrying a boosted unit first.
MoveUnitEffect :: proc(game: ^Game, player: int, from, to: Hex, allowEnemyStructure: bool) -> bool {
	if player < 0 || player >= game.playerCount || !HexAdjacent(from, to) do return false
	si, ti := CellIndex(game, from), CellIndex(game, to)
	if si < 0 || ti < 0 do return false
	source, target := &game.board[si], &game.board[ti]
	if source.rift || target.rift || source.units[player] < 1 || UnitCount(target) >= UNIT_CAP do return false
	for enemy in 0..<game.playerCount {
		if enemy == player do continue
		if target.units[enemy] > 0 || (!allowEnemyStructure && target.structures[enemy]) do return false
	}
	source.units[player] -= 1
	target.units[player] += 1
	if source.boostedUnits[player] > 0 {
		source.boostedUnits[player] -= 1
		target.boostedUnits[player] += 1
	}
	return true
}

DiscardCard :: proc(player: ^Player, index: int) -> bool {
	if player == nil || player.handCount < 0 || player.handCount > len(player.hand) || index < 0 || index >= player.handCount || player.discardCount < 0 || player.discardCount >= len(player.discard) do return false
	player.discard[player.discardCount] = player.hand[index]
	player.discardCount += 1
	for i in index..<player.handCount - 1 do player.hand[i] = player.hand[i + 1]
	player.handCount -= 1
	player.hand[player.handCount] = 0
	return true
}

// Rejection sampling keeps bounded results uniform and reproducible.
RandomIndex :: proc(game: ^Game, bound: int) -> int {
	if bound <= 0 do return -1
	if game.randomState == 0 do game.randomState = 0x9e3779b97f4a7c15
	n := u64(bound)
	limit := u64(0xffffffffffffffff) - u64(0xffffffffffffffff) % n
	for {
		x := game.randomState
		x ~= x << 13
		x ~= x >> 7
		x ~= x << 17
		game.randomState = x
		if x <= limit do return int((x - 1) % n)
	}
}
