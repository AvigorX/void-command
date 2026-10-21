class_name Footprint
extends RefCounted
## Grid footprint geometry for ships: pure functions, no nodes, no rendering.
##
## CONTRACT (S1) — invariants every future system must follow
## -----------------------------------------------------------
## 1. Occupied cells are DERIVED, never stored:
##        cells = cells_for(reference_cell, size, orientation)
##    No other code may compute a ship's cells.
## 2. The reference cell is the ship's `cell` and is always the MINIMUM corner
##    (smallest x, smallest y) of the footprint in board axes.
## 3. Orientation selects the EXTENT, never the anchor:
##        0 deg / 180 deg -> extent (size.x, size.y)
##        90 deg / 270 deg -> extent (size.y, size.x)
##    A rectangle is invariant under a 180 deg rotation about its own centre, so
##    0 and 180 (and 90 and 270) produce the SAME cell set. The four values stay
##    distinct because orientation drives the hull's bow direction and future art;
##    it never shifts the reference cell.
## 4. Cells come out in row-major order (dy outer, dx inner) starting from the
##    reference cell: deterministic, and unique for any valid size.
## 5. A 1x1 footprint occupies exactly the reference cell in all four orientations.
## 6. Geometry never depends on sprite size, hull polygons, `facing` or any other
##    rendering detail.
## 7. Invalid input is rejected, never silently "fixed": `cells()` returns an empty
##    array, the `is_valid_*` predicates return false, and `Ship` refuses the value.

enum Orientation { DEG_0 = 0, DEG_90 = 1, DEG_180 = 2, DEG_270 = 3 }

## Sanity bound for one edge (the board is 20x14). This is NOT a gameplay rule:
## board, terrain and occupancy bounds belong to the placement systems (S2).
const MAX_EDGE: int = 20


static func is_valid_size(size: Vector2i) -> bool:
	return size.x >= 1 and size.y >= 1 and size.x <= MAX_EDGE and size.y <= MAX_EDGE


static func is_valid_orientation(orientation: int) -> bool:
	return orientation >= 0 and orientation <= 3


static func extent(size: Vector2i, orientation: int) -> Vector2i:
	## Footprint extent in board axes, or Vector2i.ZERO for invalid input.
	if not is_valid_size(size) or not is_valid_orientation(orientation):
		return Vector2i.ZERO
	if orientation == Orientation.DEG_90 or orientation == Orientation.DEG_270:
		return Vector2i(size.y, size.x)
	return size


static func cells(reference: Vector2i, size: Vector2i, orientation: int) -> Array[Vector2i]:
	## THE authoritative conversion (reference, size, orientation) -> cells.
	## Empty array means the input was invalid.
	if not is_valid_size(size) or not is_valid_orientation(orientation):
		return [] as Array[Vector2i]
	var e: Vector2i = extent(size, orientation)
	var out: Array[Vector2i] = []
	for dy in range(e.y):
		for dx in range(e.x):
			out.append(reference + Vector2i(dx, dy))
	return out


static func offsets(size: Vector2i, orientation: int) -> Array[Vector2i]:
	## Same cells relative to the reference cell, so occupancy and pathfinding code
	## can work from a shape alone without a Ship instance.
	return cells(Vector2i.ZERO, size, orientation)
