#!/bin/bash
# Hook stop: se dispara al final de CADA turno del agente (no al cierre del chat).
#
# Acumula en el fichero de metricas de la tarea activa:
#   - tokens.input / output / cache_read / cache_write (sumatorios)
#   - tokens.turns (numero de turnos observados)
#   - last_stop_status (completed / aborted / error)
#   - model observado (informativo, ultimo turno)
#
# IMPORTANTE: este hook NO marca finished_at ni elapsed_ms. Esa semantica corresponde
# al hook sessionEnd (fin del chat) o al agente cuando ejecuta /im-done.
#
# Fields del payload real de Cursor (verificado en v3.10.17):
#   input_tokens        - total del turno (incluye cache_read + cache_write + fresh)
#   output_tokens       - tokens generados en la respuesta
#   cache_read_tokens   - leidos de la cache (baratos)
#   cache_write_tokens  - escritos a la cache
#   status              - completed / aborted / error
#   loop_count
#   model / model_id / model_params
#   conversation_id / generation_id / session_id
#   hook_event_name = "stop"
#   cursor_version
#   workspace_roots / user_email / transcript_path
#
# Fail-open: log de errores en .intermarkit/task-metrics/.hooks.log, exit 0 siempre.
#
# IMPORTANTE: los hooks de plugin NO comparten todos el mismo cwd. El hook "stop" se
# ejecuta con cwd = raiz del proyecto, pero el resto (postToolUse, preCompact, sessionEnd,
# sessionStart) se ejecuta con cwd = raiz de instalacion del plugin. Por eso las rutas se
# construyen siempre a partir de $CURSOR_PROJECT_DIR (variable de entorno oficial, siempre
# presente) en lugar de depender del cwd. Ver: https://forum.cursor.com/t/153236

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


def read_hook_payload() -> dict:
    try:
        raw = input_file.read_text(encoding="utf-8")
        return json.loads(raw) if raw.strip() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def accumulate(fpath: Path, payload: dict) -> None:
    try:
        with fpath.open("r+", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.seek(0)
                raw = f.read()
                data = json.loads(raw) if raw.strip() else {}

                tokens = data.get("tokens") or {
                    "input": 0,
                    "output": 0,
                    "cache_read": 0,
                    "cache_write": 0,
                    "turns": 0,
                }
                for src, dst in (
                    ("input_tokens", "input"),
                    ("output_tokens", "output"),
                    ("cache_read_tokens", "cache_read"),
                    ("cache_write_tokens", "cache_write"),
                ):
                    value = payload.get(src)
                    if isinstance(value, (int, float)):
                        tokens[dst] = int(tokens.get(dst, 0)) + int(value)
                tokens["turns"] = int(tokens.get("turns", 0)) + 1
                data["tokens"] = tokens

                if payload.get("status"):
                    data["last_stop_status"] = payload["status"]
                if payload.get("model"):
                    data["last_model"] = payload["model"]
                if payload.get("cursor_version") and not data.get("cursor_version"):
                    data["cursor_version"] = payload["cursor_version"]

                f.seek(0)
                f.truncate()
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log_error(f"accumulate fallo en {fpath}: {exc}")


active = find_active()
if active is not None:
    accumulate(active, read_hook_payload())
PYEOF

rm -f "$tmp_input"
exit 0
