#!/bin/bash
# Hook sessionEnd: se dispara cuando la conversacion completa termina (cierre de ventana,
# usuario cierra el chat, error, etc.). Es la fuente OFICIAL y fiable de duracion total.
#
# Payload documentado por Cursor:
#   session_id
#   reason (completed / aborted / error / window_close / user_close)
#   duration_ms
#   is_background_agent
#   final_status
#   error_message (si aplica)
#
# Marca en el fichero de metricas de la tarea activa:
#   finished_at        (ISO 8601 UTC, calculado ahora)
#   elapsed_ms         (duration_ms del payload, fiable)
#   session_end_reason (reason del payload)
#   final_status       (final_status del payload)
#
# NO borra el pointer .active — la tarea Jira puede seguir viva aunque el chat se cierre;
# el usuario puede continuar en otra conversacion. El pointer se limpia SOLO cuando el
# agente ejecuta /im-done o el usuario lo hace manualmente.
#
# Fail-open: log en .intermarkit/task-metrics/.hooks.log, exit 0 siempre.
#
# IMPORTANTE: este hook (sessionEnd) se ejecuta con cwd = raiz de instalacion del plugin,
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
            f.write(f"[{ts}] sessionEnd: {msg}\n")
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


def read_payload() -> dict:
    try:
        raw = input_file.read_text(encoding="utf-8")
        return json.loads(raw) if raw.strip() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def close_session(fpath: Path, payload: dict) -> None:
    try:
        with fpath.open("r+", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.seek(0)
                raw = f.read()
                data = json.loads(raw) if raw.strip() else {}

                if data.get("finished_at"):
                    return

                now = datetime.now(timezone.utc)
                data["finished_at"] = now.isoformat()

                duration_ms = payload.get("duration_ms")
                if isinstance(duration_ms, (int, float)):
                    data["elapsed_ms"] = int(duration_ms)
                    data["elapsed_minutes"] = round(duration_ms / 60000, 1)
                else:
                    try:
                        started_raw = data.get("started_at", now.isoformat())
                        started = datetime.fromisoformat(
                            started_raw.replace("Z", "+00:00")
                        )
                        if started.tzinfo is None:
                            started = started.replace(tzinfo=timezone.utc)
                        elapsed_seconds = (now - started).total_seconds()
                        data["elapsed_ms"] = int(elapsed_seconds * 1000)
                        data["elapsed_minutes"] = round(elapsed_seconds / 60, 1)
                    except (ValueError, AttributeError) as exc:
                        log_error(f"elapsed calc fallo: {exc}")

                for src, dst in (
                    ("reason", "session_end_reason"),
                    ("final_status", "final_status"),
                    ("session_id", "session_id"),
                    ("is_background_agent", "is_background_agent"),
                ):
                    if payload.get(src) is not None:
                        data[dst] = payload[src]

                f.seek(0)
                f.truncate()
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log_error(f"close_session fallo en {fpath}: {exc}")


active = find_active()
if active is not None:
    close_session(active, read_payload())
PYEOF

rm -f "$tmp_input"
exit 0
