extends SceneTree
## Visual evidence: the shipped capital hull inside the real game window.
## Runs against a scratch save (SaveGuard), so a screenshot run can never touch the
## player's file. Captures: deployment, selection, rotation, movement overlay,
## targeting, an invalid click and the destruction frame.

const SaveGuard = preload("res://tests/save_guard.gd")

var main: Node = null
var screen: Node = null
var frame: int = 0
var checks: int = 0
var failures: int = 0
var out_dir: String = ""
var captured: Array[String] = []
var bs: Ship = null
var real_save_before: Dictionary = {}
var rotate_ok: bool = false
var target_ok: bool = false
var cells_before: int = 0


func _initialize() -> void:
	print("=== VOID COMMAND — STEP1 VISUAL EVIDENCE ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	print("  %s" % SaveGuard.describe(real_save_before))
	out_dir = ProjectSettings.globalize_path("res://") + "../../G-DEV-REPORTS/void-command-step2/"
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
	match frame:
		40:
			main._start_new_battle()
			screen = main.current
			screen._start_battle(20261019)
			for s in screen.battle.ships:
				if s.team == 0 and s.ship_class == "battleship":
					bs = s
		62:
			ok(bs != null, "the fleet contains a battleship")
			if bs != null:
				ok(bs.cells().size() == bs.footprint.x * bs.footprint.y, "it owns its full footprint at deployment (%d cells)" % bs.cells().size())
			_snap("b10_deploy_hull")
		66:
			screen._on_ship_selected(bs.id)
		74:
			ok(screen.view.reachable.size() > 0, "the movement overlay covers %d anchors" % screen.view.reachable.size())
			_snap("b11_selected_hull")
		78:
			var r: Dictionary = screen.battle.rotate_ship(bs.id, 1)
			rotate_ok = bool(r["ok"])
			if not rotate_ok:
				# No room on the spot: move-and-rotate to the first legal anchor.
				for c in screen.battle.reachable_cells(bs.id)["dist"].keys():
					if screen.battle.can_place(c, bs.footprint, 1, bs.id):
						if bool(screen.battle.move_ship(bs.id, c, 1)["ok"]):
							rotate_ok = true
							break
			screen._on_ship_selected(bs.id)
		86:
			ok(rotate_ok, "the hull rotated (in place or at a legal anchor)")
			ok(bs.orientation == 1 and bs.cells().size() == bs.footprint.x * bs.footprint.y, "the rotated hull keeps the same cell count (%d)" % bs.cells().size())
			_snap("b12_rotated_hull")
		90:
			# An invalid click: far outside the movement envelope.
			screen._on_board_click(Vector2i(19, 0))
		96:
			ok(screen.hud.status_text != "", "the HUD reports the refused click: '%s'" % screen.hud.status_text)
			_snap("b12b_invalid_click")
		100:
			# Put a hostile in range so the target bracket has something real to show.
			var foe: Ship = null
			for s in screen.battle.alive_ships(1):
				foe = s
				break
			if foe != null:
				for dx in range(2, 8):
					var anchor: Vector2i = bs.cell + Vector2i(dx, 0)
					if screen.battle.can_place(anchor, foe.footprint, foe.orientation, foe.id):
						foe.cell = anchor
						break
			screen._on_ship_selected(bs.id)
		108:
			var count: int = 0
			for s in screen.battle.alive_ships(1):
				if bool(screen.battle.can_attack(bs.id, s.id)["ok"]):
					count += 1
			target_ok = count > 0
			ok(target_ok, "at least one hostile is a legal target (%d)" % count)
			screen.view.time += 0.4
			screen.view.queue_redraw()
			_snap("b13_targeting")
		114:
			cells_before = screen.battle.occupied().size()
			bs.hull = 0.0
			bs.alive = false
			screen.battle._on_destroyed(bs, null)
			screen.view.queue_redraw()
		122:
			ok(screen.battle.occupied().size() == cells_before - bs.footprint.x * bs.footprint.y, "destruction released the whole hull (%d -> %d)" % [cells_before, screen.battle.occupied().size()])
			_snap("b14_destroyed")
		128:
			_finish()
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
	ok(err == OK, "%s: PNG written" % tag)
	captured.append(path)
	var lit: int = 0
	var total: int = 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			total += 1
			if img.get_pixel(x, y).v > 0.08:
				lit += 1
	var frac: float = float(lit) / float(maxi(1, total))
	ok(frac > 0.05, "%s: the frame is drawn (%.1f%% lit)" % [tag, frac * 100.0])
	print("  %s  lit=%.1f%%" % [tag, frac * 100.0])


func _finish() -> void:
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the probe")
	print("screenshots: %d" % captured.size())
	for p in captured:
		print("  %s" % p)
	SaveGuard.cleanup()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)
