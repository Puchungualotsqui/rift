package logicEngine

ShuffleOrder :: proc(game: ^Game, values: []int) {
	for i in 0..<len(values) do values[i] = i
	for i := len(values) - 1; i > 0; i -= 1 {
		j := RandomIndex(game, i + 1)
		values[i], values[j] = values[j], values[i]
	}
}

// Fill setup orders and select the first player from a reproducible seed.
PrepareShuffledSetup :: proc(config: ^SetupConfig, seed: u64) -> bool {
	if config == nil || config.playerCount < 2 || config.playerCount > MAX_PLAYERS do return false
	copy := config^
	for i in 0..<copy.playerCount {
		if FactionDeckSize(copy.players[i].faction) == 0 do return false
		for j in 0..<i do if copy.players[j].faction == copy.players[i].faction do return false
	}
	random: Game
	random.randomState = seed
	ShuffleOrder(&random, copy.terrainOrder[:])
	ShuffleOrder(&random, copy.directiveOrder[:])
	for i in 0..<copy.playerCount {
		copy.players[i].deck = {}
		size := FactionDeckSize(copy.players[i].faction)
		ShuffleOrder(&random, copy.players[i].deck[:size])
	}
	copy.firstPlayer = RandomIndex(&random, copy.playerCount)
	copy.randomSeed = random.randomState
	config^ = copy
	return true
}
