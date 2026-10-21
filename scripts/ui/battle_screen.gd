extends Node2D
## Battle screen: owns the Battle instance, the view, the HUD, input and screen flow.

signal exit_to_menu
signal battle_recorded(victory: bool, credits: int, seed_value: int)

const BattleScript = preload("res://scripts/core/battle.gd")
const SaveScript = preload("res://scripts/core/save_data.gd")
## Preloaded (not the global class name): GDScript static vars are shared per script
## RESOURCE, and a class_name reference can resolve to a different instance - which
## would silently bypass the test isolation of the snapshot path.
const BattleSaveRef = preload("res://scripts/core/battle_save.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const HudScript = preload("res://scripts/ui/hud.gd")
const StarfieldScript = preload("res://scripts/ui/starfield.gd")
const OverlayScript = preload("res://scripts/ui/overlay.gd")

const CAM_CENTER := Vector2(640, 360)
## ZOOM_MIN has to be low enough to read a 48x34 board as a whole and high enough to
## read a 1x1 hull's silhouette; 0.60/2.40 covers both without pixel mush at 19 px cells.
const ZOOM_MIN := 0.60
const ZOOM_MAX := 2.40
const PLAY_ORIGIN := Vector2(24, 54)
const PLAY_AREA := Vector2(928, 666)


func _viewport_centre() -> Vector2:
	var size: Vector2 = get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(1280.0, 720.0)
	return size * 0.5


func _play_offset() -> Vector2:
	## A Camera2D centres its VIEWPORT, but the board has to be centred on the PLAY AREA -
	## the 928x666 region left of the HUD panel. The two centres are 152 px apart in screen
	## space, and ignoring that difference shifted the whole board to the right: on the
	## reference 20x14 board the enemy fleet was drawn at screen x = 1024, i.e. BEHIND the
	## HUD panel, where it can neither be seen nor clicked (measured, M7B).
	##
	## `camera.position` must therefore sit this offset away from the board point that has
	## to land on the play-area centre. Everything below is expressed through it.
	return (PLAY_ORIGIN + PLAY_AREA * 0.5 - _viewport_centre()) / camera.zoom

var save_data: Dictionary = {}
var start_seed: int = 0
var battle: Battle
var view: Node2D
var hud: Control
var camera: Camera2D
var starfield: Control
var overlay: Control
var ui_layer: CanvasLayer
var paused: bool = false
var reward_committed: bool = false
var ability_armed: bool = false
var ability_ship_id: int = -1
var dragging: bool = false
var drag_last: Vector2 = Vector2.ZERO
var enemy_turn_pending: bool = false
## Battlefield this screen builds (STEP 2 / Block B); the menu sets it.
var map_size: Vector2i = MapConfig.REFERENCE
## Snapshot to resume instead of starting a new battle (empty = new battle).
var resume_data: Dictionary = {}
## A composed fleet (STEP 3). Empty means the historical roster.
var player_fleet: Array = []
## Fleet-point budget for the enemy generator; 0 means "historical enemy fleets".
var fleet_budget: int = 0
var saved_round: int = -1


func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	camera = Camera2D.new()
	camera.position = CAM_CENTER
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	var sky := CanvasLayer.new()
	sky.layer = -5
	add_child(sky)
	starfield = StarfieldScript.new()
	starfield.position = Vector2.ZERO
	starfield.size = Vector2(1280, 720)
	starfield.setup(start_seed)
	sky.add_child(starfield)

	view = ViewScript.new()
	add_child(view)

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 1
	add_child(ui_layer)
	hud = HudScript.new()
	ui_layer.add_child(hud)
	hud.ship_selected.connect(_on_ship_selected)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.ability_pressed.connect(_on_ability)
	hud.wait_pressed.connect(_on_wait)
	hud.menu_pressed.connect(_toggle_pause)

	if not resume_data.is_empty():
		_resume_battle()
	else:
		_start_battle(start_seed)


func _enemy_roster(seed_value: int) -> Array:
	## A composed battle fields a generated enemy fleet inside the same budget, on the same
	## board. No budget means the historical difficulty-based rosters, untouched.
	if fleet_budget <= 0:
		return []
	var gen: Dictionary = FleetRef.generate_enemy(seed_value, fleet_budget, map_size)
	return gen["entries"]


func _resume_battle() -> void:
	## Continues a saved battle instead of deploying a new one. A snapshot that cannot be
	## restored falls back to a fresh battle with the reason in the status line - never a
	## half-restored board.
	var res: Dictionary = BattleSaveRef.restore(resume_data)
	if not bool(res.get("ok", false)):
		_start_battle(start_seed)
		hud.set_status("Battle save unreadable (%s) - new battle started." % String(res.get("reason", "")), true)
		return
	battle = res["battle"]
	view.setup(battle)
	hud.setup(battle)
	starfield.setup(battle.seed_value)
	# Fit the board instead of assuming zoom 1: a 48x34 board at 19 px cells needs a
	# different framing than the reference board, and the camera must never open on a
	# corner of the map.
	_reset_camera()
	paused = false
	reward_committed = battle.reward_granted
	enemy_turn_pending = false
	resume_data = {}
	saved_round = battle.round
	_cancel_ability()
	_close_overlay()
	view.refresh_overlays()
	hud.refresh()
	hud.set_status("Battle resumed - round %d." % battle.round)


func _autosave() -> void:
	## One snapshot per round, so leaving mid-battle never loses progress. It is a
	## separate file from the campaign save and it is deleted when the battle ends.
	if battle == null or battle.outcome != "":
		return
	if battle.round == saved_round:
		return
	saved_round = battle.round
	BattleSaveRef.save_battle(battle)


func _start_battle(p_seed: int) -> void:
	var seed_value: int = p_seed
	if seed_value <= 0:
		seed_value = int(Time.get_unix_time_from_system()) % 999983
	var stats: Dictionary = save_data.get("stats", {})
	var wins: int = int(stats.get("wins", 0))
	var difficulty: int = 1 + clampi(wins / 2, 0, 3)
	battle = BattleScript.new()
	battle.setup(seed_value, save_data.get("upgrades", {}), difficulty, map_size,
		player_fleet, _enemy_roster(seed_value))
	saved_round = -1
	view.setup(battle)
	hud.setup(battle)
	starfield.setup(seed_value)
	# Fit the board instead of assuming zoom 1: a 48x34 board at 19 px cells needs a
	# different framing than the reference board, and the camera must never open on a
	# corner of the map.
	_reset_camera()
	paused = false
	reward_committed = false
	enemy_turn_pending = false
	_cancel_ability()
	_close_overlay()
	save_data["last_seed"] = seed_value
	hud.set_status("Select a ship, then move or fire.")
	hud.refresh()
	view.refresh_overlays()


func _process(delta: float) -> void:
	if battle == null or view == null:
		return
	_update_hover()
	if not paused and overlay == null:
		var pan := Vector2.ZERO
		if Input.is_action_pressed("pan_left"):
			pan.x -= 1.0
		if Input.is_action_pressed("pan_right"):
			pan.x += 1.0
		if Input.is_action_pressed("pan_up"):
			pan.y -= 1.0
		if Input.is_action_pressed("pan_down"):
			pan.y += 1.0
		if pan != Vector2.ZERO:
			camera.position += pan.normalized() * 320.0 * delta
			_clamp_camera()
	if enemy_turn_pending and not view.is_busy():
		enemy_turn_pending = false
		hud.set_status("Your move." if battle.outcome == "" else "")
		hud.refresh()
	# One snapshot per round: leaving mid-battle never loses progress, and it is a
	# separate file from the campaign save (see BattleSave).
	_autosave()
	if battle.outcome != "" and overlay == null and not view.is_busy():
		_show_result()


func _update_hover() -> void:
	var screen_pos: Vector2 = get_viewport().get_mouse_position()
	if screen_pos.x >= 952.0:
		view.hover_cell = Vector2i(-1, -1)
		view.hover_ship_id = -1
		hud.hover_ship_id = -1
		return
	var world: Vector2 = view.get_global_mouse_position()
	var cell: Vector2i = view.world_to_cell(world)
	if battle.map.in_bounds(cell):
		view.hover_cell = cell
		var s: Ship = view.ship_at(cell)
		view.hover_ship_id = s.id if s != null else -1
		hud.hover_ship_id = view.hover_ship_id
		hud.hover_cell = cell
	else:
		view.hover_cell = Vector2i(-1, -1)
		view.hover_ship_id = -1
		hud.hover_ship_id = -1


func _unhandled_input(event: InputEvent) -> void:
	if battle == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_HOME:
			_fit_view()
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_R:
			_recenter()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause_menu"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused or overlay != null:
		return
	if event.is_action_pressed("end_turn"):
		_on_end_turn()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("next_ship"):
		_cycle_ship()
		return
	if event.is_action_pressed("ability"):
		_on_ability()
		return
	if event.is_action_pressed("wait_ship"):
		_on_wait()
		return
	if event.is_action_pressed("rotate_cw"):
		_rotate_selected()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.10, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.10, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			drag_last = mb.position
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.position.x < 952.0:
			_on_board_click()
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		camera.position -= mm.relative / camera.zoom
		_clamp_camera()


func _zoom_by(factor: float, focus: Vector2 = Vector2(-1.0, -1.0)) -> void:
	## Zoom around a FOCUS POINT, not around the screen centre: the world point under the
	## cursor has to stay under the cursor, otherwise zooming in slides the region the
	## player is looking at out of view.
	##
	## With Camera2D and no rotation the mapping is  world = camera.position + (screen -
	## viewport/2) / zoom, so inverting it after the zoom change keeps that point fixed.
	var before: float = camera.zoom.x
	var target: float = clampf(before * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(target, before):
		return
	var screen: Vector2 = focus
	if screen.x < 0.0:
		screen = Vector2(1280.0, 720.0) * 0.5
	var centre: Vector2 = Vector2(1280.0, 720.0) * 0.5
	var world: Vector2 = camera.position + (screen - centre) / before
	camera.zoom = Vector2(target, target)
	camera.position = world - (screen - centre) / target
	_clamp_camera()


func _fit_view() -> void:
	## Whole board in the play area, left of the HUD panel.
	if view == null or battle == null:
		return
	var span := Vector2(maxf(1.0, view.board_w), maxf(1.0, view.board_h))
	var z: float = minf(PLAY_AREA.x / (span.x + 16.0), PLAY_AREA.y / (span.y + 16.0))
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.position = PLAY_ORIGIN + span * 0.5 - _play_offset()
	_clamp_camera()


func _recenter() -> void:
	## Keep the current zoom, put the middle of the board in the middle of the play area.
	if view == null or battle == null:
		return
	camera.position = PLAY_ORIGIN + Vector2(view.board_w, view.board_h) * 0.5 - _play_offset()
	_clamp_camera()


func _reset_camera() -> void:
	camera.zoom = Vector2.ONE
	camera.position = CAM_CENTER
	_fit_view()


func _clamp_camera() -> void:
	## Pan limits are derived from the board, never hardcoded for the reference size.
	##
	## `focus` is the BOARD POINT that lands on the play-area centre on screen; the camera
	## position is `focus - _play_offset()`. Clamping `camera.position` directly was what
	## pushed the board behind the HUD: the play area's centre is not the viewport's centre.
	var offset: Vector2 = _play_offset()
	var half: Vector2 = PLAY_AREA * 0.5 / camera.zoom
	var b0: Vector2 = view.ORIGIN
	var b1: Vector2 = b0 + Vector2(view.board_w, view.board_h)
	var board_centre: Vector2 = (b0 + b1) * 0.5
	var focus: Vector2 = camera.position + offset
	if view.board_w > half.x * 2.0:
		focus.x = clampf(focus.x, b0.x + half.x, b1.x - half.x)
	else:
		# A board narrower than the play area is centred on it, but never at the cost of
		# cutting its edge columns.
		focus.x = clampf(board_centre.x, b1.x - half.x, b0.x + half.x)
	if view.board_h > half.y * 2.0:
		focus.y = clampf(focus.y, b0.y + half.y, b1.y - half.y)
	else:
		focus.y = clampf(board_centre.y, b1.y - half.y, b0.y + half.y)
	camera.position = focus - offset


func _on_board_click(target_cell: Vector2i = Vector2i(-999, -999)) -> void:
	if enemy_turn_pending:
		hud.set_status("Enemy fleet is manoeuvring — hold.", true)
		return
	if battle.phase != Battle.Phase.PLAYER or battle.outcome != "":
		hud.set_status("Command authority suspended during the enemy phase.", true)
		return
	var cell: Vector2i = target_cell
	if cell.x == -999:
		var world: Vector2 = view.get_global_mouse_position()
		cell = view.world_to_cell(world)
	if not battle.map.in_bounds(cell):
		return
	var clicked: Ship = view.ship_at(cell)
	if ability_armed:
		_resolve_ability_click(clicked, cell)
		return
	if clicked != null and clicked.team == 0:
		_on_ship_selected(clicked.id)
		return
	if clicked != null and clicked.team == 1:
		if battle.selected_id < 0:
			hud.set_status("Select a friendly ship first.", true)
			return
		var res: Dictionary = battle.attack(battle.selected_id, clicked.id)
		if bool(res["ok"]):
			hud.set_status("Firing solution executed.")
		else:
			hud.set_status(String(res["reason"]), true)
		_after_action()
		return
	# Empty cell: movement order.
	if battle.selected_id < 0:
		hud.set_status("No ship selected.", true)
		return
	var sel := battle.selected_ship()
	if sel == null:
		return
	if not view.reachable.has(cell):
		if battle.map.is_blocked(cell):
			hud.set_status("%s is impassable." % battle.map.terrain_name(cell), true)
		elif view.ship_at(cell) != null:
			hud.set_status("Cell occupied.", true)
		else:
			hud.set_status("Out of movement range.", true)
		return
	var dest_ori: int = int(view.reachable_ori.get(cell, sel.orientation))
	var mv: Dictionary = battle.move_ship(sel.id, cell, dest_ori)
	if bool(mv["ok"]):
		# STEP 2: the order carries the orientation the overlay showed, so a hull that
		# has to turn to fit arrives instead of being refused on a highlighted cell.
		var turns: int = int(mv.get("turns", 0))
		if turns > 0:
			hud.set_status("Moved %d cells, turned %d time(s) (%d MP left)." % [
				int(mv["cost"]), turns, sel.move_points])
		else:
			hud.set_status("Moved %d cells (%d MP left)." % [int(mv["cost"]), sel.move_points])
	else:
		hud.set_status(String(mv["reason"]), true)
	_after_action()


func _rotate_selected() -> void:
	## Explicit rotation order (R). Rotation is free and must not clip; the rules
	## layer refuses it and leaves the hull untouched when it does not fit.
	if battle == null or battle.phase != Battle.Phase.PLAYER:
		return
	var sel := battle.selected_ship()
	if sel == null or not sel.alive:
		hud.set_status("No ship selected.", true)
		return
	var res: Dictionary = battle.rotate_ship(sel.id, (sel.orientation + 1) % 4)
	if bool(res["ok"]):
		var e: Vector2i = FootprintRef.extent(sel.footprint, sel.orientation)
		hud.set_status("%s rotated: now %d×%d on the grid ([T] again to continue)." % [
			sel.display_name, e.x, e.y])
	else:
		hud.set_status("Rotation refused: %s" % String(res["reason"]), true)
	_after_action()


func _on_ship_selected(id: int) -> void:
	if battle == null or battle.phase != Battle.Phase.PLAYER:
		return
	if not battle.select(id):
		hud.set_status(battle.last_message, true)
		return
	_cancel_ability()
	view.refresh_overlays()
	hud.refresh()
	var s := battle.selected_ship()
	if s != null:
		hud.set_status("%s ready: %d MP, weapon range %d." % [s.display_name, s.move_points, s.attack_range])


func _cycle_ship() -> void:
	if battle == null or battle.phase != Battle.Phase.PLAYER:
		return
	var alive := battle.alive_ships(0)
	if alive.is_empty():
		return
	var index: int = 0
	for i in range(alive.size()):
		if alive[i].id == battle.selected_id:
			index = (i + 1) % alive.size()
			break
	_on_ship_selected(alive[index].id)


func _on_ability() -> void:
	if battle == null or paused or overlay != null:
		return
	if enemy_turn_pending:
		hud.set_status("Enemy fleet is manoeuvring — hold.", true)
		return
	if battle.phase != Battle.Phase.PLAYER:
		hud.set_status("Not your turn.", true)
		return
	var sel := battle.selected_ship()
	if sel == null:
		hud.set_status("Select a ship first.", true)
		return
	if ability_armed:
		_cancel_ability()
		hud.set_status("Ability targeting cancelled.")
		return
	var kind := String(sel.ability.get("kind", ""))
	if kind == "evade":
		_use_ability(sel.id, -1)
		return
	var targets: Array[Ship] = battle.ability_targets(sel.id)
	if targets.is_empty():
		hud.set_status("No valid %s target." % sel.ability_name(), true)
		return
	ability_armed = true
	ability_ship_id = sel.id
	hud.ability_armed = true
	view.armed_ability = true
	view.highlight_targets(targets)
	view.queue_redraw()
	hud.set_status("Select a target for %s." % sel.ability_name())
	hud.refresh()


func _resolve_ability_click(clicked: Ship, cell: Vector2i) -> void:
	var sel := battle.get_ship(ability_ship_id)
	if sel == null:
		_cancel_ability()
		return
	var target_id: int = -1
	if clicked != null and view.ability_highlight.has(cell):
		target_id = clicked.id
	elif clicked != null and clicked.id == sel.id and view.ability_highlight.has(cell):
		target_id = sel.id
	if target_id < 0:
		hud.set_status("Invalid ability target.", true)
		return
	_use_ability(sel.id, target_id)


func _use_ability(ship_id: int, target_id: int) -> void:
	var res: Dictionary = battle.use_ability(ship_id, target_id)
	if bool(res["ok"]):
		hud.set_status("%s engaged." % battle.get_ship(ship_id).ability_name())
	else:
		hud.set_status(String(res["reason"]), true)
	_cancel_ability()
	_after_action()


func _cancel_ability() -> void:
	ability_armed = false
	ability_ship_id = -1
	if hud != null:
		hud.ability_armed = false
	if view != null:
		view.armed_ability = false
		view.ability_highlight.clear()
		view.queue_redraw()


func _on_wait() -> void:
	if battle == null or paused or overlay != null:
		return
	if enemy_turn_pending:
		hud.set_status("Enemy fleet is manoeuvring — hold.", true)
		return
	if battle.selected_id < 0:
		hud.set_status("Select a ship first.", true)
		return
	if battle.wait_ship(battle.selected_id):
		hud.set_status("Ship holds position.")
	else:
		hud.set_status("Ship cannot hold here.", true)
	_after_action()


func _on_end_turn() -> void:
	if battle == null or paused or overlay != null:
		return
	if enemy_turn_pending:
		return
	if battle.phase != Battle.Phase.PLAYER or battle.outcome != "":
		hud.set_status("Cannot end the turn now.", true)
		return
	_cancel_ability()
	var ok: bool = battle.end_turn()
	if not ok:
		return
	enemy_turn_pending = true
	hud.set_status("Enemy fleet executing orders...")
	hud.refresh()
	view.refresh_overlays()


func _after_action() -> void:
	if battle == null:
		return
	view.refresh_overlays()
	hud.refresh()
	# Drop a stale selection if the ship died.
	if battle.selected_id >= 0:
		var s := battle.get_ship(battle.selected_id)
		if s == null or not s.alive:
			battle.selected_id = -1


func _toggle_pause() -> void:
	if overlay != null:
		return
	paused = not paused
	if paused:
		_show_pause()
	else:
		_close_overlay()


func _show_pause() -> void:
	_close_overlay()
	overlay = OverlayScript.new()
	ui_layer.add_child(overlay)
	overlay.setup("pause", "PAUSED", "Simulation halted — no orders accepted.", [
		"Resume to continue the current battle.",
		"Restart deploys a fresh seeded map.",
		"",
		"Controls: click to select/move/fire · Q ability · W hold",
		"Tab next ship · Space end turn · Esc pause · wheel zoom",
	], Color(0.50, 0.88, 1.0))
	overlay.primary_pressed.connect(_resume)
	overlay.secondary_pressed.connect(_restart)
	overlay.tertiary_pressed.connect(_to_menu)


func _resume() -> void:
	paused = false
	_close_overlay()


func _restart() -> void:
	paused = false
	_close_overlay()
	_start_battle(battle.seed_value + 7919)


func _to_menu() -> void:
	exit_to_menu.emit()


func _show_result() -> void:
	# The battle is over: a resumable snapshot would only resurrect a finished fight.
	BattleSaveRef.clear()
	var victory: bool = battle.outcome == "victory"
	var reward: Dictionary = battle.compute_reward()
	var sum: Dictionary = battle.summary()
	var lines: Array[String] = []
	lines.append("Round %d   ·   seed %d" % [int(sum["rounds"]), int(sum["seed"])])
	lines.append("Hostiles destroyed %d   ·   ships lost %d" % [int(sum["enemy_destroyed"]), int(sum["player_lost"])])
	if bool(sum["control_bonus"]):
		lines.append("Relay station secured — strategic objective complete.")
	lines.append("")
	for l in reward["lines"]:
		lines.append(String(l))
	lines.append("")
	lines.append("+%d CREDITS BANKED" % int(reward["credits"]))
	var title: String = "VICTORY" if victory else "DEFEAT"
	var subtitle: String = "Sector cleared. Fleet command authorises a new deployment." if victory else "Fleet annihilated. Command recalls the survivors."
	var accent: Color = Color(0.45, 0.95, 1.0) if victory else Color(1.0, 0.55, 0.42)
	if not reward_committed:
		reward_committed = true
		# Mirror the decision into the battle state so a restored snapshot cannot pay
		# the same victory a second time (BattleSave stores this flag).
		battle.reward_granted = true
		var updated: Dictionary = SaveScript.record_battle(save_data, victory, int(reward["credits"]), battle.seed_value)
		save_data.clear()
		save_data.merge(updated, true)
		SaveScript.save_data(save_data)
		battle_recorded.emit(victory, int(reward["credits"]), battle.seed_value)
	_close_overlay()
	overlay = OverlayScript.new()
	ui_layer.add_child(overlay)
	overlay.setup("result", title, subtitle, lines, accent)
	overlay.primary_pressed.connect(_restart)
	overlay.secondary_pressed.connect(_to_menu)


func _close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
