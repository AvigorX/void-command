class_name FleetPoints
extends RefCounted
## Fleet Point System (STEP 3): budgets, composition rules, validation, enemy generation.
##
## SEPARATION OF CONCERNS - the point of this file:
##   * fleet points are NOT credits. Credits are persistent meta-progression in
##     `save_data.gd`; points are spent when composing a single battle and are never
##     earned, bought, saved or converted.
##   * this layer owns the RULES of composition. The UI may disable a button, but every
##     rule here is enforced by the core, so calling the API directly cannot produce a
##     fleet the game would refuse.
##   * a fleet that is valid against the budget is not automatically deployable on a
##     given battlefield. Those are two different verdicts and the API keeps them apart.

const BUDGETS: Dictionary = {
	"skirmish": 60,
	"standard": 100,
	"fleet_engagement": 150,
	"grand_fleet": 200,
}
const BUDGET_ORDER: Array[String] = ["skirmish", "standard", "fleet_engagement", "grand_fleet"]
const DEFAULT_MODE: String = "standard"

## There is NO fleet-wide hull cap. M4 removed the old MAX_SHIPS = 8: a 100 FP budget must
## not be forced to buy at most eight ships. What limits a fleet is the budget, the per-class
## caps below and whether the chosen battlefield can actually hold it.
##
## The per-class caps live in ShipDefs.CATALOG ("cap"), not here: one source of truth, and
## the catalogue validator rejects a cap on a class that is not implemented. 0 = no cap.
const MIN_SHIPS: int = 1
const GENERATOR_GUARD: int = 400


# ------------------------------------------------------------------ budgets ----

static func mode_ids() -> Array[String]:
	return BUDGET_ORDER.duplicate()


static func budget_of(mode_id: String) -> int:
	return int(BUDGETS.get(mode_id, BUDGETS[DEFAULT_MODE]))


static func mode_label(mode_id: String) -> String:
	return String(mode_id).replace("_", " ").to_upper()


# ------------------------------------------------------------- composition ----

static func cost_of(class_id: String) -> int:
	return ShipDefs.cost(class_id)


static func total_cost(entries: Array) -> int:
	var total: int = 0
	for id in entries:
		total += cost_of(String(id))
	return total


static func count_of(entries: Array, class_id: String) -> int:
	var n: int = 0
	for id in entries:
		if String(id) == class_id:
			n += 1
	return n


static func can_add(entries: Array, class_id: String, budget: int) -> Dictionary:
	## Cheap, UI-friendly verdict: may this hull be appended right now?
	if not ShipDefs.CATALOG.has(class_id):
		return {"ok": false, "reason": "Unknown class '%s'." % class_id}
	var entry: Dictionary = ShipDefs.catalog_entry(class_id)
	if not bool(entry.get("implemented", false)):
		return {"ok": false, "reason": "%s is not implemented." % String(entry.get("label", class_id))}
	if not bool(entry.get("available", false)):
		return {"ok": false, "reason": "%s is not available for composition." % String(entry.get("label", class_id))}
	if String(entry.get("footprint_status", "")) != "confirmed":
		return {"ok": false, "reason": "%s has no confirmed footprint." % String(entry.get("label", class_id))}
	var cap: int = ShipDefs.cap_of(class_id)
	if cap > 0 and count_of(entries, class_id) >= cap:
		return {"ok": false, "reason": "At most %d %s per fleet." % [cap, String(entry.get("label", class_id))]}
	var cost: int = cost_of(class_id)
	if total_cost(entries) + cost > budget:
		return {"ok": false, "reason": "Not enough points (%d left, %d needed)." % [budget - total_cost(entries), cost]}
	return {"ok": true, "reason": ""}


static func validate_structure(entries: Array, budget: int) -> Dictionary:
	## Everything except the battlefield: budget, availability, limits, emptiness.
	var reasons: Array[String] = []
	if entries.size() < MIN_SHIPS:
		reasons.append("The fleet is empty.")
	if budget <= 0:
		reasons.append("Invalid budget.")
	for id in entries:
		var class_id: String = String(id)
		if not ShipDefs.CATALOG.has(class_id):
			reasons.append("Unknown class '%s'." % class_id)
			continue
		var entry: Dictionary = ShipDefs.catalog_entry(class_id)
		if not bool(entry.get("implemented", false)):
			reasons.append("%s is not implemented." % String(entry.get("label", class_id)))
		if not bool(entry.get("available", false)):
			reasons.append("%s is not available." % String(entry.get("label", class_id)))
		if String(entry.get("footprint_status", "")) != "confirmed":
			reasons.append("%s has no confirmed footprint." % String(entry.get("label", class_id)))
	for id2 in ShipDefs.CATALOG_ORDER:
		var cap: int = ShipDefs.cap_of(id2)
		if cap > 0 and count_of(entries, id2) > cap:
			reasons.append("More than %d %s (fleet cap)." % [cap, String(id2).to_upper()])
	var spent: int = total_cost(entries)
	if spent > budget:
		reasons.append("Over budget: %d spent of %d." % [spent, budget])
	return {"ok": reasons.is_empty(), "reasons": reasons, "spent": spent, "remaining": budget - spent}


static func deployable(entries: Array, map_size: Vector2i, seed_value: int = 4242,
		team: int = 0) -> Dictionary:
	## Does the whole fleet fit the chosen battlefield? A trial deployment is the only
	## honest answer: it exercises footprints, orientation, pockets and terrain at once.
	##
	## `team` matters and used to be ignored: the two deployment bands are symmetric in
	## shape but NOT in terrain, so a fleet that fits the player band can fail on the enemy
	## band. The M5 balance matrix found exactly that - a generated enemy fleet that had
	## passed validation failed to deploy in the real battle.
	if entries.is_empty():
		return {"ok": false, "reason": "The fleet is empty."}
	var probe = Battle.new()
	if team == 0:
		probe.setup(seed_value, {}, 1, map_size, entries, ["fighter"])
	else:
		probe.setup(seed_value, {}, 1, map_size, ["fighter"], entries)
	if not probe.deploy_failures.is_empty():
		return {"ok": false, "reason": "Does not fit the battlefield: %s could not be deployed." % str(probe.deploy_failures)}
	var cells: int = 0
	for s in probe.ships:
		if s.team == team:
			cells += s.footprint.x * s.footprint.y
	return {"ok": true, "reason": "", "cells": cells}


static func validate(entries: Array, budget: int, map_size: Vector2i) -> Dictionary:
	## The full verdict a CONFIRM button must obey: structure first, then geometry.
	var structural: Dictionary = validate_structure(entries, budget)
	if not bool(structural["ok"]):
		return {"ok": false, "reasons": structural["reasons"], "spent": structural["spent"], "remaining": structural["remaining"]}
	var geo: Dictionary = deployable(entries, map_size)
	if not bool(geo["ok"]):
		return {"ok": false, "reasons": [String(geo["reason"])], "spent": structural["spent"], "remaining": structural["remaining"]}
	return {"ok": true, "reasons": [], "spent": structural["spent"], "remaining": structural["remaining"]}


# ------------------------------------------------------- enemy composition ----

static func generate_enemy(seed_value: int, budget: int, map_size: Vector2i) -> Dictionary:
	## Deterministic enemy fleet inside the budget and the per-class caps.
	##
	## With the global hull cap gone (M4) a 200 FP budget can buy a LOT of cheap ships, and
	## the naive version - append until the budget runs out, then verify deployment - spent
	## 14 seconds per fleet because every rejected hull cost a full battle setup. Two changes
	## fix that without inventing a hidden cap:
	##
	##  1. the real geometric limit is used as a stop condition: the deployment zone holds a
	##     finite number of cells, so a fleet whose hulls need more cells than the zone has
	##     can never be deployed. Counting cells is free.
	##  2. deployability is verified ONCE at the end; a failure costs at most a few drops,
	##     each logged.
	##
	## Terminates by construction: the loop is bounded by GENERATOR_GUARD, the budget strictly
	## decreases with every pick, and the drop loop is bounded too.
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value * 7919) ^ (budget * 104729) ^ (map_size.x * 31 + map_size.y)
	var pool: Array[String] = ShipDefs.available_classes()
	var entries: Array[String] = []
	var log: Array[String] = []
	if pool.is_empty():
		return {"ok": false, "entries": entries, "spent": 0, "remaining": budget,
			"log": ["No available class."], "capacity": 0}
	var capacity: int = zone_capacity(map_size)
	# A fleet may occupy at most 60% of the zone. Not an arbitrary number: the deployment is
	# a greedy first-fit and the store ships need room to MANOEUVRE, not just to exist - a
	# band packed to 100% leaves a 1x5 hull nowhere to turn and strands the fleet. This is a
	# packing reserve, and it replaces the old global hull cap with geometry.
	var cell_budget: int = int(float(capacity) * 0.60)
	var cells_used: int = 0
	var guard: int = 0
	while guard < GENERATOR_GUARD:
		guard += 1
		var remaining: int = budget - total_cost(entries)
		var options: Array[String] = []
		for id in pool:
			var cap: int = ShipDefs.cap_of(id)
			if cost_of(id) > remaining:
				continue
			if cap > 0 and count_of(entries, id) >= cap:
				continue
			if cells_used + footprint_cells(id) > cell_budget:
				continue
			options.append(id)
		if options.is_empty():
			break
		var pick: String = options[rng.randi_range(0, options.size() - 1)]
		entries.append(pick)
		cells_used += footprint_cells(pick)
		log.append("+ %s (%d) — %d / %d, %d / %d cells" % [
			String(pick).to_upper(), cost_of(pick), total_cost(entries), budget, cells_used, capacity])
	if entries.is_empty():
		for id2 in pool:
			if cost_of(id2) <= budget and footprint_cells(id2) <= cell_budget:
				entries.append(id2)
				log.append("fallback: + %s (%d)" % [String(id2).to_upper(), cost_of(id2)])
				break
	# Largest hulls first. `_deploy()` places the roster in order, so a capital that arrives
	# when the band is already full of fighters is the one that fails - and a 1x5 hull needs
	# five contiguous cells in a four-column band, i.e. it must be placed early. Sorting by
	# footprint is deterministic (ties keep generation order) and removes most drop cycles.
	entries.sort_custom(func(a: String, b: String) -> bool:
		var ca: int = footprint_cells(a)
		var cb: int = footprint_cells(b)
		if ca == cb:
			return false
		return ca > cb)
	# One real deployment check. A drop is logged, never silent.
	var drops: int = 0
	# Team 1: this fleet is generated for the ENEMY band, and that band is not the player's.
	while drops < 4 and entries.size() > 1 and not bool(deployable(entries, map_size, 4242, 1)["ok"]):
		drops += 1
		var dropped: String = entries[entries.size() - 1]
		entries.remove_at(entries.size() - 1)
		log.append("- %s (the battlefield cannot hold the fleet)" % String(dropped).to_upper())
	var spent: int = total_cost(entries)
	# Coarse fallback: if the tail drops were not enough, halve the fleet (bounded), because
	# the enemy band can be much tighter than the player's. Each step costs one trial
	# deployment, so it is rare and capped.
	var shrink: int = 0
	while shrink < 3 and entries.size() > 1 and not bool(deployable(entries, map_size, 4242, 1)["ok"]):
		shrink += 1
		var keep: int = entries.size() / 2
		for i in range(entries.size() - keep):
			var dropped2: String = entries[entries.size() - 1]
			entries.remove_at(entries.size() - 1)
			log.append("- %s (halving: the enemy band cannot hold the fleet)" % String(dropped2).to_upper())
	# Last resort: single-hull drops, until the enemy band takes it. Bounded by the fleet
	# size, and every path that reaches here has already failed the cheap rules.
	while entries.size() > 1 and not bool(deployable(entries, map_size, 4242, 1)["ok"]):
		var dropped3: String = entries[entries.size() - 1]
		entries.remove_at(entries.size() - 1)
		log.append("- %s (the enemy band still cannot hold the fleet)" % String(dropped3).to_upper())
	var fits: bool = entries.is_empty() or bool(deployable(entries, map_size, 4242, 1)["ok"])
	# Trimming changed the roster, so the spend has to be recomputed: a total that does not
	# match the fleet that is actually returned is a lie the caller would believe.
	spent = total_cost(entries)
	return {
		# ok is NOT "not empty": a generated fleet that cannot deploy is not a fleet. The
		# caller must be able to tell, and fall back explicitly.
		"ok": not entries.is_empty() and fits,
		"deployable": fits,
		"entries": entries,
		"spent": spent,
		"remaining": budget - spent,
		"log": log,
		"capacity": capacity,
		"cell_budget": cell_budget,
	}


static func footprint_cells(class_id: String) -> int:
	var fp: Variant = ShipDefs.catalog_entry(class_id).get("footprint", null)
	if typeof(fp) != TYPE_VECTOR2I:
		return 1
	var v: Vector2i = fp
	return v.x * v.y


static func zone_capacity(map_size: Vector2i) -> int:
	## Free deployment cells for team 0 on this board. Terrain and the band width make this
	## the honest upper bound on how many hulls can be fielded, so it replaces the old global
	## hull cap with a geometric fact instead of an arbitrary number.
	var probe = Battle.new()
	probe.setup(1, {}, 1, map_size, ["fighter"], ["fighter"])
	var free_cells: int = 0
	for y in range(probe.map.height):
		for x in range(probe.map.width):
			var c := Vector2i(x, y)
			if probe.map.is_deploy_zone(c, 0) and not probe.map.is_blocked(c):
				free_cells += 1
	return free_cells
