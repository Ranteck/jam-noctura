---
name: apagado-seguro
description: Usar cuando se necesita apagar la máquina de forma segura y verificar que ninguna otra sesión o worker siga activo antes del shutdown.
---

# Apagado seguro de la máquina

Comprueba el estado de todas las terminales con agentes en Orca antes de apagar la PC, asegurando que nadie pierda trabajo no guardado ni quede una tarea a medias.

## Condiciones previas

Antes de invocar esta skill:
1. Asegurá que tu propio trabajo esté guardado y tus workers propios cerrados.
2. Si venís de un turno desatendido de `turno-noche`: tu trabajo debe estar commiteado en la rama del turno (sin push ni merge) y el informe escrito en `~/Documentos/turno-noche/<AAAA-MM-DD>-<proyecto>.md`.
3. No debe haber corridas pagas en curso.

## Pasos

1. **Avisar a las sesiones paralelas:**
   - Avisá solo por `SendMessage` a las sesiones de Claude que puedan recibir mensajes, informando que el turno terminó y que la máquina se va a apagar si están libres. Si no hay ninguna sesión de Claude que reciba mensajes, no se avisa (nunca escribas en la terminal ajena).

2. **Ejecutar el chequeo y apagado:**
   - Corré `bash scripts/apagar.sh` (o `~/.claude/skills/apagado-seguro/scripts/apagar.sh`, agregando `--simulacro` si estás probando o se pidió no apagar físicamente).

3. **Interpretar el resultado:**
   - `apagar.sh` imprime en TSV todas las terminales que no están libres (`trabajando`, `esperando-reset`, `trabado`).
   - **Salida 0 (éxito):** No hay terminales bloqueantes (`trabajando` ni `esperando-reset`).
     - Si la salida listó terminales `trabado`, anotalas en el informe (o reportalas) para que el usuario sepa qué sesiones quedaron colgadas.
     - Se programó el apagado en 5 minutos (`shutdown -P +5 ...`). Registralo en el informe y en el último mensaje del chat indicando cómo cancelar (`shutdown -c`).
   - **Salida 3 (bloqueo por actividad o espera de reset):** Hay agentes en `trabajando` o `esperando-reset`.
     - Si hay terminales `trabado`, anotalas también.
     - No fuerces el apagado: programá un nuevo chequeo en 10 minutos con `CronCreate` y cerrá el turno esperando el próximo ciclo.
   - **Salida 1 (error):** Falló el comando de apagado o la consulta a Orca. Reportalo.

## Reglas de clasificación

- **`trabado`:** Sesión con `idle=no` que lleva 60 o más minutos sin salida. No frena el apagado; se imprime para ser anotada.
- **`esperando-reset`:** Sesión con `idle=si` y mensaje de límite (`try again at`, `limit reached`, `hit your limit`, `hit your usage limit`) cuya hora de reset más 15 minutos todavía no pasó (`ahora < reset + 15 min`). Bloquea el apagado hasta que se cumpla la ventana. Si ya pasaron más de 15 minutos del reset, se considera `libre` (la sesión ya debería haber vuelto y nadie la retomó).
- **`trabajando`:** Sesión con `idle=no` con menos de 60 minutos sin salida. Bloquea el apagado.
- **`libre`:** Sesión con `idle=si` sin mensaje de límite (o con el plazo de reset ya vencido). No bloquea.
- La terminal propia queda excluida automáticamente del chequeo por `$ORCA_PANE_KEY`.
