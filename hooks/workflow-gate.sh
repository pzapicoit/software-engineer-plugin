#!/bin/bash
# Hook beforeShellExecution: bloquea `git push` de la tarea activa si el workflow
# OpenSpec + gates de calidad + validacion local no estan completos.
#
# Motivacion: la regla `intermarkit-global.mdc` §3 exige verify + adversarial APROBADO
# + tests + coverage + quality + archive antes de push, y ademas la validacion local
# del usuario (`local_validation_passed`, marcada por /im-accept) para autorizarlo.
# Eso es texto — nada lo impedia tecnicamente si el agente saltaba pasos. Este hook lee
# `.intermarkit/task-metrics/{ISSUE_KEY}.json` (bloque `verification`, ver
# `agents/reference.md §Gate tecnico de workflow`) y convierte la norma en un bloqueo real
# sobre el push.
#
# Compatibilidad hacia atras: los campos nuevos (`tests_passed`, `coverage_ok`,
# `quality_ok`, `local_validation_passed`) NO existian antes de v1.0.0. Si el fichero
# de metricas NO tiene un campo, se trata como `true` (comportamiento antiguo). Las
# tareas nuevas creadas por `/im-take` en v1.0.0+ inicializan todos los campos a
# `false` explicitamente, con lo que el gate los exige.
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
# como usan las Fases del workflow multi-repo). Cualquier otro comando pasa sin evaluar.
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
    # Fichero de metricas antiguo (creado antes del gate) sin bloque `verification`.
    # No bloqueamos retroactivamente tareas ya en curso, pero avisamos.
    log_error(f"{active.name} sin bloque 'verification' (formato antiguo) — push permitido")
    allow()
    sys.exit(0)

if verification.get("exempt") is True:
    allow()
    sys.exit(0)

# Cada gate: si el campo NO esta en el fichero, se trata como OK (compat con tareas
# creadas antes de v1.0.0 donde los gates nuevos no existian). Si esta pero no es el
# valor esperado, se considera "falta".

def gate_ok(field: str, expected=True) -> bool:
    """Devuelve True si el campo esta OK.

    Si el campo NO existe, devuelve True (compat hacia atras).
    Si existe, tiene que coincidir con `expected`.
    """
    if field not in verification:
        return True
    return verification.get(field) == expected


gates = {
    "/opsx-verify no confirmado (verify_passed)": gate_ok("verify_passed", True),
    "revision adversarial no APROBADA (adversarial_verdict)": gate_ok("adversarial_verdict", "APROBADO"),
    "tests unitarios no pasan (tests_passed)": gate_ok("tests_passed", True),
    "cobertura insuficiente (coverage_ok)": gate_ok("coverage_ok", True),
    "quality gates (lint/format/types) no pasan (quality_ok)": gate_ok("quality_ok", True),
    "/opsx-archive no ejecutado (archived)": gate_ok("archived", True),
    "validacion local del desarrollador no confirmada (local_validation_passed, se marca con /im-accept)": gate_ok("local_validation_passed", True),
}

missing = [msg for msg, ok in gates.items() if not ok]

if not missing:
    allow()
    sys.exit(0)

issue_key = data.get("issue_key", "?")
active_change = data.get("openspec_change_active") or data.get("openspec_change")
if isinstance(active_change, list):
    active_change = active_change[-1] if active_change else None

change_hint = f" (cambio activo: {active_change})" if active_change else ""

msg = (
    f"[IntermarkIt] Push bloqueado para {issue_key}{change_hint}: faltan pasos del workflow "
    f"({'; '.join(missing)}). Completa lo que falte antes de continuar, o si es un cambio "
    f"trivial exento (regla global §3), marca 'verification.exempt: true' + 'exempt_reason' en "
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
