class_name Battle
extends RefCounted
## Turn state machine + rules. No nodes, no drawing: everything here runs headless.

const MapRef = preload("res://scripts/core/battle_map.gd")
const ShipRef = preload("res://scripts/core/ship.gd")
const DefsRef = preload("res://scripts/core/ship_defs.gd")
const CombatRef = preload("res://scripts/core/combat.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const AIRef = preload("res://scripts/core/ai.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")

enum Phase { PLAYER = 0, ENEMY = 1, OVER = 2 }

const PLAYER_FLEET: Array[String] = ["fighter", "fighter", "frigate", "cruiser", "battleship"]
const ENEMY_FLEET_BASE: Array[String] = ["fighter", "fighter", "frigate", "cruiser"]
const MAX_ROUNDS: int = 40

var map: BattleMap
var ships: Array[Ship] = []
var by_id: Dictionary = {}
var seed_value: int = 1
var round: int = 1
var phase: int = Phase.PLAYER
var outcome: String = ""
var selected_id: int = -1
var log_lines: Array[String] = []
var events: Array[Dictionary] = []
var last_message: String = ""
var control_hold: int = 0
var control_owner: int = -1
var control_bonus_claimed: bool = false
var rng: RandomNumberGenerator
var ai_rng: RandomNumberGenerator
var difficulty: int = 1
var player_upgrades: Dictionary = {}
var enemy_hull_scale: float = 1.0
var losses: Array[String] = []
var deploy_failures: Array[String] = []
## Classes that had to be deployed in a sealed pocket because no better cell existed.
## Non-empty means the map is hostile to that hull - reported, never silent.
var pocket_fallbacks: Array[String] = []
## True once the battle's credits/record have been written to the campaign save. It is
## part of the snapshot so a restored battle can never pay the same victory twice.
var reward_granted: bool = false
## Per-phase timings of the last `setup()` call, in microseconds (M5 profiling).
var setup_profile: Dictionary = {}
## Deployment-search counters, reset by `setup()` and accumulated per placement attempt.
var deploy_probe_us: int = 0
var deploy_probe_calls: int = 0
var ai_enabled: bool = true
var ai_aggression: float = 0.8
## Dimensions the battle was built for (kept so the UI can size itself without
## asking the map again, and so a saved/replayed battle knows its board).
var map_size: Vector2i = MapConfig.REFERENCE
## Rosters this battle was created with. Empty input means the historical fleets.
var player_roster: Array[String] = ["fighter", "fighter", "frigate", "cruiser", "battleship"]
var enemy_roster: Array[String] = []


func setup(p_seed: int, p_upgrades: Dictionary = {}, p_difficulty: int = 1,
		p_map_size: Vector2i = MapConfig.REFERENCE,
		p_player_fleet: Array = [], p_enemy_fleet: Array = []) -> void:
	## Empty fleets mean "the historical roster", so every existing caller keeps its exact
	## behaviour; a composed fleet (STEP 3) is passed in explicitly.
	## Phase timings for this setup, in microseconds. Cheap (a handful of clocks) and it
	## makes the M5 profiling reproducible instead of a stopwatch on the whole call.
	setup_profile = {}
	var _t0: int = Time.get_ticks_usec()
	seed_value = p_seed
	player_upgrades = p_upgrades.duplicate(true)
	difficulty = maxi(1, p_difficulty)
	enemy_hull_scale = 1.0 + 0.08 * float(difficulty - 1)
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	ai_rng = RandomNumberGenerator.new()
	ai_rng.seed = p_seed ^ 0x5DEECE66
	map = MapRef.new()
	map_size = p_map_size if MapConfig.is_valid(p_map_size) else MapConfig.REFERENCE
	map.setup(p_seed, map_size)
	setup_profile["map_us"] = Time.get_ticks_usec() - _t0
	var _t_ships: int = Time.get_ticks_usec()
	deploy_probe_us = 0
	deploy_probe_calls = 0
	ships.clear()
	by_id.clear()
	log_lines.clear()
	events.clear()
	losses.clear()
	deploy_failures.clear()
	pocket_fallbacks.clear()
	outcome = ""
	round = 1
	phase = Phase.PLAYER
	selected_id = -1
	control_hold = 0
	control_owner = -1
	control_bonus_claimed = false
	last_message = ""
	player_roster = roster(p_player_fleet, PLAYER_FLEET)
	enemy_roster = roster(p_enemy_fleet, _default_enemy_fleet())
	_deploy()
	setup_profile["deploy_search_us"] = deploy_probe_us
	setup_profile["deploy_attempts"] = deploy_probe_calls
	setup_profile["ships_and_deploy_us"] = Time.get_ticks_usec() - _t_ships
	setup_profile["total_us"] = Time.get_ticks_usec() - _t0
	log_lines.append("Battle joined — seed %d, round 1." % p_seed)
	log_lines.append("Destroy every hostile ship. Relay station is optional.")


static func roster(requested: Array, fallback: Array[String]) -> Array[String]:
	## A requested roster wins; an empty one falls back to the historical list. Unknown
	## or unplayable classes are dropped here (and refused earlier by FleetPoints).
	if requested == null or requested.is_empty():
		return fallback.duplicate()
	var out: Array[String] = []
	for id in requested:
		var cid: String = String(id)
		if ShipDefs.DEFS.has(cid):
			out.append(cid)
	return out if not out.is_empty() else fallback.duplicate()


func _default_enemy_fleet() -> Array[String]:
	var enemy_fleet: Array[String] = ENEMY_FLEET_BASE.duplicate()
	if difficulty >= 2:
		enemy_fleet.append("battleship")
	if difficulty >= 3:
		enemy_fleet.append("fighter")
	if difficulty >= 4:
		enemy_fleet.append("cruiser")
	return enemy_fleet


func _deploy() -> void:
	var player_cells: Array[Vector2i] = _shuffled_zone(0)
	var enemy_cells: Array[Vector2i] = _shuffled_zone(1)
	var next_id: int = 0
	var index: int = 0
	for class_id in player_roster:
		var up: Dictionary = player_upgrades.get(class_id, {})
		var s: Ship = ShipRef.create(class_id, 0, next_id, index, up, 1.0)
		s.orientation = ShipRef.initial_orientation(s.footprint)
		s.placed = false
		var _tp: int = Time.get_ticks_usec()
		s.cell = _take_deployment_cell(player_cells, s, 0)
		deploy_probe_us += Time.get_ticks_usec() - _tp
		deploy_probe_calls += 1
		if s.cell.x < 0:
			# No cell means no ship. Adding the hull anyway put it at (-1,-1), i.e.
			# OUTSIDE the grid - the M7 defect, measured at 49 hulls on a 20x14 board.
			# The failure is already in `deploy_failures`; the hull must not exist.
			next_id += 1
			continue
		s.placed = true
		next_id += 1
		index += 1
		_add_ship(s)
	index = 0
	for class_id in enemy_roster:
		var s2: Ship = ShipRef.create(class_id, 1, next_id, index, {}, enemy_hull_scale)
		s2.orientation = ShipRef.initial_orientation(s2.footprint)
		s2.placed = false
		var _te: int = Time.get_ticks_usec()
		s2.cell = _take_deployment_cell(enemy_cells, s2, 1)
		deploy_probe_us += Time.get_ticks_usec() - _te
		deploy_probe_calls += 1
		if s2.cell.x < 0:
			next_id += 1
			continue
		s2.placed = true
		next_id += 1
		index += 1
		_add_ship(s2)


func _take_deployment_cell(pool: Array[Vector2i], ship: Ship, team: int) -> Vector2i:
	## Authoritative deployment pick for a whole footprint.
	##
	## The FIRST candidate is always the cell the single-cell deployment would have
	## used (same shuffled pool, same pop), so the RNG stream and the 1x1 layout are
	## untouched. Only when that cell cannot host the whole footprint do we keep
	## popping from the SAME shuffled pool - a deterministic scan with no extra
	## random draws, so the same seed still reproduces the same fleet exactly.
	##
	## STEP 2.1 adds a POCKET check: a cell that fits the hull but seals it in (no legal
	## state can get it out of its own deployment band) is skipped. The fallback is
	## deterministic: if every legal cell is pocketed, the first one in pool order is
	## used and the fact is recorded, so a fleet is never left unplaced by a map quirk.
	##
	## Returns Vector2i(-1, -1) when the pool is exhausted; the caller records the
	## failure in `deploy_failures` and never leaves a half-placed hull behind.
	var pocketed: Array[Vector2i] = []
	# Scan WITHOUT consuming rejected candidates: `pop_back()` on every miss emptied the
	# pool, so one undeployable capital hull left every hull after it without a cell.
	# Only the chosen cell is removed from the pool, which is the only thing a placement
	# has to consume.
	var scan: int = pool.size() - 1
	while scan >= 0:
		var c: Vector2i = pool[scan]
		scan -= 1
		if not _footprint_in_zone(c, ship.footprint, ship.orientation, team):
			continue
		if not can_place(c, ship.footprint, ship.orientation, -1):
			continue
		if _pocket_ok(c, ship, team):
			pool.erase(c)
			return c
		pocketed.append(c)
	if not pocketed.is_empty():
		# Deterministic fallback: legal but sealed. Prefer it to no deployment at all,
		# and say so - a silently pocketed capital hull is how STEP 1 stranded one.
		pocket_fallbacks.append(ship.ship_class)
		return pocketed[0]
	deploy_failures.append(ship.ship_class)
	push_error("Deployment failed: no legal %s footprint in the %s deployment zone." % [
		str(ship.footprint), "player" if team == 0 else "enemy"])
	return Vector2i(-1, -1)


func _pocket_ok(cell: Vector2i, ship: Ship, team: int) -> bool:
	## True when the hull can leave its own deployment band from `cell`.
	##
	## Deployment used to accept an anchor merely because the footprint fitted, which is
	## how a long hull ended up sealed in a pocket of terrain. This is a bounded state
	## search (two turns' worth of movement, rotations included), not a single-step
	## probe: a hull may legitimately need to turn before it can get out.
	var budget: int = maxi(6, ship.max_move * 2)
	# M7B: the pocket check asks the search a single yes/no question and stops at the
	# first escaping anchor, instead of materialising every reachable state. It is the
	# same predicate (`test_pathsearch_equivalence` compares the two on every board), and
	# it was the dominant cost of `Battle.setup()`: it runs once per deployment candidate.
	return PathfinderRef.escapes_deploy_band(
		map, cell, ship.orientation, budget, occupied(ship.id), ship.footprint, team)


func _footprint_in_zone(cell: Vector2i, size: Vector2i, orientation: int, team: int) -> bool:
	## Every cell of the footprint must sit inside the team's own deployment zone.
	var cells: Array[Vector2i] = FootprintRef.cells(cell, size, orientation)
	if cells.is_empty():
		return false
	for c in cells:
		if not map.is_deploy_zone(c, team):
			return false
	return true


func _shuffled_zone(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(map.height):
		for x in range(map.width):
			var c := Vector2i(x, y)
			if map.is_deploy_zone(c, team) and not map.is_blocked(c):
				cells.append(c)
	# Deterministic Fisher-Yates with the battle rng.
	for i in range(cells.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells


func _next_free_id() -> int:
	## Ids stay unique for the whole battle: `_deploy` uses a local counter that knows
	## nothing about hulls spawned later, so a spawned swarm must not reuse one.
	var highest: int = -1
	for sh in ships:
		highest = maxi(highest, sh.id)
	return highest + 1


func _launch_cells(s: Ship) -> Array[Vector2i]:
	## Free cells beside the hull, nearest first and deterministic (ring, then y, then x).
	## The swarm needs ONE 1x1 cell, so any free neighbour is legal; the order matters only
	## so the same battle produces the same spawn.
	var out: Array[Vector2i] = []
	for radius in range(1, 2):
		var ring: Array[Vector2i] = []
		for x in range(s.cell.x - radius, s.cell.x + radius + 1):
			for y in range(s.cell.y - radius, s.cell.y + radius + 1):
				var c := Vector2i(x, y)
				if maxi(absi(c.x - s.cell.x), absi(c.y - s.cell.y)) != radius:
					continue
				ring.append(c)
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
		for c2 in ring:
			if placement_problem(c2, Vector2i(1, 1), 0, -1) == "":
				out.append(c2)
		if not out.is_empty():
			return out
	return out


func _cell_name(c: Vector2i) -> String:
	return "%s%d" % [char(65 + c.x), c.y + 1]


func _add_ship(s: Ship) -> void:
	ships.append(s)
	by_id[s.id] = s


func get_ship(id: int) -> Ship:
	return by_id.get(id, null)


func alive_ships(team: int) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in ships:
		if s.alive and s.team == team:
			out.append(s)
	return out


func occupied(except_id: int = -1) -> Dictionary:
	## cell -> ship id for every living ship. DERIVED on every call: there is no
	## cache, so occupancy can never go stale, and a ship always occupies exactly
	## the cells its footprint declares (scripts/core/footprint.gd).
	var occ: Dictionary = {}
	for s in ships:
		if s.alive and s.placed and s.id != except_id:
			for c in s.cells():
				occ[c] = s.id
	return occ


func ship_at(cell: Vector2i) -> Ship:
	## Authoritative occupancy lookup: ANY cell of a living ship resolves to it.
	for s in ships:
		if s.alive and s.cells().has(cell):
			return s
	return null


func cells_of(id: int) -> Array[Vector2i]:
	## The cells a ship occupies right now (empty if it is gone).
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return [] as Array[Vector2i]
	return s.cells()


func cells_distance_to(cells: Array[Vector2i], b: Ship) -> int:
	## Minimum Manhattan distance between a SET OF CELLS and a ship. The single
	## authority behind weapon range; `footprint_distance` is the case where the cells
	## are a ship's current footprint, and the AI uses it for hypothetical anchors.
	var best: int = 1 << 20
	for ca in cells:
		for cb in b.cells():
			var d: int = PathfinderRef.manhattan(ca, cb)
			if d < best:
				best = d
				if best <= 1:
					return best
	return best


func cells_have_los_to(cells: Array[Vector2i], b: Ship) -> bool:
	## True when at least one cell of `cells` has a clear lane to one cell of `b`.
	var target_cells: Array[Vector2i] = b.cells()
	for ca in cells:
		for cb in target_cells:
			if map.has_line_of_sight(ca, cb):
				return true
	return false


func footprint_distance(a: Ship, b: Ship) -> int:
	## Weapon range is the MINIMUM Manhattan distance between any occupied cell of
	## the attacker and any occupied cell of the target (fixed rule S5). For two 1x1
	## ships this is exactly the old anchor-to-anchor distance.
	return cells_distance_to(a.cells(), b)


func has_firing_los(a: Ship, b: Ship) -> bool:
	## A lane exists if AT LEAST ONE source-cell / target-cell pair is clear under
	## the existing terrain rules (fixed rule S5). For 1x1 ships this is the old
	## single-pair check.
	return cells_have_los_to(a.cells(), b)


func ship_in_cover(ship: Ship) -> bool:
	## Cover rule for footprints (STEP1): a hull is in cover when ANY of its occupied
	## cells is a nebula. Combat.resolve applies the 30% reduction once, so a hull
	## straddling several nebula cells cannot stack the effect. For a 1x1 hull this
	## is exactly `map.is_cover(ship.cell)`, i.e. the rule the game already had.
	for c in ship.cells():
		if map.is_cover(c):
			return true
	return false


func closest_cells(a: Ship, b: Ship) -> Array[Vector2i]:
	## The (attacker-cell, target-cell) pair with the smallest Manhattan distance.
	## Used for the beam geometry so a big hull fires from its edge, not its corner.
	## Deterministic: the first minimum in cell order wins.
	var best: int = 1 << 20
	var out: Array[Vector2i] = [a.cell, b.cell]
	for ca in a.cells():
		for cb in b.cells():
			var d: int = PathfinderRef.manhattan(ca, cb)
			if d < best:
				best = d
				out[0] = ca
				out[1] = cb
				if best <= 1:
					return out
	return out


func can_place(cell: Vector2i, size: Vector2i, orientation: int, except_id: int = -1) -> bool:
	## Authoritative placement test for a whole footprint: every cell must be inside
	## the board, passable, and free of any other living ship.
	if not FootprintRef.is_valid_size(size) or not FootprintRef.is_valid_orientation(orientation):
		return false
	var cells: Array[Vector2i] = FootprintRef.cells(cell, size, orientation)
	if cells.is_empty():
		return false
	var occ: Dictionary = occupied(except_id)
	for c in cells:
		if not map.in_bounds(c) or map.is_blocked(c):
			return false
		if occ.has(c):
			return false
	return true


func placement_problem(cell: Vector2i, size: Vector2i, orientation: int, except_id: int = -1) -> String:
	## Human-readable reason a placement is illegal ("" when it is legal).
	if not FootprintRef.is_valid_size(size):
		return "Invalid footprint."
	if not FootprintRef.is_valid_orientation(orientation):
		return "Invalid orientation."
	var cells: Array[Vector2i] = FootprintRef.cells(cell, size, orientation)
	var occ: Dictionary = occupied(except_id)
	for c in cells:
		if not map.in_bounds(c):
			return "Outside the battle grid."
		if map.is_blocked(c):
			return "%s is impassable." % map.terrain_name(c)
		if occ.has(c):
			return "Cell occupied by another ship."
	return ""


func occupancy_conflicts() -> Array[Vector2i]:
	## Invariant probe (tests, debugging): cells claimed by more than one living ship.
	var seen: Dictionary = {}
	var dupes: Array[Vector2i] = []
	for s in ships:
		if not s.alive:
			continue
		for c in s.cells():
			if seen.has(c):
				if not dupes.has(c):
					dupes.append(c)
			else:
				seen[c] = true
	return dupes


func note(text: String) -> void:
	## Public log entry for systems outside Battle (the AI) to record a rejection.
	_push_log(text)


func _battle_over() -> bool:
	## S0: single source of truth for "no gameplay action is legal any more".
	## Checked by every validation *and* execution entry point, so the UI can
	## never be the only thing standing between a player and a post-battle action.
	return outcome != "" or phase == Phase.OVER


func select(id: int) -> bool:
	if _battle_over() or phase != Phase.PLAYER:
		last_message = "Not your turn."
		return false
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		last_message = "That ship is gone."
		return false
	if s.team != 0:
		last_message = "Enemy vessel — no command authority."
		return false
	selected_id = id
	last_message = ""
	return true


func selected_ship() -> Ship:
	return get_ship(selected_id)


func reachable_states(id: int) -> Dictionary:
	## Full (anchor, orientation) search space for this hull: the only description of
	## "reachable" that is true for a ship that may have to turn to fit somewhere.
	## Returns {"dist": {Vector3i: steps}, "prev": {Vector3i: Vector3i},
	##          "orientation": {Vector2i: int}}.
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return {}
	return PathfinderRef.explore_states(
		map, s.cell, s.orientation, s.move_points, occupied(s.id), s.footprint)


func reachable_cells(id: int) -> Dictionary:
	## Anchor -> distance overlay.
	##
	## For a 1x1 hull this is the original `explore()` call, unchanged: same
	## frontier, same tie-breaking, same numbers as before STEP 2. For a multi-cell
	## hull the anchors come from the (anchor, orientation) search, so a destination
	## that is reachable only after turning is listed too (it used to be silently
	## missing, which is what stranded the 2-wide hull in STEP1). "orientation" maps
	## each anchor to the orientation the hull would end up in.
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return {}
	if s.footprint == Vector2i.ONE:
		return PathfinderRef.explore(map, s.cell, s.move_points, occupied(s.id), s.footprint, s.orientation)
	var states: Dictionary = reachable_states(id)
	var dist_out: Dictionary = {}
	var prev_out: Dictionary = {}
	var ori_out: Dictionary = {}
	var state_dist: Dictionary = states.get("dist", {})
	var state_prev: Dictionary = states.get("prev", {})
	for key in state_dist.keys():
		var st: Vector3i = key
		var c: Vector2i = PathfinderRef.state_cell(st)
		var d: int = int(state_dist[st])
		if dist_out.has(c):
			var known: int = int(dist_out[c])
			if d > known or (d == known and st.z >= int(ori_out[c])):
				continue
		dist_out[c] = d
		ori_out[c] = st.z
		if state_prev.has(st):
			prev_out[c] = PathfinderRef.state_cell(state_prev[st])
	return {"dist": dist_out, "prev": prev_out, "orientation": ori_out}


func attack_targets(id: int) -> Array[Ship]:
	var out: Array[Ship] = []
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return out
	for e in alive_ships(1 - s.team):
		if can_attack(id, e.id).get("ok", false):
			out.append(e)
	return out


func attack_cells(id: int) -> Dictionary:
	## Cells of the enemies this ship could hit right now. Derived from can_attack(),
	## so the UI bracket can never advertise a shot the rules would refuse; for a
	## multi-cell target every occupied cell is listed.
	var cells: Dictionary = {}
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return cells
	for e in alive_ships(1 - s.team):
		if bool(can_attack(id, e.id).get("ok", false)):
			for c in e.cells():
				cells[c] = true
	return cells


func can_attack(attacker_id: int, target_id: int) -> Dictionary:
	if _battle_over():
		return {"ok": false, "reason": "Battle is over."}
	var a: Ship = get_ship(attacker_id)
	var t: Ship = get_ship(target_id)
	if a == null or not a.alive:
		return {"ok": false, "reason": "Attacker is destroyed."}
	if t == null or not t.alive:
		return {"ok": false, "reason": "Target already destroyed."}
	if a.team == t.team:
		return {"ok": false, "reason": "Friendly target."}
	if a.has_attacked:
		return {"ok": false, "reason": "%s already fired this round." % a.display_name}
	if phase == Phase.PLAYER and a.team != 0:
		return {"ok": false, "reason": "Not your turn."}
	if phase == Phase.ENEMY and a.team != 1:
		return {"ok": false, "reason": "Not the enemy turn."}
	var dist: int = footprint_distance(a, t)
	if dist > a.attack_range:
		return {"ok": false, "reason": "Out of range (%d > %d)." % [dist, a.attack_range]}
	if not has_firing_los(a, t):
		return {"ok": false, "reason": "Line of sight blocked."}
	return {"ok": true, "reason": ""}


func move_ship(id: int, dest: Vector2i, orientation: int = -1) -> Dictionary:
	## Authoritative movement AND rotation.
	## `orientation` < 0 means "keep the current one", which is what every legacy
	## caller gets. A move is: rotate in place (free) if needed, then translate at
	## the target orientation. Every check runs before any mutation, so a rejected
	## order leaves position, orientation, facing, movement points and events
	## untouched - there is no partial move.
	if _battle_over():
		return {"ok": false, "reason": "Battle is over."}
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return {"ok": false, "reason": "Ship is destroyed."}
	if phase == Phase.PLAYER and s.team != 0:
		return {"ok": false, "reason": "Not your turn."}
	if phase == Phase.ENEMY and s.team != 1:
		return {"ok": false, "reason": "Not the enemy turn."}
	var new_orientation: int = s.orientation if orientation < 0 else orientation
	if not FootprintRef.is_valid_orientation(new_orientation):
		return {"ok": false, "reason": "Invalid orientation."}
	var rotating: bool = new_orientation != s.orientation
	var moving: bool = dest != s.cell
	if not rotating and not moving:
		return {"ok": false, "reason": "Already at that position."}
	var multi: bool = s.footprint != Vector2i.ONE
	# 1. A PURE rotation order must fit where the hull stands. When the hull also
	#    moves, the turn is part of the route and the state search decides where it
	#    happens: a hull that cannot turn in place can still turn on the way. That
	#    is the corridor case STEP1 could not express.
	if rotating and not moving:
		var rot_problem: String = placement_problem(s.cell, s.footprint, new_orientation, s.id)
		if rot_problem != "":
			return {"ok": false, "reason": "Cannot rotate here: %s" % rot_problem}
	# 2. The destination must host the whole footprint at the target orientation,
	#    and a route must exist for that footprint.
	var path: Array[Vector2i] = []
	var steps: Array[Vector3i] = []
	var cost: int = 0
	var turns: int = 0
	if moving:
		var dest_problem: String = placement_problem(dest, s.footprint, new_orientation, s.id)
		if dest_problem != "":
			return {"ok": false, "reason": dest_problem}
		if multi:
			# (cell, orientation) route: every intermediate state is validated by the
			# search itself, so the whole hull - not just the anchor - can get there.
			var states: Dictionary = PathfinderRef.explore_states(
				map, s.cell, s.orientation, s.move_points, occupied(s.id), s.footprint)
			var goal: Vector3i = PathfinderRef.state_key(dest, new_orientation)
			var state_dist: Dictionary = states["dist"]
			if not state_dist.has(goal):
				return {"ok": false, "reason": "No route within %d movement." % s.move_points}
			steps = PathfinderRef.build_state_path(
				states["prev"], PathfinderRef.state_key(s.cell, s.orientation), goal)
			if steps.size() < 2:
				return {"ok": false, "reason": "No valid path."}
			cost = PathfinderRef.state_path_cost(steps)
			turns = PathfinderRef.state_path_rotations(steps)
			path = PathfinderRef.state_path_anchors(steps)
			if int(state_dist[goal]) != cost:
				# The route must cost exactly what the search paid for it.
				return {"ok": false, "reason": "Inconsistent route."}
		else:
			var explored: Dictionary = PathfinderRef.explore(
				map, s.cell, s.move_points, occupied(s.id), s.footprint, new_orientation)
			var dist: Dictionary = explored["dist"]
			if not dist.has(dest):
				return {"ok": false, "reason": "No route within %d movement." % s.move_points}
			cost = int(dist[dest])
			path = PathfinderRef.build_path(explored["prev"], s.cell, dest)
			if path.size() < 2:
				return {"ok": false, "reason": "No valid path."}
			for c in path:
				steps.append(PathfinderRef.state_key(c, new_orientation))
	# 3. Commit - nothing above this line mutated the ship.
	var from: Vector2i = s.cell
	var from_orientation: int = s.orientation
	if moving:
		var first: Vector2i = Vector2i.ZERO
		for i in range(1, steps.size()):
			var a: Vector2i = PathfinderRef.state_cell(steps[i - 1])
			var b: Vector2i = PathfinderRef.state_cell(steps[i])
			if a != b:
				first = b - a
				break
		if first == Vector2i.ZERO:
			return {"ok": false, "reason": "No valid path."}
		s.facing = Vector2(float(first.x), float(first.y))
	s.orientation = new_orientation
	s.cell = dest
	s.move_points -= cost
	events.append({
		"type": "move", "id": s.id, "from": from, "to": dest, "path": path, "cost": cost,
		"orientation": new_orientation, "from_orientation": from_orientation, "rotated": rotating,
		"steps": steps, "turns": turns,
	})
	return {"ok": true, "reason": "", "path": path, "cost": cost,
		"orientation": new_orientation, "rotated": rotating, "turns": turns, "steps": steps}


func rotate_ship(id: int, orientation: int) -> Dictionary:
	## Rotation as an explicit order. Free in movement points; it must not clip.
	return move_ship(id, get_ship(id).cell if get_ship(id) != null else Vector2i.ZERO, orientation)


func attack(attacker_id: int, target_id: int) -> Dictionary:
	var check: Dictionary = can_attack(attacker_id, target_id)
	if not bool(check["ok"]):
		last_message = String(check["reason"])
		return {"ok": false, "reason": check["reason"]}
	var a: Ship = get_ship(attacker_id)
	var t: Ship = get_ship(target_id)
	# Beam geometry: the closest pair of occupied cells, so a big hull fires from its
	# edge instead of its reference corner. Identical to the old (from, to) for 1x1.
	var pair: Array[Vector2i] = closest_cells(a, t)
	var from: Vector2i = pair[0]
	var to: Vector2i = pair[1]
	var result: Dictionary = CombatRef.resolve(a, t, map, {"cover": ship_in_cover(t)})
	a.has_attacked = true
	a.facing = Vector2(float(to.x - from.x), float(to.y - from.y))
	var line := "%s hits %s for %d (shield %d, hull %d)" % [
		a.display_name, t.display_name,
		int(round(float(result["raw"]))), int(round(float(result["shield"]))), int(round(float(result["hull"]))),
	]
	if bool(result["cover"]):
		line += " [nebula cover]"
	_push_log(line)
	events.append({
		"type": "attack", "attacker": a.id, "target": t.id, "team": a.team,
		"from": from, "to": to, "damage": float(result["raw"]),
		"shield": float(result["shield"]), "hull": float(result["hull"]),
		"destroyed": bool(result["destroyed"]), "beam": a.ship_class == "battleship" or a.ship_class == "cruiser",
	})
	if bool(result["destroyed"]):
		_on_destroyed(t, a)
	_check_outcome()
	return {"ok": true, "reason": "", "result": result}


func _on_destroyed(s: Ship, killer: Ship) -> void:
	s.alive = false
	s.hull = 0.0
	s.shield = 0.0
	if s.team == 0:
		losses.append(s.display_name)
	_push_log("%s destroyed%s" % [s.display_name, "" if killer == null else " by " + killer.display_name])
	events.append({"type": "destroy", "id": s.id, "cell": s.cell, "team": s.team, "class": s.ship_class})
	if selected_id == s.id:
		selected_id = -1


func ability_targets(id: int) -> Array[Ship]:
	## Ships the armed ability may legally target (empty = self-cast or no target needed).
	var s: Ship = get_ship(id)
	var out: Array[Ship] = []
	if s == null or not s.alive:
		return out
	var kind := String(s.ability.get("kind", ""))
	match kind:
		"precision":
			for e in alive_ships(1 - s.team):
				var dist: int = footprint_distance(s, e)
				if dist <= s.attack_range + 1 and has_firing_los(s, e):
					out.append(e)
		"salvo":
			for e in alive_ships(1 - s.team):
				if footprint_distance(s, e) <= s.attack_range and has_firing_los(s, e):
					out.append(e)
		"shield":
			for ally in alive_ships(s.team):
				if footprint_distance(s, ally) <= 3:
					out.append(ally)
	return out


func can_use_ability(id: int, target_id: int = -1) -> Dictionary:
	if _battle_over():
		return {"ok": false, "reason": "Battle is over."}
	var s: Ship = get_ship(id)
	if s == null or not s.alive:
		return {"ok": false, "reason": "Ship is destroyed."}
	if phase == Phase.PLAYER and s.team != 0:
		return {"ok": false, "reason": "Not your turn."}
	if phase == Phase.ENEMY and s.team != 1:
		return {"ok": false, "reason": "Not the enemy turn."}
	if s.ability_cooldown > 0:
		return {"ok": false, "reason": "%s recharging (%d rounds)." % [s.ability_name(), s.ability_cooldown]}
	var kind := String(s.ability.get("kind", ""))
	if kind == "evade":
		return {"ok": true, "reason": ""}
	if kind == "launch":
		# Production is capped per HULL and per BATTLE, not per turn: the counter lives on
		# the ship and never resets (turn changes, re-selection, save/load).
		if not s.ability_ready:
			return {"ok": false, "reason": "%s already launched this round." % s.display_name}
		var limit: int = int(s.ability.get("limit", 10))
		if s.squadrons_launched >= limit:
			return {"ok": false, "reason": "%s has no flight deck capacity left (%d/%d)." % [
				s.display_name, s.squadrons_launched, limit]}
		if _launch_cells(s).is_empty():
			return {"ok": false, "reason": "No free cell beside %s to launch into." % s.display_name}
		return {"ok": true, "reason": ""}
	if s.has_attacked:
		return {"ok": false, "reason": "%s already acted this round." % s.display_name}
	if target_id < 0:
		return {"ok": false, "reason": "Select a target for %s." % s.ability_name()}
	var t: Ship = get_ship(target_id)
	if t == null or not t.alive:
		return {"ok": false, "reason": "Target already destroyed."}
	if kind == "shield":
		if t.team != s.team:
			return {"ok": false, "reason": "Shield surge targets allies only."}
		if footprint_distance(s, t) > 3:
			return {"ok": false, "reason": "Ally out of support range (3)."}
		return {"ok": true, "reason": ""}
	if t.team == s.team:
		return {"ok": false, "reason": "Cannot fire on friendly ships."}
	var max_range: int = s.attack_range + (1 if kind == "precision" else 0)
	if footprint_distance(s, t) > max_range:
		return {"ok": false, "reason": "Target out of ability range."}
	if not has_firing_los(s, t):
		return {"ok": false, "reason": "Line of sight blocked."}
	return {"ok": true, "reason": ""}


func use_ability(id: int, target_id: int = -1) -> Dictionary:
	var check: Dictionary = can_use_ability(id, target_id)
	if not bool(check["ok"]):
		last_message = String(check["reason"])
		return {"ok": false, "reason": check["reason"]}
	var s: Ship = get_ship(id)
	var kind := String(s.ability.get("kind", ""))
	var power: float = float(s.ability.get("power", 0.0))
	var cd: int = int(s.ability.get("cooldown", 2))
	s.ability_cooldown = cd
	s.ability_ready = false
	match kind:
		"launch":
			# One real unit per swarm: the Interceptor is a 1x1 tactical entity that moves,
			# fires and takes damage like any other hull. The drawing is a formation, the
			# rules are one ship.
			var cells: Array[Vector2i] = _launch_cells(s)
			if cells.is_empty():
				# Nothing was created, so nothing is consumed: the check above normally
				# prevents this, but a race with a destroyed neighbour must not burn a
				# launch.
				s.ability_cooldown = 0
				s.ability_ready = true
				return {"ok": false, "reason": "No free cell beside %s to launch into." % s.display_name}
			var spot: Vector2i = cells[0]
			var swarm_id: int = _next_free_id()
			var swarm: Ship = ShipRef.create("interceptor", s.team, swarm_id, alive_ships(s.team).size(), {}, 1.0)
			swarm.placed = true
			swarm.cell = spot
			_add_ship(swarm)
			s.squadrons_launched += 1
			_push_log("%s launches INTERCEPTOR SWARM %d/%d at %s." % [
				s.display_name, s.squadrons_launched, int(s.ability.get("limit", 10)),
				_cell_name(spot)])
			events.append({"type": "ability", "id": s.id, "kind": kind, "cell": spot, "spawn": swarm.id})
			_check_outcome()
			return {"ok": true, "reason": "", "spawn": swarm.id, "cell": spot}
		"evade":
			s.evading = true
			s.move_points += int(power)
			_push_log("%s executes EVASIVE BURN (+%d move, damage halved)." % [s.display_name, int(power)])
			events.append({"type": "ability", "id": s.id, "kind": kind, "cell": s.cell})
			return {"ok": true, "reason": ""}
		"precision":
			var t: Ship = get_ship(target_id)
			var result: Dictionary = CombatRef.resolve(s, t, map, {
				"bonus_damage": power, "ignore_armor": true, "ignore_cover": true,
			})
			s.has_attacked = true
			var ppair: Array[Vector2i] = closest_cells(s, t)
			s.facing = Vector2(float(ppair[1].x - ppair[0].x), float(ppair[1].y - ppair[0].y))
			_push_log("%s fires PRECISION STRIKE on %s: %d damage (armor bypassed)." % [
				s.display_name, t.display_name, int(round(float(result["raw"])))])
			events.append({"type": "attack", "attacker": s.id, "target": t.id, "team": s.team,
				"from": ppair[0], "to": ppair[1], "damage": float(result["raw"]),
				"shield": float(result["shield"]), "hull": float(result["hull"]),
				"destroyed": bool(result["destroyed"]), "beam": true, "ability": true})
			if bool(result["destroyed"]):
				_on_destroyed(t, s)
			_check_outcome()
			return {"ok": true, "reason": "", "result": result}
		"shield":
			var ally: Ship = get_ship(target_id)
			var before: float = ally.shield
			var cap: float = ally.max_shield * 1.25
			ally.shield = minf(cap, ally.shield + power)
			s.has_attacked = true
			_push_log("%s reinforces %s shields (+%d)." % [s.display_name, ally.display_name, int(round(ally.shield - before))])
			events.append({"type": "ability", "id": s.id, "kind": kind, "cell": ally.cell, "target": ally.id})
			return {"ok": true, "reason": ""}
		"salvo":
			var main: Ship = get_ship(target_id)
			var main_hit: Dictionary = CombatRef.resolve(s, main, map, {"bonus_damage": power, "ignore_cover": true})
			s.has_attacked = true
			var spair: Array[Vector2i] = closest_cells(s, main)
			s.facing = Vector2(float(spair[1].x - spair[0].x), float(spair[1].y - spair[0].y))
			_push_log("%s unleashes HEAVY SALVO on %s: %d damage." % [s.display_name, main.display_name, int(round(float(main_hit["raw"])))])
			events.append({"type": "attack", "attacker": s.id, "target": main.id, "team": s.team,
				"from": spair[0], "to": spair[1], "damage": float(main_hit["raw"]),
				"shield": float(main_hit["shield"]), "hull": float(main_hit["hull"]),
				"destroyed": bool(main_hit["destroyed"]), "beam": true, "ability": true})
			# Splash is footprint-aware: any hull touching the struck hull takes it ONCE.
			var splash: Array = CombatRef.splash_targets(main, alive_ships(1 - s.team))
			for other in splash:
				var o: Ship = other
				var hit: Dictionary = CombatRef.resolve(s, o, map, {"bonus_damage": power * 0.5, "ignore_cover": true})
				var opair: Array[Vector2i] = closest_cells(s, o)
				events.append({"type": "attack", "attacker": s.id, "target": o.id, "team": s.team,
					"from": opair[0], "to": opair[1], "damage": float(hit["raw"]),
					"shield": float(hit["shield"]), "hull": float(hit["hull"]),
					"destroyed": bool(hit["destroyed"]), "beam": false, "ability": true})
				if bool(hit["destroyed"]):
					_on_destroyed(o, s)
			if bool(main_hit["destroyed"]):
				_on_destroyed(main, s)
			_check_outcome()
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "Unknown ability."}


func wait_ship(id: int) -> bool:
	if _battle_over():
		return false
	var s: Ship = get_ship(id)
	if s == null or not s.alive or s.team != 0 or phase != Phase.PLAYER:
		return false
	s.move_points = 0
	s.has_attacked = true
	_push_log("%s holds position." % s.display_name)
	last_message = ""
	return true


func end_turn() -> bool:
	if phase != Phase.PLAYER or outcome != "":
		return false
	selected_id = -1
	phase = Phase.ENEMY
	_push_log("— ENEMY TURN (round %d) —" % round)
	if ai_enabled:
		AIRef.take_turn(self)
	_finish_round()
	return true


func _finish_round() -> void:
	if outcome != "":
		phase = Phase.OVER
		return
	_tick_control()
	if round >= MAX_ROUNDS:
		outcome = "defeat"
		_push_log("Admiralty recall: battle exceeded %d rounds." % MAX_ROUNDS)
		phase = Phase.OVER
		return
	round += 1
	for s in ships:
		if s.alive:
			s.begin_round()
	_check_outcome()
	phase = Phase.OVER if outcome != "" else Phase.PLAYER
	if phase == Phase.PLAYER:
		_push_log("Round %d — your move." % round)


func _tick_control() -> void:
	if outcome != "":
		return
	var player_on := false
	var enemy_on := false
	for s in ships:
		if not s.alive or not s.cells().has(map.control_cell):
			continue
		if s.team == 0:
			player_on = true
		else:
			enemy_on = true
	if player_on:
		control_hold += 1
		control_owner = 0
		_push_log("Relay held (%d/3)." % control_hold)
		if control_hold >= 3 and not control_bonus_claimed:
			control_bonus_claimed = true
			_push_log("RELAY SECURED — enemy shields disrupted.")
			for s in alive_ships(1):
				s.shield = maxf(0.0, s.shield - 15.0)
			events.append({"type": "emp", "cell": map.control_cell})
	elif enemy_on:
		control_hold = 0
		control_owner = 1
		_push_log("Relay seized by the enemy.")
	else:
		control_hold = 0
		control_owner = -1


func _check_outcome() -> void:
	if outcome != "":
		return
	var p: int = alive_ships(0).size()
	var e: int = alive_ships(1).size()
	if p == 0:
		outcome = "defeat"
		phase = Phase.OVER
		_push_log("Fleet lost. Battle over.")
	elif e == 0:
		outcome = "victory"
		phase = Phase.OVER
		_push_log("Enemy fleet eliminated. Victory.")
	if outcome != "":
		selected_id = -1


func pop_event() -> Dictionary:
	if events.is_empty():
		return {}
	return events.pop_front()


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(events)
	events.clear()
	return out


func pending_events() -> int:
	return events.size()


func _push_log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 80:
		log_lines.remove_at(0)


func summary() -> Dictionary:
	var enemy_destroyed: int = 0
	for s in ships:
		if s.team == 1 and not s.alive:
			enemy_destroyed += 1
	return {
		"outcome": outcome,
		"rounds": round,
		"seed": seed_value,
		"enemy_destroyed": enemy_destroyed,
		"player_lost": losses.size(),
		"control_hold": control_hold,
		"control_bonus": control_bonus_claimed,
		"losses": losses.duplicate(),
	}


func compute_reward() -> Dictionary:
	var rows: Array[String] = []
	var credits: int = 40
	rows.append("Engagement base  ................ +40")
	var s: Dictionary = summary()
	credits += int(s["enemy_destroyed"]) * 35
	rows.append("Hostiles destroyed (%d x 35) ..... +%d" % [int(s["enemy_destroyed"]), int(s["enemy_destroyed"]) * 35])
	if String(s["outcome"]) == "victory":
		credits += 120
		rows.append("Victory bonus .................... +120")
	if bool(s["control_bonus"]):
		credits += 60
		rows.append("Relay secured .................... +60")
	var lost: int = int(s["player_lost"])
	if lost > 0:
		var penalty: int = lost * 10
		credits -= penalty
		rows.append("Ships lost (%d x 10) ............. -%d" % [lost, penalty])
	credits = maxi(0, credits)
	return {"credits": credits, "lines": rows}
