#!/usr/bin/env bash
# uso: js_contains.sh <diretório> <texto>
# Sai 0 se algum .js contém o texto, ou o escape \xHH que o dart2js usa.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <diretório> <texto>" >&2
  exit 2
fi

python3 - "$1" "$2" <<'PY'
import pathlib, sys
root, needle = pathlib.Path(sys.argv[1]), sys.argv[2]

def escaped(text):
    parts = []
    for ch in text:
        code = ord(ch)
        if code < 128:
            parts.append(ch)
        elif code < 256:
            parts.append("\\x%02x" % code)
        else:
            parts.append("\\u%04x" % code)
    return "".join(parts)

alt = escaped(needle)
for path in root.rglob("*.js"):
    data = path.read_text(encoding="utf-8", errors="ignore")
    if needle in data or alt in data:
        sys.exit(0)
sys.exit(1)
PY
