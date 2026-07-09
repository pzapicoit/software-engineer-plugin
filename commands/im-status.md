---
name: im-status
description: Muestra el estado actual del trabajo IntermarkIt - proyecto, rama, tarea activa (si existe) con estado Jira, gates del bloque verification, deltas y fixes acumulados, tokens, coste y estado de la cache MCP. Readonly, no hace llamadas MCP ni modifica nada.
---

# /im-status

Resumen del estado actual sin hacer cambios ni llamadas MCP. Solo lee ficheros locales.

## Cuando se invoca (frases naturales)

- `/im-status` (explicito)
- "como va" / "estado" / "en que estamos"
- "resumen" / "que llevamos hecho"
- "en que fase estamos"

## Pasos

1. **Contexto de proyecto** — lee `.intermarkit/config.yaml`. Muestra `jira.project`, `docs.confluence_space` si existe, y el/los repo(s):
   - Un solo repo (`repo:` legacy o `repos:` con un elemento): `type`, `workspace`, `default_branch`.
   - Multi-repo (`repos:` con varios elementos): lista con `name`, `type`, `workspace`, `default_branch` de cada uno.
2. **Rama Git actual** — para cada repo configurado, `git -C "{path}" branch --show-current` via Shell (`path` = `.` en single-repo). En multi-repo, muestra una rama por repo.
3. **Tarea activa** — comprueba `.intermarkit/task-metrics/.active`:
   - Si existe, lee el fichero apuntado (`.intermarkit/task-metrics/{ISSUE_KEY}.json`) y muestra:
     - `issue_key`.
     - Estado Jira (si `openspec_change` es una lista sin elementos, sugiere que aun no se ha ejecutado `/im-take`; si `openspec_change_active` apunta a un delta, indicalo).
     - `started_at` (ISO) y tiempo transcurrido en minutos (`now - started_at`, con `date -u`).
     - `repos` (lista de `name`) si el proyecto es multi-repo.
     - **Bloque `verification`** — muestra cada campo con marca visual: `✓` si esta en verde (`true` / `"APROBADO"`), `✗` si falta:
       ```
       Gates:
         verify_passed             ✓
         adversarial_verdict       ✓ (APROBADO)
         tests_passed              ✓
         coverage_ok               ✗
         quality_ok                ✗
         archived                  ✗
         local_validation_passed   ✗
       ```
       Si `exempt: true`, indica `EXENTO: {exempt_reason}` en vez de listar gates.
     - `openspec_change_active` (nombre del cambio actualmente en curso).
     - Deltas archivados: numero de elementos en `deltas[]` (0 si el campo no existe o esta vacio).
     - Fixes aplicados durante Testing: numero de elementos en `fixes[]`.
     - `tool_calls` (contador del hook `postToolUse`).
     - Si el bloque `tokens` existe con `turns > 0`: `input` / `output` / total / `cache hit %` / `turns` (formato M/K). Total y formulas en `agents/reference.md §Total de tokens y coste estimado`.
     - Coste estimado en € (misma seccion de referencia, `last_model` -> tarifa). Prefijo `≈`.
     - `context_peak.tokens` / `percent` / `compactions` si existe.
     - `last_model` y `cursor_version` si estan.
   - Si no existe pointer, informa "sin tarea activa".
4. **Estado cache MCP** — para cada fichero en `.intermarkit/cache/`:
   - `atlassian-user.json` (TTL 30d).
   - `bitbucket-verified.json` (TTL 24h).
   - `jira-transitions-{PROJECT}.json` (TTL 7d).
   Calcula `fresh` / `stale` / `missing` segun `cached_at + ttl_seconds` vs `now`.
5. **Documentacion** — comprueba existencia de `.intermarkit/architecture.md` y `.intermarkit/functional.md`. Informa si falta alguno (habria que aplicar la skill `architect`).
6. **OpenSpec** — comprueba `openspec/` y si hay cambios activos en `openspec/changes/`. Si hay, lista el/los nombres (marca el `openspec_change_active` con `[activo]`) y el estado de sus `tasks.md` (cuantas tareas completadas vs pendientes).

## Formato de salida

Presenta como una tabla o lista markdown compacta:

```
## Estado IntermarkIt

**Proyecto:** PROJ (bitbucket / intermarkithub / rama default: main)
**Rama actual:** feature/PROJ-42-auth-login
**Tarea activa:** PROJ-42 · Testing · iniciada hace 45 min · 87 tool calls
**Cambio OpenSpec activo:** PROJ-42-add-auth-delta-1 (delta scope, delta 1/1)
**Gates:**
  verify_passed             ✓
  adversarial_verdict       ✓ (APROBADO)
  tests_passed              ✓
  coverage_ok               ✓
  quality_ok                ✓
  archived                  ✓
  local_validation_passed   ✗   ← pendiente hasta /im-accept
**Deltas archivados:** 1 (scope)
**Fixes aplicados:** 2
**Tokens:** input 1.9M · output 10K · total 1.96M · cache hit 77% · turns 3
**Coste estimado:** ≈ 5,23 €
**Context peak:** 120K tokens (85% del window), 2 compactaciones
**Cambios OpenSpec pendientes:**
  - PROJ-42-add-auth (archivado)
  - PROJ-42-add-auth-delta-1 [activo] (12/18 tareas)
**Docs:** architecture.md ok, functional.md ok
**Cache MCP:** user_info fresh (28d restantes), transitions.PROJ fresh (6d), bitbucket_verified stale
```

Omite las lineas de `Tokens`, `Coste estimado` y `Context peak` si el fichero no las tiene (tarea recien empezada o Cursor no ha disparado aun los hooks correspondientes).

**Variante multi-repo** — sustituye `**Proyecto:**`/`**Rama actual:**` por una linea por repo (o una linea `Repos:` compacta) y anade que repos toca la tarea activa:

```
**Proyecto:** PROJ
**Repos:** frontend (bitbucket/intermarkithub, main) → feature/PROJ-42-auth-login | backend (bitbucket/intermarkithub, main) → main
**Tarea activa:** PROJ-42 · Testing · 45 min · 87 tool calls · repos: frontend, backend
```

## Nota

Este comando es idempotente y readonly: no hace llamadas MCP, no crea ficheros, no modifica nada. Puede ejecutarse en cualquier momento sin efectos secundarios.

Es la primera herramienta a usar cuando el usuario pregunta "como vamos" o cuando el agente necesita recordar el estado tras una compactacion de contexto.
