# VOID COMMAND

Gioco tattico a turni su griglia: comandi una flotta di astronavi, sfrutti terreno, copertura e
linee di tiro, e vinci annientando il nemico o completando l'obiettivo di relè.
Scritto in **GDScript** per **Godot 4.7.2**, resa **interamente procedurale**: scafi, stelle,
nebulose, pianeti, raggi, esplosioni, scudi, pannelli e testo sono disegnati a runtime.
Nessuna texture, sprite, font o suono importato. Nessuna rete, nessuna telemetria.

Questo repository è il **pacchetto di archivio** del progetto (archiviato il 20 ottobre 2026 dopo
la milestone M7B). Contiene codice, test, storia Git completa, la specifica tecnica e i documenti
di continuità. La specifica tecnica integrale (in inglese) è in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); il report dell'ultima milestone è in
[`docs/M7B-REPORT.md`](docs/M7B-REPORT.md); lo stato operativo in [`CHECKPOINT.md`](CHECKPOINT.md).

> **Stato in una riga**: il gioco si avvia, tutte le 24 suite headless passano (**4.818 controlli**,
> misurati il 20/10/2026),
> la battaglia è giocabile dall'inizio alla fine — ma **la versione attuale presenta problemi di
> giocabilità segnalati dall'utente**, documentati in §9.1. Il progetto non è più in sviluppo
> attivo: questa è una chiusura ordinata, non una release.

---

## 1. Visione e obiettivi

Un wargame tattico "piccolo ma onesto": griglia ortogonale, movimento a celle, turni alternati,
classi di nave con statistiche in dati, copertura e linea di vista, IA deterministica su seed.
Il progetto nasce da un mandato progressivo (milestone STEP 1–3, M0–M7B) con principi non
negoziabili, riassunti qui perché spiegano quasi tutte le scelte:

1. **Solo 2D.** Niente 2.5D, niente modelli 3D.
2. **Minimalismo visivo**, silhouette geometriche riconoscibili, UI leggibile.
3. **Grafica procedurale**: nessun asset esterno necessario.
4. **Sviluppo incrementale**: ogni milestone preserva ciò che funziona e supera una suite.
5. **Determinismo**: stesso seed e stesse condizioni → stesso esito.
6. **Separazione dei sistemi**: regole, presentazione e dati non si mescolano.
7. **Niente riscritture inutili**; **checkpoint Git** a ogni milestone.

Obiettivi **non** raggiunti (pianificati nel piano originale, mai implementati): campagna,
crediti e acquisto di punti flotta, progressione persistente fra battaglie, refit di Carrier e
Dreadnought.

---

## 2. Gameplay e funzionalità effettivamente presenti

- **4 campi di battaglia** selezionabili: `20×14` (riferimento storico, generatore bloccato con
  impronte di test), `32×22`, `72×72`, `80×80` (`TITAN`, `MAX_SIZE`).
- **8 classi di nave** con statistiche in `scripts/core/ship_defs.gd`; scafi **length-only**
  (1×1 · 1×3 · 1×4 · 1×5) con orientazione; tetti per classe (Dreadnought 1, Battleship 2,
  Carrier 1), nessun tetto globale.
- **Punti flotta** (FP) con budget 60 / 100 / 150 / 200 e limiti di composizione; schermata di
  composizione flotta con `+`/`−`, rifiuto motivato delle scelte illegali, conferma esplicita.
- **Battaglia a turni**: movimento con punti movimento, attacco, 4 abilità, attesa, fine turno;
  distruzione simultanea gestita; vittoria per annientamento, per obiettivo di relè, o per limite
  di round (`MAX_ROUNDS = 40`); sconfitta simmetrica; overlay di risultato e rivincita.
- **Terreno e tattica**: nebulosa come copertura (non muro), ostacoli solidi, linea di vista,
  copertura, armi ad area, footprint multi-cella con rotazione.
- **Pathfinding** BFS/A* deterministico sulla griglia, con stati `(cella, orientazione)` per gli
  scafi lunghi; rifiuto motivato quando non esiste rotta.
- **IA deterministica** (valutatore greedy con jitter su seed, campo di distanza BFS, uso delle
  abilità a regola) — un turno di profondità, nessun lookahead multi-turno.
- **Salvataggio v1** in `user://void_command_save.json` (profilo, crediti, sblocchi) e snapshot di
  battaglia `void_command_battle.json` per riprendere una partita.
- **UI completa in codice**: menu principale, composizione flotta, HUD di battaglia con roster
  scorrevole, pannello dettagli, log eventi, pausa, overlay di risultato.
- **Camera**: zoom alla rotella sul puntatore, `Home` per inquadrare il campo, `R` per ricentrare.

**Assenti**: audio (0 %), campagna/crediti, refit di Carrier e Dreadnought, fog of war,
localizzazione, export e CI.

---

## 3. Architettura e tecnologie

Tre strati con un confine verificabile:

| Strato | Directory | Contenuto |
|---|---|---|
| **Regole** (nessun nodo, deterministico) | `scripts/core/` | `ship_defs.gd` (catalogo), `ship.gd`, `battle_map.gd` (generazione, zone), `map_config.gd` (preset), `battle.gd` (stato e turni), `pathfinder.gd`, `ai.gd`, `combat.gd`, `footprint.gd`, `fleet_points.gd`, `save_data.gd`, `battle_save.gd` |
| **Presentazione** | `scripts/ui/` | `battle_view.gd` (disegno del campo), `battle_screen.gd` (interazione e camera), `hud.gd`, `menu_screen.gd`, `fleet_screen.gd`, `overlay.gd`, `starfield.gd` |
| **Composizione** | `scripts/main.gd` | radice `Main.tscn`, passaggio fra menu → flotta → battaglia |

- **Dati, non costanti sparse**: classi, costi, footprint e statistiche vivono in `ship_defs.gd`;
  le dimensioni del campo in `map_config.gd`. La geometria di rendering è **derivata** dalla
  griglia (`cell_px`), non duplicata.
- **Determinismo**: ogni decisione casuale passa da `RandomNumberGenerator` con seed esplicito e
  stream dedicati; i test usano seed fissi e stampano l'impronta del layout.
- **Un solo predicato per lo stato terminale**: `_battle_over()` è la prima istruzione dei
  validatori e degli esecutori, così nessuna azione può mutare una battaglia finita.
- **Contratto di footprint**: l'ancora è la cella minima, l'orientazione scambia le estensioni,
  l'occupazione non è in cache e la rotazione avviene prima della traslazione. Dettaglio e
  trappole: `docs/ARCHITECTURE.md` §5.1–§5.2.
- **Test come contratto**: 24 suite headless + 4 sonde con finestra, ognuna con exit code.

---

## 4. Versioni e dipendenze

| | |
|---|---|
| Motore | **Godot 4.7.2.stable.official** (`ed1daf0bf`) |
| `config/features` dichiarata | `PackedStringArray("4.7")` |
| Addon / plugin | nessuno |
| Linguaggio | GDScript tipizzato — 58 file `.gd`, 16.208 righe (codice + test + sonde) |
| Asset esterni | **nessuno** (nessuna texture, font, audio, modello) |
| Rete | nessuna |
| Risoluzione di riferimento | 1280×720, stretch `canvas_items` |
| Storia Git | 53 commit su `master`, nessun remote configurato, nessun tag |

---

## 5. Struttura delle directory

```
VOID-COMMAND/
├── project.godot              scena principale, InputMap, 1280×720
├── scenes/Main.tscn           unica scena: radice + scripts/main.gd
├── scripts/
│   ├── core/                  REGOLE: battaglia, mappa, navi, pathfinding, IA, punti flotta, salvataggi
│   ├── ui/                    PRESENTAZIONE: viste, schermate, HUD, overlay, starfield
│   └── main.gd                composizione
├── tests/                     24 suite headless + sonde (benchmark, visive, equivalenza)
├── docs/
│   ├── ARCHITECTURE.md        specifica tecnica originale (inglese): regole, geometria, milestone
│   └── M7B-REPORT.md          report dell'ultima milestone (A/B, equivalenze, difetti trovati)
├── verify.sh                  gate: check-only + import + avvio + 24 suite (exit code)
├── README.md                  questo file
├── CHECKPOINT.md              continuità operativa (stato, trappole, debiti, ripresa)
├── INDEX.md                   indice: dove sta cosa
└── project-plan.txt           piano progettuale originale dell'autore (roadmap a milestone)
```

`project-plan.txt` era escluso da Git nella directory di sviluppo (era il documento di lavoro
dell'utente). È stato **incluso e versionato** in questo pacchetto perché contiene la roadmap e le
decisioni di progetto, e un repository pubblico senza di esso sarebbe incompleto.

---

## 6. Installazione e avvio

Prerequisito: Godot **4.7.2** (stessa minor). Nessun altro requisito, nessuna dipendenza.

```bash
# 1. eseguibile (adatta il percorso)
export GODOT=/percorso/Godot_v4.7.2-stable_win64_console.exe   # Windows: variante _console
export GODOT_GUI=/percorso/Godot_v4.7.2-stable_win64.exe       # finestra reale

# 2. primo import (crea .godot/, indispensabile per --check-only e per le suite)
"$GODOT" --headless --path . --import

# 3. gioca
"$GODOT_GUI" --path .
```

Il progetto si apre anche dall'editor Godot (`Import` → `project.godot`).
Su Windows Godot vuole path nativi (`C:/...`): in una shell MSYS usa `cygpath -m "$PWD"`.

### Comandi (InputMap del progetto)

| Tasto | Azione |
|---|---|
| mouse sinistro | seleziona scafo / cella di destinazione / bersaglio |
| rotella | zoom sul puntatore (sul roster: scorre l'elenco) |
| `T` | ruota lo scafo selezionato (`rotate_cw`), con esito o motivo del rifiuto |
| `R` | ricentra la camera |
| `Home` | inquadra l'intero campo |
| `SPACE` | fine turno (`end_turn`) |
| `TAB` | scafo successivo (`next_ship`) |
| `Q` | abilità (`ability`) |
| `W` | attesa (`wait_ship`) |
| `M` | cambia dimensione del campo (`toggle_map`) |
| `F` | composizione flotta (`compose_fleet`) |
| `C` | riprendi battaglia salvata (`resume_battle`) |
| frecce | pan della camera |
| `ESC` | pausa (`pause_menu`) |

---

## 7. Test ed esecuzione delle verifiche

```bash
# tutto in un comando: versione, check-only su ogni .gd, import, avvio, 24 suite → exit 0
GODOT=/percorso/..._console.exe bash verify.sh

# solo i controlli statici (senza suite)
GODOT=... bash verify.sh --quick

# suite scelte
GODOT=... bash verify.sh --suites test_core test_hud

# una singola suite a mano
"$GODOT" --headless --path . --script res://tests/test_core.gd ; echo "exit=$?"
```

Le suite sono script `extends SceneTree` che stampano un riepilogo (`checks: N   failures: 0`) ed
escono con **0 = verde, 1 = almeno un controllo fallito**. Attenzione a due trappole già pagate:
un `SCRIPT ERROR` può abortire una funzione lasciando la suite "verde" (grep l'output, non solo
l'ultima riga), e l'exit code dopo una pipe è quello del comando a valle, non del motore.

Conteggi misurati il 20 ottobre 2026 nell'ambiente di archiviazione (Godot 4.7.2, Windows,
headless) — 24 suite, **4.818 controlli, 0 fallimenti, 0 `SCRIPT ERROR`**:

| Suite | Controlli | Suite | Controlli |
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

**Sonde** (non contano come suite, richiedono una finestra o stampano solo numeri):

| Sonda | Cosa fa | Dove scrive |
|---|---|---|
| `tests/bigmap_probe.gd` | benchmark di `Battle.setup()` e turno nemico | stdout |
| `tests/ai_decisions_probe.gd` | tabella di equivalenza delle decisioni IA | stdout |
| `tests/fleet_balance_probe.gd` | matrice di bilanciamento AI-vs-AI (lenta, non completata nella sessione) | stdout |
| `tests/visual_probe.gd`, `tests/m7b_visual_probe.gd`, `tests/step1_visual_probe.gd`, `tests/step2_fighter_probe.gd`, `tests/step3_fleet_probe.gd` | evidenza visiva, richiede finestra | `../../G-DEV-REPORTS/<nome>/` **due livelli sopra la radice del progetto**, creata dalla sonda |
| `tests/test_save_isolation.gd` | esegue tutte le suite come processi figli e prova che il salvataggio reale resta identico | nessun file |

> Le sonde visive scrivono **fuori dal progetto** (`ProjectSettings.globalize_path("res://") +
> "../../G-DEV-REPORTS/<nome>/"`, con `DirAccess.make_dir_recursive_absolute`): è deliberato, così i
> PNG non finiscono in `res://` né entrano nel repository. Con il pacchetto in
> `G-DEV/archivio/VOID-COMMAND/` il percorso risolve in `G-DEV/G-DEV-REPORTS/<nome>/`. Se sposti il
> pacchetto, puoi modificare quella riga nella sonda oppure accettare che l'output finisca due
> livelli sopra la radice. Le sonde chiamano `SaveGuard.isolate()`: il salvataggio reale non viene
> toccato (verificato in questa sede, hash identico prima e dopo).

---

## 8. Stato reale dello sviluppo

Legenda: **VERIFICATO** (eseguito con exit code o stato osservato prima/dopo) · **ESEGUITO**
(output visto, nessuna asserzione) · **PARZIALE** · **PIANIFICATO** · **NON FUNZIONANTE**.
La colonna "prova" rimanda alla suite o alla misura.

| Area | Stato | Prova |
|---|---|---|
| Avvio, menu, navigazione fra schermate | **VERIFICATO** | `test_ui`, `test_acceptance`, avvio headless exit 0 |
| Regole di battaglia, turni, vittoria/sconfitta, relè | **VERIFICATO** | `test_core` (139) |
| Geometria footprint, rotazione, occupazione | **VERIFICATO** | `test_footprint` (177), `test_multicell` (206) |
| Pathfinding e ricerca `(cella, orientazione)` | **VERIFICATO** | `test_pathfinding` (93), `test_pathsearch_equivalence` (1440) |
| IA deterministica e sue decisioni | **VERIFICATO** | `test_stress`, `ai_decisions_probe` |
| Campi 20×14 / 32×22 / 72×72 / 80×80 | **VERIFICATO** | `test_maps` (116), `test_bigmap` (132), `test_map_stress` (15) |
| Composizione flotta, budget, limiti di classe | **VERIFICATO** | `test_fleet` (1307), `test_fleet_ui` (157) |
| Salvataggio v1 e snapshot di battaglia | **VERIFICATO** | `test_battle_save` (54), `test_save_isolation` |
| HUD, roster, camera, controlli | **VERIFICATO** | `test_hud` (37), `test_camera` (21), `test_controls` (35) |
| Prestazioni su campo grande | **MISURATO** (non è un criterio di pass/fail) | `bigmap_probe`, §9.1 |
| Evidenza visiva (screenshot) | **VERIFICATO** — sonda `m7b_visual_probe` rieseguita il 20/10 dal pacchetto: 24 controlli, `RESULT: PASS`, 6 frame non vuoti; PNG prodotti **fuori** dal pacchetto e non inclusi | `README.md` §7, `docs/M7B-REPORT.md` §4 |
| Giocabilità complessiva (divertimento, ritmo) | **PROBLEMATICA** — vedi §9.1 | segnalazione utente + misure |
| Audio | **PIANIFICATO** (0 %) | — |
| Campagna, crediti, refit Carrier/Dreadnought | **PIANIFICATO** | `project-plan.txt` |
| Export, CI, localizzazione | **PIANIFICATO** | — |

---

## 9. Problemi noti e funzionalità mancanti

### 9.1 Problemi di giocabilità (segnalati dall'utente)

**La versione attuale presenta problemi di giocabilità segnalati dall'utente.** Il testo esatto
della segnalazione non è registrato nei file del progetto: qui sono riportati i **sintomi
documentati e misurati** nel repository, senza inventare diagnosi.

1. **Le partite sul campo grande finiscono per limite di round con superstiti.** Misurato su
   80×80 con IA contro IA: 5 battaglie su 6 (budget 0 / 60 / 100 FP, 9–29 scafi) terminate a
   `MAX_ROUNDS = 40` con 1–3 scafi vivi per parte, perché le flotte partono a ~68 celle di
   distanza e l'IA chiude di un paio di celle per turno. Su 20×14 la stessa regola è generosa.
   Il limite **non è stato cambiato**: è una condizione di vittoria e richiede un mandato
   (la forma ovvia del fix è un limite derivato dall'area del campo).
2. **Il campo 80×80 non è leggibile a colpo d'occhio**: celle da 8 px all'inquadratura completa
   (29 px su 32×22). È pensato per essere giocato zoomato, ma a zoom 1 non si distingue nulla.
3. **Il turno nemico congela la finestra**: ~21 s su 80×80 con 52 scafi (~0,4 s per scafo), perché
   l'IA gira sincrona dentro `end_turn`. Le flotte di default (4–9 scafi) restano sotto 0,5 s.
4. **Il roster mostra 7 righe fisse** (banda 122–274 px): con 52 scafi si scorre con la rotella;
   nessun filtro, nessuna doppia colonna.
5. **Avvio battaglia con hitch**: `Battle.setup()` 1,5 s su 72×72 e 1,8 s su 80×80, più 1,2–1,4 s
   di generazione mappa (dominata da `nav_stats()`, 25.600 stati per layout candidato).
6. **Nessun audio**: ogni azione è silenziosa.

Non sono state applicate correzioni: l'archiviazione non è una sessione di sviluppo (§12).

### 9.2 Funzionalità mancanti

- **Audio**: assente al 100 % (servirebbe generare `AudioStreamWAV`, nessun asset importato).
- **Campagna, crediti, acquisto di punti flotta**: pianificati, mai iniziati.
- **Refit di Carrier e Dreadnought**: il salvataggio potenzia solo le quattro classi originali.
- **Tassi di vittoria per budget**: non misurati (`fleet_balance_probe.gd` è lento e non è stato
  completato).
- **Fog of war**: assente per scelta (entrambe le flotte sempre visibili).
- **Localizzazione**: UI solo in inglese.
- **Export e CI**: nessun preset, nessuna pipeline.

### 9.3 Limiti noti di ciò che c'è

- IA a **un turno di profondità**: minimizza traslazioni, non piani multi-turno.
- Risoluzione di riferimento fissa 1280×720: nessun re-layout responsive; il pannello HUD non
  scala con le celle.
- Composizione della flotta nemica: lista fissa scalata per difficoltà, non generata per seed.
- Overlay di risultato dopo l'ultima animazione (~1–2 s), senza "salta animazione".
- Un test interrotto brutalmente può lasciare `user://void_command_save.test.json`: non è mai il
  salvataggio reale e la run successiva lo rimuove.

---

## 10. Debiti tecnici

Ordinati per payoff (dettaglio e misure in `CHECKPOINT.md` §7):

1. **`MAX_ROUNDS` non scala con il campo** — è il primo problema di giocabilità (§9.1.1).
2. **Turno nemico sincrono** — ~0,4 s per scafo; serve un test di linea di vista più economico o
   un turno incrementale.
3. **Generazione mappa** — `nav_stats()` è il collo di bottiglia dell'avvio battaglia.
4. **Roster a 7 righe** senza filtro né doppia colonna.
5. **Leggibilità del campo grande** a zoom 1.
6. **IA senza lookahead**.
7. **Refit mancante** e bilanciamento non misurato.
8. Contratto di geometria: la ridisegnatura delle silhouette (Cruiser 1×3 → 1×2) è **deferita**
   per mandato esplicito, non dimenticata.

---

## 11. Riprendere lo sviluppo

Ordine di lettura e protocollo completo: `CHECKPOINT.md` §0, §3 (confine di autorizzazione),
§4 (riprodurre lo stato), §10 (protocollo di ripresa). In sintesi:

1. `bash verify.sh` → deve uscire 0 con 24/24 suite verdi e i conteggi di §7.
2. Confronta il conteggio: una differenza è un segnale, non rumore.
3. **Chiedi all'utente quale milestone è autorizzata**: `CHECKPOINT.md` §8 è una raccomandazione,
   non un'autorizzazione.
4. Prima di modificare: albero pulito, un commit per unità coerente, test prima del commit.
5. Vincoli attivi: solo 2D, grafica procedurale, determinismo su seed, salvataggio reale mai
   toccato dai test, nessun comando Git distruttivo.

---

## 12. Perché il progetto è congelato

L'archiviazione (20/10/2026) **non è una milestone di sviluppo**: nessuna funzionalità è stata
aggiunta e nessun problema di gameplay è stato corretto. Sono state fatte solo operazioni di
packaging:

- copia del progetto, rimozione della cache `.godot/`, dei report di sessione e delle immagini di
  prova (conservati nel backup, `CHECKPOINT.md` §11);
- aggiunta di `verify.sh`, `.gitignore` e dei documenti `README.md`, `CHECKPOINT.md`, `INDEX.md`;
- versionamento di `project-plan.txt`, che nella directory di sviluppo era escluso da Git;
- storia Git preservata integralmente (53 commit, nessuna riscrittura, nessun nuovo remote).

Ciò che serve per riprendere è in `CHECKPOINT.md`; ciò che è stato misurato in questa sede è in
`CHECKPOINT.md` §2.

---

## 13. Licenza e attribuzioni

- **Codice del gioco**: nessuna licenza dichiarata dall'autore (tutti i diritti riservati). Va
  scelta una licenza **prima** di pubblicare il repository.
- **Motore**: Godot Engine 4.7.2, licenza MIT (© Godot Engine contributors).
- **Asset di terze parti**: nessuno. Ogni elemento visivo è disegnato dal codice del progetto.
- **Font**: nessun font importato; il gioco usa il font di fallback del motore.
