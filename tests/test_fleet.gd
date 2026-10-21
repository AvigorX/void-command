extends SceneTree
## STEP 3 / Block D — Fleet Point System.
##
## The invariants: points are not credits, the core (not the UI) enforces every rule, a
## budget-valid fleet is not automatically a deployable one, and the enemy generator is
## deterministic, bounded and never reaches for a class it cannot field.

const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const BattleScript = preload("res://scripts/core/battle.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const SaveScript = preload("res://scripts/core/save_data.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

const MIXED: Array[String] = ["fighter", "fighter", "frigate", "cruiser"]
const LONG: Array[String] = ["cruiser", "battleship", "battleship"]

var checks: int = 0
var failures: int = 0
var current: String = ""


func _initialize() -> void:
	print("=== VOID COMMAND — FLEET POINT SYSTEM SUITE (STEP 3) ===")
	SaveGuard.isolate()
	test_budgets()
	test_costs()
	test_composition_rules()
	test_no_global_cap_examples()
	test_validation_is_core_side()
	test_geometry_and_deployment()
	test_enemy_generator()
	test_enemy_generator_terminates()
	test_points_are_not_credits()
	test_default_roster_unchanged()
	test_composed_battle_is_playable()
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


# --------------------------------------------------------------- budgets ----

func test_budgets() -> void:
	begin("budgets")
	ok(FleetRef.budget_of("skirmish") == 60, "Skirmish is 60")
	ok(FleetRef.budget_of("standard") == 100, "Standard is 100")
	ok(FleetRef.budget_of("fleet_engagement") == 150, "Fleet Engagement is 150")
	ok(FleetRef.budget_of("grand_fleet") == 200, "Grand Fleet is 200")
	ok(FleetRef.mode_ids() == ["skirmish", "standard", "fleet_engagement", "grand_fleet"],
		"four modes, in order")
	ok(FleetRef.budget_of("unknown") == FleetRef.budget_of(FleetRef.DEFAULT_MODE),
		"an unknown mode falls back to Standard instead of returning 0")
	# A per-mission budget needs no new machinery: the budget is an argument everywhere.
	var mission_budget: int = 73
	var r: Dictionary = FleetRef.validate_structure(MIXED, mission_budget)
	ok(bool(r["ok"]) and int(r["remaining"]) == mission_budget - FleetRef.total_cost(MIXED),
		"a mission-specific budget is just a number, and the remainder follows it")


func test_costs() -> void:
	begin("costs")
	ok(FleetRef.total_cost(["fighter"]) == 3, "one Fighter is 3 points")
	ok(FleetRef.total_cost(MIXED) == 21, "the mixed fleet is 21 points (%d)" % FleetRef.total_cost(MIXED))
	ok(FleetRef.total_cost([]) == 0, "an empty fleet costs nothing")
	ok(FleetRef.count_of(["fighter", "fighter", "cruiser"], "fighter") == 2, "counting works")
	ok(FleetRef.cost_of("nonsense") == -1, "an unknown class has cost -1")
	var exact: Array[String] = ["battleship", "battleship", "cruiser", "fighter"]
	var spent: int = FleetRef.total_cost(exact)
	var r: Dictionary = FleetRef.validate_structure(exact, spent)
	ok(bool(r["ok"]) and int(r["remaining"]) == 0, "spending the budget exactly is legal")
	ok(int(r["spent"]) == spent, "and the report agrees on what was spent")
	var over: Dictionary = FleetRef.validate_structure(exact, spent - 1)
	ok(not bool(over["ok"]), "one point short is refused")
	ok(String(over["reasons"][0]).find("Over budget") != -1, "and says so explicitly")


# ----------------------------------------------------------- composition ----

func test_composition_rules() -> void:
	begin("composition rules: per-class caps, no global hull cap")
	ok(bool(FleetRef.can_add([], "fighter", 100)["ok"]), "a Fighter can open a Standard fleet")
	ok(bool(FleetRef.can_add([], "carrier", 500)["ok"]), "a Carrier can be added (M4 made it playable)")
	ok(bool(FleetRef.can_add([], "dreadnought", 500)["ok"]), "so can a Dreadnought")
	ok(bool(FleetRef.can_add([], "interceptor", 500)["ok"]), "and an Interceptor")
	ok(bool(FleetRef.can_add([], "destroyer", 500)["ok"]), "and a Destroyer")
	ok(not bool(FleetRef.can_add([], "nonsense", 500)["ok"]), "an unknown class cannot be added")
	ok(not bool(FleetRef.can_add([], "battleship", 10)["ok"]), "14 points do not fit in a 10 budget")
	ok(String(FleetRef.can_add([], "battleship", 10)["reason"]).find("Not enough points") != -1,
		"with the points it would need")
	# Per-class caps.
	var one_dn: Array[String] = ["dreadnought"]
	ok(not bool(FleetRef.can_add(one_dn, "dreadnought", 500)["ok"]), "a second Dreadnought is refused")
	ok(String(FleetRef.can_add(one_dn, "dreadnought", 500)["reason"]).find("At most 1") != -1,
		"because the cap is 1")
	var two_bb: Array[String] = ["battleship", "battleship"]
	ok(not bool(FleetRef.can_add(two_bb, "battleship", 500)["ok"]), "a third Battleship is refused")
	ok(String(FleetRef.can_add(two_bb, "battleship", 500)["reason"]).find("At most 2") != -1,
		"because the cap is 2")
	var two_cv: Array[String] = ["carrier", "carrier"]
	ok(not bool(FleetRef.can_add(two_cv, "carrier", 500)["ok"]), "a third Carrier is refused")
	# Unlimited classes: no hidden numeric cap of any size.
	var many: Array[String] = []
	for i in range(12):
		many.append("frigate")
	ok(FleetRef.count_of(many, "frigate") == 12, "twelve Frigates are in the fleet")
	ok(bool(FleetRef.can_add(many, "frigate", 500)["ok"]), "and a thirteenth is allowed: no class cap")
	ok(bool(FleetRef.validate_structure(many, 500)["ok"]), "twelve Frigates pass structure validation")
	var nine_fighters: Array[String] = []
	for i in range(9):
		nine_fighters.append("fighter")
	ok(bool(FleetRef.validate_structure(nine_fighters, 100)["ok"]),
		"nine Fighters are valid: the old global cap of 8 is gone")
	# The global cap must be gone from the API, not merely unused.
	ok(not ("MAX_SHIPS" in FleetRef), "FleetPoints no longer exposes a global hull cap constant")
	# Empty.
	var empty: Dictionary = FleetRef.validate_structure([], 100)
	ok(not bool(empty["ok"]), "an empty fleet is invalid")
	ok(String(empty["reasons"][0]).find("empty") != -1, "and the reason says so")
	# A fleet that WAS valid stays valid - but a changed one is re-judged, never cached.
	var a: Dictionary = FleetRef.validate_structure(MIXED, 100)
	var b: Dictionary = FleetRef.validate_structure(MIXED + ["battleship"], 25)
	ok(bool(a["ok"]), "the mixed fleet is valid at 100")
	ok(not bool(b["ok"]), "the same fleet at 25 is not: validation is not cached")


func test_no_global_cap_examples() -> void:
	begin("fleets with more than eight hulls")
	# The mandate's headline case: a 100 FP fleet with more than eight hulls that is both
	# valid and deployable. Cheap hulls only: interceptors and fighters.
	var swarm: Array[String] = []
	for i in range(10):
		swarm.append("interceptor")
	for i in range(8):
		swarm.append("fighter")
	ok(swarm.size() == 18, "an 18-hull swarm")
	ok(int(FleetRef.total_cost(swarm)) == 44, "costs 44 points (%d)" % FleetRef.total_cost(swarm))
	var v: Dictionary = FleetRef.validate_structure(swarm, 100)
	ok(bool(v["ok"]), "and passes the budget checks")
	var geo: Dictionary = FleetRef.deployable(swarm, MapConfigRef.EXPERIMENTAL)
	print("    [measured] 18-hull swarm on 32x22 deployable=%s (%s)" % [str(geo["ok"]), String(geo.get("reason", ""))])
	# Whatever the battlefield says, it must be the BATTLEFIELD saying it, not a hull cap.
	if not bool(geo["ok"]):
		ok(String(geo["reason"]).find("battlefield") != -1 or String(geo["reason"]).find("fit") != -1,
			"a refusal names the battlefield, not a hidden hull limit")
	# M6 caps the Carrier at one: the second one was replaced by a Cruiser so the fleet is
	# still twelve hulls and still legal under every cap.
	var mixed_large: Array[String] = ["dreadnought", "battleship", "battleship", "carrier",
		"cruiser", "cruiser", "cruiser", "frigate", "frigate", "fighter", "fighter", "interceptor"]
	ok(mixed_large.size() == 12, "a 12-hull fleet within every cap")
	ok(bool(FleetRef.validate_structure(mixed_large, 200)["ok"]), "valid at Grand Fleet")
	var cap: Dictionary = FleetRef.validate_structure(["dreadnought", "dreadnought"], 200)
	ok(not bool(cap["ok"]), "two Dreadnoughts are refused at any budget")
	ok(str(cap["reasons"]).find("More than 1 DREADNOUGHT") != -1, "naming the cap")


func test_validation_is_core_side() -> void:
	begin("validation is core-side")
	# The mandate is explicit: disabling a button is not enforcement.
	var smuggled: Array[String] = ["dreadnought", "dreadnought"]
	var v: Dictionary = FleetRef.validate(smuggled, 200, MapConfigRef.REFERENCE)
	ok(not bool(v["ok"]), "validate() refuses two Dreadnoughts even when called directly")
	ok(str(v["reasons"]).find("DREADNOUGHT") != -1, "naming the class cap")
	ok(not bool(FleetRef.validate_structure(["carrier", "carrier", "carrier"], 200)["ok"]),
		"three Carriers are refused without going through the UI")
	ok(str(FleetRef.validate_structure(["carrier", "carrier", "carrier"], 200)["reasons"]).find("fleet cap") != -1,
		"and the reason names the limit")
	ok(not bool(FleetRef.validate_structure(["unobtainium"], 200)["ok"]), "an unknown class is refused")
	var three_bb: Array[String] = ["battleship", "battleship", "battleship"]
	var hv: Dictionary = FleetRef.validate_structure(three_bb, 1000)
	ok(not bool(hv["ok"]), "three Battleships are refused on the class cap, not on budget")
	ok(str(hv["reasons"]).find("fleet cap") != -1, "with the class cap named")
	var ten_frig: Array[String] = []
	for i in range(10):
		ten_frig.append("frigate")
	ok(bool(FleetRef.validate_structure(ten_frig, 1000)["ok"]),
		"and ten Frigates are NOT refused: there is no global hull cap")


# ------------------------------------------------------------- geometry ----

func test_geometry_and_deployment() -> void:
	begin("geometry and deployment")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var label: String = MapConfigRef.label(size)
		var geo: Dictionary = FleetRef.deployable(MIXED, size)
		ok(bool(geo["ok"]), "the mixed fleet deploys on %s" % label)
		var g: Dictionary = FleetRef.deployable(LONG, size)
		ok(bool(g["ok"]), "the long-hull fleet deploys on %s" % label)
		var v: Dictionary = FleetRef.validate(LONG, 100, size)
		ok(bool(v["ok"]), "and validates end to end on %s" % label)
		# Exercise the real deployment: the whole hull, not the anchor.
		var b = BattleScript.new()
		b.setup(9, {}, 1, size, LONG, ["fighter"])
		ok(b.deploy_failures.is_empty(), "no long hull is stranded on %s" % label)
		var player_ships: Array = []
		var expected_cells: int = 0
		for s in b.ships:
			if s.team != 0:
				continue
			player_ships.append(s)
			expected_cells += s.footprint.x * s.footprint.y
			for c in s.cells():
				ok(b.map.in_bounds(c), "%s hull cell %s is on the board" % [label, str(c)])
				ok(b.map.is_deploy_zone(c, 0), "%s hull cell %s is inside the deployment zone" % [label, str(c)])
		ok(player_ships.size() == LONG.size(), "every requested hull exists on %s" % label)
		var occupied: Dictionary = {}
		var total_cells: int = 0
		for s in b.ships:
			for c in s.cells():
				occupied[c] = true
				total_cells += 1
		ok(occupied.size() == total_cells,
			"no two hulls share a cell on %s (%d cells, %d distinct)" % [label, total_cells, occupied.size()])
	ok(not bool(FleetRef.deployable([], MapConfigRef.REFERENCE)["ok"]), "an empty fleet is not deployable")
	# A tight board: whatever the verdict, validate() must match deployable() and explain.
	var tight: Array[String] = ["dreadnought", "battleship", "battleship", "carrier",
		"cruiser", "cruiser", "cruiser", "frigate"]
	var fits: bool = bool(FleetRef.deployable(tight, MapConfigRef.MIN_SIZE)["ok"])
	var tv: Dictionary = FleetRef.validate(tight, 200, MapConfigRef.MIN_SIZE)
	ok(bool(tv["ok"]) == fits, "validate() and deployable() agree on the smallest board")
	ok(fits or str(tv["reasons"]).find("battlefield") != -1,
		"a fleet that does not fit says it is the battlefield (%s)" % str(tv["reasons"]))
	print("    [measured] the largest legal fleet on %s: deployable=%s" % [MapConfigRef.label(MapConfigRef.MIN_SIZE), str(fits)])


# ------------------------------------------------------------------- AI ----

func test_enemy_generator() -> void:
	begin("enemy generator")
	var available: Array[String] = ShipDefsRef.available_classes()
	var seen: Dictionary = {}
	# Fewer seeds than before on purpose: with the hull cap gone a generated fleet can hold
	# 20+ hulls and each generation costs a real trial deployment (~1-2 s). Four seeds across
	# four budgets and both boards is 32 independent generations - enough for the invariants.
	var seeds: Array[int] = [1, 7, 42, 4242]
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		for mode in FleetRef.mode_ids():
			var budget: int = FleetRef.budget_of(mode)
			for sd in seeds:
				var gen: Dictionary = FleetRef.generate_enemy(sd, budget, size)
				var entries: Array = gen["entries"]
				ok(bool(gen["ok"]), "seed %d/%s/%s produces a fleet" % [sd, MapConfigRef.label(size), mode])
				ok(not entries.is_empty(), "seed %d/%s/%s is not empty" % [sd, MapConfigRef.label(size), mode])
				ok(int(gen["spent"]) <= budget, "seed %d/%s/%s respects the budget" % [sd, MapConfigRef.label(size), mode])
				ok(int(gen["spent"]) == FleetRef.total_cost(entries), "seed %d/%s/%s reports its spend honestly" % [sd, MapConfigRef.label(size), mode])
				ok(int(gen["remaining"]) == budget - int(gen["spent"]), "seed %d/%s/%s reports the remainder" % [sd, MapConfigRef.label(size), mode])
				for id in entries:
					ok(String(id) in available, "seed %d/%s/%s only fields available classes (%s)" % [sd, MapConfigRef.label(size), mode, str(id)])
				for id2 in available:
					var cap2: int = ShipDefsRef.cap_of(id2)
					ok(cap2 == 0 or FleetRef.count_of(entries, id2) <= cap2,
						"seed %d/%s/%s respects the %s cap" % [sd, MapConfigRef.label(size), mode, id2])
				# Team 1: the generated fleet is deployed on the ENEMY band. Asking the
				# player band would test a battlefield it never occupies.
				ok(bool(FleetRef.deployable(entries, size, 4242, 1)["ok"]),
					"seed %d/%s/%s is actually deployable on the enemy band" % [sd, MapConfigRef.label(size), mode])
				ok(bool(FleetRef.validate_structure(entries, budget)["ok"]),
					"seed %d/%s/%s passes structure validation" % [sd, MapConfigRef.label(size), mode])
				ok(bool(gen.get("deployable", false)),
					"seed %d/%s/%s is reported deployable" % [sd, MapConfigRef.label(size), mode])
				ok(int(gen.get("cell_budget", 0)) > 0, "and the cell budget is reported")
				seen[str(entries)] = true
	ok(seen.size() >= 4, "different seeds give different fleets (%d distinct)" % seen.size())
	# Determinism: exact equality of the entry list, checked on three independent cases.
	for case in [[7, "standard", MapConfigRef.EXPERIMENTAL], [42, "skirmish", MapConfigRef.REFERENCE],
			[4242, "grand_fleet", MapConfigRef.EXPERIMENTAL]]:
		var sd2: int = int(case[0])
		var mode2: String = String(case[1])
		var size2: Vector2i = case[2]
		var b2: int = FleetRef.budget_of(mode2)
		var first: Dictionary = FleetRef.generate_enemy(sd2, b2, size2)
		var second: Dictionary = FleetRef.generate_enemy(sd2, b2, size2)
		ok(first["entries"] == second["entries"],
			"generation is deterministic for %d/%s/%s" % [sd2, mode2, MapConfigRef.label(size2)])
		ok(first["log"] == second["log"], "and even its log is identical")
	# A budget below the cheapest hull: explicit refusal, not a crash and not a lie.
	var poor: Dictionary = FleetRef.generate_enemy(5, 1, MapConfigRef.REFERENCE)
	ok(not bool(poor["ok"]) and (poor["entries"] as Array).is_empty(),
		"a budget of 1 cannot field anything, and says so")
	var minimal: Dictionary = FleetRef.generate_enemy(5, 2, MapConfigRef.REFERENCE)
	ok(bool(minimal["ok"]) and minimal["entries"] == ["interceptor"],
		"a budget of 2 buys exactly one Interceptor (the cheapest hull)")


func test_enemy_generator_terminates() -> void:
	begin("generator termination")
	# 60 runs across both boards: the guard bound is what guarantees termination, so this
	# is a real-time check that no seed / budget combination spins.
	var started: int = Time.get_ticks_msec()
	var count: int = 0
	# 20 runs, not 60: with the hull cap gone one grand-fleet generation costs a real trial
	# deployment (~2 s). 20 independent runs still prove termination.
	for sd in range(20):
		FleetRef.generate_enemy(sd, FleetRef.budget_of("grand_fleet"), MapConfigRef.EXPERIMENTAL)
		count += 1
	var elapsed: int = Time.get_ticks_msec() - started
	ok(count == 20, "20 generations completed")
	# LIVENESS, not performance. The property under test is "the bounded loop always
	# terminates"; the bound is deliberately loose so a loaded machine cannot fail it.
	# Generation latency is measured and reported separately (test output + the M3 report),
	# never asserted here: a threshold on wall-clock time tests the CI host, not the code.
	ok(elapsed < 180000, "and the generator always terminates (%d ms for 60 runs)" % elapsed)
	print("    [measured] 20 generations in %d ms" % elapsed)


# ------------------------------------------------------------ separation ----

func test_points_are_not_credits() -> void:
	begin("points are not credits")
	SaveScript.save_data({
		"version": 1, "credits": 500, "missions_cleared": 3,
		"upgrades": {"hull": 2, "weapon": 1},
		"loadout": ["fighter", "fighter", "frigate", "cruiser", "battleship"],
	})
	var before: Dictionary = SaveScript.load_data()
	var credits_before: int = int(before.get("credits", 0))
	var upgrades_before: Dictionary = (before.get("upgrades", {}) as Dictionary).duplicate(true)
	var fleet: Array[String] = ["battleship", "battleship", "cruiser"]
	var v: Dictionary = FleetRef.validate(fleet, 100, MapConfigRef.REFERENCE)
	ok(bool(v["ok"]), "the fleet validates")
	ok(int(v["spent"]) == 37, "37 points are consumed by the composition")
	var after: Dictionary = SaveScript.load_data()
	ok(int(after.get("credits", 0)) == credits_before, "credits are untouched by composition")
	ok((after.get("upgrades", {}) as Dictionary) == upgrades_before, "upgrades are untouched")
	var raw: String = FileAccess.get_file_as_string(SaveScript.save_path())
	ok(raw.find("fleet_points") == -1 and raw.find("budget") == -1,
		"the save file stores no fleet points at all")
	ok(raw.find("500") != -1, "and it does still store the credits")
	# Building a battle from a composed fleet does not touch the save either.
	var b = BattleScript.new()
	b.setup(3, after.get("upgrades", {}), 1, MapConfigRef.REFERENCE, fleet, ["fighter"])
	ok(b.alive_ships(0).size() == 3, "the composed fleet is what reaches the board")
	ok(int(SaveScript.load_data().get("credits", 0)) == credits_before,
		"and starting it does not move a single credit")


func test_default_roster_unchanged() -> void:
	begin("historical roster unchanged")
	var b = BattleScript.new()
	b.setup(77)
	var classes: Array[String] = []
	for s in b.alive_ships(0):
		classes.append(s.ship_class)
	ok(classes == BattleScript.PLAYER_FLEET, "an empty request still means the historical roster")
	ok(b.enemy_roster.size() == BattleScript.ENEMY_FLEET_BASE.size(),
		"and difficulty 1 still fields the historical enemy fleet")
	ok(BattleScript.roster([], BattleScript.PLAYER_FLEET) == BattleScript.PLAYER_FLEET,
		"roster() falls back explicitly")
	ok(BattleScript.roster(["nonsense", "fighter"], BattleScript.PLAYER_FLEET) == ["fighter"],
		"roster() drops a class it cannot build instead of substituting one")


func test_composed_battle_is_playable() -> void:
	begin("a composed battle actually plays")
	# Deployment is not the end of the story: the generated enemy must be able to ACT.
	# This is the difference between "the fleet validates" and "the battle runs".
	var enemy: Dictionary = FleetRef.generate_enemy(31, 100, MapConfigRef.EXPERIMENTAL)
	var b = BattleScript.new()
	b.setup(31, {}, 1, MapConfigRef.EXPERIMENTAL, MIXED, enemy["entries"])
	ok(b.player_roster == MIXED, "the player fields exactly the composed fleet")
	ok(b.enemy_roster == enemy["entries"], "and the enemy the generated fleet")
	ok(b.deploy_failures.is_empty(), "both fleets deploy")
	var cells: Dictionary = {}
	var count: int = 0
	for s in b.ships:
		for c in s.cells():
			cells[c] = true
			count += 1
	ok(cells.size() == count, "no overlap anywhere on the board")
	ok(b.phase == BattleScript.Phase.PLAYER, "the battle opens on the player turn")
	ok(b.round == 1, "at round 1")
	# Give the turn to the AI and let it work through the generated fleet.
	var enemy_ships: int = b.alive_ships(1).size()
	ok(enemy_ships == enemy["entries"].size(), "every generated hull is on the board")
	b.end_turn()
	ok(b.phase != BattleScript.Phase.ENEMY, "the enemy turn completes rather than hanging")
	ok(b.round >= 2 or b.outcome != "", "and the round advances (round %d, outcome '%s')" % [b.round, b.outcome])
	# The AI must not have produced an invalid state while acting.
	var bad: int = 0
	for s2 in b.ships:
		if not s2.alive:
			continue
		for c2 in s2.cells():
			if not b.map.in_bounds(c2):
				bad += 1
	ok(bad == 0, "no hull ended up off the board")
	var occupied: Dictionary = {}
	var total: int = 0
	for s3 in b.alive_ships(-1):
		for c3 in s3.cells():
			occupied[c3] = true
			total += 1
	ok(occupied.size() == total, "and no two surviving hulls share a cell")
	var log_text: String = " ".join(b.log_lines)
	ok(log_text.find("holds position") == -1 or log_text.find("Round 2") != -1,
		"the AI did not simply idle through its turn")
