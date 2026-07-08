#!/bin/bash
# Hook sessionStart: inyecta contexto del proyecto IntermarkIt + pre-checks del entorno
# (credentials globales, docs de arquitectura, openspec, tarea activa, estado de cache MCP)
# para que el agente NO tenga que hacer 4-6 tool calls repetitivos al inicio de cada chat.
#
# Estrategia:
#   - Parsing YAML con python3 (yaml.safe_load si esta disponible, fallback minimo si no).
#   - Todo el output se serializa con json.dumps para evitar escaping fragil.
#   - Fail-open: cualquier error -> mensaje minimo, exit 0.
#
# IMPORTANTE: el hook sessionStart se ejecuta con cwd = raiz de instalacion del plugin,
# NO la raiz del proyecto. Todas las rutas se construyen a partir de $CURSOR_PROJECT_DIR
# (variable de entorno oficial, siempre presente) en lugar de depender del cwd.
# Ver: https://forum.cursor.com/t/153236

PROJECT_DIR="${CURSOR_PROJECT_DIR:-.}"
CONFIG_FILE="$PROJECT_DIR/.intermarkit/config.yaml"

# Rama Git actual (se indica explicitamente el repo con -C para no depender del cwd).
current_branch=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "")

if ! command -v python3 > /dev/null 2>&1; then
  # Fallback ultra minimo si no hay python3.
  if [ -f "$CONFIG_FILE" ]; then
    echo '{"agent_message": "[IntermarkIt] python3 no disponible; hook en modo degradado. El agente debe leer .intermarkit/config.yaml manualmente."}'
  else
    echo '{"agent_message": "[IntermarkIt] No se encontro .intermarkit/config.yaml — el agente guiara el setup."}'
  fi
  exit 0
fi

python3 - "$CONFIG_FILE" "$current_branch" "$PROJECT_DIR" <<'PYEOF'
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

config_path = sys.argv[1]
current_branch = sys.argv[2] or "N/A"
project_dir = Path(sys.argv[3])


def load_yaml(path: str) -> dict | None:
    """Carga un YAML sencillo. Usa PyYAML si esta disponible; si no, parser minimo por
    lineas ('clave: valor', indentacion de 2 espacios para anidacion).
    """
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read()
    except OSError:
        return None

    try:
        import yaml  # type: ignore

        data = yaml.safe_load(raw)
        return data if isinstance(data, dict) else None
    except ImportError:
        pass

    result: dict = {}
    stack: list[tuple[int, dict]] = [(0, result)]
    for line in raw.splitlines():
        stripped_hash = line.split("#", 1)[0]
        stripped = stripped_hash.rstrip()
        if not stripped.strip():
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        content = stripped.strip()
        if ":" not in content:
            continue
        key, _, value = content.partition(":")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        while stack and indent < stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if value == "":
            new_dict: dict = {}
            parent[key] = new_dict
            stack.append((indent + 2, new_dict))
        else:
            parent[key] = value
    return result


def cache_state(cache_dir: Path, filename: str) -> str:
    """Devuelve 'fresh' | 'stale' | 'missing' segun cached_at + ttl_seconds."""
    fpath = cache_dir / filename
    if not fpath.exists():
        return "missing"
    try:
        with fpath.open("r", encoding="utf-8") as f:
            payload = json.load(f)
        cached_at = payload.get("cached_at")
        ttl = int(payload.get("ttl_seconds", 0) or 0)
        if not cached_at or ttl <= 0:
            return "stale"
        from datetime import datetime, timezone
        try:
            dt = datetime.fromisoformat(cached_at.replace("Z", "+00:00"))
        except ValueError:
            return "stale"
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc) - dt).total_seconds()
        return "fresh" if age < ttl else "stale"
    except (OSError, ValueError, json.JSONDecodeError):
        return "stale"


def scan_transitions_caches(cache_dir: Path) -> dict:
    """Localiza jira-transitions-{PROJECT}.json y devuelve estado por proyecto."""
    result: dict = {}
    if not cache_dir.is_dir():
        return result
    for fpath in cache_dir.glob("jira-transitions-*.json"):
        proj = fpath.stem.removeprefix("jira-transitions-")
        result[proj] = cache_state(cache_dir, fpath.name)
    return result


def find_active_task(metrics_dir: Path) -> dict | None:
    """Prefiere .active (pointer O(1)). Si no existe, fallback O(n) a directorio."""
    if not metrics_dir.is_dir():
        return None

    pointer = metrics_dir / ".active"
    candidate: Path | None = None
    if pointer.is_file():
        try:
            target = pointer.read_text(encoding="utf-8").strip()
            if target:
                p = Path(target)
                if not p.is_absolute():
                    p = metrics_dir / p
                if p.is_file():
                    candidate = p
        except OSError:
            candidate = None

    if candidate is None:
        best_mtime = -1.0
        for fpath in metrics_dir.glob("*.json"):
            try:
                with fpath.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                if "finished_at" in data:
                    continue
                mtime = fpath.stat().st_mtime
                if mtime > best_mtime:
                    best_mtime = mtime
                    candidate = fpath
            except (OSError, json.JSONDecodeError):
                continue

    if candidate is None:
        return None

    try:
        with candidate.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None

    return {
        "issue_key": data.get("issue_key"),
        "started_at": data.get("started_at"),
        "tool_calls": data.get("tool_calls", 0),
    }


config = load_yaml(config_path)
home = Path(os.path.expanduser("~"))
cache_dir = project_dir / ".intermarkit" / "cache"
metrics_dir = project_dir / ".intermarkit" / "task-metrics"

payload: dict = {
    "current_branch": current_branch,
    "config_exists": config is not None,
    "credentials_global_exists": (home / ".intermarkit" / "credentials.yaml").is_file(),
    "architecture_docs_exists": (
        project_dir / ".intermarkit" / "architecture.md"
    ).is_file() and (project_dir / ".intermarkit" / "functional.md").is_file(),
    "openspec_initialized": (project_dir / "openspec").is_dir(),
    "active_task": find_active_task(metrics_dir),
    "mcp_caches": {
        "user_info": cache_state(cache_dir, "atlassian-user.json"),
        "bitbucket_verified": cache_state(cache_dir, "bitbucket-verified.json"),
        "transitions": scan_transitions_caches(cache_dir),
    },
}

if config is None:
    payload["message"] = (
        "[IntermarkIt] No se encontro .intermarkit/config.yaml — el agente guiara el setup."
    )
    print(json.dumps({"agent_message": json.dumps(payload, ensure_ascii=False)}))
    sys.exit(0)

jira = config.get("jira") or {}
repo = config.get("repo") or {}
docs = config.get("docs") or {}

payload["jira_project"] = jira.get("project")
payload["jira_site"] = jira.get("site") or "https://intermarkit.atlassian.net"
payload["repo_type"] = repo.get("type")
payload["repo_url"] = repo.get("url")
payload["repo_workspace"] = repo.get("workspace")
payload["default_branch"] = repo.get("default_branch") or "main"
confluence = docs.get("confluence_space") or ""
payload["confluence_space"] = confluence if confluence else None

# Mensaje humano compacto (una linea) que Cursor muestra al inicio.
parts = [f"Proyecto: {payload['jira_project']}"]
if payload["repo_type"]:
    parts.append(f"Repo: {payload['repo_type']}")
if payload["repo_workspace"]:
    parts.append(f"Workspace: {payload['repo_workspace']}")
if payload["default_branch"]:
    parts.append(f"Branch: {payload['default_branch']}")
parts.append(f"Rama actual: {payload['current_branch']}")
if payload["confluence_space"]:
    parts.append(f"Confluence: {payload['confluence_space']}")
if payload["active_task"] and payload["active_task"].get("issue_key"):
    parts.append(f"Tarea activa: {payload['active_task']['issue_key']}")

human = "[IntermarkIt] " + " | ".join(parts)
payload["message"] = human

print(json.dumps({"agent_message": json.dumps(payload, ensure_ascii=False)}))
PYEOF

exit 0
