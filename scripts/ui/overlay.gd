extends Control
## Modal overlay: victory / defeat summary or pause menu.
## Drawn procedurally; native buttons for input.

signal primary_pressed
signal secondary_pressed
signal tertiary_pressed

var mode: String = "pause"
var title: String = ""
var subtitle: String = ""
var lines: Array[String] = []
var accent: Color = Color(0.45, 0.92, 1.0)
var t: float = 0.0

var _buttons: Array[Button] = []


func setup(p_mode: String, p_title: String, p_subtitle: String, p_lines: Array, p_accent: Color) -> void:
	mode = p_mode
	title = p_title
	subtitle = p_subtitle
	lines.clear()
	for l in p_lines:
		lines.append(String(l))
	accent = p_accent
	if is_inside_tree():
		_build_buttons()
	queue_redraw()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_buttons()
	set_process(true)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _build_buttons() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			b.queue_free()
	_buttons.clear()
	var labels: Array[String] = []
	if mode == "pause":
		labels = ["RESUME", "RESTART BATTLE", "MAIN MENU"]
	else:
		labels = ["REMATCH", "MAIN MENU"]
	var y: float = 570.0
	for i in range(labels.size()):
		var b := Button.new()
		b.text = labels[i]
		b.size = Vector2(300, 40)
		b.position = Vector2(490, y + float(i) * 48.0)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", accent)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.07, 0.10, 0.95)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override("normal", sb)
		var hb: StyleBoxFlat = sb.duplicate()
		hb.bg_color = Color(0.09, 0.16, 0.20, 1.0)
		hb.border_color = accent
		b.add_theme_stylebox_override("hover", hb)
		var pb: StyleBoxFlat = sb.duplicate()
		pb.bg_color = Color(0.12, 0.22, 0.26, 1.0)
		b.add_theme_stylebox_override("pressed", pb)
		var index: int = i
		b.pressed.connect(func() -> void: _on_button(index))
		add_child(b)
		_buttons.append(b)


func _on_button(index: int) -> void:
	if index == 0:
		primary_pressed.emit()
	elif index == 1:
		secondary_pressed.emit()
	else:
		tertiary_pressed.emit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.0, 0.01, 0.03, 0.78))
	var pulse: float = 0.5 + 0.5 * sin(t * 2.0)
	var panel := Rect2(340, 120, 600, 500)
	draw_rect(panel, Color(0.02, 0.04, 0.07, 0.97))
	draw_rect(panel, Color(accent.r, accent.g, accent.b, 0.35 + 0.25 * pulse), false, 1.5)
	draw_line(Vector2(340, 120), Vector2(940, 120), Color(accent.r, accent.g, accent.b, 0.8), 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(370, 178), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, accent)
	draw_string(font, Vector2(370, 206), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.80, 0.88, 1.0))
	var y: float = 250.0
	for line in lines:
		var col := Color(0.78, 0.86, 0.94, 1.0)
		if line.begins_with("+"):
			col = Color(0.55, 0.95, 0.75, 1.0)
		elif line.begins_with("-"):
			col = Color(0.95, 0.62, 0.55, 1.0)
		elif line.begins_with("!"):
			col = Color(0.98, 0.78, 0.42, 1.0)
			line = line.substr(1)
		draw_string(font, Vector2(372, y), line, HORIZONTAL_ALIGNMENT_LEFT, 540, 14, col)
		y += 21.0
	draw_line(Vector2(340, 556), Vector2(940, 556), Color(accent.r, accent.g, accent.b, 0.35), 1.0)
