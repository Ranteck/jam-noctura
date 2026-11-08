#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_DESPERTAR="$SCRIPT_DIR/cron-despertar.sh"
USO_CLAUDE="$SCRIPT_DIR/uso-claude.sh"

export TZ="America/Argentina/Buenos_Aires"

EPOCH_0900=$(TZ="$TZ" date -d "2026-11-05 09:00:00" +%s)
EPOCH_1500=$(TZ="$TZ" date -d "2026-11-05 15:00:00" +%s)

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL [$label]: esperado '$expected', obtenido '$actual'" >&2
        exit 1
    fi
    echo "OK [$label]: '$actual'"
}

# 1. Reset UTC con milisegundos -> hora local redondeada + 12 min de margen
salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "2026-11-05T16:39:59.600446+00:00")
assert_eq "reset UTC 16:39:59 -> 52 13 5 11 *" "52 13 5 11 *" "$salida"

# 2. Hora suelta de hoy que no pasó ("2:10 PM" desde las 09:00) -> hoy 14:22
salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "2:10 PM")
assert_eq "hora suelta hoy '2:10 PM' -> 22 14 5 11 *" "22 14 5 11 *" "$salida"

# 3. Hora suelta que ya pasó hoy ("2:10 PM" desde las 15:00) -> mañana 14:22
salida=$(AHORA_EPOCH="$EPOCH_1500" "$CRON_DESPERTAR" "2:10 PM")
assert_eq "hora suelta pasada '2:10 PM' -> 22 14 6 11 *" "22 14 6 11 *" "$salida"

# R04: cron-despertar.sh compara la hora de despertar (epoch + margen) contra ahora antes de pasar a mañana
EPOCH_1412=$(TZ="$TZ" date -d "2026-11-05 14:12:00" +%s)
salida=$(AHORA_EPOCH="$EPOCH_1412" "$CRON_DESPERTAR" "2:10 PM")
assert_eq "R04: despertar con margen hoy (14:12 para 14:22) -> 22 14 5 11 *" "22 14 5 11 *" "$salida"

# F03: Hora suelta en formato 24h que ya pasó ("14:10" desde las 15:00) -> mañana 14:22
salida=$(AHORA_EPOCH="$EPOCH_1500" "$CRON_DESPERTAR" "14:10")
assert_eq "F03: hora suelta pasada 24h '14:10' -> 22 14 6 11 *" "22 14 6 11 *" "$salida"

# R05: fechas de avisos semanales ('Oct 28 5am', 'Nov 12, 2:10 PM', 'Nov 12th, 2026 4:50 PM')
salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "Oct 28 5am")
assert_eq "R05: aviso semanal 'Oct 28 5am' -> 12 5 28 10 *" "12 5 28 10 *" "$salida"

salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "Nov 12, 2:10 PM")
assert_eq "R05: aviso semanal 'Nov 12, 2:10 PM' -> 22 14 12 11 *" "22 14 12 11 *" "$salida"

salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "Nov 12th, 2026 4:50 PM")
assert_eq "R05: aviso semanal 'Nov 12th, 2026 4:50 PM' -> 2 17 12 11 *" "2 17 12 11 *" "$salida"

# 4. Hora suelta que ya pasó ("3am" desde las 09:00) con margen 15 -> mañana 03:15
salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "3am" 15)
assert_eq "hora suelta pasada '3am' con margen 15 -> 15 3 6 11 *" "15 3 6 11 *" "$salida"

# F07: Margen con cero a la izquierda ("08") debe tratarse en base decimal (14:10 + 8 min -> 14:18)
salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "14:10" "08")
assert_eq "F07: margen con cero '08' -> 18 14 5 11 *" "18 14 5 11 *" "$salida"

# 5. uso-claude.sh sin credenciales sale con 1 y emite mensaje a stderr
empty_dir=$(mktemp -d)
trap 'rm -rf "$empty_dir"' EXIT

stderr_output=$(mktemp)
trap 'rm -rf "$empty_dir" "$stderr_output"' EXIT

set +e
CLAUDE_CONFIG_DIR="$empty_dir" "$USO_CLAUDE" >/dev/null 2>"$stderr_output"
exit_code=$?
set -e

if [ "$exit_code" -ne 1 ]; then
    echo "FAIL [uso-claude sin credenciales]: esperado exit code 1, obtenido $exit_code" >&2
    exit 1
fi

if [ ! -s "$stderr_output" ]; then
    echo "FAIL [uso-claude sin credenciales]: se esperaba mensaje de error en stderr" >&2
    exit 1
fi
echo "OK [uso-claude sin credenciales]: exit code 1 y error en stderr ('$(cat "$stderr_output")')"

# F08: Validación de respuesta de API en uso-claude.sh
test_mock_dir=$(mktemp -d)
trap 'rm -rf "$empty_dir" "$stderr_output" "$test_mock_dir"' EXIT

mkdir -p "$test_mock_dir/bin" "$test_mock_dir/creds"
cat << 'EOF' > "$test_mock_dir/bin/curl"
#!/bin/bash
cat >/dev/null
cat "$TEST_API_RESPONSE"
EOF
chmod +x "$test_mock_dir/bin/curl"
echo '{"claudeAiOauth":{"accessToken":"TEST_TOKEN"}}' > "$test_mock_dir/creds/.credentials.json"

for invalid_payload in \
  '{"five_hour":{"utilization":-1,"resets_at":"2026-11-05T16:00:00Z"},"seven_day":{"utilization":30,"resets_at":"2026-11-12T16:00:00Z"}}' \
  '{"five_hour":{"utilization":200,"resets_at":"2026-11-05T16:00:00Z"},"seven_day":{"utilization":30,"resets_at":"2026-11-12T16:00:00Z"}}' \
  '{"five_hour":{"utilization":"bad","resets_at":"2026-11-05T16:00:00Z"},"seven_day":{"utilization":30,"resets_at":"2026-11-12T16:00:00Z"}}' \
  '{"five_hour":{"utilization":50,"resets_at":"tomorrow"},"seven_day":{"utilization":30,"resets_at":"2026-11-12T16:00:00Z"}}' \
  '{"five_hour":{"utilization":50,"resets_at":"2026-11-05"},"seven_day":{"utilization":30,"resets_at":"2026-11-12T16:00:00Z"}}' \
  '{"five_hour":{"utilization":20,"resets_at":"2026-11-05T16:00 +2 days"},"seven_day":{"utilization":0,"resets_at":null}}'; do
  echo "$invalid_payload" > "$test_mock_dir/resp.json"
  set +e
  out=$(PATH="$test_mock_dir/bin:$PATH" CLAUDE_CONFIG_DIR="$test_mock_dir/creds" TEST_API_RESPONSE="$test_mock_dir/resp.json" "$USO_CLAUDE" 2>&1)
  code=$?
  set -e
  if [ "$code" -eq 0 ]; then
    echo "FAIL [F08 api validation]: se esperaba error para $invalid_payload pero salió 0 con: $out" >&2
    exit 1
  fi
done
echo "OK [F08 api validation]: todas las respuestas corruptas de la API fueron rechazadas con error"

# R01: uso-claude.sh acepta resets_at null cuando utilization es 0
cat << 'EOF' > "$test_mock_dir/resp_null.json"
{
  "five_hour": {"utilization": 0.0, "resets_at": null},
  "seven_day": {"utilization": 30.0, "resets_at": "2026-11-12T16:00:00Z"}
}
EOF
out_null=$(PATH="$test_mock_dir/bin:$PATH" CLAUDE_CONFIG_DIR="$test_mock_dir/creds" TEST_API_RESPONSE="$test_mock_dir/resp_null.json" "$USO_CLAUDE")
assert_eq "R01: five_hour.pct es 0" "0" "$(echo "$out_null" | jq -r '.cinco_horas.pct')"
assert_eq "R01: five_hour.reset es null" "null" "$(echo "$out_null" | jq -r '.cinco_horas.reset')"

# N04: validación estricta de rango para margen_min (0..1440)
for bad_margin in "18446744073709551616" "1441" "-1" "abc"; do
  set +e
  out_bad_margin=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "14:10" "$bad_margin" 2>&1)
  code_bad_margin=$?
  set -e
  if [ "$code_bad_margin" -eq 0 ]; then
    echo "FAIL [N04 margen_min range]: se esperaba error para margen '$bad_margin' pero salió 0" >&2
    exit 1
  fi
done
echo "OK [N04 margen_min range]: márgenes inválidos o desbordados rechazados con error"

echo "Todos los tests de cron-despertar y uso-claude pasaron correctamente."
