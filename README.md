# IntermarkIt Dev Plugin

Plugin de Cursor para desarrolladores de IntermarkIt. Integra normas de trabajo siempre activas con workflow spec-driven (OpenSpec), gestion de tareas via Jira, Git/Bitbucket (MCP Atlassian incluido), cache MCP local para ahorrar peticiones y modelo fijado a `claude-sonnet-5`.

## Que incluye

- **Regla `intermarkit-global`** (`alwaysApply: true`) — fuente unica de verdad: cascada de setup, workflow OpenSpec, convenciones Git, cache MCP y comandos. Se carga en TODA conversacion sin invocar nada.
- **Agente `software-engineer`** — fijado a `claude-sonnet-5`, sigue la regla global (no la duplica). Invocable con `/software-engineer` cuando se prefiera contexto aislado.
- **Subagente `adversarial-reviewer`** — revision esceptica y readonly tras cada implementacion, antes de archivar.
- **Skill `architect`** — documenta arquitectura y funcionalidad antes de implementar (brownfield o greenfield).
- **Skill `python-development`** — buenas practicas Python (uv, ruff, mypy, pytest) y frameworks estandar (FastAPI, Django, Typer, SQLAlchemy).
- **Comandos propios**:
  - `/im-take {ISSUE_KEY}` — Fase A (rama + Jira "In Progress" + metricas + cache de transiciones).
  - `/im-close` — Fase C (push + PR + criterios + Jira "In Testing" + comentario con metricas + limpieza).
  - `/im-status` — resumen del estado (tarea activa, tiempo, tool calls, estado de la cache MCP). Readonly.
- **MCP Atlassian** (`mcp.json`) — servidor oficial `https://mcp.atlassian.com/v1/mcp/authv2`. Cubre Jira, Confluence y **Bitbucket Cloud** (PRs, branches, pipelines, repos).
- **Hook `sessionStart`** — inyecta contexto de proyecto + pre-checks (credentials, docs, openspec, tarea activa, estado cache MCP) al inicio de cada sesion. Evita 4-6 tool calls repetitivos.
- **Hook `postToolUse`** — incrementa `tool_calls` en la tarea activa. O(1) via pointer `.active`, con lock (`fcntl.flock`) para tool calls concurrentes.
- **Hook `stop`** — cierre local: `finished_at`, `elapsed_minutes`, `context_usage` si Cursor lo expone. Registro historico, no alimenta el comentario Jira del mismo turno.
- **Cache MCP local (`.intermarkit/cache/`)** — respuestas estables cacheadas con TTL: `atlassian-user.json` (30d), `jira-transitions-{PROJECT}.json` (7d), `bitbucket-verified.json` (24h). El agente lee la cache antes de llamar al MCP y la actualiza tras cada llamada exitosa.

## Como se activa

La regla `intermarkit-global` (`alwaysApply: true`) se carga automaticamente en **cada conversacion**. No hace falta escribir `/software-engineer` ni ningun comando. El agente y el subagente estan disponibles para invocacion explicita cuando se prefiera contexto aislado.

## Primera vez

La regla guia el setup automaticamente:

1. **Autentica MCP Atlassian** — si pide login OAuth, te guia para completarlo.
2. **Crea config global** (`~/.intermarkit/credentials.yaml`) — si no existe.
3. **Crea config de proyecto** (`.intermarkit/config.yaml`) — te pide clave Jira, URL repo, tipo, workspace.
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

## Ahorro de peticiones

Diseno explicito para reducir tokens y llamadas MCP:

- **Regla global unica** — el agente NO duplica la cascada; delega en la regla `intermarkit-global.mdc`. Reduccion ~40% de contexto en el agente respecto a v0.2.
- **Hook `sessionStart` con pre-checks** — devuelve `config_exists`, `credentials_global_exists`, `architecture_docs_exists`, `openspec_initialized`, `active_task` y estado de la cache MCP. El agente evita 4-6 tool calls al inicio de cada chat.
- **Cache MCP local** — `atlassianUserInfo` (30d), transiciones Jira por proyecto (7d), verificacion Bitbucket (24h). Ahorra 3-5 llamadas MCP por tarea Jira completa.
- **Pointer `.active`** — el hook `postToolUse` pasa de O(n) (escaneando todos los JSON) a O(1) (leyendo un solo pointer).

Detalles del schema de cache y ejemplos: [`agents/reference.md`](agents/reference.md#cache-mcp-schema).

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
│   ├── session-context.sh      # pre-checks + JSON payload
│   ├── task-metrics-tooluse.sh # O(1) + flock
│   └── task-metrics-stop.sh    # cierre + limpieza .active
├── scripts/
│   └── lint.sh                 # smoke checks del plugin
├── hooks.json
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
- `.intermarkit/task-metrics/*.json` — metricas por tarea (local, NO commitear).
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

Valida JSON (`hooks.json`, `mcp.json`, `plugin.json`), YAML (`config-template.yaml`) y sintaxis shell de los hooks (si `shellcheck` esta instalado).

## Licencia

MIT
