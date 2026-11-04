#!/usr/bin/env bash
# Copia o worker que se desregistra para um build web do Flutter.
# O flutter build --pwa-strategy=none grava um arquivo vazio no lugar;
# este passo publica o script que limpa o cache de quem ainda tem o worker antigo.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "uso: $0 <diretório do build web>" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$1"
if [ ! -d "$dest" ]; then
  echo "diretório inexistente: $dest" >&2
  exit 1
fi

cp "$root/tool/flutter_service_worker.js" "$dest/flutter_service_worker.js"
