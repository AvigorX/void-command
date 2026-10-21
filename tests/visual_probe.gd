extends SceneTree
## Visual evidence probe: runs the real game windowed, captures viewport PNGs,
## and verifies pixels are actually drawn (not a black screen).
## S0: it also runs against a scratch save, so a screenshot run can never award
## credits or increment the player's battle statistics.

const SaveGuard = preload("res://tests/save_guard.gd")

var main: Node = null
var screen: Node = null
var frame: int = 0
var checks: int = 0
var failures: int = 0
var out_dir: String = ""
var captured: Array[String] = []
var result_frame: int = 0
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — VISUAL PROBE ===")
	# Must happen before Main.tscn is instantiated: the menu loads the save in _ready().
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	print("  %s" % SaveGuard.describe(real_save_before))
	out_dir = ProjectSettings.globalize_path("res://") + "../../G-DEV-REPORTS/void-command/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func ok(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL  %s" % label)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 12:
		main.current._set_mode("controls")
	elif frame == 18:
		_snap("01b_controls")
	elif frame == 22:
		main.current._set_mode("upgrades")
	elif frame == 28:
		_snap("01c_upgrades")
	elif frame == 32:
		main.current._set_mode("main")
	elif frame == 36:
		_snap("01_menu")
	elif frame == 40:
		main._start_new_battle()
		screen = main.current
		screen._start_battle(20261019)
	elif frame == 62:
		## M7B: every living hull must be on screen INSIDE the play area. This is the check
		## that would have caught the camera framing the viewport instead of the play area:
		## the enemy fleet used to be drawn at screen x = 1024, behind the HUD panel.
		var play: Rect2 = Rect2(screen.PLAY_ORIGIN, screen.PLAY_AREA)
		var hidden: Array[String] = []
		for s in screen.battle.alive_ships(1):
			var world: Vector2 = screen.view.ship_center(s)
			var on_screen: Vector2 = Vector2(1280.0, 720.0) * 0.5 + (world - screen.camera.position) * screen.camera.zoom.x
			if not play.has_point(on_screen):
				hidden.append("%s at %s" % [s.ship_class, str(on_screen.round())])
		ok(hidden.is_empty(), "the enemy fleet is on screen, left of the HUD (%s)" % ", ".join(hidden))
		_snap("02_battle")
	elif frame == 66:
		var fighter: Ship = null
		for s in screen.battle.alive_ships(0):
			if s.ship_class == "fighter":
				fighter = s
				break
		if fighter != null:
			screen._on_ship_selected(fighter.id)
		elif screen.battle.alive_ships(0).size() > 0:
			screen._on_ship_selected(screen.battle.alive_ships(0)[0].id)
	elif frame == 74:
		_snap("03_selection")
	elif frame == 78:
		# Force a close-range engagement so weapon effects can be captured.
		if screen.battle.selected_id >= 0:
			var sel: Ship = screen.battle.selected_ship()
			var enemy: Ship = screen.battle.alive_ships(1)[0]
			if sel != null and enemy != null:
				var spot: Vector2i = sel.cell + Vector2i(1, 0)
				if screen.battle.map.in_bounds(spot) and not screen.battle.map.is_blocked(spot) and screen.view.ship_at(spot) == null:
					enemy.cell = spot
	elif frame == 82:
		if screen.battle.selected_id >= 0:
			var enemy2: Ship = screen.battle.alive_ships(1)[0]
			if enemy2 != null:
				screen._on_board_click(enemy2.cell)
	elif frame == 86:
		_snap("04_combat")
	elif frame == 90:
		screen._toggle_pause()
	elif frame == 94:
		_snap("06_pause")
	elif frame == 98:
		screen._resume()
		screen._on_end_turn()
	elif frame == 106:
		_snap("05_enemy_turn")
	elif frame == 110:
		for s in screen.battle.alive_ships(1):
			s.hull = 0.0
			s.alive = false
		screen.battle._check_outcome()
		screen.battle.events.clear()
		screen.view.event_queue.clear()
		screen.view.event_timer = 0.0
	elif frame > 112 and screen.overlay != null and String(screen.overlay.mode) == "result":
		if result_frame == 0:
			result_frame = frame
		elif frame >= result_frame + 4:
			_snap("07_result")
			_finish()
			return true
	elif frame > 400:
		ok(false, "result overlay captured before timeout")
		_finish()
		return true
	return false


func _snap(tag: String) -> void:
	RenderingServer.force_draw()
	var img: Image = root.get_texture().get_image()
	if img == null:
		ok(false, "%s: viewport image available" % tag)
		return
	if img.get_width() != 1280 or img.get_height() != 720:
		img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	var path: String = out_dir + "shot_%s.png" % tag
	var err: int = img.save_png(path)
	ok(err == OK, "%s: PNG written (%s)" % [tag, path])
	captured.append(path)
	var stats: Dictionary = _analyze(img)
	print("  %s  pixels=%d  lit=%.1f%%  colors=%d  cyan=%d  orange=%d  mean=%.3f" % [
		tag, int(stats["total"]), float(stats["lit"]) * 100.0, int(stats["colors"]),
		int(stats["cyan"]), int(stats["orange"]), float(stats["mean"])])
	var min_lit: float = 0.50
	var min_cyan: int = 300
	var min_colors: int = 120
	if tag == "01_menu" or tag.begins_with("01b") or tag.begins_with("01c"):
		min_lit = 0.25
		min_cyan = 150
		min_colors = 60
	elif tag == "06_pause" or tag == "07_result":
		min_lit = 0.18
		min_cyan = 150
		min_colors = 60
	ok(float(stats["lit"]) > min_lit, "%s: the screen is not black (lit %.1f%%)" % [tag, float(stats["lit"]) * 100.0])
	ok(int(stats["colors"]) > min_colors, "%s: rich procedural palette (%d colours)" % [tag, int(stats["colors"])])
	ok(int(stats["cyan"]) > min_cyan, "%s: cyan UI/engine accents present (%d px)" % [tag, int(stats["cyan"])])
	if tag.find("battle") >= 0 or tag.find("selection") >= 0 or tag.find("combat") >= 0 or tag.find("enemy") >= 0:
		ok(int(stats["orange"]) > 40, "%s: hostile fleet rendered (%d warm px)" % [tag, int(stats["orange"])])
		var warm_right: int = _count_warm(img, Rect2i(560, 54, 380, 640))
		var cyan_left: int = _count_cyan(img, Rect2i(24, 54, 320, 640))
		ok(warm_right > 40, "%s: hostile hulls inside the board, not under the HUD (%d px)" % [tag, warm_right])
		ok(cyan_left > 30, "%s: friendly hulls inside the west deployment zone (%d px)" % [tag, cyan_left])


func _count_warm(img: Image, rect: Rect2i) -> int:
	var n: int = 0
	for y in range(rect.position.y, mini(rect.end.y, img.get_height()), 2):
		for x in range(rect.position.x, mini(rect.end.x, img.get_width()), 2):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.45 and c.r > c.b + 0.14 and c.g < c.r:
				n += 1
	return n


func _count_cyan(img: Image, rect: Rect2i) -> int:
	var n: int = 0
	for y in range(rect.position.y, mini(rect.end.y, img.get_height()), 2):
		for x in range(rect.position.x, mini(rect.end.x, img.get_width()), 2):
			var c: Color = img.get_pixel(x, y)
			if c.b > 0.40 and c.g > 0.35 and c.b > c.r + 0.10:
				n += 1
	return n


func _analyze(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var total: int = 0
	var lit: int = 0
	var cyan: int = 0
	var orange: int = 0
	var sum: float = 0.0
	var palette: Dictionary = {}
	var step: int = 3
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c: Color = img.get_pixel(x, y)
			total += 1
			var lum: float = c.r * 0.3 + c.g * 0.55 + c.b * 0.15
			sum += lum
			if c.r > 0.03 or c.g > 0.03 or c.b > 0.05:
				lit += 1
			if c.b > 0.45 and c.g > 0.40 and c.r < 0.45 and c.b > c.r + 0.12:
				cyan += 1
			if c.r > 0.45 and c.r > c.b + 0.15 and c.g < c.r:
				orange += 1
			var key: int = (int(c.r * 15.0) << 8) | (int(c.g * 15.0) << 4) | int(c.b * 15.0)
			palette[key] = true
	return {
		"total": total,
		"lit": float(lit) / float(maxi(1, total)),
		"colors": palette.size(),
		"cyan": cyan,
		"orange": orange,
		"mean": sum / float(maxi(1, total)),
	}


func _finish() -> void:
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the probe")
	print("")
	print("captured %d screenshots" % captured.size())
	print("checks: %d   failures: %d" % [checks, failures])
	SaveGuard.cleanup()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)
