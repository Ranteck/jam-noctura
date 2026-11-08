#!/usr/bin/env bash
set -euo pipefail

clasificar() {
  local idle="$1"
  local min_sin_salida="$2"
  local preview="${3:-}"
  local ultima_salida="${4:-0}"
  local ahora="${5:-$(date +%s)}"

  # a. idle=no → trabado si min_sin_salida >= 60, si no trabajando (el mensaje de límite no importa si la TUI está ocupada).
  if [[ "$idle" == "no" ]]; then
    if (( min_sin_salida >= 60 )); then
      echo "trabado"
    else
      echo "trabajando"
    fi
    return 0
  fi

  # b. idle=si y el preview tiene una frase de límite (sin distinguir mayúsculas: try again at, limit reached, hit your limit, hit your usage limit)
  local lower_preview
  lower_preview=$(tr "[:upper:]" "[:lower:]" <<< "$preview" | tr '\r\n\t' ' ' | tr -s ' ')

  local has_limit_phrase=0
  for phrase in "try again at" "limit reached" "hit your limit" "hit your usage limit"; do
    if [[ "$lower_preview" == *"$phrase"* ]]; then
      has_limit_phrase=1
      break
    fi
  done

  if [[ $has_limit_phrase -eq 1 ]]; then
    local months="jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december"
    local time_pattern="(try again at|resets at|reset at|resets)[ :·•\t]*((($months))[ ]+([0-9]{1,2})(st|nd|rd|th)?([,]?[ ]*([0-9]{4}))?[,]?[ ]+)?([0-9]{1,2}(:[0-9]{2})?([ ]*(am|pm))?|[0-9]{1,2}:[0-9]{2})"

    local search_text="$lower_preview"
    if [[ "$lower_preview" == *"try again at"* ]]; then
      search_text="try again at${lower_preview##*try again at}"
    fi

    local reset_epoch=""
    if [[ "$search_text" =~ $time_pattern ]]; then
      local month="${BASH_REMATCH[3]}"
      local day="${BASH_REMATCH[5]}"
      local year="${BASH_REMATCH[8]}"
      local hora="${BASH_REMATCH[9]}"

      if [[ -n "$month" && -n "$day" ]]; then
        # Con fecha: reset = esa fecha y hora (año de ultima_salida; si queda antes de ultima_salida, año siguiente).
        # Si viene año opcional, se usa ese.
        if [[ -n "$year" ]]; then
          reset_epoch=$(date -d "$month $day $year $hora" +%s 2>/dev/null || true)
        elif [[ "$ultima_salida" -gt 0 ]]; then
          local year_salida
          year_salida=$(date -d "@$ultima_salida" +%Y 2>/dev/null || true)
          if [[ -n "$year_salida" ]]; then
            reset_epoch=$(date -d "$month $day $year_salida $hora" +%s 2>/dev/null || true)
            if [[ -n "$reset_epoch" ]] && (( reset_epoch < ultima_salida )); then
              reset_epoch=$(date -d "$month $day $((year_salida + 1)) $hora" +%s 2>/dev/null || true)
            fi
          fi
        fi
      elif [[ -n "$hora" && "$ultima_salida" -gt 0 ]]; then
        # Sin fecha: comportamiento actual (día de ultima_salida, +1 día si queda <=).
        local date_salida
        date_salida=$(date -d "@$ultima_salida" +%Y-%m-%d 2>/dev/null || true)
        if [[ -n "$date_salida" ]]; then
          reset_epoch=$(date -d "$date_salida $hora" +%s 2>/dev/null || true)
          if [[ -n "$reset_epoch" ]] && (( reset_epoch <= ultima_salida )); then
            reset_epoch=$(( reset_epoch + 86400 ))
          fi
        fi
      fi
    fi

    # Si no se puede leer la hora, reset = ultima_salida + 5 h.
    if [[ -z "$reset_epoch" ]]; then
      reset_epoch=$(( ultima_salida + 5 * 3600 ))
    fi

    # esperando-reset si ahora < reset + 15 min; si no, libre (ya debería haber vuelto: nadie lo va a retomar).
    if (( ahora < reset_epoch + 15 * 60 )); then
      echo "esperando-reset"
    else
      echo "libre"
    fi
    return 0
  fi

  # c. idle=si sin frase de límite → libre.
  echo "libre"
}

main() {
  local ORCA="${ORCA_CLI_COMMAND:-orca-ide}"
  local now_s="${AHORA_EPOCH:-$(date +%s)}"
  local my_pane="${ORCA_PANE_KEY:-}"

  local raw_json
  if ! raw_json=$("$ORCA" terminal list --json 2>/dev/null); then
    echo "Error: no se pudo obtener la lista de terminales de Orca" >&2
    exit 1
  fi

  if ! echo "$raw_json" | jq -e '.ok == true and (.result.terminals | type == "array")' >/dev/null 2>&1; then
    echo "Error: respuesta inválida de Orca terminal list (se esperaba ok==true y result.terminals array)" >&2
    exit 1
  fi

  local terminals
  terminals=$(echo "$raw_json" | jq -c --arg my_pane "$my_pane" '
    .result.terminals[]? // empty
    | select(.agentIdentity != null and .agentIdentity != "")
    | select($my_pane == "" or ((.recordedPaneKey // "\(.tabId // ""):\(.leafId // "")") != $my_pane and (.recordedPaneKey // "") != $my_pane))
  ')

  if [[ -z "$terminals" ]]; then
    return 0
  fi

  while IFS= read -r term; do
    [[ -z "$term" ]] && continue
    local handle agente titulo last_output_ms preview min_sin_salida idle wait_out estado clean_titulo last_output_s

    handle=$(jq -r '.handle' <<< "$term")
    agente=$(jq -r '.agentIdentity' <<< "$term")
    titulo=$(jq -r '.title // ""' <<< "$term")
    last_output_ms=$(jq -r '.lastOutputAt // 0' <<< "$term")
    preview=$(jq -r '.preview // ""' <<< "$term")

    if (( last_output_ms > 0 )); then
      last_output_s=$(( last_output_ms / 1000 ))
      local diff_s=$(( now_s - last_output_s ))
      if (( diff_s < 0 )); then diff_s=0; fi
      min_sin_salida=$(( diff_s / 60 ))
    else
      last_output_s=0
      min_sin_salida=0
    fi

    idle="no"
    wait_out=$("$ORCA" terminal wait --terminal "$handle" --for tui-idle --timeout-ms 2000 --json 2>/dev/null || true)
    if [[ -n "$wait_out" ]] && echo "$wait_out" | jq -e '.ok and .result.wait.satisfied == true' >/dev/null 2>&1; then
      idle="si"
    fi

    estado=$(clasificar "$idle" "$min_sin_salida" "$preview" "$last_output_s" "$now_s")
    clean_titulo="${titulo//$'\t'/ }"
    clean_titulo="${clean_titulo//$'\r'/}"
    clean_titulo="${clean_titulo//$'\n'/ }"
    [[ -z "$clean_titulo" ]] && clean_titulo="-"

    printf "%s\t%s\t%s\t%s\t%s\n" "$handle" "$agente" "$clean_titulo" "$estado" "$min_sin_salida"
  done <<< "$terminals"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
