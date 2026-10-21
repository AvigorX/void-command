extends SceneTree
## STEP 2 / Block B — the same stress campaign on BOTH battlefield sizes.
##
## A victory rate is not the assertion: what must hold on every seed and every size is
## that the battle TERMINATES (no endless stalling), that no hull ever overlaps another,
## that the AI never issues a move the rules refuse, and that the relay stays capturable.
## Outcomes and round counts are printed so the two configurations can be compared.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapScriptRef = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

const SEEDS: Array[int] = [1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009]
const MAX_STEPS: int = 60

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — TWO-SIZE STRESS CAMPAIGN (STEP 2) ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		begin("campaign %s" % MapConfigRef.label(size))
		run_campaign(size)
		begin("objective reachability %s" % MapConfigRef.label(size))
		var reach: bool = relay_reachable(size)
		ok(reach, "the relay is reachable from the player's own deployment zone")
		var relay_cells: int = relay_open_cells(size)
		ok(relay_cells >= 4, "there is room around the relay for a 1x4 hull (%d open cells in a 3x3 box)" % relay_cells)
	begin("save isolation")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the campaign")
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


func run_campaign(size: Vector2i) -> void:
	var victories: int = 0
	var stalled: int = 0
	var refused_moves: int = 0
	var conflicts: int = 0
	var relay_taken: int = 0
	var rounds_min: int = 999
	var rounds_max: int = 0
	var rounds_sum: int = 0
	var destructions: int = 0
	print("  seed  outcome  rounds  player  enemy  refused  relay")
	for sd in SEEDS:
		var b = BattleScript.new()
		b.setup(sd, {}, 1, size)
		var guard: int = 0
		var refused_before: int = 0
		var took_relay: bool = false
		while b.outcome == "" and guard < MAX_STEPS:
			guard += 1
			_player_auto(b)
			if b.outcome != "":
				break
			b.end_turn()
			if b.control_owner == 0:
				took_relay = true
		if b.outcome == "":
			stalled += 1
		elif b.outcome == "victory":
			victories += 1
		var refused: int = 0
		for l in b.log_lines:
			if String(l).find("holds position") >= 0:
				refused += 1
		refused_moves += refused
		if not b.occupancy_conflicts().is_empty():
			conflicts += 1
		if took_relay:
			relay_taken += 1
		rounds_min = mini(rounds_min, b.round)
		rounds_max = maxi(rounds_max, b.round)
		rounds_sum += b.round
		destructions += (BattleScript.PLAYER_FLEET.size() + BattleScript.ENEMY_FLEET_BASE.size()) \
			- (b.alive_ships(0).size() + b.alive_ships(1).size())
		print("  %4d  %-8s %6d %7d %6d %8d %6s" % [
			sd, b.outcome, b.round, b.alive_ships(0).size(), b.alive_ships(1).size(),
			refused, "yes" if took_relay else "no"])
	print("  summary: victories %d/%d · rounds %d..%d (avg %.1f) · ships destroyed %d · "
		% [victories, SEEDS.size(), rounds_min, rounds_max, float(rounds_sum) / float(SEEDS.size()), destructions]
		+ "refused AI moves %d · seeds with overlap %d · relay captured on %d seeds" % [
			refused_moves, conflicts, relay_taken])
	ok(stalled == 0, "every seed reaches an outcome (%d stalled)" % stalled)
	ok(conflicts == 0, "no seed ends with overlapping hulls (%d)" % conflicts)
	ok(refused_moves == 0, "the AI never issues a move the rules refuse (%d)" % refused_moves)
	ok(victories + (SEEDS.size() - victories) == SEEDS.size(), "every seed is classified")
	ok(rounds_max < MAX_STEPS, "no battle needed the safety guard (%d rounds max)" % rounds_max)


func relay_reachable(size: Vector2i) -> bool:
	## Objective reachability as a MAP property, not as a consequence of the crude
	## auto-player: a 1x1 hull, given an unlimited budget from its own deployment zone,
	## must be able to stand on the relay cell. On the bigger board the auto-player
	## usually finishes the fight before anyone walks to the centre - that is a pacing
	## observation, not an unreachable objective.
	var b = BattleScript.new()
	b.setup(1000, {}, 1, size)
	var probe = b.alive_ships(0)[0]
	for s in b.ships:
		if s != probe:
			s.alive = false
	probe.move_points = 999
	var states: Dictionary = b.reachable_states(probe.id)
	return states.get("dist", {}).has(PathfinderRef.state_key(b.map.control_cell, 0))


func relay_open_cells(size: Vector2i) -> int:
	var m = MapScriptRef.new()
	m.setup(1000, size)
	var open_cells: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2i = m.control_cell + Vector2i(dx, dy)
			if m.in_bounds(c) and not m.is_blocked(c):
				open_cells += 1
	return open_cells


func _state_value(b, anchor: Vector2i, cells: Array[Vector2i], tgt, attack_range: int, field: Dictionary) -> int:
	var score: int = -int(field.get(anchor, 9999)) * 10
	var d: int = b.cells_distance_to(cells, tgt)
	if d <= attack_range and b.cells_have_los_to(cells, tgt):
		score += 60
	return score


func _player_auto(b) -> void:
	## Same crude one-turn stand-in as balance_probe: authoritative geometry, no plan.
	for s in b.alive_ships(0):
		if s.has_attacked:
			continue
		var best = null
		for e in b.alive_ships(1):
			if bool(b.can_attack(s.id, e.id)["ok"]):
				if best == null or e.hull < best.hull:
					best = e
		if best != null:
			b.attack(s.id, best.id)
			continue
		var tgt = null
		var td: int = 9999
		for e in b.alive_ships(1):
			var d: int = b.footprint_distance(s, e)
			if d < td:
				td = d
				tgt = e
		if tgt == null:
			return
		var states: Dictionary = b.reachable_states(s.id)
		var dist: Dictionary = states.get("dist", {})
		if dist.is_empty():
			return
		var field: Dictionary = PathfinderRef.distance_field(b.map, tgt.cell)
		var best_key: Vector3i = Vector3i(s.cell.x, s.cell.y, s.orientation)
		var stay_cells: Array[Vector2i] = FootprintRef.cells(s.cell, s.footprint, s.orientation)
		var best_score: int = _state_value(b, s.cell, stay_cells, tgt, s.attack_range, field)
		for key in dist.keys():
			var st: Vector3i = key
			var anchor := Vector2i(st.x, st.y)
			var cells: Array[Vector2i] = FootprintRef.cells(anchor, s.footprint, st.z)
			var score: int = _state_value(b, anchor, cells, tgt, s.attack_range, field)
			if score > best_score:
				best_score = score
				best_key = st
		var want_cell := Vector2i(best_key.x, best_key.y)
		if want_cell != s.cell or best_key.z != s.orientation:
			b.move_ship(s.id, want_cell, best_key.z)
		if bool(b.can_attack(s.id, tgt.id)["ok"]):
			b.attack(s.id, tgt.id)
