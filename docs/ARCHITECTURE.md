# VOID COMMAND

> **Documento conservato come specifica tecnica** — è il `README.md` originale del progetto
> (ultimo aggiornamento 2026-10-20), spostato qui durante l'archiviazione. Contiene il contratto
> geometrico, le regole, l'architettura e le note di design ed è la fonte autorevole per il *perché*
> delle scelte.
>
> I comandi delle §1 (*Running the game*) e §6 (*Verification*) fanno riferimento al layout di
> sviluppo originale (`G-DEV/` con `projects/void-command/`, `tools/verify-project.sh`,
> `G-DEV-REPORTS/`). Le istruzioni valide per **questo pacchetto** sono in
> [`../README.md`](../README.md) §6–§7 e in [`../CHECKPOINT.md`](../CHECKPOINT.md) §4.
> I riferimenti a `G-DEV-AUDIT/` e `G-DEV-REPORTS/` sono storici: quei materiali non fanno parte
> del pacchetto (il backup dello stato pre-archiviazione è descritto in `../CHECKPOINT.md` §11).
> Le cifre di verifica riportate nel testo sono quelle della milestone M7B; il conteggio misurato
> al momento dell'archiviazione è in `../CHECKPOINT.md` §2.

Turn-based tactical space fleet combat with light strategy and fleet progression.
Built for **Godot 4.7.2** (`4.7.2.stable.official.ed1daf0bf`).

Every visual in the game — hulls, stars, nebulae, planets, beams, explosions,
shields, panels, bars and text — is generated at runtime by GDScript drawing calls.
There are **no imported textures, sprites, fonts, sounds, models or network calls**.

---

## 1. Running the game

```bash
# from the repository root (G-DEV)
./Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe \
    --path projects/void-command
```

Or open the project folder in the Godot 4.7.2 editor and press **F5**.
The main scene is `res://scenes/Main.tscn`; the game boots straight into the menu.

The window is 1280×720 with `canvas_items` stretch, so it scales to any window size
while keeping the tactical layout intact.

---

## 2. Controls

| Input | Action |
|---|---|
| **Left click** friendly ship | select it (roster rows also work) |
| **Left click** highlighted cell | move there (path is drawn as a dotted line) |
| **Left click** bracketed enemy | fire |
| **Q** | arm the selected ship's ability, then click a highlighted target |
| **W** | hold position (spends remaining movement and the attack) |
| **T** | rotate the selected ship 90° in place (free; refused if the hull would clip) |
| **Tab** | cycle through your ships |
| **Space** | end turn |
| **Esc** | pause menu (resume / restart / main menu) |
| **Home** | fit the whole board to the play area |
| **R** | recentre the camera on the board (keeps the zoom) |
| **Right / middle drag** | pan the camera |
| **Mouse wheel** | zoom, anchored on the pointer (0.60× – 2.40×) |
| **Arrow keys** | pan the camera |
| **Wheel over the fleet roster** | scroll a fleet larger than the band |
| **M** (main menu) | cycle the battlefield: 20×14 → 32×22 → 72×72 → 80×80 |
| **F** (main menu) | open fleet composition (fleet points, budget, deploy) |
| **C** (main menu, only when a snapshot exists) | resume the saved battle |
| **1–4** (fleet screen) | Skirmish / Standard / Fleet Engagement / Grand Fleet |
| **↑ ↓ / SPACE / BACKSPACE / ENTER / ESC** (fleet screen) | select / add / remove / deploy / back |
| **M** (fleet screen) | choose the battlefield for the deployment |

Invalid actions are rejected with a written reason in the HUD status line
(out of range, blocked line of sight, occupied cell, cooldown, already fired…).

---

## 3. Rules

### Battlefield
- Two supported configurations, chosen from the main menu with **[M]**:
  **20 × 14** (reference, the historical board) and **32 × 22** (experimental).
  The size is data (`scripts/core/map_config.gd`), not a constant in the renderer.
- Generation is seeded and reproducible **per configuration**. The reference board runs
  the original generator unchanged, so every historical seed still produces the same
  map; the larger board runs a scaled generator whose obstacle counts grow with the
  square root of the area, which buys manoeuvre room instead of a denser minefield.
- **Asteroid field** — impassable, blocks line of sight.
- **Planet** — impassable, blocks line of sight.
- **Nebula** — passable, blocks line of sight, and ships inside take **30% less damage** (cover).
- **Relay station** — optional objective: hold it at the end of a round to score a hold.
  Holding it for **3 rounds** triggers a sector EMP that strips **15 shield** from every
  hostile ship and pays a credit bonus. An enemy on the relay resets your hold counter.
- Player deploys in the four leftmost columns, the enemy in the four rightmost.
  Deployment is guaranteed clear of terrain and never overlaps.
- A connectivity check runs during generation (up to 40 deterministic attempts, then a
  carved corridor fallback), so the two deployment zones are always linked.
- The board always fits the play area: cells are 46 px on 20×14 and 29 px on 32×22, so
  no cell hides behind the HUD panel. Zoom and pan stay available on both.

### Turn structure
```
PLAYER PHASE   each living ship: move up to its MP, fire once, optionally use its ability
END TURN       player commands are locked
ENEMY PHASE    deterministic rule-based AI executes every living hostile ship
ROUND END      relay scoring, shields regenerate 12% of max, MP and attacks reset, cooldowns tick
```
`Battle` is an explicit state machine (`PLAYER` / `ENEMY` / `OVER`). Ending a turn twice,
acting with a destroyed ship, firing twice, firing out of range or through a blocked lane
are all rejected by the rules layer — not by the UI.

### Ships (data-driven, `scripts/core/ship_defs.gd`)

| Class | Hull | Shield | Move | Damage | Range | Armor | Footprint | Ability |
|---|---|---|---|---|---|---|---|---|
| **Fighter** | 38 | 12 | 6 | 11 | 2 | 0 | 1×1 | **Evasive Burn** — +3 move now, incoming damage halved until next round, does not consume the attack (CD 2) |
| **Frigate** | 64 | 26 | 4 | 15 | 3 | 1 | 1×1 | **Precision Strike** — +8 damage, +1 range, ignores armor and cover, consumes the attack (CD 2) |
| **Cruiser** | 104 | 44 | 3 | 20 | 4 | 3 | **1×3** | **Shield Surge** — +26 shield to self or an ally within 3 cells (CD 3) |
| **Battleship** | 160 | 58 | 2 | 32 | 6 | 5 | **1×4** | **Heavy Salvo** — 26 damage to the target, 13 to every hostile adjacent to it (CD 3) |

Capital hulls develop in **length, one cell wide**: the cruiser is `1×3` and the battleship `1×4`
(`3×1` / `4×1` after a 90/270 turn). Each records its **anchor** (minimum corner); every other cell is
derived. `2×2`, `2×3` and `2×4` are not allowed for any class. See §5.2.

Damage model: `raw damage → evasive halving → nebula cover ×0.7 → shields absorb 1:1 →
hull takes max(1, remainder − armor)`. Shields regenerate at the start of a round.

### Victory and defeat
- **Victory**: every hostile ship destroyed.
- **Defeat**: your whole fleet destroyed, or the 40-round limit is reached.
- Mutual annihilation resolves as a defeat.

### Progression
Credits are awarded per battle: base 40, +35 per hostile destroyed, +120 for a victory,
+60 for securing the relay, −10 per ship lost. Credits buy permanent refits
(**+10% hull / +8% weapon damage per level, 3 levels per branch**), saved between sessions.
Enemy fleet size scales with your win count (extra battleship, fighter and cruiser).

Save file: `user://void_command_save.json`, schema versioned:

```json
{ "version": 1, "credits": 0,
  "upgrades": { "fighter": {"hull": 0, "weapon": 0}, "...": {} },
  "stats": {"battles": 0, "wins": 0, "losses": 0},
  "last_seed": 20261019 }
```
Loading is defensive: unknown version → clean defaults, out-of-range values clamped.

The path is injectable — `SaveData.path_override`, or the `VOID_COMMAND_SAVE_PATH`
environment variable — so tests and probes can never write this file (§6.1).

---

## 4. Seeds and determinism

- A new battle uses `int(Time.get_unix_time_from_system()) % 999983`; the seed is shown in the
  result panel and stored in the save file.
- **Rematch** advances the current seed by `7919`, so a fresh map is guaranteed.
- Map generation, deployment, AI tie-breaking and AI jitter all use explicit
  `RandomNumberGenerator.seed` values derived from the battle seed.
- Same seed ⇒ identical terrain, control point, deployment and AI decisions
  (verified in the test suite by comparing full terrain arrays).

---

## 5. Architecture

```
scenes/Main.tscn              root node, swaps screens
scripts/main.gd               app flow, owns the save dictionary

scripts/core/                 pure logic — no nodes, no drawing, runs headless
  ship_defs.gd                ship catalogue, colours, name generator (data-driven)
  footprint.gd                grid footprint geometry: (reference, size, orientation) -> cells
  ship.gd                     runtime ship state, damage intake, per-round reset
  battle_map.gd               seeded terrain, deployment zones, LOS (Bresenham), connectivity
  pathfinder.gd               Dijkstra movement, path reconstruction, BFS distance field
  combat.gd                   damage math only
  battle.gd                   turn state machine, action validation, combat, relay, rewards
  ai.gd                       rule-based enemy tactics (target scoring, movement, abilities)
  save_data.gd                versioned save/load, validation, upgrade purchases

scripts/ui/                   presentation — reads Battle, never mutates outcomes
  battle_view.gd              grid, terrain, ships, overlays, VFX (all CanvasItem drawing)
  hud.gd                      roster, ship readout, combat log, action buttons
  battle_screen.gd            input, camera, screen flow, result/pause overlays
  menu_screen.gd              main menu, controls sheet, upgrade screen
  overlay.gd                  pause / result modal
  starfield.gd                animated parallax background

tests/                        headless + windowed verification (see §6)
  save_guard.gd               save isolation helper: scratch path + real-file fingerprint
  test_save_isolation.gd      end-to-end proof that no suite or probe touches the real save
  test_footprint.gd           footprint / orientation geometry contract
```

Design rules enforced in the code:
- **Combat resolves in `Combat`/`Battle`.** The view only replays `Battle.events`
  (shot, hit, destroy, ability) as cosmetics; deleting every effect changes no outcome.
- **AI talks to the public Battle API only** (``can_attack``, ``move_ship``, ``attack``,
  ``use_ability``, ``reachable_cells``); it has no access to nodes or rendering.
- **Data-driven classes**: adding a ship class means one entry in `ship_defs.gd`
  plus a hull polygon in `battle_view.gd`.
- Every action goes through one validation point (`can_attack`, `can_use_ability`,
  `move_ship`), so the UI and the AI share exactly the same legality rules.

### 5.1 Footprint and orientation contract (S1)

Gameplay dimensions are **data** (`ship_defs.gd`, key `footprint`), not pixels. Every class is `1x1`
today, so no rule changes; the model exists so the next milestone can raise the size of a class
without touching the geometry again.

| Concept | Meaning |
|---|---|
| `Ship.footprint` | `Vector2i(columns, rows)` copied from the class definition at creation |
| `Ship.cell` | the **reference cell**: always the minimum corner (smallest x, smallest y) |
| `Ship.orientation` | `0` = 0°, `1` = 90°, `2` = 180°, `3` = 270° (`Footprint.Orientation`) |
| `Ship.cells()` | the occupied cells, **derived** — never stored |

`Footprint.cells(reference, size, orientation)` is the only conversion in the codebase.

Invariants:

1. Footprint cells are derived from `(cell, footprint, orientation)`; nothing stores them.
2. Cells are unique for any valid size (`1 <= edge <= Footprint.MAX_EDGE`).
3. The output is deterministic: row-major from the reference cell (dy outer, dx inner).
4. A `1x1` ship occupies exactly its reference cell in **all four** orientations.
5. Rotation never moves a `1x1` ship: position, movement, attack, damage and AI are unchanged.
6. Geometry never depends on hull polygons, sprite size, `facing` or any rendering detail.
7. Orientation selects the **extent**, not the anchor: `0°/180°` → `w × h`, `90°/270°` → `h × w`.
   A rectangle is point-symmetric, so `0°`/`180°` (and `90°`/`270°`) occupy the same cells; the values
   stay distinct because orientation drives the hull's bow direction and future art.

Invalid input is rejected, never "fixed silently": `Footprint.cells()` returns an empty array,
`is_valid_size()` / `is_valid_orientation()` return false, and `Ship.set_footprint()` /
`Ship.set_orientation()` refuse the value without touching ship state.

`hull_box` in `ship_defs.gd` is **legacy, unreferenced** data and is deliberately *not* the gameplay
dimension.

### 5.2 Multi-cell engine (S2–S5), length-only hulls and the (cell, orientation) search (STEP2)

The rules layer is footprint-aware end to end. **Two classes are multi-cell**: the cruiser is `1×3` and
the battleship `1×4` (`3×1` / `4×1` after a 90/270 turn). Fighter and frigate stay `1×1`. Every capital
hull is **one cell wide**, so length - not width - is the manoeuvre constraint.

| Concern | Rule |
|---|---|
| Occupancy | `Battle.occupied()` is **derived** on every call (no cache → it cannot go stale). `ship_at(cell)` resolves *any* footprint cell to its owner; `cells_of(id)` lists them; `occupancy_conflicts()` is the invariant probe. |
| Placement | `can_place(cell, size, orientation, except_id)` is the single verdict (bounds + terrain + occupancy); `placement_problem()` returns the human-readable reason. |
| Deployment | `Battle._take_deployment_cell()` pops the cell single-cell deployment would have used first, then keeps popping from the same shuffled pool if the whole footprint does not fit. **No extra RNG draws**, so the same seed reproduces the same fleet. `_footprint_in_zone()` requires every cell inside the team's zone. |
| Movement | `move_ship(id, dest, orientation := -1)`: a multi-cell hull is routed through the `(cell, orientation)` search and commits that route, so it may **turn on the way** and still arrive at the ordered orientation. **All checks run before any mutation**, so a refusal changes nothing. `rotate_ship()` is the explicit in-place order (also bound to `R`). |
| Pathfinding | `Pathfinder.explore_states()` searches `(anchor, orientation)` with translation edges (cost 1) and rotation edges (**cost 0** - rotation in place is free in these rules). Every edge re-validates the whole footprint. `explore()` is kept verbatim for `1×1` hulls, which therefore keep their original frontier, numbers and tie-breaking. |
| Rotation | Free and validated: the rotated footprint must fit where the ship is, so a hull cannot rotate through a rock, a ship or the edge. A refused rotation leaves position and orientation untouched. |
| Range | **Minimum** Manhattan distance between any occupied cell of the attacker and any of the target. |
| Line of sight | One clear source-cell/target-cell pair is enough. Planets and nebulae block it; asteroid fields were removed in M6. |
| Cover | A hull is in cover when **any** occupied cell is a nebula; the 30 % reduction is applied **once** (`Battle.ship_in_cover`, passed to `Combat.resolve`). For `1×1` this is exactly the old cell rule. |
| Area weapons | `Combat.splash_targets()` uses the minimum distance between any pair of occupied cells, lists each ship at most once and never the struck hull, so a hull is never damaged twice for occupying several cells. |
| Interaction | Every occupied cell identifies its owner: selection, targeting and ability targets work from any cell. Movement destinations remain **anchors**, and the order carries the orientation the overlay showed. |
| Rendering | `battle_view.ship_center()` is the footprint centre (identical to the cell centre for 1×1). Multi-cell hulls draw once, aligned with the footprint's long axis and scaled to it; footprint fill under the hull and cell borders on top; the movement overlay shows the footprint **at the orientation the anchor is reached at**. `1×1` drawing is unchanged. |

Known limitations after STEP2 (see `G-DEV-AUDIT/void-command-m1/STEP2-REPORT.md`):

1. Rotation edges are free in the search, so a route may turn more than a player would; the search
   minimises translations, not turns. A hull can therefore wiggle through an L-shaped gap that a
   turn-counting rule would refuse. Deliberate: rotation is free in the rules.
2. The AI looks **one turn ahead**. A hull that cannot reach a firing position this round picks the best
   single state, which can park it behind a blocking nebula (line of sight blocked, distance not). With
   the STEP2 hulls no `balance_probe` seed loses to this any more (8/8), but it is one bad layout away -
   `seed 5` did lose for exactly this reason under the previous geometry. Multi-turn planning is the next
   AI milestone, not a geometry defect.
3. The remaining strategic debt is the deployment **pocket check**: a hull is still deployed wherever its
   footprint fits, without asking whether the connected free area can reach the enemy half.

### 5.3 Fighter squadron drawing (STEP2, visual only)

The Fighter keeps a `1×1` footprint and one cell of occupancy; only its silhouette
changed. `battle_view._draw_squadron()` draws a leader plus two wingmen in a tight V,
with a per-ship phase offset and two faint contrails, inside the same hull transform as
every other class — so facing, selection ring, hover, health bars and the overlays keep
working untouched. Three shapes inside one cell read as *one* unit because they share
the team palette, are outlined in the same trim colour and are joined by the contrails.

Nothing in the rules layer knows about the formation: stats, range, damage, targeting,
deployment, saves and AI are unchanged, and there are no independently selectable craft.
Evidence: `G-DEV-REPORTS/void-command-step2/shot_f0*.png` (idle, selected, beside a
capital hull, mid-move, overlays, 32×22 board), inspected at 1:1 and zoomed.

### 5.4 Map configuration (STEP2, Block B)

| Concern | Where it lives | Rule |
|---|---|---|
| Sizes | `scripts/core/map_config.gd` | `REFERENCE` 20×14, `EXPERIMENTAL` 32×22, `GRAND` 72×72, `TITAN` 80×80, presets by name, min/max bounds (18×12 … 80×80) |
| Generation | `BattleMap.setup(seed, size)` | reference size runs the ORIGINAL generator byte for byte; other sizes run `_build_scaled()` |
| Battle | `Battle.setup(..., map_size)` | records `map_size`; an invalid size falls back to the reference board |
| Rendering | `battle_view.cell_px` | derived from the grid: `min(46, play_w/cols, play_h/rows)`; 20×14 still yields 46 px / 920×644, 80×80 yields 8 px / 640×640 |
| Camera | `battle_screen._clamp_camera()` | pan limits derived from the board rect; a board smaller than the view is centred on the play area **without cutting its edge columns** |
| Menu | `menu_screen.map_size` | [M] cycles every preset; the list is generated from `MapConfig.PRESET_NAMES`, never hardcoded |

The same-seed reproducibility guarantee is **per configuration**: `tests/test_maps.gd`
pins ten 20×14 fingerprints taken before the change, and asserts that the two
configurations are reproducible independently rather than identical to each other.

### 5.5 Class catalogue and fleet points (STEP3)

Two tables, deliberately not one:

| Table | File | Contains |
|---|---|---|
| `DEFS` | `ship_defs.gd` | the four **playable** classes with full statistics — what `Ship.create` can build |
| `CATALOG` | `ship_defs.gd` | all **eight** named classes, plus footprint status and the four availability flags |

A class is **defined** when it has a catalogue entry, **implemented** when `DEFS` holds
statistics, **available** when composition may offer it, **deployable** when the footprint
is confirmed and the deployment supports it, and **active** when the mode authorises it.
`validate_catalog()` enforces the two rules that matter: an unconfirmed footprint can never
be available, and a class that is not implemented can never be deployable. `Ship.create()`
now refuses an unknown class explicitly instead of silently building a Fighter.

| Class | Footprint | Cost | Cap | Hull/shield | Move | Range/dmg | State |
|---|---:|---:|---:|---|---:|---|---|
| Interceptor | 1×1 | 2 | — | 26 / 8 | 7 | 2 / 8 | implemented, active |
| Fighter | 1×1 | 3 | — | 38 / 12 | 6 | 2 / 11 | implemented, active |
| Destroyer | **1×1** | 5 | — | 52 / 18 | 5 | 3 / 13 | implemented, active |
| Frigate | **1×1** | 6 | — | 64 / 26 | 4 | 3 / 15 | implemented, active |
| Cruiser | 1×3 | 9 | — | 104 / 44 | 3 | 4 / 20 | implemented, active |
| Carrier | 1×5 | 11 | **1** | 118 / 52 | 2 | 5 / 16 | implemented, active |
| Battleship | 1×4 | 14 | **2** | 160 / 58 | 2 | 6 / 32 | implemented, active |
| Dreadnought | 1×5 | 18 | **1** | 210 / 78 | 1 | 6 / 40 | implemented, active |

An em dash in the Cap column means **no numeric cap at all** (M4): the budget, the caps of the
other classes and the battlefield are the only limits. `MAX_SHIPS` — the old global cap of
eight hulls — was deleted, and a test asserts it is gone from the API rather than merely
unused. The three caps live in `ShipDefs.CATALOG["cap"]`, so there is one source of truth and
`validate_catalog()` rejects a cap on a class that is not implemented.

### 5.7 Battlefield, camera, geometry and the Carrier (M6)

**Battlefield.** M6 shipped `MapConfig.GRAND` at **48×34**, chosen by measurement: with the same
fleet deployed on both sides, 32×22 fails to hold two 200 FP fleets (7 deployment failures),
40×28 just fits, 48×34 fits with 1479 free cells and 66 free cells left in a deployment band.
The first M7 pass raised it to **72×72** and M7B added **80×80** (`TITAN`, `MAX_SIZE`): see §5.8.
The menu cycles every preset through `MapConfig.next_size`.

**Camera.** `Camera2D` with pointer-anchored zoom (`_zoom_by(factor, focus)` inverts
`world = position + (screen − centre)/zoom`), **Home** fits the whole board to the play area and
**R** recentres it. Zoom range 0.60–2.40. The clamp centres on the **play area** (928×666 left of
the HUD), not on the window: a 48×34 board was sliding under the HUD panel. The HUD lives in its
own `CanvasLayer`, so it never inherits the camera scale.

**Asteroids are gone.** Removed from the terrain enum, both generators, the block/LOS rules, the
renderer and the tests. Planets still block movement and line of sight; nebulae still block line
of sight and reduce damage. All ten reference fingerprints moved **on purpose** — the old and new
values sit side by side in `tests/test_maps.gd`.

**Geometry.** Interceptor 1×1 (dart swarm), Fighter 1×1 (V swarm), **Destroyer 1×1**, **Frigate
1×1**, Cruiser 1×3, Carrier 1×5, Battleship 1×4, Dreadnought 1×5. The engine pulse is gone from
the two swarm classes: their formations are static, and the engine plume no longer animates.

**Carrier.** Cap is **1** per fleet, enforced in the core. Its ability is `LAUNCH SQUADRON`: one
**real** 1×1 Interceptor swarm per round (selectable, movable, attackable), up to **10 per
battle**, then exhausted for good. The counter lives on the ship and is part of the battle
snapshot, so a resumed battle does not hand out ten fresh swarms. If no adjacent cell is free the
launch is refused and nothing is consumed.

### 5.8 The 80×80 battlefield, controls and HUD (M7B)

**Board.** `MapConfig.TITAN` is **80×80** (6400 cells, `MAX_SIZE`), added next to
`REFERENCE 20×14`, `EXPERIMENTAL 32×22` and `GRAND 72×72`. The menu and the fleet screen both
cycle `MapConfig.PRESET_NAMES` through `next_size()`, so a new preset cannot leave one screen
behind. 80×80 runs the scaled generator: obstacle counts follow √area, so the extra space buys
manoeuvre room instead of clutter (measured: obstacles stay under 10% of the board, a 1×5 hull
crosses it, and no planet is generated inside a deployment band — the band is six columns wide
and the generator used to protect only four). That fix changes the **32×22** maps (terrain
digest on seeds 1009/7/11 differs; seed 11 loses a planet that would have sat in the band) while
**20×14 and, for those seeds, 72×72 stay byte-identical**.

**Rendering and camera.** `cell_px` is derived from the grid: 8 px on 80×80, board 640×640, so
**Home** fits the whole board inside the play area at zoom ≈1.0. Cells stay 8 world px at any
zoom (the camera is a transform), so zooming in is what makes a hull readable; health bars
scale with the cell below 14 px and sit inside the footprint instead of spanning four cells.

The camera frames the **play area**, not the viewport. A `Camera2D` centres its viewport, so
setting `camera.position` to the play-area centre shifted the board 152 px to the right: on the
reference 20×14 board the enemy fleet was drawn at screen x = 1024 — **behind the HUD panel**,
invisible and unclickable. Everything now goes through `_play_offset()`, and both the camera
suite and `visual_probe` assert the mapping in **screen space** (a hull must land inside the
892×666 play rect) instead of comparing `camera.position` to a screen constant.

**Controls.** **T** rotates the selected hull; **R** keeps its M6 meaning (recentre the
camera). Before this, `rotate_cw` was bound to R while R was consumed by the camera, so the
rotation key did nothing and the README documented the wrong key. The HUD detail line shows
`T ROTATE 90° IN PLACE`, and the status line reports the resulting extent or the refusal
reason.

**Bows.** `Ship.bow_vector()` is the single source of the drawn bow. A 1×1 hull keeps `facing`;
a multi-cell hull points along its own long axis, taking the sense from `facing` when it is
parallel, otherwise from the fleet's inward direction (team 0 → +x, team 1 → −x). The old
expression `(orientation + long_axis)` had no sense, so every capital hull in *both* fleets was
drawn pointing left.

**Roster and spent actions.** The roster band ends where the DETAIL section starts (it used to
run to y=596, through the detail panel and the combat log). Rows never shrink below 20 px; a
fleet that does not fit **scrolls** (wheel over the roster, and the selection is scrolled into
view automatically). `Ship.action_state()` derives READY / PARTIAL / DONE from `move_points`
and `has_attacked` — never stored, so the indicator cannot drift from the engine. The roster
row shows a cyan dot, an amber dot or a hollow orange square plus `NO ACTIONS`; on the board
the spent hull is dimmed with a grey ring, which is distinct from the cyan selection ring and
from a destroyed hull (not drawn as a ship at all).

**Measured cost (same machine, back to back, 200 FP fleets = 52 hulls per side).** The A/B is
`2f6132e` (before) against the M7B tree, both with `tests/bigmap_probe.gd` (the old tree has no
80×80, so that column is new-only):

| board | map gen ms | setup ms before → after | deployment ms before → after | AI turn ms before → after |
|---|---:|---|---|---|
| 20×14 | 51 | 5172 → **2629** | 5088 → 2562 | 2385 → **1673** |
| 32×22 | 147 | 11565 → **1621** | 11297 → 1450 | 6342 → **3345** |
| 48×34 | 464 | 11738 → **865** | 11400 → 430 | 10148 → **5895** |
| 72×72 | 1189 | 18922 → **1548** | 17686 → 331 | 38984 → **16690** |
| 80×80 | 1438 | — → **1791** | — → 235 | — → **21055** |

Three measured changes produced it, each with an equivalence proof:

1. **`Pathfinder.explore_states` uses a binary heap** instead of scanning the frontier on every
   pop (O(states²) before). Same lexicographic order; `tests/test_pathsearch_equivalence.gd`
   keeps a copy of the old linear scan and compares distances, rotation counts, parent links,
   per-anchor orientations and the reconstructed routes over 144 cases → **1440 checks, 0
   differences**.
2. **`Pathfinder.escapes_deploy_band`** answers the deployment pocket question and stops at the
   first escaping anchor, instead of materialising every reachable state. Same predicate
   (removing the need to scan a dictionary of states per candidate) → the deployment search is
   the piece that fell by 12–50×. The same suite compares the predicate against the full search
   on every board, footprint, budget and side.
3. **The AI scores each state once** and skips states whose cheap upper bound already proves
   they cannot win; candidates are visited nearest-to-target first so the bound bites early.
   Bit-identical decisions, proven by `tests/ai_decisions_probe.gd` diffed old-vs-new on 16
   blocks (4 seeds × 2 boards × map/flat): **15/16 identical**, the only difference being the
   32×22 map whose terrain changed on purpose. `balance_probe` is also byte-identical.

**Residual, measured:** a 52-hull enemy turn still costs ~21 s on 80×80 (~0.4 s per hull), and
map generation alone is ~1.4 s because `nav_stats()` walks 25,600 (cell, orientation) states per
candidate layout. Both are documented rather than hidden; the default fleets (4–9 hulls) pay
well under a second.

### 5.6 Navigability (M5)

Deployment validity is not navigability, so the generator now checks the route. `BattleMap.nav_stats(footprint)`
builds the same `(anchor, orientation)` state graph the route search uses (translations cost 1,
rotations are free and legal only where the whole hull fits) and reports how much of the board a
hull can reach from its deployment band.

Measured on 10 seeds per board, before the change: a 1×5 hull crossed the board **10/10** times
and reached 77–100% of its feasible anchors on 20×14 (99–100% on 32×22). The real defect was
narrower than "asteroids block the map": **one seed in ten** left a 156-anchor pocket walled off
from a 5-cell hull. The generator now rejects a map where the largest hull cannot leave its band
or where more than 8% of its feasible anchors sit in isolated pockets.

Consequence for the pinned fingerprints: **nine of ten are unchanged**; seed 11 on 20×14 is
different on purpose (`1295843028 → 46407517`), and `tests/test_maps.gd` records both values next
to each other so the migration is auditable. `tests/test_navigation.gd` (99 assertions) is part of
the gate.

**Fleet points** (`scripts/core/fleet_points.gd`) are a per-battle budget: Skirmish 60,
Standard 100, Fleet Engagement 150, Grand Fleet 200. They are **not** credits — nothing in
the composition screen reads or writes `save_data.gd`, and no fleet point is ever stored in
the save file (`tests/test_fleet.gd` asserts the raw JSON contains no such key).

Rules, all enforced by the core and only *displayed* by the UI:
- only implemented + available + confirmed classes may be added;
- the per-class cap where one exists (Dreadnought 1, Battleship 2, Carrier 1), and **no
  fleet-wide hull cap** — a 100 FP fleet may hold more than eight hulls;
- `validate()` = budget/structure **and** `deployable()`, which builds a real trial battle
  and refuses a fleet the chosen battlefield cannot hold. A budget-valid fleet is not
  automatically a deployable one, and the two verdicts stay separate.

The enemy fleet is generated deterministically from `(seed, budget, map_size)` with a
bounded loop, a deterministic fallback and the same validity checks; it never reaches for
Carrier or Dreadnought to fill the budget.

---

## 6. Verification (measured, not claimed)

All commands are run from the repository root.

```bash
ENGINE=./Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
PKG=projects/void-command

# core rules: 139 assertions
$ENGINE --headless --path $PKG --script res://tests/test_core.gd

# full scene: menu → battle → actions → result → rematch: 47 assertions
$ENGINE --headless --path $PKG --script res://tests/test_ui.gd

# acceptance: every menu/HUD button, all four abilities, invalid actions, pause,
# defeat, result overlay and rematch through the real scene: 80 assertions
# (fixed seed 20261019, printed at startup so a failure is reproducible)
$ENGINE --headless --path $PKG --script res://tests/test_acceptance.gd

# stress: 30 seeded maps, replay determinism, max difficulty, 20-seed campaign,
# 30-round soak, timings: 27 assertions
$ENGINE --headless --path $PKG --script res://tests/test_stress.gd

# footprint / orientation geometry contract: 157 assertions
$ENGINE --headless --path $PKG --script res://tests/test_footprint.gd

# multi-cell engine (occupancy, deployment, movement, rotation, pathfinding,
# targeting, cover, area weapons, rendering) + a real 1x4 battleship lifecycle:
# 204 assertions
$ENGINE --headless --path $PKG --script res://tests/test_multicell.gd

# (cell, orientation) route search + footprint-aware AI: 70 assertions
$ENGINE --headless --path $PKG --script res://tests/test_pathfinding.gd

# battlefield configurations: reference fingerprints, 32x22, determinism,
# deployment on both, derived render geometry: 106 assertions
$ENGINE --headless --path $PKG --script res://tests/test_maps.gd

# the same 10-seed campaign on BOTH sizes, with termination/overlap/refusal
# assertions: 15 assertions
$ENGINE --headless --path $PKG --script res://tests/test_map_stress.gd

# save isolation gate: runs every suite above as child processes and proves
# the player's real save is byte-identical afterwards: 32 assertions
# (add --with-gui to include the three windowed probes)
$ENGINE --headless --path $PKG --script res://tests/test_save_isolation.gd

# visual probe (opens a window, writes PNGs to ../../G-DEV-REPORTS/void-command/)
$ENGINE --path $PKG --script res://tests/visual_probe.gd

# capital-hull evidence probe: selected / rotated / targeting / invalid click /
# destroyed, PNGs in ../../G-DEV-REPORTS/void-command-step2/
$ENGINE --path $PKG --script res://tests/step1_visual_probe.gd

# Fighter squadron evidence: idle / selected / beside a capital hull / moving /
# overlays / 32x22 board, 6 PNGs in ../../G-DEV-REPORTS/void-command-step2/
$ENGINE --path $PKG --script res://tests/step2_fighter_probe.gd

# class catalogue: eight defined, four implemented, footprint status, and the
# validator fed DELIBERATELY BROKEN entries: 160 assertions
$ENGINE --headless --path $PKG --script res://tests/test_catalog.gd

# fleet points: budgets, composition limits, deployment geometry on both boards,
# deterministic enemy generation, points-vs-credits separation: 1796 assertions
# (~90 s: it builds real trial battles, which is the point)
$ENGINE --headless --path $PKG --script res://tests/test_fleet.gd

# fleet composition screen: rows, +/- affordances, hit-testing, confirm gate,
# keyboard navigation: 155 assertions
$ENGINE --headless --path $PKG --script res://tests/test_fleet_ui.gd

# fleet-screen evidence: empty / valid / refused class / over budget /
# 32x22 board, 5 PNGs in ../../G-DEV-REPORTS/void-command-step3/
$ENGINE --path $PKG --script res://tests/step3_fleet_probe.gd

# balance/AI activity diagnostic
$ENGINE --headless --path $PKG --script res://tests/balance_probe.gd

# one-command gate (syntax on every script + import + boot + a test)
bash tools/verify-project.sh $PKG res://tests/test_core.gd
```

Last measured results in this environment (2026-10-19, STEP 2.1 / STEP 3 — catalogue and fleet points):

| Run | Result |
|---|---|
| `test_core.gd` | **139 checks, 0 failures, exit 0** |
| `test_ui.gd` | **47 checks, 0 failures, exit 0**, no engine errors |
| `test_acceptance.gd` | **80 checks, 0 failures, exit 0**, no engine errors |
| `test_stress.gd` | **27 checks, 0 failures, exit 0**; 30/30 maps valid, replay-identical AI, max difficulty resolves, 20/20 seeds finish, soak clean |
| `test_footprint.gd` | **157 checks, 0 failures**; declared footprints (cruiser 1×3, battleship 1×4), the "one cell wide" rule asserted on the live catalogue, all four orientations of a 1×1 hull, 1×2 / 2×3 geometry fixtures, non-square rotation, invalid input, purity, determinism |
| `test_multicell.gd` | **204 checks, 0 failures**; occupancy ownership and conflicts, footprint deployment (RNG order, occupied/rock/zone refusals, exhausted pool), bounds/terrain/overlap rejection, cell release on move and destruction, preview==rules, corridor needing a turn, rotation at edges/beside rocks/ships, atomicity, footprint range and LOS, cover applied once, area damage applied once, relay from a non-anchor cell, rendering geometry, a real 1×4 lifecycle (move → rotate → fire → destroy → victory), the one-cell door (2-wide hull refused, shipped 1×4 passes) |
| `test_pathfinding.gd` | **70 checks, 0 failures**; 1×1 identity with `explore()`, 1×3/1×4/1×5 routes, rotation allowed/refused, anchor-free-but-hull-blocked, corridor that only works at one orientation, edges, AI destination executability, no revisited state, goal reachability over turns, determinism |
| `test_maps.gd` | **106 checks, 0 failures**; ten pinned 20×14 fingerprints, both sizes declared, per-size determinism, obstacle density, deployment on both boards at three difficulties, long-hull manoeuvre and crossing, derived render geometry with a `world_to_cell` round-trip over every cell, invalid-size fallback |
| `test_map_stress.gd` | **15 checks, 0 failures**; 10 seeds per size, all terminate, zero overlapping hulls, zero refused AI moves, relay reachable on both boards |
| `test_deployment.gd` | **31 checks, 0 failures**; deployment pockets, unplaced hulls not blocking cells, move budgets, tight doors |
| `test_hud.gd` | **18 checks, 0 failures**; roster row metrics as a function of fleet size, a click reaches every row, board geometry |
| `test_battle_save.gd` | **54 checks, 0 failures**; snapshot round trip (hull fields, footprint, orientation, occupancy, turn, relay), determinism for four rounds after a restore, reward paid once, seven invalid snapshots, path separation |
| `test_catalog.gd` | **160 checks, 0 failures**; eight classes defined / four implemented, footprint statuses, costs, ability kinds, the validator rejected on five deliberately broken entries, `Ship.create` refuses unimplemented classes |
| `test_fleet.gd` | **1796 checks, 0 failures**; budget arithmetic, composition limits (class, hulls, budget), core-side enforcement, deployment geometry on both boards, 80 generated enemy fleets validated + reproducible, generator termination (60 runs), points-vs-credits separation, and a composed battle that deploys and takes an AI turn |
| `test_capital.gd` | **205 checks, 0 failures**; 1×5 hulls deploy on both boards, rotate only where the hull fits, refuse a move whose tail is blocked, the S5 five-lane rule, the caps reaching the battlefield, and the drawing contract: every silhouette stretched to its footprint stays inside one cell (with a regression guard on the old uniform scale, which drew a battleship 74 px wide on a 46 px cell) |
| `test_frigate.gd` | **133 checks, 0 failures**; 1×2 geometry in all four orientations, rotation without moving the reference cell, both cells occupied and released, deployment on both boards, route search over (cell, orientation), the S5 "one clear lane" rule on a two-cell hull, fleet points and neighbours unchanged, unimplemented classes still refused |
| `test_fleet_ui.gd` | **155 checks, 0 failures**; eight rows, +/-, hit-testing without overlap, confirm gate on empty/over-budget fleets, keyboard navigation and budget keys, battlefield toggle |
| `visual_probe.gd` | **49 checks, 0 failures**; 9 PNGs (menu, controls, upgrades, battle, selection, combat, pause, enemy turn, result) |
| `step1_visual_probe.gd` | **20 checks, 0 failures**; 6 PNGs of the shipped capital hull |
| `step2_fighter_probe.gd` | **21 checks, 0 failures**; 6 PNGs of the Fighter squadron (idle, selected, beside a capital hull, mid-move, overlays, 32×22) |
| `test_save_isolation.gd` | **32 checks, 0 failures** (`--with-gui`); runs the nine headless suites plus all three windowed probes as children and proves the real save is byte-identical |
| `balance_probe.gd` | **8/8 seeds**, 9–34 rounds, AI 185 attacks / 239 moves / 57 abilities (STEP1 baseline: 7/8, 197/256/58) |
| `verify-project.sh` | 32 scripts parse, import clean, headless boot exit 0 |
| **total** | **3082 assertions, 0 failures across 15 headless suites** (845 at STEP 2, 641 at STEP 1) |

### 6.1 Test isolation (S0)

Tests and probes never write the player's real save. `SaveData` exposes an explicit
injectable path:

```gdscript
SaveData.path_override = "user://void_command_save.test.json"   # set before any load/save
```

Resolution order: `path_override` → `VOID_COMMAND_SAVE_PATH` environment variable → the
production `user://void_command_save.json`. Every suite calls `SaveGuard.isolate()` in
`_initialize()`, runs against the scratch file, and asserts at the end that the real file is
byte-identical (`SHA-256` + size + existence). This is **isolation, not replacement**, so there is
no backup to lose: a crash, an assertion failure or a timeout cannot damage player data, because the
production file is never opened for writing. The scratch file is deleted on a normal exit and is
harmless if a crash leaves it behind.

```bash
# gate that proves it end to end (add -- --with-gui to include the windowed probe)
$ENGINE --headless --path $PKG --script res://tests/test_save_isolation.gd
```

Measured timings on this machine (headless): map generation **10.5–13.0 ms**, enemy AI turn
**14.1–18.5 ms** for a full 5-ship turn, well inside an interactive turn-based budget.

The core suite covers: seed determinism, deployment legality, movement/path rules,
blocked movement, occupied cells, out-of-range and friendly-fire rejection,
line-of-sight blocking and restoration, the full damage model (shield → armor → hull,
evasion, armor bypass, nebula cover), destruction and targeting cleanup, turn transitions,
double-transition rejection, all four abilities, save/upgrade logic, AI legality over
multiple turns, the relay objective, simultaneous fleet destruction, the round limit,
and three complete battles.

---

## 7. Known limitations

- **No audio.** Procedural sound would require generating `AudioStreamWAV` buffers;
  out of scope for this build.
- **Battle start costs one frame.** Measured (200 FP fleets, 52 hulls per side) `Battle.setup()`
  is 1.5 s on 72×72 and 1.8 s on 80×80 after M7B; it was 19 s on 72×72 before the deployment
  search was fixed. Map generation alone is 1.2–1.4 s on the big boards because `nav_stats()`
  walks 25,600 (cell, orientation) states per candidate, and it is now the largest single piece
  of the hitch. One-off at battle start, not per frame.
- **A 52-hull enemy turn costs ~21 s on 80×80** (~0.4 s per hull; 1.7 s on 20×14), and the AI
  runs synchronously inside `end_turn`, so the window is unresponsive for that time. The default
  fleets (4–9 hulls) stay under half a second. Improving it further means a cheaper
  line-of-sight test or an incremental enemy turn; both are outside what this milestone
  measured.
- **The 40-round limit does not scale with the board.** Measured on 80×80 with both sides
  driven by the deterministic AI: 5 of 6 battles (budgets 0 / 60 / 100 FP, 9–29 hulls) ended at
  the round limit with survivors, because the fleets start ~68 cells apart and the AI closes at
  a couple of cells per turn. On 20×14 the same rule is generous. Changing it means changing a
  victory condition, so it is **not** changed here: a per-board limit (e.g. derived from
  `MapConfig.area_ratio`) is the obvious fix and needs a mandate.
- **Cells are 8 px on 80×80** (29 px on 32×22, 19 px on 48×34, 9 px on 72×72). The whole board
  fits at zoom ≈1.0, and the camera zooms to 2.40×, but nothing is legible at the fit level: the
  big board is meant to be played zoomed in, with Home for an overview.
- **The roster band shows 7 rows** (122–274 px) whatever the fleet size; a 52-hull fleet is
  scrolled with the wheel rather than squeezed. Nothing is hidden and the selected hull is always
  scrolled into view, but there is no two-column roster.
- **Carrier and Dreadnought** have confirmed 1×5 footprints and full statistics (M4/M6); the two
  remaining gaps are the refit track (the save upgrades only the original four classes) and
  per-budget win rates, which are not measured.
- **Single-player only**, no networking (by design, offline-first).
- **AI has no lookahead** — it is a deterministic greedy evaluator with seeded jitter.
  It walks around obstacles using a BFS distance field and uses abilities by rule,
  but it does not plan multi-turn flanking.
- **No fog of war**: both fleets are always visible, in the tradition of small-scale
  tactical games.
- **Fixed 1280×720 reference resolution** (scaled by the stretch mode); there is no
  responsive re-layout for portrait or very small windows. The HUD panel is authored at
  that size, so on the 32×22 board the *cells* scale down while the panel does not.
- **English-only UI**; no localisation layer.
- The result overlay appears after the last animation event (~1–2 s); there is no
  "skip animation" button.
- Enemy fleet composition is a fixed list scaled by difficulty; it is not procedurally
  generated per seed.
- A test or probe that crashes hard (killed process) can leave the scratch file
  `user://void_command_save.test.json` behind. It is never the player's save and the next run
  removes it; no cleanup step is required for safety.

---

## 8. Design notes

- **2D, not 2.5D**: the gameplay is a discrete grid with orthogonal movement, so
  perspective and dynamic lighting would add cost without adding decisions.
- **Orthogonal movement and Manhattan ranges** keep range previews and LOS readable, and
  make the AI's evaluation easy to reason about.
- **Nebula as cover rather than a wall** gives the map a third tactical ingredient
  besides "open" and "blocked".
- The relay objective exists so that "hold ground" is rewarded: it pressures the player to
  split the fleet instead of deathballing, and pays out even on a defeat.
- **Battlefield size is data, not a constant.** The renderer derives its pixel geometry
  from the grid instead of duplicating 20×14, and the reference size keeps the original
  generator so "configurable" could not silently re-roll historical maps.
- **Capital hulls are one cell wide.** Width is what makes a hull unable to use a
  one-cell corridor; length only makes it awkward. That single decision is what removed
  the STEP1 stranded-hull failure mode, and it is why the footprint contract now forbids
  2-wide classes.
- **Rotation is free inside the route search**, because it is free in the rules. The
  search therefore minimises translations and treats orientation as part of the state.
