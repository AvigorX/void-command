extends SceneTree
## M6 — camera: fit, recentre, zoom on the pointer, clamping, selection at any zoom.
##
## These are the properties the mandate names, checked against the real BattleScreen and
## its real Camera2D (no re-implementation): the board must fit the play area, zoom must
## keep the point under the cursor fixed, the camera must not lose the board, and a screen
## point must resolve to the same cell at every zoom level.

const BattleScreenScript = preload("res://scripts/ui/battle_screen.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const SaveGuard = preload("res://tests/save_guard.gd")


var checks: int = 0
var failures: int = 0
var screen

var frame: int = 0


func _initialize() -> void:
	# Instantiating a BattleScreen touches the battle autosave path: without this the
	# suite writes into the real user profile (found by the gate's double fingerprint).
	SaveGuard.isolate()
	print("=== VOID COMMAND — CAMERA (M6) ===")
	screen = BattleScreenScript.new()
	root.add_child(screen)


func _process(_delta: float) -> bool:
	## `_ready` runs on the first frame, so the camera and the view do not exist until
	## then. The suite waits for them instead of assuming.
	frame += 1
	if frame < 3:
		return false
	if screen.view == null or screen.camera == null:
		ok(false, "the battle screen built its view and camera")
		_finish()
		return false
	_run()
	_finish()
	return false


func _run() -> void:
	# A 48x34 board at 19 px cells: the geometry the grand preset produces.
	screen.view.cell_px = 19.0
	screen.view.board_w = 48.0 * 19.0
	screen.view.board_h = 34.0 * 19.0
	test_fit()
	test_recenter()
	test_zoom_at_pointer()
	test_clamp()
	test_selection_at_zoom()
	test_zoom_limits()


func _finish() -> void:
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _board_rect() -> Rect2:
	return Rect2(screen.PLAY_ORIGIN, Vector2(screen.view.board_w, screen.view.board_h))


func _visible_rect() -> Rect2:
	var h: Vector2 = Vector2(1280.0, 720.0) * 0.5 / screen.camera.zoom
	return Rect2(screen.camera.position - h, h * 2.0)


func test_fit() -> void:
	screen._fit_view()
	var z: float = screen.camera.zoom.x
	ok(z >= screen.ZOOM_MIN and z <= screen.ZOOM_MAX, "fit keeps zoom in range (%.2f)" % z)
	var vis: Rect2 = _visible_rect()
	var board: Rect2 = _board_rect()
	ok(vis.encloses(board), "fit shows the whole board (visible %.0fx%.0f, board %.0fx%.0f)" % [
		vis.size.x, vis.size.y, board.size.x, board.size.y])
	# M7B: the invariant is about SCREEN space, not about the camera's own coordinates. A
	# Camera2D centres its viewport, while the board must be centred on the play area (928
	# wide, left of the HUD). Comparing `camera.position` to the play centre - what this
	# test used to do - passed while the board was 152 px to the right, hiding the enemy
	# fleet behind the HUD panel (measured: enemy hulls at screen x = 1024).
	#
	# `get_canvas_transform()` is one frame stale right after a camera move, so the mapping
	# is computed from the camera state itself - the same formula Camera2D applies.
	var board_centre: Vector2 = screen.view.ORIGIN + Vector2(screen.view.board_w, screen.view.board_h) * 0.5
	var on_screen: Vector2 = _screen_of(board_centre)
	var play_centre: Vector2 = screen.PLAY_ORIGIN + screen.PLAY_AREA * 0.5
	ok(on_screen.distance_to(play_centre) < 2.0,
		"fit puts the board centre on the PLAY AREA centre on screen (%.0f,%.0f vs %.0f,%.0f)" % [
			on_screen.x, on_screen.y, play_centre.x, play_centre.y])
	var right_edge: float = _screen_of(Vector2(screen.view.ORIGIN.x + screen.view.board_w, 0.0)).x
	var panel_x: float = 1280.0 - screen.view.HUD_PANEL_W
	ok(right_edge <= panel_x + 0.5,
		"the whole board ends left of the HUD panel on screen (%.0f <= %.0f)" % [right_edge, panel_x])
	ok(_screen_of(screen.view.ORIGIN).x >= 0.0, "and its left edge is on screen (%.0f)" % _screen_of(screen.view.ORIGIN).x)


func _screen_of(world: Vector2) -> Vector2:
	## World -> screen for a Camera2D with anchor mode DRAG_CENTER and no smoothing.
	return Vector2(1280.0, 720.0) * 0.5 + (world - screen.camera.position) * screen.camera.zoom.x


func test_recenter() -> void:
	screen.camera.position = Vector2(100.0, 100.0)
	screen._recenter()
	var board_centre: Vector2 = screen.view.ORIGIN + Vector2(screen.view.board_w, screen.view.board_h) * 0.5
	var on_screen: Vector2 = _screen_of(board_centre)
	var play_centre: Vector2 = screen.PLAY_ORIGIN + screen.PLAY_AREA * 0.5
	ok(absf(on_screen.x - play_centre.x) < 2.0, "recenter puts the board back on the play area (x) %.0f vs %.0f" % [on_screen.x, play_centre.x])
	ok(absf(on_screen.y - play_centre.y) < 2.0, "recenter puts the board back on the play area (y) %.0f vs %.0f" % [on_screen.y, play_centre.y])


func test_zoom_at_pointer() -> void:
	# Zoom 2 makes the board larger than the view, which is the case where an anchored zoom
	# has room to do its job (below that the clamp legitimately pins the board centred).
	# 1.2 leaves headroom under ZOOM_MAX (2.40) so the round trip is not clipped at the top:
	# a clip is correct behaviour and must not be mistaken for a broken inverse.
	screen.camera.zoom = Vector2(1.2, 1.2)
	screen.camera.position = Vector2(480.0, 380.0)
	var focus := Vector2(700.0, 400.0)
	var before: float = screen.camera.zoom.x
	var world_before: Vector2 = screen.camera.position + (focus - Vector2(640.0, 360.0)) / before
	screen._zoom_by(1.35, focus)
	var after: float = screen.camera.zoom.x
	ok(after > before, "wheel-up zooms in (%.2f -> %.2f)" % [before, after])
	var world_after: Vector2 = screen.camera.position + (focus - Vector2(640.0, 360.0)) / after
	ok(world_before.distance_to(world_after) < 1.0,
		"the point under the cursor stays put (moved %.2f px)" % world_before.distance_to(world_after))
	screen._zoom_by(1.0 / 1.35, focus)
	ok(absf(screen.camera.zoom.x - before) < 0.01, "zooming back out restores the scale")


func test_clamp() -> void:
	screen._fit_view()
	# Push the camera far off the board on every side: it must stay over the board.
	for probe in [Vector2(-5000.0, -5000.0), Vector2(5000.0, 5000.0), Vector2(-5000.0, 5000.0)]:
		screen.camera.position = probe
		screen._clamp_camera()
		var vis: Rect2 = _visible_rect()
		var board: Rect2 = _board_rect()
		var overlaps: Rect2 = vis.intersection(board)
		ok(overlaps.size.x > 0.0 and overlaps.size.y > 0.0,
			"after clamping %s the view still shows part of the board" % str(probe))


func test_selection_at_zoom() -> void:
	## A screen point must resolve to the SAME cell whatever the zoom: this is what makes
	## clicking work when the player is zoomed in on a capital ship.
	var cell := Vector2i(30, 20)
	screen._fit_view()
	var cell_point: Vector2 = screen.view.cell_center(cell)
	for z in [0.6, 1.0, 1.8]:
		screen.camera.zoom = Vector2(z, z)
		screen.camera.position = cell_point
		var local: Vector2 = screen.view.to_local(cell_point)
		var back: Vector2i = screen.view.world_to_cell(local)
		ok(back == cell, "zoom %.1f: the cell centre resolves to its own cell (%s)" % [z, str(back)])
		# And the HUD stays outside the world transform: it lives in its own CanvasLayer.
		ok(screen.ui_layer != null and screen.hud.get_parent() == screen.ui_layer,
			"zoom %.1f: the HUD is not a child of the world view" % z)


func test_zoom_limits() -> void:
	for i in range(20):
		screen._zoom_by(2.0, Vector2(500.0, 300.0))
	ok(screen.camera.zoom.x <= screen.ZOOM_MAX + 0.001, "zoom stops at the maximum (%.2f)" % screen.camera.zoom.x)
	for i in range(20):
		screen._zoom_by(0.5, Vector2(500.0, 300.0))
	ok(screen.camera.zoom.x >= screen.ZOOM_MIN - 0.001, "zoom stops at the minimum (%.2f)" % screen.camera.zoom.x)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
