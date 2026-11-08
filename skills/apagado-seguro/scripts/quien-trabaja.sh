#!/usr/bin/env bash
set -euo pipefail

_date_with_tz() {
  local tz="${1:-}"
  shift
  if [[ -n "$tz" ]]; then
    TZ="$tz" date "$@"
  else
    date "$@"
  fi
}

clasificar() {
  local idle="$1"
  local min_sin_salida="$2"
  local preview="${3:-}"
  local ultima_salida="${4:-0}"
  local ahora="${5:-$(date +%s)}"

  local norm_preview
  norm_preview=$(printf '%s' "$preview" | tr '\r\n\t' ' ' | tr -s ' ')
  local lower_preview
  lower_preview=$(tr "[:upper:]" "[:lower:]" <<< "$norm_preview")

  local tail=""
  local raw_tail=""
  local raw_prefix=""
  local prefix_40=""
  local limit_pattern="(.*)(try again at|limit reached|hit your ([a-z0-9-]+ )?limit)"
  if [[ "$lower_preview" =~ $limit_pattern ]]; then
    local prefix="${BASH_REMATCH[1]}"
    tail="${lower_preview:${#prefix}}"
    raw_tail="${norm_preview:${#prefix}}"
    raw_prefix="${norm_preview:0:${#prefix}}"
    prefix_40="${raw_prefix: ( ${#raw_prefix} > 40 ? ${#raw_prefix} - 40 : 0 )}"
  fi

  if [[ -n "$tail" ]]; then
    local after_anchor=""
    local anchor_len=0
    if [[ "$tail" == "try again at"* ]]; then
      after_anchor="${tail#try again at}"
      anchor_len=$(( ${#tail} - ${#after_anchor} ))
    else
      local first50="${tail:0:50}"
      if [[ "$first50" =~ (resets at|reset at|resets) ]]; then
        local kw="${BASH_REMATCH[1]}"
        local pre="${first50%%"$kw"*}"
        anchor_len=$(( ${#pre} + ${#kw} ))
        after_anchor="${tail:anchor_len}"
      fi
    fi

    local months="jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december"
    local date_time_pattern="^[ :·•\t,.:-]*((($months))[ ]+([0-9]{1,2})(st|nd|rd|th)?([,]?[ ]+([0-9]{4}))?([,]?[ ]*(at)?[ ]+))?([0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[ ]*(am|pm)|[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?|[0-9]{1,2}[ ]*(am|pm))([^0-9a-zA-Z]|$)"

    local notice_tz=""
    local raw_after_anchor="${raw_tail:anchor_len}"
    local raw_tail_window="$raw_tail"
    if [[ -n "$after_anchor" && "$after_anchor" =~ $date_time_pattern ]]; then
      local matched_len=${#BASH_REMATCH[0]}
      local last_char="${after_anchor:matched_len-1:1}"
      local dt_end=$matched_len
      local rest=""
      if [[ "$last_char" == "(" ]]; then
        dt_end=$(( matched_len - 1 ))
        rest="${raw_after_anchor:dt_end}"
      else
        rest="${raw_after_anchor:dt_end}"
      fi
      local rx="^[ ]*\\([^)]+\\)"
      local paren=""
      if [[ "$rest" =~ $rx ]]; then
        paren="${BASH_REMATCH[0]}"
      fi
      local window="${raw_after_anchor:0:$(( dt_end + ${#paren} ))}"
      raw_tail_window="${raw_tail:0:$anchor_len}${window}"
    fi

    local tz_rx="\(([A-Za-z_]+/[A-Za-z0-9_/-]+)\)"
    if [[ "$raw_tail_window" =~ $tz_rx ]]; then
      notice_tz="${BASH_REMATCH[1]}"
    elif [[ "$prefix_40" =~ $tz_rx ]]; then
      notice_tz="${BASH_REMATCH[1]}"
    fi

    local base="$ultima_salida"
    if (( base <= 0 )); then
      base="$ahora"
    fi

    local reset_epoch=""
    if [[ -n "$after_anchor" && "$after_anchor" =~ $date_time_pattern ]]; then
      local month="${BASH_REMATCH[3]}"
      local day="${BASH_REMATCH[4]}"
      local year="${BASH_REMATCH[7]}"
      local hora="${BASH_REMATCH[10]}"

      if [[ -n "$month" && -n "$day" ]]; then
        if [[ -n "$year" ]]; then
          reset_epoch=$(_date_with_tz "$notice_tz" -d "$month $day $year $hora" +%s 2>/dev/null || true)
        else
          local year_base
          year_base=$(_date_with_tz "$notice_tz" -d "@$base" +%Y 2>/dev/null || true)
          if [[ -n "$year_base" ]]; then
            reset_epoch=$(_date_with_tz "$notice_tz" -d "$month $day $year_base $hora" +%s 2>/dev/null || true)
            if [[ -n "$reset_epoch" ]] && (( reset_epoch < base )); then
              reset_epoch=$(_date_with_tz "$notice_tz" -d "$month $day $((year_base + 1)) $hora" +%s 2>/dev/null || true)
            fi
          fi
        fi
      elif [[ -n "$hora" ]]; then
        local cur_date next_date
        cur_date=$(_date_with_tz "$notice_tz" -d "@$base" +%Y-%m-%d 2>/dev/null || true)
        next_date=$(_date_with_tz "$notice_tz" -d "$cur_date + 1 day" +%Y-%m-%d 2>/dev/null || true)
        if [[ -n "$cur_date" ]]; then
          local reset_today reset_tomorrow
          reset_today=$(_date_with_tz "$notice_tz" -d "$cur_date $hora" +%s 2>/dev/null || true)
          reset_tomorrow=$(_date_with_tz "$notice_tz" -d "$next_date $hora" +%s 2>/dev/null || true)
          if [[ -n "$reset_today" && -n "$reset_tomorrow" ]]; then
            if (( ultima_salida > 0 )); then
              if (( reset_today > base )); then
                reset_epoch="$reset_today"
              else
                reset_epoch="$reset_tomorrow"
              fi
            else
              # con ultima_salida=0 y hora sin fecha: elegir la ocurrencia más cercana a ahora
              local dist_today dist_tomorrow
              dist_today=$(( ahora >= reset_today ? ahora - reset_today : reset_today - ahora ))
              dist_tomorrow=$(( ahora >= reset_tomorrow ? ahora - reset_tomorrow : reset_tomorrow - ahora ))
              if (( dist_tomorrow < dist_today )); then
                reset_epoch="$reset_tomorrow"
              else
                reset_epoch="$reset_today"
              fi
            fi
          elif [[ -n "$reset_today" ]]; then
            reset_epoch="$reset_today"
          fi
        fi
      fi
    fi

    # Si no se puede leer la hora, fallback = base + 5 h.
    if [[ -z "$reset_epoch" ]]; then
      reset_epoch=$(( base + 5 * 3600 ))
    fi

    # Si hay aviso de límite pendiente (ahora < reset + 15 min), esperando-reset manda
    if (( ahora < reset_epoch + 15 * 60 )); then
      echo "esperando-reset"
      return 0
    fi
  fi

  # a. idle=no → trabado si min_sin_salida >= 60, si no trabajando.
  if [[ "$idle" == "no" ]]; then
    if (( min_sin_salida >= 60 )); then
      echo "trabado"
    else
      echo "trabajando"
    fi
    return 0
  fi

  # c. idle=si y sin aviso de límite pendiente → libre.
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

    # F02: handle y agentIdentity no vacíos y sin caracteres de control
    if ! echo "$term" | jq -e '
      (.handle | (type == "string" and length > 0 and (test("[\\x00-\\x1f]") | not))) and
      (.agentIdentity | (type == "string" and length > 0 and (test("[\\x00-\\x1f]") | not)))
    ' >/dev/null 2>&1; then
      echo "Error: terminal con handle o agentIdentity inválido o con caracteres de control" >&2
      exit 1
    fi

    # F11, F01: lastOutputAt solo entero JSON dentro de rango razonable
    if ! echo "$term" | jq -e '
      .lastOutputAt == null or
      (.lastOutputAt | (type == "number" and . >= 0 and . <= 10000000000000 and . == floor))
    ' >/dev/null 2>&1; then
      echo "Error: lastOutputAt inválido (debe ser número entero positivo)" >&2
      exit 1
    fi

    handle=$(jq -r '.handle' <<< "$term")
    agente=$(jq -r '.agentIdentity' <<< "$term")
    titulo=$(jq -r '.title // ""' <<< "$term")
    last_output_ms=$(jq -r '.lastOutputAt // 0' <<< "$term")
    preview=$(jq -r '.preview // ""' <<< "$term")

    # F01: si lastOutputAt vino en segundos (entre 1e9 y 1e11), normalizar a ms
    if (( last_output_ms > 0 && last_output_ms < 100000000000 )); then
      last_output_ms=$(( last_output_ms * 1000 ))
    fi

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
    if [[ -n "$wait_out" ]] && echo "$wait_out" | jq -e '.ok == true and .result.wait.satisfied == true' >/dev/null 2>&1; then
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
