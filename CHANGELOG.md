# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versiones semanticas.

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
