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

if [[ "$hora_input" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
    if ! epoch=$(date -d "$hora_input" +%s 2>/dev/null); then
        echo "Error: formato de fecha/hora inválido: $hora_input" >&2
        exit 1
    fi
    sec=$(date -d "$hora_input" +%S 2>/dev/null)
    nsec=$(date -d "$hora_input" +%N 2>/dev/null)
else
    today_date=$(date -d "@$now_epoch" +%Y-%m-%d 2>/dev/null)
    if ! epoch=$(date -d "$today_date $hora_input" +%s 2>/dev/null); then
        echo "Error: formato de hora inválido: $hora_input" >&2
        exit 1
    fi
    sec=$(date -d "$today_date $hora_input" +%S 2>/dev/null)
    nsec=$(date -d "$today_date $hora_input" +%N 2>/dev/null)

    # Si la hora suelta ya pasó hoy, programar para el día siguiente
    if [ "$epoch" -le "$now_epoch" ]; then
        epoch=$(date -d "$today_date $hora_input + 1 day" +%s 2>/dev/null)
        sec=$(date -d "$today_date $hora_input + 1 day" +%S 2>/dev/null)
        nsec=$(date -d "$today_date $hora_input + 1 day" +%N 2>/dev/null)
    fi
fi

# Redondear al minuto siguiente si hay segundos o submilisegundos
if [ "$((10#$sec))" -gt 0 ] || [[ "$nsec" =~ [1-9] ]]; then
    epoch=$(( (epoch / 60 + 1) * 60 ))
fi

# Sumar margen en minutos
epoch=$(( epoch + margen_min * 60 ))

# Salida en formato cron local: M H D Mon *
date -d "@$epoch" +"%-M %-H %-d %-m *"
