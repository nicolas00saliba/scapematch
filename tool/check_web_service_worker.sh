#!/usr/bin/env bash
# Confere o build web: sem worker de cache, com o script que se desregistra.
# Para o jogador, também confere o script do index que solta o worker antigo
# quando o shell abre num caminho do Parceiro.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <diretório do build web> <player|partner|admin>" >&2
  exit 1
fi

dest="$1"
role="$2"
worker="$dest/flutter_service_worker.js"
bootstrap="$dest/flutter_bootstrap.js"
index="$dest/index.html"

for file in "$worker" "$bootstrap" "$index"; do
  if [ ! -f "$file" ]; then
    echo "arquivo ausente: $file" >&2
    exit 1
  fi
done

grep -F -q 'self.registration.unregister' "$worker"
grep -F -q 'caches.delete' "$worker"
grep -F -q 'client.navigate' "$worker"
if grep -F -q 'flutter-app-cache' "$worker"; then
  echo 'O service worker ainda é o de cache do Flutter.' >&2
  exit 1
fi

# O bootstrap do --pwa-strategy=none chama o loader sem registrar worker.
# O flutter.js embutido cita serviceWorkerSettings; a chamada é que importa.
if ! tail -n 8 "$bootstrap" | grep -F -q '_flutter.loader.load();'; then
  echo 'O bootstrap ainda registra o service worker.' >&2
  tail -n 8 "$bootstrap" >&2
  exit 1
fi

if [ "$role" = "player" ]; then
  grep -F -q "sessionStorage.getItem('scape-partner-shell')" "$index"
  grep -F -q 'reg.unregister()' "$index"
  grep -F -q "marker + '/'" "$index"
  grep -F -q 'reg.update()' "$index"
elif [ "$role" = "partner" ] || [ "$role" = "admin" ]; then
  grep -F -q 'reg.update()' "$index"
  if grep -F -q 'scape-partner-shell' "$index"; then
    echo 'O index deste app não deve carregar o script do shell do jogador.' >&2
    exit 1
  fi
else
  echo "papel desconhecido: $role" >&2
  exit 1
fi
