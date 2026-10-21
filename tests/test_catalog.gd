extends SceneTree
## STEP 3 / Block C — the canonical class catalogue.
##
## What is being pinned: eight classes are DEFINED, four are IMPLEMENTED, four are not,
## and the gap between those words is structural rather than aspirational. A class with an
## unresolved footprint cannot be available, and a class that is not implemented cannot be
## deployable - regardless of how attractive its cost is.
##
## The validator is also fed DELIBERATELY BROKEN entries: a table that is only ever shown
## valid rows proves nothing.

const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const ShipRef = preload("res://scripts/core/ship.gd")

const EXPECTED_COSTS: Dictionary = {
	"interceptor": 2, "fighter": 3, "destroyer": 5, "frigate": 6,
	"cruiser": 9, "carrier": 11, "battleship": 14, "dreadnought": 18,
}

var checks: int = 0
var failures: int = 0
var current: String = ""


func _initialize() -> void:
	print("=== VOID COMMAND — CLASS CATALOGUE SUITE (STEP 3) ===")
	test_catalog_shape()
	test_states()
	test_footprints()
	test_costs_and_abilities()
	test_validator_is_falsifiable()
	test_shipped_surface()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  [%s] %s" % [current, label])


func begin(name: String) -> void:
	current = name
	print("- %s" % name)


# ---------------------------------------------------------------- shape ----

func test_catalog_shape() -> void:
	begin("catalogue shape")
	var ids: Array[String] = ShipDefsRef.catalog_ids()
	ok(ids.size() == 8, "eight classes are defined (got %d)" % ids.size())
	ok(ids == ["interceptor", "fighter", "destroyer", "frigate", "cruiser", "carrier",
		"battleship", "dreadnought"], "the catalogue keeps the canonical order")
	for id in ids:
		var e: Dictionary = ShipDefsRef.catalog_entry(id)
		ok(not e.is_empty(), "%s has an entry" % id)
		ok(String(e.get("label", "")) != "", "%s has a display label" % id)
		ok(String(e.get("role", "")) != "", "%s has a tactical role" % id)
		ok(String(e.get("label", "")) == String(e.get("label", "")).to_upper(),
			"%s label is upper case, like the rest of the UI" % id)
	var labels: Dictionary = {}
	for id2 in ids:
		var label: String = String(ShipDefsRef.catalog_entry(id2).get("label", ""))
		ok(not labels.has(label), "%s label '%s' is unique" % [id2, label])
		labels[label] = true
	ok(ShipDefsRef.catalog_entry("nonsense").is_empty(), "an unknown class has no entry")


func test_states() -> void:
	begin("defined vs implemented vs available")
	var implemented: Array[String] = []
	for id in ShipDefsRef.catalog_ids():
		if ShipDefsRef.is_implemented(id):
			implemented.append(id)
	ok(implemented.size() == 8, "all eight classes are implemented (got %d)" % implemented.size())
	ok(implemented == ["interceptor", "fighter", "destroyer", "frigate", "cruiser", "carrier",
		"battleship", "dreadnought"], "and none is missing from the catalogue")
	ok(ShipDefsRef.DEFS.size() == 8, "DEFS holds statistics for all eight")
	for id2 in ShipDefsRef.catalog_ids():
		ok(ShipDefsRef.is_available(id2), "%s is available for composition" % id2)
		ok(ShipDefsRef.is_deployable(id2), "%s is deployable" % id2)
		ok(bool(ShipDefsRef.catalog_entry(id2).get("active", false)), "%s is active" % id2)
		ok(ShipDefsRef.DEFS.has(id2), "%s has battle statistics" % id2)
		ok(ShipDefsRef.has_class(id2), "Ship.create can build a %s" % id2)
	ok(ShipDefsRef.available_classes().size() == 8, "the composition menu offers all eight")
	# Per-class caps: three classes are limited, five are not.
	ok(ShipDefsRef.cap_of("dreadnought") == 1, "Dreadnought is capped at 1")
	ok(ShipDefsRef.cap_of("battleship") == 2, "Battleship is capped at 2")
	# M6 lowered the Carrier cap from 2 to 1: it owns the interceptor production ability,
	# and the design budgets that resource once per fleet.
	ok(ShipDefsRef.cap_of("carrier") == 1, "Carrier is capped at 1")
	for id3 in ["interceptor", "fighter", "destroyer", "frigate", "cruiser"]:
		ok(ShipDefsRef.cap_of(id3) == 0, "%s has no numeric cap (got %d)" % [id3, ShipDefsRef.cap_of(id3)])
	ok(ShipDefsRef.cap_of("nonsense") == 0, "an unknown class has no cap either")


func test_footprints() -> void:
	begin("footprints")
	for id in ShipDefsRef.catalog_ids():
		var e: Dictionary = ShipDefsRef.catalog_entry(id)
		var status: String = String(e.get("footprint_status", ""))
		ok(status in ["confirmed", "proposed", "unresolved"], "%s has a known status" % id)
		var fp: Variant = e.get("footprint", null)
		if status == "confirmed":
			ok(typeof(fp) == TYPE_VECTOR2I, "%s declares a footprint" % id)
			var v: Vector2i = fp
			ok(mini(v.x, v.y) == 1, "%s is one cell wide (%dx%d)" % [id, v.x, v.y])
			ok(maxi(v.x, v.y) <= ShipDefsRef.MAX_HULL_LENGTH, "%s is at most %d long" % [id, ShipDefsRef.MAX_HULL_LENGTH])
			ok(v != Vector2i(2, 2) and v != Vector2i(2, 3) and v != Vector2i(2, 4),
				"%s is not a forbidden 2-wide capital footprint" % id)
			ok(FootprintRef.cells(Vector2i.ZERO, v, 0).size() == v.x * v.y,
				"%s enumerates %d cells" % [id, v.x * v.y])
		else:
			# A "proposed" footprint is data worth keeping; only "unresolved" means there
			# is no candidate at all.
			if status == "unresolved":
				ok(fp == null, "%s claims no footprint while unresolved" % id)
			else:
				ok(typeof(fp) == TYPE_VECTOR2I, "%s keeps its proposed footprint as data" % id)
	# The per-class reading the mandate asks for.
	ok(Vector2i(ShipDefsRef.catalog_entry("fighter")["footprint"]) == Vector2i(1, 1), "Fighter is 1x1")
	ok(Vector2i(ShipDefsRef.catalog_entry("cruiser")["footprint"]) == Vector2i(1, 3), "Cruiser is 1x3")
	ok(Vector2i(ShipDefsRef.catalog_entry("battleship")["footprint"]) == Vector2i(1, 4), "Battleship is 1x4")
	# Frigate: CONFIRMED as 1x2 in M3. It shipped as 1x1 through STEP 2; the proposal is
	# now the geometry, so it must not linger as a second, competing field.
	var frig: Dictionary = ShipDefsRef.catalog_entry("frigate")
	# M6 replaced the M3 geometry: Frigate is a single 1x1 hull again.
	ok(Vector2i(frig["footprint"]) == Vector2i(1, 1), "Frigate ships as 1x1")
	ok(String(frig["footprint_status"]) == "confirmed", "and it is the confirmed geometry")
	ok(not frig.has("proposed_footprint"), "the adopted proposal is not kept as a parallel field")
	ok(Vector2i(ShipDefsRef.catalog_entry("destroyer")["footprint"]) == Vector2i(1, 1),
		"Destroyer ships as 1x1 (M6 geometry)")
	ok(String(ShipDefsRef.catalog_entry("destroyer")["footprint_status"]) == "confirmed",
		"and it is the confirmed geometry")
	ok(Vector2i(ShipDefsRef.catalog_entry("interceptor")["footprint"]) == Vector2i(1, 1), "Interceptor is 1x1")
	ok(String(ShipDefsRef.catalog_entry("carrier")["footprint_status"]) == "confirmed",
		"Carrier footprint is confirmed (1x5, M4)")
	ok(Vector2i(ShipDefsRef.catalog_entry("carrier")["footprint"]) == Vector2i(1, 5), "Carrier is 1x5")
	ok(String(ShipDefsRef.catalog_entry("dreadnought")["footprint_status"]) == "confirmed",
		"Dreadnought footprint is confirmed (1x5, M4)")
	ok(Vector2i(ShipDefsRef.catalog_entry("dreadnought")["footprint"]) == Vector2i(1, 5), "Dreadnought is 1x5")
	# No shipped class may disagree with its own catalogue footprint.
	for id2 in ShipDefsRef.DEFS.keys():
		ok(Vector2i(ShipDefsRef.DEFS[id2]["footprint"]) == Vector2i(ShipDefsRef.catalog_entry(id2)["footprint"]),
			"%s catalogue footprint matches the shipped one" % id2)
	var problems: Array[String] = ShipDefsRef.validate_catalog()
	ok(problems.is_empty(), "the whole table validates cleanly (%s)" % str(problems))


func test_costs_and_abilities() -> void:
	begin("costs and abilities")
	for id in ShipDefsRef.catalog_ids():
		ok(ShipDefsRef.cost(id) == int(EXPECTED_COSTS[id]),
			"%s costs %d" % [id, int(EXPECTED_COSTS[id])])
	for id2 in ShipDefsRef.DEFS.keys():
		var kind: String = String((ShipDefsRef.DEFS[id2]["ability"] as Dictionary).get("kind", ""))
		ok(kind in ShipDefsRef.ABILITY_KINDS, "%s references a real ability kind (%s)" % [id2, kind])
	for id3 in ["carrier", "dreadnought", "destroyer", "interceptor"]:
		ok(ShipDefsRef.cost(id3) > 0, "%s has a cost (%d)" % [id3, ShipDefsRef.cost(id3)])
		ok(ShipDefsRef.DEFS.has(id3), "and real statistics to justify it")
	ok(ShipDefsRef.cost("nonsense") == -1, "an unknown class has no cost")


func test_validator_is_falsifiable() -> void:
	begin("the validator rejects broken entries")
	var two_wide: Array[String] = ShipDefsRef.entry_problems("x", {
		"label": "X", "cost": 9, "footprint": Vector2i(2, 3), "footprint_status": "confirmed",
		"implemented": false, "available": false, "deployable": false})
	ok(not two_wide.is_empty(), "a confirmed 2x3 footprint is rejected")
	ok(String(two_wide[0]).find("one cell wide") != -1, "and the reason names the rule")
	var negative: Array[String] = ShipDefsRef.entry_problems("x", {
		"label": "", "cost": -1, "footprint": null, "footprint_status": "weird",
		"implemented": false, "available": false, "deployable": false})
	ok(negative.size() >= 3, "a negative cost, a missing label and an unknown status are all reported")
	var phantom: Array[String] = ShipDefsRef.entry_problems("carrier", {
		"label": "CARRIER", "cost": 11, "footprint": null, "footprint_status": "unresolved",
		"implemented": false, "available": true, "deployable": true})
	ok(phantom.size() >= 2, "an unimplemented, available, deployable class is rejected twice over")
	var mismatch: Array[String] = ShipDefsRef.entry_problems("cruiser", {
		"label": "CRUISER", "cost": 9, "footprint": Vector2i(1, 2), "footprint_status": "confirmed",
		"implemented": true, "available": true, "deployable": true})
	ok(not mismatch.is_empty(), "a catalogue footprint that disagrees with DEFS is rejected")
	var too_long: Array[String] = ShipDefsRef.entry_problems("x", {
		"label": "X", "cost": 9, "footprint": Vector2i(1, 6), "footprint_status": "confirmed",
		"implemented": false, "available": false, "deployable": false})
	ok(not too_long.is_empty(), "a 1x6 hull exceeds the allowed length and is rejected")


func test_shipped_surface() -> void:
	begin("the battle layer agrees")
	var s = ShipRef.create("fighter", 0, 0, 0, {}, 1.0)
	ok(s != null and s.footprint == Vector2i(1, 1), "a Fighter builds with a 1x1 footprint")
	ok(s != null and s.ship_class == "fighter", "and keeps its class id")
	var c = ShipRef.create("carrier", 0, 1, 1, {}, 1.0)
	ok(c != null and c.footprint == Vector2i(1, 5), "a Carrier builds with a 1x5 footprint")
	ok(ShipRef.create("nonsense", 0, 1, 1, {}, 1.0) == null,
		"an unknown class is still refused explicitly - no silent Fighter fallback")
	for id in ShipDefsRef.available_classes():
		var built = ShipRef.create(id, 0, 2, 2, {}, 1.0)
		ok(built != null, "every available class builds (%s)" % id)
		ok(built != null and built.footprint == Vector2i(ShipDefsRef.catalog_entry(id)["footprint"]),
			"%s builds at its catalogue footprint" % id)
