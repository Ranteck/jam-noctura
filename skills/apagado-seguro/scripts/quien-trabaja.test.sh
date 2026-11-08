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

if [[ $failures -eq 0 ]]; then
  echo "TODOS LOS TESTS PASARON EXITOSAMENTE."
  exit 0
else
  echo "$failures TESTS FALLARON." >&2
  exit 1
fi
