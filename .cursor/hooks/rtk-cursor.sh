#!/usr/bin/env bash
# Hook preToolUse (Shell) do projeto -> RTK.
# Equivale à entrada que `rtk init -g --agent cursor` grava em ~/.cursor/hooks.json
# ("command": "rtk hook cursor"), mas no nível do projeto, porque o Cloud Agent
# do Cursor roda .cursor/hooks.json do repo e NÃO roda ~/.cursor/hooks.json.
# Se o rtk não estiver no PATH, devolve {} (sem reescrita) para não quebrar comandos.
if command -v rtk >/dev/null 2>&1; then
  exec rtk hook cursor
fi
cat >/dev/null
echo '{}'
