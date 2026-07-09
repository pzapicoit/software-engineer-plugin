---
name: im-delta
description: Crea un delta OpenSpec desde Testing cuando la spec necesita cambiar (scope o funcional). Genera un cambio hermano `{original}-delta-N`, resetea el bloque verification completo y transiciona Jira de Testing a Ready para reiniciar el ciclo con la propuesta del delta.
---

# /im-delta

Ampliacion o modificacion de spec durante `Testing`. Crea un sibling OpenSpec, resetea el gate tecnico completo, y devuelve la tarea a `Ready` para pasar de nuevo por todo el ciclo (`/opsx-propose` -> aprobacion -> `/im-execute` -> `Testing`).

## Cuando se invoca (frases naturales)

- `/im-delta` (explicito)
- "cambia X a Y" / "hazlo diferente" / "prefiero que sea..."
- "falta Z" / "anade tambien..." / "y tambien..."
- "olvidamos..." / "no habiamos hablado de..."

**Cuando NO invocar `/im-delta`:**
- Si el usuario reporta un bug donde la spec estaba bien y la implementacion mal -> es `/im-fix`, no delta.
- Si hay duda, pregunta con `AskQuestion` presentando `/im-fix` vs `/im-delta`.

Solo tiene sentido cuando la tarea esta en `Testing`.

## Prerequisitos

- Existe una tarea activa (`.intermarkit/task-metrics/.active`).
- La tarea esta en `Testing`.
- `openspec_change_active` en el fichero de metricas apunta al cambio actualmente en `Testing`.

## Pasos

1. **Confirmar interpretacion y tipo del delta** — pregunta al usuario (o infiere de su frase) si es:
   - `scope`: falta algo en la spec (no se habia contemplado). Ej: "no hablamos de movil".
   - `functional`: cambio en algo que ya estaba especificado. Ej: "prefiero que el redirect sea a /dashboard en vez de /home".
   Si no queda claro, usa `AskQuestion`.
2. **Determinar nombre del delta** — `{openspec_change_active}-delta-{N}` donde `N` es el siguiente numero disponible (contar entradas en `deltas[]` del fichero de metricas + 1). Ejemplo: si el cambio activo es `PROJ-42-add-user-auth` y ya hay un delta previo, el nuevo se llama `PROJ-42-add-user-auth-delta-2`.
3. **Ejecutar `/opsx-propose`** con el nombre del delta. La propuesta debe describir SOLO el delta (no la funcionalidad original que ya esta archivada). En `proposal.md` incluye un metadato al principio:
   ```
   ---
   type: scope | functional
   parent: {openspec_change original, primer elemento de la lista}
   reason: {razon breve del delta segun el usuario}
   ---
   ```
   El metadato es informativo; no altera el flujo del comando.
4. **Actualizar el fichero de metricas** — `.intermarkit/task-metrics/{ISSUE_KEY}.json`:
   - Anade el nombre del delta al final de la lista `openspec_change`.
   - Cambia `openspec_change_active` al nombre del delta.
   - Anade una entrada a `deltas[]` (si el campo no existe, crealo):
     ```json
     {
       "name": "{nombre-del-delta}",
       "type": "scope" | "functional",
       "reason": "{razon breve}",
       "created_at": "<ISO 8601 UTC>"
     }
     ```
   - **Resetea el bloque `verification` completo** a `false`/`null` (todos los campos: `verify_passed`, `adversarial_verdict`, `tests_passed`, `coverage_ok`, `quality_ok`, `archived`, `local_validation_passed`). El delta se reverifica desde cero: la spec cambia, todo lo anterior deja de valer.
5. **Transicionar Jira de `Testing` a `Ready`** — cache de transiciones. Si no existe transicion directa `Testing -> Ready` (workflow con pasos intermedios), informa al usuario y usa la mas cercana disponible o pide transicion manual.
6. **Comentario Jira** — plantilla `/im-delta` de `agents/reference.md` (delta creado, tipo, razon).
7. **Presentar la propuesta** del delta al usuario. Da opinion tecnica (impacto sobre el original, riesgos, si complica el archive final, etc.). Espera aprobacion explicita.
8. **Ciclo repetido** — cuando el usuario apruebe, invita a `/im-execute` para arrancar la fase `En Progreso` sobre el delta. El ciclo es identico al de la propuesta original.

## Aceptacion final tras deltas

Cuando la tarea llega a `Aceptacion` (via `/im-accept`) tras uno o mas deltas, el comportamiento es:

- Se archiva el `openspec_change_active` (el delta actual, no el original).
- El PR acumula todos los commits del original + deltas + fixes (misma rama).
- El comentario Jira lista TODOS los cambios OpenSpec archivados y el numero de fixes.

Ver `commands/im-accept.md` para el detalle.

## Nota

No hay limite tecnico al numero de deltas. En la practica, si una tarea acumula muchos deltas (mas de 3-4), suele ser senal de que el refinamiento inicial fue insuficiente y valdria la pena partirla en varias tareas Jira. Comentaselo al usuario si lo detectas.
