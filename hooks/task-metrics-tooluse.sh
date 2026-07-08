#!/bin/bash
# Hook postToolUse: incrementa tool_calls en el fichero de metricas de la tarea activa.
#
# Optimizaciones respecto a la version anterior:
#   - Usa el pointer .intermarkit/task-metrics/.active (O(1)) en lugar de escanear el directorio.
#   - Fallback a escaneo O(n) si el pointer no existe (retrocompatible).
#   - Lock exclusivo (fcntl.flock) para evitar perder incrementos con tool calls concurrentes.
#   - Fail-open: log de errores en .intermarkit/task-metrics/.hooks.log, exit 0 siempre.
#
# IMPORTANTE: este hook (postToolUse) se ejecuta con cwd = raiz de instalacion del plugin,
# NO la raiz del proyecto. Por eso la ruta se construye a partir de $CURSOR_PROJECT_DIR
# (variable de entorno oficial, siempre presente) en lugar de depender del cwd.
# Ver: https://forum.cursor.com/t/153236

METRICS_DIR="${CURSOR_PROJECT_DIR:-.}/.intermarkit/task-metrics"

if [ ! -d "$METRICS_DIR" ]; then
  exit 0
fi

if ! command -v python3 > /dev/null 2>&1; then
  exit 0
fi

python3 - "$METRICS_DIR" <<'PYEOF'
from __future__ import annotations

import fcntl
import json
import os
import sys
from pathlib import Path

metrics_dir = Path(sys.argv[1])
log_file = metrics_dir / ".hooks.log"


def log_error(msg: str) -> None:
    try:
        if log_file.exists() and log_file.stat().st_size > 100_000:
            backup = log_file.with_suffix(".log.1")
            if backup.exists():
                backup.unlink()
            log_file.rename(backup)
        from datetime import datetime, timezone
        ts = datetime.now(timezone.utc).isoformat()
        with log_file.open("a", encoding="utf-8") as f:
            f.write(f"[{ts}] tooluse: {msg}\n")
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


def increment(fpath: Path) -> None:
    try:
        with fpath.open("r+", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.seek(0)
                raw = f.read()
                data = json.loads(raw) if raw.strip() else {}
                data["tool_calls"] = int(data.get("tool_calls", 0)) + 1
                f.seek(0)
                f.truncate()
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log_error(f"increment fallo en {fpath}: {exc}")


active = find_active()
if active is not None:
    increment(active)
PYEOF

exit 0
