# VOID COMMAND — M7B REPORT

80×80 battlefield · controls and orientation · readable HUD and spent actions

Date: 2026-10-20 · Engine `Godot 4.7.2.stable.official.ed1daf0bf` · branch `master`

---

## 0. Premise: the repository did not match the handoff

The mandate told me to stop and diagnose if the tree, the commit or the fingerprints did not
match `HANDOFF.md`. They did not. This is the diagnosis, made **before** touching anything:

| Handoff said | Repository actually had |
|---|---|
| HEAD = M6 (`6e7ee07` in the chain), tree clean | 6 further commits, HEAD `b070e65`, **tree dirty** |
| "M7" = the milestone to start | the M7 label was already used by a **different** mandate (grid containment, 72×72, swarms) |
| Grid = 20×14 / 32×22 | `MapConfig.GRAND = 72×72`, `MAX_SIZE = 72×72` |
| Nothing about a broken suite | **`HEAD` did not parse**: `test_footprint.gd` used `ShipRef` without declaring it |

Two of those were defects, not documentation drift:

1. **`2f6132e` — the compile repair.** `git show HEAD:tests/test_footprint.gd` was written to a
   scratch file and `--check-only` failed with `Identifier "ShipRef" not declared` at lines 120
   and 294. The uncommitted diff in the tree was exactly that missing preload, so it was
   committed first and the tree was clean from then on.
2. **`rock_shapes` in `test_battle_save.gd`.** The suite referenced a member M6 deleted; the
   access threw a `SCRIPT ERROR` that **aborted the rest of the function while the suite still
   printed PASS** (53 checks instead of 54). Fixed by asserting what the snapshot really restores
   (terrain, planet anchors, relay).

Everything else in the handoff was treated as documentation to reconcile, not as truth: the
README's control table said `R = rotate` while the code bound `rotate_cw` to R **and** consumed R
for the camera recentre, so the rotation key was dead.

Baseline before any change (21 suites, all green, save byte-identical): core 139 · ui 47 ·
acceptance 80 · stress 27 · footprint 177 · multicell 206 · pathfinding 93 · maps 106 ·
map-stress 15 · deployment 31 · hud 18 · battle-save 53 · catalog 217 · fleet 1307 · fleet-ui 156 ·
frigate 57 · capital 203 · navigation 99 · carrier 56 · camera 19 · grid 72.

---

## 1. Commits

| | |
|---|---|
| Initial (preflight) | `b070e65` (with a dirty tests/test_footprint.gd) |
| Compile repair | `2f6132e` |
| Checkpoint A | `c93abe4` — 80×80 board, band-aware generator, setup/AI search costs |
| Checkpoint B | `9d9d756` — inward bows, T to rotate, cells that stay reachable |
| Checkpoint C | `e4926ae` — readable roster with scrolling, spent-actions marker |
| Camera fix | `44b7bb1` — the camera frames the play area, not the viewport |
| AI ordering | `24ad4e0` — nearest-to-target first, so the bound prunes |
| Final | `2028c3c` (docs, gate wiring, stale tests) + `18a1045` (the `.uid` files Godot generated) |

---

## 2. Files changed and why

**Rules layer**

| File | Change |
|---|---|
| `scripts/core/map_config.gd` | `TITAN = 80×80`, `MAX_SIZE = 80×80`, preset list and name/size mapping |
| `scripts/core/battle_map.gd` | `_in_band()` = the authoritative zone rule, used by the scaled generator and by `_nearest_free`; `_in_deploy()` kept verbatim because the reference fingerprints are a promise |
| `scripts/core/battle.gd` | pocket check → `escapes_deploy_band`; escape test asks `is_deploy_zone` instead of `x > 4` |
| `scripts/core/pathfinder.gd` | binary heap in `explore_states` (same lexicographic order); new `escapes_deploy_band` |
| `scripts/core/ai.gd` | one score per state, exact upper-bound prune, nearest-to-target evaluation order |
| `scripts/core/ship.gd` | `bow_vector()` / `bow_angle()`; `action_state()` + its three constants |

**Presentation**

| File | Change |
|---|---|
| `scripts/ui/battle_view.gd` | drawn bow from `Ship.bow_vector()`; health bars scale with the cell below 14 px; spent hull dimmed with a grey ring |
| `scripts/ui/battle_screen.gd` | `_play_offset()`: the camera frames the play area (a Camera2D centres its viewport); rotation feedback reports the resulting extent; `FootprintRef` preload |
| `scripts/ui/hud.gd` | roster band 122–274, `ROW_MIN_H = 20`, scrolling window + scrollbar, per-row action marker, `NO ACTIONS`, controls hint |
| `scripts/ui/menu_screen.gd`, `fleet_screen.gd` | preset list generated from `MapConfig.PRESET_NAMES`; `[M]` cycles via `next_size` |
| `project.godot` | `rotate_cw` physical keycode 82 (R) → 84 (T) |

**Tests** — new: `test_bigmap.gd` (126), `test_controls.gd` (35), `test_pathsearch_equivalence.gd`
(1440); updated: `test_hud.gd` (18 → 37), `test_fleet_ui.gd` (156 → 157), `test_battle_save.gd`
(53 → 54), `test_save_isolation.gd` (gate list). New probes: `bigmap_probe.gd`,
`ai_decisions_probe.gd`, `m7b_visual_probe.gd`.

---

## 3. Preflight results

- Gate (`tools/verify-project.sh`) exit 0 **before** the changes and after every checkpoint.
- All 21 baseline suites green; the real save was 332 B / `7a1c4fb2…` / mtime `1792405450`
  before and after every run in this session.
- Carrier and Dreadnought: implemented since M4/M6 with 1×5 footprints and full statistics —
  the handoff's "no footprint, `available=false`" was stale.

---

## 4. Tests run

Final structural set: **24 headless suites, 4818 assertions**, every one `RESULT: PASS` with
**zero `SCRIPT ERROR` lines** in the output (checked explicitly — see §4.1 note on silent
aborts). Plus the isolation gate with `--with-gui`:

```
24 suites + 4 windowed probes as children
checks: 65   failures: 0
RESULT: PASS
real save 332 bytes, sha256 7a1c4fb22c0747a1… | REAL BATTLE FILE 73623 bytes (unchanged)
```

Three new suites account for 1607 of the assertions (`test_pathsearch_equivalence` 1440,
`test_bigmap` 132, `test_controls` 35), and `test_maps` grew from 106 to 116 with the pinned
scaled terrain (§6.2)..

Two failures were **found and fixed** during this milestone, both in tests that had drifted:

- `test_hud.gd` asserted "no roster size pushes the last row under the buttons" — that assertion
  encoded the 12-px squeeze the mandate asked me to remove. It now asserts the new contract
  (readable minimum, scroll window, every row clickable in its window, last hull reachable) and
  it was not weakened: 18 → 37 checks.
- `test_fleet_ui.gd` asserted `[M]` toggles between two boards; the contract is now a cycle over
  every preset, and the test asserts **all presets are reachable**, not just two.

`test_battle_save.gd` was silently aborting on a stale member (see §0); the fix restored the
missing check.

---

## 4.1 Defects found by verification, not by reading the code

Four defects in this milestone were **not** visible in the source; they came out of running and
looking. They are listed because each one would have shipped as "done":

1. **The enemy fleet was drawn behind the HUD panel** (reference board, every battle). A
   `Camera2D` centres its *viewport*, so `camera.position = play_area_centre` moved the whole
   board 152 px right. Measured: enemy hulls at screen x = 1024 while the panel starts at 952 —
   they could neither be seen nor clicked, and `_on_board_click` ignores that region, so the
   battle was unwinnable on the historical board. Found because `visual_probe` (a 2023-era
   suite) failed with "hostile fleet rendered (1 warm px)". Fixed with `_play_offset()`; the
   camera suite and the probe now assert **screen-space** invariants.
2. **The roster drew through the detail panel and the combat log.** Found in the first 80×80
   screenshot: `ROSTER_BOTTOM` was 596 (the bottom of the log) instead of 274 (the top of the
   detail section).
3. **A 36-px health bar on an 8-px cell** made every hull look like a bar and collided with the
   ship above. Found in the same screenshot; the bar now scales with the cell and sits inside
   the footprint.
4. **The 40-round limit is far too short for 80×80.** Found by playing a full battle (the
   mandate asks for one): with both sides driven by the AI, 5 of 6 battles at 9–29 hulls ended
   at the limit with survivors, because the fleets start ~68 cells apart. Not changed: it is a
   victory rule and needs a mandate (§10.1).

---

## 5. Benchmarks (same machine, back to back, 200 FP fleets = 52 hulls per side)

A/B against `2f6132e`, both runs with `tests/bigmap_probe.gd` on an idle machine. The old tree
has no 80×80 board, so that row is new-only.

| board | map gen ms | setup ms before → after | deployment ms before → after | AI turn ms before → after |
|---|---:|---|---|---|
| 20×14 | 51 | 5172 → **2629** | 5088 → 2562 | 2385 → **1673** |
| 32×22 | 147 | 11565 → **1621** | 11297 → 1450 | 6342 → **3345** |
| 48×34 | 464 | 11738 → **865** | 11400 → 430 | 10148 → **5895** |
| 72×72 | 1189 | 18922 → **1548** | 17686 → 331 | 38984 → **16690** |
| 80×80 | 1438 | — → **1791** | — → 235 | — → **21055** |

Route search for the longest hull on 80×80: 42.5 ms. AI decision cost for 52 hulls: 1.27 s on
20×14, 5.3 s on 32×22, 7.1 s on 48×34, 18.4 s on 72×72 (was 50.3 s).

What was actually fixed, in the order the profile pointed at it:

1. **Deployment pocket check** — 85–95% of `Battle.setup()` per the M5 note. It answered a
   yes/no question by building every reachable state. `escapes_deploy_band()` collapses free
   rotations into an anchor graph and stops at the first escaping anchor.
2. **`explore_states` frontier** — a linear scan per pop made one search O(states²).
3. **AI scoring** — every state was scored twice (two passes) and every state was scored even
   when it provably could not win. Now: one score per state, an exact bound
   (`57/22 − 10·field − 1.2·control`, the 57→22 cut when weapon range is unreachable), and a
   nearest-first order so the bound bites early.

Equivalence evidence, not "the tests still pass":

- `test_pathsearch_equivalence.gd` keeps a **copy of the old linear-scan implementation** and
  compares 144 searches: same states, distances, rotation counts, parent links, per-anchor
  orientations, and the reconstructed route to the farthest state → 1440 checks, 0 differences.
  It also compares `escapes_deploy_band` against the full search (both sides, two budgets, three
  boards).
- `ai_decisions_probe.gd` prints the destination and target the AI chooses for every hull on
  4 seeds × 2 boards, on the generated map and on a **flattened** board where both trees face
  the same terrain. Old vs new: **15/16 blocks identical**; the single difference is the 32×22
  board whose terrain changed on purpose (next paragraph).
- `balance_probe.gd` output is **byte-identical** (8/8 · 185/267/47).

---

## 6. Deliberate behaviour changes

1. **80×80 added; 72×72 kept.** The mandate called the current grand board "48×34"; the M7 pass
   had already moved it to 72×72 and that is what ships as `grand`, with `titan` = 80×80 added.
   48×34 is still a legal size (`is_valid`) even though it has no preset.
2. **Scaled terrain changed.** The scaled generator protected four columns while the deployment
   band is six wide, so planets could be generated on cells a fleet must deploy on. Now it uses
   the authoritative zone rule. Measured with a terrain digest on seeds 1009 / 7 / 11:
   **20×14 identical** (`1989675638` / `1898126611` / `579307616` before and after — the
   fingerprints are a promise), **32×22 different** (`694832753 → 1547917131`,
   `1316660837 → 1786181873`, `610143205 → 1935697191`; seed 11 even loses a planet to the band),
   **72×72 identical for those seeds**. Consequence: the 32×22 campaigns in
   `test_map_stress` move (seed 1009 ends at round 17 instead of 13) — new baseline, not a
   regression — and the only block of the AI decision table that differs is `32×22 seed 11`,
   i.e. the map, not the AI.
3. **Pocket-escape criterion**: `not is_deploy_zone(anchor)` instead of `x > 4`. On the reference
   board the band is five columns, so the two agree; on the big boards the old test called a
   hull escaped while it still sat inside the band.
4. **Rotation key moved to T**; R stays the camera recentre. `rotate_cw` is no longer reachable
   from R, which is what the code actually did before (R returned before reaching the action).
5. **Roster contract**: 20-px minimum row height and a scroll window instead of squeezing to
   12 px. The band now ends at the DETAIL section (it used to draw through it).
6. **Camera clamp**: a board narrower than the view is centred on the play area **but not at the
   cost of cutting its columns**.

Not changed, per §7 of the mandate: footprints (Cruiser stays 1×3), silhouettes, statistics,
costs, budgets, caps, the reference map's behaviour, and the AI's rules.

---

## 7. Screenshots

`G-DEV-REPORTS/void-command-m7b/`, produced by `tests/m7b_visual_probe.gd` (windowed, real
`BattleScreen`, 200 FP fleets) and inspected frame by frame:

| File | Shows |
|---|---|
| `shot_01_titan_overview.png` | 80×80 at Home, roster scrolled to 1–7/52, no HUD overlap |
| `shot_02_titan_zoom_selected.png` | 1.9× on the fleet, selected Dreadnought, detail panel |
| `shot_03_titan_spent_actions.png` | spent hulls: hollow square + `NO ACTIONS`, dimmed rows |
| `shot_04_titan_home_fit.png` | the whole board after Home |
| `shot_05_titan_roster_scrolled.png` | the roster scrolled by the wheel |
| `shot_06_reference_board.png` | 20×14 for comparison: inward bows, unchanged layout |

Two defects were found by **looking at these images** and fixed before the final run: the roster
was drawing over the detail panel and the log (band bottom 596 → 274), and a fixed 36-px health
bar was four cells of clutter on an 8-px board (now scaled and inside the footprint). A third —
the enemy fleet drawn behind the HUD — was found by `visual_probe`'s warm-pixel assertion and
confirmed by measuring the screen position of every hostile hull (§4.1.1).

---

## 8. Save and determinism

- Real save: `%APPDATA%\Godot\app_userdata\Void Command\void_command_save.json` — 332 B,
  `7a1c4fb22c0747a…`, mtime `1792405450`, **identical before and after every suite** and after the
  isolation gate (its own snapshot compares both files byte for byte).
- Determinism: `test_maps.gd` still pins the ten reference fingerprints; `test_bigmap.gd` asserts
  same-seed → identical board *and* identical deployment on 80×80; `test_stress.gd` replay and
  map-stress campaigns unchanged except the documented terrain change.

---

## 9. Working tree

Clean after each checkpoint (`git status --porcelain` empty at the time of each commit). No
destructive git commands; `project-plan.txt` untouched (it is excluded from the index).

---

## 10. Residual problems, measured

1. **The 40-round limit does not scale with the board.** On 80×80, with both sides driven by
   the AI (seed 4242 / 7, budgets 0 / 60 / 100 FP, 9–29 hulls): 5 of 6 battles ended at the round
   limit with survivors (`defeat` after 40 rounds, 1–2 hulls left per side); only one resolved
   (victory in 35 rounds). The fleets start ~68 cells apart on an 80-cell board. This is a
   victory rule, so it was **not** changed: the obvious fix is a round limit derived from the
   board (e.g. `40 * sqrt(area_ratio)`), and it needs an authorisation because it changes how a
   battle ends. It is the single most important playability item left on this board.
2. **A 52-hull enemy turn costs ~21 s on 80×80** (0.4 s per hull). The AI runs synchronously
   inside `end_turn`, so the window is unresponsive for that time. Default fleets are fine
   (<0.5 s). Fixing it needs a cheaper LOS test (a per-turn cache would only help hulls longer
   than one cell) or an incremental enemy turn in the UI layer — both are new work, not a
   tweak.
3. **Map generation is ~1.4 s on 80×80**, dominated by `nav_stats()` building a 25,600-entry
   state dictionary per candidate layout. It is the largest remaining piece of the battle-start
   hitch now that deployment is fast.
4. **The big board is only legible zoomed in** (8-px cells at the fit level). That is a design
   consequence of fitting 6400 cells in a 928×666 play area, not a defect, but it is worth
   stating.
5. **The roster shows 7 rows** at any fleet size; a 52-hull fleet needs the wheel. No two-column
   roster, no filtering.
6. `fleet_balance_probe.gd` (the M5 balance matrix) was **not** run to completion in this
   session: it is slow and outside the mandate. Recorded as not measured, not as passing.
7. The 32×22 `test_map_stress` campaign numbers moved because the terrain changed on purpose
   (§6.2). They are a new baseline, not a regression.
8. A `void_command_battle.json` snapshot (73,623 B, mtime 09:39 today) was already in the player
   profile **before this session started** (the profile also holds the 332-B campaign save,
   untouched). It is not mine to delete: the game offers it as "resume". The isolation gate
   compares it before and after every run and it has not changed.

---

## 11. Documentation changes

- `README.md`: controls table (T/R/Home/wheel/roster scroll, [M] cycles four boards), §5.4 sizes
  and clamp, §5.7 corrected (the grand board is not 48×34 any more), **new §5.8** with the board,
  camera, controls, HUD contract, the A/B table and the equivalence proofs, §7 limitations
  rewritten with the measured numbers.
- `HANDOFF.md`: rewritten for the M7B state (it described M6 and a clean tree that did not exist).
- This report. `project-plan.txt` was **not** touched: it is the user's document.

---

## 12. Explicit confirmation

**The geometry redesign stayed out of scope.** No footprint, silhouette, statistic, cost, budget
or class cap changed. The Cruiser is still 1×3 (the proposed 1×3 → 1×2 change was not applied),
Destroyer and Frigate stay 1×1, Carrier and Dreadnought stay 1×5, and the per-class caps are
untouched. What changed about orientation is only how the fleet is *deployed* (horizontally) and
which way its bow is *drawn*.
