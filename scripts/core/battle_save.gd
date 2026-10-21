class_name BattleSave
extends RefCounted
## Mid-battle snapshot: versioned, separate from the campaign save.
##
## TWO FILES, TWO PURPOSES. `SaveData` holds meta-progression (credits, refits, record)
## and is written once per finished battle; `BattleSave` holds ONE in-progress battle so
## a player can leave and come back. They never share a path and never merge: the
## campaign file has no idea a battle snapshot exists.
##
## WHAT IS STORED: the authoritative state only (map cells, ships, turn, objectives,
## RNG states, pending reward flag). WHAT IS REBUILT: anything derived - `by_id` is
## rebuilt from the ship list, and the procedural rock silhouettes are regenerated from
## the map seed, because they are rendering detail derived from `(seed, cell)`.
##
## Determinism: both RNGs are stored by `state`, so the AI and the combat rolls continue
## exactly where they stopped. A restored battle is not "similar" to the original, it is
## the same battle.

const VERSION: int = 1
const DEFAULT_PATH: String = "user://void_command_battle.json"
const ENV_PATH: String = "VOID_COMMAND_BATTLE_PATH"

static var path_override: String = ""


static func save_path() -> String:
	if path_override != "":
		return path_override
	var from_env: String = OS.get_environment(ENV_PATH)
	if from_env != "":
		return from_env
	return DEFAULT_PATH


static func has_save() -> bool:
	return FileAccess.file_exists(save_path())


static func clear() -> void:
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))


# ------------------------------------------------------------------ write ----

static func snapshot(battle) -> Dictionary:
	## Pure: reads the battle, returns a JSON-safe dictionary.
	var ships: Array = []
	for s in battle.ships:
		ships.append({
			"id": s.id,
			"class": s.ship_class,
			"name": s.display_name,
			"team": s.team,
			"cell": [s.cell.x, s.cell.y],
			"facing": [s.facing.x, s.facing.y],
			"footprint": [s.footprint.x, s.footprint.y],
			"orientation": s.orientation,
			"placed": s.placed,
			"max_hull": s.max_hull,
			"hull": s.hull,
			"max_shield": s.max_shield,
			"shield": s.shield,
			"max_move": s.max_move,
			"move_points": s.move_points,
			"base_damage": s.base_damage,
			"attack_range": s.attack_range,
			"armor": s.armor,
			"threat": s.threat,
			"has_attacked": s.has_attacked,
			"ability_cooldown": s.ability_cooldown,
			"squadrons_launched": s.squadrons_launched,
			"ability_ready": s.ability_ready,
			"alive": s.alive,
			"evading": s.evading,
			"kills": s.kills,
			"damage_dealt": s.damage_dealt,
			"ability": (s.ability as Dictionary).duplicate(true),
		})
	var plane: Array = []
	for a in battle.map.planet_anchors:
		plane.append([a.x, a.y])
	return {
		"version": VERSION,
		"seed": battle.seed_value,
		"round": battle.round,
		"phase": battle.phase,
		"outcome": battle.outcome,
		"selected_id": battle.selected_id,
		"difficulty": battle.difficulty,
		"ai_aggression": battle.ai_aggression,
		"ai_enabled": battle.ai_enabled,
		"enemy_hull_scale": battle.enemy_hull_scale,
		"player_upgrades": battle.player_upgrades.duplicate(true),
		"control_hold": battle.control_hold,
		"control_owner": battle.control_owner,
		"control_bonus_claimed": battle.control_bonus_claimed,
		"reward_granted": battle.reward_granted,
		# 64-bit RNG state as a DECIMAL STRING: a JSON number is a double, and these
		# values exceed 2^53, so writing them numerically silently loses the low bits -
		# the restored battle would then diverge after a few rolls.
		"rng_state": str(battle.rng.state) if battle.rng != null else "0",
		"ai_rng_state": str(battle.ai_rng.state) if battle.ai_rng != null else "0",
		"log": battle.log_lines.duplicate(),
		"last_message": battle.last_message,
		"losses": battle.losses.duplicate(),
		"map": {
			"width": battle.map.width,
			"height": battle.map.height,
			"seed": battle.map.seed_value,
			"cells": Array(battle.map.cells),
			"control_cell": [battle.map.control_cell.x, battle.map.control_cell.y],
			"planet_anchors": plane,
			"generation_attempts": battle.map.generation_attempts,
		},
		"ships": ships,
	}


static func save_battle(battle) -> Dictionary:
	var data: Dictionary = snapshot(battle)
	var file: FileAccess = FileAccess.open(save_path(), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "Cannot open the battle save for writing."}
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------------- read ----

static func load_raw() -> Dictionary:
	if not has_save():
		return {"ok": false, "reason": "No battle save."}
	var file: FileAccess = FileAccess.open(save_path(), FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "Cannot open the battle save."}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "The battle save is not valid JSON."}
	return {"ok": true, "data": parsed}


static func restore(data: Dictionary) -> Dictionary:
	## Rebuilds a Battle from a snapshot. Refuses explicitly instead of guessing: a
	## partially valid snapshot is an error, never a half-restored battle.
	var version: int = int(data.get("version", 0))
	if version != VERSION:
		return {"ok": false, "reason": "Unsupported battle save version %d (expected %d)." % [version, VERSION]}
	var map_raw: Variant = data.get("map", null)
	if typeof(map_raw) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "The battle save has no map."}
	var m: Dictionary = map_raw
	var w: int = int(m.get("width", 0))
	var h: int = int(m.get("height", 0))
	if w <= 0 or h <= 0 or not MapConfig.is_valid(Vector2i(w, h)):
		return {"ok": false, "reason": "The battle save declares an invalid battlefield (%dx%d)." % [w, h]}
	var cells_raw: Variant = m.get("cells", null)
	if typeof(cells_raw) != TYPE_ARRAY or (cells_raw as Array).size() != w * h:
		return {"ok": false, "reason": "The battle save map does not match its declared size."}
	var ships_raw: Variant = data.get("ships", null)
	if typeof(ships_raw) != TYPE_ARRAY or (ships_raw as Array).is_empty():
		return {"ok": false, "reason": "The battle save has no ships."}
	var phase: int = int(data.get("phase", -1))
	if phase < 0 or phase > 2:
		return {"ok": false, "reason": "The battle save declares an invalid phase."}
	if int(data.get("round", 0)) < 1:
		return {"ok": false, "reason": "The battle save declares an invalid round."}

	var b = Battle.new()
	b.seed_value = int(data.get("seed", 0))
	b.round = int(data.get("round", 1))
	b.phase = phase
	b.outcome = String(data.get("outcome", ""))
	b.selected_id = int(data.get("selected_id", -1))
	b.difficulty = maxi(1, int(data.get("difficulty", 1)))
	b.ai_aggression = float(data.get("ai_aggression", 0.8))
	b.ai_enabled = bool(data.get("ai_enabled", true))
	b.enemy_hull_scale = float(data.get("enemy_hull_scale", 1.0))
	b.player_upgrades = (data.get("player_upgrades", {}) as Dictionary).duplicate(true)
	b.control_hold = int(data.get("control_hold", 0))
	b.control_owner = int(data.get("control_owner", -1))
	b.control_bonus_claimed = bool(data.get("control_bonus_claimed", false))
	b.reward_granted = bool(data.get("reward_granted", false))
	b.last_message = String(data.get("last_message", ""))
	for line in data.get("log", []):
		b.log_lines.append(String(line))
	for l in data.get("losses", []):
		b.losses.append(String(l))

	b.map = BattleMap.new()
	b.map.width = w
	b.map.height = h
	b.map.seed_value = int(m.get("seed", b.seed_value))
	b.map.cells = PackedInt32Array(cells_raw)
	var cc: Array = m.get("control_cell", [w / 2, h / 2])
	b.map.control_cell = Vector2i(int(cc[0]), int(cc[1]))
	b.map.generation_attempts = int(m.get("generation_attempts", 1))
	b.map.planet_anchors.clear()
	for a in m.get("planet_anchors", []):
		b.map.planet_anchors.append(Vector2i(int(a[0]), int(a[1])))

	b.ships.clear()
	b.by_id.clear()
	var index_by_team: Dictionary = {0: 0, 1: 0}
	for raw in ships_raw:
		if typeof(raw) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "The battle save has a malformed ship entry."}
		var d: Dictionary = raw
		var class_id: String = String(d.get("class", ""))
		if not ShipDefs.has_class(class_id):
			return {"ok": false, "reason": "The battle save references an unknown class '%s'." % class_id}
		var team: int = int(d.get("team", -1))
		if team != 0 and team != 1:
			return {"ok": false, "reason": "The battle save has a ship with an invalid team."}
		var idx: int = int(index_by_team[team])
		var s = Ship.create(class_id, team, int(d.get("id", 0)), idx)
		index_by_team[team] = idx + 1
		s.display_name = String(d.get("name", s.display_name))
		var cell_raw: Array = d.get("cell", [0, 0])
		s.cell = Vector2i(int(cell_raw[0]), int(cell_raw[1]))
		if not b.map.in_bounds(s.cell):
			return {"ok": false, "reason": "The battle save has a ship outside the board."}
		var facing_raw: Array = d.get("facing", [1, 0])
		s.facing = Vector2(float(facing_raw[0]), float(facing_raw[1]))
		var fp_raw: Array = d.get("footprint", [1, 1])
		if not s.set_footprint(Vector2i(int(fp_raw[0]), int(fp_raw[1]))):
			return {"ok": false, "reason": "The battle save has an invalid footprint."}
		if not s.set_orientation(int(d.get("orientation", 0))):
			return {"ok": false, "reason": "The battle save has an invalid orientation."}
		s.placed = bool(d.get("placed", true))
		s.max_hull = float(d.get("max_hull", s.max_hull))
		s.hull = float(d.get("hull", s.hull))
		s.max_shield = float(d.get("max_shield", s.max_shield))
		s.shield = float(d.get("shield", s.shield))
		s.max_move = int(d.get("max_move", s.max_move))
		s.move_points = int(d.get("move_points", s.move_points))
		s.base_damage = float(d.get("base_damage", s.base_damage))
		s.attack_range = int(d.get("attack_range", s.attack_range))
		s.armor = float(d.get("armor", s.armor))
		s.threat = float(d.get("threat", s.threat))
		s.has_attacked = bool(d.get("has_attacked", false))
		s.ability_cooldown = int(d.get("ability_cooldown", 0))
		# A resumable battle must not hand the Carrier ten fresh swarms.
		s.squadrons_launched = int(d.get("squadrons_launched", 0))
		s.ability_ready = bool(d.get("ability_ready", true))
		s.alive = bool(d.get("alive", true))
		s.evading = bool(d.get("evading", false))
		s.kills = int(d.get("kills", 0))
		s.damage_dealt = float(d.get("damage_dealt", 0.0))
		if typeof(d.get("ability", null)) == TYPE_DICTIONARY:
			s.ability = (d["ability"] as Dictionary).duplicate(true)
		b._add_ship(s)

	b.rng = RandomNumberGenerator.new()
	b.rng.state = int(str(data.get("rng_state", "0")))
	b.ai_rng = RandomNumberGenerator.new()
	b.ai_rng.state = int(str(data.get("ai_rng_state", "0")))
	b.map_size = Vector2i(w, h)
	return {"ok": true, "reason": "", "battle": b}
