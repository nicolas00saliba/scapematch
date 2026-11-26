#!/usr/bin/env bash
# Confere stamp_web_build.sh e web_version_check.js sem build do Flutter.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

node "$root/tool/test_web_version_check.js"

fake_build() {
  local dest="$1"
  local shell="$2"
  local body="$3"
  mkdir -p "$dest"
  cp "$root/$shell/index.html" "$dest/index.html"
  printf '%s\n' \
    '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};' \
    '_flutter.loader.load();' > "$dest/flutter_bootstrap.js"
  printf '%s\n' "$body" > "$dest/main.dart.js"
}

id_of() {
  sed -n 's/.*name="scapematch-build" content="\([0-9a-f]\{12\}\)".*/\1/p' "$1/index.html" | head -n 1
}

for shell in web apps/parceiro/web apps/admin/web; do
  name="$(echo "$shell" | tr '/' '_')"
  fake_build "$tmp/$name-a" "$shell" 'bundle um'
  fake_build "$tmp/$name-b" "$shell" 'bundle um'
  fake_build "$tmp/$name-c" "$shell" 'bundle dois'
  for variant in a b c; do
    bash "$root/tool/stamp_web_build.sh" "$tmp/$name-$variant" >/dev/null
  done
  id_a="$(id_of "$tmp/$name-a")"
  id_b="$(id_of "$tmp/$name-b")"
  id_c="$(id_of "$tmp/$name-c")"
  [ -n "$id_a" ] || { echo "sem versão em $shell" >&2; exit 1; }
  [ "$id_a" = "$id_b" ] || { echo "a versão não é estável em $shell" >&2; exit 1; }
  [ "$id_a" != "$id_c" ] || { echo "bundle novo manteve a versão em $shell" >&2; exit 1; }
  grep -F -q "flutter_bootstrap.js?v=$id_a" "$tmp/$name-a/index.html"
  grep -F -q '"mainJsPath":"main.dart.js?v='"$id_a"'"' "$tmp/$name-a/flutter_bootstrap.js"
  grep -F -q 'id="scape-version-check"' "$tmp/$name-a/index.html"
  # Nenhuma referência sem versão sobra no carregamento.
  if grep -E -q "src\s*=\s*['\"]flutter_bootstrap\.js['\"]" "$tmp/$name-a/index.html"; then
    echo "index de $shell ainda carrega flutter_bootstrap.js sem versão" >&2
    exit 1
  fi
  # Rodar duas vezes no mesmo build não pode empilhar versões.
  if bash "$root/tool/stamp_web_build.sh" "$tmp/$name-a" 2>/dev/null; then
    echo "stamp_web_build.sh aceitou um build já versionado" >&2
    exit 1
  fi
done

echo "stamp_web_build ok"
