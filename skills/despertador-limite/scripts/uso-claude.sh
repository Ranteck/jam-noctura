#!/bin/bash
set -euo pipefail

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
creds_file="${config_dir}/.credentials.json"

if [ ! -f "$creds_file" ]; then
    echo "Error: no existe el archivo de credenciales en $creds_file" >&2
    exit 1
fi

token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null || true)
if [ -z "$token" ]; then
    echo "Error: no se encontró accessToken en $creds_file" >&2
    exit 1
fi

# El token va por stdin para que no quede en argv (visible en /proc/*/cmdline).
if ! response=$(printf 'Authorization: Bearer %s\n' "$token" | curl -sS --fail --max-time 10 \
    -H @- \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.1.34" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null); then
    echo "Error: falló la consulta a la API de uso de Anthropic" >&2
    exit 1
fi

if ! echo "$response" | jq -e '
  (.five_hour | type == "object") and
  (.seven_day | type == "object") and
  (.five_hour.utilization | (type == "number" and . >= 0 and . <= 100)) and
  (.seven_day.utilization | (type == "number" and . >= 0 and . <= 100)) and
  (.five_hour.resets_at | (. == null or (type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\\.[0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?$")))) and
  (.seven_day.resets_at | (. == null or (type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\\.[0-9]+)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?$"))))
' >/dev/null 2>&1; then
    echo "Error: respuesta inválida o sin datos válidos de rate limit de Anthropic" >&2
    exit 1
fi

five_hour_util=$(echo "$response" | jq -r '.five_hour.utilization')
five_hour_reset_utc=$(echo "$response" | jq -r '.five_hour.resets_at')
seven_day_util=$(echo "$response" | jq -r '.seven_day.utilization')
seven_day_reset_utc=$(echo "$response" | jq -r '.seven_day.resets_at')

if [ "$five_hour_util" = "null" ] || [ -z "$five_hour_util" ] || [ "$seven_day_util" = "null" ] || [ -z "$seven_day_util" ]; then
    echo "Error: datos incompletos en la respuesta de uso de Anthropic" >&2
    exit 1
fi

if [ "$five_hour_reset_utc" = "null" ]; then
    five_hour_reset_local=null
else
    if ! five_hour_reset_local_str=$(date -d "$five_hour_reset_utc" --iso-8601=seconds 2>/dev/null); then
        echo "Error: formato de fecha inválido en five_hour.resets_at: $five_hour_reset_utc" >&2
        exit 1
    fi
    five_hour_reset_local=$(printf '"%s"' "$five_hour_reset_local_str")
fi

if [ "$seven_day_reset_utc" = "null" ]; then
    seven_day_reset_local=null
else
    if ! seven_day_reset_local_str=$(date -d "$seven_day_reset_utc" --iso-8601=seconds 2>/dev/null); then
        echo "Error: formato de fecha inválido en seven_day.resets_at: $seven_day_reset_utc" >&2
        exit 1
    fi
    seven_day_reset_local=$(printf '"%s"' "$seven_day_reset_local_str")
fi

five_pct=$(echo "$five_hour_util" | jq 'round')
sev_pct=$(echo "$seven_day_util" | jq 'round')

jq -n \
    --argjson five_pct "$five_pct" \
    --argjson five_reset "$five_hour_reset_local" \
    --argjson sev_pct "$sev_pct" \
    --argjson sev_reset "$seven_day_reset_local" \
    '{
        cinco_horas: {
            pct: $five_pct,
            reset: $five_reset
        },
        semanal: {
            pct: $sev_pct,
            reset: $sev_reset
        }
    }'
