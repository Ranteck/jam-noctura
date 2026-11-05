#!/usr/bin/env bash
set -euo pipefail

simulacro=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simulacro)
      simulacro=1
      shift
      ;;
    *)
      echo "Uso: apagar.sh [--simulacro]" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lineas=$("$SCRIPT_DIR/quien-trabaja.sh")

no_libres=""
hay_bloqueo=0

if [[ -n "$lineas" ]]; then
  while IFS=$'\t' read -r handle agente titulo estado min_sin_salida; do
    [[ -z "$handle" ]] && continue
    if [[ "$estado" != "libre" ]]; then
      no_libres+="${handle}"$'\t'"${agente}"$'\t'"${titulo}"$'\t'"${estado}"$'\t'"${min_sin_salida}"$'\n'
    fi
    if [[ "$estado" == "trabajando" || "$estado" == "esperando-reset" ]]; then
      hay_bloqueo=1
    fi
  done <<< "$lineas"
fi

if [[ -n "$no_libres" ]]; then
  printf "%s\n" "${no_libres%$'\n'}"
fi

if [[ $hay_bloqueo -eq 1 ]]; then
  exit 3
fi

if [[ $simulacro -eq 1 ]]; then
  echo 'shutdown -P +5 "turno-noche: apagado en 5 min. Cancelar: shutdown -c"'
  exit 0
fi

if ! shutdown -P +5 "turno-noche: apagado en 5 min. Cancelar: shutdown -c"; then
  echo "Error al ejecutar: shutdown -P +5 \"turno-noche: apagado en 5 min. Cancelar: shutdown -c\"" >&2
  exit 1
fi

exit 0
