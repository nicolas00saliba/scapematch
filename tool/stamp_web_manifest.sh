#!/usr/bin/env bash
# Grava id, start_url e scope do manifest com o <base href> do build.
# Jogador real: / (app.scapematch.com.br)
# Parceiro real: / (parceiro.scapematch.com.br)
# Demonstração jogador: / (demo.scapematch.com.br)
# Demonstração Parceiro: /parceiro/ (demo.scapematch.com.br/parceiro/)
# Na transição o Pages antigo ainda usa /scapematch/… . O id/start_url/scope
# acompanham o <base href> de cada build.
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
