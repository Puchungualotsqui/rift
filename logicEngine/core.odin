package logicEngine

// Axial coordinates on a radius-two hexagon. Player indices are clockwise.
BOARD_RADIUS :: 2
HEX_COUNT :: 19
MAX_PLAYERS :: 4
ROUND_COUNT :: 6
RESOURCE_CAP :: 8
HAND_LIMIT :: 5
UNIT_CAP :: 3
NO_PLAYER :: -1

Hex :: struct {
	q, r: int,
}

Faction :: enum {
	Swarm,
	Corp,
	AI,
	Nomad,
}

Terrain :: enum {
	Open,
	Cover,
	Energy_Node,
	Data_Node,
}

Resources :: struct {
	energy, data: int,
}

Cell :: struct {
	pos:        Hex,
	terrain:    Terrain,
	rift:       bool,
	units:        [MAX_PLAYERS]int,
	boostedUnits: [MAX_PLAYERS]int,
	structures:   [MAX_PLAYERS]bool,
	fortified:    [MAX_PLAYERS]bool,
	shielded:     [MAX_PLAYERS]bool,
	relay:        int, // Player index, or NO_PLAYER.
}

// Card IDs are zero-based indices into the owning faction's deck definition.
// Deck order is stored bottom to top; the next draw is at deckCount - 1.
Player :: struct {
	faction:          Faction,
	resources:        Resources,
	ap:               int,
	deck:             [14]int,
	deckCount:       int,
	hand:             [HAND_LIMIT]int,
	handCount:       int,
	discard:          [14]int,
	discardCount:    int,
	directives:       [3]int,
	directiveCount:  int,
	publicVp:        int,
	combatWins:      int,
	roundCombatWins: int,
	unitsDestroyed:  int,
	tokensDestroyed: int,
	structuresDestroyed: int,
	resourcesStolen: int,
	cardsPlayed:     int,
	objectivesScored: int,
	automate, relayShield, pulse, warpath, struckThisTurn: bool,
}

Phase :: enum {
	Await_Turn,
	Acting,
	Protocol_Choice,
	Score_Objective,
	Finished,
}

Game :: struct {
	board:         [HEX_COUNT]Cell,
	players:       [MAX_PLAYERS]Player,
	playerCount:  int,
	round:         int,
	firstPlayer:  int,
	currentPlayer: int,
	turnsTaken:   int,
	relayDestroyedThisTurn: bool,
	randomState: u64,
	pendingProtocol: PendingProtocol,
	phase:         Phase,
}

HexDistance :: proc(a, b: Hex) -> int {
	dq := a.q - b.q
	dr := a.r - b.r
	return (abs(dq) + abs(dr) + abs(dq + dr)) / 2
}

HexValid :: proc(pos: Hex) -> bool {
	return HexDistance(pos, Hex{}) <= BOARD_RADIUS
}

HexAdjacent :: proc(a, b: Hex) -> bool {
	return HexDistance(a, b) == 1
}

CellIndex :: proc(game: ^Game, pos: Hex) -> int {
	for i in 0..<HEX_COUNT {
		if game.board[i].pos == pos do return i
	}
	return -1
}

// Relays grant their owner control independently of enemy pieces, without
// preventing other players from controlling the same hex.
Controls :: proc(game: ^Game, player: int, pos: Hex) -> bool {
	if player < 0 || player >= game.playerCount do return false
	i := CellIndex(game, pos)
	if i < 0 || game.board[i].rift do return false
	cell := &game.board[i]
	if cell.relay == player && game.players[player].faction == .AI do return true
	if cell.units[player] == 0 && !cell.structures[player] do return false
	for enemy in 0..<game.playerCount {
		if enemy != player && (cell.units[enemy] > 0 || cell.structures[enemy]) do return false
	}
	return true
}

UnitCount :: proc(cell: ^Cell) -> int {
	count := 0
	for n in cell.units {count += n}
	return count
}

HasStructure :: proc(cell: ^Cell) -> bool {
	for present in cell.structures {
		if present do return true
	}
	return false
}
