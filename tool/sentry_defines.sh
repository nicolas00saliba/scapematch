#!/usr/bin/env bash
# Imprime os --dart-define do Sentry. Sem DSN, o valor vai vazio e o SDK fica inerte.
set -euo pipefail

app="${1:-}"
ambiente="${2:-production}"

case "$app" in
  app) variavel=SENTRY_DSN_APP ;;
  parceiro) variavel=SENTRY_DSN_PARCEIRO ;;
  admin) variavel=SENTRY_DSN_ADMIN ;;
  *)
    echo "uso: $0 app|parceiro|admin [production|demo]" >&2
    exit 1
    ;;
esac

case "$ambiente" in
  production|demo) ;;
  *)
    echo "ambiente deve ser production ou demo" >&2
    exit 1
    ;;
esac

dsn="${!variavel:-}"
release="${SENTRY_RELEASE:-}"

printf -- '--dart-define=SENTRY_DSN=%s --dart-define=SENTRY_RELEASE=%s --dart-define=SENTRY_ENVIRONMENT=%s' \
  "$dsn" "$release" "$ambiente"
