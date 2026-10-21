extends SceneTree
## Headless test suite for VOID COMMAND core rules.
## Exit 0 = all assertions passed, exit 1 = at least one failure.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const ShipScript = preload("res://scripts/core/ship.gd")
const DefsScript = preload("res://scripts/core/ship_defs.gd")
const CombatScript = preload("res://scripts/core/combat.gd")
const PathfinderScript = preload("res://scripts/core/pathfinder.gd")
const SaveScript = preload("res://scripts/core/save_data.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current_test: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — CORE TEST SUITE ===")
	# S0: never write the player's real save. The suite runs against a scratch
	# file; the real file is only fingerprinted, and asserted unchanged at the end.
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	print("  save under test: %s (%s)" % [SaveScript.save_path(), SaveGuard.describe(real_save_before)])
	test_map_determinism()
	test_deployment()
	test_movement_rules()
	test_los_and_targeting()
	test_damage_model()
	test_destruction()
	test_turn_state_machine()
	test_abilities()
	test_save_format()
	test_ai_legality()
	test_relay_objective()
	test_simultaneous_end()
	test_stalemate()
	test_battle_end_guards()
	test_full_battles()
	begin("save isolation")
	ok(SaveScript.save_path() != SaveGuard.REAL_SAVE, "the suite writes to an isolated path, not the real save")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")
	SaveGuard.cleanup()
	# Production behaviour must be intact: with the override cleared, SaveData
	# resolves the real path again (or the explicit CI env override, if set).
	var env_path: String = OS.get_environment(SaveScript.ENV_OVERRIDE)
	var expected: String = SaveScript.PATH if env_path == "" else env_path
	ok(SaveScript.save_path() == expected, "production save path is restored once the override is cleared")
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
		print("  FAIL  [%s] %s" % [current_test, label])


func begin(name: String) -> void:
	current_test = name
	print("- %s" % name)


func free_cell(map, from: Vector2i = Vector2i(0, 0)) -> Vector2i:
	for radius in range(0, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c: Vector2i = from + Vector2i(dx, dy)
				if map.in_bounds(c) and not map.is_blocked(c):
					return c
	return Vector2i(1, 1)


func test_map_determinism() -> void:
	begin("map determinism")
	var a = MapScript.new()
	a.setup(424242)
	var b = MapScript.new()
	b.setup(424242)
	var same: bool = true
	for i in range(a.cells.size()):
		if a.cells[i] != b.cells[i]:
			same = false
			break
	ok(same, "same seed produces identical terrain")
	ok(a.control_cell == b.control_cell, "same seed produces identical control point")
	var c = MapScript.new()
	c.setup(999)
	var diff: bool = false
	for i in range(mini(a.cells.size(), c.cells.size())):
		if a.cells[i] != c.cells[i]:
			diff = true
			break
	ok(diff, "different seed produces different terrain")
	ok(not a.is_blocked(a.control_cell), "control point is passable")
	var obstacles: int = 0
	for y in range(a.height):
		for x in range(a.width):
			if a.is_blocked(Vector2i(x, y)):
				obstacles += 1
	# M6 removed asteroid fields: the reference board now carries planets only, so the old
	# "more than ten blocked cells" threshold was an asteroid-density assertion in disguise.
	# Terrain must still block - just fewer cells - so the bound is what the generator
	# actually produces, not a remembered number.
	ok(obstacles >= 4, "map has blocking terrain (%d cells)" % obstacles)


func test_deployment() -> void:
	begin("deployment")
	var b = BattleScript.new()
	b.setup(1001)
	ok(b.ships.size() == 9, "9 ships deployed (5 player, 4 enemy)")
	var player := b.alive_ships(0)
	var enemy := b.alive_ships(1)
	ok(player.size() == 5, "player fleet has 5 ships")
	ok(enemy.size() == 4, "enemy fleet has 4 ships")
	var classes: Dictionary = {}
	for s in player:
		classes[s.ship_class] = true
	ok(classes.size() == 4, "player fleet spans 4 distinct classes")
	ok(classes.has("fighter") and classes.has("frigate") and classes.has("cruiser") and classes.has("battleship"), "all four classes present")
	var occupied: Dictionary = {}
	var all_valid: bool = true
	var all_in_zone: bool = true
	for s in b.ships:
		if occupied.has(s.cell):
			all_valid = false
		occupied[s.cell] = true
		if b.map.is_blocked(s.cell):
			all_valid = false
		if not b.map.is_deploy_zone(s.cell, s.team):
			all_in_zone = false
	ok(all_valid, "no overlapping or blocked deployment")
	ok(all_in_zone, "every ship is inside its own deployment zone")


func test_movement_rules() -> void:
	begin("movement rules")
	var b = BattleScript.new()
	b.setup(2002)
	var s = b.alive_ships(0)[0]
	var explored: Dictionary = b.reachable_cells(s.id)
	var dist: Dictionary = explored["dist"]
	var max_reach: int = 0
	for c in dist.keys():
		max_reach = maxi(max_reach, int(dist[c]))
	ok(max_reach <= s.move_points, "reachable set respects movement points (%d <= %d)" % [max_reach, s.move_points])
	var blocked_dest := Vector2i(-1, -1)
	for y in range(b.map.height):
		for x in range(b.map.width):
			if b.map.is_blocked(Vector2i(x, y)):
				blocked_dest = Vector2i(x, y)
				break
		if blocked_dest.x >= 0:
			break
	ok(blocked_dest.x >= 0, "found a blocked cell to test")
	var r_blocked: Dictionary = b.move_ship(s.id, blocked_dest)
	ok(not bool(r_blocked["ok"]), "cannot move into impassable terrain")
	var other = b.alive_ships(0)[1]
	var r_occupied: Dictionary = b.move_ship(s.id, other.cell)
	ok(not bool(r_occupied["ok"]), "cannot move onto an occupied cell")
	var before_points: int = s.move_points
	var dest: Vector2i = s.cell
	for c in dist.keys():
		if int(dist[c]) == 2:
			dest = c
			break
	var r_move: Dictionary = b.move_ship(s.id, dest)
	ok(bool(r_move["ok"]), "legal move accepted: %s" % String(r_move.get("reason", "")))
	ok(s.cell == dest, "ship position updated")
	ok(s.move_points == before_points - int(r_move["cost"]), "movement points consumed")
	var again: Dictionary = b.move_ship(s.id, s.cell)
	ok(not bool(again["ok"]), "moving onto own cell rejected")
	# Path reconstruction is contiguous and starts at the origin.
	var path: Array = r_move["path"]
	var contiguous: bool = true
	for i in range(1, path.size()):
		if PathfinderScript.manhattan(path[i - 1], path[i]) != 1:
			contiguous = false
	ok(contiguous, "path is orthogonal and contiguous")


func test_los_and_targeting() -> void:
	begin("line of sight and targeting")
	var b = BattleScript.new()
	b.setup(3003)
	# Clear a firing corridor so terrain cannot mask the rule under test.
	for x in range(4, 13):
		for y in range(4, 10):
			b.map.cells[y * b.map.width + x] = MapScript.Terrain.VOID
	var shooter = b.alive_ships(0)[2]
	var target = b.alive_ships(1)[0]
	# Friendly fire is always illegal.
	var friendly: Dictionary = b.can_attack(shooter.id, b.alive_ships(0)[0].id)
	ok(not bool(friendly["ok"]), "friendly fire rejected")
	# Out of range is illegal.
	shooter.cell = Vector2i(6, 7)
	target.cell = shooter.cell + Vector2i(shooter.attack_range + 4, 0)
	var out_of_range: Dictionary = b.can_attack(shooter.id, target.id)
	ok(not bool(out_of_range["ok"]), "out of range attack rejected: %s" % String(out_of_range["reason"]))
	# LOS blocked by an alanet between the two ships.
	var mid := Vector2i(8, 7)
	b.map.cells[mid.y * b.map.width + mid.x] = MapScript.Terrain.PLANET
	var blocked_target = b.alive_ships(1)[1]
	blocked_target.cell = Vector2i(9, 7)   # 3 cells from the frigate: inside its range
	var los: Dictionary = b.can_attack(shooter.id, blocked_target.id)
	ok(not b.map.has_line_of_sight(shooter.cell, blocked_target.cell), "planet blocks line of sight")
	ok(not bool(los["ok"]), "attack through an alanet rejected: %s" % String(los["reason"]))
	# Footprint LOS (STEP2): a 1x4 hull may fire from a cell whose lane is clear even
	# when its anchor is masked. This is the documented S5 rule ("one clear cell pair
	# is enough"), and it is exactly why the assertion above needs a 1x1 shooter.
	var wide = b.alive_ships(0)[4]
	wide.cell = Vector2i(5, 5)   # 1x4 -> (5,5),(5,6),(5,7),(5,8)
	blocked_target.cell = Vector2i(9, 7)   # 3 cells from the frigate: inside its range
	ok(b.map.has_line_of_sight(Vector2i(5, 5), Vector2i(10, 7)), "a clear lane exists from the hull's far cell")
	ok(b.footprint_distance(wide, blocked_target) <= wide.attack_range, "the hull is inside its own range")
	var wide_check: Dictionary = b.can_attack(wide.id, blocked_target.id)
	ok(bool(wide_check["ok"]), "the 1x4 hull fires past the alanet from its clear cell: %s" % String(wide_check["reason"]))
	# Clear the rock: same distance, now legal.
	b.map.cells[mid.y * b.map.width + mid.x] = MapScript.Terrain.VOID
	ok(b.map.has_line_of_sight(shooter.cell, blocked_target.cell), "line of sight restored")
	ok(bool(b.can_attack(shooter.id, blocked_target.id)["ok"]), "in-range clear-shot attack accepted")
	var shot: Dictionary = b.attack(shooter.id, blocked_target.id)
	ok(bool(shot["ok"]), "attack resolved")
	ok(shooter.has_attacked, "attacker flagged as having fired")
	ok(not bool(b.can_attack(shooter.id, blocked_target.id)["ok"]), "double attack rejected")


func test_damage_model() -> void:
	begin("damage model")
	var map = MapScript.new()
	map.setup(7)
	var open_cell: Vector2i = free_cell(map, Vector2i(9, 7))
	map.cells[open_cell.y * map.width + open_cell.x] = MapScript.Terrain.VOID
	var attacker = ShipScript.create("fighter", 0, 1, 0)
	var target = ShipScript.create("frigate", 1, 2, 0)
	attacker.cell = Vector2i(0, 0)
	target.cell = open_cell
	var first: Dictionary = CombatScript.resolve(attacker, target, map)
	ok(is_equal_approx(float(first["shield"]), 11.0), "fighter damage (11) fully absorbed by shields")
	ok(is_equal_approx(float(first["hull"]), 0.0), "no hull damage while shields hold")
	ok(is_equal_approx(target.shield, 15.0), "shield pool reduced correctly")
	target.shield = 0.0
	var second: Dictionary = CombatScript.resolve(attacker, target, map)
	ok(is_equal_approx(float(second["hull"]), 10.0), "armor 1 reduces 11 damage to 10 hull")
	var ignored: Dictionary = CombatScript.resolve(attacker, target, map, {"ignore_armor": true})
	ok(is_equal_approx(float(ignored["hull"]), 11.0), "armor bypass deals full damage")
	target.evading = true
	var evaded: Dictionary = CombatScript.resolve(attacker, target, map)
	ok(is_equal_approx(float(evaded["raw"]), 6.0), "evasive target halves incoming damage (ceil 5.5 = 6)")
	target.evading = false


func test_destruction() -> void:
	begin("destruction and targeting cleanup")
	var b = BattleScript.new()
	b.setup(4004)
	for x in range(5, 13):
		b.map.cells[7 * b.map.width + x] = MapScript.Terrain.VOID
	var shooter = b.alive_ships(0)[4]
	var victim = b.alive_ships(1)[2]
	shooter.cell = Vector2i(6, 7)
	victim.cell = Vector2i(8, 7)
	victim.shield = 0.0
	victim.hull = 5.0
	var res: Dictionary = b.attack(shooter.id, victim.id)
	ok(bool(res["ok"]), "lethal attack resolved")
	ok(not victim.alive, "victim marked destroyed")
	ok(victim.hull <= 0.0, "destroyed ship hull is zero")
	var remaining := b.alive_ships(1)
	var still_listed: bool = false
	for s in remaining:
		if s.id == victim.id:
			still_listed = true
	ok(not still_listed, "destroyed ship removed from active list")
	ok(not bool(b.can_attack(shooter.id, victim.id)["ok"]), "destroyed ship cannot be targeted")
	ok(not bool(b.move_ship(victim.id, victim.cell + Vector2i(1, 0))["ok"]), "destroyed ship cannot move")


func test_turn_state_machine() -> void:
	begin("turn state machine")
	var b = BattleScript.new()
	b.setup(5005)
	ok(b.phase == BattleScript.Phase.PLAYER, "battle starts in player phase")
	ok(b.round == 1, "battle starts at round 1")
	ok(b.end_turn(), "end turn accepted in player phase")
	ok(b.phase == BattleScript.Phase.PLAYER or b.outcome != "", "control returns to player after AI")
	var round_after: int = b.round
	if b.outcome == "":
		ok(round_after == 2, "round advanced to 2")
	# Double transitions: ending twice in the same instant is impossible because phase changed.
	b.phase = BattleScript.Phase.ENEMY
	ok(not b.end_turn(), "end turn rejected outside player phase")
	b.phase = BattleScript.Phase.PLAYER
	# Resources restored at the start of the round.
	var s = b.alive_ships(0)[0]
	if s != null:
		ok(s.move_points == s.max_move, "movement restored for the new round")
	# Selecting an enemy is rejected.
	var e = b.alive_ships(1)[0]
	ok(not b.select(e.id), "enemy ship cannot be selected")
	ok(b.select(b.alive_ships(0)[0].id), "player ship can be selected")


func test_abilities() -> void:
	begin("special abilities")
	var b = BattleScript.new()
	b.setup(6006)
	# Fighter: evasive burn, free action, adds movement.
	var fighter = null
	var frigate = null
	var cruiser = null
	var battleship = null
	for s in b.alive_ships(0):
		if s.ship_class == "fighter" and fighter == null:
			fighter = s
		elif s.ship_class == "frigate":
			frigate = s
		elif s.ship_class == "cruiser":
			cruiser = s
		elif s.ship_class == "battleship":
			battleship = s
	ok(fighter != null and frigate != null and cruiser != null and battleship != null, "all ability carriers present")
	var mp: int = fighter.move_points
	var r: Dictionary = b.use_ability(fighter.id)
	ok(bool(r["ok"]), "evasive burn accepted")
	ok(fighter.move_points == mp + 3, "evasive burn adds 3 movement")
	ok(fighter.evading, "evasive flag set")
	ok(fighter.ability_cooldown == 2, "evasive burn on cooldown")
	ok(not bool(b.use_ability(fighter.id)["ok"]), "ability cannot be spammed")
	ok(not fighter.has_attacked, "evasive burn does not consume the attack")
	# Frigate precision strike on an adjacent enemy.
	for x in range(4, 14):
		b.map.cells[6 * b.map.width + x] = MapScript.Terrain.VOID
		b.map.cells[7 * b.map.width + x] = MapScript.Terrain.VOID
		b.map.cells[8 * b.map.width + x] = MapScript.Terrain.VOID
	frigate.cell = Vector2i(6, 7)
	var enemy = b.alive_ships(1)[0]
	enemy.cell = Vector2i(7, 7)
	var hit_before: float = enemy.shield + enemy.hull
	var prec: Dictionary = b.use_ability(frigate.id, enemy.id)
	ok(bool(prec["ok"]), "precision strike accepted: %s" % String(prec.get("reason", "")))
	ok(enemy.shield + enemy.hull < hit_before, "precision strike deals damage")
	ok(frigate.has_attacked, "precision strike consumes the attack")
	ok(frigate.ability_cooldown == 2, "precision strike on cooldown")
	# Cruiser shield surge on itself.
	cruiser.shield = 0.0
	var surge: Dictionary = b.use_ability(cruiser.id, cruiser.id)
	ok(bool(surge["ok"]), "shield surge accepted")
	ok(cruiser.shield >= 26.0, "shield surge restores shields")
	# Battleship salvo with splash.
	battleship.cell = Vector2i(6, 7)
	var target = b.alive_ships(1)[1]
	target.cell = Vector2i(9, 7)
	var splash_target = b.alive_ships(1)[2]
	splash_target.cell = Vector2i(9, 8)
	var hp_before: float = splash_target.shield + splash_target.hull
	var salvo: Dictionary = b.use_ability(battleship.id, target.id)
	ok(bool(salvo["ok"]), "heavy salvo accepted: %s" % String(salvo.get("reason", "")))
	ok(splash_target.shield + splash_target.hull < hp_before, "salvo splash damages adjacent ship")


func test_save_format() -> void:
	begin("save data")
	var d: Dictionary = SaveScript.default_data()
	ok(int(d["version"]) == 1, "save format is versioned")
	var fresh: Dictionary = SaveScript.sanitize({"version": 1, "credits": -50, "upgrades": {"fighter": {"hull": 9}}, "stats": {}})
	ok(int(fresh["credits"]) == 0, "negative credits clamped")
	ok(int(fresh["upgrades"]["fighter"]["hull"]) == 3, "upgrade levels clamped to max")
	fresh["credits"] = 500
	var shopper: Dictionary = SaveScript.default_data()
	shopper["credits"] = 500
	var buy: Dictionary = SaveScript.buy_upgrade(shopper, "fighter", "hull")
	ok(bool(buy["ok"]), "upgrade purchase accepted: %s" % String(buy.get("reason", "")))
	ok(int(buy["data"]["upgrades"]["fighter"]["hull"]) == 1, "upgrade level increments")
	ok(int(buy["data"]["credits"]) == 400, "credits deducted (100)")
	var poor: Dictionary = SaveScript.sanitize({"credits": 0})
	var denied: Dictionary = SaveScript.buy_upgrade(poor, "cruiser", "weapon")
	ok(not bool(denied["ok"]), "purchase denied without credits")
	var applied = ShipScript.create("fighter", 0, 1, 0, {"hull": 2, "weapon": 2})
	ok(applied.max_hull > 38.0, "hull upgrade increases max hull")
	ok(applied.base_damage > 11.0, "weapon upgrade increases damage")
	# Actual file round-trip.
	var data: Dictionary = SaveScript.default_data()
	data["credits"] = 321
	data["last_seed"] = 987654
	var saved: bool = SaveScript.save_data(data)
	ok(saved, "save file written")
	var loaded: Dictionary = SaveScript.load_data()
	ok(int(loaded["credits"]) == 321, "credits survive round-trip")
	ok(int(loaded["last_seed"]) == 987654, "seed survives round-trip")


func test_ai_legality() -> void:
	begin("AI legality")
	var b = BattleScript.new()
	b.setup(7007)
	for turn in range(6):
		if b.outcome != "":
			break
		b.end_turn()
		var seen: Dictionary = {}
		var legal: bool = true
		for s in b.ships:
			if not s.alive:
				continue
			if seen.has(s.cell):
				legal = false
			seen[s.cell] = true
			if b.map.is_blocked(s.cell):
				legal = false
			if s.hull < 0.0 or s.shield < 0.0:
				legal = false
		ok(legal, "after AI turn %d: no stacking, no blocked cells, no negative pools" % (turn + 1))
		ok(b.phase == BattleScript.Phase.PLAYER or b.outcome != "", "AI handed control back on turn %d" % (turn + 1))


func test_relay_objective() -> void:
	begin("relay objective")
	var b = BattleScript.new()
	b.setup(9009)
	var s = b.alive_ships(0)[0]
	s.cell = b.map.control_cell
	var enemy = b.alive_ships(1)[0]
	var shield_before: float = enemy.shield
	for i in range(3):
		b._tick_control()
	ok(b.control_hold == 3, "relay hold counts to 3")
	ok(b.control_bonus_claimed, "relay bonus triggers at 3 rounds")
	ok(enemy.shield < shield_before, "relay bonus disrupts enemy shields")
	var reward: Dictionary = b.compute_reward()
	ok(int(reward["credits"]) > 0, "reward computed")
	var has_relay_line: bool = false
	for l in reward["lines"]:
		if String(l).find("Relay") >= 0:
			has_relay_line = true
	ok(has_relay_line, "reward breakdown lists the relay bonus")


func test_simultaneous_end() -> void:
	begin("simultaneous fleet destruction")
	var b = BattleScript.new()
	b.setup(9010)
	for s in b.ships:
		s.alive = false
		s.hull = 0.0
	b._check_outcome()
	ok(b.outcome == "defeat", "mutual annihilation resolves as defeat")
	ok(b.phase == BattleScript.Phase.OVER, "phase moves to OVER")
	ok(b.selected_id == -1, "selection cleared when the battle ends")


func test_stalemate() -> void:
	begin("round limit")
	var b = BattleScript.new()
	b.setup(9011)
	b.round = BattleScript.MAX_ROUNDS
	b._finish_round()
	ok(b.outcome == "defeat", "round limit produces a defeat")
	ok(b.phase == BattleScript.Phase.OVER, "phase is OVER after the round limit")


func test_battle_end_guards() -> void:
	begin("battle end guards")
	# S0: once the battle is OVER the rules layer must reject every gameplay
	# action on its own, with no mutation - the UI guards are not the contract.
	var b = BattleScript.new()
	b.setup(6100)
	for e in b.alive_ships(1):
		e.alive = false
		e.hull = 0.0
	b._check_outcome()
	ok(b.outcome == "victory", "the battle reaches a terminal outcome")
	ok(b.phase == BattleScript.Phase.OVER, "phase is OVER")

	var mover = b.alive_ships(0)[0]
	var reachable: Dictionary = b.reachable_cells(mover.id)["dist"]
	var dest: Vector2i = mover.cell
	for c in reachable.keys():
		if int(reachable[c]) > 0:
			dest = c
			break
	var cell_before: Vector2i = mover.cell
	var mp_before: int = mover.move_points
	var round_before: int = b.round
	var phase_before: int = b.phase
	var events_before: int = b.events.size()
	var log_before: int = b.log_lines.size()
	var control_before: int = b.control_hold
	var owner_before: int = b.control_owner

	ok(dest != mover.cell, "a legal destination exists, so the rejection cannot come from pathing")
	var mv: Dictionary = b.move_ship(mover.id, dest)
	ok(not bool(mv["ok"]), "move_ship rejected after OVER")
	ok(mover.cell == cell_before, "position unchanged after the rejected move")
	ok(mover.move_points == mp_before, "movement points unchanged after the rejected move")

	# Attack path: a living hostile in range, then the terminal state exactly as
	# _check_outcome() sets it.
	var b2 = BattleScript.new()
	b2.setup(6101)
	for x in range(0, b2.map.width):
		b2.map.cells[7 * b2.map.width + x] = MapScript.Terrain.VOID
	var attacker = b2.alive_ships(0)[0]
	var victim = b2.alive_ships(1)[0]
	attacker.cell = Vector2i(5, 7)
	victim.cell = Vector2i(6, 7)
	ok(bool(b2.can_attack(attacker.id, victim.id)["ok"]), "the shot is legal before the battle ends")
	var hull_before: float = victim.hull
	var shield_before: float = victim.shield
	b2.outcome = "victory"
	b2.phase = BattleScript.Phase.OVER
	var chk: Dictionary = b2.can_attack(attacker.id, victim.id)
	ok(not bool(chk["ok"]), "can_attack rejected after OVER")
	var atk: Dictionary = b2.attack(attacker.id, victim.id)
	ok(not bool(atk["ok"]), "attack rejected after OVER")
	ok(is_equal_approx(victim.hull, hull_before) and is_equal_approx(victim.shield, shield_before), "target hull and shield unchanged")
	ok(not attacker.has_attacked, "attacker not flagged as having fired")
	ok(b2.events.is_empty(), "no battle events emitted by the rejected attack")

	# Ability path: the cruiser's Shield Surge aimed at itself.
	var b3 = BattleScript.new()
	b3.setup(6102)
	var cruiser = b3.alive_ships(0)[3]
	var shield_before3: float = cruiser.shield
	var cd_before: int = cruiser.ability_cooldown
	b3.outcome = "victory"
	b3.phase = BattleScript.Phase.OVER
	var achk: Dictionary = b3.can_use_ability(cruiser.id, cruiser.id)
	ok(not bool(achk["ok"]), "can_use_ability rejected after OVER")
	var abil: Dictionary = b3.use_ability(cruiser.id, cruiser.id)
	ok(not bool(abil["ok"]), "use_ability rejected after OVER")
	ok(is_equal_approx(cruiser.shield, shield_before3), "shield unchanged after the rejected ability")
	ok(cruiser.ability_cooldown == cd_before, "cooldown unchanged after the rejected ability")
	ok(b3.events.is_empty(), "no battle events emitted by the rejected ability")

	ok(not b.end_turn(), "end_turn still rejected after OVER")
	ok(b.round == round_before and b.phase == phase_before, "round and phase unchanged")
	ok(b.events.size() == events_before, "no battle events emitted by the rejected move")
	ok(b.log_lines.size() == log_before, "no log lines emitted by rejected actions")
	ok(b.control_hold == control_before and b.control_owner == owner_before and not b.control_bonus_claimed,
		"relay state unchanged (hold, owner, bonus)")

	# Active-turn behaviour is untouched: the same calls still work mid-battle.
	var b4 = BattleScript.new()
	b4.setup(6103)
	var s4 = b4.alive_ships(0)[0]
	var ex4: Dictionary = b4.reachable_cells(s4.id)["dist"]
	var d4: Vector2i = s4.cell
	for c in ex4.keys():
		if int(ex4[c]) == 1:
			d4 = c
			break
	ok(bool(b4.move_ship(s4.id, d4)["ok"]), "movement still accepted during the player phase")
	ok(bool(b4.can_use_ability(s4.id)["ok"]), "ability still accepted during the player phase")


func test_full_battles() -> void:
	begin("full battle simulation")
	var seeds: Array[int] = [11, 4242, 98765]
	for sd in seeds:
		var b = BattleScript.new()
		b.setup(sd)
		var rounds: int = 0
		while b.outcome == "" and rounds < 45:
			rounds += 1
			_player_auto(b)
			if b.outcome != "":
				break
			b.end_turn()
		ok(b.outcome == "victory" or b.outcome == "defeat", "seed %d reaches an outcome (%s, round %d)" % [sd, b.outcome, b.round])
		var reward: Dictionary = b.compute_reward()
		ok(int(reward["credits"]) >= 0, "seed %d reward is non-negative" % sd)
		ok(String(b.summary()["outcome"]) == b.outcome, "seed %d summary is consistent" % sd)


func _player_auto(b) -> void:
	for s in b.alive_ships(0):
		if s.has_attacked:
			continue
		var best = null
		var best_d: int = 9999
		for e in b.alive_ships(1):
			var d: int = PathfinderScript.manhattan(s.cell, e.cell)
			if bool(b.can_attack(s.id, e.id)["ok"]) and d < best_d:
				best_d = d
				best = e
		if best != null:
			b.attack(s.id, best.id)
			continue
		# Move toward the closest enemy.
		var target = null
		var target_d: int = 9999
		for e in b.alive_ships(1):
			var d2: int = PathfinderScript.manhattan(s.cell, e.cell)
			if d2 < target_d:
				target_d = d2
				target = e
		if target == null:
			return
		var explored: Dictionary = b.reachable_cells(s.id)
		var field: Dictionary = PathfinderScript.distance_field(b.map, target.cell)
		var best_cell: Vector2i = s.cell
		var best_score: int = -99999
		for c in explored["dist"].keys():
			var score: int = -int(field.get(c, 9999)) * 10
			if PathfinderScript.manhattan(c, target.cell) <= s.attack_range and b.map.has_line_of_sight(c, target.cell):
				score += 60
			if score > best_score:
				best_score = score
				best_cell = c
		if best_cell != s.cell:
			b.move_ship(s.id, best_cell)
		if bool(b.can_attack(s.id, target.id)["ok"]):
			b.attack(s.id, target.id)
