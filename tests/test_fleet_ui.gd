extends SceneTree
## STEP 3 — fleet composition screen.
##
## The screen draws nothing that matters here: what is tested is the INTERACTION contract
## (which row is selectable, what a click means, when CONFIRM is allowed) and the fact that
## every verdict it shows comes from FleetPoints. A screen that let a Carrier in, or that
## confirmed a 300-point fleet, would fail here even if it looked right.

const FleetScreenScript = preload("res://scripts/ui/fleet_screen.gd")
const FleetPointsRef = preload("res://scripts/core/fleet_points.gd")
const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")

var checks: int = 0
var failures: int = 0
var current: String = ""
var screen: Control = null
var confirmed_payload: Dictionary = {}


func _initialize() -> void:
	print("=== VOID COMMAND — FLEET SCREEN SUITE (STEP 3) ===")
	screen = FleetScreenScript.new()
	root.add_child(screen)
	screen.confirmed.connect(func(entries: Array, mode: String, size: Vector2i) -> void:
		confirmed_payload = {"entries": entries, "mode": mode, "size": size})
	test_rows()
	test_add_remove()
	test_budget_modes()
	test_confirm()
	test_mouse_hit_test()
	test_map_toggle()
	test_keyboard()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
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


func reset() -> void:
	screen.entries.clear()
	screen.set_mode("standard")
	screen.map_size = MapConfigRef.REFERENCE
	screen.selected_row = 0
	screen.message = ""
	screen.refresh()
	confirmed_payload = {}


# ------------------------------------------------------------------ rows ----

func test_rows() -> void:
	begin("rows")
	reset()
	ok(screen.rows().size() == 8, "all eight classes are listed, including unpickable ones")
	ok(screen.rows()[0] == "interceptor" and screen.rows()[7] == "dreadnought", "in canonical order")
	# Every row must be a distinct, clickable rectangle that does not overlap the next.
	var previous_bottom: float = 0.0
	for i in range(screen.rows().size()):
		var r: Rect2 = screen.row_rect(i)
		ok(r.position.y >= previous_bottom, "row %d does not overlap the one above" % i)
		ok(r.size.y > 20.0, "row %d is tall enough to read and click" % i)
		ok(screen.plus_rect(i).position.x < screen.minus_rect(i).position.x, "row %d keeps + before -" % i)
		previous_bottom = r.position.y + r.size.y
	ok(previous_bottom < 616.0, "the last row clears the verdict line")
	ok(screen.CONFIRM_RECT.position.y > 616.0, "the deploy button sits below the verdict")
	ok(not screen.CONFIRM_RECT.intersects(screen.row_rect(7)), "and does not overlap the last row")


func test_add_remove() -> void:
	begin("add and remove")
	reset()
	var r: Dictionary = screen.add_class("fighter")
	ok(bool(r["ok"]), "a Fighter can be added")
	ok(screen.entries == ["fighter"], "and it is in the fleet")
	ok(int(FleetPointsRef.total_cost(screen.entries)) == 3, "costing 3 points")
	screen.add_class("fighter")
	screen.add_class("cruiser")
	ok(screen.entries.size() == 3, "three hulls")
	ok(screen.remove_class("fighter"), "removing a Fighter works")
	ok(screen.entries == ["fighter", "cruiser"], "and drops the LAST one of that class")
	ok(not screen.remove_class("battleship"), "removing an absent class is refused")
	ok(screen.message != "", "and says something to the operator")
	reset()
	# Every catalogue class is playable as of M4; only the class caps and the budget refuse.
	for id in ["carrier", "dreadnought", "interceptor", "destroyer"]:
		reset()
		var good: Dictionary = screen.add_class(id)
		ok(bool(good["ok"]), "%s can be added now that it is implemented" % id)
	var bad: Dictionary = screen.add_class("nonsense")
	ok(not bool(bad["ok"]), "an unknown class cannot be added")
	ok(String(bad["reason"]) != "", "and it is refused with a reason")
	# The screen's own limits come from the core, not from a copy of the numbers.
	reset()
	# No global hull cap any more (M4). Twelve cheap hulls must be accepted in the UI too.
	for i in range(12):
		screen.add_class("interceptor")
	ok(screen.entries.size() == 12, "twelve hulls are in the fleet: no global cap in the UI")
	var thirteenth: Dictionary = screen.add_class("interceptor")
	ok(bool(thirteenth["ok"]), "and a thirteenth is accepted as well")
	# What the UI DOES refuse is the per-class cap.
	reset()
	screen.add_class("dreadnought")
	var second_dn: Dictionary = screen.add_class("dreadnought")
	ok(not bool(second_dn["ok"]), "a second Dreadnought is refused")
	ok(String(second_dn["reason"]).find("At most 1") != -1, "with the cap quoted")
	reset()
	screen.add_class("carrier")
	screen.add_class("carrier")
	var third_cv: Dictionary = screen.add_class("carrier")
	ok(not bool(third_cv["ok"]), "a third Carrier is refused")
	# The screen must SHOW the cap where one exists and stay silent where none does.
	screen.add_class("dreadnought")   # the carrier block above reset the fleet
	var dn_row: int = screen.rows().find("dreadnought")
	ok(screen._state_text("dreadnought", ShipDefsRef.catalog_entry("dreadnought")) == "AT CAP 1",
		"the Dreadnought row reads AT CAP 1 once it is in the fleet")
	ok(screen._state_text("battleship", ShipDefsRef.catalog_entry("battleship")) == "CAP 2",
		"the Battleship row advertises its cap of 2")
	ok(screen._state_text("fighter", ShipDefsRef.catalog_entry("fighter")) == "AVAILABLE",
		"a Fighter row advertises no cap at all")
	ok(screen._state_text("interceptor", ShipDefsRef.catalog_entry("interceptor")) == "AVAILABLE",
		"and neither does an Interceptor")


func test_budget_modes() -> void:
	begin("budget modes")
	reset()
	ok(screen.budget() == 100, "Standard opens at 100")
	screen.set_mode("skirmish")
	ok(screen.budget() == 60, "Skirmish is 60")
	screen.set_mode("fleet_engagement")
	ok(screen.budget() == 150, "Fleet Engagement is 150")
	screen.set_mode("grand_fleet")
	ok(screen.budget() == 200, "Grand Fleet is 200")
	screen.set_mode("nonsense")
	ok(screen.budget() == 200, "an unknown mode is ignored rather than zeroing the budget")
	# Downgrading the budget below what is already spent must be VISIBLE and must block.
	reset()
	screen.set_mode("grand_fleet")
	# Two Battleships is the cap; add carriers and cruisers to overspend instead.
	screen.add_class("battleship")
	screen.add_class("battleship")
	screen.add_class("carrier")
	screen.add_class("carrier")
	screen.add_class("cruiser")
	screen.add_class("cruiser")
	screen.add_class("cruiser")
	# M6 caps the Carrier at one, so the second CV is refused by the core: the fleet buys
	# 2 BB + 1 CV + 3 CA = 66. The test asserts what the rules allow, not the old plan.
	ok(int(FleetPointsRef.total_cost(screen.entries)) == 66,
		"2 BB + 1 CV + 3 CA cost 66 (%d)" % FleetPointsRef.total_cost(screen.entries))
	screen.set_mode("skirmish")
	ok(not bool(FleetPointsRef.validate_structure(screen.entries, screen.budget())["ok"]),
		"the same fleet no longer fits a 60 budget")
	var refused: Dictionary = screen.confirm()
	ok(not bool(refused["ok"]), "and CONFIRM refuses it")
	ok(confirmed_payload.is_empty(), "nothing was emitted")
	ok(not screen.entries.is_empty(), "the fleet was not silently trimmed")


func test_confirm() -> void:
	begin("confirm")
	reset()
	var empty: Dictionary = screen.confirm()
	ok(not bool(empty["ok"]), "an empty fleet cannot be confirmed")
	ok(confirmed_payload.is_empty(), "and emits nothing")
	ok(screen.message.find("empty") != -1, "the operator is told the fleet is empty")
	screen.add_class("fighter")
	screen.add_class("frigate")
	screen.add_class("cruiser")
	var good: Dictionary = screen.confirm()
	ok(bool(good["ok"]), "a valid fleet is confirmed")
	ok(confirmed_payload.get("entries", []) == ["fighter", "frigate", "cruiser"], "the exact fleet travels")
	ok(String(confirmed_payload.get("mode", "")) == "standard", "with its budget mode")
	ok(Vector2i(confirmed_payload.get("size", Vector2i.ZERO)) == MapConfigRef.REFERENCE, "and its battlefield")
	ok(screen.entries.size() == 3, "confirming does not consume the fleet")
	# A fleet that is over budget cannot slip through even if the UI was somehow bypassed.
	reset()
	screen.set_mode("skirmish")
	# 5 x 14 = 70 points against a 60 budget; the class limit (6) is not reached.
	screen.entries.assign(["battleship", "battleship", "battleship", "battleship", "battleship"])
	ok(not bool(screen.confirm()["ok"]), "an over-budget fleet is refused at confirm time")


func test_mouse_hit_test() -> void:
	begin("mouse")
	reset()
	# Click "+" on the Fighter row.
	var fighter_row: int = screen.rows().find("fighter")
	var p: Vector2 = screen.plus_rect(fighter_row).get_center()
	screen._gui_input(_click(p))
	ok(screen.entries == ["fighter"], "clicking + adds that class")
	ok(screen.selected_row == fighter_row, "and selects the row it belongs to")
	# Click "-" on the same row.
	screen._gui_input(_click(screen.minus_rect(fighter_row).get_center()))
	ok(screen.entries.is_empty(), "clicking - removes it")
	# Click "+" on a row that cannot be picked: nothing happens.
	var carrier_row: int = screen.rows().find("carrier")
	screen._gui_input(_click(screen.row_rect(carrier_row).get_center()))
	ok(screen.selected_row == carrier_row, "clicking a row selects it even when unpickable")
	ok(screen.entries.is_empty(), "but does not add anything")
	# Rows must not be reachable through the wrong coordinates.
	for i in range(screen.rows().size()):
		var centre: Vector2 = screen.row_rect(i).get_center()
		ok(screen.row_rect(i).has_point(centre), "row %d contains its own centre" % i)
		for j in range(screen.rows().size()):
			if i == j:
				continue
			ok(not screen.row_rect(j).has_point(centre) or j == i,
				"row %d centre is not inside row %d" % [i, j])
	# The deploy button.
	reset()
	screen.add_class("fighter")
	screen._gui_input(_click(screen.CONFIRM_RECT.get_center()))
	ok(not confirmed_payload.is_empty(), "clicking DEPLOY confirms a valid fleet")
	reset()
	screen._gui_input(_click(screen.CONFIRM_RECT.get_center()))
	ok(confirmed_payload.is_empty(), "clicking DEPLOY on an empty fleet does nothing")


func test_map_toggle() -> void:
	begin("battlefield")
	reset()
	ok(screen.map_size == MapConfigRef.REFERENCE, "the screen opens on the historical board")
	# M7B: [M] now cycles EVERY preset the map configuration knows, not two hardcoded
	# boards. The contract is: one press per preset, in PRESET_NAMES order, and the cycle
	# returns to the reference board - so adding a board cannot leave this screen behind.
	var seen: Dictionary = {screen.map_size: true}
	for i in range(MapConfigRef.PRESET_NAMES.size()):
		screen._unhandled_input(_key(KEY_M))
		seen[screen.map_size] = true
	ok(screen.map_size == MapConfigRef.REFERENCE, "cycling every preset comes back to the reference board")
	ok(seen.size() == MapConfigRef.PRESET_NAMES.size(),
		"the screen can reach all %d battlefields (%d reached)" % [MapConfigRef.PRESET_NAMES.size(), seen.size()])
	reset()
	screen._unhandled_input(_key(KEY_M))
	ok(screen.map_size == MapConfigRef.EXPERIMENTAL, "the first press goes to 32x22")


func test_keyboard() -> void:
	begin("keyboard")
	reset()
	screen.selected_row = screen.rows().find("fighter")
	screen._unhandled_input(_key(KEY_SPACE))
	ok(screen.entries == ["fighter"], "SPACE adds the selected class")
	screen._unhandled_input(_key(KEY_BACKSPACE))
	ok(screen.entries.is_empty(), "BACKSPACE removes it")
	# The selection sits on the Fighter row (index 1) after the SPACE/BACKSPACE pair above.
	screen._unhandled_input(_key(KEY_DOWN))
	ok(screen.selected_row == 2, "DOWN moves the selection")
	screen._unhandled_input(_key(KEY_UP))
	ok(screen.selected_row == 1, "UP moves it back")
	screen.selected_row = 0
	screen._unhandled_input(_key(KEY_UP))
	ok(screen.selected_row == 0, "the selection never goes past the first row")
	for i in range(12):
		screen._unhandled_input(_key(KEY_DOWN))
	ok(screen.selected_row == screen.rows().size() - 1, "nor past the last one")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	var cancelled := [false]
	screen.cancelled.connect(func() -> void: cancelled[0] = true)
	screen._unhandled_input(cancel)
	ok(cancelled[0], "ESC asks to go back")
	# Number keys pick budgets.
	for pair in [[KEY_1, "skirmish"], [KEY_3, "fleet_engagement"], [KEY_4, "grand_fleet"], [KEY_2, "standard"]]:
		screen._unhandled_input(_key(int(pair[0])))
		ok(String(screen.mode_id) == String(pair[1]), "key %s selects %s" % [str(pair[0]), str(pair[1])])


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _click(p: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	return e
