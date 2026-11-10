#!/usr/bin/env bash
# Confere que o build web publicou o ícone da splash e que o manifesto
# aponta para esse arquivo. Sem o arquivo, a abertura reserva o espaço
# do pin e só pinta o letreiro.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <diretório do build web> <player|partner>" >&2
  exit 1
fi

python3 - "$1" "$2" <<'PY'
import base64, json, pathlib, sys

root = pathlib.Path(sys.argv[1])
role = sys.argv[2]
manifest_path = root / "assets" / "AssetManifest.bin.json"
if not manifest_path.is_file():
    raise SystemExit(f"manifesto ausente: {manifest_path}")
blob = base64.b64decode(json.loads(manifest_path.read_text()))

def require_file(path: pathlib.Path, magic: bytes) -> None:
    if not path.is_file() or path.stat().st_size < 32:
        raise SystemExit(f"ícone da splash ausente: {path}")
    data = path.read_bytes()[: len(magic)]
    if data != magic:
        raise SystemExit(f"ícone da splash ilegível: {path}")

def require_key(key: str) -> None:
    if key.encode() not in blob:
        raise SystemExit(f"manifesto sem {key}")

if role == "player":
    svg = b"<svg"
    require_file(root / "assets/assets/brand/logo_simbolo.svg", svg)
    require_file(root / "assets/assets/brand/logo_simbolo_claro.svg", svg)
    require_key("assets/brand/logo_simbolo.svg")
    require_key("assets/brand/logo_simbolo_claro.svg")
    packaged = b"packages/scapematch/assets/brand/logo_simbolo.svg"
    if packaged in blob:
        raise SystemExit("o jogador publicou a chave do pin com packages/")
elif role == "partner":
    require_file(root / "assets/assets/parceiro/logo_parceiro_pin.png", b"\x89PNG")
    require_file(
        root / "assets/packages/scapematch/assets/brand/logo_simbolo.svg",
        b"<svg",
    )
    require_key("assets/parceiro/logo_parceiro_pin.png")
    require_key("packages/scapematch/assets/brand/logo_simbolo.svg")
else:
    raise SystemExit("papel deve ser player ou partner")
PY
