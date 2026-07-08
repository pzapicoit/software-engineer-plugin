# IntermarkIt Dev Plugin

Plugin de Cursor para desarrolladores de IntermarkIt. Integra normas de trabajo siempre activas con workflow spec-driven (OpenSpec), gestion de tareas via Jira, Git/Bitbucket (MCP Atlassian incluido, con soporte multi-repo para proyectos con frontend/backend/etc. en repos separados), cache MCP local para ahorrar peticiones y modelos fijados por rol (`claude-4.6-sonnet-medium-thinking` para desarrollo, `composer-2.5` para revision adversarial).

## Que incluye

- **Regla `intermarkit-global`** (`alwaysApply: true`) — fuente unica de verdad: cascada de setup, workflow OpenSpec, convenciones Git, cache MCP y comandos. Se carga en TODA conversacion sin invocar nada.
- **Agente `software-engineer`** — fijado a `claude-4.6-sonnet-medium-thinking`, sigue la regla global (no la duplica). Invocable con `/software-engineer` cuando se prefiera contexto aislado.
- **Subagente `adversarial-reviewer`** — fijado a `composer-2.5`. Revision esceptica y readonly tras cada implementacion, antes de archivar.
- **Skill `architect`** — documenta arquitectura y funcionalidad antes de implementar (brownfield o greenfield).
- **Skill `python-development`** — buenas practicas Python (uv, ruff, mypy, pytest) y frameworks estandar (FastAPI, Django, Typer, SQLAlchemy).
- **Multi-repo** — un proyecto puede tener uno o varios repositorios Git (frontend, backend, mobile...) en subcarpetas, configurados con `repos:` (lista) en vez de `repo:` (singular). El agente pregunta que repo(s) afectan a cada tarea y hace branch/commit/push/PR de forma independiente en cada uno, con la misma rama en todos. Ver `config-template.yaml` y `rules/intermarkit-global.mdc §2.3bis`.
- **Comandos propios**:
  - `/im-take {ISSUE_KEY}` — Fase A (rama + Jira "In Progress" + metricas + cache de transiciones; en multi-repo, pregunta que repos toca la tarea).
  - `/im-close` — Fase C (push + PR + criterios + Jira "In Testing" + comentario con metricas + limpieza; en multi-repo, un PR por repo tocado).
  - `/im-status` — resumen del estado (tarea activa, tiempo, tool calls, estado de la cache MCP; en multi-repo, rama de cada repo). Readonly.
- **MCP Atlassian** (`mcp.json`) — servidor oficial `https://mcp.atlassian.com/v1/mcp/authv2`. Cubre Jira, Confluence y **Bitbucket Cloud** (PRs, branches, pipelines, repos).
- **Hook `sessionStart`** — inyecta contexto de proyecto + pre-checks (credentials, docs, openspec, tarea activa, estado cache MCP) al inicio de cada sesion. Evita 4-6 tool calls repetitivos.
- **Hook `postToolUse`** — incrementa `tool_calls` en la tarea activa. O(1) via pointer `.active`, con lock (`fcntl.flock`) para tool calls concurrentes.
- **Hook `stop`** — al final de cada turno del agente acumula tokens reales (`input`, `output`, `cache_read`, `cache_write`) y cuenta de turnos. Los campos vienen del payload real de Cursor (v3.10.17+): `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`. Ya no marca `finished_at` — esa semantica corresponde a `sessionEnd`. El total de tokens y el coste estimado en € (tarifas de lista por modelo, ver `agents/reference.md`) se calculan al reportar, no los acumula el hook.
- **Hook `sessionEnd`** — al cerrarse la conversacion marca `finished_at`/`elapsed_ms` usando `duration_ms` del payload de Cursor (fiable). Registro historico local; no borra el pointer `.active` para permitir continuar la tarea en otro chat.
- **Hook `preCompact`** — cada vez que Cursor compacta el contexto por presion del window, registra el `context_peak` (tokens, porcentaje, window size) y cuenta compactaciones. Es la mejor fuente de datos sobre uso real de contexto.
- **Cache MCP local (`.intermarkit/cache/`)** — respuestas estables cacheadas con TTL: `atlassian-user.json` (30d), `jira-transitions-{PROJECT}.json` (7d), `bitbucket-verified.json` (24h). El agente lee la cache antes de llamar al MCP y la actualiza tras cada llamada exitosa.

## Como se activa

La regla `intermarkit-global` (`alwaysApply: true`) se carga automaticamente en **cada conversacion**. No hace falta escribir `/software-engineer` ni ningun comando. El agente y el subagente estan disponibles para invocacion explicita cuando se prefiera contexto aislado.

## Primera vez

La regla guia el setup automaticamente:

1. **Autentica MCP Atlassian** — si pide login OAuth, te guia para completarlo.
2. **Crea config global** (`~/.intermarkit/credentials.yaml`) — si no existe.
3. **Crea config de proyecto** (`.intermarkit/config.yaml`) — te pide clave Jira y, segun sea un proyecto de un solo repo o multi-repo, URL/tipo/workspace de uno o de cada repositorio (nombre, subcarpeta, URL, tipo, workspace).
4. **Verifica OpenSpec** — si no esta inicializado, ofrece `openspec init --tools cursor`.
5. **Verifica Bitbucket** — comprueba `bitbucketWorkspace` (requiere que un admin habilite API token auth).
6. **Documenta arquitectura** (skill `architect`) — genera `.intermarkit/architecture.md` y `.intermarkit/functional.md`.

No necesitas crear ficheros manualmente. El agente los genera. **Todo lo que ya esta OK, el hook `sessionStart` lo detecta y el agente lo salta**, evitando comprobaciones redundantes.

## Prerequisitos

1. **OpenSpec CLI**:
   ```bash
   npm install -g @fission-ai/openspec@latest
   ```
2. **Bitbucket Cloud** (para operaciones remotas: PRs, pipelines, branches via MCP):
   - El workspace de Bitbucket debe estar vinculado a la organizacion Atlassian.
   - Un admin debe habilitar **API token authentication** en: `Admin Hub > Rovo > Rovo MCP`.
   - Las operaciones Git locales (checkout, commit, push) funcionan sin este paso.

## Uso

Al ser normas siempre activas, puedes preguntar directamente sin invocar nada:

### Consultar tareas

```
que tareas tengo?
```

### Trabajar en una tarea (workflow completo)

```
trabaja en PROJ-42
```

O usa los comandos propios:

```
/im-take PROJ-42     # Fase A: prepara entorno
                     # ...implementas con /opsx-* + adversarial-reviewer...
/im-close            # Fase C: cierra tarea
```

Comprobar estado en cualquier momento (readonly):

```
/im-status
```

### Workflow (Fase A + B + C)

Detallado en la regla `rules/intermarkit-global.mdc` §6.3 y en `agents/software-engineer.md` Paso 3.

**Fase A — Preparar entorno:** rama + Jira "In Progress" + metricas + pointer `.active`.

**Fase B — Ciclo OpenSpec:** `/opsx-propose` -> revision con usuario -> `/opsx-apply` -> `/opsx-verify` -> `adversarial-reviewer` -> `/opsx-archive`. La revision adversarial es obligatoria salvo cambios triviales.

**Fase C — Cierre:** commit final + push + PR + marcar criterios Jira + Jira "In Testing" + calcular metricas + comentario Jira + borrar pointer `.active`. Tras cierre, sugerir chat nuevo para la siguiente tarea (una tarea Jira por conversacion).

**Flujo de estados Jira:** `To Do -> In Progress -> In Testing -> Done`.

## Multi-repo (frontend, backend, mobile, ...)

Por defecto un proyecto tiene un unico repositorio (`repo:` en `config.yaml`, comportamiento sin cambios). Si el proyecto tiene varios repos en subcarpetas (ej: `./frontend`, `./backend`), usa `repos:` (lista) en su lugar:

```yaml
repos:
  - name: frontend
    path: frontend
    type: bitbucket
    url: https://bitbucket.org/intermarkithub/frontend-repo
    workspace: intermarkithub
    default_branch: main
  - name: backend
    path: backend
    type: bitbucket
    url: https://bitbucket.org/intermarkithub/backend-repo
    workspace: intermarkithub
    default_branch: main
```

Como funciona:

- **Al tomar una tarea (`/im-take`)** — si hay mas de un repo configurado, el agente pregunta cuales afectan a esa tarea (uno, varios o todos). La respuesta se guarda en `.intermarkit/task-metrics/{ISSUE_KEY}.json` (`repos: ["frontend", "backend"]`) para no repetir la pregunta en el cierre.
- **Ramas** — misma convencion de nombre (`feature/PROJ-XXX-slug`) en cada repo seleccionado.
- **Al cerrar la tarea (`/im-close`)** — commit + push independiente por repo (se omite el que no tuvo cambios) y un Pull Request por repo, cada uno contra su propio `workspace`/URL.
- **`/im-status`** — muestra la rama actual de cada repo configurado.

`repos:` y `repo:` son mutuamente excluyentes; si ambos existen en el fichero, `repos:` tiene prioridad. Un proyecto de un solo repo (`repo:` o `repos:` con un unico elemento) se comporta exactamente igual que antes de esta funcionalidad — no se pregunta nada.

## Ahorro de peticiones

Diseno explicito para reducir tokens y llamadas MCP:

- **Regla global unica** — el agente NO duplica la cascada; delega en la regla `intermarkit-global.mdc`. Reduccion ~40% de contexto en el agente respecto a v0.2.
- **Hook `sessionStart` con pre-checks** — devuelve `config_exists`, `credentials_global_exists`, `architecture_docs_exists`, `openspec_initialized`, `active_task` y estado de la cache MCP. El agente evita 4-6 tool calls al inicio de cada chat.
- **Cache MCP local** — `atlassianUserInfo` (30d), transiciones Jira por proyecto (7d), verificacion Bitbucket (24h). Ahorra 3-5 llamadas MCP por tarea Jira completa.
- **Pointer `.active`** — los hooks pasan de O(n) (escaneando todos los JSON) a O(1) (leyendo un solo pointer).

Detalles del schema de cache y ejemplos: [`agents/reference.md`](agents/reference.md#cache-mcp-schema).

## Metricas de tarea

Cada tarea Jira genera `.intermarkit/task-metrics/{ISSUE_KEY}.json` con datos recolectados **automaticamente por los hooks del plugin** (sin trabajo del agente ni llamadas MCP):

| Metrica | Fuente | Fiable |
|---|---|---|
| Tool calls | Hook `postToolUse` (incremento en vivo) | Si |
| Tokens (input/output/cache_read/cache_write/turns) | Hook `stop` (payload real de Cursor v3.10.17+: `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`) | Si, cota inferior — el turno actual (el que escribe el comentario Jira) no esta contabilizado |
| Total de tokens (input + output) y coste estimado en € | Calculado por el agente al reportar, a partir del bloque `tokens` y una tabla de precios por modelo (`agents/reference.md §Total de tokens y coste estimado`) | Estimacion sobre tarifas de lista, no factura real — siempre con prefijo `≈` |
| Context peak | Hook `preCompact` (`context_tokens`, `context_usage_percent`, `context_window_size`) | Solo si Cursor compacta el contexto al menos una vez |
| Tiempo dedicado | Agente en Fase C: `started_at` vs `now` (por timestamp). El hook `sessionEnd` rellena `elapsed_ms` a posteriori usando `duration_ms` del payload | Si |

El comentario Jira de cierre de tarea (`/im-close`) refleja todas estas metricas cuando estan disponibles y las omite silenciosamente cuando no.

## Estructura

```
software-engineer-plugin/
├── .cursor-plugin/
│   └── plugin.json
├── agents/
│   ├── software-engineer.md
│   ├── adversarial-reviewer.md
│   └── reference.md            # bloques compartidos (MCP Bitbucket, cache schema, Git conventions)
├── skills/
│   ├── architect/
│   │   └── SKILL.md
│   └── python-development/
│       ├── SKILL.md
│       └── reference.md
├── rules/
│   └── intermarkit-global.mdc  # fuente unica de verdad
├── commands/
│   ├── im-take.md
│   ├── im-close.md
│   └── im-status.md
├── hooks/
│   ├── hooks.json                  # config de hooks (ubicacion requerida por Cursor)
│   ├── session-context.sh          # pre-checks + JSON payload (sessionStart)
│   ├── task-metrics-tooluse.sh     # incrementa tool_calls (postToolUse, O(1) + flock)
│   ├── task-metrics-stop.sh        # acumula tokens por turno (stop)
│   ├── task-metrics-session-end.sh # marca finished_at/elapsed_ms (sessionEnd)
│   └── task-metrics-compact.sh     # registra context_peak (preCompact)
├── scripts/
│   └── lint.sh                 # smoke checks del plugin
├── mcp.json
├── config-template.yaml
├── CHANGELOG.md
├── .gitignore
└── README.md
```

## Ficheros generados en cada proyecto consumidor

- `.intermarkit/config.yaml` — configuracion (commiteable, define el proyecto).
- `.intermarkit/architecture.md` — stack + arquitectura (commiteable, generado por la skill `architect`).
- `.intermarkit/functional.md` — documentacion funcional (commiteable, generado por la skill `architect`).
- `.intermarkit/task-metrics/{ISSUE_KEY}.json` — metricas por tarea con schema:
  ```json
  {
    "issue_key": "PROJ-42",
    "started_at": "2026-07-07T20:00:00Z",
    "repos": ["frontend", "backend"],
    "tool_calls": 42,
    "tokens": {"input": 1947096, "output": 10348, "cache_read": 1506478, "cache_write": 440604, "turns": 3},
    "context_peak": {"tokens": 120000, "percent": 85, "window_size": 128000, "compactions": 2},
    "finished_at": "...", "elapsed_ms": 5400000,
    "last_model": "claude-4.6-sonnet-medium-thinking", "cursor_version": "3.10.17"
  }
  ```
  (`repos` solo aparece en proyectos multi-repo; se omite por completo en proyectos de un solo repositorio.)
- `.intermarkit/task-metrics/.active` — pointer a tarea activa (local, NO commitear).
- `.intermarkit/task-metrics/.hooks.log` — log de errores de hooks (local, NO commitear).
- `.intermarkit/cache/*.json` — cache MCP local (local, NO commitear).

`.gitignore` recomendado para el proyecto consumidor:

```
.intermarkit/task-metrics/
.intermarkit/cache/
```

## Desarrollo del plugin

Smoke checks locales:

```bash
bash scripts/lint.sh
```

Valida JSON (`hooks/hooks.json`, `mcp.json`, `plugin.json`), YAML (`config-template.yaml`), sintaxis shell de los hooks (si `shellcheck` esta instalado) y que las rutas `command` declaradas en `hooks/hooks.json` existan y sean ejecutables.

## Licencia

MIT
