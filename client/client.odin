package rift_client

import k2 "../karl2d"
import logic "../logicEngine"
import "core:fmt"
import "core:math"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 800
PIXEL_GRID :: 4

COLOR_TABLE :: k2.Color{100, 88, 66, 255}
COLOR_FRAME :: k2.Color{53, 45, 34, 255}
COLOR_PANEL :: k2.Color{83, 71, 53, 255}
COLOR_TEXT :: k2.Color{234, 223, 194, 255}
COLOR_MUTED :: k2.Color{190, 176, 145, 255}
COLOR_BRASS :: k2.Color{180, 144, 82, 255}
COLOR_SELECTED :: k2.Color{207, 174, 110, 255}
COLOR_HOVERED :: k2.Color{194, 179, 143, 255}
COLOR_TILE_EDGE :: k2.Color{55, 47, 37, 255}
COLOR_TILE_SHADOW :: k2.Color{43, 37, 30, 255}
COLOR_OPEN :: k2.Color{157, 141, 108, 255}
COLOR_COVER :: k2.Color{126, 114, 88, 255}
COLOR_ENERGY :: k2.Color{150, 123, 78, 255}
COLOR_DATA :: k2.Color{105, 127, 113, 255}
COLOR_RIFT :: k2.Color{73, 61, 64, 255}

MARK_COVER :: 0
MARK_ENERGY :: 1
MARK_DATA :: 2
MARK_RIFT :: 3
MARK_SWARM :: 4
MARK_CORP :: 5
MARK_AI :: 6
MARK_NOMAD :: 7
MARK_STRUCTURE :: 8
MARK_RELAY :: 9
MARK_SIZE :: 24

pixelMarksTexture: k2.Texture
pixelMarksLoaded: bool
PREVIEW_PLAYER_COUNT :: 2

previewGame: logic.Game
hoveredCell: int = -1
selectedCell: int = -1
contextCell: int = -1

init :: proc() {
	k2.init(WINDOW_WIDTH, WINDOW_HEIGHT, "RIFT", options = {window_mode = .Windowed_Resizable})
	pixelMarksTexture, pixelMarksLoaded = LoadPixelMarks()
	if pixelMarksLoaded {
		k2.set_texture_sampler(pixelMarksTexture, k2.Texture_Sampler{scale_up_filter = .Point, scale_down_filter = .Point})
	}
	previewGame, _ = CreatePreviewGame(PREVIEW_PLAYER_COUNT)
}

step :: proc() -> bool {
	if !k2.update() do return false

	screenSize := k2.get_screen_size()
	boardCenter := PixelSnapVec({screenSize.x * 0.5, screenSize.y * 0.5})
	boardRadius := max(32, PixelSnap(min(124, min((screenSize.x - 80) / 8.9, (screenSize.y - 80) / 8.0))))
	mouse := k2.get_mouse_position()
	hudRect := MatchHudRect(screenSize)
	mouseInHud := k2.point_in_rect(mouse, hudRect)
	previousContextRect := k2.Rect{}
	mouseInContext := false
	if contextCell >= 0 {
		previousContextRect = ContextOverlayRect(screenSize, boardCenter, boardRadius, contextCell)
		mouseInContext = k2.point_in_rect(mouse, previousContextRect)
	}

	hoveredCell = -1
	if !mouseInHud && !mouseInContext {
		hoveredCell = HitTestBoard(mouse, boardCenter, boardRadius)
	}
	if hoveredCell >= 0 {
		contextCell = hoveredCell
	} else if !mouseInContext {
		contextCell = selectedCell
	}

	if k2.mouse_button_went_down(.Left) && !mouseInHud && !mouseInContext {
		if hoveredCell >= 0 {
			if selectedCell == hoveredCell {
				selectedCell = -1
			} else {
				selectedCell = hoveredCell
			}
			contextCell = hoveredCell
		} else {
			selectedCell = -1
			contextCell = -1
		}
	}

	contextRect := k2.Rect{}
	if contextCell >= 0 {
		contextRect = ContextOverlayRect(screenSize, boardCenter, boardRadius, contextCell)
	}

	k2.clear(COLOR_TABLE)
	DrawBoard(boardCenter, boardRadius)
	if contextCell >= 0 do DrawCellContext(contextRect, contextCell)
	DrawMatchHud(screenSize)

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	if pixelMarksLoaded do k2.destroy_texture(pixelMarksTexture)
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}

CreatePreviewGame :: proc(playerCount: int) -> (game: logic.Game, ok: bool) {
	if playerCount < 2 || playerCount > logic.MAX_PLAYERS do return
	config := logic.SetupConfig{playerCount = playerCount}
	factions := [?]logic.Faction{.Swarm, .Corp, .AI, .Nomad}
	startHexes := logic.START_HEXES
	for playerIndex in 0..<playerCount {
		startIndex := playerIndex
		if playerCount == 2 && playerIndex == 1 do startIndex = 2
		config.players[playerIndex].faction = factions[playerIndex]
		config.players[playerIndex].start = startHexes[startIndex]
	}
	if !logic.PrepareShuffledSetup(&config, 0x52494654) do return
	if !logic.SetupGame(&game, config) || !logic.BeginTurn(&game) do return {}, false
	return game, true
}

PixelSnap :: proc(value: f32) -> f32 {
	steps := 0
	if value >= 0 {
		steps = int(value / PIXEL_GRID + 0.5)
	} else {
		steps = int(value / PIXEL_GRID - 0.5)
	}
	return f32(steps * PIXEL_GRID)
}

PixelSnapVec :: proc(value: k2.Vec2) -> k2.Vec2 {
	return {PixelSnap(value.x), PixelSnap(value.y)}
}

DrawText :: proc(text: string, position: k2.Vec2, size: f32, color: k2.Color) {
	k2.draw_text(text, PixelSnapVec(position), size, color)
}

DrawPixelRect :: proc(x, y, width, height: f32, color: k2.Color) {
	rect := k2.Rect{
		PixelSnap(x),
		PixelSnap(y),
		max(f32(PIXEL_GRID), PixelSnap(width)),
		max(f32(PIXEL_GRID), PixelSnap(height)),
	}
	k2.draw_rect(rect, color)
}

DrawCard :: proc(rect: k2.Rect, fillColor, edgeColor: k2.Color) {
	DrawPixelRect(rect.x, rect.y, rect.w, rect.h, edgeColor)
	DrawPixelRect(rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, fillColor)
}

DrawDivider :: proc(x, y, width: f32) {
	DrawPixelRect(x, y, width, 6, COLOR_FRAME)
}

DrawMark :: proc(mark: int, center: k2.Vec2, size: f32) {
	if !pixelMarksLoaded do return
	source := k2.Rect{f32(mark * MARK_SIZE), 0, MARK_SIZE, MARK_SIZE}
	destSize := PixelSnap(size)
	dest := k2.Rect{
		PixelSnap(center.x - destSize * 0.5),
		PixelSnap(center.y - destSize * 0.5),
		destSize,
		destSize,
	}
	k2.draw_texture_fit(pixelMarksTexture, source, dest)
}

MatchHudRect :: proc(screenSize: k2.Vec2) -> k2.Rect {
	return {24, 24, min(320, screenSize.x - 48), 68}
}

DrawMatchHud :: proc(screenSize: k2.Vec2) {
	currentPlayer := previewGame.currentPlayer
	if currentPlayer < 0 || currentPlayer >= previewGame.playerCount do return

	rect := MatchHudRect(screenSize)
	DrawCard(rect, COLOR_PANEL, COLOR_FRAME)
	player := previewGame.players[currentPlayer]
	DrawMark(FactionMark(player.faction), {rect.x + 32, rect.y + 34}, 28)
	DrawText(FactionName(player.faction), {rect.x + 54, rect.y + 14}, 15, COLOR_TEXT)
	DrawText(fmt.tprintf("ROUND %02d / %02d", previewGame.round, logic.ROUND_COUNT), {rect.x + 54, rect.y + 40}, 12, COLOR_MUTED)
	DrawPixelRect(rect.x + 154, rect.y + 14, 4, 40, COLOR_FRAME)

	resources := player.resources
	DrawMark(MARK_ENERGY, {rect.x + 180, rect.y + 34}, 20)
	DrawText(fmt.tprintf("%d", resources.energy), {rect.x + 194, rect.y + 26}, 14, COLOR_TEXT)
	DrawMark(MARK_DATA, {rect.x + 230, rect.y + 34}, 20)
	DrawText(fmt.tprintf("%d", resources.data), {rect.x + 244, rect.y + 26}, 14, COLOR_TEXT)
	DrawText(fmt.tprintf("AP %d", player.ap), {rect.x + 276, rect.y + 27}, 13, COLOR_TEXT)
}

DrawBoard :: proc(boardCenter: k2.Vec2, radius: f32) {
	for &cell, index in previewGame.board {
		center := HexScreenPosition(cell.pos, boardCenter, radius)
		DrawHexCell(&cell, center, radius, hoveredCell == index, selectedCell == index)
	}
}

DrawHexCell :: proc(cell: ^logic.Cell, center: k2.Vec2, radius: f32, isHovered, isSelected: bool) {
	fillColor := TerrainColor(cell.terrain)
	edgeColor := COLOR_TILE_EDGE
	if logic.IsStartHex(cell.pos) do edgeColor = COLOR_BRASS
	if isHovered do edgeColor = COLOR_HOVERED
	if isSelected do edgeColor = COLOR_SELECTED
	if cell.rift do fillColor = COLOR_RIFT

	DrawHex(center + {0, 7}, radius, COLOR_TILE_SHADOW)
	DrawHex(center, radius, edgeColor)
	DrawHex(center, radius - 8, fillColor)

	if cell.rift {
		DrawRiftMark(center)
	} else {
		DrawTerrain(cell.terrain, center, radius)
		DrawPieces(cell, center, radius)
	}
}

TerrainColor :: proc(terrain: logic.Terrain) -> k2.Color {
	switch terrain {
	case .Open:        return COLOR_OPEN
	case .Cover:       return COLOR_COVER
	case .Energy_Node: return COLOR_ENERGY
	case .Data_Node:   return COLOR_DATA
	}
	return COLOR_OPEN
}

DrawHex :: proc(center: k2.Vec2, radius: f32, color: k2.Color) {
	for vertex in 0..<6 {
		first := HexVertex(center, radius, vertex)
		second := HexVertex(center, radius, (vertex + 1) % 6)
		k2.draw_triangle([3]k2.Vec2{center, first, second}, color)
	}
}

HexVertex :: proc(center: k2.Vec2, radius: f32, vertex: int) -> k2.Vec2 {
	angle := f32(math.PI) * (f32(vertex) / 3.0 - 0.5)
	point := center + k2.Vec2{f32(math.cos(f64(angle))) * radius, f32(math.sin(f64(angle))) * radius}
	return PixelSnapVec(point)
}

HexScreenPosition :: proc(pos: logic.Hex, boardCenter: k2.Vec2, radius: f32) -> k2.Vec2 {
	rootThree := math.sqrt(f32(3))
	return PixelSnapVec(boardCenter + k2.Vec2{rootThree * radius * (f32(pos.q) + f32(pos.r) * 0.5), 1.5 * radius * f32(pos.r)})
}

DrawTerrain :: proc(terrain: logic.Terrain, center: k2.Vec2, radius: f32) {
	mark := TerrainMark(terrain)
	if mark < 0 do return
	markCenter := center + {0, -radius * 0.36}
	DrawMark(mark, markCenter, 40)
}

DrawRiftMark :: proc(center: k2.Vec2) {
	DrawMark(MARK_RIFT, center + {0, -8}, 48)
}

DrawPieces :: proc(cell: ^logic.Cell, center: k2.Vec2, radius: f32) {
	for playerIndex in 0..<previewGame.playerCount {
		faction := previewGame.players[playerIndex].faction
		units := cell.units[playerIndex]
		for unitIndex in 0..<units {
			x := center.x + f32(unitIndex - (units - 1) / 2) * 24
			DrawMark(FactionMark(faction), {x, center.y + radius * 0.58}, 24)
		}
		if cell.structures[playerIndex] {
			DrawMark(MARK_STRUCTURE, {center.x - radius * 0.18, center.y + 18}, 28)
		}
		if cell.relay == playerIndex {
			DrawMark(MARK_RELAY, {center.x + radius * 0.18, center.y + 18}, 24)
		}
	}
}


ContextOverlayRect :: proc(screenSize: k2.Vec2, boardCenter: k2.Vec2, radius: f32, cellIndex: int) -> k2.Rect {
	cell := previewGame.board[cellIndex]
	center := HexScreenPosition(cell.pos, boardCenter, radius)
	width := min(280, screenSize.x - 24)
	height := 90 + f32(ContextPresenceCount(cellIndex)) * 24
	height = min(height, screenSize.y - 24)
	x := center.x + radius + 14
	if center.x > boardCenter.x do x = center.x - radius - width - 14
	y := center.y - height * 0.5
	x = max(12, min(x, screenSize.x - width - 12))
	y = max(12, min(y, screenSize.y - height - 12))
	return {x, y, width, height}
}

DrawCellContext :: proc(rect: k2.Rect, cellIndex: int) {
	cell := previewGame.board[cellIndex]
	DrawCard(rect, COLOR_PANEL, COLOR_FRAME)
	if cell.rift {
		DrawMark(MARK_RIFT, {rect.x + 32, rect.y + 30}, 28)
		DrawText("Rift", {rect.x + 54, rect.y + 18}, 16, COLOR_TEXT)
	} else {
		mark := TerrainMark(cell.terrain)
		if mark >= 0 {
			DrawMark(mark, {rect.x + 32, rect.y + 30}, 28)
		} else {
			DrawPixelRect(rect.x + 16, rect.y + 14, 32, 32, COLOR_OPEN)
		}
		DrawText(TerrainName(cell.terrain), {rect.x + 54, rect.y + 18}, 16, COLOR_TEXT)
	}
	DrawText(fmt.tprintf("Q %d    R %d", cell.pos.q, cell.pos.r), {rect.x + 54, rect.y + 42}, 12, COLOR_MUTED)
	DrawDivider(rect.x + 16, rect.y + 62, rect.w - 32)

	rowY := rect.y + 74
	rowCount := 0
	for playerIndex in 0..<previewGame.playerCount {
		units := cell.units[playerIndex]
		if units <= 0 do continue
		faction := previewGame.players[playerIndex].faction
		unitLabel := "units"
		if units == 1 do unitLabel = "unit"
		DrawMark(FactionMark(faction), {rect.x + 28, rowY + 10}, 18)
		DrawText(fmt.tprintf("%s  %d %s", FactionName(faction), units, unitLabel), {rect.x + 44, rowY + 2}, 13, COLOR_TEXT)
		rowY += 24
		rowCount += 1
	}
	for playerIndex in 0..<previewGame.playerCount {
		faction := previewGame.players[playerIndex].faction
		if cell.structures[playerIndex] {
			DrawMark(MARK_STRUCTURE, {rect.x + 28, rowY + 10}, 18)
			DrawText(fmt.tprintf("%s structure", FactionName(faction)), {rect.x + 44, rowY + 2}, 13, COLOR_TEXT)
			rowY += 24
			rowCount += 1
		}
		if cell.relay == playerIndex {
			DrawMark(MARK_RELAY, {rect.x + 28, rowY + 10}, 18)
			DrawText(fmt.tprintf("%s relay", FactionName(faction)), {rect.x + 44, rowY + 2}, 13, COLOR_TEXT)
			rowY += 24
			rowCount += 1
		}
	}
	if rowCount == 0 do DrawText("Unoccupied", {rect.x + 16, rowY + 2}, 13, COLOR_TEXT)
}

ContextPresenceCount :: proc(cellIndex: int) -> int {
	if cellIndex < 0 || cellIndex >= logic.HEX_COUNT do return 1
	cell := previewGame.board[cellIndex]
	count := 0
	for playerIndex in 0..<previewGame.playerCount {
		if cell.units[playerIndex] > 0 do count += 1
		if cell.structures[playerIndex] do count += 1
		if cell.relay == playerIndex do count += 1
	}
	return max(1, count)
}

HitTestBoard :: proc(mouse, boardCenter: k2.Vec2, radius: f32) -> int {
	nearest := -1
	nearestDistance := radius * radius
	for cell, index in previewGame.board {
		center := HexScreenPosition(cell.pos, boardCenter, radius)
		delta := mouse - center
		distance := delta.x * delta.x + delta.y * delta.y
		if distance < nearestDistance {
			nearest = index
			nearestDistance = distance
		}
	}
	return nearest
}

TerrainMark :: proc(terrain: logic.Terrain) -> int {
	switch terrain {
	case .Open:        return -1
	case .Cover:       return MARK_COVER
	case .Energy_Node: return MARK_ENERGY
	case .Data_Node:   return MARK_DATA
	}
	return -1
}

TerrainName :: proc(terrain: logic.Terrain) -> string {
	switch terrain {
	case .Open:        return "Open ground"
	case .Cover:       return "Cover"
	case .Energy_Node: return "Energy node"
	case .Data_Node:   return "Data node"
	}
	return "Unknown terrain"
}


FactionMark :: proc(faction: logic.Faction) -> int {
	switch faction {
	case .Swarm: return MARK_SWARM
	case .Corp:  return MARK_CORP
	case .AI:    return MARK_AI
	case .Nomad: return MARK_NOMAD
	}
	return MARK_SWARM
}

FactionName :: proc(faction: logic.Faction) -> string {
	switch faction {
	case .Swarm: return "Chorus"
	case .Corp:  return "Helix"
	case .AI:    return "Lattice"
	case .Nomad: return "Drift"
	}
	return "Unknown"
}
