---
name: im-accept
description: Acepta el feature tras validacion local del usuario. Marca local_validation_passed, hace commit + push + crea PR + archiva OpenSpec + marca criterios Jira + transiciona a Aceptacion + comentario con metricas. Ultimo paso antes del merge del PR.
---

# /im-accept

Transiciona la tarea de `Testing` a `Aceptacion` (reemplaza al antiguo `/im-close`). El usuario ha validado el feature en local; ahora se sube a remoto (push + PR) y se archiva el cambio OpenSpec activo.

## Cuando se invoca (frases naturales)

- `/im-accept` (explicito)
- "funciona" / "esta ok" / "todo bien"
- "aceptalo" / "sube esto" / "manda el PR"
- "cierra esta parte"

Solo tiene sentido si la tarea esta en `Testing` con TODOS los gates de calidad del bloque `verification` en verde (excepto `local_validation_passed`, que es el que marca este comando).

## Prerequisitos

- Existe una tarea activa (`.intermarkit/task-metrics/.active`).
- La tarea esta en `Testing`.
- El bloque `verification` tiene: `verify_passed = true`, `adversarial_verdict = "APROBADO"`, `tests_passed = true`, `coverage_ok = true`, `quality_ok = true`, `archived = true` (o `exempt = true` con razon). Solo falta `local_validation_passed`.
- **Confirmacion explicita del usuario** de que el feature funciona en local. Si no ha sido clara la confirmacion, pregunta con `AskQuestion` antes de ejecutar (el push + PR es una accion destructiva/costosa; no la ejecutes por adivinar).

Si algun gate no esta en verde, aborta e informa al usuario del gate que falta. Ese caso se resuelve en `/im-execute` (o `/im-fix` si es un bug detectado en `Testing`), no en `/im-accept`.

## Pasos

1. **Identificar tarea activa** — lee `.intermarkit/task-metrics/.active`. Obten `issue_key`, `openspec_change` (lista), `openspec_change_active`, `deltas[]`, `fixes[]` y, si es multi-repo, `repos`.
2. **Marcar `verification.local_validation_passed = true`** en el fichero de metricas. Esto libera el gate tecnico (`hooks/workflow-gate.sh`) para permitir el push del siguiente paso.
3. **Archivar el cambio OpenSpec en curso** — `/opsx-archive` sobre `openspec_change_active`. Si viene de un delta y hay deltas previos ya archivados, encadena la logica del archive segun proceda. Tras archivar con exito, `verification.archived = true`.
4. **Actualizar docs** — si el cambio (o alguno de sus deltas) introdujo modulo/dependencia/decision arquitectonica relevante, actualiza `.intermarkit/architecture.md` / `functional.md` (skill `architect` §Mantenimiento).
5. **Commit final + push** — si el fichero de metricas trae `repos` (multi-repo), repite en CADA repo tocado usando su `path`. Si no hay `repos`, ejecuta una vez en la raiz:
   ```bash
   git -C "{path}" status
   git -C "{path}" add -A  # si hay cambios pendientes en ese repo
   git -C "{path}" commit -m "{ISSUE_KEY}:tipo: descripcion final"  # si es necesario
   git -C "{path}" push -u origin HEAD
   ```
   Si un repo de la lista no tiene cambios pendientes, omite el commit/push de ese repo.

   El hook `workflow-gate.sh` permite este push porque `local_validation_passed` esta en `true` y todos los demas gates estan verdes.
6. **Crear PR(s)** — `bitbucketPullRequest create`, uno por cada repo que recibio push:
   - Titulo: commit message principal (formato convencional).
   - Descripcion: extraida de `proposal.md` del cambio original. Anade secciones "Deltas aplicados" y "Fixes aplicados durante Testing" segun el schema de `agents/reference.md §PRs`. Omite secciones vacias.
   - Usa el `workspace`/repositorio propio de cada repo (nunca el de otro repo de la lista).
   - Si MCP Bitbucket no esta disponible, informa la URL del repo para creacion manual.

   Si el push del paso 5 fue una actualizacion sobre una rama que YA tenia un PR abierto de una iteracion anterior (por ejemplo `/im-accept` -> delta -> `/im-accept`), NO crees un PR nuevo: el push actualiza automaticamente el PR existente. Puedes anadir un comentario al PR resumiendo el delta si aporta.
7. **Marcar criterios de aceptacion en Jira** — si el issue tenia `- [ ]` en la description:
   - Relee la description actual con `getJiraIssue` (puede haber cambiado desde `/im-take`).
   - Reescribe cambiando `- [ ]` a `- [x]` solo en criterios realmente implementados y cubiertos por los cambios archivados (original + deltas).
   - `editJiraIssue` con `fields: {"description": "..."}`, `contentFormat: "markdown"`.
   - Nunca marcar criterios a medias.
8. **Transicionar Jira a `Aceptacion`** — cache de transiciones. Si no existe transicion directa (workflow con pasos intermedios), usa la mas cercana disponible y avisa.
9. **Calcular metricas** — lee `.intermarkit/task-metrics/{ISSUE_KEY}.json`:
   - Tiempo: `started_at` vs `date -u +%Y-%m-%dT%H:%M:%SZ` (no dependas de `elapsed_ms`, lo rellena `sessionEnd` al cerrar el chat).
   - Tool calls: `tool_calls`.
   - Tokens: bloque `tokens` (`input`, `output`, `cache_read`, `cache_write`, `turns`).
   - Total y coste estimado: `agents/reference.md §Total de tokens y coste estimado` (one-liner Python recomendado).
   - Context peak: bloque `context_peak` si existe.
   - Deltas archivados: numero de elementos de `openspec_change` (la lista) menos 1 (el original) = numero de deltas. Si es 0, "sin deltas".
   - Fixes aplicados: numero de elementos de `fixes[]` (0 si no existe).
10. **Comentario Jira** — `addCommentToJiraIssue` con la plantilla `/im-accept` de `agents/reference.md`. Incluye tiempo, tool calls, tokens (M/K + cache hit %), total, coste estimado en € (prefijo `≈`), context peak si existe, lista de deltas archivados y numero de fixes. Si `repos` tiene mas de un elemento, usa el bloque `**PRs:**` con un enlace por repo.
11. **NO borrar el pointer `.active`** — la tarea sigue activa. Se queda en `Aceptacion` esperando el merge del PR y el `/im-done` posterior. El pointer se borra en `/im-done`.
12. **Confirmar cierre parcial** al usuario:
    - Rama(s) pusheada(s) + PR(s) creado(s) o actualizado(s).
    - Issue en `Aceptacion`.
    - N de M criterios marcados.
    - Tiempo, tool calls, coste estimado.
    - Deltas + fixes acumulados.
    - Indica el siguiente paso: `/im-done` cuando el PR se mergee.

## Nota

Si el veredicto adversarial fue `RECHAZADO CON HALLAZGOS` (o `adversarial_verdict != "APROBADO"`), NO ejecutes este comando: vuelve a `/im-execute` (o el paso adversarial dentro de el) hasta que salga `APROBADO`.

Si el usuario dice "aceptalo" pero el bloque `verification` tiene gates en rojo distintos de `local_validation_passed`, NO fuerces: informa que falta X gate, sugiere `/im-execute` para completarlo o `/im-fix` si el bug fue reportado durante testing.
