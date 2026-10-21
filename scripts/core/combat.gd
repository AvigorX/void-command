class_name Combat
extends RefCounted
## Damage resolution. Pure math on Ship state; animations are cosmetic and derived later.

const ShipRef = preload("res://scripts/core/ship.gd")


static func resolve(attacker: Ship, target: Ship, map: BattleMap, opts: Dictionary = {}) -> Dictionary:
	var bonus: float = float(opts.get("bonus_damage", 0.0))
	var ignore_armor: bool = bool(opts.get("ignore_armor", false))
	var ignore_cover: bool = bool(opts.get("ignore_cover", false))
	# Cover: the caller may pass an explicit verdict computed from the whole
	# footprint (`opts["cover"]`). Without it the reference cell decides, which is
	# exactly the old behaviour for a 1x1 hull.
	var covered: bool = bool(opts["cover"]) if opts.has("cover") else map.is_cover(target.cell)
	var raw: float = attacker.base_damage + bonus
	if target.evading:
		raw = ceilf(raw * 0.5)
	if not ignore_cover and covered:
		raw = ceilf(raw * 0.7)
	raw = maxf(1.0, raw)
	var hit: Dictionary = target.take_damage(raw, ignore_armor)
	var result := {
		"raw": raw,
		"shield": float(hit["shield"]),
		"hull": float(hit["hull"]),
		"destroyed": bool(hit["destroyed"]),
		"ignore_armor": ignore_armor,
		"cover": (not ignore_cover) and covered,
	}
	attacker.damage_dealt += float(hit["shield"]) + float(hit["hull"])
	if bool(hit["destroyed"]):
		attacker.kills += 1
	return result


static func splash_targets(center_ship: Ship, ships: Array, team: int = -1) -> Array:
	## Ships touching the centre ship's footprint: minimum Manhattan distance 1
	## between ANY pair of occupied cells. Each ship appears at most once and the
	## centre ship never appears, so a multi-cell hull cannot be damaged twice just
	## because the blast shares several of its cells.
	##
	## NOTE: the centre's life state is deliberately ignored - the blast geometry is
	## captured from the struck hull even when that hit already destroyed it (the
	## salvo resolves the primary target before the splash).
	var out: Array = []
	if center_ship == null:
		return out
	var center_cells: Array[Vector2i] = center_ship.cells()
	for s in ships:
		if s == null or not s.alive or s == center_ship:
			continue
		if team >= 0 and s.team != team:
			continue
		var adjacent: bool = false
		for a in s.cells():
			for b in center_cells:
				if Pathfinder.manhattan(a, b) == 1:
					adjacent = true
					break
			if adjacent:
				break
		if adjacent:
			out.append(s)
	return out
