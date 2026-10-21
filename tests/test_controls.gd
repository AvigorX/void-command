extends SceneTree
## M7B — controls and navigation: rotation key, rotation safety, moving around hulls.
##
## Three questions the mandate asks and this suite answers against the real code:
##
##  1. Is rotation reachable from the keyboard at all? [R] recentres the camera (M6), and
##     the rotation action was still bound to R, so pressing R recentred and rotated
##     nothing. The binding is now T and the test drives the real `_unhandled_input`.
##  2. Does a refused rotation leave the hull untouched, and does a successful one report
##     it? Checked on the authoritative state, not on the message.
##  3. Are big hulls OBSTACLES rather than walls? A ship behind a 1x5 hull must be able to
##     go around it, must not be able to pass through it, and a genuinely sealed hull must
##     be refused with a route reason - the two cases are distinguished, not conflated.

const BattleScript = preload("res://scripts/core/battle.gd")
const ShipScript = preload("res://scripts/core/ship.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const BattleScreenScript = preload("res://scripts/ui/battle_screen.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var screen = null
var frames: int = 0
var done: bool = false


func _initialize() -> void:
	SaveGuard.isolate()
	print("=== VOID COMMAND — CONTROLS & NAVIGATION (M7B) ===")
	test_input_map()
	test_rotation_rules()
	test_movement_around_a_capital_hull()
	test_movement_keeps_the_orientation()
	test_sealed_hull_is_refused()
	screen = BattleScreenScript.new()
	root.add_child(screen)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if screen == null or screen.view == null:
		ok(false, "the battle screen built its view")
		_finish()
		return false
	if not done:
		done = true
		test_keyboard_bindings()
	_finish()
	return false


func _finish() -> void:
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	SaveGuard.cleanup()
	quit(0 if failures == 0 else 1)


# ------------------------------------------------------------------ input map ----

func test_input_map() -> void:
	begin("the rotation shortcut is T and R is free for the camera")
	ok(InputMap.has_action("rotate_cw"), "the rotate action exists")
	ok(InputMap.has_action("end_turn"), "the end-turn action exists")
	var codes: Array[int] = []
	for ev in InputMap.action_get_events("rotate_cw"):
		if ev is InputEventKey:
			codes.append(int((ev as InputEventKey).physical_keycode))
	ok(codes.has(KEY_T), "rotate_cw is bound to T (physical keycode %d)" % KEY_T)
	ok(not codes.has(KEY_R), "rotate_cw is NOT bound to R, which recentres the camera")
	var end_codes: Array[int] = []
	for ev2 in InputMap.action_get_events("end_turn"):
		if ev2 is InputEventKey:
			end_codes.append(int((ev2 as InputEventKey).physical_keycode))
	ok(end_codes.has(KEY_SPACE), "end_turn is still SPACE")


# ------------------------------------------------------------------- rotation ----

func test_rotation_rules() -> void:
	begin("rotation is free, validated and atomic")
	var b = BattleScript.new()
	b.setup(4, {}, 1, MapConfigRef.TITAN, ["cruiser"], ["fighter"])
	var s: Ship = b.alive_ships(0)[0]
	# Put it in the middle, on a clear patch, so the rotation is about the rules only.
	var centre := Vector2i(b.map.width / 2, b.map.height / 2)
	s.cell = centre
	s.move_points = s.max_move
	var before: Array = [s.cell, s.orientation, s.move_points, s.facing]
	var res: Dictionary = b.rotate_ship(s.id, (s.orientation + 1) % 4)
	ok(bool(res["ok"]), "a legal rotation is accepted: %s" % str(res.get("reason", "")))
	ok(s.orientation == (int(before[1]) + 1) % 4, "the orientation changed by one step")
	ok(s.cell == before[0], "rotation does not move the hull")
	ok(s.move_points == int(before[2]), "rotation costs no movement points")
	ok(s.cells().size() == 3, "the footprint still occupies three cells")
	# A refused rotation: the hull is on the bottom row and cannot stand up.
	s.cell = Vector2i(centre.x, b.map.height - 1)
	var snapshot: Array = [s.cell, s.orientation, s.move_points, s.facing]
	var refused: Dictionary = b.rotate_ship(s.id, 0)
	ok(not bool(refused["ok"]), "a rotation that would leave the grid is refused")
	ok(str([s.cell, s.orientation, s.move_points, s.facing]) == str(snapshot),
		"the refused rotation left cell, orientation, movement and facing untouched")
	ok(String(refused.get("reason", "")).length() > 0, "the refusal carries a reason: %s" % String(refused.get("reason", "")))
	# Rotating in place is not moving: `move_ship` must not report a move event.
	var events_before: int = b.events.size()
	s.cell = centre
	b.rotate_ship(s.id, (s.orientation + 1) % 4)
	var rotation_events: int = 0
	for i in range(events_before, b.events.size()):
		if String(b.events[i].get("type", "")) == "move" and int(b.events[i].get("cost", -1)) == 0:
			rotation_events += 1
	ok(rotation_events >= 1, "the rotation is recorded as a zero-cost order")


# --------------------------------------------------- moving around big hulls ----

func _open_battle(player: Array[String], enemy: Array[String]) -> Battle:
	## A battle on a cleared board: terrain would otherwise make the geometry random, and
	## these tests are about occupancy, not about the generator.
	var b = BattleScript.new()
	b.setup(2, {}, 1, MapConfigRef.TITAN, player, enemy)
	b.map.cells.fill(0)
	b.map.planet_anchors.clear()
	return b


func _place(b: Battle, class_id: String, team: int, cell: Vector2i, orientation: int = 0) -> Ship:
	var s: Ship = ShipScript.create(class_id, team, b._next_free_id(), 90 + b.ships.size())
	s.placed = true
	s.cell = cell
	s.orientation = orientation
	s.move_points = s.max_move
	b._add_ship(s)
	return s


func test_movement_around_a_capital_hull() -> void:
	begin("a capital hull is an obstacle, not a wall")
	var b := _open_battle([], [])
	# A friendly wall: 1x5 along the x axis at row 10, columns 20..24.
	var wall: Ship = _place(b, "dreadnought", 0, Vector2i(20, 10), 1)
	var runner: Ship = _place(b, "fighter", 0, Vector2i(22, 13), 0)
	# The detour is 13 cells (three to clear the hull, seven along it, three back): the
	# fixture gives the hull a movement budget larger than its class value on purpose, so
	# the test measures REACHABILITY and not the fighter's 5-point budget.
	runner.move_points = 16
	var wall_cells: Array[Vector2i] = wall.cells()
	ok(wall_cells.size() == 5, "the wall hull really occupies five cells")
	# Destination on the other side of the wall, same column.
	var dest := Vector2i(22, 6)
	var route: Dictionary = b.move_ship(runner.id, dest, runner.orientation)
	ok(bool(route["ok"]), "the fighter can reach the far side around the hull: %s" % str(route.get("reason", "")))
	ok(runner.cell == dest, "and it arrives there")
	var illegal: int = 0
	var path: Array = route.get("path", [])
	for step in path:
		if wall_cells.has(step):
			illegal += 1
	ok(illegal == 0, "the route never enters an occupied cell (%d violations, %d steps)" % [illegal, path.size()])
	# Going through the hull is refused, and nothing moves.
	var b2 := _open_battle([], [])
	var wall2: Ship = _place(b2, "dreadnought", 0, Vector2i(20, 10), 1)
	var runner2: Ship = _place(b2, "fighter", 0, Vector2i(22, 13), 0)
	runner2.move_points = 10
	var blocked: Dictionary = b2.move_ship(runner2.id, Vector2i(22, 10), runner2.orientation)
	ok(not bool(blocked["ok"]), "a destination inside a hull is refused")
	ok(runner2.cell == Vector2i(22, 13), "the refused order left the fighter where it was")


func test_movement_keeps_the_orientation() -> void:
	begin("a plain move does not rotate the hull by surprise")
	var b := _open_battle([], [])
	var s: Ship = _place(b, "cruiser", 0, Vector2i(40, 40), 1)   # horizontal
	s.move_points = 6
	var ori_before: int = s.orientation
	var res: Dictionary = b.move_ship(s.id, Vector2i(44, 40), s.orientation)
	ok(bool(res["ok"]), "the cruiser moves along its own axis: %s" % str(res.get("reason", "")))
	ok(s.orientation == ori_before, "the orientation is unchanged after a plain move")
	ok(int(res.get("turns", -1)) == 0, "no turn was spent on a straight move")
	# The other side of the contract: asking for a destination AT another orientation is a
	# deliberate turn-and-move, and it must report the turns it used.
	var b2 := _open_battle([], [])
	var s2: Ship = _place(b2, "cruiser", 0, Vector2i(40, 40), 1)
	s2.move_points = 6
	var res2: Dictionary = b2.move_ship(s2.id, Vector2i(40, 44), 0)
	ok(bool(res2["ok"]), "an ordered turn-and-move is accepted: %s" % str(res2.get("reason", "")))
	ok(s2.orientation == 0, "the hull arrives at the ordered orientation")
	ok(int(res2.get("turns", 0)) >= 1, "and the order reports that it turned (%d)" % int(res2.get("turns", 0)))


func test_sealed_hull_is_refused() -> void:
	begin("a sealed hull is a refusal, not a pathfinding defect")
	var b := _open_battle([], [])
	# A single free cell completely ringed by planets (Terrain.PLANET = 2).
	var cell := Vector2i(40, 40)
	_ring_planets(b, cell)
	var s: Ship = _place(b, "fighter", 0, cell, 0)
	s.move_points = 6
	var out: Dictionary = b.move_ship(s.id, Vector2i(cell.x + 2, cell.y), s.orientation)
	ok(not bool(out["ok"]), "the sealed hull cannot leave its cell")
	ok(String(out.get("reason", "")).find("No route") >= 0,
		"the reason names the route, not a generic failure: %s" % String(out.get("reason", "")))
	ok(s.cell == cell and s.move_points == 6, "the refusal mutated nothing")
	# Control: one cell over the hull is NOT sealed and moves normally, so the refusal
	# above cannot be a pathfinder that refuses everything.
	var b2 := _open_battle([], [])
	_ring_planets(b2, Vector2i(40, 40))
	var free_ship: Ship = _place(b2, "fighter", 0, Vector2i(42, 40), 0)
	free_ship.move_points = 6
	var out2: Dictionary = b2.move_ship(free_ship.id, Vector2i(44, 40), free_ship.orientation)
	ok(bool(out2["ok"]), "one cell over the hull moves normally: %s" % str(out2.get("reason", "")))


func _ring_planets(b: Battle, centre: Vector2i) -> void:
	## Planets (enum value 2) on the eight neighbours of `centre`, nothing else.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			b.map._put(Vector2i(centre.x + dx, centre.y + dy), 2)


# --------------------------------------------------------------- keyboard path ----

func test_keyboard_bindings() -> void:
	begin("pressing T rotates through the real input handler, R recentres")
	var b = BattleScript.new()
	b.setup(6, {}, 1, MapConfigRef.TITAN, ["cruiser"], ["fighter"])
	screen.battle = b
	screen.map_size = MapConfigRef.TITAN
	screen.view.setup(b)
	screen.hud.setup(b)
	var s: Ship = b.alive_ships(0)[0]
	s.cell = Vector2i(b.map.width / 2, b.map.height / 2)
	s.move_points = s.max_move
	b.select(s.id)
	var before: int = s.orientation
	# T: the rotate action, through `_unhandled_input`.
	var ev_t := InputEventKey.new()
	ev_t.physical_keycode = KEY_T
	ev_t.keycode = KEY_T
	ev_t.pressed = true
	screen._unhandled_input(ev_t)
	ok(s.orientation == (before + 1) % 4, "T rotated the selected hull (%d -> %d)" % [before, s.orientation])
	ok(String(screen.hud.status_text).length() > 0, "the HUD reported the rotation: %s" % screen.hud.status_text)
	# R: recentre must NOT rotate. Move the camera away first, then check both effects.
	screen.camera.position = Vector2(1.0, 1.0)
	var orientation_before: int = s.orientation
	var ev_r := InputEventKey.new()
	ev_r.physical_keycode = KEY_R
	ev_r.keycode = KEY_R
	ev_r.pressed = true
	screen._unhandled_input(ev_r)
	ok(s.orientation == orientation_before, "R did not rotate the hull")
	var play_centre: Vector2 = screen.PLAY_ORIGIN + screen.PLAY_AREA * 0.5
	ok(screen.camera.position.distance_to(play_centre) < 200.0,
		"R recentred the camera (%.0f,%.0f)" % [screen.camera.position.x, screen.camera.position.y])
	# Home still fits the board.
	var ev_home := InputEventKey.new()
	ev_home.keycode = KEY_HOME
	ev_home.physical_keycode = KEY_HOME
	ev_home.pressed = true
	screen._unhandled_input(ev_home)
	ok(screen.camera.zoom.x >= screen.ZOOM_MIN and screen.camera.zoom.x <= screen.ZOOM_MAX,
		"Home keeps the zoom legal (%.2f)" % screen.camera.zoom.x)


func begin(name: String) -> void:
	current = name
	print("- %s" % name)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  [%s] %s" % [current, label])
