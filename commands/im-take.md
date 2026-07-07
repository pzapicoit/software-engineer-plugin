---
name: im-take
description: Ejecuta la Fase A del workflow IntermarkIt: crea rama desde default_branch, transiciona el issue Jira a "In Progress" y arranca metricas de tarea. Argumento requerido: issue key (ej. PROJ-42).
---

# /im-take {ISSUE_KEY}

Toma una tarea Jira y prepara el entorno (Fase A del workflow definido en `rules/intermarkit-global.mdc` §6.3 y `agents/software-engineer.md` §Fase A).

## Prerequisitos

- Se aplica la cascada de la regla global §2 (config del proyecto, credenciales, arquitectura docs, OpenSpec inicializado). No continues sin resolver §2.
- El prefijo del issue debe coincidir con `jira.project` del config.

## Pasos

1. **Leer issue** — Usa `getJiraIssue` (`cloudId` = `jira.site` del config, `issueIdOrKey` = argumento, `fields` = `["summary","description","status","issuetype","priority","labels","components","assignee"]`, `responseContentFormat = "markdown"`). Extrae y guarda los criterios de aceptacion (`- [ ]` / `- [x]` en la description) para la Fase C.
2. **Determinar tipo de rama** — `feature/` para stories, `bugfix/` para bugs no criticos, `hotfix/` para bugs criticos, segun `issuetype`.
3. **Slug** — 2-4 palabras del `summary` en kebab-case.
4. **Crear rama**:
   ```bash
   git checkout {default_branch}
   git pull
   git checkout -b {tipo}/{ISSUE_KEY}-{slug}
   ```
5. **Transicionar Jira a "In Progress"**:
   - Consulta cache `.intermarkit/cache/jira-transitions-{PROJECT}.json` (regla §7). Si `fresh`, usa el `transition_id` cacheado.
   - Si `stale`/`missing`: `getTransitionsForJiraIssue`, encuentra la que lleve a "In Progress" por nombre, actualiza la cache (TTL 604800s / 7d).
   - `transitionJiraIssue` con el ID.
   - Si no existe transicion, informa y continua.
6. **Iniciar metricas**:
   - `mkdir -p .intermarkit/task-metrics`
   - Escribe `.intermarkit/task-metrics/{ISSUE_KEY}.json` con:
     ```json
     {
       "issue_key": "{ISSUE_KEY}",
       "started_at": "<ISO 8601 UTC>",
       "tool_calls": 0,
       "tokens": {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "turns": 0}
     }
     ```
   - Escribe el pointer `.intermarkit/task-metrics/.active` con `{ISSUE_KEY}.json`. Esto habilita el modo O(1) de los hooks `postToolUse`, `stop`, `preCompact` y `sessionEnd`.
7. **Confirmar al usuario** — rama creada, Jira en "In Progress", metricas iniciadas, criterios de aceptacion detectados (o "sin checklist").
8. **Sugerir siguiente paso** — continuar con la Fase B (`/opsx-propose` para spec-driven, o analisis directo si el requisito es claro).

## Nota

Este comando NO implementa: solo prepara el entorno. La implementacion sigue el ciclo OpenSpec de Fase B.
