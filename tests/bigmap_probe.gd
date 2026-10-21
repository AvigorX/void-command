extends SceneTree
## M7B — battlefield scaling probe (measurement only, no assertions on timings).
##
## Answers one question the mandate asks and a test must not answer: what does an 80x80
## board cost? Map generation, Battle.setup (map + deployment search), a route search for
## the longest hull, one full enemy turn, and a breakdown of the AI's per-ship cost are
## timed per board. The numbers are printed, never asserted: an absolute millisecond
## threshold measures the host, not the game.
##
## Run:
##   $GODOT --headless --path projects/void-command --script res://tests/bigmap_probe.gd
##
## Deployments are built with the production validator (`FleetPoints.can_add`) so the
## measured fleets are fleets the game would actually let a player deploy.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const AIRef = preload("res://scripts/core/ai.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

const BUDGET: int = 200
const SEED: int = 7


func _initialize() -> void:
	SaveGuard.isolate()
	print("=== VOID COMMAND — BATTLEFIELD SCALING PROBE (M7B) ===")
	print("engine %s · seed %d · budget %d FP" % [Engine.get_version_info().get("string", "?"), SEED, BUDGET])
	print("")
	print("%-10s %7s %8s %5s %9s %9s %9s %8s %7s" % [
		"board", "cells", "gen ms", "att", "setup ms", "deploy ms", "route ms", "turn ms", "hulls"])
	for size in _sizes():
		_measure(size)
	print("")
	print("AI BREAKDOWN (player-side fleet, no attacks: route search vs position scoring)")
	print("%-10s %8s %11s %10s %10s %12s %11s" % ["board", "hulls", "states/ship", "search ms", "score ms", "per ship ms", "choose ms"])
	for size2 in _sizes():
		_profile_ai(size2)
	print("")
	print("RESULT: PASS")
	SaveGuard.cleanup()
	quit(0)


func _sizes() -> Array[Vector2i]:
	return [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL, Vector2i(48, 34),
		MapConfigRef.GRAND, MapConfigRef.TITAN]


func _measure(size: Vector2i) -> void:
	var label: String = MapConfigRef.label(size)
	# 1. Map generation alone, median of three.
	var map_times: Array[int] = []
	var tries: int = 0
	for i in range(3):
		var m = MapScript.new()
		var t0: int = Time.get_ticks_usec()
		m.setup(SEED, size)
		map_times.append(Time.get_ticks_usec() - t0)
		tries = int(m.generation_attempts)
	map_times.sort()
	var map_us: int = map_times[1]

	# 2. A full battle with a legal, capital-heavy fleet on both sides.
	var roster: Array[String] = _mixed_fleet()
	var b = BattleScript.new()
	var t1: int = Time.get_ticks_usec()
	b.setup(SEED, {}, 1, size, roster, roster)
	var setup_us: int = Time.get_ticks_usec() - t1
	var deploy_us: int = int(b.setup_profile.get("deploy_search_us", 0))

	# 3. Route search for the longest hull on the board.
	var route_us: int = 0
	var probe_ship = null
	for s in b.alive_ships(0):
		if probe_ship == null or s.footprint.y > probe_ship.footprint.y:
			probe_ship = s
	if probe_ship != null:
		probe_ship.move_points = maxi(probe_ship.max_move, 8)
		var t2: int = Time.get_ticks_usec()
		b.reachable_states(probe_ship.id)
		route_us = Time.get_ticks_usec() - t2

	# 4. One enemy turn end to end (AI movement + attacks + round bookkeeping).
	var t3: int = Time.get_ticks_usec()
	b.end_turn()
	var turn_us: int = Time.get_ticks_usec() - t3

	print("%-10s %7d %8.1f %5d %9.1f %9.1f %9.1f %8.1f %7d" % [
		label, size.x * size.y, map_us / 1000.0, tries, setup_us / 1000.0, deploy_us / 1000.0,
		route_us / 1000.0, turn_us / 1000.0, b.alive_ships(0).size()])


func _profile_ai(size: Vector2i) -> void:
	## Splits the per-ship AI cost into the route search and the position scoring, so an
	## optimisation targets the part that actually dominates instead of the one that looks
	## expensive. Scoring is measured on the REAL states the search returned.
	var roster: Array[String] = _mixed_fleet()
	var b = BattleScript.new()
	b.setup(SEED + 1, {}, 1, size, roster, roster)
	var total_states: int = 0
	var search_us: int = 0
	var score_us: int = 0
	var choose_us: int = 0
	var ships: int = 0
	var t_all: int = Time.get_ticks_usec()
	for s in b.alive_ships(1):
		var t0: int = Time.get_ticks_usec()
		var states: Dictionary = b.reachable_states(s.id)
		search_us += Time.get_ticks_usec() - t0
		var keys: Array = states.get("dist", {}).keys()
		total_states += keys.size()
		var target = AIRef._best_target(b, s, b.alive_ships(1 - s.team))
		var field: Dictionary = PathfinderRef.distance_field(b.map, target.cell) if target != null else {}
		var control: Dictionary = PathfinderRef.distance_field(b.map, b.map.control_cell)
		var t1: int = Time.get_ticks_usec()
		for key in keys:
			var st: Vector3i = key
			AIRef._state_score(b, s, target, Vector2i(st.x, st.y), st.z, field, control)
		score_us += Time.get_ticks_usec() - t1
		var t2: int = Time.get_ticks_usec()
		AIRef._choose_destination(b, s, target)
		choose_us += Time.get_ticks_usec() - t2
		ships += 1
	var total_us: int = Time.get_ticks_usec() - t_all
	print("%-10s %8d %11.0f %10.1f %10.1f %12.1f %11.1f" % [
		MapConfigRef.label(size), ships,
		float(total_states) / maxf(1.0, float(ships)), search_us / 1000.0, score_us / 1000.0,
		total_us / 1000.0 / maxf(1.0, float(ships)), choose_us / 1000.0])


func _mixed_fleet() -> Array[String]:
	## A capital-heavy 200 FP fleet, built through the production composition rules.
	var roster: Array[String] = []
	for wanted in ["dreadnought", "battleship", "battleship", "carrier", "cruiser", "cruiser",
			"frigate", "frigate", "destroyer"]:
		if bool(FleetRef.can_add(roster, wanted, BUDGET)["ok"]):
			roster.append(wanted)
	var fillers: Array[String] = ["fighter", "interceptor"]
	var i: int = 0
	while i < 400:
		i += 1
		var cls: String = fillers[i % 2]
		if not bool(FleetRef.can_add(roster, cls, BUDGET)["ok"]):
			break
		roster.append(cls)
	return roster
