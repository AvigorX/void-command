extends SceneTree
## Frigate and Destroyer: single 1x1 hulls (M6).
##
## M3 had confirmed a 1x2 Frigate; M6 replaced that geometry with 1x1 for both escort
## classes. This suite is the guard: the catalogue, the shipped stats, the instantiated
## ship, the occupied cells, the rotation and the deployment must all agree on ONE cell,
## and the renderer must draw them as a single hull (not as a swarm).

const ShipDefsRef = preload("res://scripts/core/ship_defs.gd")
const ShipRef = preload("res://scripts/core/ship.gd")
const BattleScript = preload("res://scripts/core/battle.gd")
const MapConfigRef = preload("res://scripts/core/map_config.gd")
const FootprintRef = preload("res://scripts/core/footprint.gd")
const FleetRef = preload("res://scripts/core/fleet_points.gd")
const ViewScript = preload("res://scripts/ui/battle_view.gd")

var checks: int = 0
var failures: int = 0

const ESCORTS: Array[String] = ["destroyer", "frigate"]

func _initialize() -> void:
	print("=== VOID COMMAND — DESTROYER / FRIGATE 1x1 (M6) ===")
	for id in ESCORTS:
		test_declared(id)
		test_instance(id)
		test_deployment(id)
	test_rendering()
	test_caps()
	print("")
	print("checks: %d   failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func test_declared(id: String) -> void:
	var d: Dictionary = ShipDefsRef.def(id)
	ok(Vector2i(d["footprint"]) == Vector2i(1, 1), "[%s] DEFS declares 1x1 (got %s)" % [id, str(d["footprint"])])
	ok(Vector2i(ShipDefsRef.catalog_entry(id)["footprint"]) == Vector2i(1, 1), "[%s] CATALOG agrees (1x1)" % id)
	ok(String(ShipDefsRef.catalog_entry(id)["footprint_status"]) == "confirmed", "[%s] the geometry is confirmed" % id)
	ok(FootprintRef.is_valid_size(Vector2i(1, 1)), "[%s] 1x1 is a legal footprint size" % id)


func test_instance(id: String) -> void:
	var s = ShipRef.create(id, 0, 1, 0, {}, 1.0)
	ok(s != null, "[%s] builds" % id)
	if s == null:
		return
	ok(s.footprint == Vector2i(1, 1), "[%s] the instance carries 1x1 (got %s)" % [id, str(s.footprint)])
	ok(s.cells().size() == 1, "[%s] it occupies exactly one cell (%d)" % [id, s.cells().size()])
	# Orientations are enum values 0..3 (DEG_0/90/180/270), not degrees.
	for ori in [0, 1, 2, 3]:
		var e: Vector2i = FootprintRef.extent(s.footprint, ori)
		ok(e == Vector2i(1, 1), "[%s] orientation %d still spans one cell (got %s)" % [id, ori * 90, str(e)])
		var probe = ShipRef.create(id, 0, 2, 0, {}, 1.0)
		probe.cell = Vector2i(5, 5)
		probe.orientation = ori
		ok(probe.cells().size() == 1 and probe.cells()[0] == Vector2i(5, 5),
			"[%s] at %d degrees it stays on its own cell" % [id, ori * 90])


func test_deployment(id: String) -> void:
	for size in [MapConfigRef.REFERENCE, MapConfigRef.EXPERIMENTAL, MapConfigRef.GRAND]:
		var b = BattleScript.new()
		b.setup(11, {}, 1, size, [id], ["fighter"])
		ok(b.deploy_failures.is_empty(),
			"[%s] deploys on %s (%s)" % [id, MapConfigRef.label(size), str(b.deploy_failures)])
		var placed = b.alive_ships(0)[0] if b.alive_ships(0).size() > 0 else null
		ok(placed != null and placed.cells().size() == 1, "[%s] on %s it holds one cell" % [id, MapConfigRef.label(size)])
		# A hull that deploys into a sealed pocket is not really deployed: it must be able
		# to reach other anchors.
		if placed != null:
			var reach: Dictionary = b.reachable_cells(placed.id)
			ok(int(reach.get("dist", {}).size()) > 3,
				"[%s] on %s it has room to move (%d anchors)" % [id, MapConfigRef.label(size), int(reach.get("dist", {}).size())])


func test_rendering() -> void:
	## The renderer must not treat them as swarms: the swarm drawing is selected by class
	## name, so the check is that the formation selector does not include them and that the
	## hull scale fits one cell.
	var view = ViewScript.new()
	ok(view._squadron_slots("fighter").size() == 3, "the Fighter formation is a three-craft V")
	ok(view._squadron_slots("interceptor").size() == 4, "the Interceptor formation is a four-craft dart")
	for id in ESCORTS:
		ok(view.HULL_SHAPES.has(id), "[%s] has a procedural hull shape" % id)
		var shape: PackedVector2Array = view.HULL_SHAPES[id]
		var half_w: float = 0.0
		for p in shape:
			half_w = maxf(half_w, absf(p.x))
		var sc: Vector2 = view.hull_draw_scale(shape, Vector2i(1, 1), 46.0)
		ok(absf(half_w) * absf(sc.x) <= 46.0 * 0.5,
			"[%s] the silhouette stays inside one cell (%.1f px of 23)" % [id, half_w * absf(sc.x)])
	view.free()


func test_caps() -> void:
	for id in ESCORTS:
		ok(int(ShipDefsRef.cap_of(id)) == 0, "[%s] has no numeric cap" % id)
	var fleet: Array[String] = []
	for i in range(6):
		if bool(FleetRef.can_add(fleet, "frigate", 400)["ok"]):
			fleet.append("frigate")
	ok(fleet.size() > 2, "more than two Frigates are allowed (%d)" % fleet.size())


func ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL  %s" % label)
