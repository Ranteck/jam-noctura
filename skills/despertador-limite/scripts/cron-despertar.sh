#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Uso: $(basename "$0") <hora> [margen_min=12]" >&2
    exit 1
fi

hora_input="$1"
margen_min="${2:-12}"

if ! [[ "$margen_min" =~ ^[0-9]+$ ]]; then
    echo "Error: margen_min debe ser un número entero mayor o igual a 0: $margen_min" >&2
    exit 1
fi

now_epoch="${AHORA_EPOCH:-$(date +%s)}"
year_now=$(date -d "@$now_epoch" +%Y 2>/dev/null)

# Quitar ordinales (1st, 2nd, 3rd, 4th), comas y ' at '
cleaned=$(sed -E 's/([0-9]{1,2})(st|nd|rd|th)/\1/g; s/,/ /g; s/[[:space:]]+at[[:space:]]+/ /g' <<< "$hora_input")
cleaned=$(echo "$cleaned" | tr -s ' ')

months="jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december"

es_fecha=0
if [[ "$cleaned" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]] || [[ "${cleaned,,}" =~ ($months) ]]; then
    es_fecha=1
fi

if [ "$es_fecha" -eq 1 ]; then
    candidate="$cleaned"
    if ! [[ "$candidate" =~ [0-9]{4} ]]; then
        candidate="$candidate $year_now"
    fi
    if ! epoch=$(date -d "$candidate" +%s 2>/dev/null); then
        echo "Error: formato de fecha/hora inválido: $hora_input" >&2
        exit 1
    fi
    sec=$(date -d "$candidate" +%S 2>/dev/null)
    nsec=$(date -d "$candidate" +%N 2>/dev/null)

    # Redondear al minuto siguiente si hay segundos o submilisegundos
    if [ "$((10#$sec))" -gt 0 ] || [[ "$nsec" =~ [1-9] ]]; then
        epoch=$(( (epoch / 60 + 1) * 60 ))
    fi
    epoch=$(( epoch + 10#$margen_min * 60 ))
else
    today_date=$(date -d "@$now_epoch" +%Y-%m-%d 2>/dev/null)
    if ! epoch=$(date -d "$today_date $cleaned" +%s 2>/dev/null); then
        echo "Error: formato de hora inválido: $hora_input" >&2
        exit 1
    fi
    sec=$(date -d "$today_date $cleaned" +%S 2>/dev/null)
    nsec=$(date -d "$today_date $cleaned" +%N 2>/dev/null)

    despertar="$epoch"
    if [ "$((10#$sec))" -gt 0 ] || [[ "$nsec" =~ [1-9] ]]; then
        despertar=$(( (despertar / 60 + 1) * 60 ))
    fi
    despertar=$(( despertar + 10#$margen_min * 60 ))

    # Si la hora de despertar ya pasó hoy, programar para el día siguiente
    if [ "$despertar" -le "$now_epoch" ]; then
        tomorrow_date=$(date -d "$today_date + 1 day" +%Y-%m-%d 2>/dev/null)
        epoch=$(date -d "$tomorrow_date $cleaned" +%s 2>/dev/null)
        sec=$(date -d "$tomorrow_date $cleaned" +%S 2>/dev/null)
        nsec=$(date -d "$tomorrow_date $cleaned" +%N 2>/dev/null)
        if [ "$((10#$sec))" -gt 0 ] || [[ "$nsec" =~ [1-9] ]]; then
            epoch=$(( (epoch / 60 + 1) * 60 ))
        fi
        epoch=$(( epoch + 10#$margen_min * 60 ))
    else
        epoch="$despertar"
    fi
fi

# Salida en formato cron local: M H D Mon *
date -d "@$epoch" +"%-M %-H %-d %-m *"
