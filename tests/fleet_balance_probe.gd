extends SceneTree
## M5 — balance matrix for ARBITRARY fleets.
##
## The historical `balance_probe` only knows the old roster, so "8/8 victories" never proved
## anything about the eight classes. Here both sides are built from the catalogue, both are
## driven by the SAME brain (`AIRT.take_turn(b, team)`), and every battle is deterministic in
## its seed.
##
## Archetypes per budget: a cheap swarm, a balanced line, a capital core. Each fights a
## generated enemy fleet of the same budget. Wins/losses/timeouts, rounds and the exact fleet
## that fought are printed, so a result can be reproduced instead of trusted.

const BattleScript = preload("res://scripts/core/battle.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const AIRef = preload("res://scripts/core/ai.gd")

const SEEDS: Array[int] = [7]
# M6: one board for every cell, so the comparison is like-for-like. 20 rounds keeps the
# matrix runnable; a battle not resolved by then is recorded as a timeout.
const MAX_ROUNDS: int = 20
## The grand board is the only size measured to hold two 200 FP fleets (capacity probe).
const BOARD: Vector2i = Vector2i(48, 34)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	print("=== VOID COMMAND — FLEET BALANCE MATRIX (M5) ===")
	print("budget archetype        side  hulls  spent  win%  rounds  timeout  deploy")
	for budget_mode in FleetRef.mode_ids():
		var budget: int = FleetRef.budget_of(budget_mode)
		for archetype in ["swarm", "line", "capital"]:
			var wins: int = 0
			var rounds_sum: int = 0
			var timeouts: int = 0
			var deploy_fail: int = 0
			var hulls_sum: int = 0
			var spent_sum: int = 0
			for seed_value in SEEDS:
				var player: Array[String] = build(archetype, budget)
				var enemy_gen: Dictionary = FleetRef.generate_enemy(seed_value, budget, BOARD)
				var enemy: Array = enemy_gen["entries"]
				var b = BattleScript.new()
				b.setup(seed_value, {}, 2, BOARD, player, enemy)
				hulls_sum += b.alive_ships(0).size()
				spent_sum += FleetRef.total_cost(player)
				if not b.deploy_failures.is_empty():
					deploy_fail += 1
					print("%-6d %-14s seed %-4d DEPLOY FAILURE: %s" % [budget, archetype, seed_value, str(b.deploy_failures)])
					continue
				var rounds: int = 0
				while b.outcome == "" and rounds < MAX_ROUNDS:
					rounds += 1
					AIRef.take_turn(b, 0)
					if b.outcome != "":
						break
					b.end_turn()
				if b.outcome == "victory":
					wins += 1
				elif b.outcome == "":
					timeouts += 1
				rounds_sum += b.round
			var games: int = SEEDS.size()
			print("%-6d %-14s %-5s %5.1f %6.1f %5d %7d %8d %7d" % [
				budget, archetype, "P", float(hulls_sum) / float(games), float(spent_sum) / float(games),
				int(100.0 * float(wins) / float(games)), rounds_sum / games, timeouts, deploy_fail])
			ok(deploy_fail == 0, "%s/%s: every fleet deployed" % [archetype, budget_mode])
			ok(hulls_sum > 0 and spent_sum > 0, "%s/%s: the fleet is non-empty" % [archetype, budget_mode])
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func build(archetype: String, budget: int) -> Array[String]:
	## Deterministic fleet builder that obeys the caps and the budget. It is a DESIGN choice,
	## not the player's optimal fleet: the point is that the archetype is reproducible.
	var order: Array[String] = []
	match archetype:
		"swarm":
			order = ["interceptor", "fighter", "destroyer"]
		"line":
			order = ["frigate", "cruiser", "battleship"]
		"capital":
			order = ["dreadnought", "battleship", "carrier", "cruiser", "frigate"]
	var fleet: Array[String] = []
	var guard: int = 0
	while guard < 200:
		guard += 1
		var added: bool = false
		for id in order:
			if bool(FleetRef.can_add(fleet, id, budget).get("ok", false)):
				fleet.append(id)
				added = true
		if not added:
			break
	# A budget-valid fleet is not automatically DEPLOYABLE, and the cheapest archetype proves
	# it: 60 hulls fit 200 FP and no 32x22 zone holds 60 hulls. The UI refuses such a fleet
	# through FleetPoints.validate(); this probe must not pretend to play it. Trim from the
	# END (the cheapest, least significant hulls) until the battlefield takes it - the same
	# deterministic drop rule the enemy generator uses.
	var drops: int = 0
	while drops < 40 and fleet.size() > 1 and not bool(FleetRef.deployable(fleet, BOARD)["ok"]):
		drops += 1
		fleet.remove_at(fleet.size() - 1)
	return fleet


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
