# IntermarkIt Dev Plugin

Plugin de Cursor para desarrolladores de IntermarkIt. Integra normas de trabajo siempre activas (sin invocacion) con workflow spec-driven (OpenSpec), gestion de tareas via Jira, Git/Bitbucket (MCP Atlassian incluido) y modelo fijado a Claude Sonnet 5.

## Que incluye

- **Regla `intermarkit-global`** (`alwaysApply: true`) — normas de trabajo activas en TODA conversacion sin invocar nada: ambito de proyecto, cascada de configuracion, Git/Bitbucket, arquitectura y skills/subagentes obligatorios
- **Regla `openspec-workflow`** (`alwaysApply: true`) — refuerza el workflow spec-driven completo (propose -> review -> apply -> verify -> revision adversarial -> archive)
- **Agente `software-engineer`** — fijado a `model: claude-sonnet-5` (nunca usa Opus), invocable explicitamente con `/software-engineer`
- **Subagente `adversarial-reviewer`** — revision esceptica y readonly tras cada implementacion, antes de archivar
- **Skill `architect`** — revisa el codigo existente (o ayuda a definir el stack si el proyecto esta vacio) y documenta arquitectura y funcionalidad antes de implementar nada
- **Skill `python-development`** — aplica buenas practicas, tooling (uv, ruff, mypy, pytest) y frameworks estandar (FastAPI, Django, Typer, SQLAlchemy) al escribir o revisar codigo Python
- **MCP Atlassian** (`mcp.json`) — servidor remoto oficial `https://mcp.atlassian.com/v1/mcp/authv2`, se instala junto al plugin. Cubre Jira, Confluence y **Bitbucket Cloud** (PRs, branches, pipelines, repos)
- **Hook `sessionStart`** — inyecta automaticamente el contexto del proyecto (Jira, repo, rama actual) al inicio de cada sesion para ahorrar tokens
- **Hook `postToolUse`** — incrementa en vivo el contador de tool calls en las metricas de la tarea activa
- **Hook `stop`** — registro historico local (timestamp de fin, duracion, context usage si Cursor lo expone) en las metricas de la tarea activa; no alimenta el comentario Jira del mismo turno (ver seccion Hooks)

## Como se activa

Las dos reglas (`intermarkit-global` y `openspec-workflow`) se cargan automaticamente en **cada conversacion** de cualquier desarrollador que tenga el plugin instalado — no hace falta escribir `/software-engineer` ni ningun comando. El agente y el subagente siguen disponibles para invocacion explicita cuando se prefiera un contexto aislado.

## Primera vez

Las reglas guian el setup automaticamente, sin invocacion:

1. **Autentica MCP Atlassian** — si pide login OAuth, te guia para completarlo
2. **Crea config global** (`~/.intermarkit/credentials.yaml`) — si no existe
3. **Crea config de proyecto** (`.intermarkit/config.yaml`) — te pide la clave del proyecto Jira, URL del repo, tipo (bitbucket/github/gitlab) y workspace
4. **Verifica OpenSpec** — si no esta inicializado, ofrece ejecutar `openspec init`
5. **Verifica Bitbucket** — comprueba que las herramientas MCP Bitbucket responden (requiere que un admin habilite API token auth, ver seccion siguiente)
6. **Documenta arquitectura** (skill `architect`) — si hay codigo, lo revisa y genera `.intermarkit/architecture.md` y `.intermarkit/functional.md`; si el proyecto esta vacio, te ayuda a decidir el stack y lo documenta

No necesitas crear ficheros manualmente. El agente te pregunta y los genera.

## Prerequisitos

1. **OpenSpec CLI** instalado:

```bash
npm install -g @fission-ai/openspec@latest
```

2. **Bitbucket Cloud** (para operaciones remotas: PRs, pipelines, branches via MCP):
   - El workspace de Bitbucket debe estar vinculado a la organizacion Atlassian
   - Un admin debe habilitar **API token authentication** en: `Admin Hub > Rovo > Rovo MCP`
   - Las operaciones Git locales (checkout, commit, push) funcionan sin este paso

## Uso

Al ser normas siempre activas, puedes preguntar directamente sin invocar nada:

### Consultar tareas asignadas

```
que tareas tengo?
```

### Trabajar en una tarea

```
trabaja en PROJ-42
```

Si prefieres forzar el contexto aislado del agente explicito, tambien funciona:

```
/software-engineer trabaja en PROJ-42
```

### Git y Bitbucket

```
crea rama para PROJ-42
```

El agente crea automaticamente `feature/PROJ-42-slug` desde la rama principal configurada.

```
crea un PR para PROJ-42
```

Usa las herramientas MCP de Bitbucket para crear el PR, enlazarlo a Jira y verificar pipelines.

### Workflow completo (Git + OpenSpec + Jira)

Al trabajar en una tarea, el agente ejecuta el ciclo completo de forma integrada:

**Fase A — Preparar entorno:**
1. Crea rama (`feature/PROJ-XXX-slug`) desde la rama principal
2. Transiciona el issue Jira a **In Progress**
3. Inicia metricas de tarea (timestamp + contador de tool calls)

**Fase B — Ciclo OpenSpec:**
4. `/opsx-propose`: genera proposal, specs, design, tasks
5. Presenta la propuesta y espera tu aprobacion (o ajustes)
6. `/opsx-apply`: implementa con commits parciales
7. `/opsx-verify`: valida contra artefactos
8. `adversarial-reviewer`: revision esceptica obligatoria
9. Si hallazgos criticos, corrige y repite verify + adversarial
10. `/opsx-archive`: solo cuando el veredicto es `APROBADO`

**Fase C — Cierre (Git + Jira):**
11. Actualiza docs de arquitectura si el cambio lo requiere
12. Commit final + `git push -u origin HEAD`
13. Crea PR via MCP Bitbucket (o informa para crearlo manualmente)
14. Marca en la descripcion del issue los criterios de aceptacion (`- [ ]`) que quedaron realmente cumplidos, como `- [x]`
15. Transiciona el issue Jira a **In Testing**
16. Calcula tiempo dedicado (por timestamp) y lee tool calls (contador en vivo)
17. Anade comentario resumen al issue (rama, PR, cambios, criterios marcados, verificacion, tiempo, tool calls)
18. Si quieres trabajar en otra tarea, el agente te pedira abrir un chat nuevo (ver seccion siguiente)

**Flujo de estados Jira:** `To Do -> In Progress -> In Testing -> Done`

### Una tarea Jira por conversacion

Cuando una tarea se cierra, el agente **no** continua con otra tarea Jira en el mismo chat. Te pedira abrir una conversacion nueva para evitar arrastrar contexto de la tarea ya cerrada (propuesta, codigo revisado, discusiones), que solo consumiria tokens sin aportar valor a la siguiente tarea.

Si solo necesitas algo puntual sobre la tarea recien cerrada (revisar el PR, una duda, ajustar el comentario), puedes seguir en el mismo chat sin problema.

**Nota:** `/opsx-verify` requiere el perfil expandido de OpenSpec. Si tu proyecto solo tiene el perfil `core`, el agente te ofrecera habilitarlo con:
```bash
openspec config profile
openspec update
```

## Estructura

```
software-engineer-plugin/
├── .cursor-plugin/
│   └── plugin.json
├── agents/
│   ├── software-engineer.md
│   └── adversarial-reviewer.md
├── skills/
│   ├── architect/
│   │   └── SKILL.md
│   └── python-development/
│       ├── SKILL.md
│       └── reference.md
├── rules/
│   ├── intermarkit-global.mdc
│   └── openspec-workflow.mdc
├── hooks/
│   ├── session-context.sh
│   ├── task-metrics-tooluse.sh
│   └── task-metrics-stop.sh
├── hooks.json
├── mcp.json
├── config-template.yaml
└── README.md
```

## Ficheros generados en cada proyecto

- `.intermarkit/config.yaml` — configuracion del proyecto (Jira, repo, docs)
- `.intermarkit/architecture.md` — stack tecnico y arquitectura (generado por la skill `architect`)
- `.intermarkit/functional.md` — documentacion funcional del sistema (generado por la skill `architect`)
- `.intermarkit/task-metrics/{PROJ-XXX}.json` — metricas por tarea (`started_at`, `tool_calls` en vivo; `finished_at`/`elapsed_minutes`/`context_usage` los anade el hook `stop` como registro historico, despues de que el comentario Jira ya se haya escrito). Datos locales de sesion, no se commitean al repo.

## Convenciones Git

El plugin impone automaticamente:

- **Ramas**: `feature/PROJ-XXX-slug`, `bugfix/PROJ-XXX-slug`, `hotfix/PROJ-XXX-slug`
- **Commits**: formato convencional `tipo(PROJ-XXX): descripcion`
- **PRs**: creados via MCP Bitbucket con titulo del commit principal y descripcion de la propuesta OpenSpec

## Hooks

### `sessionStart` — Contexto de sesion

Al iniciar cada sesion, un hook lee `.intermarkit/config.yaml` y la rama Git actual, e inyecta un resumen compacto como contexto del agente. Esto evita que el agente gaste tokens leyendo ficheros de configuracion repetidamente.

Si el fichero de config no existe, el hook informa al agente para que inicie el flujo de setup guiado.

### `postToolUse` — Contador de tool calls

Cada vez que el agente usa una herramienta, este hook incrementa el campo `tool_calls` en el fichero de metricas de la tarea activa (`.intermarkit/task-metrics/{PROJ-XXX}.json`). Si no hay tarea activa, el hook no hace nada (fail-open).

### `stop` — Registro historico de metricas

Cuando el agente termina de responder, este hook escribe en el fichero de metricas:
- `finished_at`: timestamp de fin
- `elapsed_minutes`: duracion calculada
- `context_usage`: datos de uso de contexto/tokens si Cursor los expone en el JSON del evento (puede quedar vacio si no los expone)

**Importante:** este hook se dispara DESPUES de que el agente termine de responder, es decir, despues de que el comentario de cierre ya se haya escrito en Jira. Por eso el comentario Jira nunca incluye estos campos — el agente calcula el tiempo dedicado el mismo (comparando `started_at` con la hora actual, via Shell) y usa `tool_calls` (que si esta disponible en vivo) como metrica de actividad. El registro de este hook queda solo como historico local en `.intermarkit/task-metrics/`.

### Sobre las metricas en el comentario Jira

El comentario de cierre incluye **tiempo dedicado** (calculado por timestamp) y **tool calls** (contador exacto), pero no cifras de tokens/contexto: Cursor no las expone de forma fiable a mitad de conversacion. Para ver el consumo de contexto de una conversacion, usa el panel "View Report" de Cursor.

## Licencia

MIT
