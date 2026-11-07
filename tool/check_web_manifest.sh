#!/usr/bin/env bash
# Confere manifest, ícones, título e identidade de instalação de um build web.
# Não exige service worker de cache: o Chrome atual instala sem ele.
# O worker publicado tem de carregar a mesma URL absoluta do manifest.
# A demo do Parceiro, com base "/", é https://parceiro-demo.scapematch.com.br/.
# O Pages antigo em /scapematch/parceiro/demo/ continua no github.io.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "uso: $0 <diretório do build web> <player|partner> <real|demo>" >&2
  exit 1
fi

tool_dir="$(cd "$(dirname "$0")" && pwd)"

python3 - "$1" "$2" "$3" "$tool_dir" <<'PY'
import json, pathlib, re, sys
sys.path.insert(0, sys.argv[4])
from web_install_identity import install_identity, install_names

dest, role, mode = sys.argv[1:4]
root = pathlib.Path(dest)
index = (root / "index.html").read_text()
manifest = json.loads((root / "manifest.json").read_text())
match = re.search(r'<base href="([^"]+)">', index)
if not match:
    raise SystemExit("base href ausente")
href = match.group(1)
identity = install_identity(role, mode, href)
for key in ("id", "start_url", "scope"):
    if manifest.get(key) != identity:
        raise SystemExit(f"{key}={manifest.get(key)!r}, esperado {identity}")
if manifest.get("id") == "/" or not str(manifest.get("id", "")).startswith("https://"):
    raise SystemExit("id precisa ser a URL absoluta do host")
name, short = install_names(role, mode)
if manifest.get("name") != name:
    raise SystemExit(f"name={manifest.get('name')!r}, esperado {name}")
if manifest.get("short_name") != short:
    raise SystemExit(f"short_name={manifest.get('short_name')!r}, esperado {short}")
if f"<title>{name}</title>" not in index:
    raise SystemExit(f"title não é {name}")
apple = f'<meta name="apple-mobile-web-app-title" content="{name}">'
if apple not in index:
    raise SystemExit(f"apple title não é {name}")
if manifest.get("display") != "standalone":
    raise SystemExit("display deve ser standalone")
need = {
    ("192x192", "any"),
    ("512x512", "any"),
    ("192x192", "maskable"),
    ("512x512", "maskable"),
}
found = set()
for icon in manifest.get("icons") or []:
    purpose = icon.get("purpose") or "any"
    for item in str(purpose).split():
        found.add((icon.get("sizes"), item))
        src = root / str(icon.get("src", ""))
        if not src.is_file():
            raise SystemExit(f"ícone ausente: {src}")
missing = need - found
if missing:
    raise SystemExit(f"ícones faltando: {sorted(missing)}")
description = manifest.get("description") or ""
install_meta = '<meta name="scapematch-install" content="real">'
if mode == "real":
    if "dados de exemplo" in description or "dados de exemplo" in index:
        raise SystemExit("o build real ainda fala em dados de exemplo")
    if install_meta not in index:
        raise SystemExit("falta a meta que liga o aviso de instalar")
else:
    if "dados de exemplo" not in description:
        raise SystemExit("a demonstração perdeu a frase de dados de exemplo")
    if install_meta in index:
        raise SystemExit("a demonstração não leva o aviso de instalar")
for needle in (
    "apple-mobile-web-app-capable",
    "apple-mobile-web-app-status-bar-style",
    "apple-mobile-web-app-title",
    "apple-touch-icon",
    "name=\"theme-color\"",
    "viewport-fit=cover",
):
    if needle not in index:
        raise SystemExit(f"index sem {needle}")
worker = (root / "flutter_service_worker.js").read_text()
if f'const INSTALL_ID = "{identity}";' not in worker:
    raise SystemExit("worker sem a identidade deste build")
if "__SCAPEMATCH_INSTALL_ID__" in worker:
    raise SystemExit("worker ainda tem o marcador")
print(f"ok {role} {mode} {identity}")
PY
