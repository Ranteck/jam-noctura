---
name: turno-noche
description: Usar cuando el usuario deja la sesión desatendida ("turno noche", "me voy", "apagá al terminar") para avanzar trabajo sin preguntas y opcionalmente apagar la máquina.
---

# Turno noche y trabajo desatendido

Adelanta trabajo aprobado y entregas autónomas sin el usuario presente, aislando cambios y opcionalmente apagando la máquina al terminar.

## Fase 1: Arranque (con el usuario presente)

1. **Ficha e informe:** crear la ficha en `~/Documentos/turno-noche/<AAAA-MM-DD>-<proyecto>.ficha.md` (de `assets/ficha.md`) y el informe al lado (de `assets/informe.md`).
2. **Preguntar solo lo que falta:** completar lo conocido y consultar lo faltante:
   - Trabajo aprobado.
   - Proyecto y ruta.
   - Con git: rama base, del turno (`turno/<AAAA-MM-DD>-<slug>`) y de fallidos (`turno/<AAAA-MM-DD>-fallidos`). Sin git: carpetas o archivos.
   - Sesiones paralelas en Orca.
   - **Apagar la PC al terminar:** preguntar siempre (día o noche).
   - Tope de gasto si hay pruebas pagas; si no, `sin gasto`.
3. **Chequeo de viabilidad:** antes de que el usuario se vaya, verificar:
   - Workers: probar respuesta en Orca (`ORCA="${ORCA_CLI_COMMAND:-orca-ide}"`). Si Codex muestra "Hooks need review", relanzarlo con el bypass de hooks como indica `CLAUDE.md`; si sigue trabado, avisar antes de que el usuario se vaya.
   - Checks: correr tests o linter en rama base (debe partir verde).
   - Permisos: verificar que las herramientas no pidan confirmación.
   - Tokens: chequear margen semanal con `~/.claude/skills/despertador-limite/scripts/uso-claude.sh`; avisar si no hay margen.
4. **Despertador:** invocar `despertador-limite` para mantener activos los crons ante límites de tokens.

---

## Fase 2: Reglas de la noche (desatendido)

1. **Cero preguntas y sin bloqueos:** no usar `AskUserQuestion` ni plan mode (`EnterPlanMode`/`ExitPlanMode`). El plan se escribe en un archivo y se ejecuta. Lo que requiera decisión del usuario va a `## Para el usuario` del informe y se pasa a otra tarea.
2. **Qué avanzar y flujo activo:**
   - *Avanza:* trabajo aprobado y tareas que extiendan intent/spec en el flujo vigente.
   - *Comprobar flujo activo:* verificar empíricamente (UI, API o entrypoint) que el flujo activo pasa por ahí antes de tocar código. Si es código muerto o la UI no lo usa, no arreglarlo; va a `Para el usuario`.
   - *Decisión del usuario (no tocar):* cambiar concepto o fuera de alcance de un intent, elegir alternativas de diseño o producto, modificar instrucciones o artefactos aceptados, y borrar fuera de la rama del turno.
   - *Acciones prohibidas:* no hacer push, merge, PRs, publicar ni mandar mensajes a personas. Corridas pagas autorizadas siguen la regla del tope.
3. **Stories autónomas:** redactar `intent.md`, `spec.md` y `plan.md` en `intent/<slug>/` siempre en `borrador`. Nunca marcarlos como aceptados sin el usuario. Si no requiere elegir alternativas, implementarla; si requiere decisiones, dejar artefactos en borrador, anotarla en `Para el usuario` y no implementar.
4. **Aislamiento, commits y archivos:**
   - Con git: trabajar en la rama del turno (nunca en worktrees ocultos); cada entrega es un commit atómico. No commitear en base ni borrar ramas o commits. Si un trabajo falla checks tras repararlo, moverlo a la rama de fallidos, anotarlo y limpiar la rama del turno.
   - Sin git: guardar cada entrega en su archivo o carpeta documentada en el informe.
5. **Control de gasto:** con `sin gasto`, no correr llamadas pagas. Con tope, sumar cada gasto en ficha e informe. Si el costo estimado excede el saldo restante, no correrla, anotarla y seguir con tareas gratuitas.
6. **Límites de tokens y workers:** si un worker agota cuota, pasar la tarea al otro (Codex/Antigravity) e invocar `despertador-limite` al reset del primero para que revise lo hecho.
7. **Verificación y concilio:** validar con checks del proyecto. Si las reglas exigen concilio, pedirlo en solo lectura; si falta un revisor por cupo, anotarlo en el informe.

---

## Fase 3: Informe continuo

Actualizar `~/Documentos/turno-noche/<AAAA-MM-DD>-<proyecto>.md` tras cada commit o trabajo con las secciones de `assets/informe.md`: Resumen, Hecho (un commit o archivo por línea), Ver y probar (comandos exactos o rutas), Para el usuario, Gasto, Esperas por límites y Cierre.

---

## Fase 4: Cierre del turno

1. **Precondiciones:** trabajo commiteado o guardado, informe actualizado en disco, workers propios cerrados y crons borrados (`CronDelete`).
2. **Apagado:** si la ficha dice apagar, invocar `apagado-seguro`. Si no, registrar en `## Cierre` que queda encendida.
3. **Mensaje final:** resumir el turno en 2 o 3 párrafos en el chat con la ruta al informe y el estado del apagado.
