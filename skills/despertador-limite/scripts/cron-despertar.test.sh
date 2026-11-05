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

# 4. Hora suelta que ya pasó ("3am" desde las 09:00) con margen 15 -> mañana 03:15
salida=$(AHORA_EPOCH="$EPOCH_0900" "$CRON_DESPERTAR" "3am" 15)
assert_eq "hora suelta pasada '3am' con margen 15 -> 15 3 6 11 *" "15 3 6 11 *" "$salida"

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

echo "Todos los tests de cron-despertar y uso-claude pasaron correctamente."
