extends Control
## Tactical HUD: fleet roster, selected-ship readout, combat log, action buttons.
## Drawn with CanvasItem primitives; input via native buttons + roster hit test.

signal ship_selected(id: int)
signal end_turn_pressed
signal ability_pressed
signal wait_pressed
signal menu_pressed

const PANEL_X: float = 952.0
const PANEL_W: float = 328.0
const INNER_X: float = 966.0
const INNER_W: float = 300.0

const ROW_TOP: float = 122.0
const ROW_H: float = 29.0
const ROWS: int = 5
## M7B: rows never shrink below this. Before, a big fleet was squeezed to 12 px rows,
## where the name, the class label, the hull bar and the HP numbers were drawn on top of
## each other - the illegible panel in the reference screenshots. A fleet that does not
## fit scrolls instead of collapsing.
const ROW_MIN_H: float = 20.0
## Bottom of the roster band: the DETAIL section starts here at y = 276. It used to be
## 596, which is where the log ends - so a large fleet drew its rows straight through the
## detail panel and the combat log (measured in the M7B screenshots). The band is
## 122..274 and a fleet that does not fit scrolls.
const ROSTER_BOTTOM: float = 274.0

var battle: Battle
var font: Font
var status_text: String = ""
var status_error: bool = false
var ability_armed: bool = false
var hover_ship_id: int = -1
var hover_cell: Vector2i = Vector2i(-1, -1)
var time: float = 0.0
## Index of the first roster row drawn, so a fleet larger than the band can be scrolled.
var roster_scroll: int = 0

var btn_ability: Button
var btn_wait: Button
var btn_end: Button
var btn_menu: Button


func _ready() -> void:
	position = Vector2(PANEL_X, 0)
	size = Vector2(PANEL_W, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	_build_buttons()
	set_process(true)
	queue_redraw()


func _build_buttons() -> void:
	btn_menu = _make_button("MENU", Rect2(248, 12, 66, 24), Color(0.55, 0.72, 0.82), 10)
	btn_menu.pressed.connect(func() -> void: menu_pressed.emit())
	btn_ability = _make_button("ABILITY", Rect2(14, 616, 144, 30), Color(0.55, 0.95, 1.0), 11)
	btn_ability.pressed.connect(func() -> void: ability_pressed.emit())
	btn_wait = _make_button("HOLD", Rect2(168, 616, 132, 30), Color(0.72, 0.82, 0.9), 11)
	btn_wait.pressed.connect(func() -> void: wait_pressed.emit())
	btn_end = _make_button("END TURN   [SPACE]", Rect2(14, 652, 286, 36), Color(0.55, 0.95, 1.0), 12)
	btn_end.pressed.connect(func() -> void: end_turn_pressed.emit())


func _make_button(text: String, rect: Rect2, accent: Color, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.38, 0.45, 0.52, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.085, 0.115, 0.95)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var hb: StyleBoxFlat = sb.duplicate()
	hb.bg_color = Color(0.09, 0.18, 0.23, 1.0)
	hb.border_color = accent
	b.add_theme_stylebox_override("hover", hb)
	var pb: StyleBoxFlat = sb.duplicate()
	pb.bg_color = Color(0.13, 0.24, 0.28, 1.0)
	b.add_theme_stylebox_override("pressed", pb)
	var db: StyleBoxFlat = sb.duplicate()
	db.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	db.border_color = Color(0.25, 0.30, 0.35, 0.6)
	b.add_theme_stylebox_override("disabled", db)
	add_child(b)
	return b


func setup(p_battle: Battle) -> void:
	battle = p_battle
	status_text = ""
	status_error = false
	ability_armed = false
	hover_ship_id = -1
	roster_scroll = 0
	refresh()


func refresh() -> void:
	if battle == null or not is_inside_tree():
		return
	var sel := battle.selected_ship()
	var can_end: bool = battle.phase == Battle.Phase.PLAYER and battle.outcome == ""
	btn_end.disabled = not can_end
	if sel == null:
		btn_ability.text = "ABILITY"
		btn_ability.disabled = true
		btn_wait.disabled = true
	else:
		var kind := String(sel.ability.get("kind", ""))
		var blocked_by_attack: bool = sel.has_attacked and kind != "evade"
		btn_ability.disabled = sel.ability_cooldown > 0 or blocked_by_attack or sel.team != 0
		if sel.ability_cooldown > 0:
			btn_ability.text = "ABILITY   CD %d" % sel.ability_cooldown
		elif ability_armed:
			btn_ability.text = "CANCEL TARGETING"
		else:
			btn_ability.text = "ABILITY   [Q]"
		btn_wait.disabled = sel.has_attacked or sel.team != 0
		# M7B: the roster scrolls, so the selected hull must stay inside the window. The
		# index is recomputed from the fleet, never remembered: a destroyed hull shifts it.
		var all_player: Array[Ship] = _player_ships()
		for i in range(all_player.size()):
			if all_player[i].id == sel.id:
				ensure_visible(i)
				break
	queue_redraw()


func set_status(text: String, is_error: bool = false) -> void:
	status_text = text
	status_error = is_error
	queue_redraw()


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func roster_row_h(count: int) -> float:
	## Height of one roster row for a fleet of `count` hulls.
	##
	## STEP 3 lets the player compose fleets bigger than the five shipped hulls, and the
	## roster used to be five rows tall in BOTH the drawing loop and the click hit-test.
	## Rows shrink to fit the band above the buttons, but never below ROW_MIN_H: below that
	## the text, the bars and the HP numbers overlap (measured on the reference
	## screenshots). A fleet that still does not fit is scrolled - see `roster_visible_rows`.
	if count <= ROWS:
		return ROW_H
	var band: float = ROSTER_BOTTOM - ROW_TOP
	return clampf(band / float(count), ROW_MIN_H, ROW_H)


func roster_visible_rows(count: int) -> int:
	## How many rows fit in the band at the current row height. 0 for an empty fleet.
	if count <= 0:
		return 0
	var band: float = ROSTER_BOTTOM - ROW_TOP
	return clampi(int(floor(band / roster_row_h(count))), 1, count)


func roster_max_scroll(count: int) -> int:
	return maxi(0, count - roster_visible_rows(count))


func roster_scroll_by(rows: int) -> void:
	var total: int = _player_ships().size()
	roster_scroll = clampi(roster_scroll + rows, 0, roster_max_scroll(total))
	queue_redraw()


func ensure_visible(index: int) -> void:
	## Keeps the selected hull inside the roster window; called when the selection moves
	## (roster click, board click, [TAB]), so a scrolled fleet never hides its own
	## selection.
	var total: int = _player_ships().size()
	if total <= 0:
		return
	var visible: int = roster_visible_rows(total)
	if index < roster_scroll:
		roster_scroll = index
	elif index >= roster_scroll + visible:
		roster_scroll = index - visible + 1
	roster_scroll = clampi(roster_scroll, 0, roster_max_scroll(total))


func _player_ships() -> Array[Ship]:
	var all_player: Array[Ship] = []
	if battle == null:
		return all_player
	for s in battle.ships:
		if s.team == 0:
			all_player.append(s)
	return all_player


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mp.y >= ROW_TOP and mp.y < ROSTER_BOTTOM:
				roster_scroll_by(-3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3)
				accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var all_player: Array[Ship] = _player_ships()
			var rh: float = roster_row_h(all_player.size())
			var visible: int = roster_visible_rows(all_player.size())
			if mp.x >= 6 and mp.y >= ROW_TOP and mp.y < ROW_TOP + rh * float(visible):
				var index: int = roster_scroll + int((mp.y - ROW_TOP) / rh)
				if index >= 0 and index < all_player.size() and all_player[index].alive:
					ship_selected.emit(all_player[index].id)
					accept_event()


func _text(pos: Vector2, text: String, font_size: int, color: Color, width: float = -1.0) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)


func _right_text(right_x: float, y: float, text: String, font_size: int, color: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(right_x - w, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _bar(pos: Vector2, w: float, h: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(pos, Vector2(w, h)), Color(0.06, 0.08, 0.11, 1.0))
	draw_rect(Rect2(pos, Vector2(w * clampf(ratio, 0.0, 1.0), h)), color)


func _wrap(text: String, max_w: float, font_size: int) -> Array[String]:
	var out: Array[String] = []
	if font == null:
		return out
	var words: PackedStringArray = text.split(" ")
	var cur: String = ""
	for w in words:
		var probe: String = w if cur == "" else cur + " " + w
		if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w and cur != "":
			out.append(cur)
			cur = w
		else:
			cur = probe
	if cur != "":
		out.append(cur)
	return out


func _fit(text: String, max_w: float, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var cut: String = text
	while cut.length() > 3 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
		cut = cut.substr(0, cut.length() - 1)
	return cut + "…"


func _draw() -> void:
	# Panel.
	draw_rect(Rect2(0, 0, PANEL_W, 720), Color(0.024, 0.041, 0.062, 0.97))
	draw_line(Vector2(0, 0), Vector2(0, 720), Color(0.35, 0.70, 0.88, 0.45), 1.0)
	draw_line(Vector2(0, 0.5), Vector2(PANEL_W, 0.5), Color(0.35, 0.70, 0.88, 0.35), 1.0)
	if battle == null:
		return
	_draw_header()
	_draw_objective()
	_draw_roster()
	_draw_detail()
	_draw_log()
	_draw_status()


func _draw_header() -> void:
	_text(Vector2(14, 26), "VOID COMMAND", 15, Color(0.62, 0.95, 1.0, 1.0))
	_text(Vector2(14, 40), "TACTICAL FLEET COMMAND", 8, Color(0.42, 0.56, 0.68, 1.0))
	_text(Vector2(14, 62), "ROUND %02d" % battle.round, 17, Color(0.90, 0.95, 1.0, 1.0))
	var phase_text: String = "PLAYER PHASE"
	var phase_col := Color(0.50, 0.95, 1.0, 1.0)
	if battle.phase == 1:
		phase_text = "ENEMY PHASE"
		phase_col = Color(1.0, 0.60, 0.40, 1.0)
	elif battle.outcome != "":
		phase_text = "BATTLE OVER"
		phase_col = Color(0.85, 0.88, 0.95, 1.0)
	_right_text(286, 62, phase_text, 11, phase_col)
	draw_line(Vector2(14, 72), Vector2(286, 72), Color(0.30, 0.52, 0.68, 0.35), 1.0)


func _draw_objective() -> void:
	_text(Vector2(14, 92), "OBJECTIVE", 8, Color(0.45, 0.58, 0.70, 1.0))
	_text(Vector2(14, 106), "DESTROY ALL HOSTILES", 11, Color(0.88, 0.93, 0.98, 1.0))
	var relay: String = "RELAY VACANT"
	var rc := Color(0.55, 0.62, 0.72, 1.0)
	if battle.control_owner == 0:
		relay = "RELAY HELD %d/3" % battle.control_hold
		rc = Color(0.50, 0.95, 1.0, 1.0)
	elif battle.control_owner == 1:
		relay = "RELAY: HOSTILE"
		rc = Color(1.0, 0.60, 0.42, 1.0)
	_right_text(286, 92, relay, 9, rc)


func _draw_roster() -> void:
	_text(Vector2(14, 118), "FLEET", 8, Color(0.45, 0.58, 0.70, 1.0))
	var all_player: Array[Ship] = _player_ships()
	var total: int = all_player.size()
	if total == 0:
		return
	var row_h: float = roster_row_h(total)
	var visible: int = roster_visible_rows(total)
	roster_scroll = clampi(roster_scroll, 0, roster_max_scroll(total))
	var compact: bool = row_h < 26.0
	# Scroll affordance: only when the fleet does not fit, so a five-hull roster looks
	# exactly as it did before.
	if total > visible:
		_text(Vector2(206, 118), "%d–%d / %d   WHEEL" % [roster_scroll + 1, roster_scroll + visible, total],
			8, Color(0.42, 0.56, 0.68, 1.0))
		draw_rect(Rect2(296, ROW_TOP, 3, ROSTER_BOTTOM - ROW_TOP), Color(0.10, 0.16, 0.22, 1.0))
		var track: float = ROSTER_BOTTOM - ROW_TOP
		var thumb_h: float = track * float(visible) / float(total)
		var thumb_y: float = ROW_TOP + track * float(roster_scroll) / float(total)
		draw_rect(Rect2(296, thumb_y, 3, maxf(8.0, thumb_h)), Color(0.35, 0.70, 0.88, 0.75))
	for slot in range(visible):
		var i: int = roster_scroll + slot
		if i >= total:
			break
		var s: Ship = all_player[i]
		var y: float = ROW_TOP + float(slot) * row_h
		var selected: bool = s.id == battle.selected_id
		var hovered: bool = s.id == hover_ship_id
		var state: int = s.action_state()
		if selected:
			draw_rect(Rect2(6, y - 2, 288, row_h - 2), Color(0.16, 0.42, 0.52, 0.35))
			draw_rect(Rect2(6, y - 2, 2, row_h - 2), Color(0.55, 0.98, 1.0, 0.9))
		elif hovered:
			draw_rect(Rect2(6, y - 2, 288, row_h - 2), Color(0.20, 0.30, 0.38, 0.25))
		# Action state marker: cyan = can still move AND fire, amber = one of the two
		# left, hollow orange square = nothing left this round. Distinct from the
		# selection bar (left edge) and from the destroyed row (strikethrough).
		var marker := Vector2(15, y + 5)
		if not s.alive:
			pass
		elif state == Ship.ACTION_READY:
			draw_circle(marker, 2.2, Color(0.45, 0.95, 1.0, 0.9))
		elif state == Ship.ACTION_PARTIAL:
			draw_circle(marker, 2.2, Color(0.95, 0.78, 0.32, 0.95))
		else:
			draw_rect(Rect2(marker - Vector2(2.2, 2.2), Vector2(4.4, 4.4)), Color(0.95, 0.55, 0.32, 0.95), false, 1.2)
		var name_col := Color(0.85, 0.91, 0.97, 1.0) if s.alive else Color(0.42, 0.46, 0.52, 1.0)
		if s.alive and state == Ship.ACTION_DONE:
			name_col = Color(0.62, 0.66, 0.70, 1.0)
		_text(Vector2(22, y + 10), _fit(s.display_name.substr(4), 140, 10), 10, name_col)
		_text(Vector2(180, y + 10), SHORT_LABEL.get(s.ship_class, ShipDefs.label(s.ship_class)), 8,
			Color(0.48, 0.62, 0.74, 1.0))
		if s.alive:
			var hull_col := Color(0.35, 0.95, 0.55, 1.0)
			if s.hull_ratio() < 0.35:
				hull_col = Color(1.0, 0.38, 0.32, 1.0)
			elif s.hull_ratio() < 0.66:
				hull_col = Color(1.0, 0.78, 0.32, 1.0)
			var bar_y: float = y + 13.0 if compact else y + 14.0
			_bar(Vector2(22, bar_y), 150, 3 if not compact else 2, s.hull_ratio(), hull_col)
			_bar(Vector2(22, bar_y + 4), 150, 2, s.shield_ratio(), Color(0.40, 0.80, 1.0, 1.0))
			_right_text(286, y + 10 if compact else y + 19,
				"%d/%d" % [int(ceil(s.hull)), int(ceil(s.max_hull))], 8, Color(0.62, 0.72, 0.82, 1.0))
			if state == Ship.ACTION_DONE:
				_right_text(286, y + (19 if compact else 22), "NO ACTIONS", 7, Color(0.90, 0.58, 0.40, 1.0))
		else:
			draw_line(Vector2(22, y + 14), Vector2(174, y + 14), Color(0.30, 0.15, 0.15, 0.9), 2.0)
			_right_text(286, y + 10, "DESTROYED", 8, Color(0.70, 0.38, 0.34, 1.0))


## Short class tags: the full label at 8 px does not fit next to the name and the HP
## numbers on a compact row, and a truncated label reads as a different class.
const SHORT_LABEL: Dictionary = {
	"interceptor": "INT", "fighter": "FTR", "destroyer": "DD", "frigate": "FF",
	"cruiser": "CA", "carrier": "CV", "battleship": "BB", "dreadnought": "DN",
}


func _draw_detail() -> void:
	var y0: float = 276.0
	draw_line(Vector2(14, y0), Vector2(286, y0), Color(0.30, 0.52, 0.68, 0.35), 1.0)
	var target: Ship = null
	if hover_ship_id >= 0:
		var hs := battle.get_ship(hover_ship_id)
		if hs != null and hs.alive and hs.team == 1:
			target = hs
	if target != null:
		_text(Vector2(14, y0 + 18), "HOSTILE SCAN", 8, Color(1.0, 0.62, 0.45, 1.0))
		_text(Vector2(14, y0 + 34), _fit(target.display_name, 270, 12), 12, Color(0.98, 0.86, 0.80, 1.0))
		_text(Vector2(14, y0 + 48), "%s · %s" % [ShipDefs.label(target.ship_class), String(ShipDefs.def(target.ship_class)["role"])], 9, Color(0.66, 0.60, 0.58, 1.0))
		_bar(Vector2(14, y0 + 58), 272, 5, target.hull_ratio(), Color(0.95, 0.42, 0.35, 1.0))
		_bar(Vector2(14, y0 + 66), 272, 4, target.shield_ratio(), Color(0.40, 0.80, 1.0, 1.0))
		_text(Vector2(14, y0 + 84), "HULL %d / %d    SHIELD %d / %d" % [int(ceil(target.hull)), int(ceil(target.max_hull)), int(ceil(target.shield)), int(ceil(target.max_shield))], 9, Color(0.72, 0.80, 0.88, 1.0))
		_text(Vector2(14, y0 + 102), "DMG %d   RNG %d   ARM %d   MOVE %d" % [int(round(target.base_damage)), target.attack_range, int(target.armor), target.max_move], 9, Color(0.72, 0.80, 0.88, 1.0))
		if bool(battle.can_attack(battle.selected_id, target.id).get("ok", false)):
			_text(Vector2(14, y0 + 122), "IN RANGE — CLICK TO FIRE", 9, Color(0.95, 0.75, 0.35, 1.0))
		return
	var sel := battle.selected_ship()
	if sel == null:
		_text(Vector2(14, y0 + 18), "NO SHIP SELECTED", 10, Color(0.55, 0.66, 0.76, 1.0))
		var hint: Array[String] = _wrap("Click a friendly ship to plot movement and fire. Click an enemy in range to attack. Hover hostiles to scan them. T rotates the selected ship, R recentres the camera, Home fits the board.", 272, 9)
		var hy: float = y0 + 36.0
		for line in hint:
			_text(Vector2(14, hy), line, 9, Color(0.42, 0.54, 0.64, 1.0))
			hy += 13.0
		return
	_text(Vector2(14, y0 + 18), _fit(sel.display_name, 270, 13), 13, Color(0.80, 0.96, 1.0, 1.0))
	_text(Vector2(14, y0 + 33), "%s · %s" % [ShipDefs.label(sel.ship_class), String(ShipDefs.def(sel.ship_class)["role"])], 9, Color(0.55, 0.70, 0.82, 1.0))
	_bar(Vector2(14, y0 + 42), 272, 6, sel.hull_ratio(), Color(0.35, 0.95, 0.55, 1.0))
	_bar(Vector2(14, y0 + 51), 272, 4, sel.shield_ratio(), Color(0.40, 0.80, 1.0, 1.0))
	_text(Vector2(14, y0 + 69), "HULL %d / %d    SHIELD %d / %d" % [int(ceil(sel.hull)), int(ceil(sel.max_hull)), int(ceil(sel.shield)), int(ceil(sel.max_shield))], 9, Color(0.72, 0.80, 0.88, 1.0))
	_text(Vector2(14, y0 + 87), "MOVE %d / %d    DMG %d    RNG %d    ARM %d" % [sel.move_points, sel.max_move, int(round(sel.base_damage)), sel.attack_range, int(sel.armor)], 9, Color(0.72, 0.80, 0.88, 1.0))
	var ab: Dictionary = sel.ability
	var ability_col := Color(0.62, 0.92, 1.0, 1.0)
	var state: String = "READY"
	if sel.ability_cooldown > 0:
		state = "CD %d" % sel.ability_cooldown
		ability_col = Color(0.55, 0.62, 0.70, 1.0)
	_text(Vector2(14, y0 + 108), "%s  [%s]" % [String(ab.get("name", "")), state], 10, ability_col)
	var desc_lines: Array[String] = _wrap(String(ab.get("desc", "")), 270, 8)
	var dy: float = y0 + 121.0
	for line in desc_lines:
		_text(Vector2(14, dy), line, 8, Color(0.48, 0.60, 0.70, 1.0))
		dy += 11.0
	_text(Vector2(14, y0 + 150), "ATK %s   WAIT %s   ·   T ROTATE 90° IN PLACE" % ["USED" if sel.has_attacked else "READY", "YES" if sel.move_points > 0 else "NO"], 8, Color(0.52, 0.64, 0.74, 1.0))


func _draw_log() -> void:
	var top: float = 434.0
	var bottom: float = 596.0
	draw_rect(Rect2(8, top, 282, bottom - top), Color(0.014, 0.026, 0.041, 0.85))
	_text(Vector2(14, top + 15), "COMBAT LOG", 8, Color(0.45, 0.58, 0.70, 1.0))
	var lines: Array[String] = []
	for entry in battle.log_lines:
		for wrapped in _wrap(entry, 264, 8):
			lines.append(wrapped)
	var y: float = bottom - 6.0
	var i: int = lines.size() - 1
	while i >= 0 and y > top + 20.0:
		var col := Color(0.70, 0.80, 0.88, 1.0)
		var line: String = lines[i]
		if line.begins_with("—"):
			col = Color(0.55, 0.85, 1.0, 0.95)
		elif line.find("destroyed") >= 0:
			col = Color(1.0, 0.62, 0.50, 1.0)
		elif line.find("RELAY") >= 0:
			col = Color(0.95, 0.82, 0.45, 1.0)
		_text(Vector2(14, y), line, 8, col)
		y -= 11.0
		i -= 1


func _draw_status() -> void:
	if status_text == "":
		return
	var col := Color(1.0, 0.78, 0.42, 1.0) if status_error else Color(0.60, 0.90, 1.0, 1.0)
	_text(Vector2(14, 610), _fit(status_text, 286, 9), 9, col)
