#!/bin/bash
# Hook postToolUse: incrementa el contador de tool calls en el fichero de metricas
# de la tarea activa (si existe). Fail-open: si algo falla, sale con 0 sin bloquear.

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

if command -v python3 > /dev/null 2>&1; then
  python3 -c "
import json
try:
    with open('$active_file', 'r') as f:
        data = json.load(f)
    data['tool_calls'] = data.get('tool_calls', 0) + 1
    with open('$active_file', 'w') as f:
        json.dump(data, f, indent=2)
except Exception:
    pass
"
fi

exit 0
