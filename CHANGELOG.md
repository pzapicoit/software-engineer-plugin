# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versiones semanticas.

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
