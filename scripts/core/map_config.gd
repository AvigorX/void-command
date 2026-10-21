class_name MapConfig
extends RefCounted
## Single source of truth for battlefield dimensions (STEP 2 / Block B).
##
## Before this file the grid lived in three places: `BattleMap.WIDTH/HEIGHT`, the
## renderer's `BOARD_W/BOARD_H` and the camera clamp. Now the size is a parameter,
## the renderer derives its pixel geometry from it, and every caller names a preset
## instead of hardcoding numbers.
##
## The reference configuration is a hard compatibility promise: generation on
## 20x14 must stay byte-identical to the pre-STEP2 code, so `BattleMap` keeps the
## original generator for exactly that size and uses a scaled generator for others.

const REFERENCE: Vector2i = Vector2i(20, 14)
const EXPERIMENTAL: Vector2i = Vector2i(32, 22)

## M6: the board a 200 FP fleet needs. Measured, not chosen by taste - two 200 FP fleets
## deployed on each candidate board (tests/_capacity_probe.gd):
##   20x14 -> the generator has to shrink the fleet to 10 hulls to fit
##   32x22 -> 7 deployment failures: it cannot hold the fleets
##   40x28 -> both fleets deploy, 974 free cells, 45 free cells left in a band
##   48x34 -> both fleets deploy, 1479 free cells, 66 free cells left in a band
## 48x34 is the largest board the driver still renders at 19 px cells while keeping the
## HUD unobstructed, and it is the existing MAX_SIZE, so the bounds did not have to move.
const GRAND: Vector2i = Vector2i(72, 72)
## M7B: the largest board the game offers. 6400 cells, 3.92x the 48x34 board the first
## M7 pass shipped and 1.23x the 72x72 one. The scaled generator does the work: obstacle
## counts follow sqrt(area), so the extra space buys manoeuvre room instead of clutter,
## and the deployment band stays six columns wide on both sides (480 cells per side).
const TITAN: Vector2i = Vector2i(80, 80)

## Bounds for a user-facing size. Not a gameplay rule: the presets are what the
## game ships; anything smaller than this cannot hold the deployment zones plus a
## 1x5 hull with room to turn (it needs six columns).
const MIN_SIZE: Vector2i = Vector2i(18, 12)
const MAX_SIZE: Vector2i = Vector2i(80, 80)

const PRESET_NAMES: Array[String] = ["reference", "experimental", "grand", "titan"]


static func size_of(preset: String) -> Vector2i:
	match preset:
		"experimental":
			return EXPERIMENTAL
		"grand":
			return GRAND
		"titan":
			return TITAN
		_:
			return REFERENCE


static func preset_of(size: Vector2i) -> String:
	if size == TITAN:
		return "titan"
	if size == GRAND:
		return "grand"
	if size == EXPERIMENTAL:
		return "experimental"
	return "reference"


static func next_size(size: Vector2i) -> Vector2i:
	## Cycles reference -> experimental -> grand -> reference. One function, so the menu and
	## any future caller cannot disagree about the order.
	var i: int = PRESET_NAMES.find(preset_of(size))
	return size_of(PRESET_NAMES[(i + 1) % PRESET_NAMES.size()])


static func is_valid(size: Vector2i) -> bool:
	return size.x >= MIN_SIZE.x and size.y >= MIN_SIZE.y \
		and size.x <= MAX_SIZE.x and size.y <= MAX_SIZE.y


static func label(size: Vector2i) -> String:
	return "%d×%d" % [size.x, size.y]


static func area_ratio(size: Vector2i) -> float:
	return float(size.x * size.y) / float(REFERENCE.x * REFERENCE.y)
