package server

import "base:runtime"
import logic "../logicEngine"
import ws "../wsServerOdin"
import "core:crypto"
import "core:log"
import "core:sync"
import "core:time"

MAX_LOBBY_PLAYERS :: 256

MatchStatus :: enum {
	Waiting,
	Started,
	Finished,
}

WsClient :: struct {
	server: ^ws.Server,
	id:     ws.ClientID,
}

NO_WS_CLIENT :: WsClient{}

NetworkState :: struct {
	mutex:        sync.Mutex,
	websocket:    ws.Server,
	allocator:    runtime.Allocator,
	shuttingDown: bool,
	authTimeout:  time.Duration,
	connections:  map[WsClient]WsConnection,
	matches:      [dynamic]Match,
	lobby:        [dynamic]LobbyEntry,
	nextMatchId:  i64,
}

WsConnection :: struct {
	openedAt:      time.Tick,
	authenticated: bool,
	authTimedOut:  bool,
	playerId:      i64,
	sessionToken:  string,
	displayName:   string,
	matchId:       i64,
	lastSequence:  i64,
}

LobbyEntry :: struct {
	playerId:    i64,
	displayName: string,
	connection:  WsClient,
}

MatchPlayer :: struct {
	playerId:    i64,
	displayName: string,
	faction:     logic.Faction,
	start:       logic.Hex,
	connection:  WsClient,
	connected:   bool,
	ready:       bool,
}

Match :: struct {
	id:          i64,
	databaseId:  i64,
	seed:        u64,
	maxPlayers:  int,
	playerCount: int,
	status:      MatchStatus,
	players:     [logic.MAX_PLAYERS]MatchPlayer,
	game:        logic.Game,
}

WsClientMessage :: struct {
	op:   string        `json:"op"`,
	seq:  i64           `json:"seq"`,
	data: WsClientData  `json:"data"`,
}

WsClientData :: struct {
	token:             string              `json:"token"`,
	matchId:           i64                 `json:"match_id"`,
	maxPlayers:        int                 `json:"max_players"`,
	ready:             bool                `json:"ready"`,
	round:             int                 `json:"round"`,
	apSpent:           int                 `json:"ap_spent"`,
	action:            string              `json:"action"`,
	from:              WireHex             `json:"from"`,
	via:               WireHex             `json:"via"`,
	to:                WireHex             `json:"to"`,
	count:             int                 `json:"count"`,
	positions:         [2]WireHex          `json:"positions"`,
	positionCount:     int                 `json:"position_count"`,
	handIndex:         int                 `json:"hand_index"`,
	other:             int                 `json:"other"`,
	cardIndex:         int                 `json:"card_index"`,
	resource:          string              `json:"resource"`,
	terrain:           string              `json:"terrain"`,
	target:            string              `json:"target"`,
	option:            bool                `json:"option"`,
	capture:           bool                `json:"capture"`,
	doStrike:          bool                `json:"do_strike"`,
	attackerCard:      int                 `json:"attacker_card"`,
	defenderCard:      int                 `json:"defender_card"`,
	plunder:           string              `json:"plunder"`,
	attackerMoves:     [logic.UNIT_CAP]WireCombatMove `json:"attacker_moves"`,
	defenderMoves:     [logic.UNIT_CAP]WireCombatMove `json:"defender_moves"`,
	attackerMoveCount: int                 `json:"attacker_move_count"`,
	defenderMoveCount: int                 `json:"defender_move_count"`,
	text:              string              `json:"text"`,
}

WireHex :: struct {
	q: int `json:"q"`,
	r: int `json:"r"`,
}

WireCombatMove :: struct {
	from: WireHex `json:"from"`,
	to:   WireHex `json:"to"`,
}

ServerEnvelope :: struct($T: typeid) {
	op:   string `json:"op"`,
	seq:  i64    `json:"seq"`,
	ts:   i64    `json:"ts"`,
	data: T      `json:"data"`,
}

PlayerPublicState :: struct {
	playerId:    i64       `json:"player_id"`,
	displayName: string    `json:"display_name"`,
	faction:     string    `json:"faction"`,
	resources:   Resources `json:"resources"`,
	ap:          int       `json:"ap"`,
	publicVp:    int       `json:"public_vp"`,
	connected:   bool      `json:"connected"`,
}

Resources :: struct {
	energy: int `json:"energy"`,
	data:   int `json:"data"`,
}

CellPublicState :: struct {
	q:            int                 `json:"q"`,
	r:            int                 `json:"r"`,
	terrain:      string              `json:"terrain"`,
	rift:         bool                `json:"rift"`,
	units:        [logic.MAX_PLAYERS]int `json:"units"`,
	boostedUnits: [logic.MAX_PLAYERS]int `json:"boosted_units"`,
	structures:   [logic.MAX_PLAYERS]bool `json:"structures"`,
	fortified:    [logic.MAX_PLAYERS]bool `json:"fortified"`,
	shielded:     [logic.MAX_PLAYERS]bool `json:"shielded"`,
	relayOwner:   i64                 `json:"relay_owner"`,
}

PublicGameState :: struct {
	round:        int                 `json:"round"`,
	turnPlayer:   i64                 `json:"turn_player"`,
	currentPlayer: int                `json:"current_player"`,
	phase:        string              `json:"phase"`,
	players:      []PlayerPublicState `json:"players"`,
	board:        []CellPublicState   `json:"board"`,
}

HiddenGameState :: struct {
	hand:             []int `json:"hand"`,
	secretDirectives: []int `json:"secret_directives"`,
}

LobbyPlayerWire :: struct {
	playerId:    i64    `json:"player_id"`,
	displayName: string `json:"display_name"`,
}

MatchStartWire :: struct {
	matchId:   i64       `json:"match_id"`,
	seed:      u64       `json:"seed"`,
	factions:  []string  `json:"factions"`,
	startHexes: []WireHex `json:"start_hexes"`,
}

MatchStateWire :: struct {
	round:       int             `json:"round"`,
	turnPlayer:  i64             `json:"turn_player"`,
	publicState: PublicGameState `json:"public_state"`,
}

GameHiddenWire :: struct {
	hand:             []int `json:"hand"`,
	secretDirectives: []int `json:"secret_directives"`,
}

ActionAckWire :: struct {
	seq: i64 `json:"seq"`,
}

ActionErrorWire :: struct {
	seq:    i64    `json:"seq"`,
	reason: string `json:"reason"`,
}

GenericErrorWire :: struct {
	code:    string `json:"code"`,
	message: string `json:"message"`,
}

AuthOkWire :: struct {
	playerId:    i64    `json:"player_id"`,
	displayName: string `json:"display_name"`,
}

MatchIdWire :: struct {
	matchId: i64 `json:"match_id"`,
}

ReadyUpdateWire :: struct {
	matchId: i64            `json:"match_id"`,
	players: []ReadyPlayerWire `json:"players"`,
}

ReadyPlayerWire :: struct {
	playerId: i64  `json:"player_id"`,
	ready:    bool `json:"ready"`,
}

GameObservationWire :: struct {
	kind:  string `json:"kind"`,
	owner: i64    `json:"owner"`,
	cards: []int  `json:"cards"`,
}

CombatWire :: struct {
	attackerStrength:  int  `json:"attacker_strength"`,
	defenderStrength:  int  `json:"defender_strength"`,
	attackerWon:       bool `json:"attacker_won"`,
	unitDestroyed:     bool `json:"unit_destroyed"`,
	structureDestroyed: bool `json:"structure_destroyed"`,
	captured:          bool `json:"captured"`,
}

RevealWire :: struct {
	combat:          CombatWire `json:"combat"`,
	attackerCardId:  int        `json:"attacker_card_id"`,
	defenderCardId:  int        `json:"defender_card_id"`,
}

VpBreakdownWire :: struct {
	playerId:            i64 `json:"player_id"`,
	publicVp:            int `json:"public_vp"`,
	factionVp:           int `json:"faction_vp"`,
	directivesCompleted: int `json:"directives_completed"`,
	directiveVp:         int `json:"directive_vp"`,
	totalVp:             int `json:"total_vp"`,
}

MatchEndWire :: struct {
	matchId:      i64               `json:"match_id"`,
	winner:       i64               `json:"winner"`,
	winners:      []i64             `json:"winners"`,
	forfeitBy:    i64               `json:"forfeit_by"`,
	vpBreakdown:  []VpBreakdownWire `json:"vp_breakdown"`,
}

ChatWire :: struct {
	playerId: i64    `json:"player_id"`,
	text:     string `json:"text"`,
}


NetworkInit :: proc(state: ^NetworkState) {
	state.allocator = context.allocator
	state.connections = make(map[WsClient]WsConnection, 16, state.allocator)
	state.matches = make([dynamic]Match, 0, 16, state.allocator)
	state.lobby = make([dynamic]LobbyEntry, 0, MAX_LOBBY_PLAYERS, state.allocator)
	state.authTimeout = WS_AUTH_TIMEOUT
	state.nextMatchId = 1
}

NetworkDeinit :: proc(state: ^NetworkState) {
	for _, connection in state.connections {
		if len(connection.sessionToken) > 0 do delete(connection.sessionToken, state.allocator)
		if len(connection.displayName) > 0 do delete(connection.displayName, state.allocator)
	}
	for matchIndex in 0..<len(state.matches) {
		match := &state.matches[matchIndex]
		for playerIndex in 0..<match.playerCount {
			player := &match.players[playerIndex]
			if len(player.displayName) > 0 do delete(player.displayName, state.allocator)
		}
	}
	for entry in state.lobby {
		if len(entry.displayName) > 0 do delete(entry.displayName, state.allocator)
	}
	delete(state.connections)
	delete(state.matches)
	delete(state.lobby)
	state^ = {}
}

FactionName :: proc(faction: logic.Faction) -> string {
	switch faction {
	case .Swarm: return "swarm"
	case .Corp:  return "corp"
	case .AI:    return "ai"
	case .Nomad: return "nomad"
	}
	return "unknown"
}

TerrainName :: proc(terrain: logic.Terrain) -> string {
	switch terrain {
	case .Open:       return "open"
	case .Cover:      return "cover"
	case .Energy_Node: return "energy_node"
	case .Data_Node:   return "data_node"
	}
	return "unknown"
}

PhaseName :: proc(phase: logic.Phase) -> string {
	switch phase {
	case .Await_Turn:      return "await_turn"
	case .Acting:          return "acting"
	case .Protocol_Choice: return "protocol_choice"
	case .Score_Objective: return "score_objective"
	case .Finished:        return "finished"
	}
	return "unknown"
}

WireHexToLogic :: proc(pos: WireHex) -> logic.Hex {
	return logic.Hex{pos.q, pos.r}
}

WireResource :: proc(value: string) -> (logic.ResourceKind, bool) {
	switch value {
	case "energy": return .Energy, true
	case "data":   return .Data, true
	case:          return {}, false
	}
}

WireTerrain :: proc(value: string) -> (logic.Terrain, bool) {
	switch value {
	case "open":       return .Open, true
	case "cover":      return .Cover, true
	case "energy_node": return .Energy_Node, true
	case "data_node":   return .Data_Node, true
	case:              return {}, false
	}
}

WireTarget :: proc(value: string) -> (logic.TokenKind, bool) {
	switch value {
	case "structure": return .Structure, true
	case "relay":     return .Relay, true
	case:             return {}, false
	}
}

BuildProtocolChoice :: proc(data: WsClientData) -> (logic.ProtocolChoice, bool) {
	choice := logic.ProtocolChoice{
		from = WireHexToLogic(data.from),
		to = WireHexToLogic(data.to),
		other = data.other,
		cardIndex = data.cardIndex,
		option = data.option,
	}
	if data.resource != "" {
		resource, ok := WireResource(data.resource)
		if !ok do return {}, false
		choice.resource = resource
	}
	if data.terrain != "" {
		terrain, ok := WireTerrain(data.terrain)
		if !ok do return {}, false
		choice.terrain = terrain
	}
	if data.target != "" {
		target, ok := WireTarget(data.target)
		if !ok do return {}, false
		choice.target = target
	}
	return choice, true
}

BuildCombatChoice :: proc(data: WsClientData) -> (logic.CombatChoice, bool) {
	choice := logic.CombatChoice{
		attackerCard = data.attackerCard,
		defenderCard = data.defenderCard,
	}
	if data.plunder != "" {
		plunder, ok := WireResource(data.plunder)
		if !ok do return {}, false
		choice.plunder = plunder
	}
	if data.attackerMoveCount < 0 || data.attackerMoveCount > logic.UNIT_CAP ||
		data.defenderMoveCount < 0 || data.defenderMoveCount > logic.UNIT_CAP {
		return {}, false
	}
	choice.attackerMoveCount = data.attackerMoveCount
	choice.defenderMoveCount = data.defenderMoveCount
	for i in 0..<data.attackerMoveCount {
		choice.attackerMoves[i] = logic.CombatMove{
			WireHexToLogic(data.attackerMoves[i].from),
			WireHexToLogic(data.attackerMoves[i].to),
		}
	}
	for i in 0..<data.defenderMoveCount {
		choice.defenderMoves[i] = logic.CombatMove{
			WireHexToLogic(data.defenderMoves[i].from),
			WireHexToLogic(data.defenderMoves[i].to),
		}
	}
	return choice, true
}

ApplyClientGameAction :: proc(game: ^logic.Game, data: WsClientData) -> (ok: bool, combat: logic.CombatResult, hasCombat: bool, observation: logic.ProtocolObservation, hasObservation: bool, reason: string) {
	choice: logic.ProtocolChoice
	combatChoice := logic.CombatChoice{attackerCard = logic.NO_CARD, defenderCard = logic.NO_CARD}
	choiceOk, combatChoiceOk: bool
	switch data.action {
	case "protocol", "protocol_begin", "protocol_finish":
		choice, choiceOk = BuildProtocolChoice(data)
		if !choiceOk {
			reason = "invalid_choice"
			return
		}
	case "strike", "hit_and_run":
		combatChoice, combatChoiceOk = BuildCombatChoice(data)
		if !combatChoiceOk {
			reason = "invalid_combat_choice"
			return
		}
	case:
	}
	from, to, via := WireHexToLogic(data.from), WireHexToLogic(data.to), WireHexToLogic(data.via)
	switch data.action {
	case "move":
		ok = logic.MoveUnits(game, from, to, data.count)
	case "move_via":
		ok = logic.MoveUnitsVia(game, from, via, to, data.count)
	case "harvest":
		ok = logic.Harvest(game, to)
	case "build_unit":
		ok = logic.BuildUnit(game, to)
	case "build_structure":
		ok = logic.BuildStructure(game, to)
	case "proliferate":
		if data.positionCount < 1 || data.positionCount > 2 {
			reason = "invalid_positions"
			return
		}
		positions: [2]logic.Hex
		for i in 0..<data.positionCount do positions[i] = WireHexToLogic(data.positions[i])
		ok = logic.Proliferate(game, positions[:data.positionCount])
	case "reinvest":
		ok = logic.Reinvest(game)
	case "rewire_relay":
		ok = logic.RewireRelay(game, to)
	case "rewire_terrain":
		terrain, validTerrain := WireTerrain(data.terrain)
		if !validTerrain {
			reason = "invalid_terrain"
			return
		}
		ok = logic.RewireTerrain(game, to, terrain)
	case "destroy_relay":
		ok = logic.DestroyRelay(game, to)
	case "protocol":
		ok = logic.PlayProtocol(game, data.handIndex, choice)
	case "protocol_begin":
		observation, ok = logic.BeginInformationalProtocol(game, data.handIndex, data.other)
		hasObservation = ok
	case "protocol_finish":
		ok = logic.FinishInformationalProtocol(game, choice)
	case "strike":
		combat, ok = logic.StrikeWithCards(game, from, to, data.count, data.capture, combatChoice)
		hasCombat = ok
	case "hit_and_run":
		combat, ok = logic.HitAndRunWithCards(game, from, to, data.count, data.doStrike, data.capture, combatChoice)
		hasCombat = ok
	case:
		reason = "unknown_action"
		return
	}
	if !ok && reason == "" do reason = "illegal_action"
	return
}

BuildPublicGameState :: proc(match: ^Match) -> PublicGameState {
	game := &match.game
	players := make([]PlayerPublicState, game.playerCount, context.temp_allocator)
	for i in 0..<game.playerCount {
		player := &game.players[i]
		players[i] = PlayerPublicState{
			playerId = match.players[i].playerId,
			displayName = match.players[i].displayName,
			faction = FactionName(player.faction),
			resources = Resources{player.resources.energy, player.resources.data},
			ap = player.ap,
			publicVp = player.publicVp,
			connected = match.players[i].connected,
		}
	}

	board := make([]CellPublicState, logic.HEX_COUNT, context.temp_allocator)
	for cell, i in game.board {
		relayOwner: i64 = -1
		if cell.relay >= 0 && cell.relay < game.playerCount do relayOwner = match.players[cell.relay].playerId
		board[i] = CellPublicState{
			q = cell.pos.q,
			r = cell.pos.r,
			terrain = TerrainName(cell.terrain),
			rift = cell.rift,
			units = cell.units,
			boostedUnits = cell.boostedUnits,
			structures = cell.structures,
			fortified = cell.fortified,
			shielded = cell.shielded,
			relayOwner = relayOwner,
		}
	}

	turnPlayer: i64
	if game.currentPlayer >= 0 && game.currentPlayer < game.playerCount {
		turnPlayer = match.players[game.currentPlayer].playerId
	}
	return PublicGameState{
		round = game.round,
		turnPlayer = turnPlayer,
		currentPlayer = game.currentPlayer,
		phase = PhaseName(game.phase),
		players = players,
		board = board,
	}
}

BuildMatchStartWire :: proc(match: ^Match) -> MatchStartWire {
	factions := make([]string, match.playerCount, context.temp_allocator)
	startHexes := make([]WireHex, match.playerCount, context.temp_allocator)
	for player, i in match.players[:match.playerCount] {
		factions[i] = FactionName(player.faction)
		startHexes[i] = WireHex{player.start.q, player.start.r}
	}
	return MatchStartWire{match.id, match.seed, factions, startHexes}
}

MakeSeed :: proc() -> u64 {
	seed: u64
	bytes: [size_of(u64)]byte
	crypto.rand_bytes(bytes[:])
	for value, i in bytes do seed |= u64(value) << u64(i * 8)
	if seed == 0 do seed = 1
	return seed
}

StartAuthoritativeMatch :: proc(app: ^App, match: ^Match) -> bool {
	if match.status != .Waiting || match.playerCount != match.maxPlayers do return false
	seed := MakeSeed()
	config: logic.SetupConfig
	config.playerCount = match.playerCount

	factionOrder := [?]logic.Faction{.Swarm, .Corp, .AI, .Nomad}
	random := logic.Game{randomState = seed}
	for i := len(factionOrder) - 1; i > 0; i -= 1 {
		j := logic.RandomIndex(&random, i + 1)
		factionOrder[i], factionOrder[j] = factionOrder[j], factionOrder[i]
	}
	startHexes := logic.START_HEXES
	startOffset := 0
	if match.playerCount == 2 do startOffset = int(seed % 2)
	for i in 0..<match.playerCount {
		startIndex := i
		if match.playerCount == 2 {
			startIndex = startOffset
			if i == 1 do startIndex += 2
		}
		config.players[i].faction = factionOrder[i]
		config.players[i].start = startHexes[startIndex]
		match.players[i].faction = factionOrder[i]
		match.players[i].start = startHexes[startIndex]
	}
	if !logic.PrepareShuffledSetup(&config, seed) do return false
	game: logic.Game
	if !logic.SetupGame(&game, config) || !logic.BeginTurn(&game) do return false

	participants := make([]DatabaseMatchParticipant, match.playerCount, context.temp_allocator)
	for player, i in match.players[:match.playerCount] {
		participants[i] = DatabaseMatchParticipant{player.playerId, FactionName(player.faction)}
	}
	databaseId, persisted := DatabaseStartMatch(app.database, seed, participants)
	if !persisted {
		log.errorf("Could not persist match %d before starting it", match.id)
		return false
	}

	match.seed = seed
	match.databaseId = databaseId
	match.game = game
	match.status = .Started
	return true
}

BuildGameObservationWire :: proc(observation: logic.ProtocolObservation, match: ^Match) -> GameObservationWire {
	cards := make([]int, observation.count, context.temp_allocator)
	for i in 0..<observation.count do cards[i] = observation.cardIds[i]
	owner: i64 = -1
	if observation.owner >= 0 && observation.owner < match.playerCount do owner = match.players[observation.owner].playerId
	kind := "none"
	switch observation.kind {
	case .None:
	case .Hand: kind = "hand"
	case .Deck: kind = "deck"
	}
	return GameObservationWire{kind, owner, cards}
}

