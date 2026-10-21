extends SceneTree
## M6 — what board actually holds two 200 FP fleets?
##
## For each candidate size and budget it generates the same enemy fleet the game would
## generate, builds the battle, and measures: hulls, cells occupied, free cells, whether
## BOTH sides deployed, and whether the deployment band leaves room to move afterwards.
## The chosen `MapConfig.GRAND` must be justified by these numbers, not by taste.

const BattleScript = preload("res://scripts/core/battle.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")

const CANDIDATES: Array = [
	Vector2i(20, 14),
	Vector2i(32, 22),
	Vector2i(40, 28),
	Vector2i(48, 34),
]
const BUDGETS: Array[String] = ["skirmish", "standard", "fleet_engagement", "grand_fleet"]

var checks: int = 0
var failures: int = 0
var measured: Dictionary = {}


func _initialize() -> void:
	print("=== M6 CAPACITY: two fleets, both sides, real deployment ===")
	print("board    budget      hulls  cells  free  band  pivot  deployed")
	for size in CANDIDATES:
		for mode in BUDGETS:
			var budget: int = FleetRef.budget_of(mode)
			var gen: Dictionary = FleetRef.generate_enemy(7, budget, size)
			var roster: Array = gen["entries"]
			var b = BattleScript.new()
			b.setup(7, {}, 1, size, roster, roster)
			var hulls: int = b.alive_ships(0).size() + b.alive_ships(1).size()
			var cells: int = 0
			for s in b.ships:
				cells += int(s.footprint.x) * int(s.footprint.y)
			var free: int = size.x * size.y - cells - _blocked(b)
			var band: int = 4 * size.y
			var pivot: int = _pivot_room(b, roster)
			var deployed: String = "yes" if b.deploy_failures.is_empty() else "NO %d" % b.deploy_failures.size()
			print("%-8s %-15s %5d %6d %5d %5d %6d  %s" % [
				MapConfigRef.label(size), mode, hulls, cells, free, band, pivot, deployed])
			measured["%s|%s" % [MapConfigRef.label(size), mode]] = {
				"deployed": b.deploy_failures.is_empty(), "free": free, "pivot": pivot,
			}
		print("")
	# The ship decision depends on these two facts and nothing else: 32x22 cannot hold a
	# 200 FP fleet, 48x34 can and leaves room in the band. If a generator change ever flips
	# them, the chosen board is no longer justified and this fails.
	ok(not bool(measured["32×22|grand_fleet"]["deployed"]),
		"32x22 still cannot deploy two 200 FP fleets (the reason GRAND exists)")
	ok(bool(measured["48×34|grand_fleet"]["deployed"]),
		"48x34 deploys both 200 FP fleets")
	ok(int(measured["48×34|grand_fleet"]["pivot"]) >= 20,
		"48x34 leaves room in the band after 200 FP (%d free cells)" % int(measured["48×34|grand_fleet"]["pivot"]))
	ok(MapConfigRef.GRAND == Vector2i(48, 34), "the shipping grand preset is the measured one")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)


func _blocked(b) -> int:
	var n: int = 0
	for y in range(b.map.height):
		for x in range(b.map.width):
			if b.map.is_blocked(Vector2i(x, y)):
				n += 1
	return n


func _pivot_room(b, _roster: Array) -> int:
	## Free, unblocked cells left inside the deployment band after the fleet is placed:
	## the raw headroom a player still has for another hull. Cheap and geometric.
	var free: int = 0
	for x in range(0, 4):
		for y in range(b.map.height):
			var c := Vector2i(x, y)
			if not b.map.is_blocked(c) and b.ship_at(c) == null:
				free += 1
	return free
