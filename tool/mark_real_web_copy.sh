#!/usr/bin/env bash
# Tira a frase de dados de exemplo do index e do manifest de um build real.
# Liga a meta que o aviso "Instalar o app" espera. A demonstração conserva
# a frase e não ganha essa meta. Não mexe no app do celular.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <diretório do build web> <player|partner>" >&2
  exit 1
fi

dest="$1"
role="$2"

python3 - "$dest" "$role" <<'PY'
import pathlib, sys
dest, role = sys.argv[1], sys.argv[2]
root = pathlib.Path(dest)
index = root / "index.html"
manifest = root / "manifest.json"
if role == "player":
    pairs = [
        (
            index,
            "EscapeMatch ajuda a montar grupos para escape rooms. Esta versão usa dados de exemplo.",
            "EscapeMatch ajuda a montar grupos para escape rooms.",
        ),
        (
            manifest,
            "Monte grupos para escape rooms. Esta versão usa dados de exemplo.",
            "Monte grupos para escape rooms.",
        ),
    ]
elif role == "partner":
    pairs = [
        (
            index,
            "EscapeMatch Parceiro é o painel da casa. Saldo, reservas e agenda. Esta versão usa dados de exemplo.",
            "EscapeMatch Parceiro é o painel da casa. Saldo, reservas e agenda.",
        ),
        (
            manifest,
            "Painel da casa no EscapeMatch. Saldo, reservas e agenda. Esta versão usa dados de exemplo.",
            "Painel da casa no EscapeMatch. Saldo, reservas e agenda.",
        ),
    ]
else:
    raise SystemExit(f"papel desconhecido: {role}")

for path, old, new in pairs:
    file = pathlib.Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"frase de exemplo não encontrada em {path}")
    file.write_text(text.replace(old, new, 1))

page = index.read_text()
meta = '<meta name="scapematch-install" content="real">'
if meta not in page:
    if "</head>" not in page:
        raise SystemExit(f"head ausente em {index}")
    page = page.replace("</head>", f"  {meta}\n</head>", 1)
    index.write_text(page)
PY
