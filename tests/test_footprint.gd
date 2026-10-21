extends SceneTree
## S1 — footprint and orientation model.
## Pure-geometry regression suite: every assertion is about declared dimensions,
## the geometry contract, or the guarantee that live battles stay 1x1.
## Exit 0 only if every assertion passes.

const ShipScript = preload("res://scripts/core/ship.gd")
const DefsScript = preload("res://scripts/core/ship_defs.gd")
const FootprintScript = preload("res://scripts/core/footprint.gd")
## STEP 2 contract: capital hulls develop in LENGTH, one cell wide. Exactly these
## sizes ship, and 2x2 / 2x3 / 2x4 are forbidden by the mandate - the table lives in
## the test so a silent resize (in either direction) is caught here.
const STEP2_FOOTPRINTS := {
	"interceptor": Vector2i(1, 1),
	"fighter": Vector2i(1, 1),
	# M6: both escorts are single 1x1 hulls; the table is the expected geometry, so it has
	# to move with the decision or it stops guarding anything.
	"destroyer": Vector2i(1, 1),
	"frigate": Vector2i(1, 1),
	"cruiser": Vector2i(1, 3),
	"carrier": Vector2i(1, 5),
	"battleship": Vector2i(1, 4),
	"dreadnought": Vector2i(1, 5),
}
const ShipRef = preload("res://scripts/core/ship.gd")
const BattleScript = preload("res://scripts/core/battle.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — FOOTPRINT / ORIENTATION SUITE ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	test_declared_footprints()
	test_unit_footprint_every_orientation()
	test_fixture_1x2()
	test_fixture_2x3_geometry()
	test_non_square_rotation()
	test_invalid_input()
	test_no_mutation()
	test_determinism_and_uniqueness()
	test_battles_stay_unit()
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


func fmt(cells: Array[Vector2i]) -> String:
	var parts: PackedStringArray = []
	for c in cells:
		parts.append("(%d,%d)" % [c.x, c.y])
	return "[" + ", ".join(parts) + "]"


func same_cells(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func has_duplicates(cells: Array[Vector2i]) -> bool:
	var seen: Dictionary = {}
	for c in cells:
		if seen.has(c):
			return true
		seen[c] = true
	return false


func test_declared_footprints() -> void:
	begin("declared footprints")
	ok(DefsScript.ORDER.size() == 8, "eight classes in the catalogue (M4)")
	for class_id in DefsScript.ORDER:
		var d: Dictionary = DefsScript.def(class_id)
		var fp: Variant = d.get("footprint", null)
		ok(typeof(fp) == TYPE_VECTOR2I, "%s declares a Vector2i footprint (got %s)" % [class_id, str(fp)])
		# M3: fighter 1x1, frigate 1x2 (confirmed this milestone), cruiser 1x3,
		# battleship 1x4. The expected table lives in the test so a silent resize is
		# caught here rather than surfacing as a mysterious deployment failure.
		ok(typeof(fp) == TYPE_VECTOR2I and (fp as Vector2i) == STEP2_FOOTPRINTS[class_id],
			"%s footprint is %s (got %s)" % [class_id, str(STEP2_FOOTPRINTS[class_id]), str(fp)])
		# The mandate's geometry rule, asserted on the live catalogue: one cell wide,
		# never a 2-wide (or wider) block.
		if typeof(fp) == TYPE_VECTOR2I:
			var v: Vector2i = fp
			ok(mini(v.x, v.y) == 1, "%s is one cell wide, not a %dx%d block" % [class_id, v.x, v.y])
	for i in range(DefsScript.ORDER.size()):
		var class_id: String = DefsScript.ORDER[i]
		var s: Ship = ShipScript.create(class_id, 0, i, i)
		ok(s.footprint == STEP2_FOOTPRINTS[class_id], "%s instance takes its declared footprint" % class_id)
		# M7: deployment is horizontal, which is 90 degrees for a 1xN footprint under the
		# (columns, rows) convention. Ship.initial_orientation() is the single source.
		ok(s.orientation == ShipRef.initial_orientation(s.footprint),
			"%s instance starts at its initial orientation (got %d)" % [class_id, s.orientation])


func test_unit_footprint_every_orientation() -> void:
	begin("1x1 occupies its own cell in every orientation")
	# The subject is a class that is genuinely 1x1 (the Fighter): the contract for a
	# single-cell hull is unchanged by M3.
	var s: Ship = ShipScript.create("fighter", 1, 7, 0)
	s.cell = Vector2i(9, 11)
	var reference: Vector2i = s.cell
	var all_same: bool = true
	for o in range(4):
		ok(s.set_orientation(o), "orientation %d accepted" % o)
		var got: Array[Vector2i] = s.cells()
		ok(got.size() == 1 and got[0] == reference, "orientation %d -> exactly the reference cell (%s)" % [o, fmt(got)])
		if got.size() != 1 or got[0] != reference:
			all_same = false
	ok(all_same, "all four orientations occupy the identical cell")
	ok(s.cell == reference, "the reference cell never moved")


func test_fixture_1x2() -> void:
	begin("fixture 1x2")
	var s: Ship = ShipScript.create("fighter", 0, 1, 0)
	s.cell = Vector2i(5, 5)
	ok(s.set_footprint(Vector2i(1, 2)), "fixture 1x2 accepted on the instance")
	ok(s.set_orientation(0), "orientation 0")
	var north: Array[Vector2i] = s.cells()
	var expect_north: Array[Vector2i] = [Vector2i(5, 5), Vector2i(5, 6)]
	ok(same_cells(north, expect_north), "0 deg occupies %s (got %s)" % [fmt(expect_north), fmt(north)])
	ok(s.set_orientation(1), "orientation 90")
	var east: Array[Vector2i] = s.cells()
	var expect_east: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	ok(same_cells(east, expect_east), "90 deg occupies %s (got %s)" % [fmt(expect_east), fmt(east)])
	ok(not same_cells(north, east), "0 and 90 deg differ for a 1x2 hull")
	s.set_orientation(2)
	ok(same_cells(s.cells(), expect_north), "180 deg is cell-identical to 0 deg (rectangle is point-symmetric)")
	s.set_orientation(3)
	ok(same_cells(s.cells(), expect_east), "270 deg is cell-identical to 90 deg")
	ok(s.cells()[0] == s.cell, "the reference cell is always emitted first")
	ok(not has_duplicates(north) and not has_duplicates(east), "no duplicate cells")


func test_fixture_2x3_geometry() -> void:
	begin("fixture 2x3 (generic rectangle maths, not a shipped class)")
	var s: Ship = ShipScript.create("cruiser", 0, 2, 0)
	s.cell = Vector2i(4, 4)
	ok(s.set_footprint(Vector2i(2, 3)), "fixture 2x3 accepted on the instance")
	s.set_orientation(0)
	var a: Array[Vector2i] = s.cells()
	ok(a.size() == 6, "0 deg occupies 6 cells (got %d)" % a.size())
	ok(a[0] == Vector2i(4, 4) and a[5] == Vector2i(5, 6), "0 deg spans x 4..5, y 4..6 (last %s)" % str(a[5]))
	ok(not has_duplicates(a), "0 deg cells are unique")
	s.set_orientation(1)
	var b: Array[Vector2i] = s.cells()
	ok(b.size() == 6, "90 deg occupies 6 cells (got %d)" % b.size())
	ok(b[0] == Vector2i(4, 4) and b[5] == Vector2i(6, 5), "90 deg spans x 4..6, y 4..5 (last %s)" % str(b[5]))
	ok(not has_duplicates(b), "90 deg cells are unique")
	ok(not same_cells(a, b), "2x3 and 3x2 are different cell sets")
	ok(FootprintScript.extent(Vector2i(2, 3), 0) == Vector2i(2, 3), "extent 0 deg is 2x3")
	ok(FootprintScript.extent(Vector2i(2, 3), 1) == Vector2i(3, 2), "extent 90 deg is 3x2")
	ok(FootprintScript.extent(Vector2i(2, 3), 2) == Vector2i(2, 3), "extent 180 deg is 2x3")
	ok(FootprintScript.extent(Vector2i(2, 3), 3) == Vector2i(3, 2), "extent 270 deg is 3x2")


func test_non_square_rotation() -> void:
	begin("non-square rotation")
	var s: Ship = ShipScript.create("frigate", 1, 3, 0)
	s.cell = Vector2i(2, 7)
	ok(s.set_footprint(Vector2i(3, 1)), "fixture 3x1 accepted")
	s.set_orientation(0)
	var horiz: Array[Vector2i] = s.cells()
	var expect_h: Array[Vector2i] = [Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7)]
	ok(same_cells(horiz, expect_h), "3x1 at 0 deg is horizontal (got %s)" % fmt(horiz))
	s.set_orientation(1)
	var vert: Array[Vector2i] = s.cells()
	var expect_v: Array[Vector2i] = [Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9)]
	ok(same_cells(vert, expect_v), "3x1 at 90 deg is vertical (got %s)" % fmt(vert))
	ok(not same_cells(horiz, vert), "rotation changes the occupied cells")
	ok(horiz[0] == vert[0] and horiz[0] == s.cell, "both orientations keep the same reference cell")
	# Offsets are the same shape without a Ship instance.
	ok(same_cells(FootprintScript.offsets(Vector2i(3, 1), 1), [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]),
		"offsets() gives the shape relative to the reference cell")


func test_invalid_input() -> void:
	begin("invalid dimensions and orientations")
	var bad_sizes: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 0), Vector2i.ZERO,
		Vector2i(-1, 2), Vector2i(2, -1),
		Vector2i(FootprintScript.MAX_EDGE + 1, 1), Vector2i(1, FootprintScript.MAX_EDGE + 1),
	]
	for size in bad_sizes:
		ok(not FootprintScript.is_valid_size(size), "size %s rejected by is_valid_size" % str(size))
		ok(FootprintScript.cells(Vector2i(3, 3), size, 0).is_empty(), "size %s yields no cells" % str(size))
	for o in [-1, 4, 99, -1000]:
		ok(not FootprintScript.is_valid_orientation(o), "orientation %d rejected by is_valid_orientation" % o)
		ok(FootprintScript.cells(Vector2i(3, 3), Vector2i.ONE, o).is_empty(), "orientation %d yields no cells" % o)
	ok(FootprintScript.extent(Vector2i(0, 0), 0) == Vector2i.ZERO, "invalid extent is ZERO")
	var s: Ship = ShipScript.create("fighter", 0, 4, 0)
	ok(not s.set_orientation(4), "set_orientation(4) refused")
	ok(s.orientation == 0, "orientation unchanged after a refused value")
	ok(not s.set_orientation(-1), "set_orientation(-1) refused")
	ok(not s.set_footprint(Vector2i(0, 1)), "set_footprint((0,1)) refused")
	ok(s.footprint == Vector2i.ONE, "footprint unchanged after a refused size")
	ok(s.cells() == ([s.cell] as Array[Vector2i]), "the ship still occupies exactly its cell")
	# NOTE: Ship.create()'s "invalid catalogue footprint" fallback is defence in
	# depth against a source-level data typo and is not runtime-testable here:
	# `const DEFS` is a read-only Dictionary in 4.7.2, so no test can inject a bad
	# value (measured: "Invalid assignment on read-only value"). It is therefore
	# covered by review only, and documented as such in the milestone report.


func test_no_mutation() -> void:
	begin("calculating a footprint never mutates ship state")
	var s: Ship = ShipScript.create("cruiser", 0, 5, 2)
	s.cell = Vector2i(6, 6)
	s.hull = s.max_hull * 0.5
	s.shield = 7.0
	s.move_points = 2
	s.has_attacked = true
	s.ability_cooldown = 1
	var snap: Dictionary = {
		"cell": s.cell, "footprint": s.footprint, "hull": s.hull, "shield": s.shield,
		"move_points": s.move_points, "has_attacked": s.has_attacked,
		"cooldown": s.ability_cooldown, "alive": s.alive, "max_hull": s.max_hull,
		"damage": s.base_damage, "range": s.attack_range,
	}
	for i in range(8):
		s.cells()
		FootprintScript.offsets(Vector2i(2, 2), i % 4)
	var same: bool = (
		s.cell == Vector2i(snap["cell"]) and s.footprint == Vector2i(snap["footprint"])
		and is_equal_approx(s.hull, float(snap["hull"])) and is_equal_approx(s.shield, float(snap["shield"]))
		and s.move_points == int(snap["move_points"]) and s.has_attacked == bool(snap["has_attacked"])
		and s.ability_cooldown == int(snap["cooldown"]) and s.alive == bool(snap["alive"])
		and is_equal_approx(s.max_hull, float(snap["max_hull"]))
		and is_equal_approx(s.base_damage, float(snap["damage"])) and s.attack_range == int(snap["range"])
	)
	ok(same, "combat and position state unchanged after repeated footprint reads")
	# Changing orientation is the only mutation, and it touches nothing else.
	s.set_orientation(2)
	ok(
		s.orientation == 2 and s.cell == Vector2i(snap["cell"]) and s.footprint == Vector2i(snap["footprint"])
		and is_equal_approx(s.hull, float(snap["hull"])) and s.move_points == int(snap["move_points"])
		and s.has_attacked == bool(snap["has_attacked"]),
		"set_orientation changes orientation only")


func test_determinism_and_uniqueness() -> void:
	begin("determinism and uniqueness")
	var shapes: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 1), Vector2i(4, 2)]
	for size in shapes:
		for o in range(4):
			var a: Array[Vector2i] = FootprintScript.cells(Vector2i(8, 6), size, o)
			var b: Array[Vector2i] = FootprintScript.cells(Vector2i(8, 6), size, o)
			ok(same_cells(a, b), "%s @ %d deg is deterministic" % [str(size), o * 90])
			ok(not has_duplicates(a), "%s @ %d deg has unique cells" % [str(size), o * 90])
			ok(a.size() == size.x * size.y, "%s @ %d deg occupies %d cells (got %d)" % [
				str(size), o * 90, size.x * size.y, a.size()])


func test_battles_stay_unit() -> void:
	begin("live battles match the declared footprints")
	ok(DefsScript.def("fighter")["footprint"] == Vector2i.ONE, "the catalogue was not mutated by the fixtures")
	var b = BattleScript.new()
	b.setup(4242)
	var all_declared: bool = true
	var all_zero: bool = true
	var all_cell: bool = true
	for s in b.ships:
		if s.footprint != Vector2i(STEP2_FOOTPRINTS[s.ship_class]):
			all_declared = false
		if s.orientation != ShipRef.initial_orientation(s.footprint):
			all_zero = false
		var c: Array[Vector2i] = s.cells()
		if c.size() != s.footprint.x * s.footprint.y:
			all_cell = false
	ok(all_declared, "all %d deployed ships carry their declared footprint" % b.ships.size())
	# M7: not "0 deg" any more - the rule is "horizontal", and 90 is horizontal for a 1xN.
	ok(all_zero, "all deployed ships start at their initial (horizontal) orientation")
	ok(all_cell, "every deployed ship occupies exactly its footprint cells")
	# The rules still run: three full rounds, nothing about the model interferes.
	for i in range(3):
		if b.outcome != "":
			break
		b.end_turn()
	ok(b.round == 4 and b.outcome == "", "three end_turns advance to round 4 without ending the battle")
	var still_declared: bool = true
	for s in b.ships:
		if s.footprint != Vector2i(STEP2_FOOTPRINTS[s.ship_class]):
			still_declared = false
	ok(still_declared, "ships keep their declared footprint after simulated rounds")
