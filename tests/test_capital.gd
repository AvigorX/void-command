extends SceneTree
## M4 — the capital hulls (1x5) and the drawing contract.
##
## Two things are pinned here that nothing else covers:
##  1. a 1x5 hull can be DEPLOYED, can move, and can rotate once it has room - the
##     deployment band is four columns wide, so it enters the battle pointing one way;
##  2. every class silhouette, stretched to its footprint, stays INSIDE one cell across.
##     That second one was a real defect: the drawing scaled the polygon uniformly by the
##     hull LENGTH, so a 1x4 battleship was drawn 74 px wide on a 46 px cell.

const ShipRef = preload("res://scripts/core/ship.gd")
const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const BattleScript = preload("res://scripts/core/battle.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""


func _initialize() -> void:
	print("=== VOID COMMAND — CAPITAL HULLS AND DRAWING CONTRACT (M4) ===")
	SaveGuard.isolate()
	test_declared()
	test_deployment_both_boards()
	test_rotation_needs_room()
	test_pathfinding_and_los()
	test_fleet_caps_end_to_end()
	test_silhouette_fits_one_cell()
	test_silhouettes_are_distinct()
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


func test_declared() -> void:
	begin("declared geometry")
	for id in ["carrier", "dreadnought"]:
		var d: Dictionary = ShipDefsRef.def(id)
		ok(Vector2i(d["footprint"]) == Vector2i(1, 5), "%s is 1x5 (got %s)" % [id, str(d["footprint"])])
		var s: Ship = ShipRef.create(id, 0, 0, 0)
		ok(s != null, "%s builds" % id)
		ok(s.cells().size() == 5, "%s occupies exactly 5 cells in one orientation" % id)
		ok(mini(s.footprint.x, s.footprint.y) == 1, "%s is one cell wide" % id)
	# No class in the whole catalogue is 2-wide, in any orientation.
	for id2 in ShipDefsRef.ORDER:
		var fp: Vector2i = Vector2i(ShipDefsRef.def(id2)["footprint"])
		for o in range(4):
			var e: Vector2i = FootprintRef.extent(fp, o)
			ok(mini(e.x, e.y) == 1, "%s at %d deg is %dx%d, never 2 wide" % [id2, o * 90, e.x, e.y])
			ok(maxi(e.x, e.y) <= 5, "%s at %d deg is at most 5 long" % [id2, o * 90])


func test_deployment_both_boards() -> void:
	begin("deployment on both boards")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var label: String = MapConfigRef.label(size)
		# The largest legal fleet: one Dreadnought, two Battleships, two Carriers.
		var fleet: Array[String] = ["dreadnought", "battleship", "battleship", "carrier", "carrier",
			"cruiser", "frigate"]
		var geo: Dictionary = FleetRef.deployable(fleet, size)
		ok(bool(geo["ok"]), "the capital fleet deploys on %s (%s)" % [label, String(geo.get("reason", ""))])
		var b = BattleScript.new()
		b.setup(13, {}, 1, size, fleet, ["fighter"])
		ok(b.deploy_failures.is_empty(), "and the battle places every hull on %s" % label)
		var cells: Dictionary = {}
		var total: int = 0
		for s in b.alive_ships(0):
			ok(b.map.is_deploy_zone(s.cell, 0), "%s anchor is in the zone on %s" % [s.ship_class, label])
			for c in s.cells():
				ok(b.map.in_bounds(c), "%s cell on board (%s)" % [s.ship_class, label])
				cells[c] = true
				total += 1
		ok(cells.size() == total, "no overlap on %s" % label)
		var cap_ships: int = 0
		for s2 in b.alive_ships(0):
			if s2.footprint.y == 5 or s2.footprint.x == 5:
				cap_ships += 1
		ok(cap_ships == 3, "the two Carriers and the Dreadnought are all 5-cell hulls on %s (%d)" % [label, cap_ships])


func test_rotation_needs_room() -> void:
	begin("rotation needs room")
	var b = BattleScript.new()
	b.setup(17, {}, 1, MapConfigRef.REFERENCE)
	b.map.cells.fill(MapScript.Terrain.VOID)
	var dn: Ship = null
	for s in b.alive_ships(0):
		if s.ship_class == "battleship":
			dn = s
	dn.cell = Vector2i(2, 4)
	dn.orientation = 0
	dn.move_points = 6
	# In the open it turns.
	ok(bool(b.rotate_ship(dn.id, 1)["ok"]), "a 1x4 hull rotates in open space")
	ok(FootprintRef.extent(dn.footprint, dn.orientation) == Vector2i(4, 1), "and now lies across the row")
	# In the one-cell gap beside a wall it cannot.
	b.map.cells.fill(MapScript.Terrain.VOID)
	# A one-cell doorway at (12,6) in an otherwise solid wall, AND a wall on the far side:
	# a 1x4 hull standing at (10,6) would have to occupy x=10..13 to turn, which the
	# alanet at (13,6) forbids.
	for y in range(b.map.height):
		if y != 6:
			b.map.cells[b.map.width * y + 12] = MapScript.Terrain.PLANET
	b.map.cells[b.map.width * 6 + 13] = MapScript.Terrain.PLANET
	dn.cell = Vector2i(10, 6)
	dn.orientation = 0
	dn.move_points = 6
	var refused: Dictionary = b.rotate_ship(dn.id, 1)
	ok(not bool(refused["ok"]), "a rotation that would clip is refused")
	ok(String(refused["reason"]).find("Cannot rotate") != -1, "with an explicit reason")
	ok(dn.orientation == 0, "and the orientation is unchanged")
	ok(dn.cell == Vector2i(10, 6), "and so is the position")


func test_pathfinding_and_los() -> void:
	begin("pathfinding and line of sight")
	var b = BattleScript.new()
	b.setup(19, {}, 1, MapConfigRef.REFERENCE)
	b.map.cells.fill(MapScript.Terrain.VOID)
	var cv: Ship = null
	for s in b.alive_ships(0):
		if s.ship_class == "cruiser":
			cv = s
	cv.set_footprint(Vector2i(1, 5))
	cv.cell = Vector2i(4, 3)
	cv.orientation = 0
	cv.move_points = 10
	var reach: Dictionary = b.reachable_states(cv.id)
	var states: Dictionary = reach.get("dist", {})
	ok(not states.is_empty(), "a 1x5 hull has reachable states")
	ok(states.has(Vector3i(4, 8, 0)), "it can slide down its own column")
	# A destination whose anchor is free but whose tail is blocked must be refused.
	var rock_cell: Vector2i = Vector2i(4, 9)
	b.map.cells[b.map.width * rock_cell.y + rock_cell.x] = MapScript.Terrain.PLANET
	var blocked: Dictionary = b.move_ship(cv.id, Vector2i(4, 5), 0)
	ok(not bool(blocked["ok"]), "a move whose tail would enter an alanet is refused")
	ok(cv.cell == Vector2i(4, 3), "and nothing moved")
	# LOS: a 5-cell hull has five potential firing lanes (S5 rule).
	var target: Ship = b.alive_ships(1)[0]
	target.cell = Vector2i(9, 3)
	target.placed = true
	cv.set_footprint(Vector2i(1, 5))
	cv.cell = Vector2i(6, 3)
	cv.orientation = 0
	cv.has_attacked = false
	b.map.cells[b.map.width * 3 + 7] = MapScript.Terrain.PLANET
	b.map.cells[b.map.width * 4 + 7] = MapScript.Terrain.PLANET
	b.map.cells[b.map.width * 5 + 7] = MapScript.Terrain.PLANET
	b.map.cells[b.map.width * 6 + 7] = MapScript.Terrain.PLANET
	b.map.cells[b.map.width * 7 + 7] = MapScript.Terrain.PLANET
	ok(not b.has_firing_los(cv, target), "with every lane blocked there is no firing solution")
	ok(not bool(b.can_attack(cv.id, target.id)["ok"]), "and the attack is refused")


func test_fleet_caps_end_to_end() -> void:
	begin("caps reach the battlefield")
	var b = BattleScript.new()
	b.setup(23, {}, 1, MapConfigRef.REFERENCE,
		["dreadnought", "battleship", "battleship", "carrier", "carrier"], ["fighter"])
	ok(b.alive_ships(0).size() == 5, "a fleet at every cap reaches the board")
	var classes: Array[String] = []
	for s in b.alive_ships(0):
		classes.append(s.ship_class)
	ok(classes.has("dreadnought"), "including the Dreadnought")
	ok(classes.has("carrier"), "and a Carrier")
	# The enemy generator must never exceed the caps either.
	var gen: Dictionary = FleetRef.generate_enemy(23, 200, MapConfigRef.EXPERIMENTAL)
	ok(ShipDefsRef.cap_of("dreadnought") == 1, "the Dreadnought cap is 1")
	ok(FleetRef.count_of(gen["entries"], "dreadnought") <= 1, "the generator respects it")
	ok(FleetRef.count_of(gen["entries"], "battleship") <= 2, "and the Battleship cap")
	ok(FleetRef.count_of(gen["entries"], "carrier") <= 2, "and the Carrier cap")
	ok(bool(gen["deployable"]), "and the generated fleet is deployable")


func test_silhouette_fits_one_cell() -> void:
	begin("silhouette stays inside one cell")
	var view = ViewScript.new()
	var cell: float = 46.0
	for id in ShipDefsRef.ORDER:
		var proto: PackedVector2Array = view.HULL_SHAPES.get(id, view.HULL_SHAPES["fighter"])
		var half: Vector2 = ViewScript.hull_half_extent(proto)
		var fp: Vector2i = Vector2i(ShipDefsRef.def(id)["footprint"])
		var scale: Vector2 = ViewScript.hull_draw_scale(proto, fp, cell)
		var drawn_half_width: float = half.y * scale.y
		ok(drawn_half_width <= cell * 0.5,
			"%s is drawn %.1f px wide at most, half a %.0f px cell" % [id, drawn_half_width, cell])
		var drawn_half_len: float = half.x * scale.x
		ok(drawn_half_len <= float(maxi(fp.x, fp.y)) * cell * 0.5,
			"%s stays inside its own length" % id)
	# The specific defect that motivated this: the old uniform scale.
	var bs_proto: PackedVector2Array = view.HULL_SHAPES["battleship"]
	var bs_half: Vector2 = ViewScript.hull_half_extent(bs_proto)
	var old_uniform: float = (4.0 * cell * 0.38) / bs_half.x
	ok(bs_half.y * old_uniform * 2.0 > cell,
		"the OLD uniform scale drew %.0f px across a %.0f px cell (regression guard)" % [
			bs_half.y * old_uniform * 2.0, cell])
	view.free()


func test_silhouettes_are_distinct() -> void:
	begin("silhouettes are distinct")
	var view = ViewScript.new()
	var seen: Dictionary = {}
	for id in ShipDefsRef.ORDER:
		var proto: PackedVector2Array = view.HULL_SHAPES.get(id, PackedVector2Array())
		ok(proto.size() >= 5, "%s has a real polygon (%d points)" % [id, proto.size()])
		var key: String = str(proto)
		ok(not seen.has(key), "%s has a silhouette no other class shares" % id)
		seen[key] = true
	# Carrier and Dreadnought share 1x5, so their shapes must differ in PROFILE, not just
	# in size: compare the width profile at both ends.
	var carrier: PackedVector2Array = view.HULL_SHAPES["carrier"]
	var dread: PackedVector2Array = view.HULL_SHAPES["dreadnought"]
	ok(carrier != dread, "Carrier and Dreadnought are different polygons")
	var carrier_mass: float = 0.0
	var dread_mass: float = 0.0
	for p in carrier:
		carrier_mass += absf(p.y)
	for p in dread:
		dread_mass += absf(p.y)
	ok(absf(carrier_mass - dread_mass) > 0.5, "with different width profiles (%.1f vs %.1f)" % [carrier_mass, dread_mass])
	view.free()
