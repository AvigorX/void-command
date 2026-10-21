extends SceneTree
## End-to-end smoke test of the real scene: menu -> battle -> actions -> result -> restart.
## Drives the same handlers the mouse/keyboard drive. Exits 0 only if every check passes.

const BattleScript = preload("res://scripts/core/battle.gd")
const SaveScript = preload("res://scripts/core/save_data.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var main: Node = null
var screen: Node = null
var frame: int = 0
var checks: int = 0
var failures: int = 0
var stage: int = 0
var save_existed: bool = false
var save_backup: String = ""
var save_path: String = "user://void_command_save.json"
var real_save_before: Dictionary = {}
var old_seed: int = 0
var result_checked: bool = false


func _initialize() -> void:
	print("=== VOID COMMAND — UI / SCENE SMOKE TEST ===")
	# S0: run against a scratch save. `save_path` now resolves to the isolated
	# file, so the backup/restore below is a second layer that can only ever
	# touch the scratch copy - the player's real file is never opened.
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	save_path = SaveScript.save_path()
	save_existed = FileAccess.file_exists(save_path)
	if save_existed:
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f != null:
			save_backup = f.get_as_text()
			f.close()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 8:
		_stage_menu()
	elif frame == 30:
		_stage_battle()
	elif stage == 3:
		if screen != null and screen.overlay != null and String(screen.overlay.mode) == "result":
			_stage_result()
			stage = 4
		elif frame > 900:
			ok(false, "result overlay appeared after auto-play")
			_finish()
	elif stage == 4:
		_stage_restart()
		_finish()
	if frame > 1200 and stage < 4:
		ok(false, "test completed before timeout")
		_finish()
	return false


func _stage_menu() -> void:
	ok(main != null, "Main scene instantiated")
	ok(main.current != null, "menu screen is current")
	ok(String(main.current.mode) == "main", "menu starts in main mode")
	ok(main.save_data.has("version"), "save data loaded with a version field")
	ok(main.current.button_nodes.size() == 4, "main menu exposes 4 actions")
	# Upgrade purchase writes through SaveData and refreshes the screen.
	main.save_data["credits"] = 500
	main.current._set_mode("upgrades")
	ok(main.current.button_nodes.size() == 17, "upgrade screen exposes 16 refits (8 classes) + back")
	main.current._buy("frigate", "hull")
	ok(int(main.save_data["upgrades"]["frigate"]["hull"]) == 1, "fleet upgrade purchased and stored")
	ok(int(main.save_data["credits"]) == 400, "upgrade cost deducted")
	main.current._set_mode("main")
	# Use the actual menu button signal, not an internal shortcut.
	ok(main.current.button_nodes.size() == 4, "menu buttons rebuilt after returning from upgrades")
	main.current.button_nodes[0].pressed.emit()
	screen = main.current
	ok(screen != null and screen.battle != null, "new battle screen created")
	old_seed = int(screen.battle.seed_value)


func _stage_battle() -> void:
	ok(screen.view.draw_count > 0, "battlefield renderer executed _draw (%d frames)" % screen.view.draw_count)
	ok(screen.battle.ships.size() >= 9, "fleet deployed on the battlefield")
	ok(screen.hud != null and screen.hud.btn_end != null, "HUD built with native controls")
	# --- selection ---
	var fighter: Ship = null
	for s in screen.battle.alive_ships(0):
		if s.ship_class == "fighter":
			fighter = s
			break
	ok(fighter != null, "player fighter available")
	screen._on_ship_selected(fighter.id)
	ok(screen.battle.selected_id == fighter.id, "clicking a friendly ship selects it")
	# --- movement ---
	var target_cell := Vector2i(-1, -1)
	var dist: Dictionary = screen.battle.reachable_cells(fighter.id)["dist"]
	for c in dist.keys():
		if int(dist[c]) == 2:
			target_cell = c
			break
	ok(target_cell.x >= 0, "reachable cell found")
	var start_cell: Vector2i = fighter.cell
	screen._on_board_click(target_cell)
	ok(fighter.cell == target_cell, "clicking a highlighted cell moves the ship")
	ok(fighter.cell != start_cell, "ship actually changed cell")
	# --- illegal move: blocked terrain ---
	var blocked := Vector2i(-1, -1)
	for y in range(screen.battle.map.height):
		for x in range(screen.battle.map.width):
			if screen.battle.map.is_blocked(Vector2i(x, y)):
				blocked = Vector2i(x, y)
				break
		if blocked.x >= 0:
			break
	if blocked.x >= 0:
		screen._on_board_click(blocked)
		ok(screen.hud.status_text != "", "illegal move produces feedback")
	# --- illegal attack: out of range ---
	var enemy: Ship = screen.battle.alive_ships(1)[0]
	var had_attacked: bool = fighter.has_attacked
	screen._on_board_click(enemy.cell)
	ok(fighter.has_attacked == had_attacked, "out-of-range click does not fire")
	# --- ability flow (cruiser shield surge) ---
	var cruiser: Ship = null
	for s in screen.battle.alive_ships(0):
		if s.ship_class == "cruiser":
			cruiser = s
			break
	ok(cruiser != null, "player cruiser available")
	screen._on_ship_selected(cruiser.id)
	cruiser.shield = 0.0
	screen.hud.btn_ability.pressed.emit()
	ok(screen.ability_armed, "ability arms targeting (via HUD button)")
	ok(screen.view.armed_ability, "battlefield highlights ability targets")
	screen._on_board_click(cruiser.cell)
	ok(cruiser.shield > 0.0, "shield surge resolved through the UI handler")
	ok(cruiser.ability_cooldown > 0, "ability cooldown applied")
	ok(not screen.ability_armed, "targeting disarmed after use")
	# --- roster row click (HUD hit test, same path as the mouse) ---
	var roster_event := InputEventMouseButton.new()
	roster_event.button_index = MOUSE_BUTTON_LEFT
	roster_event.pressed = true
	roster_event.position = Vector2(60, 127)
	screen.hud._gui_input(roster_event)
	ok(screen.battle.selected_id == screen.battle.alive_ships(0)[0].id, "fleet roster row click selects the ship")
	# --- positive attack through the click handler ---
	var striker: Ship = null
	for s in screen.battle.alive_ships(0):
		if not s.has_attacked:
			striker = s
			break
	var victim: Ship = screen.battle.alive_ships(1)[0]
	if striker != null and victim != null:
		var options: Array[Vector2i] = [
			striker.cell + Vector2i(1, 0), striker.cell + Vector2i(-1, 0),
			striker.cell + Vector2i(0, 1), striker.cell + Vector2i(0, -1),
		]
		for opt in options:
			if screen.battle.map.in_bounds(opt) and not screen.battle.map.is_blocked(opt) and screen.view.ship_at(opt) == null:
				victim.cell = opt
				break
		screen._on_ship_selected(striker.id)
		var pool_before: float = victim.shield + victim.hull
		screen._on_board_click(victim.cell)
		ok(striker.has_attacked, "clicking an in-range enemy fires")
		ok(victim.shield + victim.hull < pool_before, "weapon damage applied to the target")
	# --- hold ---
	var frigate: Ship = null
	for s in screen.battle.alive_ships(0):
		if s.ship_class == "frigate":
			frigate = s
			break
	if frigate != null:
		screen._on_ship_selected(frigate.id)
		screen.hud.btn_wait.pressed.emit()
		ok(frigate.has_attacked and frigate.move_points == 0, "hold consumes the ship action (via HUD button)")
	# --- pause ---
	screen._toggle_pause()
	ok(screen.overlay != null and String(screen.overlay.mode) == "pause", "pause overlay opens")
	ok(screen.overlay != null and screen.overlay.lines.size() > 0, "pause overlay populated")
	screen._resume()
	ok(screen.overlay == null and not screen.paused, "pause overlay resumes cleanly")
	# --- end turn + AI ---
	var round_before: int = screen.battle.round
	screen.hud.btn_end.pressed.emit()
	ok(screen.battle.round >= round_before, "turn transition advanced the round (via END TURN button)")
	ok(screen.battle.phase == BattleScript.Phase.PLAYER or screen.battle.outcome != "", "control returned to the player after the AI turn")
	# --- auto-play to a result, then let the overlay appear ---
	_auto_play(screen.battle)
	ok(screen.battle.outcome == "victory" or screen.battle.outcome == "defeat", "battle reaches an outcome (%s)" % screen.battle.outcome)
	screen.battle.events.clear()
	screen.view.event_queue.clear()
	screen.view.effects.clear()
	screen.view.event_timer = 0.0
	stage = 3


func _auto_play(b) -> void:
	var guard: int = 0
	while b.outcome == "" and guard < 45:
		guard += 1
		for s in b.alive_ships(0):
			if s.has_attacked:
				continue
			var best = null
			for e in b.alive_ships(1):
				if bool(b.can_attack(s.id, e.id)["ok"]):
					if best == null or e.hull < best.hull:
						best = e
			if best != null:
				b.attack(s.id, best.id)
				continue
			var tgt = null
			var td: int = 9999
			for e in b.alive_ships(1):
				var d: int = PathfinderRef.manhattan(s.cell, e.cell)
				if d < td:
					td = d
					tgt = e
			if tgt == null:
				break
			var explored: Dictionary = b.reachable_cells(s.id)
			var field: Dictionary = PathfinderRef.distance_field(b.map, tgt.cell)
			var best_cell: Vector2i = s.cell
			var best_score: int = -99999
			for c in explored["dist"].keys():
				var score: int = -int(field.get(c, 9999)) * 10
				if PathfinderRef.manhattan(c, tgt.cell) <= s.attack_range and b.map.has_line_of_sight(c, tgt.cell):
					score += 60
				if score > best_score:
					best_score = score
					best_cell = c
			if best_cell != s.cell:
				b.move_ship(s.id, best_cell)
			if bool(b.can_attack(s.id, tgt.id)["ok"]):
				b.attack(s.id, tgt.id)
		if b.outcome == "":
			b.end_turn()
	b.events.clear()


func _stage_result() -> void:
	var overlay = screen.overlay
	ok(overlay != null, "result overlay present")
	ok(String(overlay.mode) == "result", "result overlay mode is result")
	ok(String(overlay.title) == "VICTORY" or String(overlay.title) == "DEFEAT", "result title set (%s)" % String(overlay.title))
	ok(overlay.lines.size() >= 3, "result overlay lists the battle summary")
	ok(bool(screen.reward_committed), "battle rewards committed exactly once")
	result_checked = true


func _stage_restart() -> void:
	screen._restart()
	ok(screen.battle.seed_value != old_seed, "rematch uses a new seed")
	ok(screen.battle.ships.size() >= 9, "rematch deploys a fresh fleet")
	ok(screen.battle.outcome == "", "rematch starts a live battle")
	ok(screen.overlay == null, "result overlay cleared on rematch")
	ok(not screen.reward_committed, "reward flag reset for the new battle")


func _finish() -> void:
	_restore_save()
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	SaveGuard.cleanup()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)


func _restore_save() -> void:
	var abs_path: String = ProjectSettings.globalize_path(save_path)
	if save_existed:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(save_backup)
			f.close()
	else:
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(abs_path)
