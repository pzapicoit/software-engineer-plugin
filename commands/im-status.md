---
name: im-status
description: Muestra el estado del trabajo actual IntermarkIt: proyecto configurado, rama activa, tarea Jira en curso (si existe), tiempo transcurrido, tool calls acumulados y estado de la cache MCP.
---

# /im-status

Resumen del estado actual sin hacer cambios ni llamadas MCP. Solo lee ficheros locales.

## Pasos

1. **Contexto de proyecto** — lee `.intermarkit/config.yaml`. Muestra `jira.project`, `repo.type`, `repo.workspace`, `repo.default_branch`, `docs.confluence_space` si existen.
2. **Rama Git actual** — `git branch --show-current` via Shell.
3. **Tarea activa** — comprueba `.intermarkit/task-metrics/.active`:
   - Si existe, lee el fichero apuntado (`.intermarkit/task-metrics/{ISSUE_KEY}.json`) y muestra:
     - `issue_key`
     - `started_at` (ISO)
     - Tiempo transcurrido calculado en minutos (`now - started_at`, con `date -u`)
     - `tool_calls` (contador en vivo del hook `postToolUse`)
     - `tokens.input` / `output` / `cache hit %` / `turns` si el bloque `tokens` existe (acumulado por el hook `stop`). Formato M/K.
     - `context_peak.tokens` / `percent` si existe (hook `preCompact`).
     - `last_model` y `cursor_version` si estan.
   - Si no existe pointer, informa "sin tarea activa".
4. **Estado cache MCP** — para cada fichero en `.intermarkit/cache/`:
   - `atlassian-user.json` (TTL 30d)
   - `bitbucket-verified.json` (TTL 24h)
   - `jira-transitions-{PROJECT}.json` (TTL 7d)
   Calcula `fresh` / `stale` / `missing` segun `cached_at + ttl_seconds` vs `now`.
5. **Documentacion** — comprueba existencia de `.intermarkit/architecture.md` y `.intermarkit/functional.md`. Informa si falta alguno (habria que aplicar la skill `architect`).
6. **OpenSpec** — comprueba `openspec/` y si hay un cambio activo en `openspec/changes/`. Si lo hay, lista el nombre del cambio y el estado de sus `tasks.md` (cuantas tareas completadas vs pendientes).

## Formato de salida

Presenta como una tabla o lista markdown compacta, priorizando lo relevante:

```
## Estado IntermarkIt

**Proyecto:** PROJ (bitbucket / intermarkithub / rama default: main)
**Rama actual:** feature/PROJ-42-auth-login
**Tarea activa:** PROJ-42 · iniciada hace 45 min · 87 tool calls
**Tokens:** input 1.9M · output 10K · cache hit 77% · turns 3
**Context peak:** 120K tokens (85% del window), 2 compactaciones
**Cambio OpenSpec:** PROJ-42-add-auth (12/18 tareas)
**Docs:** architecture.md ok, functional.md ok
**Cache MCP:** user_info fresh (28d restantes), transitions.PROJ fresh (6d), bitbucket_verified stale
```

Omite las lineas de `Tokens` y `Context peak` si el fichero no las tiene (tarea recien empezada o Cursor no ha disparado aun los hooks correspondientes).

## Nota

Este comando es idempotente y readonly: no hace llamadas MCP, no crea ficheros, no modifica nada. Puede ejecutarse en cualquier momento sin efectos secundarios.
