#!/bin/bash
# Hook stop: captura metricas finales (timestamp de fin, duracion, context usage
# si Cursor lo expone) en el fichero de metricas de la tarea activa. Fail-open.
#
# IMPORTANTE: este hook se ejecuta DESPUES de que el agente termine de responder,
# por lo que sus datos (finished_at, context_usage) NO estan disponibles todavia
# cuando el agente escribe el comentario de cierre en Jira dentro del mismo turno.
# Sirven como registro local historico, no como fuente para ese comentario.

METRICS_DIR=".intermarkit/task-metrics"

if [ ! -d "$METRICS_DIR" ]; then
  exit 0
fi

active_file=""
for f in $(ls -t "$METRICS_DIR"/*.json 2>/dev/null); do
  if ! grep -q '"finished_at"' "$f" 2>/dev/null; then
    active_file="$f"
    break
  fi
done

if [ -z "$active_file" ]; then
  exit 0
fi

# Volcar stdin a un fichero temporal en vez de interpolarlo en el codigo Python:
# el JSON puede contener comillas que rompan la interpolacion directa en shell.
tmp_input=$(mktemp)
cat > "$tmp_input"

if command -v python3 > /dev/null 2>&1; then
  python3 - "$active_file" "$tmp_input" <<'PYEOF'
import json
import sys
from datetime import datetime, timezone

active_file, input_file = sys.argv[1], sys.argv[2]

try:
    with open(active_file, "r") as f:
        data = json.load(f)

    if "finished_at" in data:
        sys.exit(0)

    now = datetime.now(timezone.utc)
    data["finished_at"] = now.isoformat()

    started = datetime.fromisoformat(data.get("started_at", now.isoformat()))
    if started.tzinfo is None:
        started = started.replace(tzinfo=timezone.utc)
    data["elapsed_minutes"] = round((now - started).total_seconds() / 60, 1)

    try:
        with open(input_file, "r") as f:
            raw = f.read()
        hook_data = json.loads(raw) if raw.strip() else {}
        for key in ("context_usage", "usage", "token_usage", "tokens", "contextUsage"):
            if hook_data.get(key):
                data["context_usage"] = hook_data[key]
                break
    except (json.JSONDecodeError, ValueError, OSError):
        pass

    with open(active_file, "w") as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
PYEOF
fi

rm -f "$tmp_input"
exit 0
