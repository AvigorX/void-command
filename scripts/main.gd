extends Node2D
## Application root: swaps between menu and battle screens, owns the save file.

const MenuScript = preload("res://scripts/ui/menu_screen.gd")
const BattleScreenScript = preload("res://scripts/ui/battle_screen.gd")
const SaveScript = preload("res://scripts/core/save_data.gd")
## Preloaded (not the global class name): GDScript static vars are shared per script
## RESOURCE, and a class_name reference can resolve to a different instance - which
## would silently bypass the test isolation of the snapshot path.
const BattleSaveRef = preload("res://scripts/core/battle_save.gd")
const FleetScreenScript = preload("res://scripts/ui/fleet_screen.gd")
const FleetPointsScript = preload("res://scripts/core/fleet_points.gd")

var save_data: Dictionary = {}
var current: Node = null


func _ready() -> void:
	save_data = SaveScript.load_data()
	_show_menu()


func _clear_current() -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = null


func _show_menu() -> void:
	_clear_current()
	var menu := MenuScript.new()
	menu.save_data = save_data
	menu.new_battle_requested.connect(func() -> void: _start_new_battle(menu.map_size))
	menu.resume_requested.connect(_resume_saved_battle)
	menu.compose_requested.connect(_show_fleet)
	menu.quit_requested.connect(_quit_game)
	add_child(menu)
	current = menu


func _show_fleet(from_size: Vector2i = MapConfig.REFERENCE) -> void:
	## Composition is a separate entry point (key [F]), so the historical NEW BATTLE path -
	## and every test that drives it - keeps its exact behaviour.
	_clear_current()
	var screen := FleetScreenScript.new()
	screen.map_size = from_size
	screen.confirmed.connect(func(entries: Array, mode: String, size: Vector2i) -> void:
		_start_new_battle(size, entries, FleetPointsScript.budget_of(mode)))
	screen.cancelled.connect(_show_menu)
	add_child(screen)
	current = screen


func _start_new_battle(p_size: Vector2i = MapConfig.REFERENCE, p_fleet: Array = [], p_budget: int = 0) -> void:
	_clear_current()
	var screen := BattleScreenScript.new()
	screen.save_data = save_data
	screen.player_fleet = p_fleet
	screen.fleet_budget = p_budget
	screen.start_seed = 0
	screen.map_size = p_size
	screen.exit_to_menu.connect(_show_menu)
	add_child(screen)
	current = screen


func _resume_saved_battle() -> void:
	## Continues the mid-battle snapshot. The screenshot/snapshot path is separate from
	## the campaign save, so this never touches credits or refits.
	var raw: Dictionary = BattleSaveRef.load_raw()
	if not bool(raw.get("ok", false)):
		_show_menu()
		return
	_clear_current()
	var screen := BattleScreenScript.new()
	screen.save_data = save_data
	screen.start_seed = 0
	screen.resume_data = raw["data"]
	screen.exit_to_menu.connect(_show_menu)
	add_child(screen)
	current = screen


func _quit_game() -> void:
	SaveScript.save_data(save_data)
	get_tree().quit()
