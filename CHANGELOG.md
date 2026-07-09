# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versiones semanticas.

## [1.0.0] — 2026-07-09

**Breaking change.** Rediseno completo del workflow como maquina de estados Jira de 6 posiciones con ciclo formal de deltas, gate tecnico ampliado y enrutamiento por lenguaje natural. Requiere:

1. Configurar el workflow Jira del proyecto con los estados `Nueva`, `Ready`, `En Progreso`, `Testing`, `Aceptacion`, `Done` (empareja por nombre con tolerancia a espacios/acentos).
2. Actualizar `.intermarkit/architecture.md` para declarar herramientas y umbrales de tests, cobertura y quality gates (los consultan `/im-execute` y `/im-fix`).

Los proyectos existentes con tareas en curso siguen funcionando: el bloque `verification` de sus ficheros de metricas no tiene los campos nuevos y el hook `workflow-gate.sh` los trata como `true` (comportamiento antiguo).

### Added

- **Estados Jira: workflow de 6 posiciones** — `Nueva -> Ready -> En Progreso -> Testing -> Aceptacion -> Done`. Cada estado tiene un dueno, un comando de entrada y una accion definida en `rules/intermarkit-global.mdc §6.3` y `agents/software-engineer.md`.
- **Ciclo formal de `fix` y `delta` desde Testing:**
  - `/im-fix` — para bugs (la spec era correcta, la implementacion no). Mini-ciclo `apply + verify + tests + coverage + quality` sin sibling OpenSpec. Mantiene Jira en `Testing`. Se registra en un nuevo array `fixes[]` del fichero de metricas.
  - `/im-delta` — para cambios de spec (scope o funcional). Crea sibling OpenSpec `{original}-delta-{N}` con metadato `type: scope | functional`, resetea `verification` completo, transiciona Jira de `Testing` a `Ready` y reinicia el ciclo. Se registra en un nuevo array `deltas[]` del fichero de metricas.
  - Los deltas se pueden encadenar libremente (`Testing -> Ready -> En Progreso -> Testing -> ...`). El PR acumula todos los cambios en la misma rama.
- **Comandos nuevos:**
  - `/im-execute` — Ready → En Progreso → Testing con `apply` + `verify` + revision adversarial + tests + cobertura + quality gates. Al terminar todos verdes, transiciona automaticamente a `Testing`.
  - `/im-fix` — Testing loop (bug, spec correcta).
  - `/im-delta` — Testing → Ready (nuevo sibling OpenSpec, spec cambia).
  - `/im-accept` — Testing → Aceptacion. Reemplaza a `/im-close` (renombrado, ver Removed). Marca `local_validation_passed`, hace commit + push + PR + archive + criterios Jira + comentario con metricas.
- **`/im-take` cambia de rol:** ya no lleva a `In Progress`. Ahora mueve Jira a `Ready`, crea rama, inicializa metricas y ejecuta `/opsx-propose` presentando la propuesta al usuario para revision.
- **`/im-done` cambia de rol:** ya no cierra la tarea solo con la palabra del usuario. Ahora requiere confirmacion **explicita** de que el PR se ha mergeado. Ofrece verificar el estado del PR via MCP Bitbucket si el usuario tiene dudas.
- **`/im-status` ampliado:** muestra estado Jira, gates del bloque `verification` con marca visual (✓/✗), numero de deltas archivados, numero de fixes aplicados, cambio OpenSpec activo.
- **Gate tecnico ampliado (`hooks/workflow-gate.sh`).** El bloque `verification` del fichero de metricas anade cuatro campos nuevos que el gate exige antes de permitir `git push`:
  - `tests_passed` — suite de tests unitarios pasa.
  - `coverage_ok` — cobertura cumple el umbral definido en `.intermarkit/architecture.md`.
  - `quality_ok` — linter/formatter/type-checker pasan sin errores.
  - `local_validation_passed` — el usuario ha confirmado en `Testing` que el feature funciona en local (lo marca `/im-accept`).
  El gate exige TODOS ellos (mas los tres antiguos: `verify_passed`, `adversarial_verdict == "APROBADO"`, `archived`) en verde, o `exempt: true` con razon.
- **Enrutamiento por lenguaje natural** (nueva §10 en `rules/intermarkit-global.mdc`): el agente mapea frases naturales a comandos segun el estado Jira actual. Ejemplos:
  - "vi este error" en `Testing` → `/im-fix`; en `Done` → sugerir crear tarea nueva.
  - "falta X" / "cambia Y" en `Testing` → `/im-delta`.
  - "funciona" / "aceptalo" en `Testing` → `/im-accept`.
  - "el PR se mergeo" en `Aceptacion` → `/im-done`.
  - "adelante" / "ejecuta" en `Ready` → `/im-execute`.
  Reglas de desambigüacion: `AskQuestion` cuando la frase es ambigua, confirmacion explicita antes de acciones destructivas (`/im-accept`, `/im-done`), aviso si el estado Jira no permite la accion.
- **Metricas ampliadas:** `openspec_change` pasa a ser una **lista** de nombres de cambios OpenSpec (original + deltas). Nuevos campos `openspec_change_active`, `deltas[]`, `fixes[]`. Compat hacia atras: si `openspec_change` es un string (fichero antiguo), se trata como lista de un elemento.
- **Paso 0 del agente `software-engineer`**: "Interpretar la peticion" ANTES del Paso 1. Lee el estado de la tarea activa y consulta §10 de la regla global para elegir el comando adecuado o pedir confirmacion si es ambiguo.
- **Plantillas de comentario Jira** por transicion en `agents/reference.md`: `/im-accept`, `/im-fix` (opcional), `/im-delta`, `/im-done`. La de `/im-accept` incluye lista de deltas archivados y numero de fixes.
- **Skill `architect` — responsabilidad adicional:** documentar en `.intermarkit/architecture.md` las herramientas y umbrales de tests unitarios, cobertura y quality gates que consultan `/im-execute` y `/im-fix`. El plugin no impone herramientas — cada proyecto declara las suyas.

### Changed

- **Nombre de las fases:** `Fase A/B/C/D` (con "In Progress" y "In Testing" en Jira) se sustituye por los seis estados Jira actuales. `/im-take` ya no cubre "Fase A completa" sino solo la fase `Ready` (crear rama, propuesta pendiente de aprobar). La antigua "Fase D" (validacion humana con fix menor/significativo) queda formalizada en el par `/im-fix` + `/im-delta`.
- **Momento del push:** antes ocurria en `/im-close` (equivalente a `In Progress -> In Testing`), ANTES de la validacion humana. Ahora ocurre en `/im-accept` (equivalente a `Testing -> Aceptacion`), DESPUES de la validacion humana. Nada llega a remoto sin que el desarrollador haya probado el feature en local.
- **Momento del cierre en Jira:** antes `/im-done` cerraba la tarea a `Done` solo con "el usuario dice que funciona". Ahora requiere confirmacion explicita del merge del PR.
- **Cache de transiciones Jira** (`.intermarkit/cache/jira-transitions-{PROJECT}.json`): pasa a mapear los seis estados nuevos. Compat hacia atras: al primer uso el agente rellena el mapa con lo que devuelva `getTransitionsForJiraIssue` y empareja por nombre con tolerancia.
- **`agents/software-engineer.md`**: reescrito completo. Nuevo diagrama mermaid, Paso 0 de interpretacion, secciones organizadas por estado Jira (no por fase), reglas inquebrantables ampliadas (14 y 15 nuevas sobre `/im-fix` vs `/im-delta` y enrutamiento NL).
- **`agents/reference.md`**: schema `verification` ampliado con los 4 campos nuevos, schema de metricas con `deltas[]` y `fixes[]`, plantillas de comentario por transicion, tabla de estados Jira con quien dispara cada transicion.
- **`rules/intermarkit-global.mdc`**: §2.7 (estados Jira esperados), §3 reescrita (workflow con deltas), §3.1 (gate ampliado), §6.3 (tabla de fases por estado), §9 (tabla completa de comandos), §10 nueva (enrutamiento por lenguaje natural).
- **`README.md`**: seccion "Workflow" reescrita con los 6 estados, ciclo de deltas, tabla de comandos actualizada, seccion "Gate tecnico" con los 7 gates.

### Removed

- **`/im-close`** — renombrado a `/im-accept`. Cambia de rol: no solo hace push + PR + comentario, ahora tambien marca `local_validation_passed` y archiva el cambio OpenSpec. `commands/im-close.md` eliminado.
- **Concepto de "Fase D"** en la documentacion — sustituido por el ciclo formal `/im-fix` + `/im-delta` desde el estado `Testing`.

### Migracion desde 0.6.x

Tareas en curso (`.intermarkit/task-metrics/{ISSUE_KEY}.json` existente):

- **Tareas ya cerradas:** ninguna accion. Los ficheros antiguos se preservan tal cual.
- **Tareas en In Progress (formato antiguo)**: el usuario decide manualmente si:
  - (a) Continuar con el flujo antiguo (`/im-close` no existe; usar `/im-accept` que hara el equivalente, salvo que no se exigen los nuevos gates porque el bloque `verification` no los tiene → el hook los trata como `true`).
  - (b) Cerrar el ciclo actual manualmente y arrancar tareas nuevas con el nuevo flujo.
- **El hook `workflow-gate.sh` sigue funcionando** con ficheros antiguos: si el campo nuevo no existe en `verification`, lo trata como `true`. Las tareas antiguas solo veran exigidos los gates que ya tenian (`verify_passed`, `adversarial_verdict`, `archived`).

**`.cursor-plugin/plugin.json`** — bump `0.6.0 → 1.0.0` (breaking).

## [0.4.0] — 2026-07-08

### Added

- **Soporte multi-repo en la configuracion del proyecto.** Un proyecto puede tener uno o varios repositorios Git (ej: frontend, backend, mobile) en subcarpetas de la raiz del proyecto:
  - Nuevo schema `repos:` (lista) en `.intermarkit/config.yaml`, cada entrada con `name`, `path` (subcarpeta), `type`, `url`, `workspace` (solo bitbucket) y `default_branch`. Convive con el schema legacy `repo:` (singular, un solo repositorio) — si ambos existen, `repos:` tiene prioridad. Documentado y con ejemplo comentado en `config-template.yaml`.
  - **`hooks/session-context.sh`** — normaliza cualquiera de los dos formatos en `payload["repos"]` (lista, siempre presente) y `payload["is_multi_repo"]`; calcula la rama actual de cada repo con `git -C`. El parser YAML minimo (fallback sin PyYAML) se ha extendido para soportar listas de mapeos (necesario para `repos:`), no solo mapeos anidados.
  - **`/im-take`, `agents/software-engineer.md` (Fase A)** — si el proyecto es multi-repo, el agente pregunta al usuario que repo(s) configurados afectan a la tarea antes de crear rama; la seleccion se guarda en `.intermarkit/task-metrics/{ISSUE_KEY}.json` (`repos: ["frontend", "backend"]`) para no repetir la pregunta en el cierre. Mismo nombre de rama en todos los repos seleccionados.
  - **`/im-close`, `agents/software-engineer.md` (Fase C)** — commit/push independiente por repo tocado (se omiten los repos sin cambios) y un Pull Request por repo contra su propio `workspace`/URL. El comentario Jira de cierre usa un bloque `**PRs:**` (uno por repo) cuando hay mas de un repo, o la linea singular `**PR:**` si solo hay uno.
  - **`/im-status`** — muestra la rama actual de cada repo configurado y que repos toca la tarea activa.
  - **`rules/intermarkit-global.mdc`** — nueva §2.3bis con el schema completo, precedencia `repos:` > `repo:`, convenciones de ramas/PRs multi-repo y regla de "preguntar siempre que repos afectan a la tarea"; §2.6 (verificacion Bitbucket) ahora se dispara si ALGUN repo configurado es bitbucket, no solo el unico repo legacy.
  - **`agents/reference.md`** — documenta el campo opcional `repos` en el schema de metricas de tarea, la plantilla de PR/comentario Jira en variante multi-repo y la regla de no mezclar `workspace`/repositorio entre repos al llamar a las herramientas MCP Bitbucket.
  - Proyectos de un solo repositorio (la mayoria) no cambian de comportamiento: no se pregunta nada nuevo, todo sigue ocurriendo en la raiz del proyecto.
- **`README.md`** — nueva seccion "Multi-repo" con ejemplo de configuracion y explicacion del flujo.
- **`.cursor-plugin/plugin.json`** — bump a `0.4.0` (funcionalidad nueva, no rompe compatibilidad).

## [0.3.5] — 2026-07-08

### Added

- **Total de tokens y coste estimado en €** en todos los reportes de metricas (comentario Jira de `/im-close`, `/im-status`, instrucciones de Fase C del agente `software-engineer`):
  - `total = tokens.input + tokens.output` (nueva formula documentada en `agents/reference.md §Total de tokens y coste estimado`; `input` ya incluye `cache_read`+`cache_write`, no se duplican).
  - Coste estimado en € a partir de una tabla de precios por modelo (USD/1M tokens, tarifas de lista aproximadas para `claude-4.6-sonnet-medium-thinking` y `composer-2.5`, con fallback para modelos no listados) y una tasa fija USD->EUR (0.92). Se recomienda un one-liner Python via Shell para el calculo exacto.
  - Siempre se presenta con el prefijo `≈` y se aclara que es una estimacion sobre tarifas de lista, nunca la factura real de Cursor.
- **`agents/reference.md`, `commands/im-close.md`, `commands/im-status.md`, `agents/software-engineer.md`, `README.md`** — actualizados para incluir el total de tokens y el coste estimado en las plantillas y reglas de reporte.

## [0.3.4] — 2026-07-08

### Changed

- **Modelo del agente `software-engineer`**: `claude-sonnet-5` -> `claude-4.6-sonnet-medium-thinking`. Decision explicita del equipo para el rol de desarrollo/implementacion.
- **Modelo del subagente `adversarial-reviewer`**: `claude-sonnet-5` -> `composer-2.5`. Elegido entre Composer y las alternativas OpenAI (GPT-5.5) comparando benchmarks publicos (Artificial Analysis Coding Agent Index, CursorBench v3.1, SWE-Bench Multilingual, mayo 2026):
  - En el indice compuesto (que pondera mucho Terminal-Bench, tareas de shell), GPT-5.5 xhigh (65) supera a Composer 2.5 (62), pero el `adversarial-reviewer` es **readonly** y no ejecuta shell — ese benchmark no es representativo de su carga real de trabajo.
  - En las metricas mas relevantes para un rol de analisis/revision de codigo — CursorBench v3.1 (63.2% vs 59.2% de GPT-5.5 en configuracion default) y SWE-Bench Multilingual (79.8% vs ~78-80% segun fuente, esencialmente empate) — Composer 2.5 iguala o supera a GPT-5.5.
  - Composer 2.5 cuesta entre ~10x y ~60x menos por tarea que GPT-5.5/Opus en ese mismo indice, alineado con el criterio de coste del equipo.
  - Sigue sin usarse Opus en ningun caso.
- **`rules/intermarkit-global.mdc` §4** — documenta el modelo fijado por rol (ya no un unico modelo para ambos) y la razon de cada eleccion.
- **`README.md`** y **`agents/reference.md`** — referencias a `claude-sonnet-5` actualizadas a los nuevos modelos.
- **`.cursor-plugin/plugin.json`** — bump a `0.3.4`.

## [0.3.3] — 2026-07-08

### Fixed

- **Bug critico: el hook `stop` fallaba con exit code 127 (`no such file or directory: hooks/task-metrics-stop.sh`).** La correccion de v0.3.2 asumia que todos los hooks de plugin comparten el mismo cwd (raiz del plugin), pero no es cierto: segun confirma el equipo de Cursor ([foro](https://forum.cursor.com/t/inconsistent-working-directory-for-plugin-hook-commands/153236), [foro 2](https://forum.cursor.com/t/stop-hook-uses-wrong-or-different-working-directory-when-executing/157195)), el hook `stop` se ejecuta con cwd = **raiz del proyecto** (para compatibilidad con plugins de Claude Code que esperan encontrar `.claude/`), mientras que el resto de hooks de plugin (`sessionStart`, `postToolUse`, `preCompact`, `sessionEnd`) se ejecutan con cwd = **raiz de instalacion del plugin**. La ruta relativa `hooks/task-metrics-stop.sh` solo se resolvia bien para estos ultimos, nunca para `stop`. Corregido usando `${CURSOR_PLUGIN_ROOT}` (variable de entorno documentada por Cursor para plugins) en el `command` de los 5 hooks en `hooks/hooks.json`, que resuelve siempre a la raiz de instalacion del plugin independientemente del cwd real del proceso.
- **Bug critico silencioso: `session-context.sh`, `task-metrics-tooluse.sh`, `task-metrics-compact.sh` y `task-metrics-session-end.sh` probablemente nunca leian/escribian el fichero correcto.** Estos 4 hooks corren con cwd = raiz del plugin (ver punto anterior), pero construian rutas como `.intermarkit/task-metrics` o `.intermarkit/config.yaml` de forma relativa al cwd — es decir, relativas a la instalacion del plugin, no al proyecto del usuario. Como el directorio no existe ahi, los scripts hacian `exit 0` sin error visible (fail-open), por lo que el contexto de `sessionStart` y las metricas de `tool_calls`/`context_peak`/`finished_at` podian no registrarse nunca sin que se notara. Corregido: todas las rutas se construyen ahora a partir de `$CURSOR_PROJECT_DIR` (variable de entorno oficial de Cursor, siempre presente), no del cwd. `git branch --show-current` en `session-context.sh` ahora usa `git -C "$CURSOR_PROJECT_DIR"` por el mismo motivo. El hook `stop` (que si tenia cwd correcto) tambien se actualizo por consistencia y para blindarlo ante futuros cambios de Cursor en este comportamiento.
- **`scripts/lint.sh`** — el check de rutas de `hooks/hooks.json` ahora exige el prefijo `${CURSOR_PLUGIN_ROOT}/` en cada `command` en lugar de validar rutas relativas puras, para detectar una regresion de este tipo antes de publicar.

### Changed

- **`.cursor-plugin/plugin.json`** — bump a `0.3.3`, `description` actualizada.

## [0.3.2] — 2026-07-08

### Fixed

- **Bug critico: los 5 hooks no se registraban en absoluto.** El fichero de configuracion vivia en `hooks.json` (raiz del plugin), pero segun la [referencia oficial de plugins de Cursor](https://cursor.com/docs/reference/plugins.md#component-discovery), la ubicacion de descubrimiento automatico es `hooks/hooks.json`. Al no existir ahi, Cursor registraba 0 hooks silenciosamente (sin error visible), aunque el resto de componentes (`commands/`, `skills/`, `rules/`) se cargaban con normalidad. Movido `hooks.json` -> `hooks/hooks.json`.
- **Rutas de `command` incorrectas** — usaban el prefijo `.cursor/hooks/...` (convencion de hooks a nivel de *proyecto* de usuario), cuando las rutas dentro de un `hooks.json` de *plugin* se resuelven relativas a la raiz del plugin. Corregido a `hooks/session-context.sh`, `hooks/task-metrics-tooluse.sh`, etc.
- **`scripts/lint.sh`** — nuevo check que parsea `hooks/hooks.json` y valida que cada `command` exista como fichero ejecutable relativo a la raiz del plugin, para detectar esta clase de bug antes de publicar.

### Changed

- **`.cursor-plugin/plugin.json`** — bump a `0.3.2`. La `description` ahora empieza siempre con `v<version> - ` para poder verificar de un vistazo en Customize > Plugins que version esta realmente cargada. `scripts/lint.sh` valida que el prefijo coincida con `version`.

## [0.3.1] — 2026-07-07

### Added

- **Hook `sessionEnd`** (`hooks/task-metrics-session-end.sh`) — marca `finished_at`, `elapsed_ms` y `elapsed_minutes` en el fichero de metricas de la tarea activa usando `duration_ms` del payload oficial de Cursor. Es la fuente **fiable** de duracion total, no una aproximacion por timestamp. Registra ademas `session_end_reason`, `final_status`, `session_id` e `is_background_agent`. NO borra el pointer `.active` — permite continuar la tarea Jira en otro chat.
- **Hook `preCompact`** (`hooks/task-metrics-compact.sh`) — cada vez que Cursor compacta el contexto por presion del window, registra el `context_peak` con `tokens`, `percent`, `window_size` y `compactions`. Mantiene el pico maximo observado durante la tarea. Es la fuente mas fiable de uso real de contexto.
- **Metricas de tokens reales** — el hook `stop` ahora acumula `tokens.input`, `tokens.output`, `tokens.cache_read`, `tokens.cache_write` y `tokens.turns` en cada turno del agente. Usa los campos reales del payload de Cursor (`input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`) verificados en Cursor v3.10.17.
- **Campos informativos**: `last_stop_status`, `last_model`, `cursor_version` en el fichero de metricas.
- Seccion "Metricas de tarea" en el README con tabla de fuentes y fiabilidad.
- Seccion §8bis en la regla global (`intermarkit-global.mdc`) con la tabla de hooks/metricas y regla practica para el comentario Jira.
- Plantilla de comentario Jira ampliada en `agents/reference.md` con lineas de **Tokens** (formato M/K + cache hit %) y **Context peak** (opcional).
- Schema del fichero de metricas documentado completo en `agents/reference.md` §Metricas de tarea (con tabla de origen de cada campo).

### Changed

- **`hooks/task-metrics-stop.sh` reescrito** — ya NO marca `finished_at` (era incorrecto: el hook se dispara en CADA turno del agente, no al final del chat). Ahora acumula tokens sin cerrar la tarea. La semantica de cierre corresponde a `sessionEnd` (chat cerrado) o al agente cuando ejecuta `/im-close` (Fase C).
- **Fase C paso 17 (`software-engineer.md`)** — incluye instrucciones para leer y formatear tokens y context peak. El comentario Jira los reporta si estan disponibles.
- **Regla inquebrantable #10** — actualizada: en lugar de "nunca inventar metricas de tokens", ahora es "solo reportar metricas provenientes del fichero de metricas, omitir campos ausentes".
- **`commands/im-take.md`** — el fichero JSON inicial incluye el bloque `tokens` vacio para que los hooks acumulen sobre estructura conocida.
- **`commands/im-close.md`** — Fase C paso 7-8 incluye lectura y formateo de tokens/context_peak.
- **`commands/im-status.md`** — muestra tokens y context peak si existen.
- **`.cursor-plugin/plugin.json`** — bump a 0.3.1, descripcion actualizada.

### Verified

Payload real de Cursor v3.10.17 capturado con hook temporal de debug. Fields confirmados en `stop`:
```json
{
  "status": "completed", "loop_count": 0,
  "input_tokens": 1947096, "output_tokens": 10348,
  "cache_read_tokens": 1506478, "cache_write_tokens": 440604,
  "model": "...", "model_id": "...", "cursor_version": "3.10.17",
  "conversation_id": "...", "generation_id": "...", "session_id": "...",
  "transcript_path": "..."
}
```

Los 3 hooks nuevos (`stop` reescrito, `sessionEnd`, `preCompact`) probados end-to-end con simulaciones de payload: acumulacion de tokens en 2 turnos consecutivos, `context_peak` que conserva maximo pero incrementa `compactions`, y cierre con `duration_ms` fiable. Sin errores en `.hooks.log`.

## [0.3.0] — 2026-07-07

### Added

- **Cache MCP local** (`.intermarkit/cache/`) con TTL: `atlassian-user.json` (30d), `jira-transitions-{PROJECT}.json` (7d), `bitbucket-verified.json` (24h). Formato comun documentado en `agents/reference.md`. Ahorra 3-5 llamadas MCP por tarea Jira completa.
- **Pre-checks en `hooks/session-context.sh`** — el hook devuelve un JSON estructurado con `config_exists`, `credentials_global_exists`, `architecture_docs_exists`, `openspec_initialized`, `active_task` y `mcp_caches.{user_info,bitbucket_verified,transitions.<PROJECT>} = fresh|stale|missing`. El agente evita 4-6 tool calls iniciales que la version anterior repetia en cada sesion.
- **Slash commands propios**:
  - `/im-take {ISSUE_KEY}` — ejecuta Fase A completa (rama + Jira "In Progress" + metricas + pointer).
  - `/im-close` — ejecuta Fase C completa (push + PR + criterios + Jira "In Testing" + comentario + limpieza).
  - `/im-status` — resumen readonly del estado (tarea activa, tiempo, tool calls, estado cache MCP).
- **Pointer `.intermarkit/task-metrics/.active`** — apunta al fichero de la tarea activa. El hook `postToolUse` lo lee en O(1) en vez de escanear el directorio completo. Escrito por el agente al iniciar (Fase A) y borrado al cerrar (Fase C / hook `stop`).
- **Log de errores de hooks** en `.intermarkit/task-metrics/.hooks.log` (rotacion simple a 100 KB). Los hooks siguen siendo fail-open pero dejan rastro.
- **`agents/reference.md`** — nuevo fichero con bloques compartidos (Bitbucket MCP tools, cache MCP schema, Git conventions, PR/commit templates, Jira comment template). Reduce duplicacion entre la regla global y el agente.
- **`scripts/lint.sh`** — smoke checks: `python3 -m json.tool` sobre JSON, `python3 -c 'yaml.safe_load'` sobre YAML, `shellcheck` (si esta instalado) sobre los hooks.
- **CHANGELOG.md** (este fichero).

### Changed

- **Regla `intermarkit-global.mdc` es ahora la unica fuente de verdad**. El agente `software-engineer.md` ya no duplica la cascada de setup, el workflow ni las convenciones — las referencia. Reduccion ~40% del tamano del agente respecto a v0.2.
- **`hooks/session-context.sh`** — reescrito de `grep`/`sed` a `python3` (con `yaml.safe_load` si PyYAML esta disponible, fallback minimo si no). Todo el output se serializa con `json.dumps` para evitar escaping fragil.
- **`hooks/task-metrics-tooluse.sh` y `task-metrics-stop.sh`** — usan `fcntl.flock` para no perder incrementos con tool calls concurrentes. Usan el pointer `.active` (O(1)) con fallback al escaneo anterior si el pointer no existe (retrocompatible).
- **`hooks/task-metrics-stop.sh`** — borra el pointer `.active` al cerrar la tarea.
- **`agents/software-engineer.md`** — pasa de ~18 KB a ~8 KB. Ya no repite la cascada de la regla; solo describe la logica especifica del rol y los pasos concretos de las tres fases con referencias al `reference.md`.
- **`README.md`** — reescrito con seccion "Ahorro de peticiones" y estructura actualizada.
- **`.cursor-plugin/plugin.json`** — bump a `0.3.0`, descripcion actualizada.

### Removed

- **`rules/openspec-workflow.mdc`** — fusionada en `intermarkit-global.mdc` §3. Era redundante (repetia lo que ya estaba en la global) y cargarla en cada mensaje via `alwaysApply: true` sumaba tokens sin aportar nada nuevo.

### Fixed

- **Race condition en `task-metrics-tooluse.sh`** — tool calls concurrentes ya no pierden incrementos gracias a `fcntl.flock` con lectura+escritura atomicas.
- **Parsing YAML fragil en `session-context.sh`** — `grep "url:"` matcheaba tanto `repo.url` como `docs.url`, y `head -1` decidia arbitrariamente. Ahora se parsea el YAML completo y se accede por ruta (`repo.url`, `docs.url`).
- **Escaping frágil del JSON de salida en `session-context.sh`** — comillas dobles o `#` dentro de los valores del YAML corrompian el `agent_message`. Ahora se serializa con `json.dumps`.

## [0.2.0] — 2026-07-05

### Added

- Skill `python-development` con reference detallada.
- Hook `postToolUse` (contador `tool_calls` en vivo).
- Hook `stop` (registro historico de metricas al cerrar).
- Regla `openspec-workflow.mdc` (posteriormente eliminada en 0.3.0).
- Fase C detallada en `software-engineer.md` (marcar criterios de aceptacion, comentario Jira con metricas, sugerir chat nuevo).

## [0.1.0] — 2026-07-03

### Added

- Version inicial con regla `intermarkit-global`, agente `software-engineer`, subagente `adversarial-reviewer`, skill `architect`, MCP Atlassian, hook `sessionStart`.
