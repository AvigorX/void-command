extends SceneTree
## ACCEPTANCE SUITE — drives the real scene the way a player does.
## Menu buttons, upgrade purchases, HUD buttons, all four abilities, invalid actions,
## camera, pause/resume, defeat, result overlay and rematch.
## Exit 0 only if every assertion passes.

const BattleScript = preload("res://scripts/core/battle.gd")
const SaveScript = preload("res://scripts/core/save_data.gd")
const PathfinderRef = preload("res://scripts/core/pathfinder.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

## S0.1: fixed seed for the acceptance scenario. The menu path seeds a battle from
## the wall clock, which made this suite irreproducible; every stage now runs
## against this value, and it is printed at startup so a failure can be replayed.
const ACCEPT_SEED: int = 20261019

var main: Node = null
var screen: Node = null
var frame: int = 0
var stage: int = 0
var checks: int = 0
var failures: int = 0
var save_existed: bool = false
var save_backup: String = ""
var save_path: String = "user://void_command_save.json"
var real_save_before: Dictionary = {}
var old_seed: int = 0
var defeat_frame: int = 0


func _initialize() -> void:
	print("=== VOID COMMAND — ACCEPTANCE SUITE ===")
	# S0: the suite (which awards credits and records stats through the real
	# screen) runs against a scratch save. The backup/restore below therefore
	# only ever rewrites the scratch copy.
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


func ok(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL  %s" % label)


func _process(_delta: float) -> bool:
	frame += 1
	match stage:
		0:
			if frame >= 6:
				_stage_menu()
				stage = 1
		1:
			if frame >= 12:
				_stage_battle()
				stage = 2
		2:
			if frame >= 26:
				_stage_actions()
				stage = 3
		3:
			if frame >= 34:
				_stage_pause()
				stage = 4
		4:
			if frame >= 38:
				_stage_resume()
				stage = 5
		5:
			if frame >= 42:
				_stage_defeat()
				stage = 6
		6:
			if screen != null and screen.overlay != null and String(screen.overlay.mode) == "result":
				if defeat_frame == 0:
					defeat_frame = frame
				elif frame >= defeat_frame + 3:
					_stage_result()
					stage = 7
			elif frame > 300:
				ok(false, "defeat overlay appeared")
				_finish()
				return true
		7:
			if frame >= defeat_frame + 10:
				_stage_rematch()
				_finish()
				return true
	if frame > 600:
		ok(false, "suite finished before timeout")
		_finish()
		return true
	return false


func _find_button(node: Node, prefix: String) -> Button:
	for b in node.button_nodes:
		if is_instance_valid(b) and String(b.text).begins_with(prefix):
			return b
	return null


func _stage_menu() -> void:
	ok(main.current != null, "menu screen loaded")
	var menu = main.current
	ok(menu.button_nodes.size() == 4, "main menu has 4 actions")
	var wired: int = 0
	for b in menu.button_nodes:
		if b.pressed.get_connections().size() > 0:
			wired += 1
	ok(wired == 4, "all 4 menu buttons are wired to handlers (%d)" % wired)
	# Upgrades: buy the same branch three times, then check the cap.
	main.save_data["credits"] = 5000
	menu._set_mode("upgrades")
	ok(menu.button_nodes.size() == 17, "upgrade screen exposes 16 refits (8 classes x 2) + back")
	var buy_btn: Button = _find_button(menu, "HULL LV 0")
	# The first row is the first refittable class, which is the Interceptor since M5 made
	# all eight classes refittable (SaveData.CLASSES).
	ok(buy_btn != null, "interceptor hull refit available at level 0")
	if buy_btn != null:
		buy_btn.pressed.emit()
		ok(int(main.save_data["upgrades"]["interceptor"]["hull"]) == 1, "refit purchase applied via button")
		var b2: Button = _find_button(menu, "HULL LV 1")
		if b2 != null:
			b2.pressed.emit()
			var b3: Button = _find_button(menu, "HULL LV 2")
			if b3 != null:
				b3.pressed.emit()
	ok(int(main.save_data["upgrades"]["interceptor"]["hull"]) == 3, "three purchases reach level 3")
	var max_btn: Button = _find_button(menu, "HULL LV 3")
	ok(max_btn != null and max_btn.disabled, "maxed refit button is disabled")
	# Controls sheet and back.
	menu._set_mode("controls")
	var back: Button = _find_button(menu, "BACK")
	ok(back != null, "controls sheet has a back button")
	if back != null:
		back.pressed.emit()
	ok(String(menu.mode) == "main", "back returns to the main menu")
	# Start a battle through the real button.
	menu = main.current
	var start_btn: Button = _find_button(menu, "NEW BATTLE")
	ok(start_btn != null, "new battle button present")
	if start_btn != null:
		start_btn.pressed.emit()
	screen = main.current
	ok(screen != null and screen.battle != null, "battle starts from the menu button")
	# S0.1: deterministic scenario. The menu starts the battle with a wall-clock
	# seed (battle_screen falls back to Time when start_seed <= 0), which made the
	# acceptance run irreproducible. Re-seed it explicitly and log the value.
	if screen != null and screen.battle != null:
		screen._start_battle(ACCEPT_SEED)
		print("  acceptance seed: %d" % ACCEPT_SEED)
		ok(int(screen.battle.seed_value) == ACCEPT_SEED, "battle seeded deterministically (%d)" % ACCEPT_SEED)
		old_seed = int(screen.battle.seed_value)


func _stage_battle() -> void:
	ok(screen.view.draw_count > 0, "battlefield drew frames (%d)" % screen.view.draw_count)
	ok(screen.battle.ships.size() == 9, "9 ships on the field")
	ok(screen.battle.alive_ships(0).size() == 5, "5 player ships")
	var hud_wired: int = 0
	for b in [screen.hud.btn_end, screen.hud.btn_ability, screen.hud.btn_wait, screen.hud.btn_menu]:
		if b != null and b.pressed.get_connections().size() > 0:
			hud_wired += 1
	ok(hud_wired == 4, "all 4 HUD buttons are wired (%d)" % hud_wired)
	ok(screen.hud.btn_ability.disabled, "ability disabled with no selection")
	ok(screen.hud.btn_wait.disabled, "hold disabled with no selection")
	ok(not screen.hud.btn_end.disabled, "end turn enabled during the player phase")


func _stage_actions() -> void:
	# ---------------- invalid ability (no target in range) ----------------
	var battleship: Ship = null
	for s in screen.battle.alive_ships(0):
		if s.ship_class == "battleship":
			battleship = s
	ok(battleship != null, "battleship available")
	if battleship != null:
		screen._on_ship_selected(battleship.id)
		ok(not screen.hud.btn_ability.disabled, "ability enabled for a ready ship")
		screen.hud.btn_ability.pressed.emit()
		ok(not screen.ability_armed, "ability with no legal target does not arm")
		ok(screen.hud.status_text != "", "invalid ability produces feedback")
	# ---------------- fighter: evasive burn ----------------
	var fighter: Ship = null
	var frigate: Ship = null
	var cruiser: Ship = null
	for s in screen.battle.alive_ships(0):
		if s.ship_class == "fighter" and fighter == null:
			fighter = s
		elif s.ship_class == "frigate":
			frigate = s
		elif s.ship_class == "cruiser":
			cruiser = s
	ok(fighter != null and frigate != null and cruiser != null, "all player classes present")
	if fighter != null:
		screen._on_ship_selected(fighter.id)
		var mp: int = fighter.move_points
		screen.hud.btn_ability.pressed.emit()
		ok(fighter.evading, "evasive burn applied via HUD")
		ok(fighter.move_points == mp + 3, "evasive burn adds movement")
		ok(not fighter.has_attacked, "evasive burn keeps the attack")
		ok(fighter.ability_cooldown == 2, "evasive burn on cooldown")
	# ---------------- frigate: precision strike ----------------
	if frigate != null:
		var enemy: Ship = screen.battle.alive_ships(1)[0]
		var spot: Vector2i = _adjacent_free(frigate.cell)
		if spot.x >= 0 and _place(enemy, spot):
			screen._on_ship_selected(frigate.id)
			screen.hud.btn_ability.pressed.emit()
			ok(screen.ability_armed, "precision strike arms targeting")
			ok(screen.view.ability_highlight.has(spot), "battlefield highlights the target cell")
			var pool: float = enemy.shield + enemy.hull
			screen._on_board_click(spot)
			ok(frigate.has_attacked, "precision strike consumes the attack via click")
			ok(enemy.shield + enemy.hull < pool or not enemy.alive, "precision strike deals damage")
			ok(frigate.ability_cooldown == 2, "precision strike on cooldown")
	# ---------------- cruiser: shield surge ----------------
	if cruiser != null:
		if screen.battle.ability_targets(cruiser.id).is_empty():
			for ally in screen.battle.alive_ships(0):
				if ally.id != cruiser.id:
					var a_spot: Vector2i = _adjacent_free(cruiser.cell)
					if a_spot.x >= 0:
						_place(ally, a_spot)
					break
		screen._on_ship_selected(cruiser.id)
		cruiser.shield = 0.0
		screen.hud.btn_ability.pressed.emit()
		ok(screen.ability_armed, "shield surge arms targeting")
		screen._on_board_click(cruiser.cell)
		ok(cruiser.shield > 0.0, "shield surge restores shields via click")
		ok(cruiser.has_attacked, "shield surge consumes the action")
	# ---------------- battleship: heavy salvo with splash ----------------
	if battleship != null:
		_clear_area(battleship.cell, 4)
		var target: Ship = screen.battle.alive_ships(1)[0]
		var splash: Ship = null
		for s in screen.battle.alive_ships(1):
			if s.id != target.id:
				splash = s
				break
		var pairs: Array = [
			[Vector2i(2, 0), Vector2i(2, 1)],
			[Vector2i(0, 2), Vector2i(1, 2)],
			[Vector2i(-2, 0), Vector2i(-2, -1)],
			[Vector2i(0, -2), Vector2i(-1, -2)],
		]
		var target_cell: Vector2i = Vector2i(-1, -1)
		var splash_cell: Vector2i = Vector2i(-1, -1)
		# M7: hulls deploy horizontally in a six-column band, so the two-cell offsets below
		# can both land on occupied cells. Fall back to a scan of the ring around the
		# battleship, which keeps the test about the SALVO rule and not about the layout.
		for pair in pairs:
			var tc: Vector2i = battleship.cell + pair[0]
			var sc: Vector2i = battleship.cell + pair[1]
			if _can_place(tc) and _can_place(sc):
				target_cell = tc
				splash_cell = sc
				break
		if target_cell.x < 0:
			for r in range(1, 4):
				for dx in range(-r, r + 1):
					for dy in range(-r, r + 1):
						if maxi(absi(dx), absi(dy)) != r:
							continue
						var c1: Vector2i = battleship.cell + Vector2i(dx, dy)
						var c2: Vector2i = c1 + Vector2i(1, 0)
						if _can_place(c1) and _can_place(c2):
							target_cell = c1
							splash_cell = c2
							break
					if target_cell.x >= 0:
						break
				if target_cell.x >= 0:
					break
		var placed_target: bool = target_cell.x >= 0 and _place(target, target_cell)
		var placed_splash: bool = splash != null and splash_cell.x >= 0 and _place(splash, splash_cell)
		ok(placed_target, "salvo target placed on a clear lane")
		ok(placed_splash, "splash target placed adjacent to it")
		if placed_target:
			screen._on_ship_selected(battleship.id)
			screen.hud.btn_ability.pressed.emit()
			ok(screen.ability_armed, "heavy salvo arms targeting")
			var main_pool: float = target.shield + target.hull
			var splash_pool: float = (splash.shield + splash.hull) if splash != null else -1.0
			screen._on_board_click(target_cell)
			ok(battleship.has_attacked, "heavy salvo consumes the attack")
			ok(target.shield + target.hull < main_pool or not target.alive, "salvo damages the primary target")
			if splash != null and placed_splash:
				ok(splash.shield + splash.hull < splash_pool or not splash.alive, "salvo splash damages the adjacent ship")
	# ---------------- movement ----------------
	if fighter != null:
		screen._on_ship_selected(fighter.id)
		var dist: Dictionary = screen.battle.reachable_cells(fighter.id)["dist"]
		var dest: Vector2i = Vector2i(-1, -1)
		for c in dist.keys():
			if int(dist[c]) == 2:
				dest = c
				break
		ok(dest.x >= 0, "reachable destination exists")
		if dest.x >= 0:
			var before: Vector2i = fighter.cell
			var mp_before: int = fighter.move_points
			var cost: int = int(dist[dest])
			screen._on_board_click(dest)
			ok(fighter.cell == dest and dest != before, "movement click moves the ship")
			ok(fighter.move_points == mp_before - cost, "movement points spent (cost %d)" % cost)
		# Illegal destination: blocked terrain.
		var blocked: Vector2i = _first_blocked()
		if blocked.x >= 0:
			var pos_before: Vector2i = fighter.cell
			screen._on_board_click(blocked)
			ok(fighter.cell == pos_before, "blocked cell rejected")
			ok(screen.hud.status_text != "", "blocked move produces feedback")
		# Out-of-range destination.
		var far: Vector2i = Vector2i(19, 13)
		if screen.battle.map.is_blocked(far):
			far = Vector2i(18, 12)
		var pos_before2: Vector2i = fighter.cell
		screen._on_board_click(far)
		ok(fighter.cell == pos_before2, "distant cell rejected")
	# ---------------- invalid attack (out of range) ----------------
	# S0.1: the precondition is CONSTRUCTED, not assumed. A hostile is placed on a
	# clear firing lane beyond the fighter's weapon range, then clicked through the
	# real UI path. Range must be the only reason the shot is refused, so every
	# other targeting condition is asserted to hold first.
	if fighter != null:
		var far_enemy: Ship = screen.battle.alive_ships(1)[0]
		screen._on_ship_selected(fighter.id)
		# Guarantee a firing lane by construction, the same way the salvo stage
		# does: inside a radius of 5 every cell becomes open space, so a cell at
		# distance range+1 always has an unobstructed line to the fighter. Without
		# this the precondition depends on map luck (measured: seed 98765 leaves the
		# fighter in a terrain pocket with no clear lane beyond range).
		_clear_area(fighter.cell, 5)
		var range_cell: Vector2i = _out_of_range_cell_with_los(fighter)
		ok(range_cell.x >= 0, "a passable cell beyond weapon range with a clear lane exists")
		var original_cell: Vector2i = far_enemy.cell
		ok(_place(far_enemy, range_cell), "hostile placed on the far cell")
		var dist_now: int = PathfinderRef.manhattan(fighter.cell, far_enemy.cell)
		ok(dist_now > fighter.attack_range, "distance %d exceeds weapon range %d" % [dist_now, fighter.attack_range])
		ok(screen.battle.map.has_line_of_sight(fighter.cell, far_enemy.cell),
			"line of sight is clear, so range is the only blocker")
		ok(screen.battle.phase == BattleScript.Phase.PLAYER, "the player phase is active for the click")
		ok(not fighter.has_attacked, "the fighter has not fired yet")
		var had: bool = fighter.has_attacked
		var hull_before: float = far_enemy.hull
		var shield_before: float = far_enemy.shield
		var attacks_before: int = _count_attack_events(fighter.id)
		screen._on_board_click(far_enemy.cell)
		ok(fighter.has_attacked == had, "out-of-range click does not fire")
		ok(is_equal_approx(far_enemy.hull, hull_before) and is_equal_approx(far_enemy.shield, shield_before),
			"target hull and shields unchanged by the refused shot")
		ok(far_enemy.alive, "target survives the refused shot")
		ok(_count_attack_events(fighter.id) == attacks_before, "no attack event emitted for the refused shot")
		ok(screen.hud.status_text.find("range") >= 0, "the refusal names the range rule (%s)" % screen.hud.status_text)
		_place(far_enemy, original_cell)
	# ---------------- camera ----------------
	# Bounds are read from the screen, not hardcoded: M6 widened the range for the 48x34 board
	# and a literal here would silently rot again.
	screen._zoom_by(10.0)
	ok(screen.camera.zoom.x <= screen.ZOOM_MAX + 0.001,
		"zoom clamped at maximum (%.2f of %.2f)" % [screen.camera.zoom.x, screen.ZOOM_MAX])
	screen._zoom_by(0.001)
	ok(screen.camera.zoom.x >= screen.ZOOM_MIN - 0.001,
		"zoom clamped at minimum (%.2f of %.2f)" % [screen.camera.zoom.x, screen.ZOOM_MIN])
	screen.camera.position = Vector2(-4000, -4000)
	screen._clamp_camera()
	ok(screen.camera.position.x >= 480.0 and screen.camera.position.y >= 300.0, "camera pan clamped to the board")
	screen.camera.position = Vector2(640, 360)
	screen.camera.zoom = Vector2.ONE


func _stage_pause() -> void:
	screen.hud.btn_menu.pressed.emit()
	ok(screen.overlay != null and String(screen.overlay.mode) == "pause", "HUD menu opens the pause overlay")
	ok(screen.overlay != null and screen.overlay._buttons.size() == 3, "pause overlay offers 3 actions")
	ok(screen.paused, "pause flag set")


func _stage_resume() -> void:
	screen.overlay._buttons[0].pressed.emit()
	ok(screen.overlay == null, "resume button closes the overlay")
	ok(not screen.paused, "resume clears the pause flag")


func _stage_defeat() -> void:
	# Wipe the player fleet: the defeat path must resolve cleanly.
	for s in screen.battle.ships:
		if s.team == 0:
			s.alive = false
			s.hull = 0.0
	screen.battle._check_outcome()
	screen.battle.events.clear()
	screen.view.event_queue.clear()
	screen.view.event_timer = 0.0
	ok(screen.battle.outcome == "defeat", "wiped fleet resolves as defeat")
	ok(screen.battle.phase == BattleScript.Phase.OVER, "phase moves to OVER")


func _stage_result() -> void:
	var overlay = screen.overlay
	ok(overlay != null, "defeat overlay appears")
	ok(String(overlay.title) == "DEFEAT", "overlay title is DEFEAT (%s)" % String(overlay.title))
	ok(overlay.lines.size() >= 4, "defeat summary has content")
	ok(overlay._buttons.size() == 2, "result overlay offers rematch + menu")
	ok(int(main.save_data["stats"]["losses"]) >= 1, "defeat recorded in the save stats")


func _stage_rematch() -> void:
	screen.overlay._buttons[0].pressed.emit()
	ok(screen.battle.seed_value != old_seed, "rematch generated a new seed")
	ok(screen.battle.outcome == "", "rematch is a live battle")
	ok(screen.battle.alive_ships(0).size() == 5, "rematch redeploys the player fleet")
	ok(screen.overlay == null, "rematch clears the overlay")


func _adjacent_free(cell: Vector2i) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var c: Vector2i = cell + d
		if screen.battle.map.in_bounds(c) and not screen.battle.map.is_blocked(c) and screen.view.ship_at(c) == null:
			return c
	return Vector2i(-1, -1)


func _can_place(cell: Vector2i) -> bool:
	if not screen.battle.map.in_bounds(cell) or screen.battle.map.is_blocked(cell):
		return false
	return screen.view.ship_at(cell) == null


func _place(ship: Ship, cell: Vector2i) -> bool:
	if ship == null or not screen.battle.map.in_bounds(cell) or screen.battle.map.is_blocked(cell):
		return false
	var occupant = screen.view.ship_at(cell)
	if occupant != null and occupant.id != ship.id:
		return false
	ship.cell = cell
	screen.view.visual_pos[ship.id] = screen.view.cell_center(cell)
	return true


func _clear_area(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if screen.battle.map.in_bounds(c):
				screen.battle.map.cells[c.y * screen.battle.map.width + c.x] = 0


func _first_blocked() -> Vector2i:
	for y in range(screen.battle.map.height):
		for x in range(screen.battle.map.width):
			if screen.battle.map.is_blocked(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _out_of_range_cell_with_los(shooter: Ship) -> Vector2i:
	## Closest cell (ties broken row-major, so deterministic) that is in bounds,
	## passable, free of ships, beyond the shooter's weapon range, and connected by a
	## clear firing lane. Closest = the tightest possible violation of the range
	## rule, so the assertion tests the boundary instead of an obvious miss.
	var best := Vector2i(-1, -1)
	var best_dist: int = 1 << 30
	for y in range(screen.battle.map.height):
		for x in range(screen.battle.map.width):
			var c := Vector2i(x, y)
			if not _can_place(c):
				continue
			var d: int = PathfinderRef.manhattan(shooter.cell, c)
			if d <= shooter.attack_range:
				continue
			if d >= best_dist:
				continue
			if not screen.battle.map.has_line_of_sight(shooter.cell, c):
				continue
			best = c
			best_dist = d
	return best


func _count_attack_events(attacker_id: int) -> int:
	## Successful attacks leave an "attack" event in Battle.events; a refused shot
	## must not. Counting by attacker id keeps the check independent of how many
	## earlier events are still queued.
	var n: int = 0
	for ev in screen.battle.events:
		if String(ev.get("type", "")) == "attack" and int(ev.get("attacker", -1)) == attacker_id:
			n += 1
	return n


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
	if save_existed:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(save_backup)
			f.close()
	else:
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
