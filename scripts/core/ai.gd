extends RefCounted
## Deterministic rule-based tactical AI. Works on Battle's public API only:
## no nodes, no animations, no rendering. Same seed => same decisions.

const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")

## Minimum deterministic-score gain that justifies leaving the current state. Without
## it the AI would accept "improvements" that are pure noise and could ping-pong.
const EPS: float = 0.05


static func take_turn(battle, team: int = 1) -> void:
	## Plays one turn for `team`. Default 1 keeps every historical caller identical
	## (`1 - s.team` is the same expression the code already used with 0 hardcoded), and a
	## balance probe can now drive BOTH sides with the same brain.
	var order: Array[int] = []
	for s in battle.ships:
		if s.alive and s.team == team:
			order.append(s.id)
	order.sort()
	for id in order:
		var s = battle.get_ship(id)
		if s == null or not s.alive:
			continue
		if battle.alive_ships(1 - s.team).is_empty():
			return
		_take_ship_turn(battle, s)


static func _take_ship_turn(battle, s) -> void:
	_consider_ability(battle, s)
	if s.has_attacked:
		return
	var target = _best_target(battle, s, battle.alive_ships(1 - s.team))
	if target != null:
		var check: Dictionary = battle.can_attack(s.id, target.id)
		if bool(check.get("ok", false)):
			battle.attack(s.id, target.id)
			return
	var pick: Dictionary = _choose_destination(battle, s, target)
	var dest: Vector2i = pick.get("cell", s.cell)
	var dest_orientation: int = int(pick.get("orientation", s.orientation))
	if dest != s.cell or dest_orientation != s.orientation:
		var moved: Dictionary = battle.move_ship(s.id, dest, dest_orientation)
		if not bool(moved.get("ok", false)):
			# Explicit: one attempt per ship per turn, no retry, and the rejection is
			# visible in the combat log instead of silently wasting the move.
			battle.note("%s holds position (%s)" % [s.display_name, String(moved.get("reason", ""))])
	if not s.has_attacked:
		var after = _best_target(battle, s, battle.alive_ships(1 - s.team))
		if after != null and bool(battle.can_attack(s.id, after.id).get("ok", false)):
			battle.attack(s.id, after.id)


static func _best_target(battle, s, targets: Array):
	var best = null
	var best_score: float = -1000000.0
	for t in targets:
		if t == null or not t.alive:
			continue
		var score: float = _score_target(battle, s, t)
		if score > best_score:
			best_score = score
			best = t
	return best


static func _score_target(battle, s, t) -> float:
	var dist: int = battle.footprint_distance(s, t)
	var score: float = 0.0
	score += (1.0 - t.hull_ratio()) * 38.0
	score += t.threat * 9.0
	if t.shield < t.max_shield * 0.25:
		score += 9.0
	score -= float(dist) * 3.0
	# Footprint-aware: the same rule the authoritative layer uses (min cell distance
	# plus a clear lane), without the turn/attack bookkeeping.
	var in_range: bool = dist <= s.attack_range and battle.has_firing_los(s, t)
	if in_range:
		score += 45.0
	# Focus fire on the weakest hull when everything else is equal.
	score += (1.0 - t.hull_ratio()) * 14.0
	score += battle.ai_rng.randf_range(-6.0, 6.0) * float(battle.ai_aggression)
	return score


static func _state_score(battle, s, t, cell: Vector2i, orientation: int, field: Dictionary, control_field: Dictionary) -> float:
	## Tactical value of standing at (cell, orientation). Every geometric term uses the
	## WHOLE footprint, with the same rules the authoritative layer applies.
	##
	## The important term is the sight test. Before STEP 2.1 this function rewarded
	## proximity unconditionally, so a hull that could not see the target (nebula in the
	## lane) still scored well for standing next to it: the AI parked blind and lost
	## rounds. Proximity without a firing lane is now a PENALTY, and a position that
	## cannot fire now but has a legal neighbour that could fire next turn earns a
	## smaller "staging" bonus instead. Nothing here is a final veto on top of a bad
	## ranking: the ranking itself distinguishes can-fire / can-stage / blind.
	var cells: Array[Vector2i] = FootprintRef.cells(cell, s.footprint, orientation)
	if cells.is_empty():
		return -100000.0
	var score: float = 0.0
	if t != null:
		# Obstacle-aware guide: the BFS field is a greedy path estimate to the target's
		# anchor, so the hull walks around rocks instead of hugging a wall.
		score -= float(int(field.get(cell, 9999))) * 10.0
		var d: int = battle.cells_distance_to(cells, t)
		var sighted: bool = battle.cells_have_los_to(cells, t)
		var can_fire: bool = d <= int(s.attack_range) and sighted
		if can_fire:
			score += 45.0
		elif not sighted:
			# Blind: distance is not progress. Scaled by how close it pretends to be, so
			# standing right next to the target behind a nebula is the worst case.
			score -= 20.0 + maxf(0.0, 8.0 - float(d)) * 2.0
		elif _can_stage_to_fire(battle, s, t, cell, orientation):
			score += 14.0
		if d == int(s.attack_range):
			score += 4.0
	# Strategic pull towards the relay when no target is reachable this turn.
	score -= float(int(control_field.get(cell, 12))) * 1.2
	for c in cells:
		if battle.map.is_cover(c):
			score += 5.0
			break
	if cell == s.cell and orientation == s.orientation:
		score += 3.0
	return score


static func _can_stage_to_fire(battle, s, t, cell: Vector2i, orientation: int) -> bool:
	## True when a LEGAL one-step successor of this state (translation or in-place turn)
	## would be able to fire. This is what makes "approach" a real option instead of the
	## AI walking blind into the closest cell.
	for d in PathfinderRef.DIRS:
		var nxt: Vector2i = cell + d
		if not battle.can_place(nxt, s.footprint, orientation, s.id):
			continue
		var cells: Array[Vector2i] = FootprintRef.cells(nxt, s.footprint, orientation)
		if battle.cells_distance_to(cells, t) <= int(s.attack_range) and battle.cells_have_los_to(cells, t):
			return true
	for delta in [1, 3]:
		var o: int = (orientation + delta) % 4
		if not battle.can_place(cell, s.footprint, o, s.id):
			continue
		var turned: Array[Vector2i] = FootprintRef.cells(cell, s.footprint, o)
		if battle.cells_distance_to(turned, t) <= int(s.attack_range) and battle.cells_have_los_to(turned, t):
			return true
	return false


static func _choose_destination(battle, s, target) -> Dictionary:
	## Footprint-aware destination search (STEP 2 / Block A).
	##
	## STEP1 scored ANCHORS that were reachable at the hull's CURRENT orientation,
	## using `manhattan(anchor, target.cell)` and a LOS test from the anchor alone.
	## The AI therefore ignored firing positions that existed but required a turn -
	## it stopped one cell short and fired a round late.
	##
	## Here every candidate is a STATE (anchor, orientation) produced by the
	## authoritative (cell, orientation) search, scored with the whole footprint.
	## Candidates are executable by construction: they come from the same search
	## `move_ship` uses, so a chosen destination cannot be refused.
	##
	## Progress guarantee: a state is adopted only when its DETERMINISTIC score beats
	## the current one by `EPS`. Jitter picks among states that already improve, so it
	## can never make the AI step backwards into an equivalent cell. The score set is
	## finite and strictly increasing along accepted moves, which rules out an
	## indefinite ping-pong by construction.
	var states: Dictionary = battle.reachable_states(s.id)
	var dist: Dictionary = states.get("dist", {})
	if dist.is_empty():
		return {"cell": s.cell, "orientation": s.orientation}
	var control_field: Dictionary = PathfinderRef.distance_field(battle.map, battle.map.control_cell)
	var field: Dictionary = PathfinderRef.distance_field(battle.map, target.cell) if target != null else {}
	var baseline: float = _state_score(battle, s, target, s.cell, s.orientation, field, control_field)
	# Pass 1: the best deterministic score strictly above the baseline.
	#
	# M7B: each state is scored ONCE (it used to be scored twice, once per pass), and a
	# state is skipped when a cheap UPPER BOUND on its score already proves it cannot join
	# the winning group. The bound is exact and integer: the field term is `-10 * field`
	# and every positive term is bounded by 45 (in range) + 14 (staging) + 4 (range edge)
	# + 5 (cover) + 3 (stay put) = 71, so `71 - 10 * field` is >= the real score for every
	# state. Skipping `bound < best_det - EPS` therefore cannot change the maximum, the
	# group, or the RNG draws - only the work. On the large boards the field term
	# dominates, so this is where most of the AI's per-ship cost used to go.
	var best_det: float = baseline
	var keys: Array = dist.keys()
	var has_target: bool = target != null
	var scores: Array[float] = []
	scores.resize(keys.size())
	# Evaluate the most promising states FIRST (smallest BFS distance to the target). The
	# bound only prunes once `best_det` is high, so the order decides how much work the
	# bound saves; the search order (by distance from the ship) starts with the states
	# right next to the hull, which are rarely the good ones. Scoring order cannot change
	# the result: the maximum and the winning group are the same, and the group is still
	# collected in the search's own key order below.
	var order: Array[int] = []
	order.resize(keys.size())
	for i0 in range(keys.size()):
		order[i0] = i0
	if has_target:
		order.sort_custom(func(a: int, b: int) -> bool:
			var ka: Vector3i = keys[a]
			var kb: Vector3i = keys[b]
			var fa: int = int(field.get(Vector2i(ka.x, ka.y), 9999))
			var fb: int = int(field.get(Vector2i(kb.x, kb.y), 9999))
			if fa != fb:
				return fa < fb
			return a < b)
	for i in order:
		var st: Vector3i = keys[i]
		var cell := Vector2i(st.x, st.y)
		# The bound is exact and cheap. Every positive term of `_state_score` is known:
		#   +45 in range and sighted, +4 on the range edge, +5 in cover, +3 staying put
		#   (the staging bonus is an alternative to the firing bonus, never added to it);
		# the field and control terms are `-10 * field` and `-1.2 * control`, both known
		# without line of sight. If the hull cannot even REACH its weapon range from this
		# state, the +45 and the +4 are impossible and the bound drops by 35 points - which
		# is what makes the prune bite: most reachable states are out of range.
		var bound: float
		if has_target:
			var d: int = battle.cells_distance_to(FootprintRef.cells(cell, s.footprint, st.z), target)
			var bonus: float = 57.0 if d <= int(s.attack_range) else 22.0
			bound = bonus - 10.0 * float(int(field.get(cell, 9999))) \
				- 1.2 * float(int(control_field.get(cell, 12)))
		else:
			bound = 8.0
		if bound < best_det - EPS:
			scores[i] = -INF
			continue
		var det: float = _state_score(battle, s, target, cell, st.z, field, control_field)
		scores[i] = det
		if det > best_det + EPS:
			best_det = det
	if best_det <= baseline + EPS:
		return {"cell": s.cell, "orientation": s.orientation}
	# Pass 2: every state that reaches that score, in the search's deterministic
	# insertion order; jitter chooses among equals so different seeds differ.
	var group: Array[Vector3i] = []
	for i2 in range(keys.size()):
		if scores[i2] >= best_det - EPS:
			group.append(keys[i2] as Vector3i)
	if group.is_empty():
		return {"cell": s.cell, "orientation": s.orientation}
	var chosen: Vector3i = group[0]
	if group.size() > 1:
		chosen = group[battle.ai_rng.randi_range(0, group.size() - 1)]
	return {"cell": Vector2i(chosen.x, chosen.y), "orientation": chosen.z}


static func _consider_ability(battle, s) -> void:
	if s.ability_cooldown > 0 or s.has_attacked:
		return
	var kind := String(s.ability.get("kind", ""))
	match kind:
		"evade":
			if s.hull_ratio() < 0.75 and battle.ai_rng.randf() < 0.85:
				battle.use_ability(s.id)
		"precision":
			var t = _best_target(battle, s, battle.alive_ships(1 - s.team))
			if t != null and (t.armor >= 3.0 or t.hull > 60.0):
				if bool(battle.can_use_ability(s.id, t.id).get("ok", false)):
					battle.use_ability(s.id, t.id)
		"shield":
			var lowest = null
			for ally in battle.alive_ships(s.team):
				if PathfinderRef.manhattan(ally.cell, s.cell) <= 3 and ally.shield_ratio() < 0.45:
					if lowest == null or ally.shield_ratio() < lowest.shield_ratio():
						lowest = ally
			if lowest != null and bool(battle.can_use_ability(s.id, lowest.id).get("ok", false)):
				battle.use_ability(s.id, lowest.id)
		"salvo":
			var t2 = _best_target(battle, s, battle.alive_ships(1 - s.team))
			if t2 != null and bool(battle.can_use_ability(s.id, t2.id).get("ok", false)):
				var cluster: int = 0
				for p in battle.alive_ships(1 - s.team):
					if PathfinderRef.manhattan(p.cell, t2.cell) <= 1:
						cluster += 1
				if cluster >= 2 or t2.hull > 90.0:
					battle.use_ability(s.id, t2.id)
