extends SceneTree
## STEP 2 / Block B — configurable battlefield: reference 20x14 and experimental 32x22.
##
## What is asserted here, in order of importance:
##   1. the reference configuration is BYTE-IDENTICAL to pre-STEP2 generation (pinned
##      fingerprints), so "configurable" did not silently re-roll the historical maps;
##   2. each configuration is reproducible from its seed and independent of the other;
##   3. the whole fleet deploys legally on both, and long hulls can manoeuvre and reach
##      the enemy half on the bigger board;
##   4. the renderer derives its pixel geometry from the grid, so the board always fits
##      the play area and world_to_cell round-trips at both sizes.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}

## Fingerprints of the reference maps taken with the pre-STEP2 generator. If one of
## these changes, the reference configuration was altered and the milestone failed.
## Nine of these ten are the ORIGINAL pre-STEP2 numbers, unchanged. Seed 11 is different on
## purpose: M5 added a capital-route gate to the generator because that map trapped a 1x5
## hull in an isolated pocket (1 seed in 10). The old value is kept here so the migration is
## auditable: 1295843028 -> 46407517, attempts 1 -> 2, and the new map reaches 228/228 of its
## feasible 1x5 anchors instead of 156/203.
## M6 migration: asteroid fields were removed from the generator, so every reference
## fingerprint moved ON PURPOSE. The old values are kept beside the new ones so the change
## is auditable instead of invisible:
##   seed 1     1543033929 -> 329802223      seed 2    1943580815 -> 1823362262
##   seed 3      370736472 -> 1041479563     seed 4    1037875996 -> 1044381561
##   seed 5      677416242 -> 1625407381     seed 7     742187880 -> 203792438
##   seed 11      46407517 -> 1754533804     seed 42   1231465156 -> 727460030
##   seed 4242    80027535 -> 17598570       seed 98765 1824586819 -> 1238413594
## The determinism property is unchanged: same seed and size still reproduce the same board,
## and the suite checks it on both configurations.
const REFERENCE_FINGERPRINTS := {
	1: 329802223,
	2: 1823362262,
	3: 1041479563,
	4: 1044381561,
	5: 1625407381,
	7: 203792438,
	11: 1754533804,
	42: 727460030,
	4242: 17598570,
	98765: 1238413594,
}


func _initialize() -> void:
	print("=== VOID COMMAND — BATTLEFIELD CONFIGURATION SUITE (STEP 2) ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	test_reference_unchanged()
	test_scaled_terrain_pinned()
	test_sizes_declared()
	test_determinism()
	test_generation_quality()
	test_deployment_both_sizes()
	test_long_hull_manoeuvre()
	test_rendering_geometry()
	test_invalid_size_fallback()
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


func cell_hash(m) -> int:
	var h: int = 2166136261
	for v in m.cells:
		h = (h ^ int(v)) * 16777619
		h = h & 0x7FFFFFFF
	return h


func map_of(seed_value: int, size: Vector2i):
	var m = MapScript.new()
	m.setup(seed_value, size)
	return m


func blocked_fraction(m) -> float:
	var blocked: int = 0
	for y in range(m.height):
		for x in range(m.width):
			if m.is_blocked(Vector2i(x, y)):
				blocked += 1
	return float(blocked) / float(m.width * m.height)


# ------------------------------------------------------------------- tests ----

func test_reference_unchanged() -> void:
	begin("reference 20x14 is byte-identical to the pre-STEP2 generator")
	for sd in REFERENCE_FINGERPRINTS.keys():
		var m = map_of(int(sd), MapConfigRef.REFERENCE)
		ok(m.width == 20 and m.height == 14, "seed %d is 20x14" % int(sd))
		var got: int = cell_hash(m)
		ok(got == int(REFERENCE_FINGERPRINTS[sd]),
			"seed %d fingerprint %d (got %d)" % [int(sd), int(REFERENCE_FINGERPRINTS[sd]), got])


func test_scaled_terrain_pinned() -> void:
	## M7B: the scaled generator stopped placing terrain inside the (six-column) deployment
	## band; before, it protected four columns. These pins make that change auditable and
	## stop any future accident on the scaled boards, which had no fingerprint at all.
	##
	## 32×22 MOVED ON PURPOSE - old value beside the new one:
	##   seed 1009: 457392190 -> 750496438      seed 7: 2000925540 -> 1654198222
	##   seed 11:   1551358742 -> 1097616988   (seed 11 has 3 planets instead of 4: one
	##                                          would have stood inside the band)
	## 72×72 is UNCHANGED for these three seeds (705397867 / 1773823562 / 78934816), which
	## is the evidence that the fix only bites where a rock actually fell in the band.
	## 80×80 is new, so its values are simply the first baseline.
	var pins: Dictionary = {
		"32x22": {1009: 750496438, 7: 1654198222, 11: 1097616988},
		"72x72": {1009: 705397867, 7: 1773823562, 11: 78934816},
		"80x80": {1009: 1545438687, 7: 311556584, 11: 1444509979},
	}
	begin("scaled terrain is pinned (32×22 moved on purpose in M7B)")
	var sizes: Dictionary = {
		"32x22": MapConfigRef.EXPERIMENTAL, "72x72": MapConfigRef.GRAND,
		"80x80": MapConfigRef.TITAN,
	}
	for label in pins.keys():
		for sd in pins[label].keys():
			var m = map_of(int(sd), sizes[label])
			ok(cell_hash(m) == int(pins[label][sd]),
				"%s seed %d terrain %d (pinned %d)" % [label, int(sd), cell_hash(m), int(pins[label][sd])])
	# And no terrain may stand on a cell a fleet has to deploy on: the invariant behind the
	# change, checked over the whole band rather than on one seed.
	var band_violations: int = 0
	for label2 in sizes.keys():
		var m2 = map_of(1009, sizes[label2])
		for y in range(m2.height):
			for x in range(m2.width):
				var c := Vector2i(x, y)
				if m2.is_blocked(c) and (m2.is_deploy_zone(c, 0) or m2.is_deploy_zone(c, 1)):
					band_violations += 1
	ok(band_violations == 0, "no planet sits inside a deployment band (%d)" % band_violations)


func test_sizes_declared() -> void:
	begin("the two supported configurations")
	ok(MapConfigRef.REFERENCE == Vector2i(20, 14), "reference is 20x14")
	ok(MapConfigRef.EXPERIMENTAL == Vector2i(32, 22), "experimental is 32x22")
	ok(MapConfigRef.is_valid(MapConfigRef.REFERENCE), "reference passes is_valid")
	ok(MapConfigRef.is_valid(MapConfigRef.EXPERIMENTAL), "experimental passes is_valid")
	ok(MapConfigRef.size_of("reference") == Vector2i(20, 14), "preset name resolves to 20x14")
	ok(MapConfigRef.size_of("experimental") == Vector2i(32, 22), "preset name resolves to 32x22")
	ok(MapConfigRef.preset_of(Vector2i(32, 22)) == "experimental", "size resolves back to its preset")
	ok(MapConfigRef.label(Vector2i(32, 22)) == "32×22", "label is human readable")
	var m = map_of(7, MapConfigRef.EXPERIMENTAL)
	ok(m.width == 32 and m.height == 22, "the generated map really is 32x22 (got %dx%d)" % [m.width, m.height])
	ok(m.cells.size() == 32 * 22, "the cell array covers the whole grid")


func test_determinism() -> void:
	begin("determinism per configuration")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var a = map_of(31, size)
		var b = map_of(31, size)
		ok(cell_hash(a) == cell_hash(b), "%s: same seed -> identical map" % MapConfigRef.label(size))
		ok(a.control_cell == b.control_cell, "%s: same relay cell" % MapConfigRef.label(size))
		var c = map_of(32, size)
		ok(cell_hash(a) != cell_hash(c), "%s: a different seed produces a different map" % MapConfigRef.label(size))
	# The two configurations are independent: same seed, different board, and neither
	# is required to look like the other (only each is reproducible).
	var r = map_of(31, MapConfigRef.REFERENCE)
	var e = map_of(31, MapConfigRef.EXPERIMENTAL)
	ok(cell_hash(r) != cell_hash(e) or r.width != e.width, "the sizes are genuinely different boards")
	# Repeated generation on the same instance must not accumulate state.
	var m = MapScript.new()
	m.setup(31, MapConfigRef.EXPERIMENTAL)
	var first: int = cell_hash(m)
	m.setup(31, MapConfigRef.EXPERIMENTAL)
	ok(cell_hash(m) == first, "re-running setup on the same instance reproduces the map")


func test_generation_quality() -> void:
	begin("generation keeps manoeuvre space instead of scaling obstacles with area")
	var ref = map_of(3, MapConfigRef.REFERENCE)
	var exp = map_of(3, MapConfigRef.EXPERIMENTAL)
	var ref_blocked: float = blocked_fraction(ref)
	var exp_blocked: float = blocked_fraction(exp)
	ok(exp_blocked <= ref_blocked + 0.10,
		"32x22 is not denser than 20x14 (%.3f vs %.3f blocked)" % [exp_blocked, ref_blocked])
	# M6 removed asteroid fields, so "blocked" now means planets only: the density drops by
	# an order of magnitude. What still matters is that terrain exists at all and that the
	# bigger board is not emptier than the small one.
	ok(exp_blocked > 0.003, "32x22 still has blocking terrain (%.3f blocked)" % exp_blocked)
	# Deployment columns must stay clear on both boards.
	var clear_ref: bool = true
	var clear_exp: bool = true
	for y in range(ref.height):
		for x in range(0, 4):
			if ref.is_blocked(Vector2i(x, y)):
				clear_ref = false
	for y in range(exp.height):
		for x in range(0, 4):
			if exp.is_blocked(Vector2i(x, y)):
				clear_exp = false
	ok(clear_ref, "no terrain inside the 20x14 deployment columns")
	ok(clear_exp, "no terrain inside the 32x22 deployment columns")
	# The relay must be a real, free cell inside the board, reachable from the west half.
	ok(exp.in_bounds(exp.control_cell) and not exp.is_blocked(exp.control_cell), "the 32x22 relay is a free cell")
	ok(exp.control_cell.x > 0 and exp.control_cell.x < exp.width - 1, "the 32x22 relay is not on an edge")


func test_deployment_both_sizes() -> void:
	begin("the whole fleet deploys legally on both boards")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		for difficulty in [1, 2, 4]:
			var b = BattleScript.new()
			b.setup(8801, {}, difficulty, size)
			var tag: String = "%s d%d" % [MapConfigRef.label(size), difficulty]
			ok(b.deploy_failures.is_empty(), "%s: no deployment failure (%s)" % [tag, str(b.deploy_failures)])
			ok(b.occupancy_conflicts().is_empty(), "%s: no shared cells" % tag)
			var all_legal: bool = true
			var in_zone: bool = true
			for s in b.ships:
				if not b.can_place(s.cell, s.footprint, s.orientation, s.id):
					all_legal = false
				if not b._footprint_in_zone(s.cell, s.footprint, s.orientation, s.team):
					in_zone = false
			ok(all_legal, "%s: every hull stands on a legal footprint" % tag)
			ok(in_zone, "%s: every hull is inside its own deployment zone" % tag)
			ok(b.alive_ships(0).size() == BattleScript.PLAYER_FLEET.size(), "%s: the player fleet is complete" % tag)
			ok(b.map.width == size.x and b.map.height == size.y, "%s: the battle reports its board size" % tag)


func test_long_hull_manoeuvre() -> void:
	begin("long hulls manoeuvre on the bigger board")
	for seed_value in [8802, 8803, 8804]:
		var b = BattleScript.new()
		b.setup(seed_value, {}, 1, MapConfigRef.EXPERIMENTAL)
		var bs = null
		for s in b.ships:
			if s.team == 0 and s.ship_class == "battleship":
				bs = s
		ok(bs != null, "seed %d: the battleship deployed" % seed_value)
		if bs == null:
			continue
		for s in b.ships:
			if s != bs:
				s.alive = false
		bs.move_points = 999
		var states: Dictionary = b.reachable_states(bs.id)
		var anchors: Dictionary = {}
		for key in states["dist"].keys():
			var st: Vector3i = key
			anchors[Vector2i(st.x, st.y)] = true
		ok(anchors.size() > 50, "seed %d: the hull has real manoeuvre space (%d anchors)" % [seed_value, anchors.size()])
		# It must be able to reach the enemy half of the board.
		var reached_east: bool = false
		for c in anchors.keys():
			if Vector2i(c).x > b.map.width - 6:
				reached_east = true
		ok(reached_east, "seed %d: the hull can cross to the enemy half" % seed_value)
		# And a route to a far anchor is a real, executable route.
		var target := Vector2i(b.map.width - 5, b.map.height / 2)
		var dest_ori: int = int(states["orientation"].get(target, bs.orientation))
		if b.can_place(target, bs.footprint, dest_ori, bs.id):
			var mv: Dictionary = b.move_ship(bs.id, target, dest_ori)
			ok(bool(mv["ok"]), "seed %d: the crossing order is accepted (%s)" % [seed_value, String(mv.get("reason", ""))])
			var legal: bool = true
			for st in mv.get("steps", []):
				var key: Vector3i = st
				if not b.can_place(Vector2i(key.x, key.y), bs.footprint, key.z, bs.id):
					legal = false
			ok(legal, "seed %d: every state of the crossing is legal" % seed_value)


func test_rendering_geometry() -> void:
	begin("the renderer derives its pixel geometry from the grid")
	# Reference: the legacy numbers must survive exactly.
	var b_ref = BattleScript.new()
	b_ref.setup(1, {}, 1, MapConfigRef.REFERENCE)
	var v_ref = ViewScript.new()
	v_ref.setup(b_ref)
	ok(is_equal_approx(v_ref.cell_px, 46.0), "20x14 keeps 46 px cells (got %.2f)" % v_ref.cell_px)
	ok(is_equal_approx(v_ref.board_w, 920.0) and is_equal_approx(v_ref.board_h, 644.0),
		"20x14 keeps the authored 920x644 board")
	# Experimental: the whole board must fit the play area.
	var b_exp = BattleScript.new()
	b_exp.setup(1, {}, 1, MapConfigRef.EXPERIMENTAL)
	var v_exp = ViewScript.new()
	v_exp.setup(b_exp)
	ok(v_exp.board_w <= ViewScript.PLAY_SIZE.x + 0.01, "32x22 board width fits the play area (%.1f)" % v_exp.board_w)
	ok(v_exp.board_h <= ViewScript.PLAY_SIZE.y + 0.01, "32x22 board height fits the play area (%.1f)" % v_exp.board_h)
	ok(v_exp.cell_px >= 24.0, "32x22 cells stay legible (%.1f px)" % v_exp.cell_px)
	# Screen <-> cell must round-trip for every cell on both boards.
	var round_trip_ok: bool = true
	for pair in [[v_ref, b_ref], [v_exp, b_exp]]:
		var v = pair[0]
		var b = pair[1]
		for y in range(b.map.height):
			for x in range(b.map.width):
				var c := Vector2i(x, y)
				if v.world_to_cell(v.cell_center(c)) != c:
					round_trip_ok = false
	ok(round_trip_ok, "world_to_cell(cell_center(c)) == c for every cell on both boards")
	# Board edge is exactly where the HUD starts, so no cell hides behind the panel.
	ok(is_equal_approx(ViewScript.ORIGIN.x + v_exp.board_w, 952.0),
		"the 32x22 board ends at the HUD column (%.1f)" % (ViewScript.ORIGIN.x + v_exp.board_w))
	v_ref.free()
	v_exp.free()


func test_invalid_size_fallback() -> void:
	begin("an unsupported size falls back to the reference board")
	ok(not MapConfigRef.is_valid(Vector2i(4, 3)), "a 4x3 battlefield is rejected")
	var b = BattleScript.new()
	b.setup(5, {}, 1, Vector2i(4, 3))
	ok(b.map.width == 20 and b.map.height == 14, "the battle falls back to 20x14 (got %dx%d)" % [b.map.width, b.map.height])
	ok(b.map_size == MapConfigRef.REFERENCE, "the battle records the reference size")


func test_save_isolation() -> void:
	begin("save isolation")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")
