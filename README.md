# VOID COMMAND

Grid-based turn-based tactics game: you command a fleet of starships, exploit terrain, cover and
lines of fire, and win by annihilating the enemy or completing the relay objective.
Written in **GDScript** for **Godot 4.7.2**, with **entirely procedural** rendering: hulls, stars,
nebulae, planets, beams, explosions, shields, panels and text are drawn at runtime.
No imported texture, sprite, font or sound. No networking, no telemetry.

This repository is the project's **archive package** (archived on 20 October 2026 after
milestone M7B). It contains code, tests, the complete Git history, the technical specification and
the continuity documents. The full technical specification (in English) is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); the report of the last milestone is in
[`docs/M7B-REPORT.md`](docs/M7B-REPORT.md); the operational state in [`CHECKPOINT.md`](CHECKPOINT.md).

> **State in one line**: the game launches, all 24 headless suites pass (**4,818 checks**,
> measured on 20/10/2026),
> battle is playable from start to finish — but **the current version has playability problems
> reported by the user**, documented in §9.1. The project is no longer in active
> development: this is an orderly closure, not a release.

---

## 1. Vision and goals

A "small but honest" tactical wargame: orthogonal grid, cell-based movement, alternating turns,
ship classes with stats held in data, cover and line of sight, seed-deterministic AI.
The project grew out of a progressive mandate (milestones STEP 1–3, M0–M7B) with non-negotiable
principles, summarised here because they explain almost every choice:

1. **2D only.** No 2.5D, no 3D models.
2. **Visual minimalism**, recognisable geometric silhouettes, readable UI.
3. **Procedural graphics**: no external assets needed.
4. **Incremental development**: every milestone preserves what works and passes a suite.
5. **Determinism**: same seed and same conditions → same outcome.
6. **Separation of systems**: rules, presentation and data do not mix.
7. **No pointless rewrites**; **Git checkpoints** at every milestone.

Goals **not** achieved (planned in the original plan, never implemented): campaign, credits and
fleet point purchases, persistent progression between battles, Carrier and Dreadnought refits.

---

## 2. Gameplay and features actually present

- **4 selectable battlefields**: `20×14` (historical reference, generator locked with
  test fingerprints), `32×22`, `72×72`, `80×80` (`TITAN`, `MAX_SIZE`).
- **8 ship classes** with stats in `scripts/core/ship_defs.gd`; **length-only** hulls
  (1×1 · 1×3 · 1×4 · 1×5) with orientation; per-class caps (Dreadnought 1, Battleship 2,
  Carrier 1), no global cap.
- **Fleet points** (FP) with budgets 60 / 100 / 150 / 200 and composition limits; fleet
  composition screen with `+`/`−`, illegal choices rejected with a reason, explicit confirmation.
- **Turn-based battle**: movement with movement points, attack, 4 abilities, wait, end turn;
  simultaneous destruction handled; victory by annihilation, by relay objective, or by round
  limit (`MAX_ROUNDS = 40`); symmetric defeat; result overlay and rematch.
- **Terrain and tactics**: nebula as cover (not a wall), solid obstacles, line of sight,
  cover, area weapons, multi-cell footprint with rotation.
- **Pathfinding** deterministic BFS/A* on the grid, with `(cell, orientation)` states for long
  hulls; rejection with a reason when no route exists.
- **Deterministic AI** (greedy evaluator with seed jitter, BFS distance field, rule-based use of
  abilities) — one turn of depth, no multi-turn lookahead.
- **v1 save** in `user://void_command_save.json` (profile, credits, unlocks) and battle snapshot
  `void_command_battle.json` to resume a match.
- **Complete UI in code**: main menu, fleet composition, battle HUD with scrollable roster,
  detail panel, event log, pause, result overlay.
- **Camera**: mouse-wheel zoom at the pointer, `Home` to frame the field, `R` to re-centre.

**Missing**: audio (0 %), campaign/credits, Carrier and Dreadnought refits, fog of war,
localisation, export and CI.

---

## 3. Architecture and technologies

Three layers with a verifiable boundary:

| Layer | Directory | Contents |
|---|---|---|
| **Rules** (no nodes, deterministic) | `scripts/core/` | `ship_defs.gd` (catalogue), `ship.gd`, `battle_map.gd` (generation, zones), `map_config.gd` (presets), `battle.gd` (state and turns), `pathfinder.gd`, `ai.gd`, `combat.gd`, `footprint.gd`, `fleet_points.gd`, `save_data.gd`, `battle_save.gd` |
| **Presentation** | `scripts/ui/` | `battle_view.gd` (field drawing), `battle_screen.gd` (interaction and camera), `hud.gd`, `menu_screen.gd`, `fleet_screen.gd`, `overlay.gd`, `starfield.gd` |
| **Composition** | `scripts/main.gd` | `Main.tscn` root, transition from menu → fleet → battle |

- **Data, not scattered constants**: classes, costs, footprints and stats live in `ship_defs.gd`;
  field sizes in `map_config.gd`. Rendering geometry is **derived** from the grid (`cell_px`), not
  duplicated.
- **Determinism**: every random decision goes through `RandomNumberGenerator` with an explicit
  seed and dedicated streams; tests use fixed seeds and print the layout fingerprint.
- **A single predicate for the terminal state**: `_battle_over()` is the first statement of
  validators and executors, so no action can mutate a finished battle.
- **Footprint contract**: the anchor is the minimum cell, orientation swaps the extents,
  occupancy is not cached, and rotation happens before translation. Details and traps:
  `docs/ARCHITECTURE.md` §5.1–§5.2.
- **Tests as contract**: 24 headless suites + 4 windowed probes, each with an exit code.

---

## 4. Versions and dependencies

| | |
|---|---|
| Engine | **Godot 4.7.2.stable.official** (`ed1daf0bf`) |
| Declared `config/features` | `PackedStringArray("4.7")` |
| Addon / plugin | none |
| Language | Typed GDScript — 58 `.gd` files, 16,208 lines (code + tests + probes) |
| External assets | **none** (no texture, font, audio, model) |
| Networking | none |
| Reference resolution | 1280×720, `canvas_items` stretch |
| Git history | 53 commits on `master`, no remote configured, no tags |

---

## 5. Directory structure

```
VOID-COMMAND/
├── project.godot              main scene, InputMap, 1280×720
├── scenes/Main.tscn           single scene: root + scripts/main.gd
├── scripts/
│   ├── core/                  RULES: battle, map, ships, pathfinding, AI, fleet points, saves
│   ├── ui/                    PRESENTATION: views, screens, HUD, overlay, starfield
│   └── main.gd                composition
├── tests/                     24 headless suites + probes (benchmark, visual, equivalence)
├── docs/
│   ├── ARCHITECTURE.md        original technical specification (English): rules, geometry, milestones
│   └── M7B-REPORT.md          report of the last milestone (A/B, equivalences, defects found)
├── verify.sh                  gate: check-only + import + launch + 24 suites (exit code)
├── README.md                  this file
├── CHECKPOINT.md              operational continuity (state, traps, debts, resuming)
├── INDEX.md                   index: where things are
└── project-plan.txt           the author's original project plan (milestone roadmap)
```

`project-plan.txt` was excluded from Git in the development directory (it was the user's working
document). It has been **included and versioned** in this package because it contains the roadmap
and the project decisions, and a public repository without it would be incomplete.

---

## 6. Installation and launch

Prerequisite: Godot **4.7.2** (same minor). No other requirement, no dependency.

```bash
# 1. executable (adapt the path)
export GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe   # Windows: _console variant
export GODOT_GUI=/path/to/Godot_v4.7.2-stable_win64.exe       # real window

# 2. first import (creates .godot/, indispensable for --check-only and the suites)
"$GODOT" --headless --path . --import

# 3. play
"$GODOT_GUI" --path .
```

The project also opens from the Godot editor (`Import` → `project.godot`).
On Windows Godot wants native paths (`C:/...`): in an MSYS shell use `cygpath -m "$PWD"`.

### Controls (project InputMap)

| Key | Action |
|---|---|
| left mouse | select hull / destination cell / target |
| wheel | zoom at the pointer (on the roster: scrolls the list) |
| `T` | rotate the selected hull (`rotate_cw`), with outcome or reason for rejection |
| `R` | re-centre the camera |
| `Home` | frame the entire field |
| `SPACE` | end turn (`end_turn`) |
| `TAB` | next hull (`next_ship`) |
| `Q` | ability (`ability`) |
| `W` | wait (`wait_ship`) |
| `M` | change field size (`toggle_map`) |
| `F` | fleet composition (`compose_fleet`) |
| `C` | resume saved battle (`resume_battle`) |
| arrow keys | camera pan |
| `ESC` | pause (`pause_menu`) |

---

## 7. Tests and running the checks

```bash
# everything in one command: version, check-only on every .gd, import, launch, 24 suites → exit 0
GODOT=/path/to/..._console.exe bash verify.sh

# static checks only (no suites)
GODOT=... bash verify.sh --quick

# selected suites
GODOT=... bash verify.sh --suites test_core test_hud

# a single suite by hand
"$GODOT" --headless --path . --script res://tests/test_core.gd ; echo "exit=$?"
```

The suites are `extends SceneTree` scripts that print a summary (`checks: N   failures: 0`) and
exit with **0 = green, 1 = at least one failed check**. Beware of two traps already paid for:
a `SCRIPT ERROR` can abort a function leaving the suite "green" (grep the output, not just
the last line), and the exit code after a pipe is that of the downstream command, not of the engine.

Counts measured on 20 October 2026 in the archiving environment (Godot 4.7.2, Windows,
headless) — 24 suites, **4,818 checks, 0 failures, 0 `SCRIPT ERROR`**:

| Suite | Checks | Suite | Checks |
|---|---:|---|---:|
| `test_core` | 139 | `test_catalog` | 217 |
| `test_ui` | 47 | `test_fleet` | 1307 |
| `test_acceptance` | 80 | `test_fleet_ui` | 157 |
| `test_stress` | 27 | `test_frigate` | 57 |
| `test_footprint` | 177 | `test_capital` | 203 |
| `test_multicell` | 206 | `test_navigation` | 99 |
| `test_pathfinding` | 93 | `test_carrier` | 56 |
| `test_maps` | 116 | `test_camera` | 21 |
| `test_map_stress` | 15 | `test_grid` | 72 |
| `test_deployment` | 31 | `test_pathsearch_equivalence` | 1440 |
| `test_hud` | 37 | `test_bigmap` | 132 |
| `test_battle_save` | 54 | `test_controls` | 35 |

**Probes** (they do not count as suites, they require a window or only print numbers):

| Probe | What it does | Where it writes |
|---|---|---|
| `tests/bigmap_probe.gd` | benchmark of `Battle.setup()` and the enemy turn | stdout |
| `tests/ai_decisions_probe.gd` | equivalence table of AI decisions | stdout |
| `tests/fleet_balance_probe.gd` | AI-vs-AI balance matrix (slow, not completed in the session) | stdout |
| `tests/visual_probe.gd`, `tests/m7b_visual_probe.gd`, `tests/step1_visual_probe.gd`, `tests/step2_fighter_probe.gd`, `tests/step3_fleet_probe.gd` | visual evidence, requires a window | `../../G-DEV-REPORTS/<name>/` **two levels above the project root**, created by the probe |
| `tests/test_save_isolation.gd` | runs all suites as child processes and proves the real save remains identical | no file |

> The visual probes write **outside the project** (`ProjectSettings.globalize_path("res://") +
> "../../G-DEV-REPORTS/<name>/"`, with `DirAccess.make_dir_recursive_absolute`): this is deliberate, so the
> PNGs neither end up in `res://` nor enter the repository. With the package in
> `G-DEV/archivio/VOID-COMMAND/` the path resolves to `G-DEV/G-DEV-REPORTS/<name>/`. If you move the
> package, you can change that line in the probe or accept that the output ends up two
> levels above the root. The probes call `SaveGuard.isolate()`: the real save is not
> touched (verified in this location, identical hash before and after).

---

## 8. Actual state of development

Legend: **VERIFIED** (run with an exit code or state observed before/after) · **EXECUTED**
(output seen, no assertion) · **PARTIAL** · **PLANNED** · **NOT WORKING**.
The "proof" column points to the suite or the measurement.

| Area | State | Proof |
|---|---|---|
| Launch, menu, navigation between screens | **VERIFIED** | `test_ui`, `test_acceptance`, headless launch exit 0 |
| Battle rules, turns, victory/defeat, relay | **VERIFIED** | `test_core` (139) |
| Footprint geometry, rotation, occupancy | **VERIFIED** | `test_footprint` (177), `test_multicell` (206) |
| Pathfinding and `(cell, orientation)` search | **VERIFIED** | `test_pathfinding` (93), `test_pathsearch_equivalence` (1440) |
| Deterministic AI and its decisions | **VERIFIED** | `test_stress`, `ai_decisions_probe` |
| Fields 20×14 / 32×22 / 72×72 / 80×80 | **VERIFIED** | `test_maps` (116), `test_bigmap` (132), `test_map_stress` (15) |
| Fleet composition, budget, class caps | **VERIFIED** | `test_fleet` (1307), `test_fleet_ui` (157) |
| v1 save and battle snapshot | **VERIFIED** | `test_battle_save` (54), `test_save_isolation` |
| HUD, roster, camera, controls | **VERIFIED** | `test_hud` (37), `test_camera` (21), `test_controls` (35) |
| Performance on a large field | **MEASURED** (not a pass/fail criterion) | `bigmap_probe`, §9.1 |
| Visual evidence (screenshots) | **VERIFIED** — `m7b_visual_probe` re-run on 20/10 from the package: 24 checks, `RESULT: PASS`, 6 non-empty frames; PNGs produced **outside** the package and not included | `README.md` §7, `docs/M7B-REPORT.md` §4 |
| Overall playability (fun, pacing) | **PROBLEMATIC** — see §9.1 | user report + measurements |
| Audio | **PLANNED** (0 %) | — |
| Campaign, credits, Carrier/Dreadnought refits | **PLANNED** | `project-plan.txt` |
| Export, CI, localisation | **PLANNED** | — |

---

## 9. Known issues and missing features

### 9.1 Playability problems (reported by the user)

**The current version has playability problems reported by the user.** The exact text of the
report is not recorded in the project files: what is reported here are the **symptoms documented
and measured** in the repository, without inventing diagnoses.

1. **Matches on the large field end at the round limit with survivors.** Measured on
   80×80 with AI versus AI: 5 battles out of 6 (budget 0 / 60 / 100 FP, 9–29 hulls) ended at
   `MAX_ROUNDS = 40` with 1–3 hulls alive per side, because the fleets start ~68 cells
   apart and the AI closes by a couple of cells per turn. On 20×14 the same rule is generous.
   The limit **has not been changed**: it is a victory condition and requires a mandate
   (the obvious shape of the fix is a limit derived from the field area).
2. **The 80×80 field is not readable at a glance**: 8 px cells at full framing
   (29 px on 32×22). It is meant to be played zoomed in, but at zoom 1 nothing is distinguishable.
3. **The enemy turn freezes the window**: ~21 s on 80×80 with 52 hulls (~0.4 s per hull), because
   the AI runs synchronously inside `end_turn`. Default fleets (4–9 hulls) stay under 0.5 s.
4. **The roster shows 7 fixed rows** (band 122–274 px): with 52 hulls you scroll with the wheel;
   no filter, no two-column layout.
5. **Battle start with a hitch**: `Battle.setup()` 1.5 s on 72×72 and 1.8 s on 80×80, plus 1.2–1.4 s
   of map generation (dominated by `nav_stats()`, 25,600 states per candidate layout).
6. **No audio**: every action is silent.

No fixes have been applied: archiving is not a development session (§12).

### 9.2 Missing features

- **Audio**: 100 % absent (would require generating `AudioStreamWAV`, no imported assets).
- **Campaign, credits, fleet point purchases**: planned, never started.
- **Carrier and Dreadnought refits**: the save only upgrades the four original classes.
- **Victory rates per budget**: not measured (`fleet_balance_probe.gd` is slow and was not
  completed).
- **Fog of war**: absent by choice (both fleets always visible).
- **Localisation**: UI in English only.
- **Export and CI**: no preset, no pipeline.

### 9.3 Known limits of what exists

- AI with **one turn of depth**: it minimises translations, not multi-turn plans.
- Fixed reference resolution 1280×720: no responsive re-layout; the HUD panel does not
  scale with the cells.
- Enemy fleet composition: fixed list scaled by difficulty, not generated per seed.
- Result overlay after the last animation (~1–2 s), with no "skip animation".
- A brutally interrupted test can leave `user://void_command_save.test.json`: it is never the
  real save and the next run removes it.

---

## 10. Technical debt

Ordered by payoff (details and measurements in `CHECKPOINT.md` §7):

1. **`MAX_ROUNDS` does not scale with the field** — it is the first playability problem (§9.1.1).
2. **Synchronous enemy turn** — ~0.4 s per hull; a cheaper line-of-sight test is needed, or an
   incremental turn.
3. **Map generation** — `nav_stats()` is the bottleneck of battle start.
4. **7-row roster** with no filter and no two-column layout.
5. **Readability of the large field** at zoom 1.
6. **AI without lookahead**.
7. **Missing refit** and unmeasured balancing.
8. Geometry contract: the silhouette redraw (Cruiser 1×3 → 1×2) is **deferred**
   by explicit mandate, not forgotten.

---

## 11. Resuming development

Reading order and full protocol: `CHECKPOINT.md` §0, §3 (authorisation boundary),
§4 (reproduce the state), §10 (resume protocol). In short:

1. `bash verify.sh` → must exit 0 with 24/24 suites green and the counts of §7.
2. Compare the count: a difference is a signal, not noise.
3. **Ask the user which milestone is authorised**: `CHECKPOINT.md` §8 is a recommendation,
   not an authorisation.
4. Before modifying: clean tree, one commit per coherent unit, tests before the commit.
5. Active constraints: 2D only, procedural graphics, determinism on seed, real save never
   touched by tests, no destructive Git commands.

---

## 12. Why the project is frozen

Archiving (20/10/2026) **is not a development milestone**: no feature was added and no gameplay
problem was fixed. Only packaging operations were performed:

- copy of the project, removal of the `.godot/` cache, the session reports and the test
  images (kept in the backup, `CHECKPOINT.md` §11);
- addition of `verify.sh`, `.gitignore` and the `README.md`, `CHECKPOINT.md`, `INDEX.md` documents;
- versioning of `project-plan.txt`, which was excluded from Git in the development directory;
- Git history preserved in full (53 commits, no rewriting, no new remote).

What is needed to resume is in `CHECKPOINT.md`; what was measured in this location is in
`CHECKPOINT.md` §2.

---

## 13. Licence and attributions

- **Game code**: no licence declared by the author (all rights reserved). A licence must be
  chosen **before** publishing the repository.
- **Engine**: Godot Engine 4.7.2, MIT licence (© Godot Engine contributors).
- **Third-party assets**: none. Every visual element is drawn by the project code.
- **Font**: no imported font; the game uses the engine's fallback font.
