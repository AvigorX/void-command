extends SceneTree
## M6 — Carrier interceptor production.
##
## Every rule in the mandate is asserted here: one swarm per round, ten per battle, the
## ability is exhausted for good, no production after the hull dies, no launch is consumed
## when the spawn fails, the spawn is legal, the counter survives round changes and a
## save/load, and one Carrier per fleet is enforced by the CORE, not by the UI.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const SaveRef = preload("res://scripts/core/battle_save.gd")
const SaveGuard = preload("res://tests/save_guard.gd")


var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	# Instantiating a BattleScreen touches the battle autosave path: without this the
	# suite writes into the real user profile (found by the gate's double fingerprint).
	SaveGuard.isolate()
	print("=== VOID COMMAND — CARRIER PRODUCTION (M6) ===")
	test_cap()
	test_production()
	test_spawn_is_legal()
	test_blocked_spawn_consumes_nothing()
	test_destroyed_carrier_cannot_launch()
	test_determinism()
	test_snapshot_round_trip()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _battle(player: Array, enemy: Array = ["fighter"], seed_value: int = 4242):
	var b = BattleScript.new()
	b.setup(seed_value, {}, 1, MapConfigRef.REFERENCE, player, enemy)
	b.ai_enabled = false
	return b


func _carrier(b):
	for s in b.alive_ships(0):
		if s.ship_class == "carrier":
			return s
	return null


func test_cap() -> void:
	var ok2: Dictionary = FleetRef.can_add(["carrier"], "carrier", 400)
	ok(not bool(ok2["ok"]), "the core refuses a second Carrier: %s" % String(ok2.get("reason", "")))
	var ok1: Dictionary = FleetRef.can_add([], "carrier", 400)
	ok(bool(ok1["ok"]), "the core accepts the first Carrier")
	ok(int(preload("res://scripts/core/ship_defs.gd").cap_of("carrier")) == 1, "the catalog cap for Carrier is 1")
	# A budget high enough for two Carriers still yields one: no hidden global hull cap.
	var built: Array[String] = []
	for i in range(6):
		if bool(FleetRef.can_add(built, "carrier", 400)["ok"]):
			built.append("carrier")
	ok(built.size() == 1, "six attempts produce exactly one Carrier (%d)" % built.size())


func test_production() -> void:
	var b = _battle(["carrier"])
	var c = _carrier(b)
	ok(c != null, "the Carrier is on the board")
	ok(int(c.squadrons_launched) == 0, "it starts with zero swarms launched")
	var kind := String(c.ability.get("kind", ""))
	ok(kind == "launch", "its ability is the launcher (kind=%s)" % kind)
	var limit: int = int(c.ability.get("limit", 0))
	ok(limit == 10, "the limit is ten swarms (%d)" % limit)

	var before: int = b.alive_ships(0).size()
	var res: Dictionary = b.use_ability(c.id)
	ok(bool(res["ok"]), "the first launch succeeds: %s" % String(res.get("reason", "")))
	ok(int(c.squadrons_launched) == 1, "the counter is 1")
	ok(b.alive_ships(0).size() == before + 1, "exactly one new unit exists")
	var spawned = b.get_ship(int(res.get("spawn", -1)))
	ok(spawned != null and spawned.ship_class == "interceptor", "the new unit is an Interceptor")
	ok(spawned != null and spawned.team == 0, "it belongs to the Carrier's fleet")
	ok(spawned != null and spawned.footprint == Vector2i(1, 1), "it occupies one cell")

	# One per round: the second call in the SAME round is refused.
	var again: Dictionary = b.use_ability(c.id)
	ok(not bool(again["ok"]), "a second launch in the same round is refused")
	ok(int(c.squadrons_launched) == 1, "and the counter did not move")

	# Next round: allowed again, counter keeps climbing and never resets. A real battle
	# moves the swarms away; a stationary test would fill the ring and the refusal would be
	# CORRECT behaviour, so the test flies each new swarm clear of the flight deck.
	for round_index in range(9):
		b.end_turn()
		_move_swarms_away(b, c)
		var r: Dictionary = b.use_ability(c.id)
		ok(bool(r["ok"]), "round %d launches: %s" % [round_index + 2, String(r.get("reason", ""))])
	ok(int(c.squadrons_launched) == 10, "ten swarms after ten rounds (%d)" % c.squadrons_launched)
	b.end_turn()
	var eleventh: Dictionary = b.use_ability(c.id)
	ok(not bool(eleventh["ok"]), "the eleventh swarm is refused: %s" % String(eleventh.get("reason", "")))
	ok(int(c.squadrons_launched) == 10, "the counter stays at ten")
	var total: int = 0
	for s in b.alive_ships(0):
		if s.ship_class == "interceptor":
			total += 1
	ok(total >= 10, "ten interceptor units exist (%d including any starting ones)" % total)

	# Exhaustion is permanent: more rounds change nothing.
	for round_index in range(3):
		b.end_turn()
		_move_swarms_away(b, c)
		b.use_ability(c.id)
	ok(int(c.squadrons_launched) == 10, "three more rounds do not revive the ability")
	ok(total == _count_class(b, 0, "interceptor"), "no extra swarm appeared afterwards")


func test_spawn_is_legal() -> void:
	var b = _battle(["carrier"])
	var c = _carrier(b)
	for round_index in range(6):
		b.end_turn()
		var res: Dictionary = b.use_ability(c.id)
		if not bool(res["ok"]):
			continue
		var cell: Vector2i = res["cell"]
		ok(b.map.in_bounds(cell), "spawn %d is inside the board" % round_index)
		var occupant = b.ship_at(cell)
		ok(occupant != null and occupant.id == int(res["spawn"]), "spawn %d is the new unit" % round_index)
		var overlaps: int = 0
		for other in b.ships:
			if other.id == occupant.id:
				continue
			for oc in other.cells():
				if oc == cell:
					overlaps += 1
		ok(overlaps == 0, "spawn %d does not overlap another hull" % round_index)


func test_blocked_spawn_consumes_nothing() -> void:
	var b = _battle(["carrier"])
	var c = _carrier(b)
	# Seal the Carrier: occupy every free cell around it with fighters of its own fleet.
	var filled: int = 0
	for radius in range(1, 4):
		for x in range(c.cell.x - radius, c.cell.x + radius + 1):
			for y in range(c.cell.y - radius, c.cell.y + radius + 1):
				var cell := Vector2i(x, y)
				if maxi(absi(cell.x - c.cell.x), absi(cell.y - c.cell.y)) != radius:
					continue
				if b.placement_problem(cell, Vector2i(1, 1), 0, -1) != "":
					continue
				var filler = preload("res://scripts/core/ship.gd").create("fighter", 0, 500 + filled, 0, {}, 1.0)
				filler.placed = true
				filler.cell = cell
				b._add_ship(filler)
				filled += 1
		if filled > 0:
			break
	ok(filled > 0, "the test managed to surround the Carrier (%d hulls)" % filled)
	var counter_before: int = c.squadrons_launched
	var check: Dictionary = b.can_use_ability(c.id)
	ok(not bool(check["ok"]), "a surrounded Carrier cannot launch: %s" % String(check.get("reason", "")))
	var res: Dictionary = b.use_ability(c.id)
	ok(not bool(res["ok"]), "and the call is refused")
	ok(int(c.squadrons_launched) == counter_before, "no launch was consumed by the failure")
	ok(c.ability_ready, "the ability is still ready for a later round")


func test_destroyed_carrier_cannot_launch() -> void:
	var b = _battle(["carrier"])
	var c = _carrier(b)
	c.hull = 0.0
	c.alive = false
	var res: Dictionary = b.use_ability(c.id)
	ok(not bool(res["ok"]), "a destroyed Carrier cannot launch: %s" % String(res.get("reason", "")))
	ok(int(c.squadrons_launched) == 0, "and its counter is untouched")


func test_determinism() -> void:
	var a = _battle(["carrier"], ["fighter"], 777)
	var b = _battle(["carrier"], ["fighter"], 777)
	var ca = _carrier(a)
	var cb = _carrier(b)
	var same: bool = true
	for i in range(5):
		a.end_turn()
		b.end_turn()
		var ra: Dictionary = a.use_ability(ca.id)
		var rb: Dictionary = b.use_ability(cb.id)
		if bool(ra["ok"]) != bool(rb["ok"]) or ra.get("cell") != rb.get("cell"):
			same = false
	ok(same, "the same seed produces the same spawns")


func test_snapshot_round_trip() -> void:
	var b = _battle(["carrier"])
	var c = _carrier(b)
	b.end_turn()
	b.use_ability(c.id)
	b.end_turn()
	b.use_ability(c.id)
	var data: Dictionary = SaveRef.snapshot(b)
	var loaded: Dictionary = SaveRef.restore(data)
	ok(bool(loaded.get("ok", false)), "the battle snapshot loads: %s" % String(loaded.get("reason", "")))
	var restored = loaded.get("battle", null)
	if restored == null:
		return
	var c2 = null
	for s in restored.alive_ships(0):
		if s.ship_class == "carrier":
			c2 = s
	ok(c2 != null, "the Carrier is in the snapshot")
	ok(c2 != null and int(c2.squadrons_launched) == 2,
		"the launch counter survives the snapshot (%s)" % str(c2.squadrons_launched if c2 else -1))
	if c2 != null:
		restored.end_turn()
		var res: Dictionary = restored.use_ability(c2.id)
		ok(bool(res["ok"]), "the resumed battle still launches")
		ok(int(c2.squadrons_launched) == 3, "the counter continues from where it was")


func _move_swarms_away(b, carrier) -> void:
	## Puts every interceptor out of the Carrier's ring, so the next launch has somewhere
	## to go. It is the test standing in for the player moving the swarm.
	var dest_y: int = 0
	for s in b.alive_ships(0):
		if s.ship_class != "interceptor":
			continue
		if maxi(absi(s.cell.x - carrier.cell.x), absi(s.cell.y - carrier.cell.y)) > 1:
			continue
		var spot := Vector2i(-1, -1)
		for y in range(b.map.height - 1, -1, -1):
			for x in range(0, 4):
				if b.placement_problem(Vector2i(x, y), Vector2i(1, 1), 0, s.id) == "":
					spot = Vector2i(x, y)
					break
			if spot.x >= 0:
				break
		if spot.x >= 0:
			s.cell = spot
		dest_y += 1


func _count_class(b, team: int, class_id: String) -> int:
	var n: int = 0
	for s in b.alive_ships(team):
		if s.ship_class == class_id:
			n += 1
	return n


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
