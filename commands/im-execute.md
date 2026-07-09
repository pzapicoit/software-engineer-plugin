---
name: im-execute
description: Ejecuta la propuesta OpenSpec aprobada. Transiciona Jira de Ready a En Progreso, aplica el cambio, corre verify + revision adversarial + tests + cobertura + quality gates, y al terminar transiciona a Testing esperando prueba manual del usuario.
---

# /im-execute

Fase de implementacion del workflow IntermarkIt (`rules/intermarkit-global.mdc` §6.3, `agents/software-engineer.md`). Ejecuta el cambio OpenSpec activo con todos los gates de calidad y deja la tarea en `Testing` para que el usuario pruebe en local.

## Cuando se invoca (frases naturales)

- `/im-execute` (explicito)
- "adelante" / "ejecuta" / "hazlo" / "dale" / "empieza"
- "aplica la propuesta" / "implementa esto"

Solo tiene sentido si el estado Jira actual es `Ready` y ya hay una propuesta OpenSpec aprobada (`openspec_change_active` presente en el fichero de metricas).

## Prerequisitos

- Existe una tarea activa (`.intermarkit/task-metrics/.active` apunta a un fichero valido).
- La tarea esta en `Ready` con propuesta OpenSpec aprobada por el usuario.
- `.intermarkit/architecture.md` declara las herramientas de tests, cobertura y quality gates del proyecto (skill `architect` §Mantenimiento, o §2.4 de la regla global).

## Pasos

1. **Identificar tarea activa** — lee `.intermarkit/task-metrics/.active`. Obten `issue_key` y `openspec_change_active` del JSON asociado. Si no hay `openspec_change_active`, aborta e informa al usuario que primero hace falta `/im-take` (con propuesta aprobada).
2. **Transicionar Jira a `En Progreso`**:
   - Consulta cache `.intermarkit/cache/jira-transitions-{PROJECT}.json` (regla §7).
   - Si `stale`/`missing`, `getTransitionsForJiraIssue`, encuentra la transicion a `En Progreso` (empareja por nombre con tolerancia a espacios/acentos), actualiza cache.
   - `transitionJiraIssue` con el ID.
3. **`/opsx-apply`** sobre `openspec_change_active`. Genera commits parciales convencionales (formato `PROJ-XXX:tipo: descripcion`) en el repo correspondiente. Si es multi-repo (`repos` en el fichero de metricas), aplica los cambios de forma coherente en cada repo tocado; los commits pueden dividirse por repo segun corresponda.
4. **`/opsx-verify`** — si pasa sin errores, escribe `verification.verify_passed = true` en el fichero de metricas. Si no, corrige el codigo y repite. No sigas hasta que verify pase.
5. **Subagente `adversarial-reviewer`** — lanza el subagente (Task tool) con el nombre del cambio.
   - Veredicto `APROBADO`: escribe `verification.adversarial_verdict = "APROBADO"`.
   - Veredicto `RECHAZADO CON HALLAZGOS` (o cualquier otro): corrige, resetea `verify_passed = false` (el codigo cambio), vuelve al paso 4 y repite hasta que sea `APROBADO`.
   - Excepciones a esta obligatoriedad: solo las de la regla §3 (typos, deps menores, docs). Si aplica una excepcion, en vez de ejecutar adversarial marca `verification.exempt = true` con `exempt_reason` breve.
6. **Tests unitarios** — ejecuta la suite del proyecto segun `.intermarkit/architecture.md`. Si pasa, `verification.tests_passed = true`. Si no, corrige (arreglar codigo o tests, segun proceda) y repite; cualquier cambio de codigo requiere resetear `verify_passed` y volver al paso 4.
7. **Cobertura** — corre la herramienta de cobertura del proyecto y compara con el umbral declarado en `.intermarkit/architecture.md`. Si cumple, `verification.coverage_ok = true`. Si no, anade tests para cerrar el hueco y vuelve al paso 6.
8. **Quality gates** — linter, formatter, type-checker segun `.intermarkit/architecture.md`. Si todos pasan sin errores, `verification.quality_ok = true`. Si no, corrige.
9. **`/opsx-archive`** — solo con verify + adversarial APROBADO + tests + coverage + quality todos OK (o `exempt: true`). Tras archivar con exito, `verification.archived = true`.
10. **Transicionar Jira a `Testing`** — cache de transiciones, misma mecanica.
11. **Notificar al usuario** — informa:
    - Que gates pasaron (con marca ✓ por cada uno).
    - Rama, cambios aplicados.
    - Pide que pruebe el feature en local (levantar la app, ejecutar el flujo, etc.).
    - Indica los tres caminos disponibles desde `Testing`:
      - "funciona" / `/im-accept` -> Aceptacion (push + PR).
      - "vi este error" / `/im-fix` -> mini-ciclo para bugs (spec no cambia).
      - "falta X" / "cambia Y" / `/im-delta` -> nuevo delta con propuesta (spec cambia).

## Nota

El hook `workflow-gate.sh` bloqueara cualquier `git push` mientras algun gate del bloque `verification` este pendiente. En Testing no hay que hacer push; el push ocurre en `/im-accept` una vez el usuario valide localmente.

Si estas re-ejecutando `/im-execute` sobre un delta (Ready → En Progreso desde `/im-delta`), el proceso es exactamente el mismo: el `openspec_change_active` apunta ahora al delta, y el bloque `verification` se ha reseteado en `/im-delta`, por lo que TODOS los gates se vuelven a exigir desde cero.
