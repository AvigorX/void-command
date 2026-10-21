extends SceneTree
## M7 — grid containment and dense deployment.
##
## The permanent guard for the defect this milestone fixed: a hull that cannot be placed must
## not exist, every occupied cell must be inside the board, both fleets must fit at 200 FP,
## hulls deploy horizontally and move along the grid, and the swarm variants stay 1x1.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const ShipRef = preload("res://scripts/core/ship.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var real_before: Dictionary = {}

const MIXED: Array[String] = ["dreadnought", "battleship", "carrier", "cruiser", "frigate",
	"destroyer", "fighter", "interceptor"]


func _initialize() -> void:
	SaveGuard.isolate()
	real_before = SaveGuard.snapshot()
	print("=== VOID COMMAND — GRID CONTAINMENT (M7) ===")
	test_no_hull_without_cell()
	test_containment_everywhere()
	test_long_footprints()
	test_dense_200()
	test_movement()
	test_orientation()
	test_swarms()
	test_caps()
	test_save_untouched()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _contained(b) -> Array:
	## Returns [outside_cells, overlapping_cells, ghost_hulls].
	var outside: int = 0
	var dupes: int = 0
	var ghost: int = 0
	var seen: Dictionary = {}
	for s in b.ships:
		if s.cell.x < 0 or s.cell.y < 0:
			ghost += 1
		for c in s.cells():
			if c.x < 0 or c.y < 0 or c.x >= b.map.width or c.y >= b.map.height:
				outside += 1
			if seen.has(c):
				dupes += 1
			seen[c] = true
	return [outside, dupes, ghost]


func test_no_hull_without_cell() -> void:
	## The regression itself: on a board too small for the fleet, the hulls that cannot be
	## placed must NOT exist. Before M7 they existed at (-1,-1).
	# 200 FP of the cheapest hull: far more hulls than a 20x14 band can hold, which is the
	# configuration that produced ghost ships before the guard.
	var roster: Array[String] = []
	for i in range(80):
		if bool(FleetRef.can_add(roster, "interceptor", 200)["ok"]):
			roster.append("interceptor")
	var b = BattleScript.new()
	b.setup(7, {}, 1, MapConfigRef.REFERENCE, roster, roster)
	ok(roster.size() > 20, "the fleet is dense enough to overflow the band (%d hulls)" % roster.size())
	var counts: Array = _contained(b)
	ok(int(counts[2]) == 0, "no hull is left without a cell on a tight board (%d)" % int(counts[2]))
	ok(int(counts[0]) == 0, "no cell falls outside the tight board (%d)" % int(counts[0]))
	ok(b.deploy_failures.size() > 0, "the failures are REPORTED, not hidden (%d)" % b.deploy_failures.size())


func test_containment_everywhere() -> void:
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL, MapConfigRef.GRAND]:
		var b = BattleScript.new()
		b.setup(11, {}, 1, size, MIXED, MIXED)
		var counts: Array = _contained(b)
		var label: String = MapConfigRef.label(size)
		ok(int(counts[0]) == 0, "%s: every occupied cell is inside the grid (%d outside)" % [label, int(counts[0])])
		ok(int(counts[1]) == 0, "%s: no two hulls share a cell (%d overlaps)" % [label, int(counts[1])])
		ok(int(counts[2]) == 0, "%s: no ghost hull (%d)" % [label, int(counts[2])])


func test_long_footprints() -> void:
	var b = BattleScript.new()
	b.setup(5, {}, 1, MapConfigRef.GRAND, ["dreadnought", "battleship", "carrier", "cruiser"], ["fighter"])
	for s in b.alive_ships(0):
		var e: Vector2i = FootprintRef.extent(s.footprint, s.orientation)
		var last: Vector2i = s.cell + e - Vector2i.ONE
		ok(last.x < b.map.width and last.y < b.map.height,
			"%s: last occupied cell %s is inside the board" % [s.ship_class, str(last)])
		ok(s.cells().size() == e.x * e.y,
			"%s: it occupies its whole %s footprint (%d cells)" % [s.ship_class, str(e), s.cells().size()])


func test_dense_200() -> void:
	for cls in ["interceptor", "fighter"]:
		var roster: Array[String] = []
		for i in range(80):
			if bool(FleetRef.can_add(roster, cls, 200)["ok"]):
				roster.append(cls)
		var b = BattleScript.new()
		b.setup(7, {}, 1, MapConfigRef.GRAND, roster, roster)
		var counts: Array = _contained(b)
		ok(b.deploy_failures.is_empty(),
			"200 FP of %s deploys on 72x72 (%d failures)" % [cls, b.deploy_failures.size()])
		ok(b.alive_ships(0).size() == roster.size(), "the player fleet is complete (%d/%d)" % [b.alive_ships(0).size(), roster.size()])
		ok(b.alive_ships(1).size() == roster.size(), "the enemy fleet is complete (%d/%d)" % [b.alive_ships(1).size(), roster.size()])
		ok(int(counts[0]) == 0, "200 FP of %s stays inside the grid" % cls)
		ok(int(counts[1]) == 0, "200 FP of %s has no overlap" % cls)


func test_movement() -> void:
	## A fresh battle per direction: a shared one made each axis depend on the previous
	## move's remaining state, which turned a rules question into a sequencing artefact.
	var b0 = BattleScript.new()
	b0.setup(9, {}, 1, MapConfigRef.GRAND, ["dreadnought"], ["fighter"])
	var centre := Vector2i(b0.map.width / 2, b0.map.height / 2)
	for pair in [[Vector2i(1, 0), "east"], [Vector2i(-1, 0), "west"],
			[Vector2i(0, 1), "south"], [Vector2i(0, -1), "north"]]:
		var dir: Vector2i = pair[0]
		var label: String = pair[1]
		var b = BattleScript.new()
		b.setup(9, {}, 1, MapConfigRef.GRAND, ["dreadnought"], ["fighter"])
		var s = b.alive_ships(0)[0]
		s.cell = centre
		s.move_points = 20
		var before: Vector2i = s.cell
		var res: Dictionary = b.move_ship(s.id, before + dir, s.orientation)
		ok(bool(res["ok"]), "the Dreadnought moves %s from open space: %s" % [label, str(res.get("reason", ""))])
		ok(s.cell == before + dir, "it arrived one cell %s" % label)
		var counts: Array = _contained(b)
		ok(int(counts[0]) == 0, "the %s move keeps every cell inside the grid" % label)
	# Illegal destinations: off-grid and occupied. Refused, and nothing moves.
	var b2 = BattleScript.new()
	b2.setup(9, {}, 1, MapConfigRef.GRAND, ["dreadnought"], ["fighter"])
	var d = b2.alive_ships(0)[0]
	d.move_points = 20
	var before2: Vector2i = d.cell
	var far: Dictionary = b2.move_ship(d.id, Vector2i(-2, -2), d.orientation)
	ok(not bool(far["ok"]), "a destination off the grid is refused")
	ok(d.cell == before2, "the hull stays where it was after a refusal")
	var enemy_cell: Vector2i = b2.alive_ships(1)[0].cell
	var clash: Dictionary = b2.move_ship(d.id, enemy_cell, d.orientation)
	ok(not bool(clash["ok"]), "an occupied cell is refused")


func test_orientation() -> void:
	for fp in [Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)]:
		var ori: int = ShipRef.initial_orientation(fp)
		var e: Vector2i = FootprintRef.extent(fp, ori)
		ok(e.y == 1 and e.x == fp.y, "%s deploys horizontally (extent %s)" % [str(fp), str(e)])
	ok(ShipRef.initial_orientation(Vector2i.ONE) == 0, "a 1x1 hull keeps orientation 0")
	var b = BattleScript.new()
	b.setup(3, {}, 1, MapConfigRef.GRAND, ["dreadnought", "cruiser"], ["fighter"])
	for s in b.alive_ships(0):
		var e: Vector2i = FootprintRef.extent(s.footprint, s.orientation)
		ok(e.y == 1, "%s is horizontal at deployment (extent %s)" % [s.ship_class, str(e)])


func test_swarms() -> void:
	var view = ViewScript.new()
	var radii: Array[float] = []
	for v in range(4):
		var slots: Array = view._squadron_slots("fighter", v)
		ok(slots.size() == 3, "fighter variant %d is a three-craft flight" % v)
		var r: float = 0.0
		for p in slots:
			r = maxf(r, Vector2(p).length())
		radii.append(r)
	var lo: float = radii.min()
	var hi: float = radii.max()
	ok(hi - lo <= 1.5, "the four variants share the same scale (radius %.1f..%.1f)" % [lo, hi])
	ok(hi <= 46.0 * 0.5, "every variant fits one 46 px cell (max radius %.1f)" % hi)
	ok(view._squadron_slots("interceptor", 0).size() == 4, "the interceptor is a four-craft dart")
	ok(view._squadron_slots("fighter", 0) != view._squadron_slots("fighter", 1),
		"two fighters can look different")
	view.free()


func test_caps() -> void:
	ok(int(preload("res://scripts/core/ship_defs.gd").cap_of("dreadnought")) == 1, "Dreadnought cap 1")
	ok(int(preload("res://scripts/core/ship_defs.gd").cap_of("battleship")) == 2, "Battleship cap 2")
	ok(int(preload("res://scripts/core/ship_defs.gd").cap_of("carrier")) == 1, "Carrier cap 1")
	for id in ["interceptor", "fighter", "destroyer", "frigate", "cruiser"]:
		ok(int(preload("res://scripts/core/ship_defs.gd").cap_of(id)) == 0, "%s has no numeric cap" % id)
	var big: Array[String] = []
	for i in range(30):
		if bool(FleetRef.can_add(big, "interceptor", 200)["ok"]):
			big.append("interceptor")
	ok(big.size() > 8, "no hidden global hull cap (%d interceptors)" % big.size())


func test_save_untouched() -> void:
	var after: Dictionary = SaveGuard.snapshot()
	ok(str(after["save"]) == str(real_before["save"]), "the real campaign save is untouched")
	ok(str(after["battle"]) == str(real_before["battle"]), "no real battle file was created")


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
