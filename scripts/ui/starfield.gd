extends Control
## Animated, parallax deep-space background. Pure CanvasItem drawing.

var t: float = 0.0
var stars: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var seed_value: int = 1
var drift: Vector2 = Vector2.ZERO


func setup(p_seed: int) -> void:
	seed_value = p_seed
	stars.clear()
	clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed * 2654435761
	for i in range(240):
		stars.append({
			"pos": Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720)),
			"r": rng.randf_range(0.5, 1.9),
			"a": rng.randf_range(0.25, 0.95),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.4, 2.0),
			"warm": rng.randf() < 0.18,
			"depth": rng.randf_range(0.05, 0.35),
		})
	var palette: Array[Color] = [
		Color(0.18, 0.30, 0.55, 0.10),
		Color(0.35, 0.16, 0.45, 0.09),
		Color(0.08, 0.35, 0.42, 0.08),
		Color(0.42, 0.20, 0.28, 0.07),
	]
	for i in range(5):
		clouds.append({
			"pos": Vector2(rng.randf_range(100, 1180), rng.randf_range(80, 640)),
			"r": rng.randf_range(180, 340),
			"color": palette[i % palette.size()],
			"phase": rng.randf_range(0.0, TAU),
		})
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	if stars.is_empty():
		setup(seed_value)


func _process(delta: float) -> void:
	t += delta
	var cam := get_viewport().get_camera_2d()
	var target: Vector2 = Vector2.ZERO
	if cam != null:
		target = (cam.position - Vector2(640, 360)) * 0.16
	drift = drift.lerp(target, minf(1.0, delta * 4.0))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.012, 0.016, 0.030, 1.0))
	# Slow nebula clouds.
	for c in clouds:
		var center: Vector2 = c["pos"] + Vector2(cos(t * 0.03 + float(c["phase"])) * 14.0, sin(t * 0.024 + float(c["phase"])) * 10.0) - drift * 0.6
		var base: Color = c["color"]
		for ring in range(5, 0, -1):
			var rad: float = float(c["r"]) * (0.35 + 0.14 * float(ring))
			var alpha: float = base.a * (0.22 + 0.10 * float(5 - ring))
			draw_circle(center, rad, Color(base.r, base.g, base.b, alpha))
	# Stars with parallax and twinkle.
	for s in stars:
		var depth: float = float(s["depth"])
		var pos: Vector2 = s["pos"] - drift * depth
		pos.x = fposmod(pos.x, 1280.0)
		pos.y = fposmod(pos.y, 720.0)
		var alpha: float = float(s["a"]) * (0.55 + 0.45 * sin(t * float(s["speed"]) + float(s["phase"])))
		var col: Color = Color(1.0, 0.86, 0.72, alpha) if bool(s["warm"]) else Color(0.78, 0.90, 1.0, alpha)
		var rad: float = float(s["r"])
		draw_circle(pos, rad, col)
		if rad > 1.5:
			draw_line(pos - Vector2(rad * 2.4, 0), pos + Vector2(rad * 2.4, 0), Color(col.r, col.g, col.b, alpha * 0.35), 1.0)
			draw_line(pos - Vector2(0, rad * 2.4), pos + Vector2(0, rad * 2.4), Color(col.r, col.g, col.b, alpha * 0.35), 1.0)
	# Vignette bands for depth.
	draw_rect(Rect2(0, 0, 1280, 90), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(Rect2(0, 650, 1280, 70), Color(0.0, 0.0, 0.0, 0.30))
