extends Node2D
## Procedural battlefield renderer: terrain, ships, overlays, VFX.
## It reads Battle state only. It never decides outcomes.

## Pixel geometry is DERIVED from the battle's grid (STEP 2 / Block B).
## The reference 20x14 board keeps 46 px cells and the authored origin, so its
## rendering does not move; a larger grid shrinks the cell until the whole board fits
## the play area left of the HUD. (Named cell_px: local `cell` variables are everywhere.)
const BASE_CELL: float = 46.0
const ORIGIN: Vector2 = Vector2(24, 54)
## The board owns everything left of the HUD panel: 1280 - panel - left margin.
## STEP 2.1 makes the coupling explicit instead of hiding a 928 in the maths, so a
## narrower panel would widen the board without touching this file's call sites.
const HUD_PANEL_W: float = 328.0
const PLAY_H: float = 666.0
const PLAY_SIZE: Vector2 = Vector2(1280.0 - HUD_PANEL_W - 24.0, PLAY_H)
var cell_px: float = BASE_CELL
var board_w: float = 920.0
var board_h: float = 644.0

const DefsRef = preload("res://scripts/core/ship_defs.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const MapRef = preload("res://scripts/core/battle_map.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")

var HULL_SHAPES: Dictionary = {
	"fighter": PackedVector2Array([
		Vector2(-13, -6), Vector2(1, -5), Vector2(15, 0), Vector2(1, 5), Vector2(-13, 6), Vector2(-7, 0),
	]),
	"frigate": PackedVector2Array([
		Vector2(-15, -6), Vector2(4, -7), Vector2(14, -4), Vector2(17, 0),
		Vector2(14, 4), Vector2(4, 7), Vector2(-15, 6), Vector2(-11, 0),
	]),
	"cruiser": PackedVector2Array([
		Vector2(-17, -8), Vector2(0, -9), Vector2(12, -6), Vector2(17, 0),
		Vector2(12, 6), Vector2(0, 9), Vector2(-17, 8), Vector2(-13, 0),
	]),
	"interceptor": PackedVector2Array([
		Vector2(-11, -3), Vector2(2, -4), Vector2(13, 0), Vector2(2, 4), Vector2(-11, 3), Vector2(-7, 0),
	]),
	"destroyer": PackedVector2Array([
		Vector2(-16, -4), Vector2(2, -5), Vector2(12, -3), Vector2(16, 0),
		Vector2(12, 3), Vector2(2, 5), Vector2(-16, 4), Vector2(-12, 0),
	]),
	"carrier": PackedVector2Array([
		# A flight deck: a long flat slab, squared off at the stern, with two prongs
		# forward and a hangar island offset to one flank so the profile is asymmetric.
		Vector2(-20, -6), Vector2(6, -6), Vector2(18, -3), Vector2(20, 0),
		Vector2(10, 2), Vector2(6, 7), Vector2(-20, 7), Vector2(-20, -2),
	]),
	"dreadnought": PackedVector2Array([
		# A wedge: broad shoulders aft, a narrow spear forward, a central spine.
		Vector2(-21, -8), Vector2(-4, -9), Vector2(8, -6), Vector2(21, 0),
		Vector2(8, 6), Vector2(-4, 9), Vector2(-21, 8), Vector2(-21, -3),
	]),
	"battleship": PackedVector2Array([
		Vector2(-19, -9), Vector2(6, -10), Vector2(16, -7), Vector2(19, 0),
		Vector2(16, 7), Vector2(6, 10), Vector2(-19, 9), Vector2(-15, 0),
	]),
}

var battle: Battle
var time: float = 0.0
var hover_cell: Vector2i = Vector2i(-1, -1)

## Fighter formation (STEP 2, visual only): leader first, then the two wingmen.
## Offsets are in hull-local units (the cell is 46 px at reference scale).
const SQUADRON_SLOTS: Array[Vector2] = [Vector2(7.0, 0.0), Vector2(-6.0, -9.0), Vector2(-6.0, 9.0)]
## The Interceptor reads as a sharper, wider dart: a leader, two outriders further back and
## a tail. Static offsets only - the M6 mandate removed the engine pulse.
const DART_SLOTS: Array[Vector2] = [Vector2(9.0, 0.0), Vector2(-3.0, -10.0), Vector2(-3.0, 10.0),
	Vector2(-11.0, 0.0)]
## M7: the Fighter gets FOUR variants of its three-craft flight, all inside one cell and at
## the same scale (the slot radius is identical), so two fighters of the same fleet look
## like a squadron and not like a copy. The variant is picked from the unit id: stable for a
## given hull, and never a new logical unit.
const FIGHTER_VARIANTS: Array = [
	[Vector2(7.0, 0.0), Vector2(-6.0, -9.0), Vector2(-6.0, 9.0)],
	[Vector2(7.0, -2.0), Vector2(-2.0, -9.0), Vector2(-8.0, 6.0)],
	[Vector2(6.0, 1.0), Vector2(-5.0, -8.0), Vector2(-7.0, 8.0)],
	[Vector2(8.0, 0.0), Vector2(-8.0, -6.0), Vector2(-4.0, 8.0)],
]
var hover_ship_id: int = -1
var armed_ability: bool = false
var ability_highlight: Dictionary = {}

var visual_pos: Dictionary = {}
var ghosts: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var event_queue: Array[Dictionary] = []
var event_timer: float = 0.0
var reachable: Dictionary = {}
var reachable_ori: Dictionary = {}
var attack_cells: Dictionary = {}
var path_prev: Dictionary = {}
var last_selected: int = -1
var trail_clock: float = 0.0
var draw_count: int = 0


func setup(p_battle: Battle) -> void:
	battle = p_battle
	# Derive the pixel geometry from the actual grid. For the reference 20x14 board
	# this yields exactly 46 px and 920x644 - the authored values - so the historical
	# rendering does not move. A 32x22 board gets 29 px, which fits the whole board in
	# the play area instead of running under the HUD and off the window.
	var dims: Vector2i = Vector2i(battle.map.width, battle.map.height)
	cell_px = minf(BASE_CELL, floorf(PLAY_SIZE.x / float(dims.x)))
	cell_px = minf(cell_px, floorf(PLAY_SIZE.y / float(dims.y)))
	board_w = float(dims.x) * cell_px
	board_h = float(dims.y) * cell_px
	visual_pos.clear()
	ghosts.clear()
	effects.clear()
	event_queue.clear()
	event_timer = 0.0
	armed_ability = false
	ability_highlight.clear()
	last_selected = -1
	for s in battle.ships:
		visual_pos[s.id] = ship_center(s)
	refresh_overlays()
	queue_redraw()


func refresh_overlays() -> void:
	reachable.clear()
	reachable_ori.clear()
	attack_cells.clear()
	path_prev.clear()
	var sel := battle.selected_ship() if battle != null else null
	if sel != null and sel.alive:
		var explored: Dictionary = battle.reachable_cells(sel.id)
		reachable = explored.get("dist", {})
		path_prev = explored.get("prev", {})
		# The orientation each anchor would be reached at. A multi-cell hull can only
		# sit on some anchors after turning, so the overlay AND the click must use it.
		reachable_ori = explored.get("orientation", {})
		attack_cells = battle.attack_cells(sel.id)


func highlight_targets(targets: Array) -> void:
	## Marks every occupied cell of every legal target, so clicking any cell of a
	## multi-cell hull works as well as its reference corner. The view only paints -
	## legality comes from Battle (ability_targets / can_use_ability).
	ability_highlight.clear()
	for t in targets:
		for c in t.cells():
			ability_highlight[c] = true
	queue_redraw()


func is_busy() -> bool:
	return not event_queue.is_empty() or event_timer > 0.0


func cell_center(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2(float(c.x) + 0.5, float(c.y) + 0.5) * cell_px


func world_to_cell(p: Vector2) -> Vector2i:
	var local: Vector2 = (p - ORIGIN) / cell_px
	return Vector2i(int(floor(local.x)), int(floor(local.y)))


func ship_at(c: Vector2i) -> Ship:
	## Delegates to the rules layer: ANY cell of a ship's footprint resolves to it,
	## so clicking the second cell of a 2-cell hull selects the same ship.
	return battle.ship_at(c)


func ship_center(s: Ship) -> Vector2:
	## Visual centre of the footprint. For a 1x1 hull this is exactly cell_center(),
	## so the existing rendering anchors do not move by a single pixel.
	var e: Vector2i = FootprintRef.extent(s.footprint, s.orientation)
	if e == Vector2i.ONE:
		return cell_center(s.cell)
	return ORIGIN + (Vector2(s.cell) + Vector2(e) * 0.5) * cell_px


func _draw_squadron(base: Color, trim: Color, dark: Color, outline_w: float, sid: int,
		kind: String = "fighter") -> void:
	## Draws a swarm as a tight formation inside its ONE cell: three craft in a V for the
	## Fighter, four in a dart for the Interceptor.
	##
	## M6 removed the engine pulse: the swarm no longer wobbles on a sine. The formation is
	## still a formation - a per-ship static offset in the slot list keeps two units of the
	## same fleet from looking stamped out - but nothing animates periodically, by mandate.
	## `_squadron_slots()` owns that layout so the draw code has no magic positions.
	##
	## Design constraints from the mandate: the cell must stay 1x1 on the grid, the
	## squadron must read as a single unit (not as three selectable ships), and it must
	## survive the small scale of the board. So: one leader and two wingmen, all
	## outlined in the team trim, joined by two faint contrails, with a per-ship phase
	## offset so two fighters in the same fleet do not look identical.
	##
	## Called inside the hull transform (position + facing + scale), so selection rings,
	## hover, health bars and orientation keep working untouched.
	var slots: Array[Vector2] = _squadron_slots(kind, sid)
	for i in range(slots.size()):
		var at: Vector2 = slots[i]
		var k: float = 0.60 if i == 0 else (0.48 if kind == "fighter" else 0.42)
		var body := PackedVector2Array([
			at + Vector2(-8.0, -3.6) * k, at + Vector2(1.0, -3.0) * k, at + Vector2(10.0, 0.0) * k,
			at + Vector2(1.0, 3.0) * k, at + Vector2(-8.0, 3.6) * k, at + Vector2(-4.5, 0.0) * k,
		])
		var shadow := PackedVector2Array()
		for p in body:
			shadow.append(p + Vector2(1.3, 1.3))
		draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.40))
		var hull_fill: Color = base if i == 0 else base.darkened(0.14)
		draw_colored_polygon(body, hull_fill)
		var inner := PackedVector2Array()
		for p in body:
			inner.append(at + (p - at) * 0.55)
		draw_colored_polygon(inner, Color(dark.r, dark.g, dark.b, 1.0))
		draw_polyline(body + PackedVector2Array([body[0]]), trim, maxf(0.9, outline_w * 0.75), true)
		# Canopy glint: one bright point keeps the leader readable at small scale.
		draw_circle(at + Vector2(5.0 * k, 0.0), 1.5 if i == 0 else 1.1, Color(0.85, 0.98, 1.0, 0.90))
	# Contrails joining the wingmen to the leader: the cue that makes it ONE flight.
	for i in range(1, slots.size()):
		draw_line(slots[i], slots[0] + Vector2(-3.0, 0.0),
			Color(trim.r, trim.g, trim.b, 0.20), 1.0)


func _process(delta: float) -> void:
	time += delta
	if battle == null:
		return
	if battle.pending_events() > 0:
		event_queue.append_array(battle.drain_events())
	if event_timer > 0.0:
		event_timer -= delta
	elif not event_queue.is_empty() and effects.size() < 40:
		var ev: Dictionary = event_queue.pop_front()
		_spawn_event(ev)
		event_timer = 0.16 if String(ev.get("type", "")) != "move" else 0.05
	trail_clock += delta
	for s in battle.ships:
		if not visual_pos.has(s.id):
			visual_pos[s.id] = ship_center(s)
		var target: Vector2 = ship_center(s)
		var cur: Vector2 = visual_pos[s.id]
		if cur.distance_to(target) > 0.6:
			visual_pos[s.id] = cur.lerp(target, minf(1.0, delta * 8.0))
			if trail_clock > 0.035:
				trail_clock = 0.0
				effects.append({"kind": "trail", "pos": cur, "t": 0.0, "dur": 0.45, "color": DefsRef.TEAM_COLORS[s.team]})
		else:
			visual_pos[s.id] = target
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		if float(e.get("delay", 0.0)) > 0.0:
			e["delay"] = float(e["delay"]) - delta
			continue
		e["t"] = float(e.get("t", 0.0)) + delta
		if float(e["t"]) >= float(e.get("dur", 0.5)):
			effects.remove_at(i)
	for i in range(ghosts.size() - 1, -1, -1):
		ghosts[i]["t"] = float(ghosts[i]["t"]) + delta
		if float(ghosts[i]["t"]) >= float(ghosts[i]["dur"]):
			ghosts.remove_at(i)
	queue_redraw()


func _spawn_event(ev: Dictionary) -> void:
	var kind := String(ev.get("type", ""))
	match kind:
		"move":
			var from: Vector2i = ev.get("from", Vector2i.ZERO)
			var to: Vector2i = ev.get("to", Vector2i.ZERO)
			var id: int = int(ev.get("id", -1))
			if visual_pos.has(id) and PathfinderRef.manhattan(from, to) > 3:
				visual_pos[id] = cell_center(from)
		"attack":
			var from_c: Vector2i = ev.get("from", Vector2i.ZERO)
			var to_c: Vector2i = ev.get("to", Vector2i.ZERO)
			var team: int = int(ev.get("team", 0))
			var color: Color = DefsRef.TEAM_TRIM[team]
			var beam: bool = bool(ev.get("beam", false))
			var a: Vector2 = cell_center(from_c)
			var b: Vector2 = cell_center(to_c)
			effects.append({"kind": "shot", "from": a, "to": b, "t": 0.0, "dur": 0.22, "color": color, "beam": beam})
			var dmg: float = float(ev.get("damage", 0.0))
			effects.append({"kind": "hit", "pos": b, "t": 0.0, "dur": 0.40, "delay": 0.18,
				"color": color, "shield": float(ev.get("shield", 0.0))})
			effects.append({"kind": "text", "pos": b, "text": "-%d" % int(round(dmg)), "t": 0.0, "dur": 0.85,
				"delay": 0.18, "color": Color(1.0, 0.85, 0.55, 1.0)})
			effects.append({"kind": "flash", "pos": b, "t": 0.0, "dur": 0.18, "delay": 0.16})
			if bool(ev.get("destroyed", false)):
				effects.append({"kind": "boom", "pos": b, "t": 0.0, "dur": 0.95, "delay": 0.22, "seed": int(ev.get("target", 0))})
		"destroy":
			var cell: Vector2i = ev.get("cell", Vector2i.ZERO)
			var sid: int = int(ev.get("id", -1))
			var pos: Vector2 = visual_pos.get(sid, cell_center(cell))
			ghosts.append({"id": sid, "pos": pos, "class": String(ev.get("class", "fighter")),
				"team": int(ev.get("team", 1)), "t": 0.0, "dur": 0.9})
			effects.append({"kind": "boom", "pos": pos, "t": 0.0, "dur": 0.95, "seed": sid})
		"ability":
			var cell2: Vector2i = ev.get("cell", Vector2i.ZERO)
			var pos2: Vector2 = cell_center(cell2)
			var aid: int = int(ev.get("id", -1))
			var team2: int = 0
			var ship = battle.get_ship(aid)
			if ship != null:
				team2 = ship.team
			effects.append({"kind": "ring", "pos": pos2, "t": 0.0, "dur": 0.6, "color": DefsRef.TEAM_TRIM[team2]})
			effects.append({"kind": "text", "pos": pos2, "text": String(ship.ability_name()) if ship != null else "ABILITY",
				"t": 0.0, "dur": 1.0, "color": DefsRef.TEAM_TRIM[team2]})
		"emp":
			var cell3: Vector2i = ev.get("cell", Vector2i.ZERO)
			effects.append({"kind": "ring", "pos": cell_center(cell3), "t": 0.0, "dur": 0.9,
				"color": Color(0.65, 0.85, 1.0, 1.0)})


func _draw() -> void:
	if battle == null:
		return
	draw_count += 1
	_draw_board()
	_draw_terrain()
	_draw_grid()
	_draw_control_point()
	_draw_overlays()
	_draw_ships()
	_draw_effects()


func _draw_board() -> void:
	draw_rect(Rect2(ORIGIN, Vector2(board_w, board_h)), Color(0.015, 0.028, 0.050, 0.62))
	# Deployment zone tint.
	draw_rect(Rect2(ORIGIN, Vector2(cell_px * 4.0, board_h)), Color(0.20, 0.55, 0.85, 0.045))
	draw_rect(Rect2(ORIGIN + Vector2(board_w - cell_px * 4.0, 0), Vector2(cell_px * 4.0, board_h)), Color(0.85, 0.32, 0.25, 0.045))
	draw_rect(Rect2(ORIGIN, Vector2(board_w, board_h)), Color(0.35, 0.55, 0.70, 0.30), false, 1.0)
	# Corner brackets.
	var c := Color(0.42, 0.78, 0.95, 0.55)
	var L: float = 22.0
	var corners: Array[Vector2] = [
		ORIGIN, ORIGIN + Vector2(board_w, 0), ORIGIN + Vector2(0, board_h), ORIGIN + Vector2(board_w, board_h),
	]
	for i in range(4):
		var p: Vector2 = corners[i]
		var sx: float = 1.0 if p.x < ORIGIN.x + board_w * 0.5 else -1.0
		var sy: float = 1.0 if p.y < ORIGIN.y + board_h * 0.5 else -1.0
		draw_line(p, p + Vector2(L * sx, 0), c, 2.0)
		draw_line(p, p + Vector2(0, L * sy), c, 2.0)


func _squadron_slots(kind: String, sid: int = 0) -> Array[Vector2]:
	## One place decides the formation. `fighter` picks one of four three-craft layouts from
	## the unit id (same scale, same cell); `interceptor` is the four-craft dart; anything
	## else falls back to the first Fighter layout so a future class cannot crash.
	if kind == "interceptor":
		return DART_SLOTS
	if kind == "fighter":
		var idx: int = absi(sid) % FIGHTER_VARIANTS.size()
		var out: Array[Vector2] = []
		for v in FIGHTER_VARIANTS[idx]:
			out.append(v)
		return out
	return SQUADRON_SLOTS


func _draw_terrain() -> void:
	var map := battle.map
	for anchor in map.planet_anchors:
		_draw_planet(anchor)
	for y in range(map.height):
		for x in range(map.width):
			var c := Vector2i(x, y)
			match map.at(c):
				MapRef.Terrain.NEBULA:
					_draw_nebula(c)
				_:
					pass


func _draw_nebula(c: Vector2i) -> void:
	var center: Vector2 = cell_center(c)
	var phase: float = float(battle.map.cell_hash(c) % 1000) * 0.01
	var drift := Vector2(sin(time * 0.25 + phase) * 4.0, cos(time * 0.19 + phase) * 3.0)
	var tint: Color = Color(0.28, 0.36, 0.72, 1.0) if battle.map.cell_hash(c) % 3 != 0 else Color(0.48, 0.28, 0.62, 1.0)
	for i in range(3):
		var rad: float = cell_px * (0.62 - 0.13 * float(i))
		draw_circle(center + drift * (1.0 + 0.3 * float(i)), rad, Color(tint.r, tint.g, tint.b, 0.055 + 0.02 * float(i)))


func _draw_planet(anchor: Vector2i) -> void:
	var center: Vector2 = cell_center(anchor) + Vector2(cell_px * 0.45, cell_px * 0.45)
	var radius: float = cell_px * 1.15
	var h: int = battle.map.cell_hash(anchor)
	var palette: Array[Color] = [
		Color(0.24, 0.36, 0.58), Color(0.35, 0.26, 0.40), Color(0.20, 0.42, 0.42), Color(0.46, 0.34, 0.26),
	]
	var base: Color = palette[h % palette.size()]
	for i in range(9, 0, -1):
		var f: float = float(i) / 9.0
		var col: Color = Color(base.r * (0.35 + 0.65 * (1.0 - f)), base.g * (0.35 + 0.65 * (1.0 - f)), base.b * (0.35 + 0.65 * (1.0 - f)), 1.0)
		draw_circle(center + Vector2(-radius * 0.10 * f, -radius * 0.10 * f), radius * f, col)
	# Terminator shadow
	draw_circle(center + Vector2(radius * 0.35, radius * 0.30), radius * 0.92, Color(0.01, 0.015, 0.03, 0.55))
	# Atmosphere rim
	draw_arc(center, radius + 1.5, 0, TAU, 48, Color(base.r * 1.6, base.g * 1.6, base.b * 1.7, 0.35), 2.0, true)
	# Ring for some planets
	if h % 3 == 0:
		draw_set_transform(center, -0.35, Vector2(1.55, 0.42))
		draw_arc(Vector2.ZERO, radius * 0.95, 0, TAU, 48, Color(0.62, 0.60, 0.72, 0.30), 3.0, true)
		draw_arc(Vector2.ZERO, radius * 1.10, 0, TAU, 48, Color(0.52, 0.52, 0.66, 0.22), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_grid() -> void:
	var line_col := Color(0.30, 0.52, 0.68, 0.075)
	for x in range(battle.map.width + 1):
		var px: float = ORIGIN.x + float(x) * cell_px
		draw_line(Vector2(px, ORIGIN.y), Vector2(px, ORIGIN.y + board_h), line_col, 1.0)
	for y in range(battle.map.height + 1):
		var py: float = ORIGIN.y + float(y) * cell_px
		draw_line(Vector2(ORIGIN.x, py), Vector2(ORIGIN.x + board_w, py), line_col, 1.0)


func _draw_control_point() -> void:
	var c: Vector2i = battle.map.control_cell
	var center: Vector2 = cell_center(c)
	var owner: int = battle.control_owner
	var col: Color = Color(0.80, 0.85, 0.95, 1.0)
	if owner == 0:
		col = Color(0.45, 0.95, 1.0, 1.0)
	elif owner == 1:
		col = Color(1.0, 0.55, 0.35, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(time * 2.2)
	draw_circle(center, cell_px * 0.40, Color(col.r, col.g, col.b, 0.07 + 0.05 * pulse))
	draw_arc(center, cell_px * 0.34, time * 0.9, time * 0.9 + TAU * 0.72, 24, Color(col.r, col.g, col.b, 0.85), 2.0, true)
	draw_arc(center, cell_px * 0.34, time * 0.9 + PI, time * 0.9 + PI + TAU * 0.72, 24, Color(col.r, col.g, col.b, 0.55), 2.0, true)
	var d := PackedVector2Array([center + Vector2(0, -9), center + Vector2(9, 0), center + Vector2(0, 9), center + Vector2(-9, 0)])
	draw_colored_polygon(d, Color(col.r, col.g, col.b, 0.22))
	draw_polyline(d + PackedVector2Array([d[0]]), col, 1.5)
	draw_circle(center, 2.5, col)
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-16, cell_px * 0.62), "RELAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(col.r, col.g, col.b, 0.75))
	if battle.control_hold > 0:
		draw_string(font, center + Vector2(-10, cell_px * 0.80), "%d/3" % battle.control_hold, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(col.r, col.g, col.b, 0.9))


func _draw_overlays() -> void:
	var sel := battle.selected_ship()
	if sel != null and sel.alive:
		# Movement range.
		for c in reachable.keys():
			var cell: Vector2i = c
			if cell == sel.cell or cell == battle.map.control_cell:
				continue
			# A multi-cell hull must show WHERE THE HULL WOULD SIT, not just the
			# anchor: a single highlighted cell understates a 2x3 footprint and reads
			# like a 1x1 destination.
			# STEP 2: the footprint is drawn at the orientation the search reports for
			# this anchor, because that is the state the click will commit. Drawing it
			# at the hull's current orientation advertised a destination the rules
			# would refuse.
			if sel.footprint != Vector2i.ONE:
				var dest_ori: int = int(reachable_ori.get(cell, sel.orientation))
				for cc in FootprintRef.cells(cell, sel.footprint, dest_ori):
					var big_r := Rect2(ORIGIN + Vector2(cc) * cell_px + Vector2(1, 1), Vector2(cell_px - 2, cell_px - 2))
					draw_rect(big_r, Color(0.30, 0.85, 1.0, 0.045))
					draw_rect(big_r, Color(0.35, 0.90, 1.0, 0.10), false, 1.0)
				continue
			var r := Rect2(ORIGIN + Vector2(cell) * cell_px + Vector2(4, 4), Vector2(cell_px - 8, cell_px - 8))
			draw_rect(r, Color(0.30, 0.85, 1.0, 0.075))
			draw_rect(r, Color(0.35, 0.90, 1.0, 0.16), false, 1.0)
		# Weapon envelope ring.
		draw_arc(cell_center(sel.cell), float(sel.attack_range) * cell_px, 0, TAU, 64,
			Color(1.0, 0.45, 0.35, 0.10), 2.0, true)
		# Path preview.
		if hover_cell != sel.cell and reachable.has(hover_cell) and ship_at(hover_cell) == null:
			var path: Array[Vector2i] = PathfinderRef.build_path(path_prev, sel.cell, hover_cell)
			var cost: int = int(reachable.get(hover_cell, 0))
			var col := Color(0.55, 0.98, 1.0, 0.9 if cost <= sel.move_points else 0.4)
			for i in range(1, path.size()):
				draw_line(cell_center(path[i - 1]), cell_center(path[i]), Color(col.r, col.g, col.b, 0.55), 2.0)
			for i in range(path.size()):
				draw_circle(cell_center(path[i]), 2.2, col)
	# Ability targets.
	if armed_ability:
		for c in ability_highlight.keys():
			var cell2: Vector2i = c
			var r2 := Rect2(ORIGIN + Vector2(cell2) * cell_px + Vector2(2, 2), Vector2(cell_px - 4, cell_px - 4))
			draw_rect(r2, Color(0.92, 0.45, 1.0, 0.10))
			draw_rect(r2, Color(0.95, 0.55, 1.0, 0.55), false, 1.5)
	# Hover cell.
	if battle.map.in_bounds(hover_cell):
		var rh := Rect2(ORIGIN + Vector2(hover_cell) * cell_px + Vector2(1, 1), Vector2(cell_px - 2, cell_px - 2))
		var hc := Color(0.85, 0.95, 1.0, 0.35)
		if hover_ship_id >= 0:
			var hs := battle.get_ship(hover_ship_id)
			if hs != null and hs.team == 1:
				hc = Color(1.0, 0.45, 0.35, 0.75)
		draw_rect(rh, hc, false, 1.5)


func _draw_ships() -> void:
	for g in ghosts:
		_draw_ghost(g)
	var order: Array[Ship] = []
	for s in battle.ships:
		if s.alive:
			order.append(s)
	order.sort_custom(func(a: Ship, b: Ship) -> bool:
		return float(visual_pos.get(a.id, Vector2.ZERO).y) < float(visual_pos.get(b.id, Vector2.ZERO).y))
	for s in order:
		_draw_ship(s)


static func hull_draw_scale(proto: PackedVector2Array, footprint: Vector2i, cell: float) -> Vector2:
	## Pure, testable geometry: how much a class silhouette is stretched to fill its
	## footprint. X spans the long axis (76% of the hull's length), Y is normalised
	## SEPARATELY so the drawn ship can never be wider than one cell - a uniform scale by
	## the length made a 1x4 battleship 74 px wide on a 46 px cell, i.e. 1.6 cells of visual
	## overhang on a hull the rules consider one cell wide.
	var half_len: float = 1.0
	var half_width: float = 1.0
	for p in proto:
		half_len = maxf(half_len, absf(p.x))
		half_width = maxf(half_width, absf(p.y))
	var span: float = float(maxi(footprint.x, footprint.y))
	return Vector2((span * cell * 0.38) / half_len, (cell * 0.40) / half_width)


static func hull_half_extent(proto: PackedVector2Array) -> Vector2:
	## Half extents of the local polygon, so a test can multiply by the scale above.
	var half := Vector2(1.0, 1.0)
	for p in proto:
		half.x = maxf(half.x, absf(p.x))
		half.y = maxf(half.y, absf(p.y))
	return half


func _draw_ship(s: Ship) -> void:
	var pos: Vector2 = visual_pos.get(s.id, ship_center(s))
	# Footprint-aware geometry. Every value below is expressed so that a 1x1 hull
	# keeps EXACTLY the numbers it always had: the `multi` branch is never taken for
	# a shipped class, and the 1x1 expressions are the original ones verbatim.
	var multi: bool = s.footprint != Vector2i.ONE
	var extent: Vector2i = FootprintRef.extent(s.footprint, s.orientation)
	var ring: float = cell_px * 0.44
	var ring_in: float = cell_px * 0.47
	var ring_out: float = cell_px * 0.53
	var hover_r: float = cell_px * 0.40
	var bracket: float = cell_px * 0.50
	var shield_r: float = cell_px * 0.46
	var aura_r: float = cell_px * 0.52
	var bar_w: float = 36.0
	var bar_dy: float = -cell_px * 0.60
	var glyph_angle: float = s.facing.angle()
	var done_dx: float = cell_px * 0.40
	var hull_scale: float = 1.0
	## Y scale is computed SEPARATELY. Scaling a hull uniformly by the length made every
	## capital ship wider than its own cell: the battleship polygon is y +/-10 and needed
	## x3.68 to span four cells, i.e. 74 px across a 46 px cell - 1.6 cells of visual
	## overhang on a hull the rules consider one cell wide. The mandate for M4 is explicit:
	## the drawn silhouette stays inside the footprint. A 1x1 hull keeps the old numbers.
	var hull_scale_y: float = 1.0
	var outline_w: float = 1.6
	if multi:
		var span: float = float(maxi(extent.x, extent.y))
		ring = span * cell_px * 0.5 + 4.0
		ring_in = ring + 2.0
		ring_out = ring + 6.0
		hover_r = ring
		bracket = span * cell_px * 0.5 + 3.0
		shield_r = span * cell_px * 0.5 + 2.0
		aura_r = span * cell_px * 0.5 + 5.0
		bar_w = float(extent.x) * cell_px - 10.0
		bar_dy = -float(extent.y) * cell_px * 0.5 - 10.0
		# Snap the hull to the grid AND align its bow with the footprint's long axis,
		# so a 2x3 hull reads as one long ship pointing along its own body. A 180°
		# rotation keeps the same cells (rectangle symmetry) but flips the bow, which
		# is exactly what the orientation value is for.
		#
		# M7B: the bow comes from `Ship.bow_vector()` - the same source the 1x1 path uses -
		# instead of `(orientation + long_axis)`. The old expression had no notion of which
		# WAY along the axis the ship points, so every multi-cell hull was drawn pointing
		# left, in both fleets.
		glyph_angle = s.bow_angle()
		# One silhouette scaled to the footprint's long axis: a big hull must not be a
		# tiny fighter lost inside a six-cell box.
		var scales: Vector2 = hull_draw_scale(
			HULL_SHAPES.get(s.ship_class, HULL_SHAPES["fighter"]), s.footprint, cell_px)
		hull_scale = scales.x
		hull_scale_y = scales.y
		outline_w = 1.6 / ((hull_scale + hull_scale_y) * 0.5)  # ~1.6 px on screen
		done_dx = float(extent.x) * cell_px * 0.5 - 4.0
	# M7B: on a large board the cells are 8 px, and a fixed 36 px bar is four cells of
	# clutter that also collides with the hull above it. Below 14 px cells the bar shrinks
	# with the footprint and moves INSIDE it, just above the bottom edge. Zoom is a camera
	# transform, so the bar grows with the rest of the board when the player zooms in.
	if cell_px < 14.0:
		bar_w = maxf(cell_px * 1.2, minf(bar_w, cell_px * float(extent.x) * 0.9))
		bar_dy = float(extent.y) * cell_px * 0.5 - 4.0
	var selected: bool = s.id == battle.selected_id
	var hovered: bool = s.id == hover_ship_id
	# Multi-cell hulls paint their footprint so the occupied geometry stays legible.
	# The FILL goes under the hull; the cell BORDERS are re-drawn on top after the
	# hull, otherwise a big silhouette covers them completely.
	if multi:
		var tint: Color = DefsRef.TEAM_COLORS[s.team]
		for c in s.cells():
			var rc := Rect2(ORIGIN + Vector2(c) * cell_px + Vector2(3, 3), Vector2(cell_px - 6, cell_px - 6))
			draw_rect(rc, Color(tint.r, tint.g, tint.b, 0.10))
	# Selection / target markers under the hull.
	if selected:
		var pulse: float = 0.6 + 0.4 * sin(time * 4.0)
		draw_arc(pos, ring, 0, TAU, 40, Color(0.55, 0.98, 1.0, 0.55 * pulse), 2.0, true)
		for i in range(4):
			var ang: float = time * 1.2 + float(i) * TAU / 4.0
			draw_line(pos + Vector2(cos(ang), sin(ang)) * ring_in, pos + Vector2(cos(ang), sin(ang)) * ring_out,
				Color(0.55, 0.98, 1.0, 0.8), 2.0)
	if hovered:
		draw_arc(pos, hover_r, 0, TAU, 32, Color(1, 1, 1, 0.35), 1.5, true)
	var in_range: bool = s.team == 1 and battle.selected_id >= 0 and attack_cells.has(s.cell)
	if in_range:
		var pulse2: float = 0.5 + 0.5 * sin(time * 6.0)
		var rr: float = bracket
		var colr := Color(1.0, 0.35, 0.30, 0.55 + 0.35 * pulse2)
		var corners: Array[Vector2] = [
			pos + Vector2(-rr, -rr), pos + Vector2(rr, -rr), pos + Vector2(rr, rr), pos + Vector2(-rr, rr),
		]
		for q in range(4):
			var aq: Vector2 = corners[q]
			var sx: float = 1.0 if q == 0 or q == 3 else -1.0
			var sy: float = 1.0 if q == 0 or q == 1 else -1.0
			draw_line(aq, aq + Vector2(9 * sx, 0), colr, 2.0)
			draw_line(aq, aq + Vector2(0, 9 * sy), colr, 2.0)
	# Shield bubble.
	if s.shield > 0.5:
		draw_arc(pos, shield_r, 0, TAU, 40, Color(0.45, 0.85, 1.0, 0.12 + 0.22 * s.shield_ratio()), 2.0, true)
	# Hull.
	var angle: float = glyph_angle
	draw_set_transform(pos, angle, Vector2(hull_scale, hull_scale_y))
	var shape: PackedVector2Array = HULL_SHAPES.get(s.ship_class, HULL_SHAPES["fighter"])
	var base: Color = DefsRef.TEAM_COLORS[s.team]
	var trim: Color = DefsRef.TEAM_TRIM[s.team]
	var dark: Color = DefsRef.TEAM_DARK[s.team]
	# Engine plume (animated).
	# M6: the engine pulse is gone from Fighter and Interceptor. Everything else keeps its
	# plume animation, which is a hull effect, not the swarm pulse the mandate banned.
	var pulses: bool = s.ship_class != "fighter" and s.ship_class != "interceptor"
	var plume: float = 8.0 if not pulses else 7.0 + 3.0 * sin(time * 9.0 + float(s.id))
	draw_circle(Vector2(-17, 0), plume * 0.55, Color(trim.r, trim.g, trim.b, 0.20))
	draw_circle(Vector2(-16, 0), plume * 0.32, Color(trim.r, trim.g, trim.b, 0.55))
	# Shadow silhouette.
	if (s.ship_class == "fighter" or s.ship_class == "interceptor") and not multi:
		# A Fighter is ONE unit on ONE cell, drawn as a small formation: leader ahead,
		# two wingmen trailing in a tight V, plus two faint contrails so the group reads
		# as a single flight. Purely visual - footprint, stats, targeting and AI are
		# untouched, and there are still no independently selectable craft.
		_draw_squadron(base, trim, dark, outline_w, s.id, String(s.ship_class))
	else:
		var shadow := PackedVector2Array()
		var shadow_k: float = 1.12 if not multi else 1.04
		for p in shape:
			shadow.append(p * shadow_k)
		draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.45))
		draw_colored_polygon(shape, base)
		# Inner plating.
		var inner := PackedVector2Array()
		for p in shape:
			inner.append(p * 0.62)
		draw_colored_polygon(inner, Color(dark.r, dark.g, dark.b, 1.0))
		draw_polyline(shape + PackedVector2Array([shape[0]]), trim, outline_w, true)
		# Class-specific details.
		match s.ship_class:
			"frigate":
				draw_rect(Rect2(Vector2(-10, -10.5), Vector2(9, 3)), Color(trim.r, trim.g, trim.b, 0.45))
				draw_rect(Rect2(Vector2(-10, 7.5), Vector2(9, 3)), Color(trim.r, trim.g, trim.b, 0.45))
				draw_circle(Vector2(8, 0), 3.2, Color(0.85, 0.98, 1.0, 0.95))
				draw_circle(Vector2(-4, 0), 2.0, trim)
			"cruiser":
				draw_circle(Vector2(3, -3.5), 3.4, Color(dark.r, dark.g, dark.b, 1.0))
				draw_circle(Vector2(3, 3.5), 3.4, Color(dark.r, dark.g, dark.b, 1.0))
				draw_circle(Vector2(3, -3.5), 1.6, trim)
				draw_circle(Vector2(3, 3.5), 1.6, trim)
				draw_circle(Vector2(11, 0), 3.0, Color(0.85, 0.98, 1.0, 0.9))
			"battleship":
				draw_rect(Rect2(Vector2(-14, -3), Vector2(24, 6)), Color(dark.r, dark.g, dark.b, 1.0))
				for i in range(3):
					var tx: float = -6.0 + 7.0 * float(i)
					draw_circle(Vector2(tx, -5.0), 3.0, Color(0.10, 0.12, 0.16, 1.0))
					draw_circle(Vector2(tx, 5.0), 3.0, Color(0.10, 0.12, 0.16, 1.0))
					draw_circle(Vector2(tx, -5.0), 1.3, trim)
					draw_circle(Vector2(tx, 5.0), 1.3, trim)
				draw_circle(Vector2(15, 0), 3.6, Color(0.85, 0.98, 1.0, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Footprint borders ON TOP of the hull: the six occupied cells stay readable even
	# where the silhouette covers them. Without this the outline sits under the hull
	# and a 2x3 ship simply hides its own geometry.
	if multi:
		var edge: Color = DefsRef.TEAM_COLORS[s.team]
		for c in s.cells():
			var rb := Rect2(ORIGIN + Vector2(c) * cell_px + Vector2(3, 3), Vector2(cell_px - 6, cell_px - 6))
			draw_rect(rb, Color(edge.r, edge.g, edge.b, 0.42), false, 1.0)
	# Action state (M7B): a hull with nothing left to do this round is dimmed and ringed in
	# grey, so the player can see at a glance which ships still have orders to give. Drawn
	# BEFORE the health bars, which must stay readable; and distinct from the selection
	# ring (cyan, animated) and from a destroyed hull (which is not drawn at all).
	if s.alive and s.action_state() == Ship.ACTION_DONE:
		if multi:
			for c2 in s.cells():
				draw_rect(Rect2(ORIGIN + Vector2(c2) * cell_px + Vector2(2, 2),
					Vector2(cell_px - 4, cell_px - 4)), Color(0.02, 0.04, 0.06, 0.38))
		else:
			draw_circle(pos, cell_px * 0.42, Color(0.02, 0.04, 0.06, 0.32))
		draw_arc(pos, ring, 0, TAU, 24, Color(0.58, 0.62, 0.66, 0.55), 1.0, true)
	# Status aura.
	if s.evading:
		draw_arc(pos, aura_r, time * 3.0, time * 3.0 + TAU * 0.6, 20, Color(0.75, 1.0, 0.85, 0.5), 1.5, true)
	# Health / shield bars.
	var bar_pos: Vector2 = pos + Vector2(-bar_w * 0.5, bar_dy)
	draw_rect(Rect2(bar_pos + Vector2(-1, -1), Vector2(bar_w + 2, 7)), Color(0.02, 0.03, 0.05, 0.85))
	var hull_col: Color = Color(0.35, 0.95, 0.55, 1.0)
	if s.hull_ratio() < 0.35:
		hull_col = Color(1.0, 0.35, 0.30, 1.0)
	elif s.hull_ratio() < 0.66:
		hull_col = Color(1.0, 0.78, 0.30, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * s.hull_ratio(), 2.0)), hull_col)
	draw_rect(Rect2(bar_pos + Vector2(0, 3), Vector2(bar_w * s.shield_ratio(), 2.0)), Color(0.40, 0.80, 1.0, 1.0))
	# Fired / done marker.
	if s.team == 0 and s.has_attacked:
		draw_circle(pos + Vector2(done_dx, -cell_px * 0.40), 3.0, Color(1.0, 0.55, 0.30, 0.9))


func _draw_ghost(g: Dictionary) -> void:
	var p: float = float(g["t"]) / float(g["dur"])
	var alpha: float = 1.0 - p
	var pos: Vector2 = g["pos"]
	var shape: PackedVector2Array = HULL_SHAPES.get(String(g["class"]), HULL_SHAPES["fighter"])
	var col: Color = DefsRef.TEAM_COLORS[int(g["team"])]
	draw_set_transform(pos, 0.0, Vector2.ONE + Vector2(0.35, 0.35) * p)
	draw_colored_polygon(shape, Color(col.r * 1.4, col.g * 1.2, col.b * 1.1, 0.35 * alpha))
	draw_polyline(shape + PackedVector2Array([shape[0]]), Color(1.0, 0.9, 0.7, 0.8 * alpha), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_effects() -> void:
	for e in effects:
		if float(e.get("delay", 0.0)) > 0.0:
			continue
		var p: float = clampf(float(e["t"]) / float(e["dur"]), 0.0, 1.0)
		match String(e["kind"]):
			"trail":
				draw_circle(e["pos"], 6.0 * (1.0 - p), Color(e["color"].r, e["color"].g, e["color"].b, 0.18 * (1.0 - p)))
			"shot":
				var head: Vector2 = (e["from"] as Vector2).lerp(e["to"], p)
				var col: Color = e["color"]
				if bool(e["beam"]):
					draw_line(e["from"], head, Color(col.r, col.g, col.b, 0.25), 7.0)
					draw_line(e["from"], head, Color(col.r, col.g, col.b, 0.95), 2.5)
					draw_circle(head, 4.0, Color(1, 1, 1, 0.9))
				else:
					draw_line(e["from"], head, Color(col.r, col.g, col.b, 0.35), 3.0)
					draw_circle(head, 2.2, Color(col.r + 0.25, col.g + 0.2, col.b + 0.15, 1.0))
			"hit":
				var r: float = 7.0 + 30.0 * p
				var c2: Color = e["color"]
				draw_arc(e["pos"], r, 0, TAU, 24, Color(c2.r, c2.g, c2.b, 0.65 * (1.0 - p)), 3.0 * (1.0 - p) + 0.5, true)
				if float(e.get("shield", 0.0)) > 0.0:
					draw_arc(e["pos"], r * 0.7, 0, TAU, 6, Color(0.45, 0.85, 1.0, 0.8 * (1.0 - p)), 2.0, true)
				for i in range(6):
					var ang: float = TAU * float(i) / 6.0 + p
					var dir := Vector2(cos(ang), sin(ang))
					draw_line(e["pos"] + dir * r * 0.4, e["pos"] + dir * r, Color(1.0, 0.95, 0.8, 0.6 * (1.0 - p)), 1.5)
			"text":
				var pos_t: Vector2 = e["pos"] + Vector2(-12, -26 - 26 * p)
				draw_string(ThemeDB.fallback_font, pos_t, String(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(e["color"].r, e["color"].g, e["color"].b, 1.0 - p * 0.8))
			"boom":
				var rng := RandomNumberGenerator.new()
				rng.seed = int(e.get("seed", 1)) + 17
				var pos2: Vector2 = e["pos"]
				draw_circle(pos2, 34.0 * p, Color(1.0, 0.75, 0.35, 0.5 * (1.0 - p)))
				draw_circle(pos2, 18.0 * p, Color(1.0, 0.95, 0.75, 0.75 * (1.0 - p)))
				draw_arc(pos2, 10.0 + 46.0 * p, 0, TAU, 30, Color(1.0, 0.55, 0.25, 0.9 * (1.0 - p)), 3.0, true)
				for i in range(14):
					var ang2: float = rng.randf_range(0, TAU)
					var speed: float = rng.randf_range(30, 78)
					var dir2 := Vector2(cos(ang2), sin(ang2))
					var start: Vector2 = pos2 + dir2 * (6.0 + 22.0 * p)
					var col2: Color = Color(1.0, rng.randf_range(0.55, 0.9), 0.35, 0.9 * (1.0 - p))
					draw_line(start, start + dir2 * (4.0 + 8.0 * p) + Vector2(0, 24.0 * p * p), col2, 2.0)
			"ring":
				var r3: float = 12.0 + 46.0 * p
				var c3: Color = e["color"]
				draw_arc(e["pos"], r3, 0, TAU, 32, Color(c3.r, c3.g, c3.b, 0.8 * (1.0 - p)), 2.5, true)
				draw_arc(e["pos"], r3 * 0.6, 0, TAU, 24, Color(c3.r, c3.g, c3.b, 0.4 * (1.0 - p)), 1.5, true)
			"flash":
				var alpha_f: float = 0.30 * (1.0 - p)
				draw_circle(e["pos"], cell_px * 0.9, Color(1.0, 1.0, 1.0, alpha_f))
