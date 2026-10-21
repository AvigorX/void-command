class_name Ship
extends RefCounted
## Runtime state of one ship. Pure data: no nodes, no drawing, no tree access.

const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")

var id: int = 0
var ship_class: String = "fighter"
var display_name: String = ""
var team: int = 0
var cell: Vector2i = Vector2i.ZERO
var facing: Vector2 = Vector2.RIGHT
## Gameplay dimensions (columns x rows) and the reference corner. `footprint` is
## copied from the class definition at creation time; `cell` is always the
## minimum corner of the footprint (see scripts/core/footprint.gd for the contract).
var footprint: Vector2i = Vector2i.ONE
## Cardinal orientation: 0 = 0 deg, 1 = 90, 2 = 180, 3 = 270 (Footprint.Orientation).
## Runtime-only and deliberately not persisted: the save file holds meta-progression.
var orientation: int = 0
## False while the hull is waiting for a deployment anchor. A ship that has not been
## placed yet must not block cells: before STEP 2.1 every unplaced hull still sat on
## its default cell (0,0), so that corner was silently unusable as a deployment anchor.
var placed: bool = true

var max_hull: float = 0.0
var hull: float = 0.0
var max_shield: float = 0.0
var shield: float = 0.0
var max_move: int = 0
var move_points: int = 0
var base_damage: float = 0.0
var attack_range: int = 0
var armor: float = 0.0
var threat: float = 1.0

var has_attacked: bool = false
var ability_cooldown: int = 0
var ability_ready: bool = true
var alive: bool = true
var evading: bool = false
var kills: int = 0
var damage_dealt: float = 0.0

var ability: Dictionary = {}
## M6: interceptor swarms this hull has launched in this battle. Lives on the ship, so it
## survives turn changes, re-selection and a mid-battle save; it never resets.
var squadrons_launched: int = 0


static func create(class_id: String, p_team: int, p_id: int, index: int, upgrades: Dictionary = {}, hull_scale: float = 1.0) -> Ship:
	# `def()` falls back to the Fighter for an unknown id (historical behaviour), which
	# would turn a request for an unimplemented class into a silent fighter with the wrong
	# name. With a class catalogue in play that has to be an explicit refusal instead.
	if not ShipDefsRef.has_class(class_id):
		push_error("Ship.create: '%s' is not an implemented class." % class_id)
		return null
	var s := Ship.new()
	var d: Dictionary = ShipDefsRef.def(class_id)
	s.id = p_id
	s.ship_class = class_id
	s.team = p_team
	s.display_name = ShipDefsRef.ship_name(class_id, index, p_team)
	s.ability = (d["ability"] as Dictionary).duplicate(true)
	# Gameplay footprint, declared per class. Invalid or missing data must never
	# silently produce a 0-cell or oversized ship: fall back to 1x1.
	var fp_raw: Variant = d.get("footprint", null)
	if typeof(fp_raw) == TYPE_VECTOR2I and FootprintRef.is_valid_size(fp_raw):
		s.footprint = fp_raw
	else:
		if fp_raw != null:
			push_warning("%s declares an invalid footprint (%s); falling back to 1x1." % [class_id, str(fp_raw)])
		s.footprint = Vector2i.ONE
	# M7: a hull is BORN horizontal. Doing it here, not only in the deployment, means every
	# instance - including ones built by tests and probes - follows the same rule.
	s.orientation = initial_orientation(s.footprint)
	var hull_lvl: int = int(upgrades.get("hull", 0))
	var weapon_lvl: int = int(upgrades.get("weapon", 0))
	s.max_hull = float(d["hull"]) * (1.0 + 0.10 * float(hull_lvl)) * hull_scale
	s.max_shield = float(d["shield"]) * (1.0 + 0.10 * float(hull_lvl))
	s.base_damage = float(d["damage"]) * (1.0 + 0.08 * float(weapon_lvl))
	s.max_move = int(d["move"])
	s.attack_range = int(d["range"])
	s.armor = float(d["armor"])
	s.threat = float(d["threat"])
	s.hull = s.max_hull
	s.shield = s.max_shield
	s.move_points = s.max_move
	s.ability_cooldown = 0
	s.facing = Vector2.RIGHT if p_team == 0 else Vector2.LEFT
	return s


func label() -> String:
	return ShipDefsRef.label(ship_class)


func ability_name() -> String:
	return String(ability.get("name", "ABILITY"))


func hull_ratio() -> float:
	if max_hull <= 0.0:
		return 0.0
	return clampf(hull / max_hull, 0.0, 1.0)


func shield_ratio() -> float:
	if max_shield <= 0.0:
		return 0.0
	return clampf(shield / max_shield, 0.0, 1.0)


func is_damaged() -> bool:
	return hull < max_hull * 0.999 or shield < max_shield * 0.999


func cells() -> Array[Vector2i]:
	## Occupied cells in board axes, reference cell first, row-major, deterministic.
	## Pure: reading the footprint never mutates the ship.
	return FootprintRef.cells(cell, footprint, orientation)


func set_orientation(value: int) -> bool:
	## Rejects an invalid orientation and leaves the ship untouched.
	if not FootprintRef.is_valid_orientation(value):
		return false
	orientation = value
	return true


func set_footprint(size: Vector2i) -> bool:
	## Rejects invalid dimensions and leaves the ship untouched. Every shipped class
	## stays 1x1; this exists so tests (and future content) can describe other shapes
	## without editing the catalogue.
	if not FootprintRef.is_valid_size(size):
		return false
	footprint = size
	return true


static func initial_orientation(fp: Vector2i) -> int:
	## M7: every hull is deployed HORIZONTALLY. With `size = (columns, rows)` at 0 degrees,
	## a 1xN hull is vertical at 0 and horizontal at 90, so the rule is expressed once here
	## instead of being re-derived (or guessed from the fleet side) at each call site.
	if fp.x == fp.y:
		return FootprintRef.Orientation.DEG_0
	return FootprintRef.Orientation.DEG_90


func bow_vector() -> Vector2:
	## The direction the silhouette points. THE single source for the drawn bow.
	##
	## A 1x1 hull points wherever `facing` points - exactly the pre-M7B behaviour.
	## A multi-cell hull can only point ALONG its own long axis (a hull is never drawn
	## across its body), so the axis comes from the footprint extent and only the SENSE is
	## taken from `facing`, falling back to the fleet's inward direction: team 0 faces +x,
	## team 1 faces -x. That is what makes the two deployed fleets look at each other
	## instead of both pointing the same way, which is what a bow derived from the
	## orientation alone produced.
	var e: Vector2i = FootprintRef.extent(footprint, orientation)
	if e == Vector2i.ONE:
		return facing if facing != Vector2.ZERO else Vector2.RIGHT
	if e.x >= e.y:
		if facing.x > 0.01:
			return Vector2.RIGHT
		if facing.x < -0.01:
			return Vector2.LEFT
		return Vector2.RIGHT if team == 0 else Vector2.LEFT
	if facing.y > 0.01:
		return Vector2.DOWN
	return Vector2.UP


func bow_angle() -> float:
	## Atlas angle in radians, ready for `draw_set_transform`.
	return bow_vector().angle()


func begin_round() -> void:
	if not alive:
		return
	move_points = max_move
	has_attacked = false
	evading = false
	if ability_cooldown > 0:
		ability_cooldown -= 1
	ability_ready = ability_cooldown <= 0
	var regen: float = maxf(3.0, max_shield * 0.12)
	shield = minf(max_shield, shield + regen)


func can_move() -> bool:
	return alive and move_points > 0


func can_attack() -> bool:
	return alive and not has_attacked


const ACTION_READY: int = 0
const ACTION_PARTIAL: int = 1
const ACTION_DONE: int = 2


func action_state() -> int:
	## Whether this hull can still do something THIS round. Derived on every call from the
	## authoritative fields (`move_points`, `has_attacked`), never stored: a cached flag
	## would sooner or later disagree with the engine, which is exactly what the HUD
	## indicator must not do. A destroyed hull reports DONE - the renderer draws it as
	## wreckage, so the two states are never confused on screen.
	if not alive:
		return ACTION_DONE
	var move: bool = move_points > 0
	var fire: bool = not has_attacked
	if move and fire:
		return ACTION_READY
	if move or fire:
		return ACTION_PARTIAL
	return ACTION_DONE


func take_damage(amount: float, ignore_armor: bool = false) -> Dictionary:
	## Damage lands on shields first, then on hull reduced by armor.
	var result := {"shield": 0.0, "hull": 0.0, "destroyed": false}
	if not alive:
		return result
	var incoming: float = maxf(0.0, amount)
	var absorbed: float = minf(shield, incoming)
	shield -= absorbed
	incoming -= absorbed
	result["shield"] = absorbed
	if incoming > 0.0:
		var reduction: float = 0.0 if ignore_armor else armor
		var hull_damage: float = maxf(1.0, incoming - reduction)
		hull -= hull_damage
		result["hull"] = hull_damage
		if hull <= 0.0:
			hull = 0.0
			alive = false
			result["destroyed"] = true
	return result


func to_dict() -> Dictionary:
	return {
		"id": id,
		"class": ship_class,
		"name": display_name,
		"team": team,
		"cell": [cell.x, cell.y],
		"hull": hull,
		"max_hull": max_hull,
		"shield": shield,
		"max_shield": max_shield,
		"move_points": move_points,
		"has_attacked": has_attacked,
		"alive": alive,
		"cooldown": ability_cooldown,
		"squadrons": squadrons_launched,
	}
