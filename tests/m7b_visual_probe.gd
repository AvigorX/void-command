extends SceneTree
## M7B — visual evidence for the 80x80 board, the compact roster and the spent-actions
## marker. Runs the REAL BattleScreen in a window (not headless: headless draws nothing),
## captures viewport PNGs into `G-DEV-REPORTS/void-command-m7b/` and asserts the frames are
## actually drawn (lit fraction, palette presence), so a black window cannot pass.
##
## Run:
##   $GODOT --path projects/void-command --script res://tests/m7b_visual_probe.gd

const SaveGuard = preload("res://tests/save_guard.gd")
const BattleScreenScript = preload("res://scripts/ui/battle_screen.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")

var screen = null
var frame: int = 0
var checks: int = 0
var failures: int = 0
var out_dir: String = ""
var captured: Array[String] = []


func _initialize() -> void:
	print("=== VOID COMMAND — M7B VISUAL PROBE ===")
	SaveGuard.isolate()
	out_dir = ProjectSettings.globalize_path("res://") + "../../G-DEV-REPORTS/void-command-m7b/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	screen = BattleScreenScript.new()
	# Configure BEFORE the node enters the tree: `_ready` starts the battle immediately.
	screen.map_size = MapConfigRef.TITAN
	screen.start_seed = 424242
	screen.fleet_budget = 200
	screen.player_fleet = _fleet()
	root.add_child(screen)


func _fleet() -> Array:
	## A legal, capital-heavy 200 FP fleet built with the production composition rules.
	var roster: Array[String] = []
	for wanted in ["dreadnought", "battleship", "battleship", "carrier", "cruiser", "cruiser",
			"frigate", "frigate", "destroyer"]:
		if bool(FleetRef.can_add(roster, wanted, 200)["ok"]):
			roster.append(wanted)
	var fillers: Array[String] = ["fighter", "interceptor"]
	var i: int = 0
	while i < 400:
		i += 1
		var cls: String = fillers[i % 2]
		if not bool(FleetRef.can_add(roster, cls, 200)["ok"]):
			break
		roster.append(cls)
	return roster


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 4:
		# `_ready` built a reference battle; restart on the 80x80 board with this fleet.
		screen._start_battle(424242)
	elif frame == 40:
		_snap("01_titan_overview")
	elif frame == 44:
		# Zoom onto the biggest hull: this is the view a player actually plays in.
		var best = null
		for s in screen.battle.alive_ships(0):
			if best == null or s.cells().size() > best.cells().size():
				best = s
		if best != null:
			screen.camera.zoom = Vector2(1.9, 1.9)
			screen.camera.position = screen.view.ship_center(best)
			screen._clamp_camera()
			screen._on_ship_selected(best.id)
	elif frame == 52:
		print("  camera before snap: zoom=%.2f pos=%s" % [screen.camera.zoom.x, str(screen.camera.position)])
		_snap("02_titan_zoom_selected")
	elif frame == 56:
		# Spend the actions of the first eight hulls through the authoritative fields,
		# exactly what the engine sets: this is the marker the player must be able to read.
		var spent: int = 0
		for s in screen.battle.alive_ships(0):
			if spent >= 8:
				break
			s.move_points = 0
			s.has_attacked = true
			spent += 1
		screen.hud.refresh()
		screen.view.queue_redraw()
	elif frame == 64:
		_snap("03_titan_spent_actions")
	elif frame == 68:
		screen._fit_view()
	elif frame == 74:
		_snap("04_titan_home_fit")
	elif frame == 78:
		# The roster with more hulls than the band: compact rows and the scroll affordance.
		screen.hud.roster_scroll_by(6)
	elif frame == 84:
		_snap("05_titan_roster_scrolled")
	elif frame == 88:
		# A small board for comparison, same code path.
		screen.map_size = MapConfigRef.REFERENCE
		screen.fleet_budget = 0
		screen.player_fleet = []
		screen._start_battle(20261020)
	elif frame == 100:
		_snap("06_reference_board")
	elif frame == 104:
		_finish()
		return false
	return false


func _finish() -> void:
	print("")
	print("  captured %d frames" % captured.size())
	for p in captured:
		print("    %s" % p)
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	SaveGuard.cleanup()
	quit(0 if failures == 0 else 1)


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
	print("  %s  lit=%.1f%%  colors=%d  cyan=%d  orange=%d  mean=%.3f" % [
		tag, float(stats["lit"]) * 100.0, int(stats["colors"]),
		int(stats["cyan"]), int(stats["orange"]), float(stats["mean"])])
	ok(float(stats["lit"]) > 0.30, "%s: the frame is not black (%.1f%% lit)" % [tag, float(stats["lit"]) * 100.0])
	ok(int(stats["colors"]) > 120, "%s: the palette is present (%d colours)" % [tag, int(stats["colors"])])
	ok(int(stats["cyan"]) > 300, "%s: the cyan HUD identity is drawn (%d px)" % [tag, int(stats["cyan"])])


func _analyze(img: Image) -> Dictionary:
	var total: int = img.get_width() * img.get_height()
	var lit: int = 0
	var cyan: int = 0
	var orange: int = 0
	var sum: float = 0.0
	var palette: Dictionary = {}
	var step: int = 3
	var sampled: int = 0
	var x: int = 0
	while x < img.get_width():
		var y: int = 0
		while y < img.get_height():
			var c: Color = img.get_pixel(x, y)
			sampled += 1
			# Same "non-black" definition as `visual_probe.gd`: this game is deliberately
			# dark, so a luma threshold would call a normal battle screen black.
			var lum: float = c.r * 0.3 + c.g * 0.55 + c.b * 0.15
			sum += lum
			if c.r > 0.03 or c.g > 0.03 or c.b > 0.05:
				lit += 1
			if c.b > 0.45 and c.g > 0.40 and c.r < 0.45 and c.b > c.r + 0.12:
				cyan += 1
			if c.r > 0.45 and c.r > c.b + 0.15 and c.g < c.r:
				orange += 1
			palette[(int(c.r * 15.0) << 8) | (int(c.g * 15.0) << 4) | int(c.b * 15.0)] = true
			y += step
		x += step
	sampled = maxi(1, sampled)
	return {
		"total": img.get_width() * img.get_height(), "lit": float(lit) / float(sampled),
		"colors": palette.size(), "cyan": cyan, "orange": orange, "mean": sum / float(sampled),
	}


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
