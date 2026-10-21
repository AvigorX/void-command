extends SceneTree
## STEP 2 / Block A — (cell, orientation) route search and footprint-aware AI.
##
## Every assertion here is about GAMEPLAY, not about the shape of the returned data:
## a route is legal iff every intermediate state really is a legal footprint, a
## destination is reachable iff `move_ship` accepts it, and an AI pick is correct iff
## the hull can actually execute it.
##
## The fixtures build their own footprints with `Ship.set_footprint()`, so this suite
## does not depend on which sizes the catalogue happens to ship today.

const BattleScript = preload("res://scripts/core/battle.gd")
const ShipScript = preload("res://scripts/core/ship.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const PathfinderScript = preload("res://scripts/core/pathfinder.gd")
const FootprintScript = preload("res://scripts/core/footprint.gd")
const AIRef = preload("res://scripts/core/ai.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — PATHFINDING / AI SUITE (STEP 2) ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	test_single_cell_unchanged()
	test_long_hull_routes()
	test_rotation_with_space()
	test_rotation_refused_in_corridor()
	test_anchor_free_hull_blocked()
	test_corridor_needs_the_right_orientation()
	test_edges()
	test_ai_destination_executable()
	test_ai_progress_no_loop()
	test_goal_reachability_over_turns()
	test_determinism()
	test_rotation_metric()
	test_route_metric_consistency()
	test_ai_avoids_blind_positions()
	test_save_isolation()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	SaveGuard.cleanup()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  [%s] %s" % [current, label])


func begin(name: String) -> void:
	current = name
	print("- %s" % name)


# ---------------------------------------------------------------- fixtures ----

func board(seed_value: int) -> Battle:
	var b = BattleScript.new()
	b.setup(seed_value)
	b.map.cells.fill(MapScript.Terrain.VOID)
	b.map.control_cell = Vector2i(0, 0)
	for s in b.ships:
		s.alive = false
	return b


func hull(b: Battle, id: int, size: Vector2i, cell: Vector2i, orientation: int = 0, mp: int = 12) -> Ship:
	var s: Ship = b.get_ship(id)
	s.alive = true
	s.hull = s.max_hull
	s.shield = s.max_shield
	s.cell = cell
	s.move_points = mp
	s.has_attacked = false
	s.set_footprint(size)
	s.set_orientation(0)
	s.set_orientation(orientation)
	return s


func wall_row(b: Battle, y: int, x_from: int, x_to: int) -> void:
	for x in range(x_from, x_to + 1):
		if b.map.in_bounds(Vector2i(x, y)):
			b.map.cells[y * b.map.width + x] = MapScript.Terrain.PLANET


func wall_col(b: Battle, x: int, y_from: int, y_to: int) -> void:
	for y in range(y_from, y_to + 1):
		if b.map.in_bounds(Vector2i(x, y)):
			b.map.cells[y * b.map.width + x] = MapScript.Terrain.PLANET


func route_legal(b: Battle, ship_id: int, size: Vector2i, steps: Array) -> bool:
	## The mover's own hull is the exception: it must never block its own route.
	if steps.is_empty():
		return false
	for st in steps:
		var key: Vector3i = st
		if not b.can_place(Vector2i(key.x, key.y), size, key.z, ship_id):
			return false
	return true


func snapshot_ship(s: Ship) -> Array:
	return [s.cell, s.orientation, s.move_points, s.facing, s.cells().size()]


# ------------------------------------------------------------------- tests ----

func test_single_cell_unchanged() -> void:
	begin("1x1 keeps the historical search exactly")
	var b := board(7001)
	var s := hull(b, 0, Vector2i.ONE, Vector2i(4, 4))
	s.move_points = 4
	var direct: Dictionary = PathfinderScript.explore(
		b.map, s.cell, s.move_points, b.occupied(s.id), Vector2i.ONE, 0)
	var via_battle: Dictionary = b.reachable_cells(s.id)
	ok(via_battle["dist"] == direct["dist"], "reachable_cells(dist) is identical to explore() for 1x1")
	ok(via_battle["prev"] == direct["prev"], "reachable_cells(prev) is identical to explore() for 1x1")
	ok(not via_battle.has("orientation"), "the 1x1 overlay carries no orientation map (unchanged shape)")
	# A 1x1 can face any of the four ways on any anchor (rotation is free and a 1x1
	# always fits), so its state space is exactly 4x the anchor set - no more, no less.
	var st: Dictionary = b.reachable_states(s.id)
	ok(int(st["dist"].size()) == int(direct["dist"].size()) * 4, "a 1x1 has 4 orientations per reachable anchor")
	var ori_ok: bool = true
	for a in direct["dist"].keys():
		for o in range(4):
			if not st["dist"].has(Vector3i(a.x, a.y, o)):
				ori_ok = false
	ok(ori_ok, "every reachable anchor of a 1x1 carries all four orientations")
	ok(s.cells() == ([s.cell] as Array[Vector2i]), "a 1x1 occupies exactly one cell")
	var mv: Dictionary = b.move_ship(s.id, Vector2i(6, 4))
	ok(bool(mv["ok"]) and int(mv["cost"]) == 2, "1x1 move costs Manhattan steps (2)")
	ok(mv["path"] == ([Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)] as Array[Vector2i]), "1x1 path is the legacy anchor path")


func test_long_hull_routes() -> void:
	begin("long hulls route on a free board")
	var cases: Array = [
		[Vector2i(1, 2), Vector2i(5, 5), Vector2i(5, 9), 4],
		[Vector2i(1, 3), Vector2i(5, 5), Vector2i(5, 10), 5],
		[Vector2i(1, 4), Vector2i(2, 2), Vector2i(2, 9), 7],
		[Vector2i(1, 5), Vector2i(3, 1), Vector2i(3, 8), 7],
	]
	for c in cases:
		var size: Vector2i = c[0]
		var from: Vector2i = c[1]
		var to: Vector2i = c[2]
		var expect: int = c[3]
		var b := board(7002 + int(size.y))
		var s := hull(b, 0, size, from, 0, 14)
		var mv: Dictionary = b.move_ship(s.id, to)
		ok(bool(mv["ok"]), "%s moves straight down the open board (%s)" % [str(size), String(mv.get("reason", ""))])
		ok(int(mv.get("cost", -1)) == expect, "%s costs %d translations (got %s)" % [str(size), expect, str(mv.get("cost"))])
		ok(route_legal(b, s.id, size, mv.get("steps", [])), "%s route states are all legal footprints" % str(size))
		ok(s.cell == to and s.cells().size() == size.x * size.y, "%s arrives with its full footprint" % str(size))
		ok(b.occupancy_conflicts().is_empty(), "%s left no overlap behind" % str(size))


func test_rotation_with_space() -> void:
	begin("rotation: allowed when the hull fits, costs nothing")
	var b := board(7010)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(5, 5), 0, 0)
	var mp: int = s.move_points
	var rot: Dictionary = b.rotate_ship(s.id, 1)
	ok(bool(rot["ok"]), "1x4 turns to 4x1 in the open (%s)" % String(rot.get("reason", "")))
	ok(s.orientation == 1, "orientation is 90 deg")
	ok(s.move_points == mp, "the turn consumed no movement points")
	ok(s.cells() == ([Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5)] as Array[Vector2i]),
		"the 4x1 footprint has the same area on the other axis")
	ok(b.occupancy_conflicts().is_empty(), "no overlap after the turn")
	# Turning back must be symmetric.
	ok(bool(b.rotate_ship(s.id, 0)["ok"]), "turning back to 0 deg is accepted")
	ok(s.cells().size() == 4, "same number of occupied cells")


func test_rotation_refused_in_corridor() -> void:
	begin("rotation: refused in a corridor narrower than the rotated hull")
	var b := board(7011)
	# A one-cell-wide vertical corridor at x=5.
	wall_col(b, 4, 0, 13)
	wall_col(b, 6, 0, 13)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(5, 3), 0, 3)
	ok(s.cells().size() == 4, "the hull stands vertically in the corridor")
	var before: Array = snapshot_ship(s)
	var rot: Dictionary = b.rotate_ship(s.id, 1)
	ok(not bool(rot["ok"]), "rotating to a 4-wide footprint is refused (%s)" % String(rot.get("reason", "")))
	ok(snapshot_ship(s) == before, "the refused rotation changed nothing")
	# It can still travel ALONG the corridor.
	var mv: Dictionary = b.move_ship(s.id, Vector2i(5, 6))
	ok(bool(mv["ok"]), "a 1-wide hull still moves along a 1-wide corridor (%s)" % String(mv.get("reason", "")))
	ok(int(mv.get("turns", 0)) == 0, "no turn was needed along the corridor")


func test_anchor_free_hull_blocked() -> void:
	begin("an anchor can be free while the hull collides")
	var b := board(7012)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(5, 0), 0, 8)
	b.map.cells[4 * b.map.width + 5] = MapScript.Terrain.PLANET   # (5,4) blocks the hull
	ok(not b.map.is_blocked(Vector2i(5, 3)), "the destination anchor itself is free")
	ok(not b.can_place(Vector2i(5, 3), s.footprint, 0, s.id), "the whole 1x4 footprint does not fit there")
	var before: Array = snapshot_ship(s)
	var mv: Dictionary = b.move_ship(s.id, Vector2i(5, 3))
	ok(not bool(mv["ok"]), "the move is refused on the hull, not on the anchor (%s)" % String(mv.get("reason", "")))
	ok(snapshot_ship(s) == before, "nothing was partially applied")
	ok(b.occupancy_conflicts().is_empty(), "no overlap after the refusal")


func test_corridor_needs_the_right_orientation() -> void:
	begin("corridor passable only at one orientation")
	var b := board(7013)
	# A one-tall horizontal corridor at y=5 from x=5 to x=15.
	wall_row(b, 4, 5, 15)
	wall_row(b, 6, 5, 15)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(2, 2), 0, 20)
	ok(b.can_place(Vector2i(2, 2), s.footprint, 0, s.id), "the hull starts in the open, standing up")
	var inside := Vector2i(10, 5)
	ok(not b.can_place(inside, s.footprint, 0, s.id), "it cannot stand vertically inside the corridor")
	ok(b.can_place(inside, s.footprint, 1, s.id), "it fits horizontally inside the corridor")
	var reach: Dictionary = b.reachable_cells(s.id)
	ok(reach["dist"].has(inside), "the corridor is reachable at all")
	ok(int(reach["orientation"].get(inside, -1)) == 1, "and only at 90 deg, as the search reports")
	var mv: Dictionary = b.move_ship(s.id, inside, 1)
	ok(bool(mv["ok"]), "the move into the corridor is accepted (%s)" % String(mv.get("reason", "")))
	ok(int(mv.get("turns", 0)) >= 1, "the route contains the turn (%d)" % int(mv.get("turns", 0)))
	ok(route_legal(b, s.id, s.footprint, mv.get("steps", [])), "every state of the corridor route is legal")
	ok(b.occupancy_conflicts().is_empty(), "no clipping through the corridor walls")


func test_edges() -> void:
	begin("navigation along the board edges")
	var b := board(7014)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(0, 0), 0, 6)
	ok(s.cells() == ([Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)] as Array[Vector2i]),
		"the hull fits in the top-left corner")
	var reach: Dictionary = b.reachable_cells(s.id)
	var all_inside: bool = true
	var ori_map: Dictionary = reach.get("orientation", {})
	for c in reach["dist"].keys():
		var anchor: Vector2i = c
		for cc in FootprintScript.cells(anchor, s.footprint, int(ori_map.get(anchor, s.orientation))):
			if not b.map.in_bounds(cc):
				all_inside = false
	ok(all_inside, "every reachable anchor keeps the whole footprint inside the board")
	# Sliding down the left column must work; leaving the board must not.
	var mv: Dictionary = b.move_ship(s.id, Vector2i(0, 4))
	ok(bool(mv["ok"]), "the hull slides down the edge (%s)" % String(mv.get("reason", "")))
	ok(not bool(b.move_ship(s.id, Vector2i(-1, 4))["ok"]), "an anchor outside the board is refused")
	# A hull that would stick out of the bottom edge cannot be placed there.
	var b2 := board(7015)
	var s2 := hull(b2, 0, Vector2i(1, 4), Vector2i(3, 9), 1, 6)
	ok(b2.can_place(Vector2i(3, 10), s2.footprint, 0, s2.id) == true, "1x4 at y=10 fits (rows 10..13)")
	var out: Dictionary = b2.move_ship(s2.id, Vector2i(3, 11), 0)
	ok(not bool(out["ok"]), "1x4 at y=11 would leave the board and is refused (%s)" % String(out.get("reason", "")))


func test_ai_destination_executable() -> void:
	begin("AI destination is executable for the whole footprint")
	var b := board(7020)
	var target := hull(b, 0, Vector2i.ONE, Vector2i(12, 6))
	target.team = 0
	var enemy := hull(b, 5, Vector2i(1, 4), Vector2i(1, 5), 0, 3)
	enemy.team = 1
	# A rock wall with a two-cell gap forces a real route decision.
	wall_col(b, 8, 0, 4)
	wall_col(b, 8, 7, 13)
	b.phase = Battle.Phase.ENEMY
	var pick: Dictionary = AIRef._choose_destination(b, enemy, target)
	var cell: Vector2i = pick.get("cell", Vector2i(-1, -1))
	var ori: int = int(pick.get("orientation", -1))
	ok(cell != Vector2i(-1, -1), "the AI produced a destination")
	ok(b.can_place(cell, enemy.footprint, ori, enemy.id), "the destination hosts the whole footprint")
	ok(cell != enemy.cell or ori != enemy.orientation, "the AI decided to move")
	var mv: Dictionary = b.move_ship(enemy.id, cell, ori)
	ok(bool(mv["ok"]), "move_ship accepts the AI's pick (%s)" % String(mv.get("reason", "")))
	ok(b.occupancy_conflicts().is_empty(), "no overlap after the AI move")


func test_ai_progress_no_loop() -> void:
	begin("AI never loops without progress")
	var b := board(7021)
	var target := hull(b, 0, Vector2i.ONE, Vector2i(14, 6))
	target.team = 0
	target.max_hull = 100000.0
	target.hull = 100000.0
	var enemy := hull(b, 5, Vector2i(1, 4), Vector2i(1, 6), 0, 3)
	enemy.team = 1
	enemy.attack_range = 0   # never in range: the only way to end is to keep closing in
	b.phase = Battle.Phase.ENEMY
	var visited: Dictionary = {}
	var moves: int = 0
	var repeated: bool = false
	var start_dist: int = b.footprint_distance(enemy, target)
	for step in range(10):
		var before_cell: Vector2i = enemy.cell
		var before_ori: int = enemy.orientation
		AIRef.take_turn(b)
		var state := Vector3i(enemy.cell.x, enemy.cell.y, enemy.orientation)
		if enemy.cell != before_cell or enemy.orientation != before_ori:
			moves += 1
			if visited.has(state):
				repeated = true
			visited[state] = true
		enemy.move_points = enemy.max_move
	ok(moves > 0, "the AI actually moved (%d moves)" % moves)
	ok(not repeated, "no state was revisited: the AI cannot ping-pong")
	ok(b.footprint_distance(enemy, target) < start_dist, "the AI closed the distance (%d -> %d)" %
		[start_dist, b.footprint_distance(enemy, target)])


func test_goal_reachability_over_turns() -> void:
	begin("a firing position is reached over several turns")
	var b := board(7022)
	var target := hull(b, 0, Vector2i.ONE, Vector2i(15, 5))
	target.team = 0
	target.hull = 100000.0
	target.max_hull = 100000.0
	var enemy := hull(b, 5, Vector2i(1, 4), Vector2i(1, 5), 0, 2)
	enemy.team = 1
	enemy.attack_range = 6
	b.phase = Battle.Phase.ENEMY
	var fired: bool = false
	var last_dist: int = b.footprint_distance(enemy, target)
	var monotone: bool = true
	for step in range(12):
		# Shields absorb before the hull, so "did it fire" must watch the TOTAL.
		var before_total: float = target.hull + target.shield
		AIRef.take_turn(b)
		var d: int = b.footprint_distance(enemy, target)
		if d > last_dist and target.hull + target.shield >= before_total:
			monotone = false
		last_dist = d
		if target.hull + target.shield < before_total:
			fired = true
			break
		enemy.move_points = enemy.max_move
	ok(fired, "the AI eventually fires from a real firing position")
	ok(monotone, "the distance to the target never grows back without damage dealt")


func test_determinism() -> void:
	begin("determinism of the state search")
	var a := board(7030)
	var sa := hull(a, 5, Vector2i(1, 4), Vector2i(2, 4), 0, 5)
	sa.team = 1
	wall_col(a, 7, 0, 5)
	wall_col(a, 7, 8, 13)
	var first: Dictionary = a.reachable_states(sa.id)
	var b := board(7030)
	var sb := hull(b, 5, Vector2i(1, 4), Vector2i(2, 4), 0, 5)
	sb.team = 1
	wall_col(b, 7, 0, 5)
	wall_col(b, 7, 8, 13)
	var second: Dictionary = b.reachable_states(sb.id)
	ok(first["dist"] == second["dist"], "same board + same hull => identical distance map")
	var k1: Array = first["dist"].keys()
	var k2: Array = second["dist"].keys()
	ok(k1 == k2, "identical key order (deterministic expansion)")
	var c := board(7030)
	var sc := hull(c, 5, Vector2i(1, 4), Vector2i(2, 4), 0, 14)
	sc.team = 0
	wall_col(c, 7, 0, 5)
	wall_col(c, 7, 8, 13)
	var r1: Dictionary = c.move_ship(sc.id, Vector2i(9, 4), 1)
	ok(bool(r1["ok"]), "the reference move is accepted")
	var s1: Array = r1.get("steps", [])
	var d := board(7030)
	var sd2 := hull(d, 5, Vector2i(1, 4), Vector2i(2, 4), 0, 14)
	sd2.team = 0
	wall_col(d, 7, 0, 5)
	wall_col(d, 7, 8, 13)
	var r2: Dictionary = d.move_ship(sd2.id, Vector2i(9, 4), 1)
	ok(s1 == r2.get("steps", []), "same order => byte-identical route")


func test_save_isolation() -> void:
	begin("save isolation")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")

# ------------------------------------------------- STEP 2.1 regressions ----

func test_rotation_metric() -> void:
	begin("rotation metric: counted and comparable, never charged")
	# 1x4 lying flat (4 wide x 1 tall) on an empty board.
	var b := board(7040)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(4, 4), 1, 10)
	var states: Dictionary = b.reachable_states(s.id)
	ok(states.has("turns"), "the search reports a turns map")
	var goal := PathfinderScript.state_key(Vector2i(6, 4), 1)
	ok(states["dist"].has(goal), "a straight translation is reachable")
	ok(int(states["turns"].get(goal, 99)) == 0,
		"a straight route needs no turn (got %d)" % int(states["turns"].get(goal, 99)))
	ok(int(states["dist"].get(goal, 99)) == 2, "it costs 2 translations (got %d)" % int(states["dist"].get(goal, 99)))
	# Rotation in place: 0 translations, 1 turn.
	var rot := PathfinderScript.state_key(Vector2i(4, 4), 0)
	ok(states["dist"].has(rot), "an in-place rotation is a reachable state")
	ok(int(states["dist"][rot]) == 0, "rotation costs 0 translations")
	ok(int(states["turns"][rot]) == 1, "rotation counts as 1 turn (got %d)" % int(states["turns"][rot]))
	# The same anchor at the same orientation is also reachable by turning twice and
	# coming back; the lexicographic cost must still report the zero-turn route.
	ok(int(states["turns"][goal]) == 0, "among equal distances the fewer-turns route wins")


func test_route_metric_consistency() -> void:
	begin("the reported metrics match the route actually committed")
	var b := board(7041)
	var s := hull(b, 0, Vector2i(1, 4), Vector2i(2, 5), 0, 14)
	wall_col(b, 8, 0, 4)
	wall_col(b, 8, 7, 13)
	var states: Dictionary = b.reachable_states(s.id)
	var start := PathfinderScript.state_key(s.cell, s.orientation)
	# Every reachable state must agree with its own reconstructed route, on both
	# components. This is the assertion that would catch a search that reports a
	# distance it cannot deliver.
	var mismatches: int = 0
	var turned_routes: int = 0
	for key in states["dist"].keys():
		var st: Vector3i = key
		var path: Array[Vector3i] = PathfinderScript.build_state_path(states["prev"], start, st)
		if path.is_empty() and st != start:
			mismatches += 1
			continue
		if PathfinderScript.state_path_cost(path) != int(states["dist"][st]):
			mismatches += 1
		if PathfinderScript.state_path_rotations(path) != int(states["turns"][st]):
			mismatches += 1
		if int(states["turns"][st]) > 0:
			turned_routes += 1
	ok(mismatches == 0, "dist and turns agree with every rebuilt route (%d mismatches)" % mismatches)
	ok(turned_routes > 0, "the fixture really contains routes with turns (%d states)" % turned_routes)
	# A committed move reports the same numbers the search promised.
	var mv: Dictionary = b.move_ship(s.id, Vector2i(10, 6), 1)
	ok(bool(mv["ok"]), "the roundabout order is accepted (%s)" % String(mv.get("reason", "")))
	ok(int(mv.get("turns", -1)) == PathfinderScript.state_path_rotations(mv.get("steps", [])),
		"the move event reports the same turn count it committed")


func test_ai_avoids_blind_positions() -> void:
	begin("AI does not park blind behind a nebula")
	var b := board(7042)
	var ai := hull(b, 5, Vector2i.ONE, Vector2i(4, 7), 0, 8)
	ai.team = 1
	ai.attack_range = 2
	var tgt := hull(b, 0, Vector2i.ONE, Vector2i(10, 7))
	tgt.team = 0
	tgt.max_hull = 100000.0
	tgt.hull = 100000.0
	# A nebula exactly on the straight lane at (9,7). The closest cell (8,7) is then
	# BLIND, while (9,6) keeps a clear diagonal and is still inside range 2.
	b.map.cells[7 * b.map.width + 9] = MapScript.Terrain.NEBULA
	b.phase = Battle.Phase.ENEMY
	var blind_cells: Array[Vector2i] = FootprintScript.cells(Vector2i(8, 7), Vector2i.ONE, 0)
	ok(not b.cells_have_los_to(blind_cells, tgt), "fixture: the closest cell really is blind")
	var sighted_cells: Array[Vector2i] = FootprintScript.cells(Vector2i(9, 6), Vector2i.ONE, 0)
	ok(b.cells_have_los_to(sighted_cells, tgt), "fixture: a sighted firing cell really exists")
	var states: Dictionary = b.reachable_states(ai.id)
	ok(states["dist"].has(PathfinderScript.state_key(Vector2i(8, 7), 0)),
		"fixture: the blind cell was reachable, so the test is meaningful")
	var pick: Dictionary = AIRef._choose_destination(b, ai, tgt)
	var chosen := Vector2i(pick.get("cell", Vector2i(-1, -1)))
	var chosen_ori: int = int(pick.get("orientation", 0))
	var chosen_cells: Array[Vector2i] = FootprintScript.cells(chosen, ai.footprint, chosen_ori)
	ok(b.cells_have_los_to(chosen_cells, tgt),
		"the AI picks a state with a firing lane, not the blind cell (chose %s)" % str(chosen))
	ok(b.cells_distance_to(chosen_cells, tgt) <= ai.attack_range,
		"and the chosen state is actually inside weapon range")
	# The order really is executable through the authoritative layer.
	var mv: Dictionary = b.move_ship(ai.id, chosen, chosen_ori)
	ok(bool(mv["ok"]), "the AI's pick is accepted by move_ship (%s)" % String(mv.get("reason", "")))
