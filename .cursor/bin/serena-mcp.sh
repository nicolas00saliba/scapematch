#!/usr/bin/env bash
# Sobe o Serena em stdio com as ferramentas de símbolo (get_symbols_overview,
# find_symbol, ...). O `serena init` do Serena 2 grava agent_interface: REPL,
# que não publica essas ferramentas; --agent-interface tools força o modo clássico.
# Procura o binário em ~/.local/bin mesmo quando o processo do MCP não lê o bashrc.
set -euo pipefail
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

project="${1:-${PWD}}"
args=(
  start-mcp-server
  --context ide
  --agent-interface tools
  --project "${project}"
  --open-web-dashboard false
  --enable-gui-log-window false
)

if [ -x "${HOME}/.local/bin/serena" ]; then
  exec "${HOME}/.local/bin/serena" "${args[@]}"
fi
if command -v serena >/dev/null 2>&1; then
  exec serena "${args[@]}"
fi
if [ -x "${HOME}/.local/bin/uvx" ]; then
  exec "${HOME}/.local/bin/uvx" --from git+https://github.com/oraios/serena serena "${args[@]}"
fi
if command -v uvx >/dev/null 2>&1; then
  exec uvx --from git+https://github.com/oraios/serena serena "${args[@]}"
fi

printf '%s\n' "serena ausente. Rode: bash .cursor/instalar-ferramentas.sh" >&2
exit 1
