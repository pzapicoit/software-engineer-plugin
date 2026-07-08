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


def load_yaml_minimal(raw: str) -> dict:
    """Parser YAML muy simple (sin dependencias): soporta mapeos anidados y listas
    de mapeos (necesario para `repos:`), con indentacion de 2 espacios. No es un
    parser YAML completo (sin listas de escalares multilinea complejas, anchors,
    multilinea con `|`/`>`, etc.) — cubre el subconjunto que usa este plugin.
    """
    lines: list[tuple[int, str]] = []
    for line in raw.splitlines():
        stripped_hash = line.split("#", 1)[0]
        stripped = stripped_hash.rstrip()
        if not stripped.strip():
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        lines.append((indent, stripped.strip()))

    pos = 0

    def parse_scalar(value: str) -> str:
        return value.strip().strip('"').strip("'")

    def parse_block(indent: int):
        nonlocal pos
        if pos < len(lines) and lines[pos][0] == indent and lines[pos][1].startswith("- "):
            seq: list = []
            while pos < len(lines) and lines[pos][0] == indent and lines[pos][1].startswith("- "):
                item_indent, content = lines[pos]
                content = content[2:]
                sub_indent = item_indent + 2
                pos += 1
                if ":" in content:
                    key, _, value = content.partition(":")
                    key = key.strip()
                    value = value.strip()
                    item: dict = {}
                    item[key] = parse_block(sub_indent) if value == "" else parse_scalar(value)
                    while pos < len(lines) and lines[pos][0] == sub_indent and not lines[pos][1].startswith("- "):
                        k2, _, v2 = lines[pos][1].partition(":")
                        k2 = k2.strip()
                        v2 = v2.strip()
                        pos += 1
                        item[k2] = parse_block(sub_indent + 2) if v2 == "" else parse_scalar(v2)
                    seq.append(item)
                else:
                    seq.append(parse_scalar(content))
            return seq

        mapping: dict = {}
        while pos < len(lines) and lines[pos][0] == indent:
            content = lines[pos][1]
            if ":" not in content:
                pos += 1
                continue
            key, _, value = content.partition(":")
            key = key.strip()
            value = value.strip()
            pos += 1
            mapping[key] = parse_block(indent + 2) if value == "" else parse_scalar(value)
        return mapping

    result = parse_block(0)
    return result if isinstance(result, dict) else {}


def load_yaml(path: str) -> dict | None:
    """Carga un YAML sencillo. Usa PyYAML si esta disponible; si no, parser minimo
    propio (`load_yaml_minimal`, soporta listas de mapeos para `repos:`)."""
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

    return load_yaml_minimal(raw)


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
docs = config.get("docs") or {}

# Normaliza repo(s) a una lista unica en payload["repos"], sea cual sea el
# formato usado en config.yaml. `repos:` (lista, multi-repo) tiene prioridad
# sobre `repo:` (legacy, un solo repositorio) si ambos existieran.
raw_repos = config.get("repos")
repos_list: list[dict] = []
if isinstance(raw_repos, list) and raw_repos:
    for entry in raw_repos:
        if not isinstance(entry, dict):
            continue
        repos_list.append(
            {
                "name": entry.get("name"),
                "path": entry.get("path") or ".",
                "type": entry.get("type"),
                "url": entry.get("url"),
                "workspace": entry.get("workspace"),
                "default_branch": entry.get("default_branch") or "main",
            }
        )
else:
    legacy_repo = config.get("repo") or {}
    if legacy_repo:
        repos_list.append(
            {
                "name": None,
                "path": ".",
                "type": legacy_repo.get("type"),
                "url": legacy_repo.get("url"),
                "workspace": legacy_repo.get("workspace"),
                "default_branch": legacy_repo.get("default_branch") or "main",
            }
        )

# Rama actual por repo (git -C <project_dir>/<path>). Para el repo con path "."
# reutiliza current_branch (ya calculado antes de invocar python, sin coste extra).
for repo_entry in repos_list:
    if repo_entry["path"] == ".":
        repo_entry["current_branch"] = current_branch
    else:
        repo_path = project_dir / repo_entry["path"]
        try:
            import subprocess

            out = subprocess.run(
                ["git", "-C", str(repo_path), "branch", "--show-current"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            repo_entry["current_branch"] = out.stdout.strip() or "N/A"
        except (OSError, ValueError):
            repo_entry["current_branch"] = "N/A"

payload["jira_project"] = jira.get("project")
payload["jira_site"] = jira.get("site") or "https://intermarkit.atlassian.net"
payload["repos"] = repos_list
payload["is_multi_repo"] = len(repos_list) > 1

# Campos singulares legacy: solo se rellenan cuando hay exactamente un repo
# configurado (compatibilidad con integraciones existentes que los leian
# directamente). En multi-repo, usa siempre payload["repos"].
if len(repos_list) == 1:
    only = repos_list[0]
    payload["repo_type"] = only["type"]
    payload["repo_url"] = only["url"]
    payload["repo_workspace"] = only["workspace"]
    payload["default_branch"] = only["default_branch"]
else:
    payload["repo_type"] = None
    payload["repo_url"] = None
    payload["repo_workspace"] = None
    payload["default_branch"] = None

confluence = docs.get("confluence_space") or ""
payload["confluence_space"] = confluence if confluence else None

# Mensaje humano compacto (una linea) que Cursor muestra al inicio.
parts = [f"Proyecto: {payload['jira_project']}"]
if len(repos_list) == 1:
    only = repos_list[0]
    if only["type"]:
        parts.append(f"Repo: {only['type']}")
    if only["workspace"]:
        parts.append(f"Workspace: {only['workspace']}")
    if only["default_branch"]:
        parts.append(f"Branch: {only['default_branch']}")
    parts.append(f"Rama actual: {payload['current_branch']}")
elif len(repos_list) > 1:
    repos_summary = ", ".join(
        f"{r['name'] or r['path']}@{r['current_branch']}" for r in repos_list
    )
    parts.append(f"Repos: {repos_summary}")
else:
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
