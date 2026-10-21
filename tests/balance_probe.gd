extends SceneTree
## Diagnostic (not part of the gate): balance + AI activity across seeds.

const BattleScript = preload("res://scripts/core/battle.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")

func _initialize() -> void:
	print("seed  outcome  rounds  player_left  enemy_left  ai_hits  ai_moves  abilities")
	var seeds: Array[int] = [1, 2, 3, 4, 5, 11, 4242, 98765]
	var total_hits: int = 0
	var total_moves: int = 0
	var total_abilities: int = 0
	var victories: int = 0
	for sd in seeds:
		var b = BattleScript.new()
		b.setup(sd)
		var guard: int = 0
		var ai_hits: int = 0
		var ai_moves: int = 0
		var abilities: int = 0
		while b.outcome == "" and guard < 60:
			guard += 1
			_player_auto(b)
			if b.outcome != "":
				break
			var before_hits: int = _count(b.log_lines, "HKS")
			var phase_before: int = b.phase
			b.end_turn()
			ai_hits += _count(b.log_lines, "HKS") - before_hits
			for ev in b.events:
				if String(ev.get("type", "")) == "move":
					ai_moves += 1
				elif String(ev.get("type", "")) == "ability":
					abilities += 1
			b.events.clear()
		if b.outcome == "victory":
			victories += 1
		print("%5d %-8s %6d %12d %11d %8d %9d %9d" % [
			sd, b.outcome, b.round, b.alive_ships(0).size(), b.alive_ships(1).size(),
			ai_hits, ai_moves, abilities])
		total_hits += ai_hits
		total_moves += ai_moves
		total_abilities += abilities
	print("")
	print("auto-player victories %d/%d · AI attacks %d · AI moves %d · AI abilities %d" % [
		victories, seeds.size(), total_hits, total_moves, total_abilities])
	quit(0)


func _count(lines: Array, needle: String) -> int:
	var n: int = 0
	for l in lines:
		if String(l).begins_with(needle):
			n += 1
	return n


func _state_value(b, anchor: Vector2i, cells: Array[Vector2i], tgt, attack_range: int, field: Dictionary) -> int:
	## Higher is better. The BFS field is an obstacle-aware guide (it walks around rocks
	## and nebulae instead of hugging them); the firing test uses the authoritative
	## footprint rule. Both are needed: without the field the auto-player parks behind
	## a nebula because its Manhattan distance is already minimal.
	var score: int = -int(field.get(anchor, 9999)) * 10
	var d: int = b.cells_distance_to(cells, tgt)
	if d <= attack_range and b.cells_have_los_to(cells, tgt):
		score += 60
	return score


func _player_auto(b) -> void:
	## Stand-in for a human (see HANDOFF trap 10): it must judge positions with the
	## AUTHORITATIVE rules, which since STEP 2 means the whole footprint and the
	## orientation the search reports - not anchor-to-anchor Manhattan distance.
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
		# Baseline = staying put. Without it the first candidate always won and the
		# auto-player ping-ponged between equal states until the round limit.
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
