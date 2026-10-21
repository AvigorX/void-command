extends SceneTree
## STEP 2.1 / Block A — HUD and hit-testing on both battlefields.
##
## The roster used to be five rows tall in BOTH the drawing loop (which iterates every
## hull) and the click hit-test (which used the constant ROWS = 5). With a composed
## fleet that means rows you can see but cannot click. These tests pin the layout maths
## and the click path, not just the pixels.

const BattleScript = preload("res://scripts/core/battle.gd")
const ShipScript = preload("res://scripts/core/ship.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const HudScript = preload("res://scripts/ui/hud.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var real_save_before: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — HUD LAYOUT SUITE (STEP 2.1) ===")
	real_save_before = SaveGuard.snapshot()
	SaveGuard.isolate()
	test_row_metrics()
	test_roster_click_reaches_every_row()
	test_roster_scroll_and_selection()
	test_action_state_matches_the_engine()
	test_hud_never_draws_overlapping_rows()
	test_board_never_under_the_panel()
	test_every_cell_is_clickable()
	test_save_isolation()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	SaveGuard.cleanup()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  [%s] %s" % [current, label])


func begin(name: String) -> void:
	current = name
	print("- %s" % name)


func battle_for(size: Vector2i, extra_player_ships: int = 0) -> Battle:
	var b = BattleScript.new()
	b.setup(4242, {}, 1, size)
	var next_id: int = 100
	for i in range(extra_player_ships):
		var s: Ship = ShipScript.create("fighter", 0, next_id, 10 + i)
		s.placed = false
		s.cell = Vector2i(1, 1 + i)
		s.placed = true
		b._add_ship(s)
		next_id += 1
	return b


# ------------------------------------------------------------------- tests ----

func test_row_metrics() -> void:
	begin("roster rows shrink to a readable minimum, then scroll")
	var hud = HudScript.new()
	ok(is_equal_approx(hud.roster_row_h(5), HudScript.ROW_H), "five hulls keep the authored row height")
	ok(is_equal_approx(hud.roster_row_h(3), HudScript.ROW_H), "fewer hulls do not stretch")
	var h20: float = hud.roster_row_h(20)
	ok(h20 < HudScript.ROW_H, "twenty hulls use shorter rows (%.1f px)" % h20)
	ok(h20 >= HudScript.ROW_MIN_H, "rows stay readable at twenty hulls (%.1f px)" % h20)
	# M7B contract: a row NEVER drops below ROW_MIN_H (12 px rows drew the name, the class
	# tag, the hull bar and the HP numbers on top of each other). Overflow scrolls instead.
	var never_squashed: bool = true
	var always_fits: bool = true
	var scroll_reaches_all: bool = true
	for n in range(1, 61):
		var rh: float = hud.roster_row_h(n)
		var visible: int = hud.roster_visible_rows(n)
		if rh < HudScript.ROW_MIN_H - 0.01:
			never_squashed = false
		if HudScript.ROW_TOP + rh * float(visible) > HudScript.ROSTER_BOTTOM + 0.01:
			always_fits = false
		if visible < 1 or visible > n:
			always_fits = false
		# Scrolling must be able to reveal the last hull and hide nothing permanently.
		if int(hud.roster_max_scroll(n)) + visible != maxi(n, visible):
			scroll_reaches_all = false
	ok(never_squashed, "no fleet size squashes a row below %.0f px" % HudScript.ROW_MIN_H)
	ok(always_fits, "no fleet size draws a visible row under the buttons")
	ok(scroll_reaches_all, "the maximum scroll always brings the last hull into view")
	ok(hud.roster_max_scroll(5) == 0, "a small fleet needs no scrolling")
	ok(hud.roster_max_scroll(40) == 40 - hud.roster_visible_rows(40),
		"a large fleet scrolls by exactly the rows that do not fit (%d)" % hud.roster_max_scroll(40))
	hud.free()


func test_roster_scroll_and_selection() -> void:
	begin("a scrolled roster stays clickable and follows the selection")
	var b := battle_for(MapConfigRef.REFERENCE, 30)   # 35 player hulls: more than the band
	var hud = HudScript.new()
	root.add_child(hud)
	hud.setup(b)
	var all_player: Array = []
	for s in b.ships:
		if s.team == 0:
			all_player.append(s)
	var visible: int = hud.roster_visible_rows(all_player.size())
	ok(all_player.size() > visible, "the fixture overflows the band (%d hulls, %d visible)" % [all_player.size(), visible])
	# Scroll to the bottom and click the LAST drawn row: it must select the last hull.
	hud.roster_scroll_by(999)
	ok(hud.roster_scroll == hud.roster_max_scroll(all_player.size()), "the wheel clamps at the bottom")
	var got: Array[int] = []
	hud.ship_selected.connect(func(id: int) -> void: got.append(id))
	var rh: float = hud.roster_row_h(all_player.size())
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(40.0, HudScript.ROW_TOP + rh * float(visible) - 2.0)
	hud._gui_input(ev)
	ok(got.size() == 1 and got[0] == all_player[all_player.size() - 1].id,
		"clicking the last visible row selects the last hull")
	# Selecting a hull outside the window scrolls it into view (board click / TAB path).
	hud.roster_scroll_by(-999)
	hud.ensure_visible(all_player.size() - 1)
	ok(hud.roster_scroll + visible > all_player.size() - 1,
		"ensure_visible brings the last hull into the window (scroll %d)" % hud.roster_scroll)
	ok(hud.roster_scroll == hud.roster_max_scroll(all_player.size()),
		"and it scrolls exactly as far as needed")
	hud.queue_free()


func test_action_state_matches_the_engine() -> void:
	begin("the spent-actions indicator follows the authoritative state")
	var b := battle_for(MapConfigRef.REFERENCE)
	var s: Ship = b.alive_ships(0)[0]
	ok(s.action_state() == Ship.ACTION_READY, "a fresh hull still has both actions")
	s.move_points = 0
	ok(s.action_state() == Ship.ACTION_PARTIAL, "moving without firing is a partial state")
	s.has_attacked = true
	ok(s.action_state() == Ship.ACTION_DONE, "no movement and no shot is DONE")
	s.begin_round()
	ok(s.action_state() == Ship.ACTION_READY, "a new round restores the READY state")
	s.has_attacked = true
	ok(s.action_state() == Ship.ACTION_PARTIAL, "firing first leaves movement, so PARTIAL")
	s.has_attacked = false
	s.move_points = 0
	ok(s.action_state() == Ship.ACTION_PARTIAL, "walking the whole budget leaves the shot")
	# Destroyed hulls report DONE, and the renderer draws them as wreckage instead.
	s.take_damage(100000.0, true)
	ok(not s.alive and s.action_state() == Ship.ACTION_DONE, "a destroyed hull reports DONE")
	# The state really is derived: mutating the engine fields moves it, with no cache.
	var other: Ship = b.alive_ships(0)[0]
	other.move_points = 0
	other.has_attacked = true
	ok(other.action_state() == Ship.ACTION_DONE, "a spent hull reports DONE")
	other.begin_round()
	ok(other.action_state() == Ship.ACTION_READY, "and the round change clears it")


func test_hud_never_draws_overlapping_rows() -> void:
	begin("compact rows keep text, bars and HP inside their own row")
	# The layout is geometry, so it can be pinned without rendering: for every fleet size,
	# the lowest element of a row (the shield bar) must end above the next row's top.
	var hud = HudScript.new()
	var bad: int = 0
	for n in range(1, 61):
		var rh: float = hud.roster_row_h(n)
		var compact: bool = rh < 26.0
		# Mirror of _draw_roster's offsets: name baseline 10, bars start 13/14, +4 shield.
		var lowest: float = (13.0 if compact else 14.0) + 4.0 + 2.0
		if lowest > rh + 0.01:
			bad += 1
	ok(bad == 0, "every row height fits its own content (%d violations)" % bad)
	hud.free()


func test_roster_click_reaches_every_row() -> void:
	begin("every roster row is clickable, honouring the scroll window")
	var b := battle_for(MapConfigRef.REFERENCE, 7)   # 12 player hulls in total
	var hud = HudScript.new()
	root.add_child(hud)
	hud.setup(b)
	var got: Array[int] = []
	hud.ship_selected.connect(func(id: int) -> void: got.append(id))
	var all_player: Array = []
	for s in b.ships:
		if s.team == 0:
			all_player.append(s)
	ok(all_player.size() == 12, "the fixture really has 12 player hulls")
	var rh: float = hud.roster_row_h(all_player.size())
	var visible: int = hud.roster_visible_rows(all_player.size())
	ok(all_player.size() > visible, "the band shows %d of %d rows, the rest scrolls" % [visible, all_player.size()])
	# A row is clickable in the window it is drawn in: for rows below the fold the roster
	# must first be scrolled there (that is what a wheel or a board selection does).
	var all_ok: bool = true
	for i in range(all_player.size()):
		hud.ensure_visible(i)
		var slot: int = i - hud.roster_scroll
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = Vector2(40.0, HudScript.ROW_TOP + rh * (float(slot) + 0.5))
		hud._gui_input(ev)
	ok(got.size() == all_player.size(), "each of the 12 rows emitted a selection (%d)" % got.size())
	for i in range(mini(got.size(), all_player.size())):
		if got[i] != all_player[i].id:
			all_ok = false
	ok(all_ok, "and each row selected its own hull")
	hud.queue_free()


func test_board_never_under_the_panel() -> void:
	begin("the board stops exactly where the HUD panel starts")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var b := battle_for(size)
		var v = ViewScript.new()
		v.setup(b)
		var right_edge: float = ViewScript.ORIGIN.x + v.board_w
		var panel_x: float = 1280.0 - ViewScript.HUD_PANEL_W
		ok(right_edge <= panel_x + 0.01,
			"%s: board ends at %.1f, panel starts at %.1f" % [MapConfigRef.label(size), right_edge, panel_x])
		ok(v.board_h + ViewScript.ORIGIN.y <= 720.0 + 0.01,
			"%s: board fits vertically (%.1f)" % [MapConfigRef.label(size), v.board_h + ViewScript.ORIGIN.y])
		ok(v.cell_px >= 24.0, "%s: cells stay legible (%.1f px)" % [MapConfigRef.label(size), v.cell_px])
		v.free()


func test_every_cell_is_clickable() -> void:
	begin("every cell centre maps back to its own cell on both boards")
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL]:
		var b := battle_for(size)
		var v = ViewScript.new()
		v.setup(b)
		var bad: int = 0
		for y in range(b.map.height):
			for x in range(b.map.width):
				var c := Vector2i(x, y)
				var centre: Vector2 = v.cell_center(c)
				if v.world_to_cell(centre) != c:
					bad += 1
				# The same point must lie inside the play area, not behind the panel.
				if centre.x >= 1280.0 - ViewScript.HUD_PANEL_W or centre.y >= 720.0:
					bad += 1
		ok(bad == 0, "%s: %d cells failed the round trip or the panel check" % [MapConfigRef.label(size), bad])
		v.free()


func test_save_isolation() -> void:
	begin("save isolation")
	ok(SaveGuard.unchanged(real_save_before), "the real save file is byte-identical after the suite")
