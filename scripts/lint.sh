#!/bin/bash
# Smoke checks del plugin: valida JSON, YAML, sintaxis shell y estructura minima.
# Uso: bash scripts/lint.sh
#
# Exit codes:
#   0 - todo OK
#   1 - algun check ha fallado

set -u

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

errors=0
ok=0

check() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  if [ "$status" -eq 0 ]; then
    printf "  [OK]   %s\n" "$name"
    ok=$((ok + 1))
  else
    printf "  [FAIL] %s%s\n" "$name" "${detail:+ — $detail}"
    errors=$((errors + 1))
  fi
}

echo "== JSON =="
for f in hooks/hooks.json mcp.json .cursor-plugin/plugin.json; do
  if [ ! -f "$f" ]; then
    check "$f" 1 "no existe"
    continue
  fi
  if python3 -m json.tool "$f" > /dev/null 2>&1; then
    check "$f" 0
  else
    check "$f" 1 "JSON invalido"
  fi
done

echo ""
echo "== Rutas de comandos en hooks/hooks.json =="
if [ -f "hooks/hooks.json" ]; then
  # Los "command" deben usar el prefijo ${CURSOR_PLUGIN_ROOT}/ porque el cwd de los
  # hooks de plugin varia segun el evento (el hook "stop" corre con cwd = raiz del
  # proyecto, el resto con cwd = raiz de instalacion del plugin). Ver:
  # https://forum.cursor.com/t/153236
  while IFS= read -r cmd_path; do
    [ -z "$cmd_path" ] && continue
    case "$cmd_path" in
      '${CURSOR_PLUGIN_ROOT}/'*)
        rel_path="${cmd_path#\$\{CURSOR_PLUGIN_ROOT\}/}"
        ;;
      *)
        check "hooks/hooks.json -> $cmd_path" 1 "debe empezar por \${CURSOR_PLUGIN_ROOT}/ (el cwd de los hooks de plugin no es fiable)"
        continue
        ;;
    esac
    if [ -f "$rel_path" ]; then
      if [ -x "$rel_path" ]; then
        check "hooks/hooks.json -> $cmd_path" 0
      else
        check "hooks/hooks.json -> $cmd_path" 1 "no ejecutable (chmod +x)"
      fi
    else
      check "hooks/hooks.json -> $cmd_path" 1 "no existe relativo a la raiz del plugin ($rel_path)"
    fi
  done < <(python3 -c "
import json
data = json.load(open('hooks/hooks.json'))
for entries in data.get('hooks', {}).values():
    for entry in entries:
        cmd = entry.get('command', '')
        if cmd:
            print(cmd)
" 2>/dev/null)
else
  check "hooks/hooks.json" 1 "no existe, no se pueden validar rutas de comandos"
fi

echo ""
echo "== Version en description =="
if [ -f ".cursor-plugin/plugin.json" ]; then
  version_check_result="$(python3 -c "
import json, sys
try:
    data = json.load(open('.cursor-plugin/plugin.json'))
    version = data.get('version', '')
    description = data.get('description', '')
    expected_prefix = f'v{version} - '
    sys.exit(0 if description.startswith(expected_prefix) else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null; echo $?)"
  if [ "$version_check_result" -eq 0 ]; then
    check "description empieza con 'v<version> - '" 0
  else
    check "description empieza con 'v<version> - '" 1 "actualiza description en .cursor-plugin/plugin.json al bump de version"
  fi
else
  check "description empieza con 'v<version> - '" 1 ".cursor-plugin/plugin.json no existe"
fi

echo ""
echo "== YAML =="
for f in config-template.yaml; do
  if [ ! -f "$f" ]; then
    check "$f" 1 "no existe"
    continue
  fi
  if python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$f" > /dev/null 2>&1; then
    check "$f" 0
  else
    if python3 -c "import yaml" > /dev/null 2>&1; then
      check "$f" 1 "YAML invalido"
    else
      check "$f" 0 "(PyYAML no instalado, se salta parseo estricto)"
    fi
  fi
done

echo ""
echo "== Shell hooks =="
for f in hooks/session-context.sh hooks/task-metrics-tooluse.sh hooks/task-metrics-stop.sh hooks/task-metrics-session-end.sh hooks/task-metrics-compact.sh hooks/workflow-gate.sh; do
  if [ ! -f "$f" ]; then
    check "$f" 1 "no existe"
    continue
  fi
  if [ ! -x "$f" ]; then
    check "$f" 1 "no ejecutable (chmod +x)"
    continue
  fi
  if bash -n "$f" 2> /dev/null; then
    if command -v shellcheck > /dev/null 2>&1; then
      if shellcheck -e SC2016 "$f" > /dev/null 2>&1; then
        check "$f" 0
      else
        check "$f" 1 "shellcheck reporta warnings"
      fi
    else
      check "$f" 0 "(shellcheck no instalado, solo bash -n)"
    fi
  else
    check "$f" 1 "sintaxis shell invalida"
  fi
done

echo ""
echo "== Estructura minima =="
for path in \
  ".cursor-plugin/plugin.json" \
  "rules/intermarkit-global.mdc" \
  "agents/software-engineer.md" \
  "agents/adversarial-reviewer.md" \
  "agents/reference.md" \
  "skills/architect/SKILL.md" \
  "skills/python-development/SKILL.md" \
  "commands/im-take.md" \
  "commands/im-execute.md" \
  "commands/im-fix.md" \
  "commands/im-delta.md" \
  "commands/im-accept.md" \
  "commands/im-done.md" \
  "commands/im-status.md" \
  "hooks/session-context.sh" \
  "hooks/task-metrics-tooluse.sh" \
  "hooks/task-metrics-stop.sh" \
  "hooks/task-metrics-session-end.sh" \
  "hooks/task-metrics-compact.sh" \
  "hooks/workflow-gate.sh" \
  "hooks/hooks.json" \
  "mcp.json" \
  "config-template.yaml" \
  "README.md" \
  "CHANGELOG.md"; do
  if [ -e "$path" ]; then
    check "$path" 0
  else
    check "$path" 1 "no existe"
  fi
done

echo ""
echo "== Resumen: $ok OK, $errors FAIL =="
if [ "$errors" -gt 0 ]; then
  exit 1
fi
exit 0
