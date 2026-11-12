#!/usr/bin/env bash
set -euo pipefail

raiz="$(cd "$(dirname "$0")/.." && pwd)"
script="$raiz/tool/sentry_defines.sh"

saida="$(SENTRY_DSN_APP= SENTRY_RELEASE=abc123 "$script" app production)"
case "$saida" in
  "--dart-define=SENTRY_DSN= --dart-define=SENTRY_RELEASE=abc123 --dart-define=SENTRY_ENVIRONMENT=production") ;;
  *)
    echo "define vazio inesperado: $saida" >&2
    exit 1
    ;;
esac

saida="$(SENTRY_DSN_PARCEIRO=https://publico@ingest.exemplo.invalid/1 SENTRY_RELEASE=def "$script" parceiro demo)"
case "$saida" in
  *"--dart-define=SENTRY_DSN=https://publico@ingest.exemplo.invalid/1 "*) ;;
  *)
    echo "DSN de exemplo não entrou no define: $saida" >&2
    exit 1
    ;;
esac
case "$saida" in
  *"SENTRY_ENVIRONMENT=demo") ;;
  *)
    echo "ambiente demo ausente: $saida" >&2
    exit 1
    ;;
esac

if "$script" app homolog 2>/dev/null; then
  echo "ambiente inválido deveria falhar" >&2
  exit 1
fi

echo "sentry_defines ok"
