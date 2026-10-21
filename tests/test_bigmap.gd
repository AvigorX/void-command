extends SceneTree
## M7B — the 80x80 battlefield: configuration, generation, deployment, navigation, camera.
##
## The mandate asks for a board that is USABLE, not merely accepted by a menu, so this
## suite checks the properties a player would notice: the preset exists and cycles, the
## same seed builds the same map, a 200 FP fleet deploys on both sides with no overlaps
## and no hull outside the grid, every footprint class fits and can turn, every cell can
## be reached with the camera, and a full enemy turn runs without corrupting the board.
##
## It deliberately does NOT assert timings: the numbers live in `bigmap_probe.gd`, because
## an absolute millisecond threshold measures the host.

const BattleScript = preload("res://scripts/core/battle.gd")
const MapScript = preload("res://scripts/core/battle_map.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const AIRef = preload("res://scripts/core/ai.gd")
const BattleScreenScript = preload("res://scripts/ui/battle_screen.gd")
const SaveGuard = preload("res://tests/save_guard.gd")

const TITAN: Vector2i = Vector2i(80, 80)

var checks: int = 0
var failures: int = 0
var current: String = ""
var screen = null
var frames: int = 0
var camera_done: bool = false


func _initialize() -> void:
	SaveGuard.isolate()
	print("=== VOID COMMAND — 80x80 BATTLEFIELD (M7B) ===")
	var before: Dictionary = SaveGuard.snapshot()
	test_configuration()
	test_generation()
	test_deployment()
	test_footprints_and_rotation()
	test_full_turn()
	test_full_battle()
	test_save_untouched(before)
	# The camera checks need a real BattleScreen (its `_ready` builds the Camera2D), so they
	# run on the first frame like test_camera does.
	screen = BattleScreenScript.new()
	root.add_child(screen)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if screen == null or screen.camera == null or screen.view == null:
		ok(false, "the battle screen built its view and camera")
		_finish()
		return false
	if not camera_done:
		camera_done = true
		test_camera_on_the_big_board()
	_finish()
	return false


func _finish() -> void:
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	SaveGuard.cleanup()
	quit(0 if failures == 0 else 1)


# ------------------------------------------------------------- configuration ----

func test_configuration() -> void:
	begin("the preset exists and cycles")
	ok(MapConfigRef.TITAN == TITAN, "TITAN is 80x80")
	ok(MapConfigRef.is_valid(TITAN), "80x80 passes is_valid")
	ok(MapConfigRef.MAX_SIZE.x >= TITAN.x and MapConfigRef.MAX_SIZE.y >= TITAN.y,
		"the bound admits 80x80 (%s)" % str(MapConfigRef.MAX_SIZE))
	ok(MapConfigRef.size_of("titan") == TITAN, "'titan' resolves to 80x80")
	ok(MapConfigRef.preset_of(TITAN) == "titan", "80x80 resolves back to its preset")
	ok(MapConfigRef.label(TITAN) == "80×80", "the label is human readable")
	# Every preset is distinct, valid and reachable from the menu's single cycling call.
	var seen: Dictionary = {}
	var size: Vector2i = MapConfigRef.REFERENCE
	for i in range(MapConfigRef.PRESET_NAMES.size()):
		seen[size] = true
		size = MapConfigRef.next_size(size)
	ok(seen.size() == MapConfigRef.PRESET_NAMES.size(),
		"cycling reaches %d distinct boards" % seen.size())
	ok(size == MapConfigRef.REFERENCE, "cycling comes back to the reference board")
	ok(seen.has(TITAN), "the cycle includes 80x80")
	for preset in MapConfigRef.PRESET_NAMES:
		var s: Vector2i = MapConfigRef.size_of(preset)
		ok(MapConfigRef.is_valid(s), "preset '%s' (%s) is a legal battlefield" % [preset, MapConfigRef.label(s)])
	ok(not MapConfigRef.is_valid(Vector2i(81, 80)), "81x80 is outside the bound")


# ---------------------------------------------------------------- generation ----

func test_generation() -> void:
	begin("80x80 generation is deterministic and playable")
	var a = MapScript.new()
	a.setup(11, TITAN)
	var b = MapScript.new()
	b.setup(11, TITAN)
	ok(a.cell_hash(Vector2i(3, 7)) == b.cell_hash(Vector2i(3, 7)) and a.control_cell == b.control_cell,
		"the same seed builds the identical board")
	var c = MapScript.new()
	c.setup(12, TITAN)
	ok(a.cell_hash(Vector2i(3, 7)) != c.cell_hash(Vector2i(3, 7)), "a different seed builds a different board")

	var blocked: int = 0
	var nebula: int = 0
	for y in range(a.height):
		for x in range(a.width):
			var cell := Vector2i(x, y)
			if a.is_blocked(cell):
				blocked += 1
			elif a.is_cover(cell):
				nebula += 1
	var total: int = a.width * a.height
	ok(blocked + nebula < total / 10, "obstacles stay under 10%% of the board (%d blocked, %d nebula of %d)" % [blocked, nebula, total])
	ok(blocked > 0, "the board is not empty (%d planets)" % blocked)
	ok(not a.is_blocked(a.control_cell), "the relay is not inside a planet")
	ok(not a.is_deploy_zone(a.control_cell, 0) and not a.is_deploy_zone(a.control_cell, 1),
		"the relay is outside both deployment bands")
	# The generator's own acceptance gate: the longest hull must be able to cross the board
	# and almost none of its anchors may sit in an isolated pocket.
	var nav: Dictionary = a.nav_stats(Vector2i(1, 5))
	ok(bool(nav["crosses"]), "a 1x5 hull can cross the 80x80 board")
	ok(int(nav["feasible_anchors"]) > 2000, "it has plenty of legal anchors (%d)" % int(nav["feasible_anchors"]))
	var pockets: float = float(nav["pocket_anchors"]) / maxf(1.0, float(nav["feasible_anchors"]))
	ok(pockets <= 0.08, "pocketed anchors stay under 8%% (%.1f%%)" % (pockets * 100.0))
	# No terrain on a cell a hull must be able to deploy on.
	var terrain_in_band: int = 0
	for y in range(a.height):
		for x in range(a.width):
			var cell2 := Vector2i(x, y)
			if a.is_blocked(cell2) and (a.is_deploy_zone(cell2, 0) or a.is_deploy_zone(cell2, 1)):
				terrain_in_band += 1
	ok(terrain_in_band == 0, "no planet sits inside a deployment band (%d)" % terrain_in_band)


# ---------------------------------------------------------------- deployment ----

func test_deployment() -> void:
	begin("a 200 FP fleet deploys on both sides of 80x80")
	for cls in ["interceptor", "fighter"]:
		var roster: Array[String] = []
		for i in range(120):
			if bool(FleetRef.can_add(roster, cls, 200)["ok"]):
				roster.append(cls)
		var b = BattleScript.new()
		b.setup(7, {}, 1, TITAN, roster, roster)
		ok(b.deploy_failures.is_empty(), "200 FP of %s deploys (%d failures)" % [cls, b.deploy_failures.size()])
		ok(b.alive_ships(0).size() == roster.size(), "the player fleet is complete (%d/%d)" % [b.alive_ships(0).size(), roster.size()])
		ok(b.alive_ships(1).size() == roster.size(), "the enemy fleet is complete (%d/%d)" % [b.alive_ships(1).size(), roster.size()])
		var counts: Array = _containment(b)
		ok(int(counts[0]) == 0, "%s: no occupied cell is outside the grid (%d)" % [cls, int(counts[0])])
		ok(int(counts[1]) == 0, "%s: no two hulls share a cell (%d)" % [cls, int(counts[1])])
		ok(int(counts[2]) == 0, "%s: no ghost hull (%d)" % [cls, int(counts[2])])

	# A capital-heavy fleet: the case that stresses the band and the pocket check.
	var mixed: Array[String] = ["dreadnought", "battleship", "battleship", "carrier", "cruiser",
		"cruiser", "frigate", "frigate", "destroyer", "fighter", "fighter", "interceptor"]
	var bm = BattleScript.new()
	bm.setup(7, {}, 1, TITAN, mixed, mixed)
	ok(bm.deploy_failures.is_empty(), "the capital fleet deploys (%d failures)" % bm.deploy_failures.size())
	var counts2: Array = _containment(bm)
	ok(int(counts2[0]) == 0 and int(counts2[1]) == 0, "the capital fleet stays inside the grid and does not overlap")
	# Deployment is deterministic: the same seed places the same hulls on the same cells.
	var bm2 = BattleScript.new()
	bm2.setup(7, {}, 1, TITAN, mixed, mixed)
	var same: bool = bm.ships.size() == bm2.ships.size()
	if same:
		for i in range(bm.ships.size()):
			if bm.ships[i].cell != bm2.ships[i].cell or bm.ships[i].orientation != bm2.ships[i].orientation:
				same = false
	ok(same, "the same seed produces the same deployment")


func test_footprints_and_rotation() -> void:
	begin("every footprint class fits, turns and moves on 80x80")
	var classes: Array[String] = []
	for id in ShipDefsRef.available_classes():
		classes.append(id)
	ok(classes.size() >= 8, "the catalogue offers %d classes" % classes.size())
	for cls in classes:
		var fp: Vector2i = ShipDefsRef.def(cls)["footprint"]
		var roster: Array[String] = [cls]
		var b = BattleScript.new()
		b.setup(13, {}, 1, TITAN, roster, ["fighter"])
		var s: Ship = null
		for cand in b.alive_ships(0):
			s = cand
		if s == null:
			ok(false, "%s could not be deployed at all" % cls)
			continue
		ok(s.cell.x >= 0 and s.cell.y >= 0, "%s has a real cell" % cls)
		# Horizontal by construction, and the bow points INWARD: team 0 to +x.
		ok(s.orientation == Ship.initial_orientation(fp), "%s deploys at its initial orientation" % cls)
		var extent: Vector2i = FootprintRef.extent(fp, s.orientation)
		ok(extent.y == 1, "%s lies horizontally (extent %s)" % [cls, str(extent)])
		ok(s.bow_vector().x > 0.5, "%s points towards the enemy fleet (+x)" % cls)
		var counts: Array = _containment(b)
		ok(int(counts[0]) == 0, "%s: every occupied cell is inside the grid" % cls)
		# It must be able to turn in the open: clear a generous pocket around the hull.
		var centre := Vector2i(b.map.width / 2 - 2, b.map.height / 2)
		var clear: bool = true
		for cell in FootprintRef.cells(centre, Vector2i(5, 5), 0):
			if not b.map.in_bounds(cell) or b.map.is_blocked(cell):
				clear = false
		if clear:
			s.cell = centre
			s.move_points = 8
			var before: int = s.orientation
			var turned: Dictionary = b.rotate_ship(s.id, (before + 1) % 4)
			ok(bool(turned["ok"]), "%s rotates in open space: %s" % [cls, str(turned.get("reason", ""))])
			ok(s.orientation == (before + 1) % 4, "%s adopted the new orientation" % cls)
			var counts2: Array = _containment(b)
			ok(int(counts2[0]) == 0, "%s: the rotated hull is still inside the grid" % cls)
			# ... and turning into the border must be refused without moving anything. A
			# hull parked on the last row cannot turn vertical (its own length would leave
			# the board); a 1x1 hull can, so the refusal only exists for elongated hulls.
			if fp.x != fp.y:
				s.cell = Vector2i(0, b.map.height - 1)
				var snapshot: Array = [s.cell, s.orientation, s.move_points]
				var refused: Dictionary = b.rotate_ship(s.id, 0)
				ok(not bool(refused["ok"]), "%s: a rotation that would leave the grid is refused" % cls)
				ok(str([s.cell, s.orientation, s.move_points]) == str(snapshot),
					"%s: a refused rotation changes nothing" % cls)
		else:
			# Not a failure of the game: this board happened to be blocked there. Say so.
			print("  note: no open 5x5 pocket for %s near the centre; rotation checked elsewhere" % cls)


func test_full_turn() -> void:
	begin("a full enemy turn runs on 80x80 without corrupting the board")
	var b = BattleScript.new()
	b.setup(21, {}, 1, TITAN)
	ok(b.alive_ships(1).size() > 0, "the enemy fleet deployed (%d hulls)" % b.alive_ships(1).size())
	b.end_turn()
	var counts: Array = _containment(b)
	ok(int(counts[0]) == 0, "after the AI turn no hull is outside the grid (%d)" % int(counts[0]))
	ok(int(counts[1]) == 0, "after the AI turn no two hulls overlap (%d)" % int(counts[1]))
	ok(b.phase == Battle.Phase.PLAYER or b.outcome != "", "control comes back to the player")
	ok(b.round >= 2, "the round advanced (round %d)" % b.round)
	# And a reachable state exists for the longest surviving player hull: the board is not
	# a maze the fleet cannot leave.
	var longest: Ship = null
	for s in b.alive_ships(0):
		if longest == null or s.footprint.y > longest.footprint.y:
			longest = s
	if longest != null:
		longest.move_points = longest.max_move
		var states: Dictionary = b.reachable_states(longest.id)
		ok(not states.get("dist", {}).is_empty(),
			"the longest player hull (%s) has reachable states" % longest.ship_class)


func test_full_battle() -> void:
	begin("a whole battle is played on 80x80")
	## Both sides driven by the AI, on the biggest board, from deployment to an outcome: the
	## mandate asks for at least one complete battle there, and this is the reproducible one.
	var b = BattleScript.new()
	b.setup(4242, {}, 1, TITAN)
	var rounds: int = 0
	while b.outcome == "" and rounds < BattleScript.MAX_ROUNDS:
		rounds += 1
		AIRef.take_turn(b, 0)
		if b.outcome != "":
			break
		b.end_turn()
	ok(b.outcome != "", "the battle reaches an outcome in %d rounds (%s)" % [rounds, b.outcome])
	ok(rounds <= BattleScript.MAX_ROUNDS, "it does not hit the round limit (%d rounds)" % rounds)
	var counts: Array = _containment(b)
	ok(int(counts[0]) == 0, "no hull ended outside the grid (%d)" % int(counts[0]))
	ok(int(counts[1]) == 0, "no hulls ended up overlapping (%d)" % int(counts[1]))
	ok(b.log_lines.size() > 5, "the battle left a combat log (%d lines)" % b.log_lines.size())
	print("  battle on %s: %s in %d rounds, %d player / %d enemy hulls left" % [
		MapConfigRef.label(TITAN), b.outcome, rounds, b.alive_ships(0).size(), b.alive_ships(1).size()])


# -------------------------------------------------------------------- camera ----

func test_camera_on_the_big_board() -> void:
	begin("every cell of the 80x80 board can be seen and selected")
	var b = BattleScript.new()
	b.setup(5, {}, 1, TITAN)
	screen.battle = b
	screen.map_size = TITAN
	screen.view.setup(b)
	# The renderer derives the cell size from the grid: it must still be a legal board.
	var dims: Vector2i = Vector2i(b.map.width, b.map.height)
	ok(dims == TITAN, "the view is rendering an 80x80 board (%s)" % str(dims))
	ok(screen.view.cell_px > 0.0 and screen.view.board_w == float(dims.x) * screen.view.cell_px,
		"the board geometry is derived (%0.1f px cells, %0.0fx%0.0f board)" % [
			screen.view.cell_px, screen.view.board_w, screen.view.board_h])
	screen.camera.zoom = Vector2.ONE
	screen.camera.position = screen.CAM_CENTER
	screen._fit_view()
	var z: float = screen.camera.zoom.x
	ok(z >= screen.ZOOM_MIN and z <= screen.ZOOM_MAX, "Home keeps the zoom in range (%.2f)" % z)
	# The whole board must be visible at the fit zoom, or Home would lie about its promise.
	var half: Vector2 = Vector2(1280.0, 720.0) * 0.5 / z
	var visible: Rect2 = Rect2(screen.camera.position - half, half * 2.0)
	var board: Rect2 = Rect2(screen.view.ORIGIN,
		Vector2(screen.view.board_w, screen.view.board_h))
	ok(visible.encloses(board), "Home shows the whole 80x80 board (visible %.0fx%.0f, board %.0fx%.0f)" % [
		visible.size.x, visible.size.y, board.size.x, board.size.y])
	# Round trip at every cell: clicking maps back to the cell the player aimed at.
	var bad: int = 0
	for y in range(dims.y):
		for x in range(dims.x):
			var cell := Vector2i(x, y)
			var centre: Vector2 = screen.view.cell_center(cell)
			if screen.view.world_to_cell(screen.view.to_local(centre)) != cell:
				bad += 1
	ok(bad == 0, "all %d cells round-trip through screen space (%d failed)" % [dims.x * dims.y, bad])
	# Panning must be able to bring ANY cell into the play area: clamp the camera onto a
	# cell centre and check where that cell lands ON SCREEN. Screen space is the point -
	# the camera's own coordinates say nothing about what the player can see.
	var unreachable: int = 0
	var step: int = 7
	var play: Rect2 = Rect2(screen.PLAY_ORIGIN, screen.PLAY_AREA)
	for y in range(0, dims.y, step):
		for x in range(0, dims.x, step):
			var cell2 := Vector2i(x, y)
			var point: Vector2 = screen.view.cell_center(cell2)
			screen.camera.zoom = Vector2(1.4, 1.4)
			screen.camera.position = point
			screen._clamp_camera()
			if not play.has_point(_screen_of(point)):
				unreachable += 1
	ok(unreachable == 0, "every sampled cell can be panned into the play area (%d unreachable)" % unreachable)
	# And at the fit zoom the whole board must be on screen, left of the HUD panel: this is
	# the assertion that catches the camera framing the viewport instead of the play area.
	screen._fit_view()
	var right_edge: float = _screen_of(Vector2(screen.view.ORIGIN.x + screen.view.board_w, 0.0)).x
	var left_edge: float = _screen_of(screen.view.ORIGIN).x
	ok(right_edge <= 1280.0 - screen.view.HUD_PANEL_W + 0.5 and left_edge >= -0.5,
		"at Home the 80x80 board sits entirely in the play area (%.0f .. %.0f)" % [left_edge, right_edge])


func _screen_of(world: Vector2) -> Vector2:
	## World -> screen for a Camera2D with anchor mode DRAG_CENTER and no smoothing.
	return Vector2(1280.0, 720.0) * 0.5 + (world - screen.camera.position) * screen.camera.zoom.x


# -------------------------------------------------------------------- helpers ----

func _containment(b) -> Array:
	## [outside cells, overlapping cells, ghost hulls]
	var outside: int = 0
	var dupes: int = 0
	var ghost: int = 0
	var seen: Dictionary = {}
	for s in b.ships:
		if s.cell.x < 0 or s.cell.y < 0:
			ghost += 1
		for c in s.cells():
			if c.x < 0 or c.y < 0 or c.x >= b.map.width or c.y >= b.map.height:
				outside += 1
			if seen.has(c):
				dupes += 1
			seen[c] = true
	return [outside, dupes, ghost]


func test_save_untouched(before: Dictionary) -> void:
	begin("save isolation")
	var after: Dictionary = SaveGuard.snapshot()
	ok(str(after["save"]) == str(before["save"]), "the real campaign save is byte-identical")
	ok(str(after["battle"]) == str(before["battle"]), "no real battle snapshot was touched")


func begin(name: String) -> void:
	current = name
	print("- %s" % name)


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  [%s] %s" % [current, label])
