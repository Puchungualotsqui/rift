package rift_client

import k2 "../karl2d"
import logic "../logicEngine"
import "core:fmt"
import "core:math"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 800
PIXEL_GRID :: 4

COLOR_BACKGROUND :: k2.Color{43, 37, 29, 255}
COLOR_FRAME :: k2.Color{53, 45, 34, 255}
COLOR_PANEL :: k2.Color{83, 71, 53, 255}
COLOR_PANEL_INNER :: k2.Color{70, 60, 46, 255}
COLOR_TABLE :: k2.Color{100, 88, 66, 255}
COLOR_TEXT :: k2.Color{234, 223, 194, 255}
COLOR_TEXT_DARK :: k2.Color{49, 41, 31, 255}
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
COLOR_BUTTON :: k2.Color{91, 77, 57, 255}
COLOR_BUTTON_ACTIVE :: k2.Color{178, 143, 82, 255}
COLOR_CARD :: k2.Color{92, 79, 58, 255}
COLOR_CARD_EDGE :: k2.Color{57, 49, 38, 255}

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
previewGame: logic.Game
previewPlayerCount: int = 2
hoveredCell: int = -1
selectedCell: int = -1
contextCell: int = -1
playerMenuOpen: bool

init :: proc() {
	k2.init(WINDOW_WIDTH, WINDOW_HEIGHT, "RIFT | Tactical Conflict", options = {window_mode = .Windowed_Resizable})
	pixelMarksTexture, pixelMarksLoaded = LoadPixelMarks()
	if pixelMarksLoaded {
		k2.set_texture_sampler(pixelMarksTexture, k2.Texture_Sampler{scale_up_filter = .Point, scale_down_filter = .Point})
	}
	previewGame, _ = CreatePreviewGame(previewPlayerCount)
}

step :: proc() -> bool {
	if !k2.update() do return false

	screenSize := k2.get_screen_size()
	boardPanel := BoardPanelRect(screenSize)
	boardCenter := PixelSnapVec({boardPanel.x + boardPanel.w * 0.5, boardPanel.y + boardPanel.h * 0.5})
	boardRadius := PixelSnap(min(96, min((boardPanel.w - 80) / 7.1, (boardPanel.h - 56) / 6.2)))
	mouse := k2.get_mouse_position()
	hoveredCell = HitTestBoard(mouse, boardCenter, boardRadius)
	if hoveredCell >= 0 {
		contextCell = hoveredCell
	} else if selectedCell >= 0 {
		contextCell = selectedCell
	} else if !playerMenuOpen && !k2.point_in_rect(mouse, SidebarContextRect(SidePanelRect(screenSize, contextCell, playerMenuOpen))) {
		contextCell = -1
	}

	if k2.mouse_button_went_down(.Left) {
		clickHandled := false
		if playerMenuOpen {
			for playerCount in 2..=4 {
				if k2.point_in_rect(mouse, PlayerCountOptionRect(screenSize, playerCount)) {
					previewPlayerCount = playerCount
					previewGame, _ = CreatePreviewGame(previewPlayerCount)
					selectedCell = -1
					contextCell = -1
					playerMenuOpen = false
					clickHandled = true
					break
				}
			}
		}
		if !clickHandled && k2.point_in_rect(mouse, PlayerCountButtonRect(screenSize)) {
			playerMenuOpen = !playerMenuOpen
			clickHandled = true
		} else if !clickHandled && playerMenuOpen {
			playerMenuOpen = false
		}
		if !clickHandled {
			if hoveredCell >= 0 {
				if selectedCell == hoveredCell {
					selectedCell = -1
				} else {
					selectedCell = hoveredCell
				}
				contextCell = hoveredCell
			} else if !k2.point_in_rect(mouse, SidebarContextRect(SidePanelRect(screenSize, contextCell, playerMenuOpen))) {
				selectedCell = -1
				contextCell = -1
			}
		}
	}

	k2.clear(COLOR_BACKGROUND)
	DrawHeader(screenSize)
	DrawBoardPanel(boardPanel)
	DrawBoard(boardCenter, boardRadius)
	DrawSidebar(screenSize, mouse)

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
	DrawPixelRect(rect.x + 8, rect.y + 8, rect.w - 16, rect.h - 16, fillColor)
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

DrawHeader :: proc(screenSize: k2.Vec2) {
	header := k2.Rect{24, 16, screenSize.x - 48, 64}
	DrawCard(header, COLOR_PANEL, COLOR_FRAME)
	DrawText("RIFT", {48, 27}, 34, COLOR_TEXT)
	DrawText("TACTICAL CONFLICT", {152, 39}, 16, COLOR_MUTED)
	DrawText("LOCAL PREVIEW", {screenSize.x - 200, 39}, 16, COLOR_TEXT)
}

BoardPanelRect :: proc(screenSize: k2.Vec2) -> k2.Rect {
	return {24, 96, screenSize.x - 388, screenSize.y - 168}
}

DrawBoardPanel :: proc(panel: k2.Rect) {
	DrawCard(panel, COLOR_TABLE, COLOR_FRAME)
	DrawText("BATTLE MAP", {panel.x + 24, panel.y + 16}, 18, COLOR_TEXT)
	DrawText("19 HEXES", {panel.x + panel.w - 112, panel.y + 19}, 14, COLOR_MUTED)
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

DrawSidebar :: proc(screenSize, mouse: k2.Vec2) {
	panel := SidePanelRect(screenSize, contextCell, playerMenuOpen)
	DrawCard(panel, COLOR_PANEL, COLOR_FRAME)
	panelX, panelY := panel.x, panel.y
	DrawText("MATCH", {panelX + 24, panelY + 20}, 22, COLOR_TEXT)
	DrawPlayerMenuButton(screenSize, mouse)

	if playerMenuOpen {
		DrawPlayerMenu(screenSize, mouse)
		return
	}

	DrawDivider(panelX + 24, panelY + 68, panel.w - 48)
	DrawMatchStatus(panelX, panelY)
	if contextCell >= 0 {
		DrawDivider(panelX + 24, panelY + 278, panel.w - 48)
		DrawCellContext(panelX, panelY, contextCell)
	}
}

SidePanelRect :: proc(screenSize: k2.Vec2, cellIndex: int, menuOpen: bool) -> k2.Rect {
	height := f32(286)
	if menuOpen {
		height = 268
	} else if cellIndex >= 0 {
		height = 456 + f32(ContextPresenceCount(cellIndex)) * 24
	}
	height = min(height, screenSize.y - 120)
	return {screenSize.x - 344, 96, 320, height}
}

SidebarContextRect :: proc(panel: k2.Rect) -> k2.Rect {
	return {panel.x + 8, panel.y + 278, panel.w - 16, panel.h - 286}
}

PlayerCountButtonRect :: proc(screenSize: k2.Vec2) -> k2.Rect {
	panelX := screenSize.x - 344
	return {panelX + 152, 112, 144, 40}
}

PlayerCountOptionRect :: proc(screenSize: k2.Vec2, playerCount: int) -> k2.Rect {
	panelX := screenSize.x - 344
	return {panelX + 24, 196 + f32(playerCount - 2) * 44, 272, 40}
}

DrawPlayerMenuButton :: proc(screenSize, mouse: k2.Vec2) {
	rect := PlayerCountButtonRect(screenSize)
	isHovered := k2.point_in_rect(mouse, rect)
	fill := COLOR_BUTTON
	textColor := COLOR_TEXT
	if isHovered {
		fill = COLOR_BUTTON_ACTIVE
		textColor = COLOR_TEXT_DARK
	}
	DrawPixelRect(rect.x, rect.y, rect.w, rect.h, COLOR_CARD_EDGE)
	DrawPixelRect(rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, fill)
	DrawText(fmt.tprintf("%d Players", previewPlayerCount), {rect.x + 12, rect.y + 12}, 14, textColor)
	arrowX := rect.x + rect.w - 18
	arrowY := rect.y + rect.h * 0.5
	k2.draw_triangle([3]k2.Vec2{{arrowX - 6, arrowY - 3}, {arrowX + 6, arrowY - 3}, {arrowX, arrowY + 5}}, textColor)
}

DrawPlayerMenu :: proc(screenSize, mouse: k2.Vec2) {
	panelX := screenSize.x - 344
	DrawText("PLAYER COUNT", {panelX + 24, 172}, 14, COLOR_MUTED)
	for playerCount in 2..=4 {
		rect := PlayerCountOptionRect(screenSize, playerCount)
		fill := COLOR_BUTTON
		textColor := COLOR_TEXT
		if playerCount == previewPlayerCount {
			fill = COLOR_BUTTON_ACTIVE
			textColor = COLOR_TEXT_DARK
		} else if k2.point_in_rect(mouse, rect) {
			fill = COLOR_HOVERED
			textColor = COLOR_TEXT_DARK
		}
		DrawPixelRect(rect.x, rect.y, rect.w, rect.h, COLOR_CARD_EDGE)
		DrawPixelRect(rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, fill)
		DrawText(fmt.tprintf("%d Players", playerCount), {rect.x + 16, rect.y + 10}, 15, textColor)
	}
}

DrawMatchStatus :: proc(panelX, panelY: f32) {
	DrawText("ROUND", {panelX + 24, panelY + 88}, 14, COLOR_MUTED)
	DrawText(fmt.tprintf("%02d / %02d", previewGame.round, logic.ROUND_COUNT), {panelX + 24, panelY + 108}, 28, COLOR_TEXT)
	DrawText("ACTIVE PLAYER", {panelX + 154, panelY + 88}, 14, COLOR_MUTED)
	currentPlayer := previewGame.currentPlayer
	if currentPlayer < 0 || currentPlayer >= previewGame.playerCount do return

	faction := previewGame.players[currentPlayer].faction
	DrawMark(FactionMark(faction), {panelX + 168, panelY + 145}, 32)
	DrawText(FactionName(faction), {panelX + 194, panelY + 137}, 15, COLOR_TEXT)
	resources := previewGame.players[currentPlayer].resources
	cardY := panelY + 184
	DrawResourceCard({panelX + 24, cardY, 80, 60}, "ENERGY", resources.energy, COLOR_BRASS)
	DrawResourceCard({panelX + 112, cardY, 80, 60}, "DATA", resources.data, k2.Color{104, 130, 120, 255})
	DrawResourceCard({panelX + 200, cardY, 80, 60}, "ACTIONS", previewGame.players[currentPlayer].ap, COLOR_TEXT)
}

DrawResourceCard :: proc(rect: k2.Rect, label: string, value: int, accent: k2.Color) {
	DrawPixelRect(rect.x, rect.y, rect.w, rect.h, COLOR_CARD_EDGE)
	DrawPixelRect(rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, COLOR_CARD)
	DrawText(label, {rect.x + 8, rect.y + 7}, 12, accent)
	DrawText(fmt.tprintf("%d", value), {rect.x + 8, rect.y + 24}, 24, COLOR_TEXT)
}

DrawCellContext :: proc(panelX, panelY: f32, cellIndex: int) {
	cell := previewGame.board[cellIndex]
	DrawText("HEX DETAILS", {panelX + 24, panelY + 294}, 14, COLOR_MUTED)
	if selectedCell == cellIndex {
		DrawText("PINNED", {panelX + 232, panelY + 294}, 11, COLOR_BRASS)
	} else {
		DrawText("HOVER", {panelX + 232, panelY + 294}, 11, COLOR_MUTED)
	}

	if cell.rift {
		DrawMark(MARK_RIFT, {panelX + 44, panelY + 348}, 36)
		DrawText("Rift", {panelX + 76, panelY + 330}, 18, COLOR_TEXT)
	} else {
		mark := TerrainMark(cell.terrain)
		if mark >= 0 {
			DrawMark(mark, {panelX + 44, panelY + 348}, 36)
		} else {
			DrawPixelRect(panelX + 28, panelY + 332, 32, 32, COLOR_OPEN)
		}
		DrawText(TerrainName(cell.terrain), {panelX + 76, panelY + 330}, 18, COLOR_TEXT)
	}
	DrawText(fmt.tprintf("Q %d    R %d", cell.pos.q, cell.pos.r), {panelX + 76, panelY + 356}, 14, COLOR_TEXT)
	DrawDivider(panelX + 24, panelY + 388, 272)
	DrawText("PRESENCE", {panelX + 24, panelY + 402}, 12, COLOR_MUTED)

	rowY := panelY + 426
	rowCount := 0
	for playerIndex in 0..<previewGame.playerCount {
		units := cell.units[playerIndex]
		if units <= 0 do continue
		faction := previewGame.players[playerIndex].faction
		unitLabel := "units"
		if units == 1 do unitLabel = "unit"
		DrawMark(FactionMark(faction), {panelX + 36, rowY + 11}, 20)
		DrawText(fmt.tprintf("%s  %d %s", FactionName(faction), units, unitLabel), {panelX + 54, rowY + 2}, 13, COLOR_TEXT)
		rowY += 24
		rowCount += 1
	}
	for playerIndex in 0..<previewGame.playerCount {
		faction := previewGame.players[playerIndex].faction
		if cell.structures[playerIndex] {
			DrawMark(MARK_STRUCTURE, {panelX + 36, rowY + 11}, 20)
			DrawText(fmt.tprintf("%s structure", FactionName(faction)), {panelX + 54, rowY + 2}, 13, COLOR_TEXT)
			rowY += 24
			rowCount += 1
		}
		if cell.relay == playerIndex {
			DrawMark(MARK_RELAY, {panelX + 36, rowY + 11}, 20)
			DrawText(fmt.tprintf("%s relay", FactionName(faction)), {panelX + 54, rowY + 2}, 13, COLOR_TEXT)
			rowY += 24
			rowCount += 1
		}
	}
	if rowCount == 0 do DrawText("No forces or structures", {panelX + 24, rowY + 2}, 13, COLOR_TEXT)
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
