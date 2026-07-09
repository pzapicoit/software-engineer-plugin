---
name: im-take
description: Toma una tarea Jira y prepara el entorno hasta el estado "Ready" con propuesta OpenSpec lista para revisar. Crea rama, inicializa metricas y ejecuta /opsx-propose. Argumento requerido - issue key (ej. PROJ-42).
---

# /im-take {ISSUE_KEY}

Toma una tarea Jira y la deja en estado `Ready` con propuesta OpenSpec generada y presentada al usuario (fase de arranque del workflow definido en `rules/intermarkit-global.mdc` §6.3 y `agents/software-engineer.md`).

## Cuando se invoca (frases naturales)

- `/im-take PROJ-42` (explicito)
- "trabaja en PROJ-42" / "toma esta tarea"
- "empezamos con PROJ-42"
- "vamos con la tarea X"

## Prerequisitos

- Se aplica la cascada de la regla global §2 (config del proyecto, credenciales, arquitectura docs, OpenSpec inicializado). No continues sin resolver §2.
- El prefijo del issue debe coincidir con `jira.project` del config.

## Pasos

1. **Leer issue** — Usa `getJiraIssue` (`cloudId` = `jira.site` del config, `issueIdOrKey` = argumento, `fields` = `["summary","description","status","issuetype","priority","labels","components","assignee"]`, `responseContentFormat = "markdown"`). Extrae y guarda los criterios de aceptacion (`- [ ]` / `- [x]` en la description) para `/im-accept`.
2. **Determinar tipo de rama** — `feature/` para stories, `bugfix/` para bugs no criticos, `hotfix/` para bugs criticos, segun `issuetype`.
3. **Slug** — 2-4 palabras del `summary` en kebab-case.
4. **Resolver repo(s)** — lee `repos` del payload de `sessionStart` (o `.intermarkit/config.yaml` si hace falta releer):
   - Si `is_multi_repo` es `false` (un solo repo, `repo:` legacy o `repos:` con un elemento): usa ese repo directamente, sin preguntar nada. `path` = `.` en el caso legacy.
   - Si `is_multi_repo` es `true`: **pregunta al usuario** que repo(s) de los configurados (`name` de cada entrada) afectan a esta tarea. Puede ser uno, varios o todos. Guarda la respuesta como lista de `name` para el paso 7.
5. **Crear rama** — para cada repo seleccionado (uno solo si es single-repo), usando su `path` (`.` en single-repo):
   ```bash
   git -C "{path}" checkout {default_branch}
   git -C "{path}" pull
   git -C "{path}" checkout -b {tipo}/{ISSUE_KEY}-{slug}
   ```
   Mismo nombre de rama en todos los repos seleccionados (regla §6.1 de la regla global).
6. **Transicionar Jira a `Ready`**:
   - Consulta cache `.intermarkit/cache/jira-transitions-{PROJECT}.json` (regla §7). Si `fresh`, usa el `transition_id` cacheado.
   - Si `stale`/`missing`: `getTransitionsForJiraIssue`, encuentra la transicion que lleve a `Ready` (o el equivalente en el workflow del proyecto, empareja por nombre con tolerancia a espacios/acentos), actualiza la cache (TTL 604800s / 7d).
   - `transitionJiraIssue` con el ID.
   - Si no existe transicion directa (por ejemplo el issue estaba en `Nueva` y solo hay refinamiento manual), informa al usuario y continua sin bloquear.
7. **Iniciar metricas**:
   - `mkdir -p .intermarkit/task-metrics`
   - Escribe `.intermarkit/task-metrics/{ISSUE_KEY}.json` con:
     ```json
     {
       "issue_key": "{ISSUE_KEY}",
       "started_at": "<ISO 8601 UTC>",
       "openspec_change": [],
       "openspec_change_active": null,
       "verification": {
         "verify_passed": false,
         "adversarial_verdict": null,
         "tests_passed": false,
         "coverage_ok": false,
         "quality_ok": false,
         "archived": false,
         "local_validation_passed": false,
         "exempt": false,
         "exempt_reason": null
       },
       "tool_calls": 0,
       "tokens": {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "turns": 0}
     }
     ```
     Si el proyecto es multi-repo, anade el campo `"repos": ["frontend", "backend"]` con los `name` seleccionados en el paso 4 (omitelo por completo en proyectos de un solo repo).

     El bloque `verification` es el gate tecnico que el hook `workflow-gate.sh` consulta antes de permitir `git push` (ver `agents/reference.md §Gate tecnico de workflow`). Se actualiza en cada paso del ciclo — mientras algun campo quede en `false`/`null`, el push se bloquea salvo que se marque `exempt: true` con `exempt_reason` (cambios triviales, regla global §3).
   - Escribe el pointer `.intermarkit/task-metrics/.active` con `{ISSUE_KEY}.json`. Esto habilita el modo O(1) de los hooks `postToolUse`, `stop`, `preCompact` y `sessionEnd`.
8. **Ejecutar `/opsx-propose`** con el nombre del cambio (`{ISSUE_KEY}-{slug-descriptivo}`, mas descriptivo que el slug de rama si hace falta). Actualiza el fichero de metricas:
   - `openspec_change`: `["{nombre-del-cambio}"]` (lista con un elemento).
   - `openspec_change_active`: `"{nombre-del-cambio}"`.
9. **Presentar la propuesta** — muestra un resumen de `proposal.md`, `specs/`, `design.md` y `tasks.md`. Da opinion tecnica (riesgos, alternativas, complejidad).
10. **Confirmar al usuario** — informa: rama creada (en que repo(s), si aplica), Jira en `Ready`, metricas iniciadas, criterios de aceptacion detectados (o "sin checklist"), propuesta OpenSpec presentada.
11. **Esperar aprobacion explicita** de la propuesta antes de continuar. Si el usuario pide cambios, vuelve a `/opsx-propose` sobre el mismo cambio (mismo nombre). Si aprueba, sugerir `/im-execute`.

## Nota

Este comando NO implementa: solo prepara el entorno y deja lista la propuesta OpenSpec para revision. La implementacion real ocurre en `/im-execute` (fase `En Progreso`).
