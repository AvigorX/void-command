extends SceneTree
## STEP 2 / Block C visual evidence: the Fighter reads as a small squadron on ONE cell.
##
## Captures the cases the mandate asks for: unselected, selected, mid-move, beside a
## capital hull, with the tactical overlays on, and on BOTH battlefield sizes. Runs
## behind SaveGuard so a screenshot run can never touch the player's save.

const SaveGuard = preload("res://tests/save_guard.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")

var main: Node = null
var screen: Node = null
var frame: int = 0
var checks: int = 0
var failures: int = 0
var out_dir: String = ""
var captured: Array[String] = []
var fighter: Ship = null
var big: Ship = null
var real_save_before: Dictionary = {}
var start_cell: Vector2i = Vector2i.ZERO


func _initialize() -> void:
	print("=== VOID COMMAND — FIGHTER SQUADRON VISUAL EVIDENCE ===")
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
		30:
			main._start_new_battle(MapConfigRef.REFERENCE)
			screen = main.current
			screen._start_battle(20261019)
			for s in screen.battle.ships:
				if s.team == 0 and s.ship_class == "fighter" and fighter == null:
					fighter = s
				if s.team == 0 and s.ship_class == "battleship":
					big = s
		40:
			ok(fighter != null, "the fleet contains a fighter")
			ok(big != null, "the fleet contains a capital hull")
			ok(fighter.footprint == Vector2i.ONE, "the fighter is still 1x1 on the grid")
			ok(fighter.cells().size() == 1, "it occupies exactly one cell")
			screen._on_ship_selected(-1)
			screen.view.queue_redraw()
		48:
			_snap("f01_fighter_idle")
		52:
			screen._on_ship_selected(fighter.id)
		60:
			ok(screen.view.reachable.size() > 4, "the movement overlay covers %d anchors" % screen.view.reachable.size())
			_snap("f02_fighter_selected")
		64:
			# Park a capital hull one cell away so both silhouettes share the frame.
			if big != null:
				start_cell = fighter.cell
				big.cell = fighter.cell + Vector2i(2, 0)
				big.set_orientation(0)
				if not screen.battle.can_place(big.cell, big.footprint, 0, big.id):
					for dx in range(2, 6):
						var c: Vector2i = fighter.cell + Vector2i(dx, 0)
						if screen.battle.can_place(c, big.footprint, 0, big.id):
							big.cell = c
							break
				screen.view.queue_redraw()
		72:
			_snap("f03_fighter_beside_capital")
		76:
			# Mid-move: issue a one-cell order and snapshot while the hull is lerping.
			var dest: Vector2i = fighter.cell + Vector2i(0, 1)
			var moved: Dictionary = screen.battle.move_ship(fighter.id, dest)
			ok(bool(moved["ok"]), "a one-cell fighter move is accepted (%s)" % String(moved.get("reason", "")))
			screen.view.set_process(true)
		78:
			_snap("f04_fighter_moving")
		84:
			# Overlays: movement envelope plus the attack bracket on a hostile.
			var foe: Ship = null
			for s in screen.battle.alive_ships(1):
				foe = s
				break
			if foe != null and fighter != null:
				for dx in range(1, 4):
					var c2: Vector2i = fighter.cell + Vector2i(dx, 0)
					if screen.battle.can_place(c2, foe.footprint, foe.orientation, foe.id):
						foe.cell = c2
						break
			screen._on_ship_selected(fighter.id)
			screen.view.time += 0.5
			screen.view.queue_redraw()
		92:
			_snap("f05_fighter_overlays")
		98:
			# Same subject on the experimental battlefield.
			main._start_new_battle(MapConfigRef.EXPERIMENTAL)
			screen = main.current
			screen._start_battle(20261020)
			fighter = null
			for s in screen.battle.ships:
				if s.team == 0 and s.ship_class == "fighter" and fighter == null:
					fighter = s
		108:
			ok(fighter != null, "a fighter deployed on the 32x22 board")
			ok(screen.battle.map.width == 32 and screen.battle.map.height == 22, "the board is 32x22")
			ok(is_equal_approx(screen.view.cell_px, 29.0), "the cell shrank to %.1f px so the board fits" % screen.view.cell_px)
			screen._on_ship_selected(fighter.id)
		116:
			_snap("f06_fighter_on_32x22")
		120:
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
