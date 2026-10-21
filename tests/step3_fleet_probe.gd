extends SceneTree
## STEP 3 visual probe — fleet composition screen.
## Requires a real window (no --headless). Frame-driven: SceneTree._initialize cannot await.

const FleetScreenScript = preload("res://scripts/ui/fleet_screen.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")

var screen: Control = null
var frame: int = 0
var checks: int = 0
var failures: int = 0
var out_dir: String = ""


func _initialize() -> void:
	print("=== VOID COMMAND — FLEET COMPOSITION VISUAL EVIDENCE ===")
	out_dir = ProjectSettings.globalize_path("res://") + "../../G-DEV-REPORTS/void-command-step3/"
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			# The root window does not exist yet inside _initialize: build the screen on
			# the first frame, or every later step silently operates on a null.
			root.get_window().size = Vector2i(1280, 720)
			screen = FleetScreenScript.new()
			root.add_child(screen)
		6:
			ok(screen != null, "the screen was created")
			ok(screen.rows().size() == 8, "and it lists all eight classes")
		12:
			_shoot("f01_empty")
			ok(FileAccess.file_exists(out_dir + "f01_empty.png"), "f01_empty.png written")
			for id in ["fighter", "fighter", "frigate", "cruiser"]:
				screen.add_class(id)
			screen.selected_row = 3
		24:
			_shoot("f02_standard_valid")
			ok(FileAccess.file_exists(out_dir + "f02_standard_valid.png"), "f02_standard_valid.png written")
			# M4: every class is playable, so the interesting refusal is a CLASS CAP.
			screen.entries.clear()
			screen.add_class("dreadnought")
			screen.add_class("dreadnought")
			screen.selected_row = screen.rows().find("dreadnought")
		36:
			_shoot("f03_dreadnought_at_cap")
			screen.entries.clear()
			screen.set_mode("grand_fleet")
			for i in range(2):
				screen.add_class("battleship")
			screen.add_class("carrier")
			screen.add_class("carrier")
			screen.add_class("cruiser")
			screen.add_class("cruiser")
			screen.add_class("cruiser")
			screen.set_mode("skirmish")
			screen.confirmed.connect(func(_e: Array, _m: String, _s: Vector2i) -> void:
				ok(false, "an over-budget fleet must not confirm"))
			screen.confirm()
		48:
			_shoot("f04_over_budget")
			screen.set_mode("standard")
			screen.entries.clear()
			for id2 in ["battleship", "cruiser", "frigate"]:
				screen.add_class(id2)
			screen.map_size = MapConfigRef.EXPERIMENTAL
			screen.refresh()
			screen.selected_row = 6
		60:
			_shoot("f05_experimental_board")
			ok(FileAccess.file_exists(out_dir + "f05_experimental_board.png"), "f05_experimental_board.png written")
			print("checks: %d   failures: %d" % [checks, failures])
			print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
			return true
	return false


func _shoot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("  shot %s  %dx%d" % [name, img.get_width(), img.get_height()])


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
