# INDEX — VOID COMMAND

Indice del pacchetto. Non è una seconda documentazione: serve a **trovare** le informazioni.
Documenti principali: [`README.md`](README.md) (cos'è, come si avvia, cosa funziona e cosa no) ·
[`CHECKPOINT.md`](CHECKPOINT.md) (stato operativo, trappole, debiti, ripresa).

| | |
|---|---|
| Stato | tattico a turni giocabile, **congelato** per archiviazione (20/10/2026) con problemi di giocabilità noti |
| Motore | Godot 4.7.2.stable.official (`ed1daf0bf`) |
| Commit di riferimento | `793596e` = ultimo commit di **sviluppo** (M7B); sopra, i commit di archiviazione (vedi `git log --oneline`) |
| Verifica minima | `bash verify.sh` → exit 0, 24 suite, 4.818 controlli |

---

## 1. Documenti

| File | Cosa contiene | Quando leggerlo |
|---|---|---|
| `README.md` | descrizione, gameplay, architettura, avvio, test con i conteggi, stato reale, problemi (incl. §9.1 giocabilità), licenza | per primo |
| `CHECKPOINT.md` | stato misurato, cosa ha fatto la sessione di archiviazione, confine di autorizzazione, numeri cambiati di proposito, **16 trappole pagate**, debiti, protocollo di ripresa, backup | prima di modificare qualcosa |
| `INDEX.md` | questo file | per orientarsi |
| `docs/ARCHITECTURE.md` | specifica tecnica originale (inglese): regole, contratto geometrico multi-cella, mappe, milestone | per il *perché* delle scelte |
| `docs/M7B-REPORT.md` | report dell'ultima milestone: benchmark A/B, prove di equivalenza, difetti trovati eseguendo il gioco | per capire l'ultimo stato del motore |
| `project-plan.txt` | piano progettuale originale dell'autore (visione, principi, roadmap a milestone) | per la visione e per ciò che era pianificato |
| `verify.sh` | gate riproducibile: versione, `--check-only` su 58 script, import, avvio, 24 suite | per verificare tutto in un comando |

## 2. Mappa dei componenti

| Sistema | File principali | Note |
|---|---|---|
| Composizione | `scripts/main.gd` + `scenes/Main.tscn` | menu → composizione flotta → battaglia → risultato |
| Stato e turni | `scripts/core/battle.gd` (1073 righe) | regole, `end_turn`, condizioni di vittoria, `_battle_over()` |
| Mappa e generazione | `scripts/core/battle_map.gd`, `map_config.gd` | preset 20×14 / 32×22 / 72×72 / 80×80, bande di deployment |
| Navi e catalogo | `scripts/core/ship.gd`, `ship_defs.gd`, `footprint.gd` | statistiche in dati, footprint length-only, orientazione |
| Percorsi | `scripts/core/pathfinder.gd` | BFS/A* con stati `(cella, orientazione)`, `escapes_deploy_band` |
| IA | `scripts/core/ai.gd` | valutatore greedy deterministico, bound, un turno di profondità |
| Combattimento | `scripts/core/combat.gd` | risoluzione danno, copertura, area |
| Punti flotta | `scripts/core/fleet_points.gd` | budget 60/100/150/200, limiti di composizione |
| Persistenza | `scripts/core/save_data.gd`, `battle_save.gd` | schema v1, snapshot di battaglia |
| Presentazione | `scripts/ui/battle_view.gd` (797), `battle_screen.gd` (675), `hud.gd` (470), `fleet_screen.gd`, `menu_screen.gd`, `overlay.gd`, `starfield.gd` | tutto disegnato in codice |

Dettaglio dei contratti: `docs/ARCHITECTURE.md` §5.1–§5.8.

## 3. Punti di ingresso

- **Eseguire**: `project.godot` → `run/main_scene = res://scenes/Main.tscn`.
- **Capire una battaglia**: `battle.gd` (`setup`, `end_turn`, `move_ship`, `can_attack`) →
  `battle_screen.gd` (input/camera) → `battle_view.gd` (disegno).
- **Capire la generazione**: `battle_map.gd` (`generate`, `_in_band`, `nav_stats`) +
  `map_config.gd` (preset).
- **Capire l'IA**: `ai.gd` (`_score`, bound, ordine nearest-first) + `pathfinder.gd`.
- **Capire la persistenza**: `save_data.gd`, `battle_save.gd` (schema v1, validazione).

## 4. Test e strumenti

| File | Tipo | Cosa prova |
|---|---|---|
| `tests/test_core.gd` | suite headless | regole, turni, vittoria/sconfitta, relè — 139 controlli |
| `tests/test_acceptance.gd` | suite headless | percorso reale menu → battaglia → azioni → risultato → rivincita — 80 |
| `tests/test_footprint.gd`, `test_multicell.gd` | suite | geometria e occupazione multi-cella — 177 + 206 |
| `tests/test_pathfinding.gd`, `test_pathsearch_equivalence.gd` | suite | rotte e **equivalenza** con la ricerca completa — 93 + 1440 |
| `tests/test_maps.gd`, `test_bigmap.gd`, `test_map_stress.gd` | suite | preset, impronte di riferimento, 30 mappe su seed, determinismo — 116 + 132 + 15 |
| `tests/test_fleet.gd`, `test_fleet_ui.gd` | suite | budget, composizione, schermata flotta — 1307 + 157 |
| `tests/test_hud.gd`, `test_camera.gd`, `test_controls.gd` | suite | roster, camera in coordinate schermo, tasti — 37 + 21 + 35 |
| `tests/test_battle_save.gd`, `test_save_isolation.gd` | suite / gate | snapshot v1 e **non interferenza col salvataggio reale** |
| `tests/bigmap_probe.gd`, `ai_decisions_probe.gd`, `fleet_balance_probe.gd` | sonde | benchmark, tabella di equivalenza IA, matrice di bilanciamento (lenta) |
| `tests/*_visual_probe.gd`, `step*_probe.gd` | sonde **GUI** | screenshot in `../G-DEV-REPORTS/` |
| `verify.sh` | gate | tutto quanto sopra in un comando con exit code |

Elenco completo con i conteggi: `README.md` §7.

## 5. Dove NON guardare

- `.godot/` è cache rigenerabile, non versionata.
- I riferimenti a `G-DEV-AUDIT/` e `G-DEV-REPORTS/` dentro `docs/ARCHITECTURE.md` sono **storici**:
  quei materiali stanno nel backup (`CHECKPOINT.md` §11), non nel pacchetto.
- `project-plan.txt` contiene la roadmap originale: alcune voci (campagna, crediti) sono
  **pianificate e mai implementate**, non stato corrente.

## 6. Collegamenti

- Cosa funziona e cosa no: `README.md` §8–§9 · `CHECKPOINT.md` §1
- Problemi di giocabilità segnalati: `README.md` §9.1
- Debiti tecnici ordinati: `CHECKPOINT.md` §7
- Trappole già pagate (16): `CHECKPOINT.md` §6
- Cosa è cambiato di proposito in M7B: `CHECKPOINT.md` §5
- Confine di autorizzazione: `CHECKPOINT.md` §3
- Ripresa: `CHECKPOINT.md` §10
- Backup e ripristino: `CHECKPOINT.md` §11
