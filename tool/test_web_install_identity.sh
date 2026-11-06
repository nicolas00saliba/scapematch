#!/usr/bin/env bash
# Confere que app e demo saem com atalhos diferentes, sem build do Flutter.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

prepare() {
  local dest="$1"
  local shell="$2"
  local href="$3"
  mkdir -p "$dest/icons"
  cp "$root/$shell/index.html" "$dest/index.html"
  cp "$root/$shell/manifest.json" "$dest/manifest.json"
  cp "$root/tool/flutter_service_worker.js" "$dest/flutter_service_worker.js"
  printf '%s\n' '_flutter.loader.load();' > "$dest/flutter_bootstrap.js"
  cp "$root/$shell/icons/"*.png "$dest/icons/"
  python3 - "$dest/index.html" "$href" <<'PY'
import pathlib, sys
path, href = sys.argv[1], sys.argv[2]
file = pathlib.Path(path)
file.write_text(file.read_text().replace("$FLUTTER_BASE_HREF", href, 1))
PY
}

stamp() {
  local dest="$1"
  local role="$2"
  local mode="$3"
  bash "$root/tool/stamp_web_manifest.sh" "$dest" "$role" "$mode"
  if [ "$mode" = "real" ]; then
    bash "$root/tool/mark_real_web_copy.sh" "$dest" "$role"
  fi
  bash "$root/tool/check_web_service_worker.sh" "$dest" "$role"
  bash "$root/tool/check_web_manifest.sh" "$dest" "$role" "$mode"
}

prepare "$tmp/player-real" web "/"
prepare "$tmp/player-demo" web "/"
prepare "$tmp/partner-real" apps/parceiro/web "/"
prepare "$tmp/partner-demo" apps/parceiro/web "/parceiro/"
prepare "$tmp/legacy-player" web "/scapematch/"
prepare "$tmp/legacy-demo" web "/scapematch/demo/"

stamp "$tmp/player-real" player real
stamp "$tmp/player-demo" player demo
stamp "$tmp/partner-real" partner real
stamp "$tmp/partner-demo" partner demo
stamp "$tmp/legacy-player" player real
stamp "$tmp/legacy-demo" player demo

python3 - "$tmp" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
want = {
    "player-real": "https://app.scapematch.com.br/",
    "player-demo": "https://demo.scapematch.com.br/",
    "partner-real": "https://parceiro.scapematch.com.br/",
    "partner-demo": "https://demo.scapematch.com.br/parceiro/",
    "legacy-player": "https://nicolas00saliba.github.io/scapematch/",
    "legacy-demo": "https://nicolas00saliba.github.io/scapematch/demo/",
}
ids = []
for name, identity in want.items():
    manifest = json.loads((root / name / "manifest.json").read_text())
    for key in ("id", "start_url", "scope"):
        if manifest[key] != identity:
            raise SystemExit(f"{name} {key}={manifest[key]!r}")
    worker = (root / name / "flutter_service_worker.js").read_text()
    if f'const INSTALL_ID = "{identity}";' not in worker:
        raise SystemExit(f"{name} worker sem {identity}")
    ids.append(identity)
if len(set(ids)) != len(ids):
    raise SystemExit(f"identidades repetidas: {ids}")
demo = json.loads((root / "player-demo" / "manifest.json").read_text())
real = json.loads((root / "player-real" / "manifest.json").read_text())
if demo["name"] != "ScapeMatch Demo" or demo["short_name"] != "Scape Demo":
    raise SystemExit(f"nome da demo: {demo['name']!r} / {demo['short_name']!r}")
if real["name"] != "ScapeMatch":
    raise SystemExit("o app real mudou de nome")
if "https://app.scapematch.com.br/" in (root / "player-demo" / "flutter_service_worker.js").read_text():
    raise SystemExit("o worker da demo cita o app real")
if "https://demo.scapematch.com.br/" in (root / "player-real" / "flutter_service_worker.js").read_text():
    raise SystemExit("o worker do real cita a demo")
real_index = (root / "player-real" / "index.html").read_text()
demo_index = (root / "player-demo" / "index.html").read_text()
if "<title>ScapeMatch Demo</title>" not in demo_index:
    raise SystemExit("título da demo ausente")
if 'content="ScapeMatch Demo"' not in demo_index:
    raise SystemExit("atalho da Apple da demo ausente")
if "<title>ScapeMatch</title>" not in real_index:
    raise SystemExit("título do real mudou")
print("ok identidades distintas")
PY

WORKER="$tmp/player-demo/flutter_service_worker.js" \
LEGACY="$tmp/legacy-player/flutter_service_worker.js" \
node <<'JS'
const fs = require('fs');
const code = fs.readFileSync(process.env.WORKER, 'utf8');
const api = new Function(
  'self',
  code + '\nreturn { inThisInstall, ownsCache, CACHE_PREFIX };',
)({
  addEventListener() {},
  registration: {scope: 'https://demo.scapematch.com.br/'},
});
const partner = 'scapematch-cache:https://demo.scapematch.com.br/parceiro/|shell';
const mine = api.CACHE_PREFIX + 'shell';
if (api.ownsCache(partner)) {
  throw new Error('o cache da demo do Parceiro cairia no worker do jogador');
}
if (!api.ownsCache(mine) || !api.ownsCache('flutter-app-cache')) {
  throw new Error('o worker deixou de apagar o cache deste app');
}
if (api.inThisInstall('https://demo.scapematch.com.br/parceiro/')) {
  throw new Error('o worker do jogador tomou a demo do Parceiro');
}
if (!api.inThisInstall('https://demo.scapematch.com.br/')) {
  throw new Error('o worker do jogador largou a própria página');
}
const legacy = new Function(
  'self',
  fs.readFileSync(process.env.LEGACY, 'utf8') +
    '\nreturn { inThisInstall, ownsCache };',
)({addEventListener() {}, registration: {scope: ''}});
const legacyDemo = 'https://nicolas00saliba.github.io/scapematch/demo/';
if (legacy.inThisInstall(legacyDemo)) {
  throw new Error('o worker do app antigo tomou a demo do Pages');
}
if (legacy.ownsCache('scapematch-cache:' + legacyDemo + '|shell')) {
  throw new Error('o cache da demo antiga cairia no app real');
}
console.log('ok caches separados');
JS
