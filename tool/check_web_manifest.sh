#!/usr/bin/env bash
# Confere manifest, ícones e metas de instalação de um build web.
# Não exige service worker: o Chrome atual instala sem ele.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "uso: $0 <diretório do build web> <player|partner> <real|demo>" >&2
  exit 1
fi

python3 - "$1" "$2" "$3" <<'PY'
import json, pathlib, re, sys
dest, role, mode = sys.argv[1:]
if role not in ("player", "partner") or mode not in ("real", "demo"):
    raise SystemExit(f"papel ou modo desconhecido: {role} {mode}")
root = pathlib.Path(dest)
index = (root / "index.html").read_text()
manifest = json.loads((root / "manifest.json").read_text())
match = re.search(r'<base href="([^"]+)">', index)
if not match:
    raise SystemExit("base href ausente")
href = match.group(1)
for key in ("id", "start_url", "scope"):
    if manifest.get(key) != href:
        raise SystemExit(f"{key}={manifest.get(key)!r}, esperado {href}")
name = "ScapeMatch" if role == "player" else "ScapeMatch Parceiro"
short = "ScapeMatch" if role == "player" else "Parceiro"
if manifest.get("name") != name:
    raise SystemExit(f"name={manifest.get('name')!r}")
if manifest.get("short_name") != short:
    raise SystemExit(f"short_name={manifest.get('short_name')!r}")
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
print(f"ok {role} {mode} {href}")
PY
