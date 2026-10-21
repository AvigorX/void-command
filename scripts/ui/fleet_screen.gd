class_name FleetScreen
extends Control
## Fleet composition screen (STEP 3).
##
## Entirely procedural: `_draw` primitives only, no textures, no fonts beyond the
## project's default, no external assets.
##
## The screen owns NO rules. Every verdict comes from `FleetPoints`, so the UI cannot
## disagree with the core and the core cannot be bypassed by calling the screen directly.
## What the screen owns is the interaction: which row is selected, what a click means, and
## which of the four budgets and two battlefields is active.

signal confirmed(entries: Array, mode: String, map_size: Vector2i)
signal cancelled

const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")

const ROW_TOP: float = 208.0
const ROW_H: float = 46.0
const ROW_LEFT: float = 56.0
const ROW_RIGHT: float = 916.0
const PLUS_X: float = 826.0
const MINUS_X: float = 876.0
const CONFIRM_RECT: Rect2 = Rect2(56, 636, 300, 44)

var entries: Array[String] = []
var mode_id: String = FleetRef.DEFAULT_MODE
var map_size: Vector2i = MapConfig.REFERENCE
var selected_row: int = 0
var message: String = ""

var _font: Font
var _verdict: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	refresh()


# ------------------------------------------------------------------ state ----

func budget() -> int:
	return FleetRef.budget_of(mode_id)


func rows() -> Array[String]:
	## Every class is listed, including the ones that cannot be picked: an operator should
	## see that a Carrier exists and WHY it is not selectable, instead of a silent gap.
	return ShipDefsRef.catalog_ids()


func refresh() -> void:
	_verdict = FleetRef.validate_structure(entries, budget())
	queue_redraw()


func _row_for(class_id: String) -> int:
	var all_rows: Array[String] = rows()
	return all_rows.find(class_id)


func _selected_class() -> String:
	var all_rows: Array[String] = rows()
	if selected_row < 0 or selected_row >= all_rows.size():
		return ""
	return all_rows[selected_row]


func add_class(class_id: String) -> Dictionary:
	var check: Dictionary = FleetRef.can_add(entries, class_id, budget())
	if bool(check["ok"]):
		entries.append(class_id)
		message = ""
	else:
		message = String(check["reason"])
	refresh()
	return check


func remove_class(class_id: String) -> bool:
	var index: int = entries.rfind(class_id)
	if index < 0:
		message = "No %s in the fleet." % class_id.to_upper()
		refresh()
		return false
	entries.remove_at(index)
	message = ""
	refresh()
	return true


func set_mode(p_mode: String) -> void:
	if p_mode in FleetRef.mode_ids():
		mode_id = p_mode
		message = ""
		refresh()


func confirm() -> Dictionary:
	## The only path to a battle. A refused confirmation never emits `confirmed`.
	var full: Dictionary = FleetRef.validate(entries, budget(), map_size)
	if not bool(full["ok"]):
		message = String(full["reasons"][0]) if not (full["reasons"] as Array).is_empty() else "Invalid fleet."
		refresh()
		return {"ok": false, "reason": message}
	message = ""
	confirmed.emit(entries.duplicate(), mode_id, map_size)
	return {"ok": true, "reason": ""}


# --------------------------------------------------------------- drawing ----

func row_rect(index: int) -> Rect2:
	return Rect2(ROW_LEFT, ROW_TOP + float(index) * ROW_H, ROW_RIGHT - ROW_LEFT, ROW_H - 6.0)


func plus_rect(index: int) -> Rect2:
	var r: Rect2 = row_rect(index)
	return Rect2(PLUS_X, r.position.y + 4, 40, r.size.y - 8)


func minus_rect(index: int) -> Rect2:
	var r2: Rect2 = row_rect(index)
	return Rect2(MINUS_X, r2.position.y + 4, 40, r2.size.y - 8)


func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 1.0))
	draw_string(_font, Vector2(56, 56), "FLEET COMPOSITION", HORIZONTAL_ALIGNMENT_LEFT, -1, 28,
		Color(0.72, 0.92, 1.0, 1.0))
	draw_string(_font, Vector2(56, 82), "POINTS, NOT CREDITS  ·  spend the mission budget, keep your account",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.42, 0.56, 0.66, 1.0))
	# Budget line.
	var spent: int = FleetRef.total_cost(entries)
	var total: int = budget()
	var colour: Color = Color(0.55, 0.95, 1.0, 1.0) if spent <= total else Color(1.0, 0.42, 0.38, 1.0)
	draw_string(_font, Vector2(56, 122), "%s  ·  %d / %d" % [FleetRef.mode_label(mode_id), spent, total],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, colour)
	draw_rect(Rect2(56, 134, 860, 8), Color(0.10, 0.14, 0.20, 1.0))
	var fill: float = 0.0 if total <= 0 else clampf(float(spent) / float(total), 0.0, 1.0)
	draw_rect(Rect2(56, 134, 860.0 * fill, 8), colour)
	# A negative "remaining" reads as a bug; the overrun is what the operator needs to see.
	var remainder: int = total - spent
	draw_string(_font, Vector2(600, 122), ("REMAINING %d" % remainder) if remainder >= 0 else ("OVER BY %d" % -remainder),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.62, 0.95, 1.0, 1.0) if remainder >= 0 else Color(1.0, 0.42, 0.38, 1.0))
	draw_string(_font, Vector2(56, 166), "[1] SKIRMISH  [2] STANDARD  [3] FLEET ENGAGEMENT  [4] GRAND FLEET     [M] BATTLEFIELD %s" % MapConfigRef.label(map_size),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.42, 0.56, 0.66, 1.0))
	draw_string(_font, Vector2(56, 186), "CLASS                    ROLE                       FOOTPRINT   COST   x   STATE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.36, 0.48, 0.58, 1.0))
	# Rows.
	var all_rows: Array[String] = rows()
	for i in range(all_rows.size()):
		var id: String = all_rows[i]
		var e: Dictionary = ShipDefsRef.catalog_entry(id)
		var r: Rect2 = row_rect(i)
		var pickable: bool = bool(FleetRef.can_add(entries, id, budget()).get("ok", false))
		var have: int = FleetRef.count_of(entries, id)
		var base: Color = Color(0.06, 0.09, 0.13, 1.0)
		if i == selected_row:
			base = Color(0.10, 0.18, 0.26, 1.0)
		draw_rect(r, base)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(0.55, 0.95, 1.0, 1.0) if i == selected_row else Color(0.14, 0.20, 0.28, 1.0))
		var dim: Color = Color(0.70, 0.82, 0.90, 1.0) if bool(e.get("implemented", false)) else Color(0.34, 0.42, 0.50, 1.0)
		draw_string(_font, Vector2(r.position.x + 14, r.position.y + 26), String(e.get("label", id)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, dim)
		draw_string(_font, Vector2(r.position.x + 190, r.position.y + 26), String(e.get("role", "")),
			HORIZONTAL_ALIGNMENT_LEFT, 220, 12, dim)
		draw_string(_font, Vector2(r.position.x + 430, r.position.y + 26), _footprint_text(e),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)
		draw_string(_font, Vector2(r.position.x + 540, r.position.y + 26), "%d" % int(e.get("cost", -1)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)
		draw_string(_font, Vector2(r.position.x + 600, r.position.y + 26), "x%d" % have,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.95, 1.0, 1.0) if have > 0 else dim)
		draw_string(_font, Vector2(r.position.x + 660, r.position.y + 26), _state_text(id, e),
			HORIZONTAL_ALIGNMENT_LEFT, 160, 11, _state_colour(id, e))
		# +/- affordances, only where they mean something.
		if bool(e.get("implemented", false)) and bool(e.get("available", false)):
			_draw_button(plus_rect(i), "+", pickable)
			_draw_button(minus_rect(i), "-", have > 0)
		# Procedural footprint silhouette: the hull's shape, not a decoration.
		_draw_hull(e, Vector2(r.position.x + 478, r.position.y + 19))
	# Verdict + actions.
	var verdict_line: String = message
	if verdict_line == "":
		if bool(_verdict["ok"]):
			verdict_line = "READY - %d hulls, %d points spent, %d left." % [entries.size(), spent, total - spent]
		else:
			verdict_line = String((_verdict["reasons"] as Array)[0]) if not (_verdict["reasons"] as Array).is_empty() else "Invalid fleet."
	var v_colour: Color = Color(0.45, 0.95, 0.62, 1.0) if (bool(_verdict["ok"]) and message == "") else Color(1.0, 0.62, 0.42, 1.0)
	draw_string(_font, Vector2(56, 616), verdict_line, HORIZONTAL_ALIGNMENT_LEFT, 860, 13, v_colour)
	var can_confirm: bool = bool(_verdict["ok"])
	draw_rect(CONFIRM_RECT, Color(0.10, 0.26, 0.34, 1.0) if can_confirm else Color(0.10, 0.12, 0.16, 1.0))
	draw_string(_font, CONFIRM_RECT.position + Vector2(24, 28), "DEPLOY  [ENTER]",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.96, 1.0, 1.0) if can_confirm else Color(0.36, 0.42, 0.50, 1.0))
	draw_string(_font, Vector2(380, 664), "[SPACE] add   [BACKSPACE] remove   [UP/DOWN] select   [ESC] back",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.42, 0.56, 0.66, 1.0))


func _draw_button(r: Rect2, label: String, enabled: bool) -> void:
	var bg: Color = Color(0.12, 0.22, 0.30, 1.0) if enabled else Color(0.08, 0.10, 0.13, 1.0)
	draw_rect(r, bg)
	draw_rect(r, Color(0.30, 0.55, 0.68, 1.0) if enabled else Color(0.16, 0.20, 0.26, 1.0), false, 1.0)
	draw_string(_font, r.position + Vector2(16, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.80, 0.96, 1.0, 1.0) if enabled else Color(0.30, 0.36, 0.44, 1.0))


func _draw_hull(e: Dictionary, origin: Vector2) -> void:
	## Footprint silhouette from the same data the rules use. An unresolved footprint draws
	## a question mark, never a guessing shape.
	var fp: Variant = e.get("footprint", null)
	var status: String = String(e.get("footprint_status", ""))
	if typeof(fp) != TYPE_VECTOR2I or status != "confirmed":
		draw_string(_font, origin, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.40, 0.50, 0.60, 1.0))
		return
	var v: Vector2i = fp
	var unit: float = 6.0
	for x in range(maxi(v.x, v.y)):
		draw_rect(Rect2(origin + Vector2(float(x) * (unit + 1.0), 0), Vector2(unit, unit)),
			Color(0.55, 0.95, 1.0, 0.85))


func _footprint_text(e: Dictionary) -> String:
	var fp: Variant = e.get("footprint", null)
	if typeof(fp) != TYPE_VECTOR2I:
		return "n/a"
	var v: Vector2i = fp
	return "%dx%d" % [mini(v.x, v.y), maxi(v.x, v.y)]


func _state_text(id: String, e: Dictionary) -> String:
	if not bool(e.get("implemented", false)):
		return "NOT IMPLEMENTED"
	if not bool(e.get("available", false)):
		return "UNAVAILABLE"
	if String(e.get("footprint_status", "")) != "confirmed":
		return "FOOTPRINT OPEN"
	# A cap is only shown where one exists: five of the eight classes have none, and
	# inventing a number for them would be exactly the "false limit" the mandate forbids.
	var cap: int = ShipDefsRef.cap_of(id)
	var have: int = FleetRef.count_of(entries, id)
	if cap > 0:
		if have >= cap:
			return "AT CAP %d" % cap
		return "CAP %d" % cap
	if have > 0:
		return "IN FLEET"
	return "AVAILABLE"


func _state_colour(id: String, e: Dictionary) -> Color:
	var text: String = _state_text(id, e)
	if text.begins_with("AT CAP"):
		return Color(1.0, 0.62, 0.42, 1.0)
	match text:
		"IN FLEET":
			return Color(0.45, 0.95, 0.62, 1.0)
		"AVAILABLE":
			return Color(0.62, 0.95, 1.0, 1.0)
		_:
			return Color(0.40, 0.50, 0.60, 1.0)


# ----------------------------------------------------------------- input ----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		return
	# Keys are matched by keycode, NOT through ui_accept: Godot's default InputMap binds
	# ui_accept to SPACE as well as ENTER, which would make SPACE confirm the fleet instead
	# of adding the selected hull.
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_UP:
			selected_row = maxi(0, selected_row - 1)
			queue_redraw()
		KEY_DOWN:
			selected_row = mini(rows().size() - 1, selected_row + 1)
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			confirm()
		KEY_SPACE:
			add_class(_selected_class())
		KEY_BACKSPACE:
			remove_class(_selected_class())
		KEY_1:
			set_mode("skirmish")
		KEY_2:
			set_mode("standard")
		KEY_3:
			set_mode("fleet_engagement")
		KEY_4:
			set_mode("grand_fleet")
		KEY_M:
			map_size = MapConfigRef.next_size(map_size)
			message = "Battlefield set to %s." % MapConfigRef.label(map_size)
			refresh()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = click.position
	if CONFIRM_RECT.has_point(p):
		confirm()
		return
	var all_rows: Array[String] = rows()
	for i in range(all_rows.size()):
		var id: String = all_rows[i]
		if plus_rect(i).has_point(p):
			selected_row = i
			add_class(id)
			return
		if minus_rect(i).has_point(p):
			selected_row = i
			remove_class(id)
			return
		if row_rect(i).has_point(p):
			selected_row = i
			message = ""
			queue_redraw()
			return
