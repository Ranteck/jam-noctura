# turno-noche Implementation Plan (desde spec.md e intent.md 2026-11-05)
Estado: aceptado (Denis, 2026-11-05: "Me parece bien", incluida la línea de los dos CLAUDE.md)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tres skills versionadas en `~/Proyectos/jam-noctura/skills/` que dejan un turno desatendido trabajando, despiertan al agente tras un límite de tokens y apagan la PC cuando todo terminó.

**Architecture:** `turno-noche` (principal) arma la ficha, fija las reglas de la noche y el informe, y llama en orden a `despertador-limite` (uso de tokens y wakeups con `CronCreate`) y a `apagado-seguro` (quién sigue trabajando en Orca y `shutdown +5`). Lo determinista va en scripts bash con tests; lo que requiere criterio va en el SKILL.md.

**Tech Stack:** bash, `jq`, `curl`, GNU `date`, `orca` CLI, `shutdown` de systemd, herramientas `CronCreate`/`CronDelete` de Claude Code.

**Spec:** `intent/spec.md` (con `intent/intent.md`).

## Global Constraints
- Sin hooks ni timers de systemd (intent, Fuera de alcance).
- Margen del despertador: 12 minutos (dentro de "10 a 15").
- Apagado: `shutdown -P +5 "turno-noche: apagado en 5 min. Cancelar: shutdown -c"`.
- Trabado = sin salida en la terminal durante 60 minutos y sin estar libre (REQ-12).
- Sin push, merge ni publicación; commits en la rama del turno (REQ-6).
- Skills genéricas: proyecto, rama, rutas y tope entran por la ficha, nunca escritos en la skill.
- Informes en `~/Documentos/turno-noche/<AAAA-MM-DD>-<proyecto>.md` (decisión de Claude: un solo lugar para todos los proyectos, fuera de cualquier rama).

## Tests a escribir
| Test (comportamiento observable) | REQ |
| --- | --- |
| `cron-despertar.test.sh`: reset UTC, hora suelta de hoy y de mañana, margen | REQ-8, REQ-9 |
| `uso-claude.sh` real muestra pct y reset; sin credenciales sale con 1 | REQ-2, REQ-8 |
| El cron `a22c81d1` despierta a esta sesión a las 14:22 | REQ-8 |
| `quien-trabaja.test.sh`: libre, trabajando, esperando-reset (Codex y Claude), trabado | REQ-12 |
| `apagar.sh --simulacro` en esta máquina excluye la terminal propia | REQ-12 |
| Escenario arranque: ficha incompleta → pregunta solo lo que falta; Codex en "Hooks need review" → lo avisa | REQ-1, REQ-2 |
| Escenario desvío en la CLI que la UI no usa → lo anota, no lo toca | REQ-3, REQ-4 |
| Escenario story sin plan y sin decisiones → plan en borrador, implementación y un commit en la rama del turno | REQ-5, REQ-6 |
| Escenario story que necesita elegir entre alternativas de producto → artefactos en borrador, sin implementar | REQ-4, REQ-5 |
| Escenario check que falla y no se arregla → otra rama y anotado | REQ-6 |
| Escenario USD 12 de 15 y la corrida cuesta 3,16 → no la corre | REQ-7 |
| Escenario Codex sin cuota a la 1:00 → Antigravity sigue, Codex revisa al volver | REQ-9, REQ-10 |
| Escenario informe → "Ver y probar" con rama, ruta y comandos; resumen en el último mensaje | REQ-11 |
| Escenario otra sesión trabajando o esperando reset al cerrar → espera; trabada 1 h → apaga | REQ-12 |

## Review Focus
1. El endpoint de uso falla (sin token o sin red): no hay hora de reset. Esperado: el despertador horario de respaldo igual lo retoma. Test en Task 1.
2. Hora de Codex "2:10 PM" cuando ya pasaron las 14:10: es mañana, no hoy. Test en Task 1.
3. Reset en UTC (`resets_at`): la cron va en hora local. Test en Task 1.
4. Una sesión de Claude que chocó con su límite está libre para Orca, pero espera un reset: no puede contar como libre. Test en Task 2.
5. La terminal del propio coordinador siempre está trabajando: hay que excluirla o nunca apaga. Test en Task 2.

---

### Task 1: `despertador-limite` (REQ-8, REQ-9)

**Files:**
- Create: `skills/despertador-limite/SKILL.md`
- Create: `skills/despertador-limite/scripts/uso-claude.sh`
- Create: `skills/despertador-limite/scripts/cron-despertar.sh`
- Test: `skills/despertador-limite/scripts/cron-despertar.test.sh`

**Interfaces:**
- Produces: `uso-claude.sh` imprime JSON `{"cinco_horas":{"pct":N,"reset":"<ISO local>"},"semanal":{"pct":N,"reset":"<ISO local>"}}`. Lee el token de `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json` y llama a `https://api.anthropic.com/api/oauth/usage` con los headers de `~/.claude/statusline.sh`. No usa `/tmp/claude/statusline-usage-cache.json`, que comparten los dos perfiles. Sale con 1 y un mensaje en stderr si falla.
- Produces: `cron-despertar.sh <hora> [margen_min=12]` imprime `M H D Mon *` local. `<hora>` es ISO-8601 o una hora suelta ("2:10 PM", "3am"); si una hora suelta ya pasó, toma la del día siguiente. Redondea al minuto siguiente. `AHORA_EPOCH` fija "ahora" en los tests.

- [ ] **Step 1: Write the failing test** con `TZ=America/Argentina/Buenos_Aires`, `AHORA_EPOCH` de 2026-11-05 09:00 -03:
  - `2026-11-05T16:39:59.600446+00:00` → `52 13 5 11 *`
  - `"2:10 PM"` → `22 14 5 11 *`
  - `"2:10 PM"` con `AHORA_EPOCH` de 15:00 → `22 14 6 11 *`
  - `"3am" 15` → `15 3 6 11 *`
  - `CLAUDE_CONFIG_DIR=<carpeta vacía> uso-claude.sh` → sale con 1 y mensaje en stderr (Review Focus 1)
- [ ] **Step 2:** `bash skills/despertador-limite/scripts/cron-despertar.test.sh` → FAIL.
- [ ] **Step 3:** implementar los dos scripts.
- [ ] **Step 4:** test → PASS. `uso-claude.sh | jq .` muestra pct y reset reales.
- [ ] **Step 5:** SKILL.md:
  - con trabajo pendiente, mantiene un `CronCreate` de una vez en `cron-despertar.sh <reset>` y uno horario de respaldo (`7 * * * *`), y lo rearma al despertar;
  - si el uso semanal no deja margen, lo avisa al arrancar;
  - si un worker choca, lee "try again at …" o "resets …" en su terminal, pasa la tarea al otro worker y programa el despertar en el reset del primero para que revise lo hecho;
  - al despertar, lee la ficha y el estado y sigue;
  - al terminar el turno, borra sus crons con `CronDelete`.
- [ ] **Step 6:** commit.

### Task 2: `apagado-seguro` (REQ-12)

**Files:**
- Create: `skills/apagado-seguro/SKILL.md`
- Create: `skills/apagado-seguro/scripts/quien-trabaja.sh`
- Create: `skills/apagado-seguro/scripts/apagar.sh`
- Test: `skills/apagado-seguro/scripts/quien-trabaja.test.sh`

**Interfaces:**
- Produces: `clasificar <idle:si|no> <min_sin_salida> <preview>` (función en `quien-trabaja.sh`, se puede cargar con `source`) → `libre | trabajando | esperando-reset | trabado`.
- Produces: `quien-trabaja.sh` imprime un TSV por cada terminal de Orca con agente: `handle agente titulo estado min_sin_salida`. Excluye la que tiene `recordedPaneKey == $ORCA_PANE_KEY`. Usa `orca terminal list --json` y `orca terminal wait --for tui-idle --timeout-ms 2000`.
- Produces: `apagar.sh [--simulacro]`: si alguna terminal está `trabajando` o `esperando-reset`, sale con 3 y la lista. Si no, lanza el `shutdown` (o lo imprime en simulacro) y sale con 0. Si `shutdown` falla, sale con 1.

- [ ] **Step 1: Write the failing test:**
  - `clasificar si 5 "❯"` → `libre`
  - `clasificar si 5 "try again at 2:10 PM"` → `esperando-reset`
  - `clasificar si 5 "limit reached · resets 3am"` → `esperando-reset`
  - `clasificar no 5 "…"` → `trabajando`
  - `clasificar no 61 "…"` → `trabado`
- [ ] **Step 2:** test → FAIL. **Step 3:** implementar. **Step 4:** test → PASS.
- [ ] **Step 5:** `ORCA_PANE_KEY=$ORCA_PANE_KEY apagar.sh --simulacro` en esta máquina: no lista la terminal propia y clasifica bien las sesiones vivas.
- [ ] **Step 6:** SKILL.md:
  - antes de apagar: trabajo propio commiteado, informe escrito y workers propios cerrados;
  - con salida 3, vuelve a chequear en 10 minutos con `CronCreate` y anota los trabados en el informe;
  - avisa a las sesiones paralelas por `SendMessage` o por Orca;
  - corre `apagar.sh` y deja el resultado en el informe y en el último mensaje.
- [ ] **Step 7:** commit.

### Task 3: `turno-noche` (REQ-1 a REQ-7, REQ-10, REQ-11)

**Files:**
- Create: `skills/turno-noche/SKILL.md`
- Create: `skills/turno-noche/assets/ficha.md`
- Create: `skills/turno-noche/assets/informe.md`

**Interfaces:**
- Consumes: Task 1 (despertador) y Task 2 (apagado), invocadas por nombre.
- Produces: la ficha en `~/Documentos/turno-noche/<AAAA-MM-DD>-<proyecto>.ficha.md` y el informe al lado.

- [ ] **Step 1:** `assets/ficha.md`: aprobado, proyecto, ruta, rama base y rama del turno, sesiones paralelas, apagar sí/no, tope de gasto o "sin gasto", gastado.
- [ ] **Step 2:** `assets/informe.md` con estas secciones: Resumen · Hecho (un commit por línea) · Ver y probar · Para Denis · Gasto · Esperas por límites · Cierre.
- [ ] **Step 3:** SKILL.md por fases:
  - arranque: completa la ficha, pregunta lo que falta y hace el chequeo de REQ-2 (worker de prueba, checks, permisos, uso semanal);
  - reglas de la noche: REQ-3 a REQ-7 y REQ-10, con la lista de lo que es decisión de Denis y el chequeo del flujo vigente;
  - informe: lo actualiza en cada trabajo;
  - cierre: invoca `despertador-limite` al arrancar y `apagado-seguro` al final.
- [ ] **Step 4:** el concilio (solo lectura) recorre con la skill los escenarios de la tabla "Tests a escribir" y dice qué haría el agente. Cada uno tiene que coincidir con lo esperado.
- [ ] **Step 5:** commit.

### Task 4: instalación y excepción en CLAUDE.md

**Files:**
- Create: `README.md`, `LICENSE` (MIT, como `handoff-clear`), y `.gitignore` (ya existe).
- Modify: `~/Proyectos/hyprland-config/claude/.claude/CLAUDE.md` (destino del symlink de `~/.claude/CLAUDE.md`) y `~/.claude-personal/CLAUDE.md`, en "Skills de proceso", con esta línea textual:
  `- Excepción: en un turno de la skill \`turno-noche\` (sesión desatendida) rigen sus reglas: avanza sin preguntar lo que no requiere mi decisión, deja intent, spec y plan en borrador, trabaja en su rama con un commit por trabajo y no hace push ni merge.`

- [ ] **Step 1:** symlinks `~/.claude/skills/{turno-noche,despertador-limite,apagado-seguro}` → `~/Proyectos/jam-noctura/skills/…`. `~/.claude-personal/skills` ya apunta a `~/.claude/skills`. Revisar también `$ORCA_CLAUDE_CONFIG_DIR/skills`.
- [ ] **Step 2:** agregar la línea en los dos CLAUDE.md (aprobada con este plan) y commitearla en `hyprland-config` en una rama propia, sin push.
- [ ] **Step 3:** en una sesión nueva, la lista de skills muestra las tres.
- [ ] **Step 4:** commit en `jam-noctura`.

## Ejecución
Implementa Antigravity (house rules 8; Codex sin cuota hasta las 14:10). Claude reparte las tasks, lee cada diff, corre los tests y hace las tasks 3.4 y 4.2. Codex revisa todo a las 14:22 (cron `a22c81d1`). Repo público en GitHub (pedido de Denis): el primer commit, con `intent/` y `.gitignore`, va a `main`. Lo demás se commitea en la rama `skill-v1` y se pushea a esa rama, sin merge a `main`.
