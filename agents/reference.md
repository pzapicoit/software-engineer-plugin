# Reference — Software Engineer / IntermarkIt Global

Material de apoyo referenciado desde `rules/intermarkit-global.mdc` y `agents/software-engineer.md`. Leer solo la seccion necesaria.

## MCP Bitbucket

Todas las herramientas se invocan via el MCP `atlassian` (mismo servidor que Jira). Requieren API token auth habilitado por admin.

| Herramienta | Acciones |
|---|---|
| `bitbucketWorkspace` | list, get |
| `bitbucketRepository` | list, get |
| `bitbucketPullRequest` | create, get, list, merge, approve, comment, comments, diff |
| `bitbucketRepoContent` | branch.get, branch.create, commit.get, commit.create, files.get |
| `bitbucketPipelines` | list, run, get, steps, step.get, step.log |
| `bitbucketDeployments` | list, get |
| `bitbucketEnvironments` | list, get, create, delete, update |

## Cache MCP (schema)

Formato comun de todos los ficheros bajo `.intermarkit/cache/`:

```json
{
  "data": {},
  "cached_at": "2026-07-07T20:15:00Z",
  "ttl_seconds": 2592000
}
```

- `data`: contenido especifico. Ver por fichero abajo.
- `cached_at`: ISO 8601 UTC.
- `ttl_seconds`: 2592000 (30d) para user info, 604800 (7d) para transiciones, 86400 (24h) para bitbucket verified.

### `atlassian-user.json`
```json
{
  "data": {
    "accountId": "...",
    "email": "...",
    "displayName": "..."
  },
  "cached_at": "...",
  "ttl_seconds": 2592000
}
```

### `jira-transitions-{PROJECT}.json`
```json
{
  "data": {
    "To Do": "11",
    "In Progress": "21",
    "In Testing": "31",
    "Done": "41"
  },
  "cached_at": "...",
  "ttl_seconds": 604800
}
```

Nota: los IDs son ejemplo. Se rellenan tras la primera llamada real a `getTransitionsForJiraIssue`.

### `bitbucket-verified.json`
```json
{
  "data": { "verified": true, "workspace": "intermarkithub" },
  "cached_at": "...",
  "ttl_seconds": 86400
}
```

### Codigo tipo (Python) para leer/escribir cache

```python
import json
from datetime import datetime, timezone
from pathlib import Path

CACHE_DIR = Path(".intermarkit/cache")

def cache_get(name: str) -> dict | None:
    fpath = CACHE_DIR / name
    if not fpath.exists():
        return None
    payload = json.loads(fpath.read_text())
    cached_at = datetime.fromisoformat(payload["cached_at"].replace("Z", "+00:00"))
    age = (datetime.now(timezone.utc) - cached_at).total_seconds()
    if age >= payload.get("ttl_seconds", 0):
        return None
    return payload["data"]

def cache_put(name: str, data: dict, ttl_seconds: int) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    (CACHE_DIR / name).write_text(json.dumps({
        "data": data,
        "cached_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "ttl_seconds": ttl_seconds,
    }, indent=2))
```

El agente puede usar este patron via un one-liner `python3 -c "..."` en un Shell, o usar `Write`/`Read` para gestionar el JSON directamente.

## Metricas de tarea (`.intermarkit/task-metrics/`)

- `.intermarkit/task-metrics/{PROJ-XXX}.json` — fichero por tarea. Campos:
  ```json
  {
    "issue_key": "PROJ-XXX",
    "started_at": "2026-07-07T20:00:00Z",
    "tool_calls": 42,
    "finished_at": "2026-07-07T21:30:00Z",
    "elapsed_minutes": 90.0,
    "context_usage": null
  }
  ```
  `tool_calls` lo mantiene el hook `postToolUse` en tiempo real. `finished_at`/`elapsed_minutes` los rellena el hook `stop` DESPUES del comentario Jira, asi que sirven solo como historico local.

- `.intermarkit/task-metrics/.active` — pointer al fichero de la tarea activa (path relativo). Lo escribe el agente al iniciar (Fase A) y lo borra al cerrar (Fase C). Optimiza el hook `postToolUse` de O(n) a O(1).

- `.intermarkit/task-metrics/.hooks.log` — log de fallos de hooks (fail-open + rastro). Rotacion simple si supera 100 KB.

## Convenciones Git

### Ramas
- `feature/{PROJ-XXX}-{slug}` — nueva funcionalidad
- `bugfix/{PROJ-XXX}-{slug}` — bug no critico
- `hotfix/{PROJ-XXX}-{slug}` — bug critico en produccion

`{slug}`: 2-4 palabras del titulo en kebab-case.

### Commits
Formato: `tipo(PROJ-XXX): descripcion breve` (imperativo, minusculas).

Tipos: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `perf`.

Ejemplos:
- `feat(PROJ-42): add JWT authentication`
- `fix(PROJ-42): handle expired token edge case`
- `refactor(PROJ-42): extract token validation to service`

### PRs

- **Titulo:** el commit message principal (formato convencional).
- **Descripcion:** resumen extraido de `proposal.md`:
  ```
  ## Que
  <1-2 lineas>

  ## Por que
  <1-2 lineas>

  ## Como
  - <cambio 1>
  - <cambio 2>

  ## Verificacion
  OpenSpec verify + revision adversarial: APROBADO
  ```

## Plantilla de comentario Jira (cierre de tarea)

`addCommentToJiraIssue` con `contentFormat: "markdown"`:

```
**Implementacion completada** (via IntermarkIt Dev Plugin)

- **Rama:** `feature/PROJ-XXX-slug`
- **PR:** [enlace al PR, o "pendiente de crear manualmente"]
- **Cambios:** [resumen de 2-3 lineas de proposal.md]
- **Criterios de aceptacion:** N de M marcados como cumplidos (o "sin checklist")
- **Verificacion:** OpenSpec verify + revision adversarial APROBADA
- **Tiempo dedicado:** X min
- **Tool calls:** N
```

No incluir cifras de tokens/contexto (Cursor no las expone de forma fiable en el momento del cierre).

## Flujo de estados Jira

```
To Do --> In Progress --> In Testing --> Done
```

Transiciones por nombre via `getTransitionsForJiraIssue` (los IDs varian entre proyectos). Cachear el mapa por proyecto en `.intermarkit/cache/jira-transitions-{PROJECT}.json` (TTL 7d).
