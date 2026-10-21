extends SceneTree
## M5 — where does Battle.setup() spend its time?
##
## Five runs per configuration, median and range, with the deployment search separated from
## the map build and from everything else. Timings come from `setup_profile`, filled by the
## battle itself, so the numbers are reproducible and not a stopwatch around the call.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")

func _initialize() -> void:
	print("=== VOID COMMAND — SETUP PROFILE (M5) ===")
	print("hulls  board   total_ms (min..max)  map_ms  deploy_search_ms  attempts")
	var fleets: Array = [
		["fighter", "fighter", "frigate", "cruiser", "battleship"],
		["interceptor", "interceptor", "interceptor", "fighter", "fighter", "fighter",
			"frigate", "frigate", "cruiser", "cruiser", "battleship", "carrier"],
		["dreadnought", "battleship", "battleship", "carrier", "carrier", "cruiser", "cruiser",
			"frigate", "frigate", "interceptor", "interceptor", "fighter", "fighter",
			"fighter", "destroyer", "destroyer", "destroyer", "destroyer"],
		["interceptor", "interceptor", "interceptor", "interceptor", "interceptor",
			"interceptor", "interceptor", "interceptor", "interceptor", "interceptor",
			"fighter", "fighter", "fighter", "fighter", "fighter", "fighter", "fighter",
			"fighter", "fighter", "frigate", "frigate", "frigate", "frigate", "frigate",
			"frigate", "frigate", "frigate", "cruiser"],
	]
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		for fleet in fleets:
			var totals: Array[int] = []
			var maps: Array[int] = []
			var deploys: Array[int] = []
			var attempts: Array[int] = []
			for i in range(5):
				var b = BattleScript.new()
				b.setup(i + 1, {}, 1, size, fleet, ["fighter"])
				totals.append(int(b.setup_profile["total_us"]))
				maps.append(int(b.setup_profile["map_us"]))
				deploys.append(int(b.setup_profile["deploy_search_us"]))
				attempts.append(int(b.setup_profile["deploy_attempts"]))
			print("%5d  %-7s %6.0f (%5.0f..%5.0f) %7.1f %16.1f %9.1f" % [
				fleet.size(), MapConfigRef.label(size),
				_median(totals) / 1000.0, totals.min() / 1000.0, totals.max() / 1000.0,
				_median(maps) / 1000.0, _median(deploys) / 1000.0, _median(attempts)])
	quit(0)


func _median(values: Array) -> float:
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])
