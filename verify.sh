#!/usr/bin/env bash
# Verifica riproducibile di VOID COMMAND (pacchetto di archivio).
#
# Uso:
#   GODOT=/percorso/Godot_v4.7.2-stable_win64_console.exe bash verify.sh            # completo
#   GODOT=... bash verify.sh --quick                                                # senza le suite
#   bash verify.sh --suites test_core test_hud                                      # suite scelte
#
# Passi: versione → --check-only su ogni .gd → --import → avvio headless → suite headless.
# Esce 0 solo se tutto passa. Le suite usano un file di salvataggio di prova
# (`user://void_command_save.test.json`) e non devono toccare il salvataggio reale:
# se hai un salvataggio reale, confrontane l'hash prima e dopo.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_SUITES="test_core test_ui test_acceptance test_stress test_footprint test_multicell \
test_pathfinding test_maps test_map_stress test_deployment test_hud test_battle_save \
test_catalog test_fleet test_fleet_ui test_frigate test_capital test_navigation \
test_carrier test_camera test_grid test_pathsearch_equivalence test_bigmap test_controls"

MODE=full; SUITES=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick)  MODE=quick; shift ;;
    --suites) MODE=custom; shift; SUITES="$*"; break ;;
    *) echo "argomento non riconosciuto: $1" >&2; exit 64 ;;
  esac
done
[ "$MODE" = custom ] || SUITES="$ALL_SUITES"

GD="${GODOT:-}"
if [ -z "$GD" ]; then
  if command -v godot >/dev/null 2>&1; then GD="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then GD="$(command -v godot4)"
  else
    echo "ERRORE: imposta GODOT=/percorso/dell'eseguibile Godot 4.7.2 (variante _console)." >&2
    exit 1
  fi
fi
[ -x "$GD" ] || { echo "ERRORE: eseguibile non trovato o non eseguibile: $GD" >&2; exit 1; }
if command -v cygpath >/dev/null 2>&1; then PROJ="$(cygpath -m "$HERE")"; else PROJ="$HERE"; fi

fail() { echo "ERRORE: $*" >&2; echo "=== ESITO: FALLITO ===" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }

[ -f "$PROJ/project.godot" ] || fail "project.godot assente in $PROJ"

step "1. motore"
VER="$("$GD" --version 2>&1 | head -1)"
echo "versione: $VER"
case "$VER" in 4.*) ;; *) fail "versione inattesa: $VER (serve Godot 4.7.x)" ;; esac

step "2. import (genera .godot/ e la cache dei class_name)"
# Va PRIMA del --check-only: senza .godot/global_script_class_cache.cfg ogni script che usa un
# class_name fallisce con "Could not find type" e la verifica sembra rotta.
"$GD" --headless --path "$PROJ" --import >/dev/null 2>&1
echo "  eseguito (--import)"

step "3. sintassi e tipi (--check-only) su ogni script"
n_ok=0; n_ko=0; ko_list=""
while IFS= read -r s; do
  [ -z "$s" ] && continue
  out="$("$GD" --headless --path "$PROJ" --check-only --script "res://$s" 2>&1)"
  if printf '%s' "$out" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load'; then
    n_ko=$((n_ko+1)); ko_list="$ko_list $s"
    echo "  FAIL  $s"
    printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error' | sed 's/^/        /' | head -3
  else
    n_ok=$((n_ok+1)); echo "  ok    $s"
  fi
done < <(cd "$HERE" && find . -name '*.gd' -not -path './.godot/*' | sed 's|^\./||' | sort)
echo "  -> $n_ok ok, $n_ko con errori"
[ "$n_ko" -eq 0 ] || fail "script con errori di parsing:$ko_list"

step "4. avvio headless"
out="$("$GD" --headless --path "$PROJ" --quit 2>&1)"; rc=$?
printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
[ "$rc" -eq 0 ] || fail "avvio headless fallito (exit $rc)"
printf '%s' "$out" | grep -q 'SCRIPT ERROR' && fail "errori di script all'avvio"

if [ "$MODE" = quick ]; then
  echo
  echo "=== ESITO: TUTTO OK (exit 0, --quick: suite non eseguite) ==="
  exit 0
fi

step "5. suite headless"
total=0; failures=0
for t in $SUITES; do
  out="$("$GD" --headless --path "$PROJ" --script "res://tests/$t.gd" 2>&1)"; rc=$?
  line="$(printf '%s\n' "$out" | grep -E '^checks:' | tail -1)"
  errs="$(printf '%s' "$out" | grep -c 'SCRIPT ERROR')"
  echo "  $t exit=$rc script_errors=$errs ${line:-'(nessuna riga checks:)'}"
  # un SCRIPT ERROR abortisce la funzione ma la suite può ancora stampare PASS
  if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ]; then
    failures=$((failures+1))
    printf '%s\n' "$out" | tail -15 | sed 's/^/      /'
  fi
  n="$(printf '%s' "$line" | grep -oE '[0-9]+' | tail -1)"; total=$((total + ${n:-0}))
done
echo "  -> suite: $(echo $SUITES | wc -w) · fallite: $failures · controlli: $total"
[ "$failures" -eq 0 ] || fail "$failures suite fallite"

echo
echo "=== ESITO: TUTTO OK (exit 0) ==="
