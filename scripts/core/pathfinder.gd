class_name Pathfinder
extends RefCounted
## Orthogonal grid pathfinding (Dijkstra). Small boards: linear-scan frontier is enough.

const FootprintRef = preload("res://scripts/core/footprint.gd")

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


static func footprint_free(map: BattleMap, anchor: Vector2i, size: Vector2i, orientation: int, occupied: Dictionary) -> bool:
	## True when every cell of the footprint is inside the board, passable and free
	## of a ship. A 1x1 footprint reduces to the single-cell test, so the legacy path
	## keeps its exact behaviour (and its speed).
	if size == Vector2i.ONE:
		return map.in_bounds(anchor) and not map.is_blocked(anchor) and not occupied.has(anchor)
	var cells: Array[Vector2i] = FootprintRef.cells(anchor, size, orientation)
	if cells.is_empty():
		return false
	for c in cells:
		if not map.in_bounds(c) or map.is_blocked(c) or occupied.has(c):
			return false
	return true


static func explore(map: BattleMap, start: Vector2i, max_cost: int, occupied: Dictionary,
		size: Vector2i = Vector2i.ONE, orientation: int = 0) -> Dictionary:
	## Returns {"dist": {anchor: steps}, "prev": {anchor: parent}}.
	##
	## `size`/`orientation` default to 1x1, which is byte-for-byte the behaviour the
	## single-cell game has always had: same frontier, same expansion order, same
	## tie-breaking. With a larger footprint every anchor on the frontier must be able
	## to host the WHOLE footprint, so the returned set contains only destinations the
	## authoritative rules would accept.
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var closed: Dictionary = {}
	var open: Array[Vector2i] = [start]
	dist[start] = 0
	# The mover may sit on its own start cell; every other cell of `occupied` blocks.
	var occ: Dictionary = occupied
	if occ.has(start):
		occ = occupied.duplicate()
		occ.erase(start)
	while open.size() > 0:
		var best_index: int = 0
		for i in range(1, open.size()):
			if int(dist[open[i]]) < int(dist[open[best_index]]):
				best_index = i
		var cur: Vector2i = open[best_index]
		open.remove_at(best_index)
		if closed.has(cur):
			continue
		closed[cur] = true
		var steps: int = int(dist[cur])
		if steps >= max_cost:
			continue
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if not footprint_free(map, nxt, size, orientation, occ):
				continue
			var nd: int = steps + 1
			if nd > max_cost:
				continue
			if not dist.has(nxt) or nd < int(dist[nxt]):
				dist[nxt] = nd
				prev[nxt] = cur
				open.append(nxt)
	return {"dist": dist, "prev": prev}


static func build_path(prev: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if goal == start:
		return path
	if not prev.has(goal):
		return path
	var cur: Vector2i = goal
	var guard: int = 0
	while cur != start and guard < 512:
		guard += 1
		path.push_front(cur)
		if not prev.has(cur):
			return [] as Array[Vector2i]
		cur = prev[cur]
	if cur != start:
		return [] as Array[Vector2i]
	path.push_front(start)
	return path


static func path_cost(path: Array[Vector2i]) -> int:
	return maxi(0, path.size() - 1)


static func distance_field(map: BattleMap, goal: Vector2i) -> Dictionary:
	## BFS step distance from every passable cell to goal (ignores ships).
	## Used by the AI so it walks around obstacles instead of hugging walls.
	var field: Dictionary = {}
	if not map.in_bounds(goal) or map.is_blocked(goal):
		return field
	field[goal] = 0
	var queue: Array[Vector2i] = [goal]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var steps: int = int(field[cur])
		for d in DIRS:
			var nxt: Vector2i = cur + d
			if not map.in_bounds(nxt) or map.is_blocked(nxt):
				continue
			if field.has(nxt):
				continue
			field[nxt] = steps + 1
			queue.append(nxt)
	return field


# ---------------------------------------------------------------------------
# (cell, orientation) state search — STEP 2 / Block A
# ---------------------------------------------------------------------------
# `explore()` above explores ANCHORS at ONE fixed orientation. That is enough for
# 1x1 hulls, and it is kept byte-for-byte for them, but it cannot represent a hull
# that must turn to fit through a corridor: the shortest route may be legal for the
# footprint at another orientation than the one the hull happens to have.
#
# `explore_states()` searches the composite space (anchor, orientation):
#   * translation edge  (cell + d, same orientation)  -> cost 1
#   * rotation edge     (cell, orientation +-1)       -> cost 0
# Rotation in place costs no movement points in the VOID COMMAND rules
# (Battle.rotate_ship is free), so a rotation edge must cost 0 here as well:
# charging 1 would invent a movement rule the game does not have. The resulting
# distance is therefore "number of TRANSLATIONS", which is exactly what
# `move_ship` subtracts from `move_points`.
#
# Every edge re-validates the WHOLE footprint of the resulting state, so a state
# that the authoritative placement rules would refuse can never enter the search.


static func state_key(cell: Vector2i, orientation: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, orientation)


static func state_cell(key: Vector3i) -> Vector2i:
	return Vector2i(key.x, key.y)


static func _fits(map: BattleMap, anchor: Vector2i, offsets: Array[Vector2i], occ: Dictionary) -> bool:
	## Whole-footprint test against a precomputed offset set (no per-call allocation).
	for o in offsets:
		var c: Vector2i = anchor + o
		if not map.in_bounds(c) or map.is_blocked(c) or occ.has(c):
			return false
	return true


## Heap entry packing: `w = translations * BIAS + rotations`. The bias only has to exceed
## any possible rotation count, which is bounded by the number of states (4 * cells + 8).
const HEAP_BIAS: int = 1000000


static func _entry_before(a: Vector4i, b: Vector4i) -> bool:
	## Same order as `_state_before`: translations, then rotations, then the state key.
	if a.w != b.w:
		return a.w < b.w
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


static func _heap_push(heap: Array, entry: Vector4i) -> void:
	heap.append(entry)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if not _entry_before(heap[i], heap[parent]):
			break
		var tmp: Vector4i = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _heap_pop(heap: Array) -> Vector4i:
	var top: Vector4i = heap[0]
	var last: Vector4i = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i: int = 0
		var n: int = heap.size()
		while true:
			var left: int = i * 2 + 1
			var right: int = left + 1
			var smallest: int = i
			if left < n and _entry_before(heap[left], heap[smallest]):
				smallest = left
			if right < n and _entry_before(heap[right], heap[smallest]):
				smallest = right
			if smallest == i:
				break
			var tmp2: Vector4i = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp2
			i = smallest
	return top


static func escapes_deploy_band(map: BattleMap, start: Vector2i, start_orientation: int,
		max_cost: int, occupied: Dictionary, size: Vector2i, team: int) -> bool:
	## True when the hull can bring its ANCHOR out of `team`'s deployment band within
	## `max_cost` translations. This is the deployment pocket check.
	##
	## It answers exactly the question `Battle._pocket_ok` used to answer by running the
	## full state search and scanning every visited state, and it stops at the FIRST
	## escaping anchor. Equivalence is not assumed: rotations are free in the rules, so a
	## state path projects onto an anchor path of the same translation count in which an
	## orientation common to each pair of neighbours exists (rotate in place, translate,
	## rotate again); and any such anchor path lifts back to a state path. The reachable
	## anchor set, and therefore the predicate, is the same - `test_pathsearch_equivalence`
	## checks it against the full search on every board, footprint and budget.
	##
	## The expensive part of the old version was not the search itself but the dictionary
	## of Vector3i states: the pocket check runs once per deployment candidate, so it
	## dominated `Battle.setup()` on the large boards.
	if not FootprintRef.is_valid_size(size) or not FootprintRef.is_valid_orientation(start_orientation):
		return false
	var offsets: Array = []
	for o in range(4):
		offsets.append(FootprintRef.offsets(size, o))
	if offsets[start_orientation].is_empty():
		return false
	if not _fits(map, start, offsets[start_orientation], occupied):
		return false
	# Feasible orientations per anchor, cached: the same anchors recur as neighbours.
	var masks: Dictionary = {}
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var depth: Dictionary = {start: 0}
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if not map.is_deploy_zone(cur, team):
			return true
		var d: int = int(depth[cur])
		if d >= max_cost:
			continue
		var cur_mask: int = _orientation_mask(map, cur, offsets, occupied, masks)
		for dir in DIRS:
			var nxt: Vector2i = cur + dir
			if seen.has(nxt):
				continue
			if (cur_mask & _orientation_mask(map, nxt, offsets, occupied, masks)) == 0:
				continue
			seen[nxt] = true
			depth[nxt] = d + 1
			queue.append(nxt)
	return false


static func _orientation_mask(map: BattleMap, anchor: Vector2i, offsets: Array,
		occupied: Dictionary, cache: Dictionary) -> int:
	## Bit o set when the hull fits at `anchor` with orientation o.
	if cache.has(anchor):
		return int(cache[anchor])
	var mask: int = 0
	for o in range(4):
		if _fits(map, anchor, offsets[o], occupied):
			mask |= 1 << o
	cache[anchor] = mask
	return mask


static func explore_states(map: BattleMap, start: Vector2i, start_orientation: int,
		max_cost: int, occupied: Dictionary, size: Vector2i = Vector2i.ONE) -> Dictionary:
	## Dijkstra over (anchor, orientation) with a LEXICOGRAPHIC cost:
	##     primary   = translations  (movement points spent)
	##     secondary = rotations     (free in the rules, but not free of consequence)
	##
	## Rotation costs 0 movement points, because `Battle.rotate_ship` is free. Charging
	## movement for it would invent a rule the game does not have. What it DOES cost is
	## the second component: among routes of equal length the search prefers the one with
	## fewer turns, so `move_points` stays the authoritative budget while `turns` becomes
	## a documented, comparable metric instead of an artefact of tie-breaking.
	##
	## Zero-weight edges are safe under a lexicographic order because both components are
	## non-negative and the frontier always pops the lexicographic minimum: a state that
	## could be reached with fewer turns at the same distance is discovered before it is
	## closed. The order is total and additive, so Dijkstra's argument still holds.
	##
	## Returns {"dist": {Vector3i: translations}, "turns": {Vector3i: rotations},
	##          "prev": {Vector3i: Vector3i}, "orientation": {Vector2i: int}}.
	var dist: Dictionary = {}
	var turns: Dictionary = {}
	var prev: Dictionary = {}
	var closed: Dictionary = {}
	if not FootprintRef.is_valid_size(size) or not FootprintRef.is_valid_orientation(start_orientation):
		return {"dist": dist, "turns": turns, "prev": prev, "orientation": {}}
	var offsets: Array = []
	for o in range(4):
		offsets.append(FootprintRef.offsets(size, o))
	if offsets[start_orientation].is_empty():
		return {"dist": dist, "turns": turns, "prev": prev, "orientation": {}}
	var start_state: Vector3i = state_key(start, start_orientation)
	dist[start_state] = 0
	turns[start_state] = 0
	# M7B: a binary heap instead of a linear scan of the frontier. The order is the SAME
	# lexicographic (translations, rotations, state key) as `_state_before`; the frontier
	# used to be scanned on every pop, which made one route search O(states^2) and was the
	# measured bottleneck of both the deployment pocket check and the AI's route search.
	var open: Array = []
	_heap_push(open, Vector4i(start.x, start.y, start_orientation, 0))
	while not open.is_empty():
		var entry: Vector4i = _heap_pop(open)
		var cur: Vector3i = Vector3i(entry.x, entry.y, entry.z)
		var entry_d: int = entry.w / HEAP_BIAS
		var entry_t: int = entry.w % HEAP_BIAS
		# Lazy deletion: an entry improved while it sat in the heap leaves a stale copy
		# behind. Discarding it cannot change the result - a fresh copy is already queued.
		if int(dist.get(cur, -1)) != entry_d or int(turns.get(cur, -1)) != entry_t:
			continue
		if closed.has(cur):
			continue
		closed[cur] = true
		var steps: int = int(dist[cur])
		var spent_turns: int = int(turns[cur])
		var cell: Vector2i = state_cell(cur)
		# Rotation edges: 0 movement points, 1 turn.
		for delta in [1, 3]:
			var n_ori: int = (cur.z + delta) % 4
			var rot_state: Vector3i = state_key(cell, n_ori)
			if closed.has(rot_state):
				continue
			if not _fits(map, cell, offsets[n_ori], occupied):
				continue
			var n_turns: int = spent_turns + 1
			if _relax(dist, turns, rot_state, steps, n_turns):
				prev[rot_state] = cur
				_heap_push(open, Vector4i(rot_state.x, rot_state.y, rot_state.z, steps * HEAP_BIAS + n_turns))
		if steps >= max_cost:
			continue
		var offs: Array[Vector2i] = offsets[cur.z]
		for d in DIRS:
			var nxt: Vector2i = cell + d
			if not _fits(map, nxt, offs, occupied):
				continue
			var nd: int = steps + 1
			if nd > max_cost:
				continue
			var n_state: Vector3i = state_key(nxt, cur.z)
			if _relax(dist, turns, n_state, nd, spent_turns):
				prev[n_state] = cur
				_heap_push(open, Vector4i(n_state.x, n_state.y, n_state.z, nd * HEAP_BIAS + spent_turns))
	var by_anchor: Dictionary = {}
	for key in dist.keys():
		var st: Vector3i = key
		var c: Vector2i = state_cell(st)
		if not by_anchor.has(c):
			by_anchor[c] = st.z
			continue
		if _state_before(st, state_key(c, int(by_anchor[c])), dist, turns):
			by_anchor[c] = st.z
	return {"dist": dist, "turns": turns, "prev": prev, "orientation": by_anchor}


static func _state_before(a: Vector3i, b: Vector3i, dist: Dictionary, turns: Dictionary) -> bool:
	## Lexicographic (translations, rotations, state key). Used by the frontier and by
	## the per-anchor "best orientation" reduction, so both agree on what "best" means.
	var da: int = int(dist.get(a, 1 << 30))
	var db: int = int(dist.get(b, 1 << 30))
	if da != db:
		return da < db
	var ta: int = int(turns.get(a, 1 << 30))
	var tb: int = int(turns.get(b, 1 << 30))
	if ta != tb:
		return ta < tb
	return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))


static func _relax(dist: Dictionary, turns: Dictionary, state: Vector3i, d: int, t: int) -> bool:
	## True when (d, t) improves the best known cost of `state` (and writes it).
	if not dist.has(state):
		dist[state] = d
		turns[state] = t
		return true
	var known_d: int = int(dist[state])
	var known_t: int = int(turns[state])
	if d < known_d or (d == known_d and t < known_t):
		dist[state] = d
		turns[state] = t
		return true
	return false


static func build_state_path(prev: Dictionary, start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	## Full state route (translations AND rotations) from start to goal, inclusive.
	## Empty when unreachable. A rejected search yields no path rather than a guess.
	var path: Array[Vector3i] = []
	if goal == start:
		return path
	if not prev.has(goal):
		return path
	var cur: Vector3i = goal
	var guard: int = 0
	while cur != start and guard < 4096:
		guard += 1
		path.push_front(cur)
		if not prev.has(cur):
			return [] as Array[Vector3i]
		cur = prev[cur]
	if cur != start:
		return [] as Array[Vector3i]
	path.push_front(start)
	return path


static func state_path_cost(path: Array[Vector3i]) -> int:
	## Movement points for a state route: translations only, rotations are free.
	var cost: int = 0
	for i in range(1, path.size()):
		if state_cell(path[i]) != state_cell(path[i - 1]):
			cost += 1
	return cost


static func state_path_rotations(path: Array[Vector3i]) -> int:
	var turns: int = 0
	for i in range(1, path.size()):
		if path[i].z != path[i - 1].z:
			turns += 1
	return turns


static func state_path_anchors(path: Array[Vector3i]) -> Array[Vector2i]:
	## Anchor route with consecutive duplicates collapsed (a rotation keeps the cell),
	## so the renderer can lerp along it without zero-length segments.
	var out: Array[Vector2i] = []
	for st in path:
		var c: Vector2i = state_cell(st)
		if out.is_empty() or out[out.size() - 1] != c:
			out.append(c)
	return out
