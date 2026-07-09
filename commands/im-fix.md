---
name: im-fix
description: Corrige un bug detectado por el usuario durante Testing. La spec no cambia, por eso no crea sibling OpenSpec ni mueve el estado Jira. Resetea los gates de calidad afectados, ejecuta un mini-ciclo apply+verify+tests+coverage+quality, y vuelve a Testing para que el usuario reprueve.
---

# /im-fix

Correccion de bug durante `Testing`. La spec estaba bien, la implementacion no. Se resetean los gates de calidad, se aplica el fix, se reverifica y se deja la tarea de nuevo en `Testing`.

## Cuando se invoca (frases naturales)

- `/im-fix` (explicito)
- "vi este error" / "hay un bug" / "no funciona bien"
- "no hace lo que dijimos" / "esto no va como deberia"
- "esto peta cuando..." / "el X esta roto"

Solo tiene sentido cuando la tarea esta en `Testing`. Si esta en `Aceptacion` (PR ya abierto) y el usuario reporta un bug, tambien se ejecuta `/im-fix`: el push posterior actualizara el PR automaticamente sobre la misma rama.

**Cuando NO invocar `/im-fix`:**
- Si el usuario dice "cambia X a Y" o "falta Z" -> es un cambio de spec, no un bug. Usa `/im-delta`.
- Si el usuario esta contento con la implementacion pero pide algo extra -> es scope, `/im-delta`.
- Si hay duda, pregunta con `AskQuestion` presentando `/im-fix` vs `/im-delta`.

## Prerequisitos

- Existe una tarea activa (`.intermarkit/task-metrics/.active`).
- La tarea esta en `Testing` (o `Aceptacion` con PR abierto).
- `openspec_change_active` en el fichero de metricas apunta al cambio en curso.

## Pasos

1. **Confirmar interpretacion** — resume al usuario que has entendido como bug ("la spec dice X pero la implementacion hace Y") y que vas a corregir sin cambiar la spec. Si el usuario confirma o el contexto es claro, sigue. Si duda, ofrece `/im-delta` como alternativa (`AskQuestion`).
2. **Resetear gates afectados** en el bloque `verification` del fichero de metricas:
   - `verify_passed = false` (el codigo va a cambiar, la verificacion anterior ya no vale).
   - `tests_passed = false`, `coverage_ok = false`, `quality_ok = false` (por seguridad; si el fix es minusculo se validan rapido).
   - **NO tocar** `adversarial_verdict` (sigue siendo `"APROBADO"`; la spec no cambia, la revision adversarial del spec sigue valida).
   - **NO tocar** `archived` (el cambio OpenSpec sigue archivado; el fix no crea uno nuevo).
   - **NO tocar** `local_validation_passed` (si venia de `Aceptacion`, se mantiene; si venia de `Testing`, ya estaba en `false`).
3. **Aplicar el fix** — puede ser codigo directo o `/opsx-apply` si toca elementos que OpenSpec ya coordina. Commits convencionales con `PROJ-XXX:fix: descripcion breve`.
4. **`/opsx-verify`** — si pasa, `verify_passed = true`. Si no, corrige y repite.
5. **Tests + cobertura + quality** — pasos 6-8 de `/im-execute` (ejecutar tests, comprobar umbral de cobertura, quality gates). Cuando cada uno pase, marca su campo en `verification` a `true`.
6. **Registrar el fix** en `fixes[]` del fichero de metricas. Si el campo no existe, crealo. Anade una entrada:
   ```json
   {
     "description": "descripcion breve del bug corregido",
     "gates_reset": ["verify_passed", "tests_passed", "coverage_ok", "quality_ok"],
     "timestamp": "<ISO 8601 UTC>"
   }
   ```
7. **NO cambiar el estado Jira**. La tarea sigue en `Testing` (o `Aceptacion` si venia de ahi). Ningun `transitionJiraIssue`.
8. **Comentario Jira opcional** — para fixes significativos, plantilla `/im-fix` de `agents/reference.md`. Para fixes triviales (typo, padding), se puede omitir el comentario individual y acumular todo en el resumen final de `/im-accept` (via `fixes[]`).
9. **Notificar al usuario** — informa: gates que se re-comprobaron y pasaron, y pide que vuelva a probar. Recuerda las opciones desde `Testing`: `/im-accept`, otro `/im-fix`, o `/im-delta`.

## Nota

Si un "fix" empieza a arrastrar cambios de spec (por ejemplo el usuario dice "arreglalo, y ya que estas cambia tambien X"), detente y sugiere convertirlo en `/im-delta`. Mantener los bugs como fixes rapidos y los cambios de spec como deltas es lo que evita que el gate de calidad y el archive OpenSpec se descoordinen.
