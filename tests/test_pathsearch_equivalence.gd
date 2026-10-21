extends SceneTree
## M7B — route-search equivalence guard.
##
## `Pathfinder.explore_states` replaced its linear frontier scan with a binary heap. That
## is a performance change, so the only acceptable proof is that it computes the SAME
## search: same states, same distances, same rotation counts, same parent links, hence the
## same routes. This suite keeps a copy of the previous implementation (`_reference_*`,
## verbatim linear scan) and compares the two on a grid of boards, footprints,
## orientations, occupancies and movement budgets.
##
## If someone later "optimises" the search again, this is the suite that says whether the
## behaviour moved. It also protects the deployment pocket check and the AI, which both
## consume `explore_states` directly.

const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const MapRef = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var cases: int = 0


func _initialize() -> void:
	SaveGuard.isolate()
	print("=== VOID COMMAND — ROUTE SEARCH EQUIVALENCE (M7B) ===")
	var sizes: Array[Vector2i] = [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL, MapConfigRef.TITAN]
	var footprints: Array[Vector2i] = [Vector2i.ONE, Vector2i(1, 3), Vector2i(1, 5)]
	for size in sizes:
		for seed_value in [3, 7]:
			var m = MapRef.new()
			m.setup(seed_value, size)
			# A little traffic, so occupancy is part of the comparison and not an empty set.
			var occupied: Dictionary = {}
			for i in range(6):
				var c := Vector2i(2 + i * 3, 1 + (i * 5) % (size.y - 2))
				if m.in_bounds(c) and not m.is_blocked(c):
					occupied[c] = 100 + i
			for fp in footprints:
				for orientation in range(4):
					_compare(m, occupied, fp, orientation, 6)
					_compare(m, occupied, fp, orientation, 8)
				_compare_escapes(m, occupied, fp, seed_value)
	print("")
	print("  %d cases compared (dist, turns, orientation map, routes)" % cases)
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _compare(m, occupied: Dictionary, fp: Vector2i, orientation: int, budget: int) -> void:
	## One board/footprint/orientation/budget case: find a free anchor, run both searches,
	## compare everything a caller can observe.
	var start := Vector2i(-1, -1)
	for y in range(m.height):
		for x in range(m.width):
			var c := Vector2i(x, y)
			var fits: bool = true
			for cell in FootprintRef.cells(c, fp, orientation):
				if not m.in_bounds(cell) or m.is_blocked(cell) or occupied.has(cell):
					fits = false
					break
			if fits:
				start = c
				break
		if start.x >= 0:
			break
	if start.x < 0:
		return
	cases += 1
	var got: Dictionary = PathfinderRef.explore_states(m, start, orientation, budget, occupied, fp)
	var want: Dictionary = _reference_explore(m, start, orientation, budget, occupied, fp)
	var label: String = "%s %s ori %d budget %d" % [MapConfigRef.label(Vector2i(m.width, m.height)), str(fp), orientation, budget]

	var got_dist: Dictionary = got["dist"]
	var want_dist: Dictionary = want["dist"]
	ok(got_dist.size() == want_dist.size(),
		"%s: same number of reachable states (%d vs %d)" % [label, got_dist.size(), want_dist.size()])
	var mismatch_d: int = 0
	var mismatch_t: int = 0
	var mismatch_p: int = 0
	for key in want_dist.keys():
		if not got_dist.has(key):
			mismatch_d += 1
			continue
		if int(got_dist[key]) != int(want_dist[key]):
			mismatch_d += 1
		if int(got["turns"].get(key, -1)) != int(want["turns"].get(key, -1)):
			mismatch_t += 1
		# Parent links must agree too: they are what build_state_path follows.
		if str(got["prev"].get(key, Vector3i(-1, -1, -1))) != str(want["prev"].get(key, Vector3i(-1, -1, -1))):
			mismatch_p += 1
	ok(mismatch_d == 0, "%s: every distance matches (%d mismatches)" % [label, mismatch_d])
	ok(mismatch_t == 0, "%s: every rotation count matches (%d mismatches)" % [label, mismatch_t])
	ok(mismatch_p == 0, "%s: every parent link matches (%d mismatches)" % [label, mismatch_p])

	var got_ori: Dictionary = got["orientation"]
	var want_ori: Dictionary = want["orientation"]
	var mismatch_o: int = 0
	for anchor in want_ori.keys():
		if int(got_ori.get(anchor, -9)) != int(want_ori[anchor]):
			mismatch_o += 1
	ok(mismatch_o == 0 and got_ori.size() == want_ori.size(),
		"%s: the per-anchor best orientation agrees (%d mismatches)" % [label, mismatch_o])

	# A route to the farthest state must be identical, cell by cell.
	var farthest: Vector3i = Vector3i.ZERO
	var farthest_d: int = -1
	for key in want_dist.keys():
		if int(want_dist[key]) > farthest_d:
			farthest_d = int(want_dist[key])
			farthest = key
	if farthest_d > 0:
		var got_path: Array[Vector3i] = PathfinderRef.build_state_path(
			got["prev"], PathfinderRef.state_key(start, orientation), farthest)
		var want_path: Array[Vector3i] = PathfinderRef.build_state_path(
			want["prev"], PathfinderRef.state_key(start, orientation), farthest)
		ok(str(got_path) == str(want_path),
			"%s: the route to the farthest state is identical (%d vs %d states)" % [
				label, got_path.size(), want_path.size()])
		ok(PathfinderRef.state_path_cost(got_path) == PathfinderRef.state_path_cost(want_path)
				and PathfinderRef.state_path_rotations(got_path) == PathfinderRef.state_path_rotations(want_path),
			"%s: the route costs the same movement and the same turns" % label)


func _compare_escapes(m, occupied: Dictionary, fp: Vector2i, seed_value: int) -> void:
	## `escapes_deploy_band` must answer exactly what the old pocket check answered: does
	## the full state search reach any anchor outside the team's band? Compared on a sample
	## of legal anchors per board, both teams and two movement budgets, and NEVER on an
	## anchor where the hull does not fit (that is a different question).
	var checked: int = 0
	var step: int = maxi(1, m.width / 10)
	for y in range(0, m.height, step):
		for x in range(0, m.width, step):
			var anchor := Vector2i(x, y)
			for orientation in range(4):
				var fits_here: bool = true
				for cell in FootprintRef.cells(anchor, fp, orientation):
					if not m.in_bounds(cell) or m.is_blocked(cell) or occupied.has(cell):
						fits_here = false
						break
				if not fits_here:
					continue
				for budget in [6, 10]:
					var states: Dictionary = PathfinderRef.explore_states(
						m, anchor, orientation, budget, occupied, fp)
					for team in [0, 1]:
						var want: bool = false
						for key in states.get("dist", {}).keys():
							if not m.is_deploy_zone(PathfinderRef.state_cell(key), team):
								want = true
								break
						var got: bool = PathfinderRef.escapes_deploy_band(
							m, anchor, orientation, budget, occupied, fp, team)
						ok(got == want, "%s %s anchor %s ori %d budget %d team %d: pocket verdict %s vs %s" % [
							MapConfigRef.label(Vector2i(m.width, m.height)), str(fp), str(anchor),
							orientation, budget, team, str(got), str(want)])
						checked += 1
						if checked >= 24:
							return


func _reference_explore(map, start: Vector2i, start_orientation: int, max_cost: int,
		occupied: Dictionary, size: Vector2i) -> Dictionary:
	## The implementation `explore_states` had before M7B: identical rules, linear frontier.
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
	var start_state: Vector3i = PathfinderRef.state_key(start, start_orientation)
	dist[start_state] = 0
	turns[start_state] = 0
	var open: Array[Vector3i] = [start_state]
	while open.size() > 0:
		var best_index: int = 0
		for i in range(1, open.size()):
			if PathfinderRef._state_before(open[i], open[best_index], dist, turns):
				best_index = i
		var cur: Vector3i = open[best_index]
		open.remove_at(best_index)
		if closed.has(cur):
			continue
		closed[cur] = true
		var steps: int = int(dist[cur])
		var spent_turns: int = int(turns[cur])
		var cell: Vector2i = PathfinderRef.state_cell(cur)
		for delta in [1, 3]:
			var n_ori: int = (cur.z + delta) % 4
			var rot_state: Vector3i = PathfinderRef.state_key(cell, n_ori)
			if closed.has(rot_state):
				continue
			if not PathfinderRef._fits(map, cell, offsets[n_ori], occupied):
				continue
			var n_turns: int = spent_turns + 1
			if PathfinderRef._relax(dist, turns, rot_state, steps, n_turns):
				prev[rot_state] = cur
				open.append(rot_state)
		if steps >= max_cost:
			continue
		var offs: Array[Vector2i] = offsets[cur.z]
		for d in PathfinderRef.DIRS:
			var nxt: Vector2i = cell + d
			if not PathfinderRef._fits(map, nxt, offs, occupied):
				continue
			var nd: int = steps + 1
			if nd > max_cost:
				continue
			var n_state: Vector3i = PathfinderRef.state_key(nxt, cur.z)
			if PathfinderRef._relax(dist, turns, n_state, nd, spent_turns):
				prev[n_state] = cur
				open.append(n_state)
	var by_anchor: Dictionary = {}
	for key in dist.keys():
		var st: Vector3i = key
		var c: Vector2i = PathfinderRef.state_cell(st)
		if not by_anchor.has(c):
			by_anchor[c] = st.z
			continue
		if PathfinderRef._state_before(st, PathfinderRef.state_key(c, int(by_anchor[c])), dist, turns):
			by_anchor[c] = st.z
	return {"dist": dist, "turns": turns, "prev": prev, "orientation": by_anchor}


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
