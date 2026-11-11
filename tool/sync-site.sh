#!/usr/bin/env bash
# Publica o build de apps/site no GitHub Pages nicolas00saliba/scapematch-site.
#
# Substitui o sync.sh daquele repositório, que copiava apps/landing.
# Não roda no CI e não faz push sozinho. O push pede --push e o ok do Nícolas.
#
# O CNAME publicado sai de apps/site/dist e tem de ser escapematch.com.br.
# Se o dist ou o CNAME já existente no Pages divergir, o script aborta.
# Ele não grava outro domínio no lugar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ESPERADO="escapematch.com.br"
PUSH=0
DESTINO="${SITE_REPO:-}"

for arg in "$@"; do
  case "$arg" in
    --push) PUSH=1 ;;
    *)
      echo "uso: $0 [--push]" >&2
      echo "SITE_REPO aponta para um clone de nicolas00saliba/scapematch-site." >&2
      exit 2
      ;;
  esac
done

cd "$ROOT/apps/site"
npm ci
npm run build

cname="$(tr -d '[:space:]' < dist/CNAME)"
if [ "$cname" != "$ESPERADO" ]; then
  echo "dist/CNAME é '$cname'. O esperado é $ESPERADO." >&2
  exit 1
fi

if [ -z "$DESTINO" ]; then
  echo "Build pronto em apps/site/dist, com CNAME $ESPERADO."
  echo "Para publicar, exporte SITE_REPO e rode de novo com --push, depois do ok."
  exit 0
fi

if [ ! -d "$DESTINO/.git" ]; then
  echo "SITE_REPO não é um clone git: $DESTINO" >&2
  exit 1
fi

if [ -f "$DESTINO/CNAME" ]; then
  atual="$(tr -d '[:space:]' < "$DESTINO/CNAME")"
  if [ "$atual" != "$ESPERADO" ]; then
    echo "O CNAME do Pages é '$atual'. Abortado, sem regravar." >&2
    exit 1
  fi
fi

tmp="$(mktemp -d)"
cp -a "$DESTINO/CNAME" "$tmp/CNAME" 2>/dev/null || cp -a "$ROOT/apps/site/dist/CNAME" "$tmp/CNAME"
find "$DESTINO" -mindepth 1 -maxdepth 1 \
  ! -name '.git' ! -name '.github' ! -name 'README.md' ! -name 'sync.sh' ! -name 'CNAME' \
  -exec rm -rf {} +
cp -a "$ROOT/apps/site/dist/." "$DESTINO/"
cp -a "$tmp/CNAME" "$DESTINO/CNAME"
rm -rf "$tmp"

publicado="$(tr -d '[:space:]' < "$DESTINO/CNAME")"
if [ "$publicado" != "$ESPERADO" ]; then
  echo "CNAME final divergiu. Abortado, sem commit." >&2
  exit 1
fi

if [ "$PUSH" -ne 1 ]; then
  echo "Cópia pronta em $DESTINO. Sem commit. Use --push depois do ok."
  exit 0
fi

git -C "$DESTINO" add -A
git -C "$DESTINO" commit -m "Publica o site Astro de apps/site."
git -C "$DESTINO" push origin HEAD
