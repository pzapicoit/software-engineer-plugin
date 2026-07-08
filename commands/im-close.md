---
name: im-close
description: Ejecuta la Fase C del workflow IntermarkIt: push final, PR, marcar criterios de aceptacion, transicion Jira a "In Testing", comentario de cierre con metricas y limpieza del pointer .active.
---

# /im-close

Cierra la tarea activa (Fase C del workflow definido en `rules/intermarkit-global.mdc` §6.3 y `agents/software-engineer.md` §Fase C).

## Prerequisitos

- La Fase B esta completa: `/opsx-verify` OK, `adversarial-reviewer` con veredicto `APROBADO`, `/opsx-archive` ejecutado.
- Existe una tarea activa: `.intermarkit/task-metrics/.active` debe apuntar a un fichero valido. Si no, aborta e informa al usuario.

## Pasos

1. **Identificar tarea activa** — lee `.intermarkit/task-metrics/.active`. Obten `issue_key` del JSON asociado.
2. **Actualizar docs** — si el cambio introdujo modulo/dependencia/decision arquitectonica relevante, actualiza `.intermarkit/architecture.md` / `functional.md` (skill `architect` §Mantenimiento).
3. **Commit final + push**:
   ```bash
   git status
   git add -A  # si hay cambios pendientes
   git commit -m "tipo({ISSUE_KEY}): descripcion" -m "$(cat proposal.md ...)"  # si es necesario
   git push -u origin HEAD
   ```
4. **Crear PR** — `bitbucketPullRequest` (create):
   - Titulo: commit message principal (formato convencional).
   - Descripcion: resumen extraido de `proposal.md` (ver `agents/reference.md` §PRs).
   - Si el MCP Bitbucket no esta disponible, informa la URL del repo para creacion manual.
5. **Marcar criterios de aceptacion** — si el issue tenia `- [ ]` en la description (detectados en `/im-take` o Fase A):
   - Relee la description actual con `getJiraIssue` (puede haber cambiado).
   - Reescribe cambiando `- [ ]` a `- [x]` solo en criterios realmente implementados y cubiertos por el veredicto `APROBADO`.
   - `editJiraIssue` con `fields: {"description": "..."}`, `contentFormat: "markdown"`.
   - Nunca marcar criterios a medias.
6. **Transicionar Jira a "In Testing"**:
   - Consulta cache `.intermarkit/cache/jira-transitions-{PROJECT}.json` (regla §7).
   - Si `stale`/`missing`, `getTransitionsForJiraIssue` + actualizar cache.
   - `transitionJiraIssue` con el ID.
   - Si no existe transicion, informa y continua.
7. **Calcular metricas** — lee `.intermarkit/task-metrics/{ISSUE_KEY}.json`:
   - Tiempo: `started_at` vs `date -u +%Y-%m-%dT%H:%M:%SZ` (no dependas de `elapsed_ms`, lo rellena `sessionEnd`).
   - Tool calls: `tool_calls` (hook `postToolUse` en vivo).
   - Tokens: bloque `tokens` (`input`, `output`, `cache_read`, `cache_write`, `turns`) acumulado por el hook `stop`. Cota inferior: el turno actual no esta contabilizado aun.
   - Total y coste estimado: calcula segun `agents/reference.md §Total de tokens y coste estimado` (usa el one-liner Python sugerido para precision, con `last_model` del fichero).
   - Context peak: bloque `context_peak` si existe (hook `preCompact`).
8. **Comentario Jira** — `addCommentToJiraIssue` con la plantilla de `agents/reference.md` §Plantilla de comentario Jira. Incluye tiempo, tool calls, tokens (formato M/K + cache hit %), total de tokens y coste estimado en € (prefijo `≈`). Anade la linea de `context peak` solo si el fichero la trae. No inventes cifras: si `tokens.turns == 0`, omite esas lineas.
9. **Borrar pointer** — `rm .intermarkit/task-metrics/.active`. Esto desactiva el hook `postToolUse` para esta tarea (el hook `stop` tambien lo hace por si acaso).
10. **Confirmar cierre** al usuario:
    - Rama pusheada + PR creado (o pendiente)
    - Issue en "In Testing"
    - N de M criterios marcados
    - Tiempo X min, tool calls N
    - Comentario Jira anadido
11. **Sugerir chat nuevo** si el usuario menciona OTRA tarea Jira (regla §0.1). No continuar la nueva tarea en el chat actual.

## Nota

Si el veredicto adversarial es `RECHAZADO CON HALLAZGOS`, NO ejecutes este comando: vuelve a Fase B (corregir + verify + adversarial hasta APROBADO).
