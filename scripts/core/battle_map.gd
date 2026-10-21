class_name BattleMap
extends RefCounted
## Seeded tactical grid: terrain, deployment zones, control point, connectivity.
##
## M6 removed asteroid fields entirely: they are no longer generated, drawn, blocking or
## part of the terrain enum. Planets still block movement and line of sight, nebulae still
## block line of sight and reduce damage, so cover and terrain decisions survive.

const WIDTH: int = 20
const HEIGHT: int = 14

const FootprintRef = preload("res://scripts/core/footprint.gd")

enum Terrain { VOID = 0, PLANET = 2, NEBULA = 3 }

var width: int = WIDTH
var height: int = HEIGHT
var cells: PackedInt32Array = PackedInt32Array()
var seed_value: int = 0
var control_cell: Vector2i = Vector2i(10, 7)
var planet_anchors: Array[Vector2i] = []
var generation_attempts: int = 1

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func setup(p_seed: int, p_size: Vector2i = MapConfig.REFERENCE) -> void:
	## Seeded generation for a battlefield of `p_size` cells.
	##
	## `MapConfig.REFERENCE` (20x14) runs the ORIGINAL generator, unchanged, so every
	## historical seed still produces the exact same map - the fingerprints are pinned
	## in tests/test_maps.gd. Any other size runs the scaled generator, which keeps the
	## obstacle DENSITY (not the raw count) comparable and leaves a manoeuvre corridor.
	seed_value = p_seed
	width = p_size.x
	height = p_size.y
	control_cell = Vector2i(width / 2, height / 2)
	var reference: bool = p_size == MapConfig.REFERENCE
	for attempt in range(40):
		generation_attempts = attempt + 1
		if reference:
			_build(attempt)
		else:
			_build_scaled(attempt)
		# Connectivity alone is a 1x1 promise. A capital hull needs a route too: the M5
		# measurement found that one 20x14 seed in ten left a meaningful pocket unreachable
		# to a 1x5 hull even though every single cell was connected.
		if _zones_connected() and _capital_route_ok():
			return
	# Deterministic fallback: clear a corridor along the middle row and keep the layout.
	for x in range(4, width - 4):
		cells[_idx(Vector2i(x, height / 2))] = Terrain.VOID
	generation_attempts = 41


func _build(attempt: int) -> void:
	cells.resize(width * height)
	cells.fill(Terrain.VOID)
	planet_anchors.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + attempt * 104729

	# Nebula clouds: passable, block line of sight, damage reduction inside.
	for i in range(7):
		var c := Vector2i(rng.randi_range(5, 14), rng.randi_range(1, height - 2))
		var r: int = rng.randi_range(1, 2)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) + abs(dy) > r + 1:
					continue
				var p := c + Vector2i(dx, dy)
				if _in(p) and not _in_deploy(p):
					_put(p, Terrain.NEBULA)

	# Planets: impassable, block line of sight, 2x2 mass.
	var planet_count: int = rng.randi_range(2, 3)
	for i in range(planet_count):
		var c := Vector2i(rng.randi_range(6, 13), rng.randi_range(2, height - 4))
		var span_x: int = rng.randi_range(1, 2)
		var span_y: int = rng.randi_range(1, 2)
		var ok := true
		for dx in range(span_x):
			for dy in range(span_y):
				if not _in(c + Vector2i(dx, dy)) or _in_deploy(c + Vector2i(dx, dy)):
					ok = false
		if not ok:
			continue
		planet_anchors.append(c)
		for dx in range(span_x):
			for dy in range(span_y):
				_put(c + Vector2i(dx, dy), Terrain.PLANET)

	# Control point near the middle, on a free cell.
	var middle := Vector2i(width / 2, height / 2)
	control_cell = _nearest_free(middle)



func _build_scaled(attempt: int) -> void:
	## Generator for every size except the reference one.
	##
	## Counts scale with the SQUARE ROOT of the area, not with the area: doubling the
	## board must not double the obstacles, or the extra space buys no manoeuvre room
	## for 1x4 hulls. The bands also keep the middle third of the board the least
	## cluttered, so both fleets can actually meet.
	cells.resize(width * height)
	cells.fill(Terrain.VOID)
	planet_anchors.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + attempt * 104729
	var ratio: float = MapConfig.area_ratio(Vector2i(width, height))
	var spread: float = sqrt(ratio)
	var x_lo: int = int(round(float(width) * 0.20))
	var x_hi: int = int(round(float(width) * 0.80))
	var y_lo: int = maxi(1, int(round(float(height) * 0.06)))
	var y_hi: int = height - 2

	# Nebula clouds: passable, block line of sight, damage reduction inside.
	var nebula_count: int = maxi(4, int(round(7.0 * spread)))
	for i in range(nebula_count):
		var c := Vector2i(rng.randi_range(x_lo, x_hi), rng.randi_range(y_lo, y_hi))
		var r: int = rng.randi_range(1, 2)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) + abs(dy) > r + 1:
					continue
				var p := c + Vector2i(dx, dy)
				if _in(p) and not _in_band(p):
					_put(p, Terrain.NEBULA)

	# Planets: impassable, block line of sight, 1x1..2x2 mass.
	var planet_count: int = clampi(int(round(2.5 * spread)), 2, 6)
	for i in range(planet_count):
		var c2 := Vector2i(rng.randi_range(x_lo + 1, x_hi - 1), rng.randi_range(maxi(2, y_lo + 1), y_hi - 2))
		var span_x: int = rng.randi_range(1, 2)
		var span_y: int = rng.randi_range(1, 2)
		var ok := true
		for dx in range(span_x):
			for dy in range(span_y):
				if not _in(c2 + Vector2i(dx, dy)) or _in_band(c2 + Vector2i(dx, dy)):
					ok = false
		if not ok:
			continue
		planet_anchors.append(c2)
		for dx in range(span_x):
			for dy in range(span_y):
				_put(c2 + Vector2i(dx, dy), Terrain.PLANET)

	# Control point near the middle, on a free cell.
	control_cell = _nearest_free(Vector2i(width / 2, height / 2))



func _nearest_free(center: Vector2i) -> Vector2i:
	for radius in range(0, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) + abs(dy) != radius:
					continue
				var p := center + Vector2i(dx, dy)
				if _in(p) and not is_blocked(p) and not _in_band(p):
					return p
	return center


func nav_stats(footprint: Vector2i) -> Dictionary:
	## Navigation report for one hull shape on THIS map, using the same rules as the route
	## search: a state is (anchor, orientation), translations cost 1, rotations are free and
	## only allowed where the whole hull fits. Pure and side-effect free, so both the
	## generator and the navigation suite can call it.
	var states: Dictionary = {}
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			for o in range(4):
				if _hull_fits(cell, footprint, o):
					states[Vector3i(x, y, o)] = true
	var starts: Array[Vector3i] = []
	for k in states.keys():
		if k.x <= 3:
			starts.append(k)
	var seen: Dictionary = {}
	var queue: Array[Vector3i] = []
	for st in starts:
		if not seen.has(st):
			seen[st] = true
			queue.append(st)
	var head: int = 0
	while head < queue.size():
		var cur: Vector3i = queue[head]
		head += 1
		var cell2 := Vector2i(cur.x, cur.y)
		for d in DIRS:
			var n := Vector3i(cell2.x + d.x, cell2.y + d.y, cur.z)
			if states.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
		for o2 in range(4):
			var r := Vector3i(cur.x, cur.y, o2)
			if states.has(r) and not seen.has(r):
				seen[r] = true
				queue.append(r)
	var anchors: Dictionary = {}
	var reachable_anchors: Dictionary = {}
	for k2 in states.keys():
		anchors[Vector2i(k2.x, k2.y)] = true
	for k3 in seen.keys():
		reachable_anchors[Vector2i(k3.x, k3.y)] = true
	var crosses: bool = false
	for k4 in seen.keys():
		for c in FootprintRef.cells(Vector2i(k4.x, k4.y), footprint, k4.z):
			if c.x >= width - 4:
				crosses = true
				break
		if crosses:
			break
	return {
		"feasible_anchors": anchors.size(),
		"reachable_anchors": reachable_anchors.size(),
		"pocket_anchors": anchors.size() - reachable_anchors.size(),
		"crosses": crosses,
	}


func _hull_fits(cell: Vector2i, footprint: Vector2i, orientation: int) -> bool:
	for c in FootprintRef.cells(cell, footprint, orientation):
		if not in_bounds(c) or is_blocked(c):
			return false
	return true


func _capital_route_ok() -> bool:
	## Gate for the generator: the largest hull must be able to leave its band and reach the
	## other half, and no more than 8% of its feasible anchors may end up in isolated
	## pockets. Below that, an unreachable cranny is terrain; above it, the map is broken.
	var nav: Dictionary = nav_stats(Vector2i(1, 5))
	if not bool(nav["crosses"]):
		return false
	var feasible: int = int(nav["feasible_anchors"])
	if feasible == 0:
		return false
	return float(nav["pocket_anchors"]) <= maxf(8.0, float(feasible) * 0.08)


func _zones_connected() -> bool:
	var start := Vector2i(2, height / 2)
	var goal := Vector2i(width - 3, height / 2)
	if is_blocked(start):
		start = _nearest_free(start)
	if is_blocked(goal):
		goal = _nearest_free(goal)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			return true
		for d in DIRS:
			var n := cur + d
			if _in(n) and not is_blocked(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return false


func _idx(c: Vector2i) -> int:
	return c.y * width + c.x


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func _in_deploy(c: Vector2i) -> bool:
	## Historical four-column guard, kept EXACTLY as it is because the reference generator
	## is pinned: changing it would move the 20x14 fingerprints. The scaled generator uses
	## `_in_band()`, which asks the same question the deployment does.
	return c.x <= 3 or c.x >= width - 4


func _in_band(c: Vector2i) -> bool:
	## True for a cell inside EITHER deployment band, using the authoritative zone rule.
	## `_in_deploy` above still says four columns while the bands are `DEPLOY_BAND` wide,
	## so on a scaled board terrain could be generated on a cell the fleet must deploy on.
	return is_deploy_zone(c, 0) or is_deploy_zone(c, 1)


func _put(c: Vector2i, value: int) -> void:
	if _in(c):
		cells[_idx(c)] = value


func in_bounds(c: Vector2i) -> bool:
	return _in(c)


func at(c: Vector2i) -> int:
	if not _in(c):
		return Terrain.PLANET
	return cells[_idx(c)]


## M7: the band has to hold the LONGEST hull deployed HORIZONTALLY, not a fixed four
## columns. With hulls laid out along the x axis, a 1x5 needs five columns; a four-column
## band made every capital ship undeployable on the grand board.
const DEPLOY_BAND: int = 6


func is_deploy_zone(c: Vector2i, team: int) -> bool:
	if not _in(c):
		return false
	var band: int = mini(DEPLOY_BAND, maxi(1, width / 4))
	if team == 0:
		return c.x < band
	return c.x >= width - band


func is_blocked(c: Vector2i) -> bool:
	var t := at(c)
	return t == Terrain.PLANET


func blocks_los(c: Vector2i) -> bool:
	var t := at(c)
	return t == Terrain.PLANET or t == Terrain.NEBULA


func is_cover(c: Vector2i) -> bool:
	return at(c) == Terrain.NEBULA


func terrain_name(c: Vector2i) -> String:
	match at(c):
		Terrain.PLANET:
			return "Planet"
		Terrain.NEBULA:
			return "Nebula"
		_:
			return "Open space"


func has_line_of_sight(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	## Bresenham: intermediate cells must not block; endpoints are always allowed.
	var x0: int = from_cell.x
	var y0: int = from_cell.y
	var x1: int = to_cell.x
	var y1: int = to_cell.y
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var guard: int = 0
	while guard < 256:
		guard += 1
		if x0 == x1 and y0 == y1:
			return true
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
		if x0 == x1 and y0 == y1:
			return true
		if blocks_los(Vector2i(x0, y0)):
			return false
	return true


func passable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var c := Vector2i(x, y)
			if not is_blocked(c):
				out.append(c)
	return out


func cell_hash(c: Vector2i) -> int:
	return abs(seed_value * 73856093 ^ c.x * 19349663 ^ c.y * 83492791)
