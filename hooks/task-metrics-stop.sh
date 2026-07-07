#!/bin/bash
# Hook stop: captura metricas finales (finished_at, elapsed_minutes, context_usage si Cursor
# lo expone) en el fichero de metricas de la tarea activa.
#
# IMPORTANTE: este hook se ejecuta DESPUES de que el agente termine de responder,
# por lo que sus datos NO estan disponibles cuando el agente escribe el comentario Jira
# dentro del mismo turno. Sirve como registro local historico.
#
# Optimizaciones respecto a la version anterior:
#   - Usa el pointer .active (O(1)) con fallback a escaneo.
#   - flock para no colisionar con task-metrics-tooluse.sh.
#   - Fail-log en .intermarkit/task-metrics/.hooks.log.

METRICS_DIR=".intermarkit/task-metrics"

if [ ! -d "$METRICS_DIR" ]; then
  exit 0
fi

if ! command -v python3 > /dev/null 2>&1; then
  exit 0
fi

tmp_input=$(mktemp)
cat > "$tmp_input"

python3 - "$METRICS_DIR" "$tmp_input" <<'PYEOF'
from __future__ import annotations

import fcntl
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

metrics_dir = Path(sys.argv[1])
input_file = Path(sys.argv[2])
log_file = metrics_dir / ".hooks.log"


def log_error(msg: str) -> None:
    try:
        if log_file.exists() and log_file.stat().st_size > 100_000:
            backup = log_file.with_suffix(".log.1")
            if backup.exists():
                backup.unlink()
            log_file.rename(backup)
        ts = datetime.now(timezone.utc).isoformat()
        with log_file.open("a", encoding="utf-8") as f:
            f.write(f"[{ts}] stop: {msg}\n")
    except OSError:
        pass


def find_active() -> Path | None:
    pointer = metrics_dir / ".active"
    if pointer.is_file():
        try:
            target = pointer.read_text(encoding="utf-8").strip()
            if target:
                p = Path(target)
                if not p.is_absolute():
                    p = metrics_dir / p
                if p.is_file():
                    return p
        except OSError as exc:
            log_error(f".active illegible: {exc}")

    best: Path | None = None
    best_mtime = -1.0
    try:
        for fpath in metrics_dir.glob("*.json"):
            try:
                with fpath.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                if "finished_at" in data:
                    continue
                mtime = fpath.stat().st_mtime
                if mtime > best_mtime:
                    best_mtime = mtime
                    best = fpath
            except (OSError, json.JSONDecodeError):
                continue
    except OSError as exc:
        log_error(f"escaneo fallo: {exc}")
    return best


def read_hook_context() -> dict:
    try:
        raw = input_file.read_text(encoding="utf-8")
        return json.loads(raw) if raw.strip() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def finalize(fpath: Path, hook_data: dict) -> None:
    try:
        with fpath.open("r+", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.seek(0)
                raw = f.read()
                data = json.loads(raw) if raw.strip() else {}

                if "finished_at" in data:
                    return

                now = datetime.now(timezone.utc)
                data["finished_at"] = now.isoformat()

                try:
                    started_raw = data.get("started_at", now.isoformat())
                    started = datetime.fromisoformat(started_raw.replace("Z", "+00:00"))
                    if started.tzinfo is None:
                        started = started.replace(tzinfo=timezone.utc)
                    data["elapsed_minutes"] = round((now - started).total_seconds() / 60, 1)
                except (ValueError, AttributeError) as exc:
                    log_error(f"elapsed_minutes fallo: {exc}")
                    data["elapsed_minutes"] = None

                for key in ("context_usage", "usage", "token_usage", "tokens", "contextUsage"):
                    if hook_data.get(key):
                        data["context_usage"] = hook_data[key]
                        break

                f.seek(0)
                f.truncate()
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log_error(f"finalize fallo en {fpath}: {exc}")


active = find_active()
if active is not None:
    finalize(active, read_hook_context())

    pointer = metrics_dir / ".active"
    if pointer.is_file():
        try:
            target = pointer.read_text(encoding="utf-8").strip()
            resolved = active.name if active.is_absolute() and active.parent == metrics_dir else target
            if resolved == active.name or Path(target).name == active.name:
                pointer.unlink()
        except OSError as exc:
            log_error(f".active unlink fallo: {exc}")
PYEOF

rm -f "$tmp_input"
exit 0
