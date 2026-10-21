# CHECKPOINT — VOID COMMAND

> **Documento di continuità.** Scritto per un agente che non ha memoria della sessione che l'ha
> prodotto. Tutto ciò che è dichiarato qui è stato **misurato** in questo ambiente (Windows,
> Godot 4.7.2); dove qualcosa **non** è stato eseguito, è detto esplicitamente.
>
> Ultimo aggiornamento: **20 ottobre 2026** (archiviazione) · motore
> `4.7.2.stable.official.ed1daf0bf` · branch `master`

---

## 0. Ordine di lettura

1. Questo file §1–§3 (stato, cosa è successo, confine di autorizzazione).
2. `README.md` §9.1 (problemi di giocabilità) e §10 (debiti) — cosa non funziona e perché.
3. `docs/ARCHITECTURE.md` §5.1–§5.8 (contratto geometrico, multi-cella, mappe, M7B).
4. `docs/M7B-REPORT.md` — cosa ha fatto l'ultima milestone, con i benchmark A/B.
5. Solo dopo, il codice.

---

## 1. Stato (misurato il 20/10/2026, in questo pacchetto)

| | |
|---|---|
| Percorso | pacchetto `VOID-COMMAND/` (archivio G-DEV) · originale `G-DEV/projects/void-command` (rimosso) |
| Branch / HEAD | `master` · ultimo commit di **sviluppo**: **`793596e`** *M7B: pin the scaled terrain…*; sopra ci sono solo i commit di archiviazione (vedi `git log --oneline`) |
| Storia | 53 commit di sviluppo dal `3a41524` (baseline pre-Milestone 0, 19/10 12:25) + i commit di archiviazione · nessun remote · nessun tag |
| Working tree | **pulito** (verificato al momento dell'archiviazione, 126 file tracciati) |
| Suite | **24 headless, 4.818 controlli, 0 fallimenti, 0 `SCRIPT ERROR`** (`verify.sh`) |
| Campi | `20×14` riferimento · `32×22` · `72×72` · `80×80` (`TITAN`, `MAX_SIZE`) |
| Classi | 8 giocabili, scafi length-only 1×1 ×4 / 1×3 / 1×4 / 1×5 ×2; tetti Dreadnought 1, Battleship 2, Carrier 1 |
| Controlli | `T` ruota · `R` ricentra · `Home` inquadra · rotella = zoom · `SPACE` fine turno · `M` campo · `ESC` pausa |
| Salvataggio | schema **v1**, `user://void_command_save.json` |
| Salvataggio reale (profilo) | 332 B · mtime `1792405450` · sha256 `7a1c4fb22c0747a172582699053c1f3ba6aeb277a5017f4498ffc0148d167e3` — **identico prima e dopo** questa sessione |
| Snapshot di battaglia reale | `void_command_battle.json` · **12.604 B** · sha256 `690d7487…` · mtime `1792500189` (20/10 14:43) — identico prima e dopo |
| Motore | Godot `4.7.2.stable.official.ed1daf0bf` |
| Gate | `bash verify.sh` (incluso nel pacchetto) → exit 0 con 24/24 suite |

⚠️ **Discrepanza nota e voluta**: il vecchio `HANDOFF.md` (ora sostituito da questo file) registrava
`void_command_battle.json` a 73.623 B / 09:39. Al momento dell'archiviazione il file è 12.604 B con
mtime 14:43, quindi è stato **riscritto dal gioco** dopo quel handoff. Non è un danno della
sessione di archiviazione: la sessione ha solo letto il file e ne ha confrontato l'hash
prima/dopo (identico). È il salvataggio del giocatore e resta al suo posto.

---

## 2. Cosa è stato fatto in questa sessione (solo archiviazione)

| Operazione | Dettaglio |
|---|---|
| Backup integrale | `C:\Users\Dave\PROGETTI\G-DEV-BACKUP-2026-10-20\` — 5 archivi `.tar.gz` + `SHA256SUMS.txt` (integrità verificata con `tar tzf`) |
| Copia nel pacchetto | progetto intero **tranne** `.godot/` (cache rigenerabile) |
| Rimosso dal pacchetto | report di sessione `G-DEV-AUDIT/void-command-m0…m7b/`, `G-DEV-REPORTS/void-command*` (screenshot e log), `HANDOFF.md` |
| Conservato | `docs/M7B-REPORT.md` (unico report con misure A/B non riproducibili altrove) · `docs/ARCHITECTURE.md` (vecchio README, specifica tecnica) |
| Aggiunto | `README.md`, `CHECKPOINT.md`, `INDEX.md`, `verify.sh`, `.gitignore` |
| Versionato | `project-plan.txt` (prima escluso da Git: era in `.git/info/exclude`) |
| Verifica eseguita | `--import` exit 0 · avvio headless exit 0 · 24/24 suite verdi (4.818 controlli) · sonda visiva GUI `m7b_visual_probe` (24 controlli, `RESULT: PASS`, 6 frame non vuoti) · salvataggio reale e snapshot di battaglia **invariati** (hash identico prima/dopo) |
| **Non** eseguito | `test_save_isolation --with-gui` (richiede finestra, ~12 min), `bigmap_probe` / `fleet_balance_probe` (benchmark, minuti), export, playtest |

Il `.git/info/exclude` originale conteneva `.godot/`, `*.translation`, `G-DEV-REPORTS/` e
`project-plan.txt`. Nel pacchetto le prime due regole sono in un `.gitignore` versionato; le altre
due riguardavano il layout di sviluppo e non hanno più senso.

---

## 3. Confine di autorizzazione — leggere prima di scrivere codice

**Chiusi e verificati:** STEP 2, STEP 3, M3, M4, M6, M7 (72×72) e M7B. **Non autorizzati** senza un
nuovo mandato esplicito:

- cambiare footprint, silhouette, statistiche, costi, budget (60/100/150/200) o i tetti per classe —
  la ridisegnatura geometrica è **esplicitamente rinviata** (il Cruiser 1×3 → 1×2 proposto **non** è
  stato applicato);
- reintrodurre un tetto globale agli scafi, con qualsiasi nome;
- cambiare il comportamento della mappa di riferimento 20×14 (le dieci impronte in `test_maps.gd`
  sono una promessa) o gli esiti registrati di bilanciamento/map-stress;
- **cambiare le condizioni di vittoria**, incluso `MAX_ROUNDS = 40` (vedi §7.1: è misurato come il
  problema di giocabilità principale su 80×80, ed è lasciato intatto di proposito);
- ridisegnare l'HUD oltre le correzioni già fatte, o riscrivere l'IA;
- campagna, budget di missione, acquisto di punti flotta con crediti.

Regole permanenti: **solo 2D**, visuali procedurali in GDScript, identità scuro/ciano/arancio,
offline, determinismo su seed, il salvataggio reale non è mai toccato dai test, nessun comando Git
distruttivo.

---

## 4. Riprodurre e verificare lo stato

Dalla radice del pacchetto:

```bash
export GODOT=/percorso/Godot_v4.7.2-stable_win64_console.exe
export GODOT_GUI=/percorso/Godot_v4.7.2-stable_win64.exe    # serve solo alle sonde con finestra

# 1. storia e albero
git log --oneline -6          # deve contenere 44b7bb1 (fix camera) e i checkpoint M7B
git status --porcelain        # atteso: vuoto

# 2. gate completo: versione + check-only su 58 script + import + avvio + 24 suite → exit 0
bash verify.sh

# 3. solo la parte statica (veloce)
bash verify.sh --quick

# 4. una suite singola, con exit code catturato PRIMA della pipe
"$GODOT" --headless --path . --script res://tests/test_core.gd > /tmp/tc.log 2>&1; echo "exit=$?"

# 5. benchmark (stampa numeri, non asserisce tempi) — ~1–4 min
"$GODOT" --headless --path . --script res://tests/bigmap_probe.gd

# 6. sonde con finestra (richiedono GPU) — scrivono in ../G-DEV-REPORTS/
"$GODOT_GUI" --path . --script res://tests/m7b_visual_probe.gd
```

Attesi: 24 suite `exit=0` con i conteggi di `README.md` §7. **Se un conteggio o l'hash del
salvataggio differiscono, fermarsi e diagnosticare prima di scrivere codice.**

---

## 5. Numeri che sono cambiati di proposito (non "ripristinarli")

| | prima di M7B | dopo M7B |
|---|---|---|
| Campi | 20×14 / 32×22 / 72×72 | + **80×80** (`TITAN`), `MAX_SIZE` 80 |
| Terreno 32×22 | fascia di quattro colonne protetta | protezione **a tutta banda** ⇒ mappe diverse (digest diverso su seed 1009/7/11) |
| Test della tasca di deployment | `x > 4` su `states.keys()` | `not is_deploy_zone()` su `escapes_deploy_band()` |
| `explore_states` | scansione lineare della frontiera | heap binario, stesso ordine lessicografico |
| Ricerca destinazione IA | due passate, nessuna potatura | una passata + bound esatto + ordine nearest-first |
| `Battle.setup()` (52 scafi) | 19 s su 72×72 | **1,5 s** su 72×72 · 1,8 s su 80×80 |
| Turno nemico (52 scafi) | 39 s su 72×72 | **16,7 s** su 72×72 · 21,1 s su 80×80 |
| Tasto rotazione | `R` (morto: lo consumava la camera) | **`T`** |
| Banda del roster | 122–596 (sopra il pannello dettagli) | **122–274**, 7 righe, scorrevole |
| Riga minima HUD | 12 px (sovrapposte) | **20 px** |
| Camera | inquadrava il viewport → campo 152 px a destra, nemico sotto l'HUD | inquadra l'**area di gioco** |
| Controlli asseriti | 3.457 | **4.818** |

Due di queste non sono estetiche: il bug della camera rendeva **invisibile la flotta nemica** sul
campo di riferimento, e il bug del roster nascondeva il pannello dettagli dietro l'elenco. Entrambi
sono stati trovati **eseguendo e guardando**, non leggendo il codice.

---

## 6. Trappole già pagate — non pagarle di nuovo

1. **Una `Camera2D` centra il VIEWPORT, non l'area di gioco.** Impostare `camera.position` al centro
   dell'area sposta il mondo di (centro viewport − centro area) — 152 px qui. Esprimi la posizione
   come `focus - _play_offset()` e **asserisci in coordinate schermo**:
   `screen = viewport/2 + (world - camera.position) * zoom`.
2. **`get_canvas_transform()` è vecchio di un frame** subito dopo un movimento di camera (misurato:
   5 px di errore). Usa la formula sopra, oppure attendi un frame.
3. **Un `SCRIPT ERROR` dentro una suite aborta quella funzione ma la suite stampa comunque PASS.**
   `test_battle_save.gd` lo faceva da mesi (53 controlli invece di 54). Fai grep di `SCRIPT ERROR`
   sull'output, non solo dell'ultima riga. Per la stessa ragione l'exit code dopo una pipe è quello
   di `grep`, non del motore: cattura prima (`cmd > log 2>&1; rc=$?`).
4. **Esistono due costanti di banda**: `_in_deploy()` (quattro colonne, storica, alimenta il
   generatore di riferimento) e `DEPLOY_BAND = 6` (la zona reale). Il codice scalato usa
   `is_deploy_zone`/`_in_band`; il percorso di riferimento non deve cambiare.
5. **Sostituisci un predicato solo con una prova di equivalenza.** `escapes_deploy_band()` collassa
   le rotazioni libere in un grafo di ancore; `test_pathsearch_equivalence.gd` lo confronta con la
   ricerca completa su ogni campo, footprint, budget e lato (1.440 controlli).
6. **Un bound non stretto non pota mai.** Il primo bound dell'IA ignorava il termine di controllo e
   il caso "non arriva nemmeno a portata" e non scattava **mai** su 80×80 (misurato). Con
   `-1.2·control` e il taglio 57→22 pota, e le decisioni restano identiche bit per bit.
7. **Provare l'equivalenza dell'IA sulla STESSA mappa.** Appiattisci il terreno **e resetta
   `rng.seed`** prima di rischierare, altrimenti confronti consumi di RNG dipendenti dal terreno.
8. **Barre e anelli sono in unità di mondo.** Una barra vita fissa da 36 px sono quattro celle su un
   campo da 8 px: deriva tutto da `cell_px` (lo zoom è una trasformazione di camera, `cell_px` no).
9. **`ships.clear()` lascia `by_id` stantio** — svuota entrambi, o `get_ship()` restituisce `null` e
   i validatori rispondono con un motivo fuorviante. Aggiungi scafi con `battle._add_ship(ship)`.
10. **Le righe `ERROR: Deployment failed…` in una run verde sono attese** (test negativi che
    chiamano `push_error` di proposito).
11. **I rami di `match` sono scope separati**; `cell` è un nome locale in tutto `battle_view` (la
    dimensione in pixel è `cell_px`).
12. **Strumenti nativi + MSYS**: `git worktree`, `--script`, `--path` vogliono path `C:/...`; `/tmp`
    non è tradotto e `/c/...` fa fallire Godot con *Invalid project path*. Un worktree nuovo richiede
    `--import` prima di `--script`, altrimenti esce silenziosamente con codice 0.
13. **`WASAPI … dummy driver` / `ERR_CANT_OPEN` nelle run con finestra** = questa macchina non ha
    dispositivo audio. Preesistente, non è un fallimento.
14. **Le sonde visive sovrascrivono i loro PNG** e scrivono in `../../G-DEV-REPORTS/<nome>/`
    (relativo alla radice del progetto): in questo pacchetto la destinazione è `../G-DEV-REPORTS/`.
15. **`RandomNumberGenerator.state = 0` dopo `seed` annulla il seed**: imposta solo `rng.seed` e
    verifica con un hash del layout, non a occhio.
16. **I test non devono scrivere il salvataggio reale.** Le suite usano
    `user://void_command_save.test.json`; `test_save_isolation.gd` esegue tutte le suite come
    processi figli e prova che il salvataggio vero resta byte-identico. In questa sessione l'hash è
    stato confrontato prima/dopo: invariato. Fai lo stesso prima di lanciare suite che non hai
    scritto tu.

---

## 7. Debiti tecnici aperti (misurati, ordinati per payoff)

1. **`MAX_ROUNDS = 40` non scala con il campo.** Su 80×80, IA vs IA: 5 battaglie su 6 (budget
   0/60/100 FP, 9–29 scafi) finite al limite con 1–3 scafi vivi per parte; le flotte partono a
   ~68 celle. Cambiarlo significa cambiare una condizione di vittoria: serve un'autorizzazione.
   La forma ovvia del fix è `40 * sqrt(area_ratio)`. **È il primo problema di giocabilità.**
2. **Un turno nemico con 52 scafi costa ~21 s su 80×80** (~0,4 s per scafo) e gira sincrono dentro
   `end_turn`: la finestra si blocca. Le flotte di default restano sotto 0,5 s.
3. **La generazione della mappa costa ~1,4 s su 80×80**, dominata da `nav_stats()` (25.600 stati per
   layout candidato) — ora la fetta più grossa dell'hitch d'avvio battaglia.
4. **Il roster mostra 7 righe** a qualsiasi dimensione di flotta (52 scafi: si scorre). Nessun
   filtro, nessuna doppia colonna.
5. **Il campo grande è leggibile solo zoomato** (celle da 8 px a `Home`).
6. **L'IA è a un turno di profondità**: minimizza traslazioni, non piani.
7. **Refit Carrier/Dreadnought mancante** (il salvataggio potenzia solo le quattro classi originali);
   i tassi di vittoria per budget non sono misurati (`fleet_balance_probe.gd` è lento, non completato).
8. **Audio assente** al 100 %.

---

## 8. Milestone successiva raccomandata (richiede autorizzazione)

- **M8a — ridisegno di geometria e silhouette** (rinviato da M7B): Cruiser 1×3 → 1×2 (o no),
  silhouette per classe e relativi test; mantenere la regola length-only salvo mandato contrario e
  ri-derivare le guardie di `hull_draw_scale`.
- **M8b — regole scalate sul campo**: limite di round (debito 1), distanza iniziale delle flotte su
  80×80, costo del turno nemico (debito 2). Ognuno è un cambio di regole o di motore con mandato e
  misura propri.

*Definition of done* per qualunque voce: gate 0, 24 suite verdi con gli stessi conteggi salvo dove
una regola documentata è cambiata, hash del salvataggio invariato, sonda visiva rigenerata e
ispezionata, report in `docs/`.

---

## 9. Mappa dei file (cosa conta davvero)

**Regole — `scripts/core/`**: `map_config.gd` (preset, `TITAN`) · `battle_map.gd` (`_in_band`,
generatore scalato) · `battle.gd` (`_pocket_ok`, deployment, turni) · `pathfinder.gd` (heap,
`escapes_deploy_band`) · `ai.gd` (punteggio a passata singola + bound) · `ship.gd` (`bow_vector`,
`action_state`) · `ship_defs.gd` (catalogo) · `fleet_points.gd` (budget, limiti) · `save_data.gd`,
`battle_save.gd` (persistenza v1).

**UI — `scripts/ui/`**: `battle_screen.gd` (`_play_offset`, clamp, feedback di rotazione) ·
`battle_view.gd` (prua, barre scalate su `cell_px`, overlay scafo speso) · `hud.gd` (finestra del
roster, marcatori, guida comandi) · `menu_screen.gd`, `fleet_screen.gd` (ciclo dei preset).

**Test**: 24 suite + sonde. Nuove in M7B: `test_bigmap.gd`, `test_controls.gd`,
`test_pathsearch_equivalence.gd`; sonde `bigmap_probe.gd`, `ai_decisions_probe.gd`,
`m7b_visual_probe.gd`.

---

## 10. Protocollo di ripresa

1. Leggi §1–§3. Esegui `git status --porcelain` e `bash verify.sh --quick`: albero sporco o gate
   rosso → **fermati e riporta**.
2. Esegui `bash verify.sh`. Confronta i conteggi con `README.md` §7. Qualsiasi differenza →
   diagnostica, non codice.
3. Confronta l'hash del salvataggio reale con quello di §1 (se il file esiste sulla macchina).
4. **Chiedi all'utente quale milestone è autorizzata**: §8 è una raccomandazione, non
   un'autorizzazione.
5. Prima di modificare: albero pulito, un commit per unità coerente, test prima del commit.

---

## 11. Backup e ripristino

| | |
|---|---|
| Backup di sessione | `C:\Users\Dave\PROGETTI\G-DEV-BACKUP-2026-10-20\` |
| Contenuto | `void-command-project-20261020.tar.gz` (progetto pre-archiviazione, cache inclusa) · `echoes-of-ash-project-20261020.tar.gz` · `void-command-audit-20261020.tar.gz` (`G-DEV-AUDIT/` completo, M0→M7B) · `void-command-reports-20261020.tar.gz` (`G-DEV-REPORTS/void-command*`: screenshot e log) · `checkpoints-20261020.tar.gz` (i checkpoint tar precedenti) |
| Integrità | `SHA256SUMS.txt` accanto agli archivi; ogni archivio verificato con `tar tzf` |
| Ripristino di un singolo file | `tar -xzf <archivio> -C <destinazione> <percorso>` |
| Ripristino completo | scompattare `void-command-project-20261020.tar.gz` e poi `--import` |

I report M0–M7 e gli screenshot **non** fanno parte del pacchetto: stanno solo nel backup. Il
pacchetto conserva la loro unica informazione non riproducibile in `docs/M7B-REPORT.md` e nel §5
di questo file.
