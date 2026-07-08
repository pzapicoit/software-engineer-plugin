---
name: im-status
description: Muestra el estado del trabajo actual IntermarkIt: proyecto configurado, rama activa, tarea Jira en curso (si existe), tiempo transcurrido, tool calls acumulados y estado de la cache MCP.
---

# /im-status

Resumen del estado actual sin hacer cambios ni llamadas MCP. Solo lee ficheros locales.

## Pasos

1. **Contexto de proyecto** — lee `.intermarkit/config.yaml`. Muestra `jira.project`, `docs.confluence_space` si existe, y el/los repo(s):
   - Un solo repo (`repo:` legacy o `repos:` con un elemento): `type`, `workspace`, `default_branch`.
   - Multi-repo (`repos:` con varios elementos): lista con `name`, `type`, `workspace`, `default_branch` de cada uno.
2. **Rama Git actual** — para cada repo configurado, `git -C "{path}" branch --show-current` via Shell (`path` = `.` en single-repo). En multi-repo, muestra una rama por repo.
3. **Tarea activa** — comprueba `.intermarkit/task-metrics/.active`:
   - Si existe, lee el fichero apuntado (`.intermarkit/task-metrics/{ISSUE_KEY}.json`) y muestra:
     - `issue_key`
     - `started_at` (ISO)
     - Tiempo transcurrido calculado en minutos (`now - started_at`, con `date -u`)
     - `tool_calls` (contador en vivo del hook `postToolUse`)
     - `repos` (lista de `name`) si el proyecto es multi-repo y el campo existe — indica que repos toca esta tarea concreta.
     - `tokens.input` / `output` / total / `cache hit %` / `turns` si el bloque `tokens` existe (acumulado por el hook `stop`). Formato M/K. Total y formulas en `agents/reference.md §Total de tokens y coste estimado`.
     - Coste estimado en € (misma seccion de referencia, usa `last_model` para la tarifa). Prefijo `≈`, no es facturacion real.
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
**Tokens:** input 1.9M · output 10K · total 1.96M · cache hit 77% · turns 3
**Coste estimado:** ≈ 5,23 €
**Context peak:** 120K tokens (85% del window), 2 compactaciones
**Cambio OpenSpec:** PROJ-42-add-auth (12/18 tareas)
**Docs:** architecture.md ok, functional.md ok
**Cache MCP:** user_info fresh (28d restantes), transitions.PROJ fresh (6d), bitbucket_verified stale
```

Omite las lineas de `Tokens`, `Coste estimado` y `Context peak` si el fichero no las tiene (tarea recien empezada o Cursor no ha disparado aun los hooks correspondientes).

**Variante multi-repo** — sustituye `**Proyecto:**`/`**Rama actual:**` por una linea por repo (o una linea `Repos:` compacta) y anade que repos toca la tarea activa:

```
**Proyecto:** PROJ
**Repos:** frontend (bitbucket/intermarkithub, main) → feature/PROJ-42-auth-login | backend (bitbucket/intermarkithub, main) → main
**Tarea activa:** PROJ-42 · iniciada hace 45 min · 87 tool calls · repos: frontend, backend
```

## Nota

Este comando es idempotente y readonly: no hace llamadas MCP, no crea ficheros, no modifica nada. Puede ejecutarse en cualquier momento sin efectos secundarios.
