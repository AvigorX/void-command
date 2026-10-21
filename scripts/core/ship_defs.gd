class_name ShipDefs
extends RefCounted
## Data-driven ship catalogue. Adding a class only requires a new entry here.
##
## Gameplay dimensions live in `footprint` (Vector2i, columns x rows). Every class
## is 1x1 today; multi-cell hulls stay inactive until a later milestone.
## `hull_box` is legacy, unreferenced data: nothing reads it and it is NOT the
## gameplay dimension - do not use it to infer size.

const ORDER: Array[String] = ["interceptor", "fighter", "destroyer", "frigate", "cruiser",
	"carrier", "battleship", "dreadnought"]


## ---------------------------------------------------------------------------
## CANONICAL CLASS CATALOGUE (STEP 3)
## ---------------------------------------------------------------------------
## `DEFS` above is what the game can actually build: four playable classes with full
## statistics. `CATALOG` is the canonical table the roadmap talks about, and it also
## contains classes that are only NAMED there. The distinction is the whole point:
##
##   defined      -> there is a catalogue entry (all eight)
##   implemented  -> `DEFS` has full statistics and the mechanics exist
##   available    -> it may appear in fleet composition
##   deployable   -> its footprint is confirmed and the deployment supports it
##   active       -> it is authorised in the current game mode
##
## A class whose footprint is not confirmed can never be available, and a class that is
## not implemented can never be deployable. Those two rules are asserted in the tests.
##
## Costs are the initial, explicitly provisional values from the roadmap. A cost never
## implies a footprint, a statistic or availability.

const CATALOG: Dictionary = {
	"interceptor": {
		"label": "INTERCEPTOR", "role": "Recon and mobility", "cost": 2,
		"footprint": Vector2i(1, 1), "footprint_status": "confirmed",
		"implemented": true, "available": true, "deployable": true, "active": true,
		"cap": 0,
	},
	"fighter": {
		"label": "FIGHTER", "role": "Fast flanker", "cost": 3,
		"footprint": Vector2i(1, 1), "footprint_status": "confirmed",
		"cap": 0,
		"implemented": true, "available": true, "deployable": true, "active": true,
	},
	"destroyer": {
		"label": "DESTROYER", "role": "Escort and strike", "cost": 5,
		# M6: single 1x1 hull, drawn as one ship. It was 1x2; the mandate replaced the
		# geometry, so the renderer had to stop drawing a two-cell silhouette.
		"footprint": Vector2i(1, 1), "footprint_status": "confirmed",
		"implemented": true, "available": true, "deployable": true, "active": true,
		"cap": 0,
	},
	"frigate": {
		"label": "FRIGATE", "role": "Balanced escort", "cost": 6,
		# M6: back to a single 1x1 hull. The M3 mandate had confirmed 1x2; M6 replaces that
		# decision, so the catalogue, the renderer and every test follow this value.
		"footprint": Vector2i(1, 1), "footprint_status": "confirmed",
		"cap": 0,
		"implemented": true, "available": true, "deployable": true, "active": true,
	},
	"cruiser": {
		"label": "CRUISER", "role": "Durable line ship", "cost": 9,
		"footprint": Vector2i(1, 3), "footprint_status": "confirmed",
		"cap": 0,
		"implemented": true, "available": true, "deployable": true, "active": true,
	},
	"carrier": {
		"label": "CARRIER", "role": "Support and control", "cost": 11,
		# 1x5 CONFIRMED in M4. Shares the length with the Dreadnought on purpose: the
		# difference is role, statistics and silhouette, not geometry.
		"footprint": Vector2i(1, 5), "footprint_status": "confirmed",
		"implemented": true, "available": true, "deployable": true, "active": true,
		# M6: one Carrier per fleet. It carries the interceptor production ability, so a
		# second one would double a per-battle resource the design budgets once.
		"cap": 1,
	},
	"battleship": {
		"label": "BATTLESHIP", "role": "Heavy weapons platform", "cost": 14,
		"footprint": Vector2i(1, 4), "footprint_status": "confirmed",
		"implemented": true, "available": true, "deployable": true, "active": true,
		"cap": 2,
	},
	"dreadnought": {
		"label": "DREADNOUGHT", "role": "Dominant capital unit", "cost": 18,
		"footprint": Vector2i(1, 5), "footprint_status": "confirmed",
		"implemented": true, "available": true, "deployable": true, "active": true,
		"cap": 1,
	},
}

const CATALOG_ORDER: Array[String] = [
	"interceptor", "fighter", "destroyer", "frigate", "cruiser", "carrier",
	"battleship", "dreadnought",
]

## Ability kinds the combat layer implements. A catalogue entry may not reference one.
const ABILITY_KINDS: Array[String] = ["evade", "precision", "shield", "salvo", "launch"]

## Footprints the geometry contract allows: one cell wide, or a single cell.
const MAX_HULL_LENGTH: int = 5


static func catalog_entry(class_id: String) -> Dictionary:
	return CATALOG.get(class_id, {})


static func catalog_ids() -> Array[String]:
	return CATALOG_ORDER.duplicate()


static func cost(class_id: String) -> int:
	return int(CATALOG.get(class_id, {}).get("cost", -1))


static func cap_of(class_id: String) -> int:
	## Per-class fleet cap. 0 (or a missing entry) means NO numeric cap: the budget, the
	## caps of other classes and deployability are the real limits. There is deliberately
	## no fleet-wide hull cap any more - M4 removed it.
	return int(CATALOG.get(class_id, {}).get("cap", 0))


static func is_implemented(class_id: String) -> bool:
	return bool(CATALOG.get(class_id, {}).get("implemented", false))


static func is_available(class_id: String) -> bool:
	return bool(CATALOG.get(class_id, {}).get("available", false))


static func is_deployable(class_id: String) -> bool:
	return bool(CATALOG.get(class_id, {}).get("deployable", false))


static func available_classes() -> Array[String]:
	## Classes the fleet builder may offer: implemented, footprint confirmed, active.
	var out: Array[String] = []
	for id in CATALOG_ORDER:
		var e: Dictionary = CATALOG[id]
		if bool(e.get("available", false)) and bool(e.get("implemented", false)) 				and String(e.get("footprint_status", "")) == "confirmed":
			out.append(id)
	return out


static func validate_catalog() -> Array[String]:
	## Structural validation of the catalogue. Returns human-readable problems; an empty
	## array means the table is coherent.
	var problems: Array[String] = []
	for id in CATALOG_ORDER:
		if not CATALOG.has(id):
			problems.append("%s is listed in CATALOG_ORDER but has no entry." % id)
			continue
		problems.append_array(entry_problems(id, CATALOG[id]))
	return problems


static func entry_problems(class_id: String, e: Dictionary) -> Array[String]:
	## The per-entry rules, exposed so the tests can feed DELIBERATELY BROKEN entries and
	## prove the validator rejects them. A validator that is only ever shown a valid table
	## is not evidence: it may be returning [] for the wrong reason.
	var id: String = class_id
	var problems: Array[String] = []
	if true:
		var cost_value: int = int(e.get("cost", -1))
		if cost_value < 0:
			problems.append("%s has a negative or missing cost." % id)
		if int(e.get("cap", 0)) < 0:
			problems.append("%s declares a negative fleet cap." % id)
		if int(e.get("cap", 0)) > 0 and not bool(e.get("implemented", false)):
			problems.append("%s has a fleet cap but is not implemented." % id)
		if String(e.get("label", "")) == "":
			problems.append("%s has no display label." % id)
		var status: String = String(e.get("footprint_status", ""))
		if not (status in ["confirmed", "proposed", "unresolved"]):
			problems.append("%s has an unknown footprint_status '%s'." % [id, status])
		var fp: Variant = e.get("footprint", null)
		if status == "confirmed":
			if typeof(fp) != TYPE_VECTOR2I:
				problems.append("%s is confirmed but declares no footprint." % id)
			else:
				var v: Vector2i = fp
				if mini(v.x, v.y) != 1:
					problems.append("%s declares a %dx%d footprint: capital hulls must be one cell wide." % [id, v.x, v.y])
				if maxi(v.x, v.y) > MAX_HULL_LENGTH:
					problems.append("%s is longer than %d cells." % [id, MAX_HULL_LENGTH])
		if bool(e.get("implemented", false)):
			if not DEFS.has(id):
				problems.append("%s claims to be implemented but has no statistics in DEFS." % id)
			else:
				if typeof(fp) == TYPE_VECTOR2I and Vector2i(DEFS[id]["footprint"]) != Vector2i(fp):
					problems.append("%s catalogue footprint %s disagrees with the shipped %s." % [id, str(fp), str(DEFS[id]["footprint"])])
				var ability_kind: String = String((DEFS[id]["ability"] as Dictionary).get("kind", ""))
				if not (ability_kind in ABILITY_KINDS):
					problems.append("%s references an unknown ability kind '%s'." % [id, ability_kind])
		else:
			if bool(e.get("available", false)):
				problems.append("%s is not implemented but is marked available." % id)
			if bool(e.get("deployable", false)):
				problems.append("%s is not implemented but is marked deployable." % id)
		if status != "confirmed" and bool(e.get("deployable", false)):
			problems.append("%s has an unconfirmed footprint but is marked deployable." % id)
	return problems


static func has_class(class_id: String) -> bool:
	## True when the catalogue defines this class. Used by the battle snapshot to
	## refuse a save that references a class the build no longer knows.
	return DEFS.has(class_id)

const DEFS: Dictionary = {
	"fighter": {
		"label": "FIGHTER",
		"role": "Fast flanker",
		"hull": 38.0,
		"shield": 12.0,
		"move": 6,
		"damage": 11.0,
		"range": 2,
		"armor": 0.0,
		"threat": 1.3,
		"hull_box": 0,
		"footprint": Vector2i(1, 1),
		"ability": {
			"name": "EVASIVE BURN",
			"kind": "evade",
			"cooldown": 2,
			"power": 3.0,
			"desc": "+3 move now, incoming damage halved until next round.",
		},
	},
	"frigate": {
		"label": "FRIGATE",
		"role": "Balanced escort",
		"hull": 64.0,
		"shield": 26.0,
		"move": 4,
		"damage": 15.0,
		"range": 3,
		"armor": 1.0,
		"threat": 1.6,
		"hull_box": 1,
		"footprint": Vector2i(1, 1),
		"ability": {
			"name": "PRECISION STRIKE",
			"kind": "precision",
			"cooldown": 2,
			"power": 8.0,
			"desc": "+8 damage, ignores armor, +1 range. Consumes attack.",
		},
	},
	"cruiser": {
		"label": "CRUISER",
		"role": "Durable line ship",
		"hull": 104.0,
		"shield": 44.0,
		"move": 3,
		"damage": 20.0,
		"range": 4,
		"armor": 3.0,
		"threat": 2.2,
		"hull_box": 2,
		# STEP 2 re-spec: capital hulls develop in LENGTH, one cell wide.
		"footprint": Vector2i(1, 3),
		"ability": {
			"name": "SHIELD SURGE",
			"kind": "shield",
			"cooldown": 3,
			"power": 26.0,
			"desc": "+26 shield to self or an ally within 3 cells.",
		},
	},
	"battleship": {
		"label": "BATTLESHIP",
		"role": "Heavy weapons platform",
		"hull": 160.0,
		"shield": 58.0,
		"move": 2,
		"damage": 32.0,
		"range": 6,
		"armor": 5.0,
		"threat": 3.0,
		"hull_box": 3,
		# STEP 2 re-spec: 1x4 (4x1 after a 90/270 turn). The old 2x3 was two cells
		# wide, which the geometry contract no longer allows: a capital hull must be
		# one cell wide and develop along its length.
		"footprint": Vector2i(1, 4),
		"ability": {
			"name": "HEAVY SALVO",
			"kind": "salvo",
			"cooldown": 3,
			"power": 26.0,
			"desc": "26 damage to target, 13 to every ship adjacent to it.",
		},
	},
	"interceptor": {
		"label": "INTERCEPTOR",
		"role": "Recon and mobility",
		"hull": 26.0,
		"shield": 8.0,
		"move": 7,
		"damage": 8.0,
		"range": 2,
		"armor": 0.0,
		"threat": 0.6,
		"hull_box": 0,
		"footprint": Vector2i(1, 1),
		"ability": {
			"name": "AFTERBURNER",
			"kind": "evade",
			"cooldown": 2,
			"power": 2.0,
			"desc": "+2 move now, incoming damage halved until next round.",
		},
	},
	"destroyer": {
		"label": "DESTROYER",
		"role": "Escort and strike",
		"hull": 52.0,
		"shield": 18.0,
		"move": 5,
		"damage": 13.0,
		"range": 3,
		"armor": 1.0,
		"threat": 1.4,
		"hull_box": 1,
		"footprint": Vector2i(1, 1),
		"ability": {
			"name": "TORPEDO SPREAD",
			"kind": "salvo",
			"cooldown": 3,
			"power": 9.0,
			"desc": "9 damage to target, 4 to every ship adjacent to it.",
		},
	},
	"carrier": {
		"label": "CARRIER",
		"role": "Support and control",
		"hull": 118.0,
		"shield": 52.0,
		"move": 2,
		"damage": 16.0,
		"range": 5,
		"armor": 3.0,
		"threat": 2.0,
		"hull_box": 4,
		"footprint": Vector2i(1, 5),
		"ability": {
			"name": "LAUNCH SQUADRON",
			"kind": "launch",
			"cooldown": 0,
			"power": 1.0,
			"limit": 10,
			"desc": "Deploys one Interceptor swarm next to the hull, once per round, up to 10 per battle.",
		},
	},
	"dreadnought": {
		"label": "DREADNOUGHT",
		"role": "Dominant capital unit",
		"hull": 210.0,
		"shield": 78.0,
		"move": 1,
		"damage": 40.0,
		"range": 6,
		"armor": 7.0,
		"threat": 3.8,
		"hull_box": 4,
		"footprint": Vector2i(1, 5),
		"ability": {
			"name": "ANNIHILATION BROADSIDE",
			"kind": "salvo",
			"cooldown": 4,
			"power": 34.0,
			"desc": "34 damage to target, 17 to every ship adjacent to it.",
		},
	},
}

const TEAM_COLORS: Array[Color] = [
	Color(0.30, 0.72, 0.95, 1.0),
	Color(0.95, 0.45, 0.32, 1.0),
]
const TEAM_TRIM: Array[Color] = [
	Color(0.55, 0.98, 1.0, 1.0),
	Color(1.0, 0.72, 0.34, 1.0),
]
const TEAM_DARK: Array[Color] = [
	Color(0.10, 0.26, 0.36, 1.0),
	Color(0.34, 0.14, 0.14, 1.0),
]

const NAME_PARTS_A: Array[String] = [
	"AEGIS", "TALON", "VESPER", "ORION", "HALCYON", "KESTREL",
	"NOMAD", "SABLE", "VIGIL", "ZEPHYR", "ONYX", "RAPIER",
	"CASTOR", "DRIFT", "EMBER", "FARADAY",
]
const NAME_PARTS_B: Array[String] = [
	"PRIME", "II", "VII", "WARDEN", "SPEAR", "RELAY", "MARK", "NOVA",
]


static func def(class_id: String) -> Dictionary:
	return DEFS.get(class_id, DEFS["fighter"])


static func label(class_id: String) -> String:
	return String(def(class_id)["label"])


static func ability(class_id: String) -> Dictionary:
	return def(class_id)["ability"]


static func ship_name(class_id: String, index: int, team: int) -> String:
	var a: String = NAME_PARTS_A[(index * 3 + team * 5) % NAME_PARTS_A.size()]
	var b: String = NAME_PARTS_B[(index * 2 + team) % NAME_PARTS_B.size()]
	var prefix := "VCV" if team == 0 else "HKS"
	return "%s %s %s" % [prefix, a, b]
