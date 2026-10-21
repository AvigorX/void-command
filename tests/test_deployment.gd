extends SceneTree
## STEP 2.1 / Block A — deployment pockets.
##
## Deployment used to accept an anchor merely because the footprint fitted. A long hull
## could then be sealed between terrain and the board edge with no legal way out, which
## is the deployment-side twin of the stranded-hull bug. These tests pin the distinction
## the mandate asks for: "fits" is not "can leave".

const BattleScript = preload("res://scripts/core/battle.gd")
const ShipScript = preload("res://scripts/core/ship.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FootprintScript = preload("res://scripts/core/footprint.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — DEPLOYMENT POCKET SUITE (STEP 2.1) ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	test_pocket_probe()
	test_sealed_cell_is_skipped()
	test_all_sealed_falls_back()
	test_rotation_escape_is_not_a_pocket()
	test_real_maps_have_no_pockets()
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


func board(seed_value: int) -> Battle:
	var b = BattleScript.new()
	b.setup(seed_value)
	b.map.cells.fill(MapScript.Terrain.VOID)
	b.map.control_cell = Vector2i(0, 0)
	for s in b.ships:
		s.alive = false
	b.deploy_failures.clear()
	b.pocket_fallbacks.clear()
	return b


func hull(b: Battle, id: int, size: Vector2i, cell: Vector2i, orientation: int = 0, move: int = 6) -> Ship:
	var s: Ship = b.get_ship(id)
	s.alive = true
	s.cell = cell
	s.max_move = move
	s.move_points = move
	# Mirrors real deployment: a hull waiting for an anchor must not block cells.
	s.placed = false
	s.set_footprint(size)
	s.set_orientation(0)
	s.set_orientation(orientation)
	return s


func wall_col(b: Battle, x: int, skip_y: int) -> void:
	for y in range(b.map.height):
		if y != skip_y:
			b.map.cells[y * b.map.width + x] = MapScript.Terrain.PLANET


# ------------------------------------------------------------------- tests ----

func test_pocket_probe() -> void:
	begin("a pocket is measured, not guessed")
	var b := board(8101)
	# A wall at x=3 with a single gap at y=7: the only way out of the deployment band.
	wall_col(b, 3, 7)
	var bs := hull(b, 0, Vector2i(1, 4), Vector2i(1, 6), 0, 2)
	ok(b.can_place(Vector2i(1, 6), bs.footprint, 0, bs.id), "the near anchor fits the hull")
	ok(b._pocket_ok(Vector2i(1, 6), bs, 0),
		"and it can reach the gap: 1 down + 4 right = 5 translations inside a budget of 6")
	ok(b.can_place(Vector2i(1, 0), bs.footprint, 0, bs.id), "the far anchor also fits")
	ok(not b._pocket_ok(Vector2i(1, 0), bs, 0),
		"but from the far end the same hull cannot reach the gap (move 2, budget 6)")
	# The probe must use the real rules: a 1x1 with move 6 has a bigger budget.
	var fighter := hull(b, 1, Vector2i.ONE, Vector2i(1, 0), 0, 6)
	ok(b._pocket_ok(Vector2i(1, 0), fighter, 0), "a fast 1x1 covers the same distance in its budget")


func test_sealed_cell_is_skipped() -> void:
	begin("a sealed anchor is skipped, the open one is taken")
	var b := board(8102)
	wall_col(b, 3, 7)
	var bs := hull(b, 0, Vector2i(1, 4), Vector2i(1, 6), 0, 2)
	# Pool order matters: pop_back takes the last, so the SEALED anchor is offered first.
	var pool: Array[Vector2i] = [Vector2i(1, 6), Vector2i(1, 0)]
	var picked: Vector2i = b._take_deployment_cell(pool, bs, 0)
	ok(picked == Vector2i(1, 6), "the sealed anchor is refused and the reachable one is used (got %s)" % str(picked))
	ok(b.pocket_fallbacks.is_empty(), "no fallback was needed")
	ok(b.deploy_failures.is_empty(), "and no deployment failure was recorded")


func test_all_sealed_falls_back() -> void:
	begin("when every legal anchor is sealed, the fallback is deterministic and reported")
	var b := board(8103)
	wall_col(b, 3, -1)   # no gap at all: the whole deployment band is sealed off
	var bs := hull(b, 0, Vector2i(1, 4), Vector2i(1, 4), 0, 2)
	var pool: Array[Vector2i] = [Vector2i(1, 4), Vector2i(1, 0)]
	var first: Vector2i = b._take_deployment_cell(pool, bs, 0)
	ok(first == Vector2i(1, 0), "the first pooled anchor is used deterministically (got %s)" % str(first))
	ok(b.pocket_fallbacks.size() == 1, "the sealed placement is recorded (%d)" % b.pocket_fallbacks.size())
	ok(b.deploy_failures.is_empty(), "it is not reported as a deployment failure")
	# Same inputs, same output: the fallback adds no randomness.
	var b2 := board(8103)
	wall_col(b2, 3, -1)
	var bs2 := hull(b2, 0, Vector2i(1, 4), Vector2i(1, 4), 0, 2)
	var pool2: Array[Vector2i] = [Vector2i(1, 4), Vector2i(1, 0)]
	ok(b2._take_deployment_cell(pool2, bs2, 0) == first, "the fallback is reproducible")


func test_rotation_escape_is_not_a_pocket() -> void:
	begin("a hull that must turn to get out is NOT a pocket")
	var b := board(8104)
	var bs := hull(b, 0, Vector2i(1, 4), Vector2i(1, 5), 0, 2)
	# Vertical dead ends above and below, and walls beside the middle: the hull can only
	# leave by turning horizontal at (1,5) and sliding right.
	b.map.cells[4 * b.map.width + 1] = MapScript.Terrain.PLANET
	b.map.cells[9 * b.map.width + 1] = MapScript.Terrain.PLANET
	b.map.cells[6 * b.map.width + 2] = MapScript.Terrain.PLANET
	b.map.cells[7 * b.map.width + 2] = MapScript.Terrain.PLANET
	ok(b.can_place(Vector2i(1, 5), bs.footprint, 0, bs.id), "the vertical hull fits where it stands")
	ok(b.can_place(Vector2i(1, 5), bs.footprint, 1, bs.id), "the horizontal hull also fits there")
	ok(b._pocket_ok(Vector2i(1, 5), bs, 0), "turning out of the dead end counts as an escape")
	# And the same geometry is accepted by the real deployment pick.
	var pool: Array[Vector2i] = [Vector2i(1, 5)]
	ok(b._take_deployment_cell(pool, bs, 0) == Vector2i(1, 5), "the pick is accepted, not skipped")


func test_real_maps_have_no_pockets() -> void:
	begin("generated maps deploy fleets without sealed hulls")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var fallbacks: int = 0
		var failures_total: int = 0
		for sd in range(9001, 9006):
			var b = BattleScript.new()
			b.setup(sd, {}, 1, size)
			fallbacks += b.pocket_fallbacks.size()
			failures_total += b.deploy_failures.size()
			ok(b.occupancy_conflicts().is_empty(), "%s seed %d: no overlap" % [MapConfigRef.label(size), sd])
		ok(fallbacks == 0, "%s: no hull had to be sealed in a pocket (%d)" % [MapConfigRef.label(size), fallbacks])
		ok(failures_total == 0, "%s: every hull found a legal anchor (%d)" % [MapConfigRef.label(size), failures_total])


func test_save_isolation() -> void:
	begin("save isolation")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")
