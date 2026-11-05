# Intención: turno-noche
Autor: Denis · Estado: aceptado (Denis, 2026-11-05: "dale") · Fecha: 2026-11-05

## Problema
Denis deja un agente trabajando de noche "para ir adelantando trabajo que no requiere mi decisión" y
le pide que apague la PC al terminar. La noche del 04/11, en AI Hunting, el agente
marcó un plan como aceptado sin que Denis lo leyera, arregló un camino en desuso y dejó los cambios
sin commitear en otro worktree, donde Denis no los vio.

## Resultado esperado
Una skill para cualquier proyecto, de código "o alguna otra cosa", de noche o "en algún momento que
yo salga y necesito que esto corra y apenas voy a estar mirando".
- Antes de irse, Denis contesta lo que haga falta. Después, "yo no voy a estar en la computadora":
  nada espera respuesta.
- Ejecuta lo aprobado "y también adelantar trabajo que no requiera decisión mía", "siempre siguiendo
  las propuestas, flujo lógico o lo que esté usando como la propuesta del proyecto". "La idea no es
  que cree cosas de la nada, sino que pueda discernir entre qué avanzar y con qué no avanzar."
- Puede escribir intent, spec y plan "en distintas carpetas como si fuesen distintas stories". Quedan
  en `borrador`.
- Cada trabajo es un commit en una rama aparte: "si está mal, se elimina y listo".
- El que choca con el límite de tokens se despierta al reset más 10 a 15 minutos, "revise qué fue lo
  que pasó" y sigue.
- Puede gastar en "las pruebas que corresponden", hasta un tope que se fija al arrancar ("que no
  supere, por ejemplo, $10, $15").
- Al volver, un informe: qué se hizo, cómo verlo y probarlo, y qué espera una decisión de Denis.
- Sin hora límite: "prefiero que se termine apagando la PC una vez que finalizaron todo".

## Usuarios y sistemas afectados
Denis. Claude Code, workers de Orca, sesiones paralelas, el repo de cada proyecto y el apagado.

## Restricciones
- "No hagas push, pero si querés comitear, sí": sin push, merge ni publicación.
- Rigen las house rules y CLAUDE.md, salvo lo que este intent habilita. Como CLAUDE.md manda sobre las
  skills, el de cada perfil suma una línea con esa excepción.
- Cumple el checklist de "Crear skills".

## Fuera de alcance
- Decidir lo que es de Denis: queda anotado.
- Hooks y timers de systemd: "no veo la idea de usar un hook", "timer tampoco".

## Preguntas abiertas
Ninguna.

## Cambios
