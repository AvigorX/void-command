extends RefCounted
## S0 test support: proves that a test run never touches the player's real save.
##
## Strategy: isolation, not replacement. `isolate()` redirects every SaveData
## read/write to a scratch file *before* the suite loads or saves anything, so
## the production file is never opened for writing. Because nothing is replaced,
## there is nothing to restore: a crash, an assertion failure or a timeout cannot
## lose player data - the real file was never touched in the first place.
##
## `snapshot()` + `unchanged()` are the evidence: each suite asserts at the end
## that the real file is byte-identical to what it found at the start.

const SaveScript = preload("res://scripts/core/save_data.gd")
const BattleSaveScript = preload("res://scripts/core/battle_save.gd")

const REAL_SAVE: String = "user://void_command_save.json"
const TEST_SAVE: String = "user://void_command_save.test.json"
## The mid-battle snapshot is a SECOND file. It is isolated too: a suite or a UI probe
## must not leave a resumable battle behind in the player's profile.
const REAL_BATTLE: String = "user://void_command_battle.json"
const TEST_BATTLE: String = "user://void_command_battle.test.json"


static func fingerprint(path: String) -> Dictionary:
	## Byte-level fingerprint of one production file (read-only).
	var exists: bool = FileAccess.file_exists(path)
	var sha: String = ""
	var size: int = 0
	if exists:
		var abs_path: String = ProjectSettings.globalize_path(path)
		sha = FileAccess.get_sha256(abs_path)
		size = FileAccess.get_size(abs_path)
	return {"exists": exists, "sha": sha, "size": size}


static func snapshot() -> Dictionary:
	## Both real files, not just the campaign save: a suite that leaks a mid-battle
	## snapshot into the player's profile is a real leak even though the campaign save is
	## untouched. The battle file went unnoticed for exactly that reason once.
	return {"save": fingerprint(REAL_SAVE), "battle": fingerprint(REAL_BATTLE)}


static func unchanged(snap: Dictionary) -> bool:
	var now: Dictionary = snapshot()
	return _same(snap["save"], now["save"]) and _same(snap["battle"], now["battle"])


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return (bool(a["exists"]) == bool(b["exists"])
		and String(a["sha"]) == String(b["sha"])
		and int(a["size"]) == int(b["size"]))


static func describe(snap: Dictionary) -> String:
	var save: Dictionary = snap["save"]
	var battle: Dictionary = snap["battle"]
	var left: String = "real save absent"
	if bool(save["exists"]):
		left = "real save %d bytes, sha256 %s…" % [int(save["size"]), String(save["sha"]).substr(0, 16)]
	var right: String = "no real battle file"
	if bool(battle["exists"]):
		right = "REAL BATTLE FILE %d bytes" % int(battle["size"])
	return "%s | %s" % [left, right]


static func isolate() -> void:
	## Point both save systems at scratch paths and start from a clean slate.
	SaveScript.path_override = TEST_SAVE
	BattleSaveScript.path_override = TEST_BATTLE
	# Belt and braces: the snapshot path is also pinned through the environment, which is
	# process-global. A static var lives on one script RESOURCE, and a file that reaches
	# BattleSave through its class_name instead of a preload could otherwise resolve to a
	# different instance and write the player's real file (this actually happened once).
	OS.set_environment(BattleSaveScript.ENV_PATH, TEST_BATTLE)
	remove_test_save()


static func cleanup() -> void:
	remove_test_save()
	SaveScript.path_override = ""
	# The BATTLE snapshot stays pinned to the scratch path until the process exits, on
	# purpose: `cleanup()` runs at the end of a suite, but a scene-driven suite still
	# gets one more `_process` frame before `quit()` takes effect - and the battle
	# screen autosaves once per round. Releasing the override there wrote the player's
	# real battle file. Leaving it pinned costs nothing: the scratch file is deleted
	# here and again by the next run's isolate().
	BattleSaveScript.path_override = TEST_BATTLE
	OS.set_environment(BattleSaveScript.ENV_PATH, TEST_BATTLE)


static func remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	if FileAccess.file_exists(TEST_BATTLE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BATTLE))
