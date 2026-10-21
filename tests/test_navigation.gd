extends SceneTree
## M5 — NAVIGABILITY of the generated battlefields, per hull footprint.
##
## The question this suite answers is not "is the map valid" but "can the hull actually get
## somewhere useful". Deployment validity proves nothing: a hull can be placed correctly and
## still be walled in. The measurement uses the same state model as the route search -
## (anchor, orientation), translations cost 1, rotations are free and legal only where the
## whole hull fits - so a "corridor" here means a corridor the engine can use.

const MapScript = preload("res://scripts/core/battle_map.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const BattleScript = preload("res://scripts/core/battle.gd")
const ShipRef = preload("res://scripts/core/ship.gd")

const SEEDS: Array[int] = [1, 2, 3, 4, 5, 7, 11, 42, 4242, 98765]
const FOOTPRINTS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3),
	Vector2i(1, 4), Vector2i(1, 5)]

var checks: int = 0
var failures: int = 0
var current: String = ""


func _initialize() -> void:
	print("=== VOID COMMAND — NAVIGATION SUITE (M5) ===")
	test_generated_maps_all_footprints()
	test_capital_route_gate()
	test_corridor_widths()
	test_door_and_edge()
	test_rotation_required_route()
	test_deployment_then_movement()
	test_no_isolated_pockets()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
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


# ------------------------------------------------------------- generated ----

func test_generated_maps_all_footprints() -> void:
	begin("generated maps, every footprint")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		for fp in FOOTPRINTS:
			var worst_pct: int = 100
			var crosses: int = 0
			var worst_seed: int = -1
			for sd in SEEDS:
				var m = MapScript.new()
				m.setup(sd, size)
				var nav: Dictionary = m.nav_stats(fp)
				var feasible: int = int(nav["feasible_anchors"])
				var reach: int = int(nav["reachable_anchors"])
				var pct: int = 0 if feasible == 0 else int(100.0 * float(reach) / float(feasible))
				if pct < worst_pct:
					worst_pct = pct
					worst_seed = sd
				if bool(nav["crosses"]):
					crosses += 1
			# Measured baseline after the M5 gate: 1x1..1x4 sit at 97-100%, 1x5 at 77-100%
			# before the fix and 95-100% after it. 90% is the floor we are willing to promise.
			ok(worst_pct >= 90, "%dx%d reaches >=90%% of its feasible anchors on %s (worst %d%% at seed %d)" % [
				fp.x, fp.y, MapConfigRef.label(size), worst_pct, worst_seed])
			if fp == Vector2i(1, 5):
				ok(crosses == SEEDS.size(),
					"a 1x5 hull crosses the board on all %d seeds (%d)" % [SEEDS.size(), crosses])
			else:
				ok(crosses >= SEEDS.size() - 1, "%dx%d crosses on nearly every seed (%d/%d)" % [
					fp.x, fp.y, crosses, SEEDS.size()])


func test_capital_route_gate() -> void:
	begin("the generator's own gate")
	# Every generated map must satisfy the invariant the generator enforces now.
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		for sd in SEEDS:
			var m = MapScript.new()
			m.setup(sd, size)
			var nav: Dictionary = m.nav_stats(Vector2i(1, 5))
			ok(bool(nav["crosses"]), "seed %d/%s: a 1x5 can leave its band (%s)" % [
				sd, MapConfigRef.label(size), "yes" if bool(nav["crosses"]) else "NO"])
			var feasible: int = int(nav["feasible_anchors"])
			var pocket: int = int(nav["pocket_anchors"])
			ok(float(pocket) <= maxf(8.0, float(feasible) * 0.08),
				"seed %d/%s: isolated pocket %d of %d anchors stays under the 8%% allowance" % [
					sd, MapConfigRef.label(size), pocket, feasible])
	# The seed that used to fail is explicitly covered: 11 on 20x14 trapped a 1x5 hull.
	var broken = MapScript.new()
	broken.setup(11, MapConfigRef.REFERENCE)
	var fixed: Dictionary = broken.nav_stats(Vector2i(1, 5))
	ok(int(fixed["reachable_anchors"]) == int(fixed["feasible_anchors"]),
		"the seed-11 map that used to strand a 1x5 hull now reaches every feasible anchor (%d/%d)" % [
			int(fixed["reachable_anchors"]), int(fixed["feasible_anchors"])])
	# M6 removed the asteroid fields, so the seed-11 board is no longer rejected on the
	# first attempt: what matters is the PROPERTY (the gate accepts a board where a 1x5 can
	# cross), not how many attempts it took. Pinning the attempt count would pin a defect.
	ok(bool(broken.nav_stats(Vector2i(1, 5))["crosses"]),
		"and the accepted board lets a 1x5 cross (%d attempts)" % broken.generation_attempts)


# --------------------------------------------------------------- synthetic ----

func _blank(size: Vector2i) -> BattleMap:
	var m = MapScript.new()
	m.setup(1, size)
	m.cells.fill(MapScript.Terrain.VOID)
	m.control_cell = Vector2i(2, 2)
	return m


func _wall(m, column: int, gap_rows: Array) -> void:
	for y in range(m.height):
		if gap_rows.has(y):
			continue
		m.cells[m.width * y + column] = MapScript.Terrain.PLANET


func test_corridor_widths() -> void:
	begin("corridor widths")
	# A wide corridor across the middle: every hull crosses.
	var m = _blank(MapConfigRef.REFERENCE)
	for x in range(4, m.width - 4):
		for y in range(m.height):
			if y < 4 or y > 8:
				m.cells[m.width * y + x] = MapScript.Terrain.PLANET
	ok(bool(m.nav_stats(Vector2i(1, 1))["crosses"]), "a 1x1 passes a 5-row corridor")
	check_crosses(m.nav_stats(Vector2i(1, 5)), MapConfigRef.REFERENCE, Vector2i(1, 5), "in a 5-row corridor")
	# A 4-row corridor: a 1x5 cannot stand ACROSS it, but it crosses lengthwise - the hull
	# only needs one free row of five columns, and the corridor has five columns.
	var m2 = _blank(MapConfigRef.REFERENCE)
	for x in range(4, m2.width - 4):
		for y in range(m2.height):
			if y < 4 or y > 7:
				m2.cells[m2.width * y + x] = MapScript.Terrain.PLANET
	check_crosses(m2.nav_stats(Vector2i(1, 5)), MapConfigRef.REFERENCE, Vector2i(1, 5), "in a 4-row corridor (lengthwise)")
	# A ZIG-ZAG: free space is row 7 up to x=8, down column 8 to row 9, then row 9 to the
	# edge. Every straight run is too short to hold the hull across the turn, so a 1x5 cannot
	# get through while a 1x1 walks the whole thing. This is the geometry that really stops a
	# long hull: a single gap in a wall does NOT, because the hull drives through it sideways.
	var m3 = _blank(MapConfigRef.REFERENCE)
	for y in range(m3.height):
		for x in range(m3.width):
			m3.cells[m3.width * y + x] = MapScript.Terrain.PLANET
	for x in range(0, 9):
		m3.cells[m3.width * 7 + x] = MapScript.Terrain.VOID
	for y in range(7, 10):
		m3.cells[m3.width * y + 8] = MapScript.Terrain.VOID
	for x in range(8, m3.width):
		m3.cells[m3.width * 9 + x] = MapScript.Terrain.VOID
	ok(bool(m3.nav_stats(Vector2i(1, 1))["crosses"]), "a 1x1 walks the zig-zag corridor")
	ok(not bool(m3.nav_stats(Vector2i(1, 5))["crosses"]), "a 1x5 cannot turn inside it")
	ok(not bool(m3.nav_stats(Vector2i(1, 3))["crosses"]), "nor can a 1x3")



func check_crosses(nav: Dictionary, _size: Vector2i, fp: Vector2i, where: String) -> void:
	ok(bool(nav["crosses"]), "a %dx%d hull crosses %s" % [fp.x, fp.y, where])


func test_door_and_edge() -> void:
	begin("edges")
	var m = _blank(MapConfigRef.REFERENCE)
	# Corridor along the top row only: a 1x5 travelling along y=0 needs five free columns there.
	for y in range(1, m.height):
		for x in range(0, m.width):
			m.cells[m.width * y + x] = MapScript.Terrain.PLANET
	var edge = m.nav_stats(Vector2i(1, 5))
	ok(bool(edge["crosses"]), "a 1x5 can travel along the top edge row")
	var edgemap = _blank(MapConfigRef.REFERENCE)
	# A hull standing hard against the wall can still rotate if the row below is open.
	for x in range(0, edgemap.width):
		edgemap.cells[edgemap.width * 6 + x] = MapScript.Terrain.PLANET
	ok(bool(edgemap.nav_stats(Vector2i(1, 5))["crosses"]), "a single rock row does not block the board")


func test_rotation_required_route() -> void:
	begin("a route that requires a rotation")
	var m = _blank(MapConfigRef.REFERENCE)
	# Start area on the left, a tall thin slot in the middle, exit on the right: the hull must
	# enter vertically, and the only way out is a horizontal shaft.
	for y in range(m.height):
		if y != 7:
			m.cells[m.width * y + 10] = MapScript.Terrain.PLANET
	for x in range(10, m.width):
		for y in range(m.height):
			if y != 7 and y != 3:
				m.cells[m.width * y + x] = MapScript.Terrain.PLANET
	# Row 7 is a one-cell door (only a 1x1 fits), row 3 is the horizontal shaft.
	var nav1 = m.nav_stats(Vector2i(1, 1))
	ok(bool(nav1["crosses"]), "the 1x1 finds its way through the door")
	var nav5 = m.nav_stats(Vector2i(1, 5))
	ok(bool(nav5["crosses"]), "a 1x5 finds the five-column shaft instead")


func test_deployment_then_movement() -> void:
	begin("deployment followed by movement")
	# The real integration: deploy a capital fleet, then ask the engine whether the 1x5 can
	# actually leave the deployment band.
	var b = BattleScript.new()
	b.setup(42, {}, 1, MapConfigRef.EXPERIMENTAL,
		["dreadnought", "carrier", "battleship"], ["fighter"])
	ok(b.deploy_failures.is_empty(), "the capital fleet deploys")
	var dn: Ship = null
	for s in b.alive_ships(0):
		if s.ship_class == "dreadnought":
			dn = s
	ok(dn != null, "the Dreadnought is on the board")
	# `reachable_cells()` is the UI contract: anchor -> distance, plus the orientation the
	# hull would end in at that anchor. A destination taken from it is a pair the rules have
	# already accepted, so a later refusal would be a real inconsistency.
	dn.move_points = 6
	var rc: Dictionary = b.reachable_cells(dn.id)
	var cells_reach: Dictionary = rc.get("dist", {})
	var ori_map: Dictionary = rc.get("orientation", {})
	ok(not cells_reach.is_empty(), "it has reachable anchors")
	var outside: int = 0
	for c in cells_reach.keys():
		if (c as Vector2i).x > 3:
			outside += 1
	ok(outside > 0, "and %d of them are OUTSIDE the deployment band" % outside)
	var target: Vector2i = Vector2i(-1, -1)
	for c2 in cells_reach.keys():
		var cc: Vector2i = c2
		if cc.x > 4:
			target = cc
			break
	ok(target.x > 4, "a destination outside the band was found: %s" % str(target))
	var target_ori: int = int(ori_map.get(target, dn.orientation))
	var moved: Dictionary = b.move_ship(dn.id, target, target_ori)
	ok(bool(moved["ok"]), "it can actually move out of the band: target=%s ori=%d problem='%s' (%s)" % [
		str(target), target_ori, b.placement_problem(target, dn.footprint, target_ori, dn.id),
		String(moved.get("reason", ""))])
	ok(dn.cell.x > 3, "and ends up outside it (x=%d)" % dn.cell.x)


func test_no_isolated_pockets() -> void:
	begin("no meaningful isolated pockets")
	# The property that matters for gameplay: nothing sizeable is walled off for the largest
	# hull. Small crannies are terrain; a 12-anchor pocket is a defect.
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		for sd in SEEDS:
			var m = MapScript.new()
			m.setup(sd, size)
			var nav: Dictionary = m.nav_stats(Vector2i(1, 5))
			ok(int(nav["pocket_anchors"]) < 12,
				"seed %d/%s leaves no 12-anchor pocket for a 1x5 (pocket %d)" % [
					sd, MapConfigRef.label(size), int(nav["pocket_anchors"])])
