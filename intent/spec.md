# Spec: turno-noche (desde intent.md 2026-11-05)
Estado: aceptado (Denis, 2026-11-05, con los ajustes de REQ-1, REQ-9 y REQ-12: "me parece bien armar
todo el spec"). Revisado por Codex y Antigravity (2026-11-07): aprobado tras los arreglos de
apagado-seguro d871049, a701af8, 9ae659b y 2ba72f8.

Glosario: **turno** = desde que Denis lo arranca hasta que se apaga la PC o vuelve. **Ficha** = el
encargo del turno, escrito en un archivo.

## Requisitos
- REQ-1 MUST: al arrancar, con Denis presente, arma la ficha con lo que ya consta y le pregunta solo
  lo que falta: qué está aprobado, proyecto y rama propia, sesiones paralelas, si apaga al final
  (siempre lo pregunta, sea de día o de noche) y, si habrá gasto, el tope. Origen: Resultado, "Denis contesta lo que haga
  falta"; tope "que se fija al arrancar".
- REQ-2 MUST: antes de que Denis se vaya, comprueba que nada lo va a frenar: workers que respondan
  (sin "Hooks need review"), checks que corran, permisos que no pidan aprobación y límite semanal de
  tokens con margen. Lo que falle se resuelve o se avisa ahí. Origen: "nada espera respuesta".
- REQ-3 MUST: durante el turno no hace preguntas ni espera aprobaciones. Lo que necesita una decisión
  de Denis va a "Para Denis" y sigue con otra cosa. Origen: ídem.
- REQ-4 MUST: además de lo aprobado, avanza el trabajo que sigue el intent, los specs y planes y el
  flujo que el proyecto usa hoy. Antes de tocar algo, comprueba que ese flujo pasa por ahí. Es
  decisión de Denis, y no lo hace: cambiar el concepto o tocar el "fuera de alcance" de un intent,
  elegir entre alternativas que cambian el producto, editar instrucciones o artefactos aceptados,
  borrar fuera de su rama y cualquier acción hacia afuera. Origen: "discernir entre qué avanzar y con
  qué no avanzar"; Fuera de alcance.
- REQ-5 MUST: puede escribir intent, spec y plan por story en `intent/<slug>/`, que siempre quedan en
  `borrador`. Si la story no necesita decisiones de Denis (REQ-4), puede implementarla en su rama; si
  las necesita, deja los artefactos y no la implementa. Origen: "distintas stories"; "adelantar trabajo
  que no requiera decisión mía"; "rama aparte: si está mal, se elimina y listo".
- REQ-6 MUST: cada trabajo es un commit en la rama propia del turno. Nunca commitea en la rama base ni
  hace push, merge o publica. Un trabajo que no pasa los checks y no logra arreglar va a otra rama,
  separado de los que pasaron, y se anota; nunca borra ramas ni commits (decisión de Claude: borrar
  es de Denis). Origen: Restricciones; "se elimina y listo".
- REQ-7 MUST: gasta solo en las pruebas que hacen falta y sin pasar el tope. Si la próxima corrida no
  entra, la anota y no la corre. Respeta las reglas de coordinación del proyecto. Origen: tope.
- REQ-8 MUST: mientras queda trabajo, mantiene un despertador programado para el próximo reset de sus
  tokens, con 10 a 15 minutos de margen. Lo programa la propia sesión de Claude Code, que queda abierta
  mientras está sin tokens; no es un timer del sistema ni un hook. Al despertar, lee la ficha y el
  estado, revisa qué pasó y sigue. Origen: "se despierta al reset".
- REQ-9 MUST: si un worker choca con su límite, pasa la tarea al otro. Cuando el primero se resetea,
  se despierta con el mismo margen y le pide que revise lo hecho: son modelos distintos y su opinión
  suma. Si no hay otro worker disponible, espera al reset. Origen: ídem; Restricciones (CLAUDE.md:
  "si uno se queda sin tokens, va al otro" y el concilio).
- REQ-10 MUST: antes de dar un trabajo por terminado, lo verifica como piden las reglas vigentes
  (checks y concilio). Si falta un revisor, lo dice en el informe. Origen: Restricciones.
- REQ-11 MUST: deja un informe con qué se hizo, "Ver y probar" (rama, ruta, comandos exactos y qué
  mirar), "Para Denis", gasto, esperas por límites y cómo terminó. El último mensaje del chat lo
  resume y da la ruta. Origen: "un informe".
- REQ-12 MUST: si la ficha dice que apague, lo hace cuando todo terminó: su trabajo commiteado, el
  informe escrito, sus workers cerrados, ninguna otra sesión ni worker trabajando y ninguna corrida
  paga en curso. Si algo sigue trabajando, espera. Una sesión o worker sin actividad visible durante
  1 hora cuenta como trabado, no como trabajando: se anota y no frena el apagado (decisión de Claude).
  La excepción es el que espera el reset de su límite: no está trabado, así que se espera a que vuelva
  y termine.
  Avisa a las sesiones paralelas y apaga con margen para cancelar. Origen: "apagando la PC una vez que
  finalizaron todo".

## Capacidades y escenarios
### Arranque (REQ-1, REQ-2)
- GIVEN Codex frena en "Hooks need review" WHEN corre el chequeo THEN se lo dice a Denis antes de que se vaya.
### Qué avanza (REQ-3, REQ-4, REQ-5)
- GIVEN un desvío en un camino que la UI ya no usa WHEN lo encuentra THEN lo anota y no lo arregla.
- GIVEN una story sin plan WHEN la toma THEN escribe el plan en `borrador` y lo implementa en su rama.
### Límites (REQ-8, REQ-9)
- GIVEN reset a las 02:40 WHEN se queda sin tokens a las 02:10 THEN a las 02:50-02:55 retoma desde la ficha.
- GIVEN gastó USD 12 de un tope de 15 WHEN la próxima corrida cuesta 3,16 THEN no la corre y la anota.
### Cierre (REQ-11, REQ-12)
- GIVEN otra sesión trabajando WHEN termina su trabajo THEN espera, y apaga cuando la otra termina.
- GIVEN una sesión parada esperando a Denis WHEN chequea THEN no cuenta como trabajando.
- GIVEN un worker sin actividad desde hace 1 hora WHEN chequea THEN lo anota como trabado y apaga.
- GIVEN un worker sin tokens hasta dentro de 3 horas WHEN chequea THEN no lo cuenta como trabado y espera.

## Lo que queda al builder
Estructura en skills, formato de la ficha, ubicación del informe, cómo leer el uso de tokens y cómo
detectar sesiones trabajando.

## Concerns
- Sin la línea de excepción en el CLAUDE.md de cada perfil, CLAUDE.md le gana a REQ-4 y REQ-5.
- Si la sesión no tiene permisos suficientes, un pedido de permiso la frena igual. REQ-2 solo lo detecta.
- No está probado que el despertador funcione después de chocar con el límite, y se pierde si se cierra la sesión.
- La regla de 1 hora puede apagar con una sesión ajena que trabajaba sin mostrar actividad.
