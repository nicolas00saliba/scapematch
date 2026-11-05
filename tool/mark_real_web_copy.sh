#!/usr/bin/env bash
# Tira a frase de dados de exemplo do index.html de um build real.
# A demonstração conserva a frase. Não mexe no app do celular.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <diretório do build web> <player|partner>" >&2
  exit 1
fi

dest="$1"
role="$2"
index="$dest/index.html"
if [ ! -f "$index" ]; then
  echo "arquivo ausente: $index" >&2
  exit 1
fi

python3 - "$index" "$role" <<'PY'
import pathlib, sys
path, role = sys.argv[1], sys.argv[2]
file = pathlib.Path(path)
text = file.read_text()
if role == "player":
    old = "ScapeMatch ajuda a montar grupos para escape rooms. Esta versão usa dados de exemplo."
    new = "ScapeMatch ajuda a montar grupos para escape rooms."
elif role == "partner":
    old = "ScapeMatch Parceiro é o painel da casa. Saldo, reservas e agenda. Esta versão usa dados de exemplo."
    new = "ScapeMatch Parceiro é o painel da casa. Saldo, reservas e agenda."
else:
    raise SystemExit(f"papel desconhecido: {role}")
if old not in text:
    raise SystemExit(f"frase de exemplo não encontrada em {path}")
file.write_text(text.replace(old, new, 1))
PY
