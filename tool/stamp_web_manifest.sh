#!/usr/bin/env bash
# Grava a identidade de instalação no manifest, no título e no worker.
# Cada build leva id, start_url e scope absolutos e distintos:
#   jogador real     https://app.escapematch.com.br/
#   jogador demo     https://demo.escapematch.com.br/
#   Parceiro real    https://parceiro.escapematch.com.br/
#   Parceiro demo    https://parceiro-demo.escapematch.com.br/
# O Pages antigo em /scapematch/… usa o host do github.io mais o base href.
# Rode depois de install_cleanup_service_worker.sh.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "uso: $0 <diretório do build web> <player|partner> <real|demo>" >&2
  exit 1
fi

dest="$1"
role="$2"
mode="$3"
tool_dir="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$dest/index.html" ] || [ ! -f "$dest/manifest.json" ]; then
  echo "build web incompleto: $dest" >&2
  exit 1
fi
if [ ! -f "$dest/flutter_service_worker.js" ]; then
  echo "service worker ausente em $dest (rode install_cleanup_service_worker.sh antes)" >&2
  exit 1
fi

python3 - "$dest" "$role" "$mode" "$tool_dir" <<'PY'
import json, pathlib, re, sys
sys.path.insert(0, sys.argv[4])
from web_install_identity import install_identity, install_names

root = pathlib.Path(sys.argv[1])
role, mode = sys.argv[2], sys.argv[3]
index_path = root / "index.html"
index = index_path.read_text()
match = re.search(r'<base href="([^"]+)">', index)
if not match:
    raise SystemExit("base href ausente")
href = match.group(1)
identity = install_identity(role, mode, href)
name, short = install_names(role, mode)

manifest_path = root / "manifest.json"
data = json.loads(manifest_path.read_text())
data["id"] = identity
data["start_url"] = identity
data["scope"] = identity
data["name"] = name
data["short_name"] = short
manifest_path.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n")

index, n = re.subn(r"<title>[^<]*</title>", f"<title>{name}</title>", index, count=1)
if n != 1:
    raise SystemExit("title ausente")
index, n = re.subn(
    r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")',
    rf"\1{name}\2",
    index,
    count=1,
)
if n != 1:
    raise SystemExit("apple-mobile-web-app-title ausente")
index_path.write_text(index)

worker_path = root / "flutter_service_worker.js"
worker = worker_path.read_text()
marker = "__SCAPEMATCH_INSTALL_ID__"
stamped = f'const INSTALL_ID = "{identity}";'
if marker in worker:
    worker = worker.replace(marker, identity, 1)
elif stamped not in worker:
    raise SystemExit("worker sem marcador de identidade")
worker_path.write_text(worker)
print(f"manifest {identity} {name}")
PY
