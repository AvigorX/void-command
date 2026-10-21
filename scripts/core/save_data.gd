extends RefCounted
## Versioned save file. Explicit schema, validated on load, safe fallback.

const PATH: String = "user://void_command_save.json"
## Environment hook for CI and for any tool that must run the game without
## touching the player's progression.
const ENV_OVERRIDE: String = "VOID_COMMAND_SAVE_PATH"
const VERSION: int = 1
## Classes with a refit track. M5: all eight catalogue classes, in catalogue order. Adding
## entries is backward compatible - `sanitize()` fills the missing tracks at level 0 for an
## older save, and the schema version stays 1 because no existing field changed meaning.
const CLASSES: Array[String] = ["interceptor", "fighter", "destroyer", "frigate", "cruiser",
	"carrier", "battleship", "dreadnought"]
const MAX_UPGRADE: int = 3

## Isolation hook. Empty means "use the production path".
## Tests and probes set this to a scratch file *before* any load/save, so a test
## run can never reach the player's real progression. Because the real file is
## never opened for writing, isolation holds even after a crash or a timeout:
## there is no backup to restore and nothing to lose.
static var path_override: String = ""


static func save_path() -> String:
	if path_override != "":
		return path_override
	var from_env: String = OS.get_environment(ENV_OVERRIDE)
	if from_env != "":
		return from_env
	return PATH


static func default_data() -> Dictionary:
	var up: Dictionary = {}
	for c in CLASSES:
		up[c] = {"hull": 0, "weapon": 0}
	return {
		"version": VERSION,
		"credits": 0,
		"upgrades": up,
		"stats": {"battles": 0, "wins": 0, "losses": 0},
		"last_seed": 20261019,
	}


static func load_data() -> Dictionary:
	var path: String = save_path()
	if not FileAccess.file_exists(path):
		return default_data()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return default_data()
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return default_data()
	var raw: Dictionary = parsed
	if int(raw.get("version", 0)) != VERSION:
		return default_data()
	return sanitize(raw)


static func save_data(d: Dictionary) -> bool:
	var clean: Dictionary = sanitize(d)
	var f: FileAccess = FileAccess.open(save_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(clean, "\t"))
	f.close()
	return true


static func sanitize(raw: Dictionary) -> Dictionary:
	var d: Dictionary = default_data()
	d["credits"] = maxi(0, int(raw.get("credits", 0)))
	d["last_seed"] = int(raw.get("last_seed", 20261019))
	var stats_raw: Dictionary = raw.get("stats", {}) if typeof(raw.get("stats", {})) == TYPE_DICTIONARY else {}
	d["stats"] = {
		"battles": maxi(0, int(stats_raw.get("battles", 0))),
		"wins": maxi(0, int(stats_raw.get("wins", 0))),
		"losses": maxi(0, int(stats_raw.get("losses", 0))),
	}
	var upgrades_raw: Dictionary = raw.get("upgrades", {}) if typeof(raw.get("upgrades", {})) == TYPE_DICTIONARY else {}
	var up: Dictionary = {}
	for c in CLASSES:
		var entry: Dictionary = upgrades_raw.get(c, {}) if typeof(upgrades_raw.get(c, {})) == TYPE_DICTIONARY else {}
		up[c] = {
			"hull": clampi(int(entry.get("hull", 0)), 0, MAX_UPGRADE),
			"weapon": clampi(int(entry.get("weapon", 0)), 0, MAX_UPGRADE),
		}
	d["upgrades"] = up
	return d


static func record_battle(d: Dictionary, victory: bool, credits: int, seed_value: int) -> Dictionary:
	var out: Dictionary = sanitize(d)
	out["credits"] = maxi(0, int(out["credits"]) + credits)
	out["last_seed"] = seed_value
	var stats: Dictionary = out["stats"]
	stats["battles"] = int(stats["battles"]) + 1
	if victory:
		stats["wins"] = int(stats["wins"]) + 1
	else:
		stats["losses"] = int(stats["losses"]) + 1
	out["stats"] = stats
	return out


static func upgrade_cost(level: int) -> int:
	return 100 + 60 * clampi(level, 0, MAX_UPGRADE)


static func buy_upgrade(d: Dictionary, class_id: String, kind: String) -> Dictionary:
	## Returns {ok, reason, data}. Mutates nothing on failure.
	var data: Dictionary = sanitize(d)
	if not CLASSES.has(class_id):
		return {"ok": false, "reason": "Unknown ship class.", "data": data}
	if kind != "hull" and kind != "weapon":
		return {"ok": false, "reason": "Unknown upgrade branch.", "data": data}
	var level: int = int(data["upgrades"][class_id][kind])
	if level >= MAX_UPGRADE:
		return {"ok": false, "reason": "Already at maximum level.", "data": data}
	var cost: int = upgrade_cost(level)
	if int(data["credits"]) < cost:
		return {"ok": false, "reason": "Not enough credits (%d needed)." % cost, "data": data}
	data["credits"] = int(data["credits"]) - cost
	data["upgrades"][class_id][kind] = level + 1
	return {"ok": true, "reason": "", "data": data}
