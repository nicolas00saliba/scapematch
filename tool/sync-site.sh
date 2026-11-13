#!/usr/bin/env bash
# Publica o build de apps/site no GitHub Pages nicolas00saliba/scapematch-site.
#
# Substitui o sync.sh daquele repositório, que copiava apps/landing.
# Não roda no CI e não faz push sozinho. O push pede --push e o ok do Nícolas.
#
# O DSN do site é a variável PUBLIC_SENTRY_DSN neste ambiente. Sem ela,
# o build sai com o SDK inerte. Não é variável da Cloudflare Pages.
#
# O CNAME publicado sai de apps/site/dist e tem de ser escapematch.com.br.
# Se o dist ou o CNAME já existente no Pages divergir, o script aborta.
# Ele não grava outro domínio no lugar.
#
# O Pages de scapematch-site é Jekyll na raiz da main. Sem .nojekyll ele
# descarta dist/_astro e o site sobe sem CSS. O arquivo é preservado no
# destino e recriado se faltar. O script nunca o apaga.
#
# INDEXNOW=1, e só depois do --push, espera a chave em
# https://escapematch.com.br/<chave>.txt (até 5 min, a cada 15 s) e
# então envia as URLs do sitemap. Se a chave não aparecer, avisa e
# segue com código 0: o site já foi publicado. Fica desligado por
# padrão. Ligue só depois de verificar o domínio no Bing Webmaster Tools.
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

# No box, o DSN do site fica em ~/.secrets/sentry-site.env (chmod 600,
# fora do repositório). Uma variável já exportada tem prioridade.
SENTRY_ENV_FILE="${SENTRY_SITE_ENV:-$HOME/.secrets/sentry-site.env}"
if [ -z "${PUBLIC_SENTRY_DSN:-}" ] && [ -z "${SENTRY_DSN:-}" ] && [ -r "$SENTRY_ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$SENTRY_ENV_FILE"
fi

cd "$ROOT/apps/site"
npm ci
# O HTML publicado nasce aqui, não na Cloudflare Pages.
# PUBLIC_SENTRY_DSN vazio deixa o SDK inerte. O release é o SHA deste repo.
release="${PUBLIC_SENTRY_RELEASE:-}"
if [ -z "$release" ]; then
  release="$(git -C "$ROOT" rev-parse HEAD)"
fi
export PUBLIC_SENTRY_DSN="${PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}"
export PUBLIC_SENTRY_RELEASE="$release"
export PUBLIC_SENTRY_ENVIRONMENT="${PUBLIC_SENTRY_ENVIRONMENT:-production}"
npm run build

cname="$(tr -d '[:space:]' < dist/CNAME)"
if [ "$cname" != "$ESPERADO" ]; then
  echo "dist/CNAME é '$cname'. O esperado é $ESPERADO." >&2
  exit 1
fi
if [ ! -f dist/.nojekyll ]; then
  echo "dist/.nojekyll ausente. O Jekyll do Pages descartaria _astro." >&2
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
if [ -f "$DESTINO/.nojekyll" ]; then
  cp -a "$DESTINO/.nojekyll" "$tmp/.nojekyll"
else
  cp -a "$ROOT/apps/site/dist/.nojekyll" "$tmp/.nojekyll"
fi
find "$DESTINO" -mindepth 1 -maxdepth 1 \
  ! -name '.git' ! -name '.github' ! -name 'README.md' ! -name 'sync.sh' ! -name 'CNAME' ! -name '.nojekyll' \
  -exec rm -rf {} +
cp -a "$ROOT/apps/site/dist/." "$DESTINO/"
cp -a "$tmp/CNAME" "$DESTINO/CNAME"
if [ ! -f "$DESTINO/.nojekyll" ]; then
  cp -a "$tmp/.nojekyll" "$DESTINO/.nojekyll"
fi
rm -rf "$tmp"

if [ ! -f "$DESTINO/.nojekyll" ]; then
  echo ".nojekyll ausente no destino. Abortado, sem commit." >&2
  exit 1
fi

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

if [ "${INDEXNOW:-}" != "1" ]; then
  echo "IndexNow desligado. Verifique o domínio no Bing Webmaster Tools e exporte INDEXNOW=1 para enviar o sitemap."
  exit 0
fi
python3 "$ROOT/tool/indexnow_ping.py" \
  --dist "$ROOT/apps/site/dist" \
  --public "$ROOT/apps/site/public"
