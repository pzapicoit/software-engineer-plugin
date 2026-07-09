---
name: im-done
description: Cierra definitivamente la tarea tras confirmar que el PR se ha mergeado. Transiciona Jira de Aceptacion a Done, anade comentario final y libera el pointer de tarea activa. Requiere confirmacion explicita del usuario del merge - nunca por iniciativa propia.
---

# /im-done

Cierra la tarea (transicion `Aceptacion -> Done` del workflow `rules/intermarkit-global.mdc` §6.3 y `agents/software-engineer.md`). Ocurre tras el merge del PR abierto en `/im-accept`.

## Cuando se invoca (frases naturales)

- `/im-done` (explicito)
- "el PR se mergeo" / "ya esta en main" / "esta en master"
- "cierralo" / "termina" / "hecho"
- "mergeado, cierralo"

Solo tiene sentido si la tarea esta en `Aceptacion` con PR(s) abierto(s) que se han mergeado en la rama por defecto (`main`, `master` o la configurada en el repo).

**Regla dura:** este comando NUNCA se ejecuta por iniciativa del agente. Requiere:
1. Que la tarea este en `Aceptacion` (o el usuario reconozca que quiere saltarse un estado, cosa rara).
2. Confirmacion **explicita** del usuario de que el PR esta mergeado. No basta con "creo que ya esta" o "parece que va bien"; hace falta una afirmacion inequivoca.

Si hay ambiguedad, pregunta con `AskQuestion` u ofrece consultar el estado del PR via MCP Bitbucket.

## Prerequisitos

- Existe una tarea activa (`.intermarkit/task-metrics/.active` apunta a un fichero valido). Si no, aborta e informa.
- La tarea esta en `Aceptacion` (o al menos ha pasado por `/im-accept` en algun momento — si esta en un estado anterior, informa y sugiere completar los pasos previos primero).
- **Confirmacion explicita del usuario** del merge del/los PR(s).

## Pasos

1. **Identificar tarea activa** — lee `.intermarkit/task-metrics/.active`. Obten `issue_key`, `repos` (si multi-repo), `openspec_change` (lista), `fixes[]`.
2. **Confirmar merge del PR** — si el usuario ha sido claro ("el PR se mergeo", "esta en main", "ya esta"), continua. Si tiene dudas ("creo que si", "parece que si"), ofrece verificarlo:
   - Ofrecele consultar el estado del PR via MCP Bitbucket (`bitbucketPullRequest get`) para cada PR abierto. Si el estado devuelto es `MERGED`, tienes confirmacion tecnica.
   - Si aun asi el usuario no puede confirmar (por ejemplo esta esperando al mergeo de otro), NO cierres la tarea. Dile que lo invoque cuando el PR este mergeado.
3. **Registrar detalles de PR mergeado** — para el comentario Jira, recopila:
   - URL del PR mergeado (o de cada PR, si multi-repo).
   - Hash del commit de merge si esta disponible.
4. **Transicionar Jira a `Done`**:
   - Consulta cache `.intermarkit/cache/jira-transitions-{PROJECT}.json` (regla §7). Si `fresh`, usa el `transition_id` cacheado.
   - Si `stale`/`missing`: `getTransitionsForJiraIssue`, encuentra la transicion a `Done` por nombre (empareja con tolerancia a espacios/acentos), actualiza cache (TTL 7d).
   - `transitionJiraIssue` con el ID.
   - Si no existe transicion directa `Aceptacion -> Done` (workflow con pasos intermedios), informa al usuario y usa la mas cercana disponible.
5. **Comentario Jira** — `addCommentToJiraIssue` con la plantilla `/im-done` de `agents/reference.md §Plantilla de comentario Jira — /im-done (Done, tras merge)`. Incluye:
   - Enlace(s) al PR mergeado (formato singular `**PR mergeado:**` para un repo, bloque `**PRs mergeados:**` para multi-repo).
   - Rama.
   - Confirmacion breve del cierre.
6. **Borrar pointer** — `rm .intermarkit/task-metrics/.active` (via Shell). Esto desactiva el hook `postToolUse` para esta tarea; los hooks `stop`/`preCompact`/`sessionEnd` tambien salen en modo no-op cuando `.active` no existe.
7. **Confirmar cierre** al usuario: issue en `Done`, comentario anadido, pointer liberado.
8. **Sugerir chat nuevo** para la siguiente tarea Jira distinta (regla §0.1). No continuar la nueva tarea en el chat actual.

## Nota

Si el usuario reporta un problema DESPUES de invocar `/im-done` (por ejemplo, descubre un bug en produccion tras el merge), NO se reabre la tarea Jira: se crea una tarea nueva (bug/hotfix) y se sigue el ciclo completo desde `/im-take`. Sugierele hacerlo en un chat nuevo (regla §0.1).
