extends SceneTree
## S0 REGRESSION — the test suites and the visual probe must never touch the
## player's real save file.
##
## This is an end-to-end proof, not a unit test: it launches each suite as a
## child process with the same engine binary (exactly the command a developer
## runs), then compares a SHA-256 fingerprint of `user://void_command_save.json`
## before and after. Any suite that reaches the production file - directly or
## through the real scene - makes this test fail.
##
## Usage:
##   godot --headless --path <project> --script res://tests/test_save_isolation.gd
##   godot --headless --path <project> --script res://tests/test_save_isolation.gd -- --with-gui
##     (--with-gui also runs the windowed visual probe; needs a display)

const SaveGuard = preload("res://tests/save_guard.gd")

const SUITES: Array[String] = ["test_core", "test_ui", "test_acceptance", "test_stress", "test_footprint", "test_multicell", "test_pathfinding", "test_maps", "test_map_stress", "test_deployment", "test_hud", "test_battle_save", "test_catalog", "test_fleet", "test_fleet_ui", "test_frigate", "test_capital", "test_navigation", "test_carrier", "test_camera", "test_grid", "test_pathsearch_equivalence", "test_bigmap", "test_controls"]
## Windowed probes: they render real frames, so they only run behind --with-gui.
## `step1_visual_probe` is a child of this gate as of STEP 2 (it was the last suite
## still running outside the isolation proof - HANDOFF section 7, debt 4).
const GUI_PROBES: Array[String] = ["visual_probe", "step1_visual_probe", "step2_fighter_probe", "step3_fleet_probe"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	print("=== VOID COMMAND — SAVE ISOLATION REGRESSION ===")
	var before: Dictionary = SaveGuard.snapshot()
	print("  %s" % SaveGuard.describe(before))

	ok(String(SaveGuard.TEST_SAVE) != String(SaveGuard.REAL_SAVE), "the test save path differs from the production path")
	ok(typeof(JSON.parse_string(_read_real())) == TYPE_DICTIONARY or not bool(before["save"]["exists"]),
		"real save parses as JSON before the run")
	# The player must not start the run with a resumable battle either: if one exists, the
	# gate will hold the runner to keeping it byte-identical (a suite must not overwrite it).
	print("  battle file before: %s" % ("present" if bool(before["battle"]["exists"]) else "absent"))

	var engine: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	ok(engine != "" and FileAccess.file_exists(engine), "engine binary resolved: %s" % engine)
	print("  engine : %s" % engine)
	print("  project: %s" % project)

	for suite in SUITES:
		_run_suite(engine, project, suite, false)

	if OS.get_cmdline_user_args().has("--with-gui"):
		for probe in GUI_PROBES:
			_run_suite(engine, project, probe, true)

	var after: Dictionary = SaveGuard.snapshot()
	print("  %s" % SaveGuard.describe(after))
	ok(SaveGuard.unchanged(before), "BOTH real files are byte-identical after every suite")
	ok(bool(after["save"]["exists"]) == bool(before["save"]["exists"]), "the real save still exists (not deleted)")
	ok(bool(after["battle"]["exists"]) == bool(before["battle"]["exists"]),
		"no suite created or deleted a mid-battle snapshot in the player profile")
	if not bool(before["battle"]["exists"]):
		ok(not bool(after["battle"]["exists"]),
			"the player's profile has no battle snapshot after the run (was absent before)")
	if bool(after["save"]["exists"]):
		var parsed: Variant = JSON.parse_string(_read_real())
		ok(typeof(parsed) == TYPE_DICTIONARY, "the real save is still valid JSON")
		if typeof(parsed) == TYPE_DICTIONARY:
			ok(int(parsed.get("version", 0)) == 1, "the real save still declares schema version 1")
			ok(int(parsed.get("credits", -1)) >= 0, "credits are still a non-negative integer")

	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)


func _read_real() -> String:
	## Read-only access to the production save, used for the "still valid" checks.
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path(SaveGuard.REAL_SAVE))


func _run_suite(engine: String, project: String, script_name: String, gui: bool) -> void:
	var args := PackedStringArray()
	if not gui:
		args.append("--headless")
	args.append("--path")
	args.append(project)
	args.append("--script")
	args.append("res://tests/%s.gd" % script_name)
	var output: Array = []
	var code: int = OS.execute(engine, args, output, false, false)
	var text: String = ""
	for line in output:
		text += String(line) + "\n"
	var counts: String = _find_line(text, "checks:")
	var verdict: String = _find_line(text, "RESULT:")
	print("  %-14s exit=%-3d %s %s" % [script_name, code, counts, verdict])
	ok(code == 0, "%s exits 0" % script_name)
	ok(verdict == "RESULT: PASS", "%s reported PASS" % script_name)
	# A failing child used to leave nothing behind but two red lines: the reason died in the
	# captured buffer. Print the tail of its output so the next occurrence names itself.
	if code != 0 or verdict != "RESULT: PASS":
		var tail_lines: PackedStringArray = text.strip_edges().split("\n")
		var start_at: int = maxi(0, tail_lines.size() - 15)
		print("      --- output tail of %s (exit %d) ---" % [script_name, code])
		for i in range(start_at, tail_lines.size()):
			print("      | %s" % String(tail_lines[i]))
		print("      --- end of %s ---" % script_name)


func _find_line(text: String, key: String) -> String:
	for line in text.split("\n"):
		var s: String = String(line).strip_edges()
		if s.find(key) == 0:
			return s
	return "<no '%s' in output>" % key


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
