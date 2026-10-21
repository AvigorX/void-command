extends Control
## Main menu + controls sheet + fleet upgrade screen. All drawn from code.

signal new_battle_requested
signal resume_requested
signal compose_requested(map_size: Vector2i)
signal quit_requested

const SaveScript = preload("res://scripts/core/save_data.gd")
## Preloaded (not the global class name): GDScript static vars are shared per script
## RESOURCE, and a class_name reference can resolve to a different instance - which
## would silently bypass the test isolation of the snapshot path.
const BattleSaveRef = preload("res://scripts/core/battle_save.gd")
const DefsRef = preload("res://scripts/core/ship_defs.gd")

var save_data: Dictionary = {}
var mode: String = "main"
var time: float = 0.0
var font: Font
var stars: Array[Vector2] = []
var button_nodes: Array[Button] = []
var footer_message: String = ""
## Battlefield the next battle is created on (STEP 2 / Block B).
var map_size: Vector2i = MapConfig.REFERENCE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in range(160):
		stars.append(Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720)))
	_build_buttons()
	set_process(true)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _build_buttons() -> void:
	for b in button_nodes:
		if is_instance_valid(b):
			b.queue_free()
	button_nodes.clear()
	match mode:
		"main":
			_add_button("NEW BATTLE", Rect2(120, 366, 300, 46), Color(0.55, 0.95, 1.0), func() -> void: new_battle_requested.emit())
			_add_button("FLEET UPGRADES", Rect2(120, 422, 300, 46), Color(0.70, 0.90, 1.0), func() -> void: _set_mode("upgrades"))
			_add_button("CONTROLS", Rect2(120, 478, 300, 46), Color(0.65, 0.78, 0.88), func() -> void: _set_mode("controls"))
			_add_button("QUIT", Rect2(120, 534, 300, 46), Color(0.60, 0.66, 0.72), func() -> void: quit_requested.emit())
		"controls":
			_add_button("BACK", Rect2(120, 648, 300, 46), Color(0.55, 0.95, 1.0), func() -> void: _set_mode("main"))
		"upgrades":
			var upgrades: Dictionary = save_data.get("upgrades", {})
			for i in range(SaveScript.CLASSES.size()):
				var class_id: String = SaveScript.CLASSES[i]
				var y: float = 206.0 + float(i) * 44.0
				var hull_level: int = int(upgrades.get(class_id, {}).get("hull", 0))
				var weapon_level: int = int(upgrades.get(class_id, {}).get("weapon", 0))
				_add_button("HULL LV %d · %d CR" % [hull_level, SaveScript.upgrade_cost(hull_level)],
					Rect2(560, y, 230, 32), Color(0.55, 0.95, 0.70), func() -> void: _buy(class_id, "hull"), hull_level >= SaveScript.MAX_UPGRADE)
				_add_button("WEAPON LV %d · %d CR" % [weapon_level, SaveScript.upgrade_cost(weapon_level)],
					Rect2(800, y, 230, 32), Color(1.0, 0.72, 0.40), func() -> void: _buy(class_id, "weapon"), weapon_level >= SaveScript.MAX_UPGRADE)
			_add_button("BACK", Rect2(120, 606, 240, 46), Color(0.55, 0.95, 1.0), func() -> void: _set_mode("main"))
	queue_redraw()


func _add_button(text: String, rect: Rect2, accent: Color, action: Callable, disabled: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.40, 0.46, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.065, 0.095, 0.92)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var hb: StyleBoxFlat = sb.duplicate()
	hb.bg_color = Color(0.08, 0.16, 0.21, 1.0)
	hb.border_color = accent
	b.add_theme_stylebox_override("hover", hb)
	var pb: StyleBoxFlat = sb.duplicate()
	pb.bg_color = Color(0.12, 0.22, 0.26, 1.0)
	b.add_theme_stylebox_override("pressed", pb)
	var db: StyleBoxFlat = sb.duplicate()
	db.bg_color = Color(0.03, 0.04, 0.05, 0.9)
	db.border_color = Color(0.24, 0.28, 0.32, 0.5)
	b.add_theme_stylebox_override("disabled", db)
	b.pressed.connect(action)
	add_child(b)
	button_nodes.append(b)


func _set_mode(m: String) -> void:
	mode = m
	footer_message = ""
	_build_buttons()


func _buy(class_id: String, kind: String) -> void:
	var result: Dictionary = SaveScript.buy_upgrade(save_data, class_id, kind)
	if bool(result["ok"]):
		var updated: Dictionary = result["data"]
		save_data.clear()
		save_data.merge(updated, true)
		SaveScript.save_data(save_data)
		footer_message = "%s %s upgraded." % [DefsRef.label(class_id), kind.to_upper()]
		_build_buttons()
	else:
		footer_message = String(result["reason"])
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and mode == "main":
		new_battle_requested.emit()
	if event.is_action_pressed("toggle_map") and mode == "main":
		# Battlefield selection (STEP 2 / Block B). A key rather than a button: the main
		# menu's four actions are an asserted UI contract, and this is a settings
		# toggle, not a fifth action. The current choice is always on screen.
		map_size = MapConfig.next_size(map_size)
		footer_message = "Battlefield set to %s." % MapConfig.label(map_size)
		queue_redraw()
	if event.is_action_pressed("compose_fleet") and mode == "main":
		compose_requested.emit(map_size)
	if event.is_action_pressed("resume_battle") and mode == "main":
		if BattleSaveRef.has_save():
			resume_requested.emit()
		else:
			footer_message = "No saved battle to resume."
			queue_redraw()


func _draw() -> void:
	_draw_background()
	if mode == "main":
		_draw_main()
	elif mode == "controls":
		_draw_controls()
	else:
		_draw_upgrades()


func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.010, 0.014, 0.028, 1.0))
	for i in range(4):
		var r: float = 260.0 + 60.0 * float(i)
		draw_circle(Vector2(980, 300), r, Color(0.10, 0.16, 0.32, 0.035))
	for i in range(stars.size()):
		var p: Vector2 = stars[i]
		var tw: float = 0.35 + 0.35 * sin(time * 1.3 + float(i) * 0.7)
		draw_circle(p, 1.0 + float(i % 3) * 0.4, Color(0.75, 0.88, 1.0, 0.25 + tw * 0.35))
	# Distant planet with limb glow.
	var c := Vector2(1000, 320)
	draw_circle(c, 214, Color(0.10, 0.16, 0.28, 1.0))
	for i in range(12):
		var f: float = float(i) / 11.0
		draw_circle(c + Vector2(-18, -16) * f, 200.0 - 150.0 * f * 0.2, Color(0.12 + 0.10 * f, 0.20 + 0.10 * f, 0.34 + 0.10 * f, 1.0))
	draw_arc(c, 206, -1.2, 1.4, 60, Color(0.35, 0.75, 1.0, 0.30), 2.0, true)
	draw_set_transform(c, -0.42, Vector2(1.7, 0.36))
	draw_arc(Vector2.ZERO, 258, 0, TAU, 64, Color(0.50, 0.62, 0.85, 0.18), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Drifting capital ship silhouette.
	var bob: float = sin(time * 0.6) * 6.0
	_draw_silhouette(Vector2(880, 540 + bob), 2.2, 0.55)
	_draw_silhouette(Vector2(1090, 620 - bob), 1.2, 0.35)
	_draw_silhouette(Vector2(760, 640 + bob * 0.6), 0.9, 0.25)
	draw_rect(Rect2(0, 0, 1280, 2), Color(0.30, 0.60, 0.80, 0.25))


func _draw_silhouette(pos: Vector2, scale: float, alpha: float) -> void:
	var shape := PackedVector2Array([
		Vector2(-19, -9), Vector2(6, -10), Vector2(16, -7), Vector2(19, 0),
		Vector2(16, 7), Vector2(6, 10), Vector2(-19, 9), Vector2(-15, 0),
	])
	var pts := PackedVector2Array()
	for p in shape:
		pts.append(pos + p * scale)
	draw_colored_polygon(pts, Color(0.10, 0.20, 0.28, alpha))
	var outline := PackedVector2Array()
	for p in shape:
		outline.append(pos + p * scale)
	draw_polyline(outline + PackedVector2Array([outline[0]]), Color(0.30, 0.70, 0.90, alpha * 0.9), 1.4)
	draw_circle(pos + Vector2(14, 0) * scale, 2.6 * scale, Color(0.55, 0.95, 1.0, alpha * 0.8))
	draw_circle(pos + Vector2(-18, 0) * scale, 3.2 * scale, Color(0.35, 0.80, 1.0, alpha * 0.35))


func _draw_main() -> void:
	var bob: float = sin(time * 0.8) * 2.0
	for i in range(6, 0, -1):
		var a: float = 0.035 * float(i)
		draw_string(font, Vector2(118, 232 + bob), "VOID COMMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 64,
			Color(0.30, 0.85, 1.0, a))
	draw_string(font, Vector2(120, 230 + bob), "VOID COMMAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.88, 0.97, 1.0, 1.0))
	draw_string(font, Vector2(122, 258 + bob), "TACTICAL FLEET COMMAND  ·  PROCEDURAL SECTOR ENGINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.45, 0.66, 0.80, 1.0))
	draw_line(Vector2(120, 280), Vector2(600, 280), Color(0.35, 0.70, 0.90, 0.45), 1.0)
	var credits: int = int(save_data.get("credits", 0))
	var stats: Dictionary = save_data.get("stats", {})
	draw_string(font, Vector2(120, 310), "CREDITS  %d" % credits, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.85, 0.50, 1.0))
	draw_string(font, Vector2(270, 310), "BATTLES %d   WINS %d   LOSSES %d" % [
		int(stats.get("battles", 0)), int(stats.get("wins", 0)), int(stats.get("losses", 0))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.74, 0.84, 1.0))
	draw_string(font, Vector2(120, 336), "LAST SEED  %d" % int(save_data.get("last_seed", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.42, 0.54, 0.64, 1.0))
	# Battlefield size: every preset the map configuration knows, switchable with [M].
	draw_string(font, Vector2(120, 596), "BATTLEFIELD  %s" % MapConfig.label(map_size), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.55, 0.95, 1.0, 1.0))
	var preset_labels: PackedStringArray = PackedStringArray()
	for preset in MapConfig.PRESET_NAMES:
		preset_labels.append(MapConfig.label(MapConfig.size_of(preset)))
	draw_string(font, Vector2(120, 614), "PRESS [M] TO SWITCH   ·   %s" % "  /  ".join(preset_labels),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.42, 0.56, 0.66, 1.0))
	draw_string(font, Vector2(838, 596), "[F] COMPOSE FLEET", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.55, 0.95, 1.0, 1.0))
	# Saved battle (mid-battle snapshot): only offered when one actually exists.
	if BattleSaveRef.has_save():
		draw_string(font, Vector2(430, 596), "PRESS [C] TO RESUME THE SAVED BATTLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.62, 0.95, 1.0, 1.0))
	draw_string(font, Vector2(120, 640), "Every hull, star and explosion in this build is drawn by code.", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.38, 0.48, 0.58, 1.0))
	draw_string(font, Vector2(120, 658), "No imported textures, fonts, audio or network services.", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.38, 0.48, 0.58, 1.0))


func _draw_controls() -> void:
	draw_rect(Rect2(80, 80, 1120, 640), Color(0.015, 0.030, 0.048, 0.95))
	draw_rect(Rect2(80, 80, 1120, 640), Color(0.35, 0.70, 0.90, 0.35), false, 1.5)
	draw_string(font, Vector2(112, 130), "CONTROLS & RULES", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.62, 0.95, 1.0, 1.0))
	var rows: Array[String] = [
		"LEFT CLICK           select ship · move to highlighted cell · fire at bracketed enemy",
		"Q                    arm ship ability (then click the highlighted target)",
		"W                    hold position (spend remaining movement and attack)",
		"T                    rotate the selected ship 90° in place (free, must fit)",
		"TAB                  cycle through your ships",
		"SPACE                end turn and hand control to the enemy fleet",
		"ESC                  pause menu (resume / restart / main menu)",
		"HOME                 fit the whole board to the play area",
		"R                    recentre the camera on the board (keeps the zoom)",
		"RIGHT DRAG           pan the camera          WHEEL   zoom at the pointer",
		"ARROW KEYS           pan the camera",
		"",
		"TURN FLOW            deploy → move → fire → end turn → enemy AI → new round",
		"MOVEMENT             orthogonal, 1 MP per cell, blocked by planets",
		"LINE OF SIGHT        planets and nebula clouds block firing lanes",
		"COVER                ships inside a nebula take 30% less damage",
		"SHIELDS              absorb damage first and regenerate 12% at the start of a round",
		"ARMOR                reduces hull damage after shields are depleted",
		"ABILITIES            each class has one ability with a cooldown in rounds",
		"RELAY (optional)     hold the relay for 3 rounds to disrupt every enemy shield",
		"",
		"VICTORY              destroy every hostile ship",
		"DEFEAT               lose your entire fleet, or exceed 40 rounds",
	]
	var y: float = 176.0
	for line in rows:
		var col := Color(0.74, 0.84, 0.92, 1.0)
		if line.begins_with("TURN FLOW") or line.begins_with("MOVEMENT") or line.begins_with("VICTORY") or line.begins_with("DEFEAT"):
			col = Color(0.55, 0.90, 1.0, 1.0)
		draw_string(font, Vector2(116, y), line, HORIZONTAL_ALIGNMENT_LEFT, 1040, 11, col)
		y += 21.0


func _draw_upgrades() -> void:
	draw_rect(Rect2(80, 80, 1120, 640), Color(0.015, 0.030, 0.048, 0.95))
	draw_rect(Rect2(80, 80, 1120, 640), Color(0.35, 0.70, 0.90, 0.35), false, 1.5)
	draw_string(font, Vector2(112, 132), "FLEET UPGRADES", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.62, 0.95, 1.0, 1.0))
	draw_string(font, Vector2(112, 158), "Permanent refits are saved between battles (versioned save format).", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.50, 0.64, 0.76, 1.0))
	draw_string(font, Vector2(1030, 132), "%d CR" % int(save_data.get("credits", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.95, 0.85, 0.50, 1.0))
	draw_line(Vector2(112, 176), Vector2(1168, 176), Color(0.35, 0.70, 0.90, 0.35), 1.0)
	var upgrades: Dictionary = save_data.get("upgrades", {})
	# One row per refittable class. M5 made all eight classes refittable, so the rows are
	# compact (44 px, single detail line): eight rows of 74 px would run off the panel.
	for i in range(SaveScript.CLASSES.size()):
		var class_id: String = SaveScript.CLASSES[i]
		var y: float = 206.0 + float(i) * 44.0
		var d: Dictionary = DefsRef.def(class_id)
		draw_rect(Rect2(112, y - 4, 1056, 38), Color(0.03, 0.06, 0.08, 0.7))
		draw_string(font, Vector2(126, y + 15), String(d["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.80, 0.94, 1.0, 1.0))
		var up: Dictionary = upgrades.get(class_id, {})
		draw_string(font, Vector2(126, y + 29), "%s · hull %d · dmg %d · rng %d · refit h%d/w%d" % [
			String(d["role"]), int(d["hull"]), int(d["damage"]), int(d["range"]),
			int(up.get("hull", 0)), int(up.get("weapon", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.48, 0.62, 0.74, 1.0))
	if footer_message != "":
		var col := Color(0.55, 0.95, 0.75, 1.0)
		if footer_message.find("Not enough") >= 0 or footer_message.find("maximum") >= 0:
			col = Color(1.0, 0.70, 0.42, 1.0)
		draw_string(font, Vector2(390, 642), footer_message, HORIZONTAL_ALIGNMENT_LEFT, 600, 12, col)
