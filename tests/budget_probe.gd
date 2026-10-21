extends SceneTree
## M4 — fleet composition probe for the four budgets.
##
## What it measures: what the deterministic enemy generator produces at 60 / 100 / 150 / 200
## FP on both boards - hull count, spend, cells used against the real deployment capacity,
## deployability, and determinism.
##
## What it deliberately does NOT measure: win rates per budget. The auto-player lives inside
## `balance_probe.gd` and is written for the historical roster; producing per-budget win rates
## would need that player generalised first, and a crude player's numbers would be worse than
## no numbers. That gap is stated in the report instead of being filled with a guess.

const FleetRef = preload("res://scripts/core/fleet_points.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	print("=== VOID COMMAND — FLEET BUDGET PROBE (M4) ===")
	print("mode              board   hulls  spent  left  cells  cap  deploy  ms")
	for mode in FleetRef.mode_ids():
		var budget: int = FleetRef.budget_of(mode)
		for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
			var t0: int = Time.get_ticks_msec()
			var gen: Dictionary = FleetRef.generate_enemy(4242, budget, size)
			var ms: int = Time.get_ticks_msec() - t0
			var entries: Array = gen["entries"]
			var cells: int = 0
			for id in entries:
				cells += FleetRef.footprint_cells(String(id))
			print("%-16s %-7s %5d %6d %5d %6d %4d %7s %4d" % [
				mode, MapConfigRef.label(size), entries.size(), int(gen["spent"]),
				int(gen["remaining"]), cells, int(gen.get("cell_budget", 0)),
				"yes" if bool(gen["deployable"]) else "NO", ms])
			ok(bool(gen["ok"]), "%s/%s produces a fleet" % [mode, MapConfigRef.label(size)])
			ok(bool(gen["deployable"]), "%s/%s is deployable" % [mode, MapConfigRef.label(size)])
			ok(int(gen["spent"]) <= budget, "%s/%s respects the budget" % [mode, MapConfigRef.label(size)])
			ok(cells <= int(gen.get("cell_budget", 0)), "%s/%s respects the cell budget" % [mode, MapConfigRef.label(size)])
			var again: Dictionary = FleetRef.generate_enemy(4242, budget, size)
			ok(again["entries"] == entries, "%s/%s is deterministic" % [mode, MapConfigRef.label(size)])
			for id2 in ShipDefsRef.available_classes():
				var cap: int = ShipDefsRef.cap_of(id2)
				ok(cap == 0 or FleetRef.count_of(entries, id2) <= cap,
					"%s/%s respects the %s cap" % [mode, MapConfigRef.label(size), id2])
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
