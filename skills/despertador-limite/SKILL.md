---
name: despertador-limite
description: Usar en sesiones desatendidas (turno-noche) o cuando la sesión o un worker choca con el límite de tokens (Claude o Codex), para consultar el uso, programar el despertar automático tras el reset con margen y alternar workers.
---

# Despertador por límite de tokens

Gestiona los resets de cuota durante turnos desatendidos usando las herramientas `CronCreate` y `CronDelete` de Claude Code.

## Scripts

- `scripts/uso-claude.sh`: consulta `https://api.anthropic.com/api/oauth/usage` con el token de `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json`. Devuelve JSON con porcentaje y reset local de 5 horas y semanal:
  `{"cinco_horas":{"pct":N,"reset":"<ISO local>"},"semanal":{"pct":N,"reset":"<ISO local>"}}`.
  Sale con 1 y error en stderr si falla.
- `scripts/cron-despertar.sh <hora> [margen_min=12]`: recibe un ISO-8601 o una hora suelta ("2:10 PM", "3am") y devuelve la expresión cron local `M H D Mon *`, redondeando al minuto siguiente y sumando el margen (12 min por defecto). Si la hora suelta ya pasó, programa para el día siguiente.

## Procedimiento

### 1. Arranque del turno
1. Ejecutá `scripts/uso-claude.sh`.
2. Si `semanal.pct` es alto (no deja margen para el turno), avisale al usuario antes de que se vaya.
3. Mientras quede trabajo pendiente, programá dos crons con `CronCreate`. El prompt de los dos nombra la ruta de la ficha, para retomar aunque el contexto se haya compactado:
   - El cron exacto del reset: `cron_expr=$(scripts/cron-despertar.sh "$reset")` (ej. `CronCreate cron: "$cron_expr" prompt: "Despertar: verificar reset de cuota y continuar turno"`).
   - El cron horario de respaldo: `CronCreate cron: "7 * * * *" prompt: "Verificación horaria de respaldo del turno"`.

### 2. Choque de límite en un worker (Codex o Claude)
1. Leé el mensaje en la terminal del worker con `ORCA="${ORCA_CLI_COMMAND:-orca-ide}"`: buscá `"try again at …"` o `"resets …"`.
2. Calculá el cron para su despertar: `scripts/cron-despertar.sh "<hora>"`.
3. Pasá la tarea al otro worker disponible.
4. Programá un `CronCreate` para el reset del primer worker: cuando recupere cuota, pedile que revise lo hecho por el segundo (los modelos cruzados aportan perspectivas complementarias).
5. Si no hay otro worker disponible, esperá al reset.

### 3. Al despertar
1. Leé la ficha del turno y el estado actual de tareas y ramas.
2. Si la cuota ya se recuperó, continuá con el trabajo pendiente.
3. Rearmá el cron de una vez para el próximo reset con `scripts/uso-claude.sh` y `scripts/cron-despertar.sh`.

### 4. Cierre del turno
- Al finalizar todo el trabajo del turno, eliminá los crons activos con `CronDelete`.

## Reglas
- Para invocar Orca desde comandos o scripts, usá siempre `ORCA="${ORCA_CLI_COMMAND:-orca-ide}"`, nunca `orca` a secas (en GNOME es el lector de pantalla).
- No uses timers de systemd ni hooks; Claude Code gestiona los despertares con sus crons mientras la sesión permanezca abierta.
- Mantené siempre activo el cron de respaldo `7 * * * *` mientras haya trabajo pendiente, para recuperarte si falla la red o la API de uso al momento del reset.
