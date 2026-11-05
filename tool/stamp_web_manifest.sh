#!/usr/bin/env bash
# Grava id, start_url e scope do manifest com o <base href> do build.
# Jogador real: /scapematch/
# Demonstração: /scapematch/demo/
# Parceiro real: /scapematch/parceiro/
# Parceiro demonstração: /scapematch/parceiro/demo/
# O id separa os quatro apps no mesmo domínio. Um não substitui o outro.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "uso: $0 <diretório do build web>" >&2
  exit 1
fi

dest="$1"
if [ ! -f "$dest/index.html" ] || [ ! -f "$dest/manifest.json" ]; then
  echo "build web incompleto: $dest" >&2
  exit 1
fi

python3 - "$dest" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
index = (root / "index.html").read_text()
match = re.search(r'<base href="([^"]+)">', index)
if not match:
    raise SystemExit("base href ausente")
href = match.group(1)
if not href.startswith("/") or not href.endswith("/"):
    raise SystemExit(f"base href inválido: {href}")
path = root / "manifest.json"
data = json.loads(path.read_text())
data["id"] = href
data["start_url"] = href
data["scope"] = href
path.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n")
print(f"manifest {href}")
PY
