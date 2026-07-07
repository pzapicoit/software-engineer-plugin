#!/bin/bash
# Hook sessionStart: inyecta contexto del proyecto IntermarkIt al inicio de cada sesion.
# Ahorra tokens evitando que el agente tenga que leer ficheros de configuracion.

CONFIG_FILE=".intermarkit/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"agent_message": "[IntermarkIt] No se encontro .intermarkit/config.yaml — el agente guiara el setup."}'
  exit 0
fi

# Extraer valores del config sin dependencias externas (solo grep/sed)
jira_project=$(grep -A1 "^jira:" "$CONFIG_FILE" | grep "project:" | sed 's/.*project:\s*//' | sed 's/\s*#.*//')
repo_type=$(grep "type:" "$CONFIG_FILE" | head -1 | sed 's/.*type:\s*//' | sed 's/\s*#.*//')
repo_url=$(grep "url:" "$CONFIG_FILE" | head -1 | sed 's/.*url:\s*//' | sed 's/\s*#.*//')
repo_workspace=$(grep "workspace:" "$CONFIG_FILE" | head -1 | sed 's/.*workspace:\s*//' | sed 's/\s*#.*//')
default_branch=$(grep "default_branch:" "$CONFIG_FILE" | head -1 | sed 's/.*default_branch:\s*//' | sed 's/\s*#.*//')
confluence=$(grep "confluence_space:" "$CONFIG_FILE" | sed 's/.*confluence_space:\s*//' | sed 's/\s*#.*//' | sed 's/"//g')

# Rama actual de Git
current_branch=$(git branch --show-current 2>/dev/null || echo "N/A")

# Construir mensaje compacto
msg="[IntermarkIt] Proyecto: ${jira_project}"
[ -n "$repo_type" ] && msg="$msg | Tipo: ${repo_type}"
[ -n "$repo_workspace" ] && msg="$msg | Workspace: ${repo_workspace}"
[ -n "$repo_url" ] && msg="$msg | Repo: ${repo_url}"
[ -n "$default_branch" ] && msg="$msg | Branch principal: ${default_branch}"
msg="$msg | Rama actual: ${current_branch}"
[ -n "$confluence" ] && [ "$confluence" != "" ] && msg="$msg | Confluence: ${confluence}"

echo "{\"agent_message\": \"${msg}\"}"
exit 0
