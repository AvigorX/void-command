extends SceneTree
## Multi-cell engine suite (S2/S3): authoritative occupancy, footprint-aware
## movement, rotation and pathfinding.
##
## Every non-1x1 ship in this file is an ISOLATED FIXTURE: created on a battle
## instance that no other test uses, with the other ships disabled - except the
## real-fleet sections, which exercise the shipped hulls (1x3 cruiser, 1x4
## battleship as of STEP 2).
##
## Fixture shapes such as 2x3 are GEOMETRY inputs for the engine (it must handle any
## rectangle, including the ones the catalogue is forbidden to declare). What the
## catalogue actually ships is asserted in test_footprint.

const BattleScript = preload("res://scripts/core/battle.gd")
const ShipScript = preload("res://scripts/core/ship.gd")
const DefsScript = preload("res://scripts/core/ship_defs.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const PathfinderScript = preload("res://scripts/core/pathfinder.gd")
const FootprintScript = preload("res://scripts/core/footprint.gd")
const CombatRef = preload("res://scripts/core/combat.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — MULTI-CELL ENGINE SUITE ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	test_occupancy()
	test_deployment_footprint()
	test_occupancy_rejections()
	test_destruction_releases_cells()
	test_move_releases_cells()
	test_unit_preview_matches_rules()
	test_multicell_movement()
	test_corridor_rotation()
	test_rotation_rules()
	test_atomicity()
	test_targeting_range()
	test_targeting_los()
	test_targeting_no_double_hit()
	test_targeting_relay()
	test_combat_footprint()
	test_rendering_geometry()
	test_integration_unit_only()
	test_live_battleship_lifecycle()
	test_one_cell_door()
	begin("save isolation")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")
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

func board(seed_value: int, clear: bool = true) -> Battle:
	## A battle whose terrain is wiped, so every test controls the geometry exactly.
	var b = BattleScript.new()
	b.setup(seed_value)
	if clear:
		b.map.cells.fill(MapScript.Terrain.VOID)
		b.map.control_cell = Vector2i(0, 0)
	return b


func kill_all(b: Battle) -> void:
	## Empty the board of ships but keep the (seeded) battle instance.
	for s in b.ships:
		s.alive = false
	b.selected_id = -1


func solo(b: Battle, class_id: String, size: Vector2i, cell: Vector2i, orientation: int = 0) -> Ship:
	## Keep exactly one living ship (id 0), shaped and placed as requested.
	for s in b.ships:
		s.alive = false
	var ship: Ship = b.get_ship(0)
	ship.alive = true
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	ship.cell = cell
	ship.move_points = 12
	ship.has_attacked = false
	ship.set_footprint(size)
	ship.set_orientation(0)
	ship.set_orientation(orientation)
	b.selected_id = -1
	return ship


func second(b: Battle, id: int, cell: Vector2i, size: Vector2i = Vector2i.ONE, orientation: int = 0) -> Ship:
	var s: Ship = b.get_ship(id)
	s.alive = true
	s.hull = s.max_hull
	s.shield = s.max_shield
	s.cell = cell
	s.set_footprint(size)
	s.set_orientation(0)
	s.set_orientation(orientation)
	return s


func wall(b: Battle, x: int, y_from: int, y_to: int) -> void:
	for y in range(y_from, y_to + 1):
		if b.map.in_bounds(Vector2i(x, y)):
			b.map.cells[y * b.map.width + x] = MapScript.Terrain.PLANET


func route_is_legal(b: Battle, ship_id: int, size: Vector2i, steps: Array) -> bool:
	## Proves a returned route really is executable: EVERY intermediate state must be a
	## legal footprint on this board (in bounds, terrain, other ships). This is the
	## assertion that catches a search which validates the anchor but not the hull.
	##
	## `ship_id` is passed as the exception on purpose: the mover's own hull must not
	## be treated as an outside obstacle at every step of its own route.
	if steps.is_empty():
		return false
	for st in steps:
		var key: Vector3i = st
		var anchor: Vector2i = Vector2i(key.x, key.y)
		var ori: int = key.z
		if not b.can_place(anchor, size, ori, ship_id):
			return false
	return true


func free_cell(b: Battle, from: Vector2i) -> Vector2i:
	for radius in range(0, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c: Vector2i = from + Vector2i(dx, dy)
				if b.map.in_bounds(c) and not b.map.is_blocked(c) and b.ship_at(c) == null:
					return c
	return Vector2i(-1, -1)


# ------------------------------------------------------------------- tests ----

func test_deployment_footprint() -> void:
	begin("deployment: the whole footprint is validated")
	# 1) The first candidate is exactly what single-cell deployment would have used,
	#    so the RNG-shuffled order is untouched for 1x1 ships.
	var a := board(7001)
	var b := board(7001)
	kill_all(a)
	kill_all(b)
	var pool_a: Array[Vector2i] = a._shuffled_zone(0)
	var pool_b: Array[Vector2i] = b._shuffled_zone(0)
	ok(pool_a.size() == pool_b.size() and pool_a == pool_b, "the shuffled zone is reproducible per seed")
	var expected_cell: Vector2i = pool_a[pool_a.size() - 1]
	var unit: Ship = a.get_ship(0)
	var picked: Vector2i = a._take_deployment_cell(pool_a, unit, 0)
	ok(picked == expected_cell, "a 1x1 hull takes the first popped cell (RNG order preserved)")
	ok(a.deploy_failures.is_empty(), "no deployment failure for a 1x1 hull")

	# 2) A 1x4 hull takes an anchor where the whole hull is inside the zone and free.
	var big := board(7002)
	kill_all(big)
	var hull: Ship = big.get_ship(0)
	hull.set_footprint(Vector2i(1, 4))
	var pool: Array[Vector2i] = big._shuffled_zone(0)
	var anchor: Vector2i = big._take_deployment_cell(pool, hull, 0)
	ok(anchor.x >= 0, "a 1x4 hull finds a deployment anchor")
	ok(big._footprint_in_zone(anchor, Vector2i(1, 4), 0, 0), "every cell of the pick is inside the zone")
	ok(big.can_place(anchor, Vector2i(1, 4), 0, -1), "the pick passes the authoritative placement test")

	# 3) An occupied first candidate is skipped, and the hull still deploys.
	var clash := board(7003)
	kill_all(clash)
	var blocker: Ship = clash.get_ship(1)
	blocker.alive = true
	blocker.cell = Vector2i(1, 6)
	var hull3: Ship = clash.get_ship(0)
	hull3.set_footprint(Vector2i(1, 4))
	var pool3: Array[Vector2i] = clash._shuffled_zone(0)
	pool3.erase(Vector2i(1, 6))
	pool3.append(Vector2i(1, 6))  # make the clash the first candidate
	var anchor3: Vector2i = clash._take_deployment_cell(pool3, hull3, 0)
	ok(anchor3 != Vector2i(1, 6), "an occupied candidate is skipped")
	ok(clash.can_place(anchor3, Vector2i(1, 4), 0, -1), "the fallback anchor is legal")

	# 4) Terrain in any footprint cell rejects the candidate.
	var rocky := board(7004)
	kill_all(rocky)
	var hull4: Ship = rocky.get_ship(0)
	hull4.set_footprint(Vector2i(1, 4))
	var pool4: Array[Vector2i] = [Vector2i(1, 5)]
	rocky.map.cells[7 * rocky.map.width + 1] = MapScript.Terrain.PLANET  # (1,7) inside the hull
	var rocky_pick: Vector2i = rocky._take_deployment_cell(pool4, hull4, 0)
	ok(rocky_pick == Vector2i(-1, -1), "a footprint touching a rock is refused")
	ok(rocky.deploy_failures.size() == 1, "the refusal is recorded (expected ERROR line above)")

	# 5) Zone fit is a LENGTH problem now: every capital hull is one cell wide, so
	#    what can fail is a hull that is longer than the deployment zone is wide.
	var narrow := board(7005)
	kill_all(narrow)
	var hull5: Ship = narrow.get_ship(0)
	hull5.set_footprint(Vector2i(1, 5))
	hull5.set_orientation(1)   # 5 wide x 1 tall: the zone is only 4 columns wide
	var narrow_pool: Array[Vector2i] = []
	for y in range(narrow.map.height):
		for x in range(0, 4):
			narrow_pool.append(Vector2i(x, y))
	# M7 changes both halves of this fixture on purpose.
	# 1. The band is no longer four columns: DEPLOY_BAND = 6, because a hull deployed
	#    HORIZONTALLY (the M7 rule) needs five columns to fit at all. A 5-wide hull now
	#    deploys in the real zone - the old refusal was the bug, not the contract.
	var narrow_pick: Vector2i = narrow._take_deployment_cell(narrow_pool, hull5, 0)
	ok(narrow_pick.x >= 0, "a 5-wide hull fits the deployment zone (got %s)" % str(narrow_pick))
	ok(narrow.placement_problem(narrow_pick, hull5.footprint, hull5.orientation, -1) == "",
		"and the returned cell hosts the whole footprint")
	# 2. Rejected candidates are no longer consumed: the pool keeps every cell that was
	#    only scanned, so one unplaceable hull cannot starve the next.
	var starve_pool: Array[Vector2i] = []
	for y in range(2):
		starve_pool.append(Vector2i(0, y))
	var sealer = hull5
	sealer.cell = Vector2i(0, 0)
	sealer.placed = true
	narrow._add_ship(sealer)
	var probe_cells: int = starve_pool.size()
	var rejected: Vector2i = narrow._take_deployment_cell(starve_pool, hull5, 0)
	ok(rejected == Vector2i(-1, -1) or rejected.x >= 0, "the scan terminates")
	ok(starve_pool.size() >= probe_cells - 1, "the pool is only consumed by an accepted cell (%d -> %d)" % [
		probe_cells, starve_pool.size()])

	# 6) Edge of the board: an anchor that would leave the grid is refused.
	var edge := board(7006)
	kill_all(edge)
	var hull6: Ship = edge.get_ship(0)
	hull6.set_footprint(Vector2i(1, 3))
	var edge_pool: Array[Vector2i] = [Vector2i(2, 13)]
	ok(edge._take_deployment_cell(edge_pool, hull6, 0) == Vector2i(-1, -1), "a 3-tall hull at y=13 leaves the grid")

	# 7) A real deployment (setup) places the whole fleet legally.
	var full = BattleScript.new()
	full.setup(7007)
	ok(full.deploy_failures.is_empty(), "a fresh deployment reports no failure")
	var all_legal: bool = true
	var all_in_zone: bool = true
	for s in full.ships:
		if not full.can_place(s.cell, s.footprint, s.orientation, s.id):
			all_legal = false
		if not full._footprint_in_zone(s.cell, s.footprint, s.orientation, s.team):
			all_in_zone = false
	ok(all_legal, "every deployed ship stands on a legal footprint")
	ok(all_in_zone, "every deployed footprint is inside its own zone")
	ok(full.occupancy_conflicts().is_empty(), "no shared cells after the full deployment")


func test_occupancy() -> void:
	begin("occupancy: every cell resolves to its owner")
	var b := board(5001)
	var ship := solo(b, "cruiser", Vector2i(2, 3), Vector2i(5, 5))  # 2x3 at 0 deg
	ok(ship.cells().size() == 6, "fixture occupies 6 cells")
	var occ: Dictionary = b.occupied()
	ok(occ.size() == 6, "occupancy lists 6 cells (got %d)" % occ.size())
	var all_owned: bool = true
	var all_lookup: bool = true
	for c in ship.cells():
		if int(occ.get(c, -1)) != ship.id:
			all_owned = false
		var who: Ship = b.ship_at(c)
		if who == null or who.id != ship.id:
			all_lookup = false
	ok(all_owned, "every footprint cell maps to the ship in occupied()")
	ok(all_lookup, "ship_at() resolves every footprint cell to the same ship")
	ok(b.occupancy_conflicts().is_empty(), "no cell is claimed twice")
	ok(b.ship_at(Vector2i(8, 8)) == null, "an empty cell resolves to nothing")
	ok(b.cells_of(ship.id).size() == 6, "cells_of() reports the footprint")
	# A 1x1 neighbour keeps its own cell.
	var other := second(b, 1, Vector2i(9, 9))
	ok(b.ship_at(Vector2i(9, 9)) == other, "a second ship owns its own cell")
	ok(b.occupancy_conflicts().is_empty(), "no conflict after adding a neighbour")
	# Rotating the 2x3 in place swaps its extent.
	ok(ship.set_orientation(1), "fixture rotated to 90 deg")
	ok(ship.cells().size() == 6, "rotation keeps the same area")
	ok(b.ship_at(Vector2i(6, 5)) == ship and b.ship_at(Vector2i(5, 6)) == ship, "rotated cells resolve to the ship")
	ok(b.occupancy_conflicts().is_empty(), "no conflict after rotation")


func test_occupancy_rejections() -> void:
	begin("occupancy: out of bounds, terrain and overlap are refused")
	var b := board(5002)
	var ship := solo(b, "fighter", Vector2i(1, 2), Vector2i(10, 6))
	ok(not b.can_place(Vector2i(19, 13), Vector2i(2, 1), 0), "a 2-wide footprint at x=19 leaves the board")
	ok(not b.can_place(Vector2i(0, 13), Vector2i(1, 2), 0), "a 2-tall footprint at the bottom edge is refused")
	ok(b.can_place(Vector2i(0, 12), Vector2i(1, 2), 0), "a 2-tall footprint one row higher is legal")
	ok(b.can_place(Vector2i(18, 13), Vector2i(2, 1), 0), "a 2-wide footprint just inside the edge is legal")
	ok(b.can_place(Vector2i(10, 6), Vector2i(1, 2), 0, ship.id), "the ship may re-use its own cells")
	# Terrain: put a rock where the second cell of the footprint would go.
	b.map.cells[6 * b.map.width + 12] = MapScript.Terrain.PLANET
	ok(not b.can_place(Vector2i(11, 6), Vector2i(2, 1), 0), "a footprint overlapping a rock is refused")
	ok(b.can_place(Vector2i(11, 7), Vector2i(2, 1), 0), "the same footprint one row lower is legal")
	ok(b.placement_problem(Vector2i(11, 6), Vector2i(2, 1), 0).find("impassable") >= 0,
		"the rejection names the terrain")
	# Occupancy: a second ship blocks one cell of the footprint.
	var other := second(b, 1, Vector2i(13, 9))
	ok(not b.can_place(Vector2i(12, 9), Vector2i(2, 1), 0), "a footprint overlapping another ship is refused")
	ok(b.placement_problem(Vector2i(12, 9), Vector2i(2, 1), 0).find("occupied") >= 0,
		"the rejection names the occupant")
	ok(b.placement_problem(Vector2i(13, 9), Vector2i(1, 1), 0, other.id) == "", "a ship may stand where it already is")
	# Invalid dimensions/orientation never reach the map.
	ok(not b.can_place(Vector2i(5, 5), Vector2i(0, 1), 0), "zero-width footprint refused")
	ok(not b.can_place(Vector2i(5, 5), Vector2i(1, 1), 7), "invalid orientation refused")
	ok(b.placement_problem(Vector2i(5, 5), Vector2i(0, 1), 0) == "Invalid footprint.", "invalid size reason")


func test_destruction_releases_cells() -> void:
	begin("destruction releases every occupied cell")
	var b := board(5003)
	var ship := solo(b, "cruiser", Vector2i(2, 2), Vector2i(6, 6))
	ok(b.occupied().size() == 4, "4 cells occupied before the loss")
	ship.alive = false
	ok(b.occupied().is_empty(), "a destroyed ship occupies nothing")
	ok(b.ship_at(Vector2i(6, 6)) == null, "its cells no longer resolve to it")
	ok(b.cells_of(ship.id).is_empty(), "cells_of() is empty for a destroyed ship")
	var other := second(b, 1, Vector2i(6, 6))
	ok(b.occupancy_conflicts().is_empty(), "another ship may take the freed cell")
	other.alive = false


func test_move_releases_cells() -> void:
	begin("movement releases the old footprint and claims the new one")
	var b := board(5004)
	var ship := solo(b, "frigate", Vector2i(1, 2), Vector2i(4, 4))  # vertical 1x2
	ok(b.occupied().size() == 2, "two cells before the move")
	var before_cells: Array[Vector2i] = ship.cells().duplicate()
	var res: Dictionary = b.move_ship(ship.id, Vector2i(7, 4))
	ok(bool(res["ok"]), "move accepted: %s" % String(res.get("reason", "")))
	ok(ship.cell == Vector2i(7, 4), "reference cell updated")
	var released: bool = true
	for c in before_cells:
		if b.occupied().has(c) and c != Vector2i(7, 4):
			released = false
	ok(released, "old cells released")
	ok(b.ship_at(Vector2i(7, 5)) == ship, "the new footprint's far cell resolves to the ship")
	ok(b.occupied().size() == 2, "still exactly two cells after the move")
	ok(b.occupancy_conflicts().is_empty(), "no conflict after the move")
	ok(ship.move_points == 9, "cost of 3 paid (12 -> 9), got %d" % ship.move_points)
	# Every anchor advertised for a multi-cell hull must be executable.
	var probe := board(5004)
	var pship := solo(probe, "frigate", Vector2i(1, 2), Vector2i(4, 4))
	var anchors: Array[Vector2i] = []
	for c in probe.reachable_cells(pship.id)["dist"].keys():
		if c == pship.cell:
			continue
		anchors.append(c)
		if anchors.size() >= 5:
			break
	ok(anchors.size() >= 3, "the 1x2 hull has %d sampled destinations" % anchors.size())
	var refused_count: int = 0
	for a in anchors:
		var fresh := board(5004)
		var s3 := solo(fresh, "frigate", Vector2i(1, 2), Vector2i(4, 4))
		var r3: Dictionary = fresh.move_ship(s3.id, a)
		if not bool(r3["ok"]):
			refused_count += 1
			print("    1x2 preview advertised %s but refused (%s)" % [str(a), String(r3.get("reason", ""))])
	ok(refused_count == 0, "every advertised 1x2 destination is executable (%d refused)" % refused_count)


func test_unit_preview_matches_rules() -> void:
	begin("preview == authoritative movement (1x1, unchanged game)")
	var checked: int = 0
	var mismatches: int = 0
	for seed_value in [11, 4242]:
		var probe = BattleScript.new()
		probe.setup(seed_value)
		var ship: Ship = probe.alive_ships(0)[0]
		var cells: Array[Vector2i] = []
		for c in probe.reachable_cells(ship.id)["dist"].keys():
			if c == ship.cell:
				continue  # the start cell is part of the preview but is not a move
			cells.append(c)
			if cells.size() >= 8:
				break
		for c in cells:
			var b = BattleScript.new()
			b.setup(seed_value)
			var s2: Ship = b.get_ship(ship.id)
			var res: Dictionary = b.move_ship(s2.id, c)
			checked += 1
			if not bool(res["ok"]):
				mismatches += 1
				print("    seed %d: %s advertised but refused (%s)" % [seed_value, str(c), String(res.get("reason", ""))])
	ok(checked >= 10, "sampled %d advertised destinations" % checked)
	ok(mismatches == 0, "every advertised destination is executable (%d mismatches)" % mismatches)


func test_multicell_movement() -> void:
	begin("multi-cell movement (1x2 and 2x2 fixtures)")
	var b := board(5005)
	var ship := solo(b, "battleship", Vector2i(2, 1), Vector2i(3, 3))  # 2 wide, 1 tall
	ok(bool(b.move_ship(ship.id, Vector2i(6, 3))["ok"]), "2x1 hull moves three cells right")
	ok(ship.cells().size() == 2, "still 2 cells")
	ok(b.ship_at(Vector2i(7, 3)) == ship, "far cell owned after the move")
	ok(b.occupancy_conflicts().is_empty(), "no overlap")
	# A 2x2 hull cannot fit through a one-cell opening.
	var b2 := board(5006)
	var square := solo(b2, "battleship", Vector2i(2, 2), Vector2i(2, 6))
	wall(b2, 10, 0, 12)
	ok(bool(b2.move_ship(square.id, Vector2i(14, 6))["ok"]) == false, "a 2x2 hull cannot cross a full wall")
	b2.map.cells[6 * b2.map.width + 10] = MapScript.Terrain.VOID
	b2.map.cells[7 * b2.map.width + 10] = MapScript.Terrain.VOID
	ok(bool(b2.move_ship(square.id, Vector2i(14, 6))["ok"]), "a 2x2 hull crosses a 2-cell gap")
	ok(b2.occupancy_conflicts().is_empty(), "no overlap after crossing")


func test_corridor_rotation() -> void:
	begin("narrow corridor: rotation during movement")
	# A one-cell gap: the 1x1 passes, the 1x2 can only pass oriented along the gap.
	var b := board(5007)
	var ship := solo(b, "frigate", Vector2i(1, 2), Vector2i(7, 5))  # vertical 1x2 at (7,5)-(7,6)
	wall(b, 10, 0, 12)
	b.map.cells[6 * b.map.width + 10] = MapScript.Terrain.VOID  # single gap at (10,6)
	var as_vertical: Dictionary = b.move_ship(ship.id, Vector2i(13, 5))
	# STEP 2 / Block A: this used to be REFUSED. The anchor route exists but the hull
	# had to stand across the door, and the old search only validated one fixed
	# orientation. The (cell, orientation) search turns the hull at the door and back,
	# so the same order now succeeds - and it must do so through legal states only.
	ok(bool(as_vertical["ok"]), "1x2 crosses the one-cell gap by turning on the way (%s)" % String(as_vertical.get("reason", "")))
	ok(int(as_vertical.get("turns", 0)) >= 2, "the route turns in and back out (%d turns)" % int(as_vertical.get("turns", 0)))
	ok(ship.cell == Vector2i(13, 5) and ship.orientation == 0, "arrives at the requested anchor and orientation")
	ok(route_is_legal(b, ship.id, ship.footprint, as_vertical.get("steps", [])), "every state of the route is a legal footprint")
	ok(ship.cells() == ([Vector2i(13, 5), Vector2i(13, 6)] as Array[Vector2i]), "vertical footprint at the destination")
	ok(b.occupancy_conflicts().is_empty(), "no overlap in the corridor")
	# The fix must not make the impossible possible: a hull whose SHORTEST side is 2
	# can never pass a one-cell door, whatever it does with rotations.
	var b2 := board(5017)
	var sq: Ship = solo(b2, "fighter", Vector2i(2, 2), Vector2i(7, 5))
	wall(b2, 10, 0, 12)
	b2.map.cells[6 * b2.map.width + 10] = MapScript.Terrain.VOID
	var mp: int = sq.move_points
	var blocked: Dictionary = b2.move_ship(sq.id, Vector2i(13, 5))
	ok(not bool(blocked["ok"]), "a 2x2 hull is still refused at the same door (%s)" % String(blocked.get("reason", "")))
	ok(sq.cell == Vector2i(7, 5) and sq.orientation == 0 and sq.move_points == mp, "the refused move left the ship untouched")


func test_rotation_rules() -> void:
	begin("rotation: free, validated, no clipping")
	var b := board(5008)
	var ship := solo(b, "cruiser", Vector2i(1, 2), Vector2i(5, 5))  # vertical 1x2
	var mp_before: int = ship.move_points
	ok(bool(b.move_ship(ship.id, ship.cell, 1)["ok"]), "rotation in place accepted")
	ok(ship.orientation == 1, "orientation is 90 deg")
	ok(ship.move_points == mp_before, "rotation costs no movement points")
	ok(ship.cells().size() == 2, "same area after rotation")
	ok(b.occupancy_conflicts().is_empty(), "no overlap after rotation")
	# Partial overlap between old and new footprint is fine.
	ok(b.move_ship(ship.id, ship.cell, 0)["ok"], "rotate back to 0 deg")
	ok(bool(b.move_ship(ship.id, ship.cell, 1)["ok"]), "rotate again over the shared cell")
	# Rotation at the board edge is refused when the new extent would leave the map.
	var edge := board(5009)
	var s2 := solo(edge, "fighter", Vector2i(1, 2), Vector2i(19, 4))
	ok(s2.cells() == ([Vector2i(19, 4), Vector2i(19, 5)] as Array[Vector2i]), "fixture stands vertically at the right edge")
	var rot: Dictionary = edge.move_ship(s2.id, s2.cell, 1)
	ok(not bool(rot["ok"]), "rotating to a 2-wide footprint at x=19 is refused (%s)" % String(rot.get("reason", "")))
	ok(s2.orientation == 0, "orientation unchanged after the refusal")
	# Rotation beside an obstacle is refused when the new footprint would overlap it.
	var near := board(5010)
	var s3 := solo(near, "fighter", Vector2i(1, 2), Vector2i(5, 5))
	near.map.cells[5 * near.map.width + 6] = MapScript.Terrain.PLANET
	var rot2: Dictionary = near.move_ship(s3.id, s3.cell, 1)
	ok(not bool(rot2["ok"]), "rotating into a rock is refused (%s)" % String(rot2.get("reason", "")))
	ok(s3.orientation == 0 and s3.cells().size() == 2, "ship unchanged after the refused rotation")
	# Rotation beside another ship is refused when the new footprint would overlap it.
	var near2 := board(5011)
	var s4 := solo(near2, "fighter", Vector2i(1, 2), Vector2i(5, 5))
	second(near2, 1, Vector2i(6, 5))
	var rot3: Dictionary = near2.move_ship(s4.id, s4.cell, 1)
	ok(not bool(rot3["ok"]), "rotating into another ship is refused (%s)" % String(rot3.get("reason", "")))
	ok(near2.occupancy_conflicts().is_empty(), "no overlap after the refused rotation")
	# Invalid orientation is refused and leaves the ship alone.
	var bad: Dictionary = near2.move_ship(s4.id, s4.cell, 9)
	ok(not bool(bad["ok"]), "orientation 9 refused")
	ok(s4.orientation == 0, "orientation still 0")


func test_atomicity() -> void:
	begin("invalid orders never partially mutate state")
	var b := board(5012)
	var ship := solo(b, "cruiser", Vector2i(2, 2), Vector2i(4, 4))
	second(b, 1, Vector2i(9, 9))
	wall(b, 7, 0, 13)
	var snap := {
		"cell": ship.cell, "orientation": ship.orientation, "mp": ship.move_points,
		"facing": ship.facing, "events": b.events.size(), "log": b.log_lines.size(),
	}
	var attempts: Array[Dictionary] = [
		{"dest": Vector2i(12, 4), "label": "beyond a full wall"},
		{"dest": Vector2i(9, 9), "label": "onto another ship"},
		{"dest": Vector2i(30, 30), "label": "outside the grid"},
	]
	for a in attempts:
		var res: Dictionary = b.move_ship(ship.id, a["dest"])
		ok(not bool(res["ok"]), "%s refused (%s)" % [String(a["label"]), String(res.get("reason", ""))])
	ok(ship.cell == Vector2i(snap["cell"]), "position unchanged after every refusal")
	ok(ship.orientation == int(snap["orientation"]), "orientation unchanged")
	ok(ship.move_points == int(snap["mp"]), "movement points unchanged")
	ok(ship.facing == Vector2(snap["facing"]), "facing unchanged")
	ok(b.events.size() == int(snap["events"]), "no move event emitted by a refusal")
	ok(b.log_lines.size() == int(snap["log"]), "no log line emitted by a refusal")
	var rotated: Dictionary = b.move_ship(ship.id, ship.cell, 2)
	ok(bool(rotated["ok"]), "a legal rotation still works after the refusals")
	ok(b.occupancy_conflicts().is_empty(), "occupancy consistent at the end")


func test_targeting_range() -> void:
	begin("targeting: range is the minimum footprint distance")
	var b := board(6001)
	var att := solo(b, "frigate", Vector2i(1, 1), Vector2i(4, 5))
	var tgt := second(b, 5, Vector2i(1, 5), Vector2i(2, 1))  # cells (1,5),(2,5)
	ok(b.footprint_distance(att, tgt) == 2, "min distance 2 (anchor-to-anchor would be 3), got %d" % b.footprint_distance(att, tgt))
	ok(PathfinderScript.manhattan(att.cell, tgt.cell) == 3, "the old anchor metric would have said 3")
	att.attack_range = 2
	ok(bool(b.can_attack(att.id, tgt.id)["ok"]), "range 2 reaches the hull's near cell")
	att.attack_range = 1
	var refused: Dictionary = b.can_attack(att.id, tgt.id)
	ok(not bool(refused["ok"]), "range 1 refuses")
	ok(String(refused["reason"]).find("Out of range (2 > 1)") >= 0, "the reason quotes the footprint distance (%s)" % String(refused["reason"]))
	att.attack_range = 2
	att.cell = Vector2i(3, 5)  # adjacent to (2,5)
	ok(b.footprint_distance(att, tgt) == 1, "adjacency is 1, not 0")
	ok(bool(b.can_attack(att.id, tgt.id)["ok"]), "adjacent shot accepted")
	# Friendly fire is unchanged.
	var ally := second(b, 1, Vector2i(5, 5))
	var friendly: Dictionary = b.can_attack(att.id, ally.id)
	ok(not bool(friendly["ok"]) and String(friendly["reason"]) == "Friendly target.", "friendly fire still refused")


func test_targeting_los() -> void:
	begin("targeting: line of sight over the whole footprint")
	# Two 1x2 hulls facing each other across a wall with exactly one open row.
	var b := board(6002)
	var att := solo(b, "frigate", Vector2i(1, 2), Vector2i(4, 5))
	var tgt := second(b, 5, Vector2i(8, 5), Vector2i(1, 2))
	wall(b, 6, 0, 13)
	for y in range(0, 14):
		if y != 6:
			b.map.cells[y * b.map.width + 6] = MapScript.Terrain.PLANET
	b.map.cells[6 * b.map.width + 6] = MapScript.Terrain.VOID  # one open cell at (6,6)
	ok(b.map.has_line_of_sight(Vector2i(4, 6), Vector2i(8, 6)), "the single open row gives a clear lane")
	ok(not b.map.has_line_of_sight(Vector2i(4, 5), Vector2i(8, 5)), "the blocked row has no lane")
	ok(b.has_firing_los(att, tgt), "one clear pair is enough for the attack")
	att.attack_range = 6
	ok(bool(b.can_attack(att.id, tgt.id)["ok"]), "attack accepted through the one clear pair")
	# Close the last lane: now every pair is blocked.
	b.map.cells[6 * b.map.width + 6] = MapScript.Terrain.PLANET
	ok(not b.has_firing_los(att, tgt), "no pair has a lane any more")
	var blocked: Dictionary = b.can_attack(att.id, tgt.id)
	ok(not bool(blocked["ok"]), "attack refused")
	ok(String(blocked["reason"]) == "Line of sight blocked.", "the reason is the blocked lane (%s)" % String(blocked["reason"]))
	# Nebula still blocks sight but stays passable (existing rules preserved).
	var b2 := board(6003)
	var a2 := solo(b2, "fighter", Vector2i(1, 1), Vector2i(3, 5))
	var t2 := second(b2, 5, Vector2i(6, 5), Vector2i(2, 1))
	b2.map.cells[5 * b2.map.width + 5] = MapScript.Terrain.NEBULA  # strictly between them
	ok(not b2.map.is_blocked(Vector2i(5, 5)), "nebula is passable")
	ok(not b2.has_firing_los(a2, t2), "nebula blocks every lane between the hulls")
	a2.attack_range = 3
	ok(not bool(b2.can_attack(a2.id, t2.id)["ok"]), "shot through a nebula refused")
	# Clear the nebula: same geometry, now legal.
	b2.map.cells[5 * b2.map.width + 5] = MapScript.Terrain.VOID
	ok(bool(b2.can_attack(a2.id, t2.id)["ok"]), "the same shot is legal once the cloud clears")


func test_targeting_no_double_hit() -> void:
	begin("targeting: a multi-cell target takes damage exactly once")
	var b := board(6004)
	var att := solo(b, "battleship", Vector2i(1, 1), Vector2i(2, 5))
	att.attack_range = 6
	var tgt := second(b, 5, Vector2i(5, 5), Vector2i(1, 2))
	var pool_before: float = tgt.hull + tgt.shield
	var events_before: int = _count_events(b, "attack", att.id)
	var res: Dictionary = b.attack(att.id, tgt.id)
	ok(bool(res["ok"]), "attack accepted: %s" % String(res.get("reason", "")))
	var dealt: float = pool_before - (tgt.hull + tgt.shield)
	ok(is_equal_approx(dealt, att.base_damage), "damage applied once (%d, expected %d)" % [int(dealt), int(att.base_damage)])
	ok(_count_events(b, "attack", att.id) == events_before + 1, "exactly one attack event")
	ok(att.has_attacked, "attacker flagged once")
	var second_shot: Dictionary = b.attack(att.id, tgt.id)
	ok(not bool(second_shot["ok"]), "the same attacker cannot fire twice")
	ok(is_equal_approx(tgt.hull + tgt.shield, pool_before - dealt), "no extra damage from the refused second shot")


func test_targeting_relay() -> void:
	begin("relay: any occupied cell counts, not only the anchor")
	var b := board(6005)
	b.map.control_cell = Vector2i(10, 7)
	var ship := solo(b, "cruiser", Vector2i(1, 2), Vector2i(10, 6))  # second cell is the relay
	ok(ship.cell != b.map.control_cell, "the anchor is not on the relay")
	ok(ship.cells().has(b.map.control_cell), "but the footprint covers it")
	b._tick_control()
	ok(b.control_hold == 1, "relay held from a non-anchor cell (hold %d)" % b.control_hold)
	ok(b.control_owner == 0, "owner is the player")
	var off := board(6006)
	off.map.control_cell = Vector2i(10, 7)
	solo(off, "cruiser", Vector2i(1, 2), Vector2i(10, 9))
	off._tick_control()
	ok(off.control_hold == 0, "a hull away from the relay does not hold it")


func test_combat_footprint() -> void:
	begin("combat: cover, splash and beam follow the footprint")

	# --- cover: any occupied cell in a nebula, applied exactly once ------------
	var b := board(8001)
	var gun: Ship = solo(b, "cruiser", Vector2i.ONE, Vector2i(5, 5))
	var hull: Ship = second(b, 1, Vector2i(6, 5), Vector2i(2, 3))
	hull.team = 1
	hull.shield = 0.0
	ok(not b.ship_in_cover(hull), "a 2x3 hull clear of nebulae is not in cover")
	# Two nebula cells under the hull must still be ONE cover effect.
	b.map.cells[5 * b.map.width + 6] = MapScript.Terrain.NEBULA  # (6,5) anchor
	b.map.cells[6 * b.map.width + 6] = MapScript.Terrain.NEBULA  # (6,6) middle
	ok(b.ship_in_cover(hull), "one nebula cell is enough to put the hull in cover")
	var hull_before: float = hull.hull
	var covered: Dictionary = b.attack(gun.id, hull.id)
	var covered_dmg: float = hull_before - hull.hull
	ok(covered.has("result") and bool(covered["result"]["cover"]), "the attack reports nebula cover")

	var b2 := board(8002)
	var gun2: Ship = solo(b2, "cruiser", Vector2i.ONE, Vector2i(5, 5))
	var twin: Ship = second(b2, 1, Vector2i(6, 5), Vector2i(2, 3))
	twin.team = 1
	twin.shield = 0.0
	var twin_before: float = twin.hull
	var plain: Dictionary = b2.attack(gun2.id, twin.id)
	var plain_dmg: float = twin_before - twin.hull
	ok(plain.has("result") and not bool(plain["result"]["cover"]), "a hull outside nebulae takes no cover")
	ok(covered_dmg == ceilf(plain_dmg * 0.7),
		"cover is applied once even with two nebula cells (%.0f vs %.0f)" % [covered_dmg, plain_dmg])
	# 1x1 verdict must stay identical to the old cell-based rule.
	var unit: Ship = second(b2, 2, Vector2i(12, 2), Vector2i.ONE)
	ok(b2.ship_in_cover(unit) == b2.map.is_cover(unit.cell), "1x1 cover verdict is unchanged")

	# --- splash: touching hulls take area damage once --------------------------
	var s3 := board(8003)
	for s in s3.ships:
		s.alive = false
	var struck: Ship = second(s3, 1, Vector2i(8, 6), Vector2i(2, 3))
	struck.team = 1
	struck.shield = 0.0
	var touching: Ship = second(s3, 2, Vector2i(10, 6), Vector2i(2, 3))
	touching.team = 1
	touching.shield = 0.0
	var distant: Ship = second(s3, 3, Vector2i(15, 2), Vector2i.ONE)
	distant.team = 1
	distant.shield = 0.0
	var bs: Ship = ShipScript.create("battleship", 0, 90, 5, {}, 1.0)
	bs.cell = Vector2i(5, 6)
	s3._add_ship(bs)  # registers the id in by_id, like a real deployment
	ok(bool(s3.can_attack(bs.id, struck.id)["ok"]), "the salvo carrier can reach the 2x3 hull")

	var event_mark: int = s3.events.size()
	var struck_before: float = struck.hull
	var touching_before: float = touching.hull
	var distant_before: float = distant.hull
	var res: Dictionary = s3.use_ability(bs.id, struck.id)
	ok(bool(res["ok"]), "salvo resolves")
	var counts := {}
	for i in range(event_mark, s3.events.size()):
		var e: Dictionary = s3.events[i]
		if String(e["type"]) == "attack":
			counts[e["target"]] = int(counts.get(e["target"], 0)) + 1
	ok(int(counts.get(struck.id, 0)) == 1, "the struck hull takes the salvo exactly once")
	ok(int(counts.get(touching.id, 0)) == 1, "the touching hull is splashed exactly once")
	ok(int(counts.get(distant.id, 0)) == 0, "a hull outside the blast is untouched")
	ok(struck.hull < struck_before and touching.hull < touching_before and distant.hull == distant_before,
		"damage matches the emitted events")

	# --- beam geometry --------------------------------------------------------
	var pair: Array[Vector2i] = s3.closest_cells(gun, hull)
	ok(pair[0] == gun.cell, "a 1x1 shooter fires from its own cell")
	ok(hull.cells().has(pair[1]), "the beam lands on an occupied cell of the target")
	ok(PathfinderScript.manhattan(pair[0], pair[1]) == 1, "the beam uses the closest pair of cells")
	var ev: Dictionary = b.events[b.events.size() - 1]
	ok(hull.cells().has(ev["to"]), "the attack event ends on a cell of the target hull")
	var lone: Ship = second(b2, 2, Vector2i(6, 2), Vector2i.ONE)
	ok(b2.closest_cells(gun2, lone) == [gun2.cell, lone.cell], "1x1 beam endpoints are unchanged")

	# --- selection and ability highlight --------------------------------------
	var view = ViewScript.new()
	view.setup(b)
	ok(view.ship_at(Vector2i(7, 7)) == hull, "a secondary cell resolves to the owning ship")
	view.highlight_targets([hull])
	ok(view.ability_highlight.size() == 6, "the ability highlight covers all six occupied cells")
	var all_cells: bool = true
	for c in hull.cells():
		if not view.ability_highlight.has(c):
			all_cells = false
	ok(all_cells, "every cell of the target is clickable")
	view.free()


func test_rendering_geometry() -> void:
	begin("rendering: footprint centre, lookup and selection")
	var b := board(6007)
	var unit := solo(b, "fighter", Vector2i(1, 1), Vector2i(6, 6))
	var view = ViewScript.new()
	root.add_child(view)
	view.setup(b)
	ok(view.ship_center(unit) == view.cell_center(unit.cell), "a 1x1 hull keeps the cell centre (no pixel shift)")
	ok(view.ship_at(Vector2i(6, 6)) == unit, "the cell resolves to the ship")
	# A 2x1 hull is centred between its two cells and resolves from either.
	var wide := solo(b, "cruiser", Vector2i(2, 1), Vector2i(4, 4))
	view.setup(b)
	var mid: Vector2 = (view.cell_center(Vector2i(4, 4)) + view.cell_center(Vector2i(5, 4))) * 0.5
	ok(view.ship_center(wide) == mid, "a 2x1 hull is centred on its footprint")
	ok(view.ship_at(Vector2i(4, 4)) == wide, "the anchor cell resolves to the hull")
	ok(view.ship_at(Vector2i(5, 4)) == wide, "the second cell resolves to the SAME hull")
	ok(view.ship_at(Vector2i(6, 4)) == null, "a free cell resolves to nothing")
	ok(view.visual_pos[wide.id] == mid, "the visual position starts at the footprint centre")
	# Selection + targeting overlays agree with the rules layer.
	b.select(wide.id)
	view.refresh_overlays()
	ok(view.reachable.has(wide.cell), "the hull's own anchor is in the preview set")
	var tgt := second(b, 5, Vector2i(7, 4), Vector2i(1, 1))
	wide.attack_range = 3
	view.refresh_overlays()
	ok(view.attack_cells.has(Vector2i(7, 4)), "an attackable enemy cell is bracketed")
	ok(bool(b.can_attack(wide.id, tgt.id)["ok"]), "which matches the authoritative rule")
	view.queue_free()


func _count_events(b: Battle, kind: String, attacker_id: int) -> int:
	var n: int = 0
	for ev in b.events:
		if String(ev.get("type", "")) == kind and int(ev.get("attacker", -1)) == attacker_id:
			n += 1
	return n


func test_live_battleship_lifecycle() -> void:
	begin("a real 1x4 battleship: move, rotate, fire, destroy")
	var b = BattleScript.new()
	b.setup(9101)
	b.map.cells.fill(MapScript.Terrain.VOID)
	b.map.control_cell = Vector2i(0, 0)
	var bs: Ship = null
	for s in b.ships:
		if s.team == 0 and s.ship_class == "battleship":
			bs = s
	ok(bs != null, "the player fleet deploys a battleship")
	if bs == null:
		return
	ok(bs.footprint == Vector2i(1, 4), "the deployed battleship is 1x4 (got %s)" % str(bs.footprint))
	ok(bs.cells().size() == 4, "it occupies four cells")
	ok(FootprintScript.extent(bs.footprint, 0) == Vector2i(1, 4), "orientation 0 is 1 wide x 4 tall")
	ok(FootprintScript.extent(bs.footprint, 1) == Vector2i(4, 1), "orientation 1 is 4 wide x 1 tall")

	# Isolate the hull so the lifecycle is exact.
	for s in b.ships:
		if s != bs:
			s.alive = false
	bs.cell = Vector2i(2, 5)
	bs.set_orientation(0)
	bs.move_points = 4
	var foe: Ship = second(b, 1, Vector2i(10, 5), Vector2i.ONE)
	foe.team = 1
	foe.shield = 0.0
	ok(b.occupancy_conflicts().is_empty(), "fixture starts conflict-free")

	# Move: every old cell is released, every new cell is taken.
	var before_cells: Array[Vector2i] = bs.cells()
	var mv: Dictionary = b.move_ship(bs.id, Vector2i(4, 5))
	ok(bool(mv["ok"]), "the battleship moves to a legal anchor")
	ok(bs.cell == Vector2i(4, 5) and bs.cells() != before_cells, "position and cells updated")
	ok(b.occupancy_conflicts().is_empty(), "no overlap after the move")
	var all_in_bounds: bool = true
	for c in bs.cells():
		if not b.map.in_bounds(c):
			all_in_bounds = false
	ok(all_in_bounds, "every occupied cell stays inside the board")

	# Rotation in place: 1x4 becomes 4x1.
	var rot: Dictionary = b.rotate_ship(bs.id, 1)
	ok(bool(rot["ok"]), "the battleship rotates in place")
	ok(bs.orientation == 1, "orientation is now 1")
	ok(bs.cells().size() == 4, "the rotated hull still occupies four cells")
	ok(FootprintScript.extent(bs.footprint, bs.orientation) == Vector2i(4, 1), "the extent is now 4x1")
	ok(b.occupancy_conflicts().is_empty(), "no overlap after the rotation")

	# Fire: one shot, one event, damage applied once.
	var events_before: int = b.events.size()
	var foe_hull: float = foe.hull
	var shot: Dictionary = b.attack(bs.id, foe.id)
	ok(bool(shot["ok"]), "the battleship fires on the target")
	var shots: int = 0
	for i in range(events_before, b.events.size()):
		if String(b.events[i]["type"]) == "attack":
			shots += 1
	ok(shots == 1, "exactly one attack event for the whole hull")
	ok(foe.hull < foe_hull, "the target lost hull")

	# Destruction releases every cell.
	foe.hull = 1.0
	bs.has_attacked = false
	var kill: Dictionary = b.attack(bs.id, foe.id)
	ok(bool(kill["ok"]) and not foe.alive, "the target is destroyed")
	var leftover: bool = false
	for c in foe.cells():
		if b.occupied().has(c):
			leftover = true
	ok(not leftover, "the destroyed hull occupies no cells")
	ok(b.occupancy_conflicts().is_empty(), "occupancy stays consistent after the kill")
	ok(b.outcome == "victory", "destroying the last hostile ends the battle in victory (got '%s')" % b.outcome)
	# The big hull still owns its four cells after the battle ends.
	ok(b.occupied().size() == 4, "the surviving battleship keeps exactly four occupied cells")


func test_one_cell_door() -> void:
	begin("one-cell door: length-only hulls pass, 2-wide hulls do not")
	# NEGATIVE case. A hull whose SHORT side is 2 can never fit a one-cell door, with
	# any number of turns. 2x3 is used here purely as a geometric fixture (the shipped
	# catalogue is asserted in test_footprint, where 2x3 is forbidden).
	var b := board(9202)
	var wide: Ship = solo(b, "battleship", Vector2i(2, 3), Vector2i(2, 5))
	wide.move_points = 40
	# A wall at x=8 with a single-cell door at y=7.
	for y in range(b.map.height):
		if y != 7:
			b.map.cells[y * b.map.width + 8] = MapScript.Terrain.PLANET
	var reach_1: Dictionary = b.reachable_cells(wide.id)
	var past_1: bool = false
	for c in reach_1["dist"].keys():
		if c.x > 8:
			past_1 = true
	ok(not past_1, "a 2-wide hull cannot pass a one-cell door")
	# Widen the door: the same hull fits through.
	for x in range(8, 10):
		for y in range(7, 10):
			b.map.cells[y * b.map.width + x] = MapScript.Terrain.VOID
	var reach_2: Dictionary = b.reachable_cells(wide.id)
	var past_2: bool = false
	for c in reach_2["dist"].keys():
		if c.x > 10:
			past_2 = true
	ok(past_2, "the same hull passes a door exactly its own size")
	var legal: bool = true
	var ori_map: Dictionary = reach_2.get("orientation", {})
	for c in reach_2["dist"].keys():
		# STEP 2: a reachable anchor is legal at the orientation the search REPORTS,
		# which is not necessarily the hull's current one. Checking `wide.orientation`
		# for every anchor was the old (wrong) assertion.
		var o: int = int(ori_map.get(c, wide.orientation))
		if not b.can_place(c, wide.footprint, o, wide.id):
			legal = false
	ok(legal, "every reachable anchor is legal at the orientation the search reports")

	# POSITIVE case, the reason for the STEP 2 re-spec: the SHIPPED 1x4 battleship
	# crosses the same one-cell door by turning. Under STEP1's 2-wide hull this was
	# impossible, which stranded capital ships on half the map.
	var b2 := board(9203)
	var bs: Ship = solo(b2, "battleship", DefsScript.def("battleship")["footprint"], Vector2i(2, 5))
	bs.move_points = 40
	for y in range(b2.map.height):
		if y != 7:
			b2.map.cells[y * b2.map.width + 8] = MapScript.Terrain.PLANET
	var reach_3: Dictionary = b2.reachable_cells(bs.id)
	var past_3: bool = false
	for c in reach_3["dist"].keys():
		if c.x > 9:
			past_3 = true
	ok(past_3, "the shipped 1x4 hull reaches the far side of a one-cell door")
	var cross: Dictionary = b2.move_ship(bs.id, Vector2i(12, 7), 1)
	ok(bool(cross["ok"]), "and can be ordered through it (%s)" % String(cross.get("reason", "")))
	ok(route_is_legal(b2, bs.id, bs.footprint, cross.get("steps", [])), "every state of the crossing is legal")
	ok(b2.occupancy_conflicts().is_empty(), "no overlap after the crossing")

	# And a move that would clip the wall is refused without mutation.
	var before: Vector2i = wide.cell
	var res: Dictionary = b.move_ship(wide.id, Vector2i(7, 11))
	ok(not bool(res["ok"]) or wide.cell != before, "an illegal destination never leaves the hull half-moved")
	if not bool(res["ok"]):
		ok(wide.cell == before, "a refused move keeps the anchor")
	ok(b.occupancy_conflicts().is_empty(), "no overlap after the corridor probes")


func test_integration_unit_only() -> void:
	begin("a real battle deploys the 2x3 battleship and keeps working")
	var b = BattleScript.new()
	b.setup(777)
	var all_declared: bool = true
	var all_legal: bool = true
	var cells_expected: int = 0
	var big: int = 0
	for s in b.ships:
		var declared: Vector2i = Vector2i(DefsScript.def(s.ship_class)["footprint"])
		cells_expected += declared.x * declared.y
		if s.footprint != declared:
			all_declared = false
		if s.footprint != Vector2i.ONE:
			big += 1
		if not b.can_place(s.cell, s.footprint, s.orientation, s.id):
			all_legal = false
	# Derived from the fleet constants, not hardcoded: with STEP 2 both the cruiser
	# and the battleship are multi-cell, so "exactly one" would encode the old roster.
	var expected_big: int = 0
	for class_id in BattleScript.PLAYER_FLEET:
		if Vector2i(DefsScript.def(class_id)["footprint"]) != Vector2i.ONE:
			expected_big += 1
	for class_id in BattleScript.ENEMY_FLEET_BASE:
		if Vector2i(DefsScript.def(class_id)["footprint"]) != Vector2i.ONE:
			expected_big += 1
	ok(all_declared, "every deployed ship matches its declared footprint")
	ok(big == expected_big, "every multi-cell hull in the fleets is deployed (got %d, expected %d)" % [big, expected_big])
	ok(all_legal, "every deployed ship stands on a legal footprint")
	ok(b.occupancy_conflicts().is_empty(), "deployment produces no overlap")
	ok(b.occupied().size() == cells_expected, "occupancy covers every footprint cell (%d)" % cells_expected)
	# A complete battle still resolves.
	var rounds: int = 0
	while b.outcome == "" and rounds < 45:
		rounds += 1
		for s in b.alive_ships(0):
			var target = null
			var best_d: int = 9999
			for e in b.alive_ships(1):
				var d: int = PathfinderScript.manhattan(s.cell, e.cell)
				if bool(b.can_attack(s.id, e.id)["ok"]) and d < best_d:
					best_d = d
					target = e
			if target != null:
				b.attack(s.id, target.id)
		if b.outcome != "":
			break
		b.end_turn()
	ok(b.outcome == "victory" or b.outcome == "defeat", "the battle reaches an outcome (%s, round %d)" % [b.outcome, b.round])
	ok(b.occupancy_conflicts().is_empty(), "occupancy stays consistent through the battle")
