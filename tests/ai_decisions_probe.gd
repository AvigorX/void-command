extends SceneTree
## AI decision table — an EQUIVALENCE probe, run twice (before/after a refactor) and diffed.
##
## It prints, for fixed seeds and boards, the destination and target the AI chooses for
## every hull. Two runs are identical if and only if the scoring, the pruning and the RNG
## draws are unchanged, because the choice is the last step of all of them. Used to prove
## that the M7B single-pass scoring with an upper-bound prune did not move the AI.
##
## Run:
##   $GODOT --headless --path <project> --script res://tests/ai_decisions_probe.gd

const BattleScript = preload("res://scripts/core/battle.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const AIRef = preload("res://scripts/core/ai.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

const SEEDS: Array[int] = [1, 3, 7, 11]
const SIZES: Array[Vector2i] = [Vector2i(20, 14), Vector2i(32, 22)]


func _initialize() -> void:
	SaveGuard.isolate()
	print("=== AI DECISION TABLE ===")
	for size in SIZES:
		for sd in SEEDS:
			_table(size, sd)
			# FLAT: the terrain is erased and the fleet redeployed, so the two code trees
			# face EXACTLY the same board. Any remaining difference is the AI itself, not
			# a map that one side generated differently.
			_flat_table(size, sd)
	print("RESULT: PASS")
	SaveGuard.cleanup()
	quit(0)


func _flat_table(size: Vector2i, seed_value: int) -> void:
	var b = BattleScript.new()
	b.setup(seed_value, {}, 1, size, BattleScript.PLAYER_FLEET, BattleScript.ENEMY_FLEET_BASE)
	b.map.cells.fill(0)
	b.ships.clear()
	b.by_id.clear()
	b.deploy_failures.clear()
	b.pocket_fallbacks.clear()
	# The first (terrain-dependent) deployment already consumed RNG draws, and the number
	# of draws depends on how many band cells were blocked - which is exactly what differs
	# between the two trees. Restart the stream so both redeploy from the same state.
	b.rng.seed = seed_value
	b.ai_rng.seed = seed_value ^ 0x5DEECE66
	b._deploy()
	print("-- FLAT %s seed %d --" % [MapConfigRef.label(size), seed_value])
	_rows(b)


func _rows(b) -> void:
	for s in b.alive_ships(0):
		var target = AIRef._best_target(b, s, b.alive_ships(1))
		var target_id: int = -1 if target == null else target.id
		var pick: Dictionary = AIRef._choose_destination(b, s, target)
		print("  P%d %s %s -> cell %s ori %d target %d" % [
			s.id, s.ship_class, str(s.cell), str(pick.get("cell", s.cell)),
			int(pick.get("orientation", s.orientation)), target_id])
	for s2 in b.alive_ships(1):
		var t2 = AIRef._best_target(b, s2, b.alive_ships(0))
		var p2: Dictionary = AIRef._choose_destination(b, s2, t2)
		print("  E%d %s %s -> cell %s ori %d" % [
			s2.id, s2.ship_class, str(s2.cell), str(p2.get("cell", s2.cell)),
			int(p2.get("orientation", s2.orientation))])


func _table(size: Vector2i, seed_value: int) -> void:
	var b = BattleScript.new()
	b.setup(seed_value, {}, 1, size, BattleScript.PLAYER_FLEET, BattleScript.ENEMY_FLEET_BASE)
	print("-- %s seed %d --" % [MapConfigRef.label(size), seed_value])
	for s in b.alive_ships(0):
		var target = AIRef._best_target(b, s, b.alive_ships(1))
		var target_id: int = -1 if target == null else target.id
		var pick: Dictionary = AIRef._choose_destination(b, s, target)
		print("  P%d %s %s -> cell %s ori %d target %d" % [
			s.id, s.ship_class, str(s.cell), str(pick.get("cell", s.cell)),
			int(pick.get("orientation", s.orientation)), target_id])
	# One enemy turn, then the enemy's own choices: the same code path, the other side.
	b.end_turn()
	for s2 in b.alive_ships(1):
		var t2 = AIRef._best_target(b, s2, b.alive_ships(0))
		var p2: Dictionary = AIRef._choose_destination(b, s2, t2)
		print("  E%d %s %s -> cell %s ori %d" % [
			s2.id, s2.ship_class, str(s2.cell), str(p2.get("cell", s2.cell)),
			int(p2.get("orientation", s2.orientation))])
