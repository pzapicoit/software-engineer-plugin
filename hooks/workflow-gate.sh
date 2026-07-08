#!/bin/bash
# Hook beforeShellExecution: bloquea `git push` de la tarea activa si el workflow
# OpenSpec (verify + revision adversarial + archive) no esta completo.
#
# Motivacion: la regla `intermarkit-global.mdc` §3 exige verify + adversarial APROBADO
# antes de archive, y archive antes de push. Eso es texto — nada lo impedia tecnicamente
# si el agente saltaba pasos. Este hook lee `.intermarkit/task-metrics/{ISSUE_KEY}.json`
# (bloque `verification`, ver `agents/reference.md §Gate tecnico de workflow`) y convierte
# la norma en un bloqueo real sobre el push.
#
# Fail-open deliberado: si no hay tarea activa gestionada por este plugin, si python3 no
# esta disponible, o si el fichero de metricas es ilegible, se permite la accion sin
# bloquear (no debe romper trabajo fuera del workflow IntermarkIt).
#
# IMPORTANTE: igual que el resto de hooks del plugin, las rutas se construyen a partir de
# $CURSOR_PROJECT_DIR (variable de entorno oficial) en lugar de depender del cwd.
# Ver: https://forum.cursor.com/t/153236

PROJECT_DIR="${CURSOR_PROJECT_DIR:-.}"
METRICS_DIR="$PROJECT_DIR/.intermarkit/task-metrics"

tmp_input=$(mktemp)
cat > "$tmp_input"

if [ ! -d "$METRICS_DIR" ] || ! command -v python3 > /dev/null 2>&1; then
  echo '{"permission": "allow"}'
  rm -f "$tmp_input"
  exit 0
fi

python3 - "$METRICS_DIR" "$tmp_input" <<'PYEOF'
from __future__ import annotations

import json
import re
import sys
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
        from datetime import datetime, timezone
        ts = datetime.now(timezone.utc).isoformat()
        with log_file.open("a", encoding="utf-8") as f:
            f.write(f"[{ts}] workflow-gate: {msg}\n")
    except OSError:
        pass


def allow() -> None:
    print(json.dumps({"permission": "allow"}))


def read_payload() -> dict:
    try:
        raw = input_file.read_text(encoding="utf-8")
        return json.loads(raw) if raw.strip() else {}
    except (OSError, json.JSONDecodeError) as exc:
        log_error(f"input illegible: {exc}")
        return {}


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
    return None


payload = read_payload()
command = payload.get("command", "") or ""

# Solo interesa si el comando es un `git push` real (con o sin `-C <path>` intermedio,
# como usan las Fases A/C/D del workflow). Cualquier otro comando pasa sin evaluar.
if not re.search(r"\bgit\b.*\bpush\b", command):
    allow()
    sys.exit(0)

active = find_active()
if active is None:
    # Sin tarea activa gestionada por el plugin: no bloqueamos pushes ajenos al workflow.
    allow()
    sys.exit(0)

try:
    data = json.loads(active.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    log_error(f"metrics illegible en {active}: {exc}")
    allow()
    sys.exit(0)

verification = data.get("verification")
if verification is None:
    # Fichero de metricas antiguo (creado antes de este gate) sin bloque `verification`.
    # No bloqueamos retroactivamente tareas ya en curso, pero avisamos.
    log_error(f"{active.name} sin bloque 'verification' (formato antiguo) — push permitido")
    allow()
    sys.exit(0)

if verification.get("exempt") is True:
    allow()
    sys.exit(0)

verify_ok = verification.get("verify_passed") is True
adversarial_ok = verification.get("adversarial_verdict") == "APROBADO"
archived_ok = verification.get("archived") is True

if verify_ok and adversarial_ok and archived_ok:
    allow()
    sys.exit(0)

missing = []
if not verify_ok:
    missing.append("/opsx-verify no confirmado")
if not adversarial_ok:
    missing.append("revision adversarial no APROBADA")
if not archived_ok:
    missing.append("/opsx-archive no ejecutado")

issue_key = data.get("issue_key", "?")
msg = (
    f"[IntermarkIt] Push bloqueado para {issue_key}: faltan pasos del workflow OpenSpec "
    f"({'; '.join(missing)}). Completa Fase B (verify + adversarial APROBADO + archive) antes "
    f"de continuar, o si es un cambio trivial exento (regla global §3), marca "
    f"'verification.exempt: true' + 'exempt_reason' en "
    f".intermarkit/task-metrics/{active.name}."
)

print(json.dumps({
    "permission": "ask",
    "user_message": msg,
    "agent_message": msg,
}))
PYEOF

rm -f "$tmp_input"
exit 0
