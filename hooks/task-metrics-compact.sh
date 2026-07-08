#!/bin/bash
# Hook preCompact: se dispara cuando Cursor va a compactar el contexto por presion
# del context window. Es la MEJOR fuente de datos sobre uso real de contexto.
#
# Payload documentado por Cursor:
#   trigger              (auto / manual)
#   context_usage_percent
#   context_tokens
#   context_window_size
#   message_count
#   messages_to_compact
#   is_first_compaction
#
# Registra en context_peak del fichero de metricas de la tarea activa el punto de mayor
# uso observado durante la tarea (no se sobreescribe si un pico posterior es menor).
#
# Fail-open: log en .intermarkit/task-metrics/.hooks.log, exit 0 siempre.
#
# IMPORTANTE: este hook (preCompact) se ejecuta con cwd = raiz de instalacion del plugin,
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
            f.write(f"[{ts}] preCompact: {msg}\n")
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


def record_peak(fpath: Path, payload: dict) -> None:
    tokens = payload.get("context_tokens")
    percent = payload.get("context_usage_percent")
    window = payload.get("context_window_size")

    if not isinstance(tokens, (int, float)):
        return

    try:
        with fpath.open("r+", encoding="utf-8") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.seek(0)
                raw = f.read()
                data = json.loads(raw) if raw.strip() else {}

                previous = data.get("context_peak") or {}
                previous_tokens = previous.get("tokens", 0)
                compactions = int(previous.get("compactions", 0)) + 1

                if tokens >= previous_tokens:
                    data["context_peak"] = {
                        "tokens": int(tokens),
                        "percent": float(percent) if isinstance(percent, (int, float)) else None,
                        "window_size": int(window) if isinstance(window, (int, float)) else None,
                        "recorded_at": datetime.now(timezone.utc).isoformat(),
                        "compactions": compactions,
                    }
                else:
                    previous["compactions"] = compactions
                    data["context_peak"] = previous

                f.seek(0)
                f.truncate()
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        log_error(f"record_peak fallo en {fpath}: {exc}")


active = find_active()
if active is not None:
    record_peak(active, read_payload())
PYEOF

rm -f "$tmp_input"
exit 0
