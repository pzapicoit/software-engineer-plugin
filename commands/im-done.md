---
name: im-done
description: Ejecuta la Fase D final del workflow IntermarkIt tras confirmacion del usuario, transicionando Jira de "In Testing" a "Done" y anadiendo el comentario de validacion completada.
---

# /im-done

Cierra definitivamente la tarea activa (Fase D del workflow definido en `rules/intermarkit-global.mdc` §6.3 y `agents/software-engineer.md` §Fase D), tras validacion manual del usuario.

## Prerequisitos

- Existe una tarea activa: `.intermarkit/task-metrics/.active` debe apuntar a un fichero valido. Si no, aborta e informa al usuario.
- La Fase C esta completa: Jira en "In Testing", PR(s) creado(s).
- **El usuario ha confirmado explicitamente** que sus pruebas manuales son satisfactorias (p. ej. "funciona", "ok, ciérralo", o invocando este comando directamente). Nunca ejecutes este comando por iniciativa propia solo porque el codigo paso `verify`/`adversarial` — esas validaciones son de calidad de codigo, no de comportamiento funcional.

## Pasos

1. **Identificar tarea activa** — lee `.intermarkit/task-metrics/.active`. Obten `issue_key` del JSON asociado.
2. **Confirmar con el usuario si hay ambiguedad** — si no esta claro que el usuario esta dando el visto bueno final (p. ej. si solo dijo "parece que va bien" sin cerrar el tema), pregunta explicitamente antes de transicionar Jira.
3. **Registrar fixes de Fase D (si los hubo)** — si durante la validacion manual hubo commits de correccion, recopila un resumen breve (hash corto + descripcion) para el comentario Jira.
4. **Transicionar Jira a "Done"**:
   - Consulta cache `.intermarkit/cache/jira-transitions-{PROJECT}.json` (regla §7).
   - Si `stale`/`missing`: `getTransitionsForJiraIssue`, encuentra la transicion a "Done" por nombre, actualiza la cache (TTL 7d).
   - `transitionJiraIssue` con el ID.
   - Si no existe transicion directa "In Testing" -> "Done" (workflow con pasos intermedios), informa al usuario y usa la transicion disponible mas cercana.
5. **Comentario Jira** — `addCommentToJiraIssue` con la plantilla de `agents/reference.md §Plantilla de comentario Jira — /im-done`. Incluye el numero de iteraciones de fix (o "ninguna") y el detalle de fixes si los hubo (paso 3).
6. **Borrar pointer** — `rm .intermarkit/task-metrics/.active` (si no se borro ya en `/im-close`; puede que ya no exista, en cuyo caso no hay nada que hacer).
7. **Confirmar cierre** al usuario: issue en "Done", comentario anadido.
8. **Sugerir chat nuevo** para la siguiente tarea Jira distinta (regla §0.1).

## Nota

Este comando asume que `/im-close` (Fase C) ya se ejecuto. Si Jira todavia esta en "In Progress" (Fase C no se completo), informa al usuario y sugiere `/im-close` primero.
