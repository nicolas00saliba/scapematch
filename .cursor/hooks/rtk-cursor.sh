#!/usr/bin/env bash
# preToolUse (matcher Shell) do repositório.
# Cloud agents carregam .cursor/hooks.json e não o ~/.cursor/hooks.json,
# então o hook do projeto chama `rtk hook cursor` (formato oficial do RTK).
#
# Entrada (Cursor): JSON com tool_input.command.
# Saída: JSON com permission "allow" e updated_input.command, ou {}.
# O RTK 1.1 devolve permission "ask" na reescrita padrão. A doc atual do
# Cursor aceita "ask" no schema, mas não o aplica no preToolUse; sem
# "allow" o updated_input pode ser ignorado. Este script só troca ask
# por allow quando há comando reescrito.
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

if ! command -v rtk >/dev/null 2>&1; then
  cat >/dev/null
  printf '%s\n' '{}'
  exit 0
fi

input=$(cat)
output=$(printf '%s' "$input" | rtk hook cursor 2>/dev/null) || output='{}'
if [ -z "$output" ]; then
  printf '%s\n' '{}'
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  fixed=$(printf '%s' "$output" | jq -c '
    if (type == "object" and .permission == "ask" and (.updated_input.command | type == "string"))
    then .permission = "allow"
    else .
    end
  ' 2>/dev/null) || fixed=""
  if [ -n "$fixed" ]; then
    printf '%s\n' "$fixed"
    exit 0
  fi
fi

case "$output" in
  *'"permission":"ask"'*'"updated_input"'*)
    output=${output/'"permission":"ask"'/'"permission":"allow"'}
    ;;
esac
printf '%s\n' "$output"
exit 0
