#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=skills/apagado-seguro/scripts/quien-trabaja.sh
if ! source "$SCRIPT_DIR/quien-trabaja.sh" 2>/dev/null; then
  echo "FAIL: No se pudo cargar quien-trabaja.sh con source" >&2
  exit 1
fi

failures=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $msg"
  else
    echo "FAIL: $msg (esperaba '$expected', obtuvo '$actual')" >&2
    failures=$((failures + 1))
  fi
}

echo "=== Step 1: Tests unitarios de clasificar (con nueva firma y reglas) ==="

export TZ="America/Argentina/Buenos_Aires"

# Epochs del 2026-11-05
ep_0100=$(date -d "2026-11-05 01:00:00" +%s)
ep_0200=$(date -d "2026-11-05 02:00:00" +%s)
ep_0400=$(date -d "2026-11-05 04:00:00" +%s)
ep_0920=$(date -d "2026-11-05 09:20:00" +%s)
ep_1000=$(date -d "2026-11-05 10:00:00" +%s)
ep_1430=$(date -d "2026-11-05 14:30:00" +%s)
ep_1436=$(date -d "2026-11-05 14:36:00" +%s)

# Tests pedidos por el coordinador:
# 1. si, "You've hit your usage limit ... try again at 2:10 PM", última 09:20, ahora 10:00 → esperando-reset
res=$(clasificar si 40 "You've hit your usage limit ... try again at 2:10 PM" "$ep_0920" "$ep_1000")
assert_eq "$res" "esperando-reset" "si, hit your usage limit ... try again at 2:10 PM, última 09:20, ahora 10:00 -> esperando-reset"

# 2. lo mismo con ahora 14:30 → libre
res=$(clasificar si 310 "You've hit your usage limit ... try again at 2:10 PM" "$ep_0920" "$ep_1430")
assert_eq "$res" "libre" "si, hit your usage limit ... try again at 2:10 PM, última 09:20, ahora 14:30 -> libre"

# 3. si, "5-hour limit reached ∙ resets 3am", última 01:00, ahora 02:00 → esperando-reset
res=$(clasificar si 60 "5-hour limit reached ∙ resets 3am" "$ep_0100" "$ep_0200")
assert_eq "$res" "esperando-reset" "si, 5-hour limit reached ∙ resets 3am, última 01:00, ahora 02:00 -> esperando-reset"

# 4. ahora 04:00 → libre
res=$(clasificar si 180 "5-hour limit reached ∙ resets 3am" "$ep_0100" "$ep_0400")
assert_eq "$res" "libre" "si, 5-hour limit reached ∙ resets 3am, última 01:00, ahora 04:00 -> libre"

# 5. si, "──weekly ●●●●○○ 49% ⟳ nov 11, 5:00" → libre
res=$(clasificar si 5 "──weekly ●●●●○○ 49% ⟳ nov 11, 5:00" "$ep_0920" "$ep_1000")
assert_eq "$res" "libre" "si, statusline semanal sin frase de límite -> libre"

# 6. si, "5h 30% resets 14:00" (statusline, sin frase de límite) → libre
res=$(clasificar si 5 "5h 30% resets 14:00" "$ep_0920" "$ep_1000")
assert_eq "$res" "libre" "si, statusline 5h sin frase de límite -> libre"

# 7. no, 5 → trabajando
res=$(clasificar no 5 "…" "$ep_0920" "$ep_1000")
assert_eq "$res" "trabajando" "no, 5 -> trabajando"

# 8. no, 61 → trabado
res=$(clasificar no 61 "…" "$ep_0920" "$ep_1000")
assert_eq "$res" "trabado" "no, 61 -> trabado"

# 9. Fallback cuando hay frase pero no hora legible (+5h)
res=$(clasificar si 10 "hit your limit! please wait" "$ep_0920" "$ep_1000")
assert_eq "$res" "esperando-reset" "si, frase de límite sin hora legible, última 09:20 (+5h=14:20), ahora 10:00 -> esperando-reset"
res=$(clasificar si 320 "hit your limit! please wait" "$ep_0920" "$ep_1436")
assert_eq "$res" "libre" "si, frase de límite sin hora legible (+5h=14:20 +15m=14:35), ahora 14:36 -> libre"

echo "=== Defecto 3: Reset con fecha ==="
ep_05_1500=$(date -d "2026-11-05 15:00:00" +%s)
ep_12_1420=$(date -d "2026-11-12 14:20:00" +%s)
ep_12_1426=$(date -d "2026-11-12 14:26:00" +%s)

# Formato: "Try again at Nov 12, 2:10 PM" con última salida 05/11/2026 09:20
res=$(clasificar si 340 "You have hit your usage limit. Try again at Nov 12, 2:10 PM" "$ep_0920" "$ep_05_1500")
assert_eq "$res" "esperando-reset" "fecha futura Nov 12: ahora 05/11 15:00 -> esperando-reset"

res=$(clasificar si 10380 "You have hit your usage limit. Try again at Nov 12, 2:10 PM" "$ep_0920" "$ep_12_1420")
assert_eq "$res" "esperando-reset" "fecha futura Nov 12: ahora 12/11 14:20 -> esperando-reset"

res=$(clasificar si 10386 "You have hit your usage limit. Try again at Nov 12, 2:10 PM" "$ep_0920" "$ep_12_1426")
assert_eq "$res" "libre" "fecha futura Nov 12: ahora 12/11 14:26 -> libre"

# Formato real de Codex con ordinal y año: "You've hit your usage limit. ... or try again at Nov 12th, 2026 4:50 PM."
ep_07_2305=$(date -d "2026-11-07 23:05:00" +%s)
ep_12_1650=$(date -d "2026-11-12 16:50:00" +%s)
ep_12_1706=$(date -d "2026-11-12 17:06:00" +%s)

res=$(clasificar si 6825 "You've hit your usage limit. ... or try again at Nov 12th, 2026 4:50 PM." "$ep_07_2305" "$ep_12_1650")
assert_eq "$res" "esperando-reset" "Codex ordinal+año Nov 12th 2026 4:50 PM: ahora 12/11 16:50 -> esperando-reset"

res=$(clasificar si 6841 "You've hit your usage limit. ... or try again at Nov 12th, 2026 4:50 PM." "$ep_07_2305" "$ep_12_1706")
assert_eq "$res" "libre" "Codex ordinal+año Nov 12th 2026 4:50 PM: ahora 12/11 17:06 -> libre"

# Texto partido en dos líneas ("try" / "again at")
preview_multiline=$'You have hit your usage limit. Try\nagain at Nov 12, 2:10 PM'
res=$(clasificar si 340 "$preview_multiline" "$ep_0920" "$ep_05_1500")
assert_eq "$res" "esperando-reset" "preview multilínea Try\nagain at Nov 12: ahora 05/11 15:00 -> esperando-reset"

# Preview mixto: statusline con resets anterior + aviso de límite con Try again at
preview_mixto=$'5h 30% resets 14:00\nYou have hit your usage limit. Try again at Nov 12, 2:10 PM'
res=$(clasificar si 340 "$preview_mixto" "$ep_0920" "$ep_05_1500")
assert_eq "$res" "esperando-reset" "preview mixto statusline + límite: ahora 05/11 15:00 -> esperando-reset"

echo "=== Nuevos tests de extracción anclada y casos de revisión ==="
# Caso A: statusline 'resets 14:00' + '5-hour limit reached · resets Nov 12, 2:10 PM'
preview_caso_a=$'5h 30% resets 14:00\n5-hour limit reached · resets Nov 12, 2:10 PM'
res=$(clasificar si 310 "$preview_caso_a" "$ep_0920" "$ep_1430")
assert_eq "$res" "esperando-reset" "Caso A clasificar: ahora 05/11 14:30 -> esperando-reset"

# Caso B: 'You hit your limit. Try again at ???' + '5h 30% resets 14:00' -> fallback 09:20+5h=14:20 (+15m=14:35)
preview_caso_b=$'You hit your limit. Try again at ???\n5h 30% resets 14:00'
res=$(clasificar si 310 "$preview_caso_b" "$ep_0920" "$ep_1430")
assert_eq "$res" "esperando-reset" "Caso B clasificar: ahora 05/11 14:30 -> esperando-reset"
res=$(clasificar si 316 "$preview_caso_b" "$ep_0920" "$ep_1436")
assert_eq "$res" "libre" "Caso B clasificar: ahora 05/11 14:36 -> libre"

# limit reached · resets 3 days -> fallback (no 03:00): base 09:20+5h=14:20 (+15m=14:35)
res=$(clasificar si 310 "limit reached · resets 3 days" "$ep_0920" "$ep_1430")
assert_eq "$res" "esperando-reset" "resets 3 days no es hora: ahora 14:30 -> esperando-reset"
res=$(clasificar si 316 "limit reached · resets 3 days" "$ep_0920" "$ep_1436")
assert_eq "$res" "libre" "resets 3 days no es hora: ahora 14:36 -> libre"

# 'resets nov 12 at 4:50 pm' tras 'limit reached' con conector 'at'
res=$(clasificar si 6000 "limit reached · resets nov 12 at 4:50 pm" "$ep_0920" "$ep_12_1650")
assert_eq "$res" "esperando-reset" "resets nov 12 at 4:50 pm: ahora 12/11 16:50 -> esperando-reset"
res=$(clasificar si 6016 "limit reached · resets nov 12 at 4:50 pm" "$ep_0920" "$ep_12_1706")
assert_eq "$res" "libre" "resets nov 12 at 4:50 pm: ahora 12/11 17:06 -> libre"

# ultima_salida=0, ahora 05/11 14:30, 'Try again at Nov 12, 2:10 PM' -> esperando-reset
res=$(clasificar si 0 "Try again at Nov 12, 2:10 PM" 0 "$ep_1430")
assert_eq "$res" "esperando-reset" "ultima_salida=0 con reset futuro Nov 12 -> esperando-reset"

# R03: ultima_salida=0 y hora sin fecha:
# Si la hora de hoy ya pasó, usar mañana SOLO si queda a 5 h o menos de ahora; si no, hoy (y se libera a reset+15).
ep_05_1500=$(date -d "2026-11-05 15:00:00" +%s)
res=$(clasificar si 0 "You have hit your usage limit · resets 2:40pm" 0 "$ep_05_1500")
assert_eq "$res" "libre" "R03: ultima_salida=0, ahora 15:00, resets 2:40pm -> libre"

ep_05_2300=$(date -d "2026-11-05 23:00:00" +%s)
res=$(clasificar si 0 "You have hit your usage limit · resets 3am" 0 "$ep_05_2300")
assert_eq "$res" "esperando-reset" "R03: ultima_salida=0, ahora 23:00, resets 3am -> esperando-reset"

echo "=== Tests de avisos de límite reales de Claude Code ==="
ep_05_1000=$(date -d "2026-11-05 10:00:00" +%s)
ep_05_1450=$(date -d "2026-11-05 14:50:00" +%s)
ep_05_1456=$(date -d "2026-11-05 14:56:00" +%s)
ep_05_1850=$(date -d "2026-11-05 18:50:00" +%s)
ep_05_1856=$(date -d "2026-11-05 18:56:00" +%s)

ep_oct20_1000=$(date -d "2026-10-20 10:00:00" +%s)
ep_oct28_0510=$(date -d "2026-10-28 05:10:00" +%s)
ep_oct28_0516=$(date -d "2026-10-28 05:16:00" +%s)

ep_06_0510=$(date -d "2026-11-06 05:10:00" +%s)
ep_06_0516=$(date -d "2026-11-06 05:16:00" +%s)

# 1. session limit: 'You'\''ve hit your session limit · resets 2:40pm (America/Argentina/Buenos_Aires)'
preview_session="You've hit your session limit · resets 2:40pm (America/Argentina/Buenos_Aires)"
res=$(clasificar si 290 "$preview_session" "$ep_05_1000" "$ep_05_1450")
assert_eq "$res" "esperando-reset" "Claude Code session limit 2:40pm: ahora 14:50 -> esperando-reset"
res=$(clasificar si 296 "$preview_session" "$ep_05_1000" "$ep_05_1456")
assert_eq "$res" "libre" "Claude Code session limit 2:40pm: ahora 14:56 -> libre"

# 2. 5-hour limit: 'You'\''ve hit your 5-hour limit · resets 6:40pm (America/Argentina/Buenos_Aires)'
preview_5h="You've hit your 5-hour limit · resets 6:40pm (America/Argentina/Buenos_Aires)"
res=$(clasificar si 530 "$preview_5h" "$ep_05_1000" "$ep_05_1850")
assert_eq "$res" "esperando-reset" "Claude Code 5-hour limit 6:40pm: ahora 18:50 -> esperando-reset"
res=$(clasificar si 536 "$preview_5h" "$ep_05_1000" "$ep_05_1856")
assert_eq "$res" "libre" "Claude Code 5-hour limit 6:40pm: ahora 18:56 -> libre"

# 3. weekly limit con fecha: 'You'\''ve hit your weekly limit · resets Oct 28, 5am (America/Argentina/Buenos_Aires)'
preview_weekly_date="You've hit your weekly limit · resets Oct 28, 5am (America/Argentina/Buenos_Aires)"
res=$(clasificar si 11230 "$preview_weekly_date" "$ep_oct20_1000" "$ep_oct28_0510")
assert_eq "$res" "esperando-reset" "Claude Code weekly limit Oct 28 5am: ahora 28/10 05:10 -> esperando-reset"
res=$(clasificar si 11236 "$preview_weekly_date" "$ep_oct20_1000" "$ep_oct28_0516")
assert_eq "$res" "libre" "Claude Code weekly limit Oct 28 5am: ahora 28/10 05:16 -> libre"

# 4. weekly limit sin fecha: 'You'\''ve hit your weekly limit · resets 5am (America/Argentina/Buenos_Aires)'
preview_weekly_nodate="You've hit your weekly limit · resets 5am (America/Argentina/Buenos_Aires)"
res=$(clasificar si 1150 "$preview_weekly_nodate" "$ep_05_1000" "$ep_06_0510")
assert_eq "$res" "esperando-reset" "Claude Code weekly limit 5am (al día siguiente): ahora 06/11 05:10 -> esperando-reset"
res=$(clasificar si 1156 "$preview_weekly_nodate" "$ep_05_1000" "$ep_06_0516")
assert_eq "$res" "libre" "Claude Code weekly limit 5am (al día siguiente): ahora 06/11 05:16 -> libre"

echo "=== Tests de revisión adversaria (F04, F05, F06, F10) ==="
# F04: Zona explícita IANA en el aviso (America/Argentina/Buenos_Aires) evaluada en host UTC
ep_f04_base=$(TZ=UTC date -d "2026-11-05 09:00:00" +%s)
ep_f04_now=$(TZ=UTC date -d "2026-11-05 15:00:00" +%s)
res=$(TZ=UTC clasificar si 0 "You've hit your session limit · resets 2:40pm (America/Argentina/Buenos_Aires)" "$ep_f04_base" "$ep_f04_now")
assert_eq "$res" "esperando-reset" "F04: aviso con TZ explícito evaluado en host UTC -> esperando-reset"

# F05: DST fall en Nueva York (03:00 no alcanzado a las 02:30 del 1 de noviembre)
ep_f05_base=$(TZ="America/New_York" date -d "2026-10-31 23:00:00" +%s)
ep_f05_now=$(TZ="America/New_York" date -d "2026-11-01 02:30:00" +%s)
res=$(TZ="America/New_York" clasificar si 0 "You've hit your session limit · resets 3am" "$ep_f05_base" "$ep_f05_now")
assert_eq "$res" "esperando-reset" "F05: DST fall reset 03:00 no alcanzado a las 02:30 -> esperando-reset"

# F06: Segundos en la hora 'Nov 12, 2:10:59 PM' no debe truncarse a 2:10 AM
ep_f06_base=$(TZ="$TZ" date -d "2026-11-05 09:00:00" +%s)
ep_f06_now=$(TZ="$TZ" date -d "2026-11-12 14:00:00" +%s)
res=$(clasificar si 0 "Try again at Nov 12, 2:10:59 PM" "$ep_f06_base" "$ep_f06_now")
assert_eq "$res" "esperando-reset" "F06: reset 14:10:59 no alcanzado a las 14:00 -> esperando-reset"

# F10: idle=no pero con aviso de límite pendiente a las 2pm manda sobre regla de 60 min
ep_f10_base=$(TZ="$TZ" date -d "2026-11-05 08:00:00" +%s)
ep_f10_now=$(TZ="$TZ" date -d "2026-11-05 10:00:00" +%s)
res=$(clasificar no 120 "You've hit your session limit · resets 2pm" "$ep_f10_base" "$ep_f10_now")
assert_eq "$res" "esperando-reset" "F10: aviso de límite pendiente a las 2pm manda sobre idle=no y 120 min -> esperando-reset"

echo "=== Tests de zona del sistema sin zona en aviso ==="
# 1. Con TZ=UTC exportado y un aviso sin zona 'You've hit your session limit · resets 2:40pm',
# última salida 05/11/2026 10:00 UTC -> esperando-reset a 14:50 UTC y libre a 14:56 UTC
ep_tz_utc_base=$(TZ=UTC date -d "2026-11-05 10:00:00" +%s)
ep_tz_utc_1450=$(TZ=UTC date -d "2026-11-05 14:50:00" +%s)
ep_tz_utc_1456=$(TZ=UTC date -d "2026-11-05 14:56:00" +%s)
preview_no_tz="You've hit your session limit · resets 2:40pm"

res_utc_1450=$(TZ=UTC clasificar si 0 "$preview_no_tz" "$ep_tz_utc_base" "$ep_tz_utc_1450")
assert_eq "$res_utc_1450" "esperando-reset" "TZ=UTC sin zona en aviso: 14:50 UTC -> esperando-reset"

res_utc_1456=$(TZ=UTC clasificar si 0 "$preview_no_tz" "$ep_tz_utc_base" "$ep_tz_utc_1456")
assert_eq "$res_utc_1456" "libre" "TZ=UTC sin zona en aviso: 14:56 UTC -> libre"

# 2. Con TZ sin definir (env -u TZ) que use la zona del sistema
res_sys_1450=$(env -u TZ bash -c '
  source "'"$SCRIPT_DIR"'/quien-trabaja.sh"
  preview="You'\''ve hit your session limit · resets 2:40pm"
  base=$(date -d "2026-11-05 10:00:00" +%s)
  now_esp=$(date -d "2026-11-05 14:50:00" +%s)
  clasificar si 0 "$preview" "$base" "$now_esp"
')
assert_eq "$res_sys_1450" "esperando-reset" "env -u TZ sin zona en aviso: 14:50 local -> esperando-reset"

res_sys_1456=$(env -u TZ bash -c '
  source "'"$SCRIPT_DIR"'/quien-trabaja.sh"
  preview="You'\''ve hit your session limit · resets 2:40pm"
  base=$(date -d "2026-11-05 10:00:00" +%s)
  now_lib=$(date -d "2026-11-05 14:56:00" +%s)
  clasificar si 0 "$preview" "$base" "$now_lib"
')
assert_eq "$res_sys_1456" "libre" "env -u TZ sin zona en aviso: 14:56 local -> libre"

# 3. Verificar que si TZ no está definida, no se pasa TZ al comando date ni se hardcodea una zona fija
mock_date_dir=$(mktemp -d)
cat << EOF > "$mock_date_dir/date"
#!/usr/bin/env bash
if [[ -n "\${TZ+x}" ]]; then
  echo "SET:\$TZ" >> "$mock_date_dir/calls.log"
else
  echo "UNSET" >> "$mock_date_dir/calls.log"
fi
exec /usr/bin/date "\$@"
EOF
chmod +x "$mock_date_dir/date"

env -u TZ PATH="$mock_date_dir:$PATH" bash -c '
  source "'"$SCRIPT_DIR"'/quien-trabaja.sh"
  clasificar si 0 "You'\''ve hit your session limit · resets 2:40pm" 1793872800 1793890560 >/dev/null
'

if grep -q "^SET:" "$mock_date_dir/calls.log" 2>/dev/null; then
  echo "FAIL: clasificar fijó TZ='$(head -n 1 "$mock_date_dir/calls.log")' cuando TZ no estaba definida y el aviso no traía zona" >&2
  failures=$((failures + 1))
else
  echo "PASS: clasificar no exportó TZ cuando no estaba definida y el aviso no traía zona"
fi
rm -rf "$mock_date_dir"

if grep -q "America/Argentina/Buenos_Aires" "$SCRIPT_DIR/quien-trabaja.sh"; then
  echo "FAIL: quien-trabaja.sh contiene zona horaria hardcodeada America/Argentina/Buenos_Aires" >&2
  failures=$((failures + 1))
else
  echo "PASS: quien-trabaja.sh no contiene zona horaria hardcodeada"
fi


echo "=== Tests de integración: quien-trabaja.sh y apagar.sh con mock orca ==="

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_ORCA="$TMP_DIR/mock-orca"

cat << 'EOF' > "$MOCK_ORCA"
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
subcmd="${2:-}"

if [[ "$cmd" == "terminal" && "$subcmd" == "list" ]]; then
  cat "$MOCK_ORCA_STATE/terminal_list.json"
  exit 0
elif [[ "$cmd" == "terminal" && "$subcmd" == "wait" ]]; then
  if [[ -f "$MOCK_ORCA_STATE/wait_override.json" ]]; then
    cat "$MOCK_ORCA_STATE/wait_override.json"
    exit 0
  fi
  handle=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--terminal" ]]; then
      handle="$2"
      shift 2
    else
      shift
    fi
  done
  if grep -q "^$handle:idle" "$MOCK_ORCA_STATE/idle_status.txt" 2>/dev/null; then
    echo '{"ok":true,"result":{"wait":{"satisfied":true,"status":"running"}}}'
    exit 0
  else
    echo '{"ok":false,"error":{"code":"timeout","message":"timeout"}}' >&2
    exit 1
  fi
fi

echo "Mock no soporta: $*" >&2
exit 1
EOF
chmod +x "$MOCK_ORCA"

MOCK_STATE="$TMP_DIR/state"
mkdir -p "$MOCK_STATE"
export MOCK_ORCA_STATE="$MOCK_STATE"
export ORCA_CLI_COMMAND="$MOCK_ORCA"

# Fijar AHORA_EPOCH en 1793884800 (2026-11-05 10:20:00)
export AHORA_EPOCH=1793884800
# 5 min atras = 1793884800 - 300 = 1793884500 (1793884500000 ms)
# 65 min atras = 1793884800 - 3900 = 1793880900 (1793880900000 ms)
export ORCA_PANE_KEY="tab_self:leaf_self"

cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_libre",
        "agentIdentity": "claude",
        "title": "Sesión Libre",
        "recordedPaneKey": "tab_1:leaf_1",
        "lastOutputAt": 1793884500000,
        "preview": "❯"
      },
      {
        "handle": "term_trabajando",
        "agentIdentity": "antigravity",
        "title": "Worker Activo",
        "recordedPaneKey": "tab_2:leaf_2",
        "lastOutputAt": 1793884500000,
        "preview": "Working..."
      },
      {
        "handle": "term_reset",
        "agentIdentity": "codex",
        "title": "Worker Sin Cuota",
        "recordedPaneKey": "tab_3:leaf_3",
        "lastOutputAt": 1793884500000,
        "preview": "You've hit your usage limit ... try again at 2:10 PM"
      },
      {
        "handle": "term_trabado",
        "agentIdentity": "claude",
        "title": "Sesión Colgada",
        "recordedPaneKey": "tab_4:leaf_4",
        "lastOutputAt": 1793880900000,
        "preview": "thinking..."
      },
      {
        "handle": "term_no_agent",
        "agentIdentity": null,
        "title": "Terminal de Shell",
        "recordedPaneKey": "tab_5:leaf_5",
        "lastOutputAt": 1793884500000,
        "preview": "bash"
      },
      {
        "handle": "term_propia",
        "agentIdentity": "antigravity",
        "title": "Mi Terminal",
        "tabId": "tab_self",
        "leafId": "leaf_self",
        "recordedPaneKey": null,
        "lastOutputAt": 1793884800000,
        "preview": "corriendo test"
      }
    ]
  }
}
EOF

cat << EOF > "$MOCK_STATE/idle_status.txt"
term_libre:idle
term_reset:idle
EOF

# Ejecutar quien-trabaja.sh
tsv_output=$("$SCRIPT_DIR/quien-trabaja.sh")

# Verificar que term_propia y term_no_agent no están en la salida
if echo "$tsv_output" | grep -q "term_propia"; then
  echo "FAIL: quien-trabaja.sh incluyó la terminal propia (debe excluirse por ORCA_PANE_KEY)" >&2
  failures=$((failures + 1))
else
  echo "PASS: quien-trabaja.sh excluye la terminal propia"
fi

if echo "$tsv_output" | grep -q "term_no_agent"; then
  echo "FAIL: quien-trabaja.sh incluyó una terminal sin agente" >&2
  failures=$((failures + 1))
else
  echo "PASS: quien-trabaja.sh ignora terminales sin agente"
fi

line_libre=$(echo "$tsv_output" | grep "^term_libre" || true)
assert_eq "$line_libre" $'term_libre\tclaude\tSesión Libre\tlibre\t5' "TSV term_libre"

line_trabajando=$(echo "$tsv_output" | grep "^term_trabajando" || true)
assert_eq "$line_trabajando" $'term_trabajando\tantigravity\tWorker Activo\ttrabajando\t5' "TSV term_trabajando"

line_reset=$(echo "$tsv_output" | grep "^term_reset" || true)
assert_eq "$line_reset" $'term_reset\tcodex\tWorker Sin Cuota\tesperando-reset\t5' "TSV term_reset"

line_trabado=$(echo "$tsv_output" | grep "^term_trabado" || true)
assert_eq "$line_trabado" $'term_trabado\tclaude\tSesión Colgada\ttrabado\t65' "TSV term_trabado"

echo "=== Tests de apagar.sh ==="

# 1. Cuando hay sesiones 'trabajando', 'esperando-reset' y 'trabado':
# apagar.sh imprime TODAS las no libres (trabajando, esperando-reset y trabado) y sale con 3
set +e
apagar_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_code=$?
set -e

assert_eq "$apagar_code" "3" "apagar.sh sale con código 3 cuando hay sesiones activas o esperando reset"

# Debe imprimir term_trabajando, term_reset Y term_trabado (todas las que no están libre)
if echo "$apagar_out" | grep -q "term_trabajando" && echo "$apagar_out" | grep -q "term_reset" && echo "$apagar_out" | grep -q "term_trabado"; then
  echo "PASS: apagar.sh imprime todas las terminales no libres (trabajando, esperando-reset y trabado)"
else
  echo "FAIL: apagar.sh no imprimió todas las terminales no libres esperadas: $apagar_out" >&2
  failures=$((failures + 1))
fi

# No debe imprimir term_libre
if echo "$apagar_out" | grep -q "term_libre"; then
  echo "FAIL: apagar.sh imprimió una terminal libre" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime terminales libres"
fi

# 2. Ahora simulamos que term_trabajando y term_reset se liberaron, pero term_trabado SIGUE trabado
cat << EOF > "$MOCK_STATE/idle_status.txt"
term_libre:idle
term_trabajando:idle
term_reset:idle
EOF
# Y cambiamos preview de reset para que no tenga frase de límite
sed -i 's/You.*2:10 PM/listo/' "$MOCK_STATE/terminal_list.json"

set +e
apagar_trabado_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_trabado_code=$?
set -e

assert_eq "$apagar_trabado_code" "0" "apagar.sh sale con 0 cuando solo hay terminales trabadas (no bloquean el apagado)"

# Verifica que imprimió la terminal trabada para que el agente la anote
if echo "$apagar_trabado_out" | grep -q "term_trabado"; then
  echo "PASS: apagar.sh imprimió la terminal trabada antes del comando de apagado"
else
  echo "FAIL: apagar.sh no imprimió la terminal trabada" >&2
  failures=$((failures + 1))
fi

# Y también imprimió el shutdown
if echo "$apagar_trabado_out" | grep -q 'shutdown -P +5 "turno-noche: apagado en 5 min. Cancelar: shutdown -c"'; then
  echo "PASS: apagar.sh imprimió el comando de apagado correctamente"
else
  echo "FAIL: apagar.sh no imprimió el comando de shutdown esperado: $apagar_trabado_out" >&2
  failures=$((failures + 1))
fi

echo "=== Defecto 1: Título vacío corre los campos ==="
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_notitle",
        "agentIdentity": "claude",
        "title": "",
        "recordedPaneKey": "tab_notitle:leaf_notitle",
        "lastOutputAt": 1793884800000,
        "preview": "trabajando en algo"
      }
    ]
  }
}
EOF
: > "$MOCK_STATE/idle_status.txt"

# Validación de columna 3 ('-') en TSV para título vacío
qt_notitle_out=$("$SCRIPT_DIR/quien-trabaja.sh")
line_notitle=$(echo "$qt_notitle_out" | grep "^term_notitle" || true)
assert_eq "$line_notitle" $'term_notitle\tclaude\t-\ttrabajando\t0' "quien-trabaja.sh imprime '-' en columna 3 para título vacío"

set +e
apagar_notitle_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_notitle_code=$?
set -e

assert_eq "$apagar_notitle_code" "3" "terminal con title vacío y agente trabajando: apagar.sh sale 3"
if echo "$apagar_notitle_out" | grep -q "shutdown"; then
  echo "FAIL: apagar.sh imprimió shutdown a pesar de terminal ocupada con title vacío" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime shutdown con title vacío y agente trabajando"
fi

echo "=== Defecto 2: Inventario inválido = nadie trabajando ==="

# Caso 2a: ok: false con error
echo '{"ok":false,"error":{"code":"unavailable"}}' > "$MOCK_STATE/terminal_list.json"

set +e
qt_err_out=$("$SCRIPT_DIR/quien-trabaja.sh" 2>&1)
qt_err_code=$?
apagar_err_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_err_code=$?
set -e

assert_eq "$qt_err_code" "1" "quien-trabaja.sh sale 1 cuando ok=false"
if [[ "$apagar_err_code" -ne 0 ]]; then
  echo "PASS: apagar.sh --simulacro sale distinto de 0 cuando ok=false"
else
  echo "FAIL: apagar.sh --simulacro sale 0 cuando ok=false (esperaba != 0)" >&2
  failures=$((failures + 1))
fi

if echo "$apagar_err_out" | grep -q "shutdown"; then
  echo "FAIL: apagar.sh imprimió shutdown cuando ok=false" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime shutdown cuando ok=false"
fi

# Caso 2b: JSON vacío {}
echo '{}' > "$MOCK_STATE/terminal_list.json"

set +e
qt_empty_out=$("$SCRIPT_DIR/quien-trabaja.sh" 2>&1)
qt_empty_code=$?
apagar_empty_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_empty_code=$?
set -e

assert_eq "$qt_empty_code" "1" "quien-trabaja.sh sale 1 cuando json es {}"
if [[ "$apagar_empty_code" -ne 0 ]]; then
  echo "PASS: apagar.sh --simulacro sale distinto de 0 cuando json es {}"
else
  echo "FAIL: apagar.sh --simulacro sale 0 cuando json es {} (esperaba != 0)" >&2
  failures=$((failures + 1))
fi

if echo "$apagar_empty_out" | grep -q "shutdown"; then
  echo "FAIL: apagar.sh imprimió shutdown cuando json es {}" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime shutdown cuando json es {}"
fi

# Caso 2c: Array vacío válido (nadie trabajando)
echo '{"ok":true,"result":{"terminals":[]}}' > "$MOCK_STATE/terminal_list.json"

set +e
qt_valid_empty_out=$("$SCRIPT_DIR/quien-trabaja.sh" 2>&1)
qt_valid_empty_code=$?
apagar_valid_empty_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_valid_empty_code=$?
set -e

assert_eq "$qt_valid_empty_code" "0" "quien-trabaja.sh sale 0 con terminals: []"
assert_eq "$apagar_valid_empty_code" "0" "apagar.sh sale 0 con terminals: []"
if echo "$apagar_valid_empty_out" | grep -q "shutdown"; then
  echo "PASS: apagar.sh imprime shutdown con terminals: [] válido"
else
  echo "FAIL: apagar.sh no imprimió shutdown con terminals: [] válido" >&2
  failures=$((failures + 1))
fi

echo "=== Defecto: Preview mixto statusline + límite en mock ==="
export AHORA_EPOCH="$ep_05_1500"
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_mixto",
        "agentIdentity": "claude",
        "title": "Sesión Mixta",
        "recordedPaneKey": "tab_mixto:leaf_mixto",
        "lastOutputAt": $(( ep_0920 * 1000 )),
        "preview": "5h 30% resets 14:00\nYou have hit your usage limit. Try again at Nov 12, 2:10 PM"
      }
    ]
  }
}
EOF
echo "term_mixto:idle" > "$MOCK_STATE/idle_status.txt"

set +e
apagar_mixto_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_mixto_code=$?
set -e

assert_eq "$apagar_mixto_code" "3" "preview mixto en mock: apagar.sh sale 3"
if echo "$apagar_mixto_out" | grep -q "shutdown"; then
  echo "FAIL: apagar.sh imprimió shutdown con preview mixto" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime shutdown con preview mixto"
fi

echo "=== Defecto: Caso A en mock (statusline resets + 5-hour limit reached · resets Nov 12) ==="
export AHORA_EPOCH="$ep_1430"
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_caso_a",
        "agentIdentity": "claude",
        "title": "Sesión Caso A",
        "recordedPaneKey": "tab_a:leaf_a",
        "lastOutputAt": $(( ep_0920 * 1000 )),
        "preview": "5h 30% resets 14:00\n5-hour limit reached · resets Nov 12, 2:10 PM"
      }
    ]
  }
}
EOF
echo "term_caso_a:idle" > "$MOCK_STATE/idle_status.txt"

set +e
apagar_caso_a_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_caso_a_code=$?
set -e

assert_eq "$apagar_caso_a_code" "3" "Caso A en mock: apagar.sh sale 3"
if echo "$apagar_caso_a_out" | grep -q "shutdown"; then
  echo "FAIL: apagar.sh imprimió shutdown en Caso A" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime shutdown en Caso A"
fi

echo "=== Defecto: Claude Code session limit en mock ==="
export AHORA_EPOCH="$ep_05_1450"
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_session",
        "agentIdentity": "claude",
        "title": "Sesión Claude Code",
        "recordedPaneKey": "tab_sess:leaf_sess",
        "lastOutputAt": $(( ep_05_1000 * 1000 )),
        "preview": "You've hit your session limit · resets 2:40pm (America/Argentina/Buenos_Aires)"
      }
    ]
  }
}
EOF
echo "term_session:idle" > "$MOCK_STATE/idle_status.txt"

set +e
apagar_session_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_session_code=$?
set -e

assert_eq "$apagar_session_code" "3" "Claude Code session limit en mock: apagar.sh sale 3"
if echo "$apagar_session_out" | grep -q "shutdown"; then
  echo "FAIL: apagar.sh imprimió shutdown en Claude Code session limit" >&2
  failures=$((failures + 1))
else
  echo "PASS: apagar.sh no imprime shutdown en Claude Code session limit"
fi

echo "=== Tests de integración adversarios (F01, F02, F09, F10, F11) ==="

# F01: lastOutputAt en segundos con sesión ocupada (no idle) debe clasificar trabajando y apagar salir 3
ep_f01_output=$(date -d "2026-11-05 09:55:00" +%s)
export AHORA_EPOCH="$ep_05_1000"
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_f01",
        "agentIdentity": "claude",
        "title": "F01 seconds",
        "recordedPaneKey": "tab_f01:leaf_f01",
        "lastOutputAt": $ep_f01_output,
        "preview": "working"
      }
    ]
  }
}
EOF
: > "$MOCK_STATE/idle_status.txt"
rm -f "$MOCK_STATE/wait_override.json"

set +e
apagar_f01_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_f01_code=$?
set -e

assert_eq "$apagar_f01_code" "3" "F01: timestamp en segundos con agente ocupado apagar.sh sale 3"
if echo "$apagar_f01_out" | grep -q "shutdown"; then
  echo "FAIL: F01: apagar.sh imprimió shutdown con timestamp en segundos" >&2
  failures=$((failures + 1))
else
  echo "PASS: F01: apagar.sh no imprime shutdown con timestamp en segundos"
fi

# F02: handle vacío o con tabs, o agentIdentity con tabs
for bad_term in '{"handle":"","agentIdentity":"claude"}' '{"handle":"term\tx","agentIdentity":"claude"}' '{"handle":"term_x","agentIdentity":"claude\tx"}'; do
  cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      $bad_term
    ]
  }
}
EOF
  set +e
  qt_bad_code=0
  "$SCRIPT_DIR/quien-trabaja.sh" >/dev/null 2>&1 || qt_bad_code=$?
  apagar_bad_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
  apagar_bad_code=$?
  set -e
  if [ "$apagar_bad_code" -ne 0 ] && ! echo "$apagar_bad_out" | grep -q "shutdown"; then
    echo "PASS: F02: terminal malformada $bad_term bloquea shutdown con error"
  else
    echo "FAIL: F02: terminal malformada $bad_term no bloqueó shutdown (code=$apagar_bad_code)" >&2
    failures=$((failures + 1))
  fi
done

# F02b: fila TSV con estado corrupto en apagar.sh
set +e
apagar_bad_tsv_out=$(printf "term_bad\tclaude\tTitulo\testado_invalido\t5\n" | "$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_bad_tsv_code=$?
set -e
if [ "$apagar_bad_tsv_code" -ne 0 ] && ! echo "$apagar_bad_tsv_out" | grep -q "shutdown"; then
  echo "PASS: F02b: estado inválido en TSV hace salir a apagar.sh con error"
else
  echo "FAIL: F02b: estado inválido en TSV no produjo error en apagar.sh (code=$apagar_bad_tsv_code)" >&2
  failures=$((failures + 1))
fi

# F09: wait_out con ok string "false" debe fallar closed (no considerar idle)
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_f09",
        "agentIdentity": "claude",
        "title": "F09 nonboolean ok",
        "recordedPaneKey": "tab_f09:leaf_f09",
        "lastOutputAt": $(( ep_05_1000 * 1000 )),
        "preview": "working"
      }
    ]
  }
}
EOF
echo '{"ok":"false","result":{"wait":{"satisfied":true}}}' > "$MOCK_STATE/wait_override.json"

set +e
apagar_f09_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_f09_code=$?
set -e

if [ "$apagar_f09_code" -ne 0 ] && ! echo "$apagar_f09_out" | grep -q "shutdown"; then
  echo "PASS: F09: ok no booleano no autoriza shutdown"
else
  echo "FAIL: F09: ok no booleano autorizó shutdown (code=$apagar_f09_code)" >&2
  failures=$((failures + 1))
fi
rm -f "$MOCK_STATE/wait_override.json"

# F10: wait timeout con preview de límite pendiente
ep_f10_out=$(date -d "2026-11-05 08:00:00" +%s)
cat << EOF > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_f10",
        "agentIdentity": "claude",
        "title": "F10 timeout",
        "recordedPaneKey": "tab_f10:leaf_f10",
        "lastOutputAt": $(( ep_f10_out * 1000 )),
        "preview": "You've hit your session limit · resets 2pm"
      }
    ]
  }
}
EOF
: > "$MOCK_STATE/idle_status.txt"
set +e
apagar_f10_out=$("$SCRIPT_DIR/apagar.sh" --simulacro 2>&1)
apagar_f10_code=$?
set -e
assert_eq "$apagar_f10_code" "3" "F10: wait timeout preserva aviso pendiente: apagar.sh sale 3"
if echo "$apagar_f10_out" | grep -q "shutdown"; then
  echo "FAIL: F10: apagar.sh imprimió shutdown con wait timeout y aviso pendiente" >&2
  failures=$((failures + 1))
else
  echo "PASS: F10: apagar.sh no imprime shutdown con wait timeout y aviso pendiente"
fi

# F11: inyección de shell en lastOutputAt
cat << 'EOF' > "$MOCK_STATE/terminal_list.json"
{
  "ok": true,
  "result": {
    "terminals": [
      {
        "handle": "term_f11",
        "agentIdentity": "claude",
        "title": "F11 injection",
        "recordedPaneKey": "tab_f11:leaf_f11",
        "lastOutputAt": "now_s[$(printf ARITHMETIC_EXECUTED >&2)0]",
        "preview": "working"
      }
    ]
  }
}
EOF
set +e
f11_stderr=$(mktemp)
"$SCRIPT_DIR/quien-trabaja.sh" 2>"$f11_stderr" >/dev/null
f11_code=$?
set -e
if grep -q "ARITHMETIC_EXECUTED" "$f11_stderr"; then
  echo "FAIL: F11: lastOutputAt ejecutó sustitución de comando en shell" >&2
  failures=$((failures + 1))
else
  echo "PASS: F11: lastOutputAt no ejecutó shell"
fi
if [ "$f11_code" -ne 0 ]; then
  echo "PASS: F11: quien-trabaja.sh sale con error ante lastOutputAt inválido"
else
  echo "FAIL: F11: quien-trabaja.sh salió 0 con lastOutputAt string inválido" >&2
  failures=$((failures + 1))
fi
rm -f "$f11_stderr"

if [[ $failures -eq 0 ]]; then
  echo "TODOS LOS TESTS PASARON EXITOSAMENTE."
  exit 0
else
  echo "$failures TESTS FALLARON." >&2
  exit 1
fi
