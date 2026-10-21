extends SceneTree
## STEP 2.1 / Block A — mid-battle save.
##
## The invariants under test are the ones the mandate names: campaign save vs battle
## snapshot are separate files, loading never re-runs actions, the reward cannot be paid
## twice, derived structures are rebuilt, and a restored battle continues DETERMINISTICALLY
## (same AI decisions, same damage rolls) because both RNGs travel in the snapshot.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const BattleSaveRef = preload("res://scripts/core/battle_save.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — BATTLE SNAPSHOT SUITE (STEP 2.1) ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	BattleSaveRef.path_override = "user://void_command_battle.test.json"
	BattleSaveRef.clear()
	test_round_trip()
	test_multicell_and_orientation()
	test_occupancy_after_restore()
	test_turn_and_objectives()
	test_determinism_after_restore()
	test_reward_not_duplicated()
	test_invalid_snapshots()
	test_file_errors()
	test_paths_are_separate()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	BattleSaveRef.clear()
	# Back to the harness scratch path, never to the default one (see SaveGuard.cleanup).
	BattleSaveRef.path_override = SaveGuard.TEST_BATTLE
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


func fresh(size: Vector2i = MapConfigRef.REFERENCE, seed_value: int = 555001) -> Battle:
	var b = BattleScript.new()
	b.setup(seed_value, {}, 1, size)
	return b


func total_hull(b, team: int) -> float:
	var sum: float = 0.0
	for s in b.alive_ships(team):
		sum += s.hull + s.shield
	return sum


func play(b, rounds: int) -> String:
	## Deterministic driver: the player does nothing, so only the AI acts. Two battles
	## fed the same snapshot must produce the same signature.
	var sig: String = ""
	for i in range(rounds):
		if b.outcome != "":
			break
		b.end_turn()
		sig += "%d|%s|%.2f|%.2f;" % [b.round, b.outcome, total_hull(b, 0), total_hull(b, 1)]
	return sig


# ------------------------------------------------------------------- tests ----

func test_round_trip() -> void:
	begin("a valid battle survives a save/load cycle")
	var b := fresh()
	b.end_turn()
	b.end_turn()
	var saved: Dictionary = BattleSaveRef.save_battle(b)
	ok(bool(saved["ok"]), "the snapshot is written (%s)" % String(saved.get("reason", "")))
	ok(BattleSaveRef.has_save(), "and the file exists")
	var raw: Dictionary = BattleSaveRef.load_raw()
	ok(bool(raw["ok"]), "the file parses back")
	var res: Dictionary = BattleSaveRef.restore(raw["data"])
	ok(bool(res["ok"]), "the snapshot restores (%s)" % String(res.get("reason", "")))
	var r = res["battle"]
	ok(r.seed_value == b.seed_value, "seed preserved")
	ok(r.round == b.round, "round preserved (%d)" % r.round)
	ok(r.phase == b.phase, "phase preserved")
	ok(r.map.width == b.map.width and r.map.height == b.map.height, "battlefield size preserved")
	ok(r.map.cells == b.map.cells, "every terrain cell preserved")
	ok(r.map.control_cell == b.map.control_cell, "relay cell preserved")
	ok(r.ships.size() == b.ships.size(), "ship count preserved (%d)" % r.ships.size())
	var same: bool = true
	for i in range(b.ships.size()):
		var a: Ship = b.ships[i]
		var c: Ship = r.ships[i]
		if a.id != c.id or a.ship_class != c.ship_class or a.team != c.team \
				or a.cell != c.cell or a.orientation != c.orientation \
				or not is_equal_approx(a.hull, c.hull) or not is_equal_approx(a.shield, c.shield) \
				or a.has_attacked != c.has_attacked or a.move_points != c.move_points \
				or a.ability_cooldown != c.ability_cooldown:
			same = false
	ok(same, "every hull keeps id, class, team, cell, orientation, hull, shield, flags")
	ok(r.get_ship(0) != null, "the by_id index is rebuilt")
	ok(r.map.cells == b.map.cells and r.map.control_cell == b.map.control_cell
			and r.map.planet_anchors == b.map.planet_anchors,
		"the terrain, the planet anchors and the relay are restored")
	# The old assertion here read `rock_shapes`, which M6 deleted with the asteroid fields.
	# It threw a SCRIPT ERROR that aborted the rest of this function while the suite still
	# printed PASS - the failure mode this suite exists to prevent.


func test_multicell_and_orientation() -> void:
	begin("multi-cell hulls and orientation survive the cycle")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var b := fresh(size, 555002)
		var bs: Ship = null
		for s in b.ships:
			if s.ship_class == "battleship":
				bs = s
		ok(bs != null, "%s: a battleship deployed" % MapConfigRef.label(size))
		if bs == null:
			continue
		# Turn it so the snapshot has to carry a non-zero orientation.
		if not bool(b.rotate_ship(bs.id, 1)["ok"]):
			bs.set_orientation(1)
		var cells_before: Array[Vector2i] = bs.cells()
		ok(cells_before.size() == bs.footprint.x * bs.footprint.y, "the hull owns its whole footprint")
		BattleSaveRef.save_battle(b)
		var res: Dictionary = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])
		var r = res["battle"]
		var rb: Ship = null
		for s2 in r.ships:
			if s2.id == bs.id:
				rb = s2
		ok(rb != null, "the battleship is restored")
		if rb == null:
			continue
		ok(rb.orientation == bs.orientation, "orientation preserved (%d)" % rb.orientation)
		ok(rb.footprint == bs.footprint, "footprint preserved (%s)" % str(rb.footprint))
		ok(rb.cells() == cells_before, "and the occupied cells are identical")


func test_occupancy_after_restore() -> void:
	begin("occupancy is rebuilt exactly, without overlap")
	var b := fresh(MapConfigRef.EXPERIMENTAL, 555003)
	b.end_turn()
	BattleSaveRef.save_battle(b)
	var r = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])["battle"]
	ok(r.occupied() == b.occupied(), "the cell -> ship map is identical")
	ok(r.occupancy_conflicts().is_empty(), "and contains no conflict")
	ok(r.occupied().size() == b.occupied().size(), "same number of occupied cells (%d)" % r.occupied().size())


func test_turn_and_objectives() -> void:
	begin("turn state and relay objective survive")
	var b := fresh(MapConfigRef.REFERENCE, 555004)
	b.end_turn()
	b.control_hold = 2
	b.control_owner = 0
	b.control_bonus_claimed = false
	b.last_message = "Relay held."
	BattleSaveRef.save_battle(b)
	var r = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])["battle"]
	ok(r.phase == b.phase, "phase preserved")
	ok(r.round == b.round, "round preserved")
	ok(r.control_hold == 2 and r.control_owner == 0, "relay hold counter and owner preserved")
	ok(r.control_bonus_claimed == false, "relay bonus flag preserved")
	ok(r.last_message == "Relay held.", "last status line preserved")
	var mp_same: bool = true
	for i in range(b.ships.size()):
		if b.ships[i].move_points != r.ships[i].move_points:
			mp_same = false
	ok(mp_same, "per-hull movement points preserved")


func test_determinism_after_restore() -> void:
	begin("a restored battle continues deterministically")
	var b := fresh(MapConfigRef.REFERENCE, 555005)
	play(b, 2)
	BattleSaveRef.save_battle(b)
	var restored = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])["battle"]
	# Same starting point, same driver, four more rounds each.
	ok(play(b, 4) == play(restored, 4), "identical outcome, rounds and hull totals for four rounds")
	# And the RNG streams really are what carries it.
	var b2 := fresh(MapConfigRef.REFERENCE, 555006)
	play(b2, 1)
	var mid: int = b2.ai_rng.state
	BattleSaveRef.save_battle(b2)
	var r2 = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])["battle"]
	ok(r2.ai_rng.state == mid, "the AI RNG state is restored exactly")


func test_reward_not_duplicated() -> void:
	begin("the reward flag cannot pay twice")
	var b := fresh(MapConfigRef.REFERENCE, 555007)
	b.reward_granted = true
	BattleSaveRef.save_battle(b)
	var r = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])["battle"]
	ok(r.reward_granted, "a settled battle stays settled after the restore")
	var b2 := fresh(MapConfigRef.REFERENCE, 555008)
	BattleSaveRef.save_battle(b2)
	var r2 = BattleSaveRef.restore(BattleSaveRef.load_raw()["data"])["battle"]
	ok(not r2.reward_granted, "an unsettled battle is not marked settled by loading")


func test_invalid_snapshots() -> void:
	begin("invalid snapshots are refused explicitly, never half-restored")
	var base: Dictionary = BattleSaveRef.snapshot(fresh())
	var cases: Array = []
	var bad_version: Dictionary = base.duplicate(true)
	bad_version["version"] = 99
	cases.append([bad_version, "version"])
	var bad_cells: Dictionary = base.duplicate(true)
	bad_cells["map"]["cells"] = [0, 0]
	cases.append([bad_cells, "does not match"])
	var bad_class: Dictionary = base.duplicate(true)
	# M4 made every catalogue class playable, so the fixture must use a class that is
	# genuinely unknown - not one that merely used to be unimplemented.
	bad_class["ships"][0]["class"] = "unobtainium"
	cases.append([bad_class, "unknown class"])
	var bad_cell: Dictionary = base.duplicate(true)
	bad_cell["ships"][0]["cell"] = [999, 999]
	cases.append([bad_cell, "outside the board"])
	var bad_phase: Dictionary = base.duplicate(true)
	bad_phase["phase"] = 7
	cases.append([bad_phase, "phase"])
	var no_ships: Dictionary = base.duplicate(true)
	no_ships["ships"] = []
	cases.append([no_ships, "no ships"])
	var bad_round: Dictionary = base.duplicate(true)
	bad_round["round"] = 0
	cases.append([bad_round, "round"])
	for entry in cases:
		var res: Dictionary = BattleSaveRef.restore(entry[0])
		ok(not bool(res["ok"]) and String(res["reason"]).find(String(entry[1])) >= 0,
			"refused with a reason mentioning '%s' (got '%s')" % [String(entry[1]), String(res.get("reason", ""))])
	# A map with no dictionary at all.
	var no_map: Dictionary = base.duplicate(true)
	no_map.erase("map")
	ok(not bool(BattleSaveRef.restore(no_map)["ok"]), "a snapshot with no map is refused")


func test_file_errors() -> void:
	begin("broken files are refused")
	BattleSaveRef.clear()
	ok(not bool(BattleSaveRef.load_raw()["ok"]), "no save means no load")
	var f: FileAccess = FileAccess.open(BattleSaveRef.save_path(), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	ok(not bool(BattleSaveRef.load_raw()["ok"]), "garbage is refused")
	BattleSaveRef.clear()
	ok(not BattleSaveRef.has_save(), "clearing removes the snapshot")


func test_paths_are_separate() -> void:
	begin("battle snapshot and campaign save are different files")
	ok(String(BattleSaveRef.DEFAULT_PATH) != String(SaveGuard.REAL_SAVE),
		"the default battle path is not the campaign path")
	ok(String(BattleSaveRef.save_path()) != String(SaveGuard.REAL_BATTLE),
		"the active snapshot path is not the player's battle file")
	ok(String(BattleSaveRef.save_path()) != String(SaveGuard.REAL_SAVE),
		"and it is not the campaign save either")
	ok(SaveGuard.unchanged(real_save_before), "the real save is byte-identical after the suite")
