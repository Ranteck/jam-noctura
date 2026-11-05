# jam-noctura

Skills de Claude Code para dejar un agente trabajando cuando no estás, de noche o cuando salís, y que apague la PC al terminar.

## Para qué sirve

Antes de irte, el agente arma la ficha del turno: qué está aprobado, en qué rama trabaja, el tope de gasto si hay corridas pagas y si apaga al final. Te pregunta solo lo que falta y comprueba que nada lo va a frenar. Después no pregunta nada:

- avanza lo aprobado y lo que no requiere tu decisión, siguiendo el intent y el flujo que el proyecto usa hoy;
- cada trabajo queda en un commit de su rama, sin push ni merge, y lo que necesita tu decisión queda anotado;
- si se queda sin tokens, se despierta solo cuando se resetean;
- deja un informe con lo hecho, cómo verlo y probarlo, y lo que espera tu decisión;
- apaga la PC cuando ninguna otra sesión ni worker sigue trabajando.

## Skills

- `turno-noche`: la principal.
- `despertador-limite`: programa el despertar para el reset del límite de tokens, propio o de un worker. Sirve sola.
- `apagado-seguro`: apaga con `shutdown +5` cuando nadie sigue trabajando en Orca. Sirve sola.

Necesita Claude Code, Orca (para ver las otras sesiones y los workers), `jq`, `curl` y systemd.

## Instalación

```sh
git clone https://github.com/Ranteck/jam-noctura.git ~/Proyectos/jam-noctura
for s in turno-noche despertador-limite apagado-seguro; do
  ln -s ~/Proyectos/jam-noctura/skills/$s ~/.claude/skills/$s
done
```

Si tu CLAUDE.md exige aprobar los planes antes de implementar, sumale una excepción para `turno-noche`: si no, CLAUDE.md le gana a la skill.

Se invoca con `/turno-noche` o pidiendo que lo deje corriendo y apague la PC al terminar.

El diseño está en `intent/`: intent, spec y plan.

## Licencia

MIT
