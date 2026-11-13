#!/usr/bin/env bash
# Confere a CSP e o Referrer-Policy publicados no HTML.
# O GitHub Pages clássico ignora _headers. HSTS, X-Frame-Options,
# X-Content-Type-Options e o Access-Control-Allow-Origin do Pages
# não podem ser definidos daqui.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 flutter <index.html>" >&2
  echo "     $0 admin <index.html>" >&2
  echo "     $0 landing <diretório>" >&2
  echo "     $0 site <diretório>" >&2
  exit 1
fi

raiz=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$1" "$2" "$raiz" <<'PY'
import base64, hashlib, os, pathlib, re, sys

mode, target, repo = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
# sentry_flutter 10.3.0 (sentry_js_sdk_version.dart): JS SDK 11.0.0.
# O release pede o .min; o debug pede o bundle sem minificar. Os dois
# hashes são os integrity que o pacote grava no script da CDN.
sdk_version = "11.0.0"
sdk_bundles = {
    "bundle.tracing.min.js":
        "sha384-TcpSGbL8WtdpR8lXDGGaurUtinn44aaUcN/5iratedpnLQZYJpnJlzK4pdS8sBn5",
    "bundle.tracing.js":
        "sha384-hlI/tESUJSweV0xHfXj9uDHTAXNGExvDMzSQy/tiwSZ/o14fLbBfq7wKSCebkOgN",
}
flutter_csp = (
    "default-src 'self'; base-uri 'self'; object-src 'none'; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' "
    "https://www.gstatic.com/flutter-canvaskit/ blob:; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob: https:; "
    # Roboto e Noto saem de fonts.gstatic.com/s/ via fetch (connect-src).
    # font-src não cobre esse fetch; ícone e Poppins continuam em 'self'.
    "font-src 'self' data:; "
    "connect-src 'self' https://eujlhicairvksvmssruz.supabase.co "
    "wss://eujlhicairvksvmssruz.supabase.co "
    "https://api.pwnedpasswords.com "
    "https://www.gstatic.com/flutter-canvaskit/ "
    "https://fonts.gstatic.com/s/ "
    "https://tile.openstreetmap.org "
    "https://*.ingest.sentry.io https://*.ingest.us.sentry.io "
    "https://*.ingest.de.sentry.io; "
    "worker-src 'self' blob:; frame-src 'none'; "
    "manifest-src 'self'; form-action 'self'"
)
# O Admin não consulta senha vazada nem o mapa.
admin_csp = (
    "default-src 'self'; base-uri 'self'; object-src 'none'; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' "
    "https://www.gstatic.com/flutter-canvaskit/ blob:; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob: https:; "
    "font-src 'self' data:; "
    "connect-src 'self' https://eujlhicairvksvmssruz.supabase.co "
    "wss://eujlhicairvksvmssruz.supabase.co "
    "https://www.gstatic.com/flutter-canvaskit/ "
    "https://fonts.gstatic.com/s/ "
    "https://*.ingest.sentry.io https://*.ingest.us.sentry.io "
    "https://*.ingest.de.sentry.io; "
    "worker-src 'self' blob:; frame-src 'none'; "
    "manifest-src 'self'; form-action 'self'"
)
landing_csp = (
    "default-src 'self'; base-uri 'self'; object-src 'none'; "
    "script-src 'self'; style-src 'self'; img-src 'self'; "
    "font-src 'self'; connect-src 'self'; worker-src 'none'; "
    "frame-src 'none'; manifest-src 'self'; form-action 'self'"
)
site_csp = (
    "default-src 'self'; base-uri 'self'; object-src 'none'; "
    "script-src 'self'; style-src 'self'; img-src 'self'; "
    "font-src 'self'; connect-src 'self' "
    "https://*.ingest.sentry.io https://*.ingest.us.sentry.io "
    "https://*.ingest.de.sentry.io; worker-src 'none'; "
    "frame-src 'none'; manifest-src 'self'; form-action 'self'"
)
referrer = '<meta name="referrer" content="strict-origin-when-cross-origin">'
fake_meta = (
    'http-equiv="X-Frame-Options"',
    'http-equiv="X-Content-Type-Options"',
    'http-equiv="Strict-Transport-Security"',
)

def require(text, needle, where):
    if needle not in text:
        raise SystemExit(f"ausente em {where}: {needle}")

def reject(text, where):
    for item in fake_meta:
        if item in text:
            raise SystemExit(f"{where} finge o cabeçalho {item}; o navegador ignora isso em meta")
    for policy in re.findall(
        r'http-equiv="Content-Security-Policy" content="([^"]*)"', text
    ):
        for item in ("frame-ancestors", "report-uri", "sandbox"):
            if item in policy:
                raise SystemExit(
                    f"{where} põe {item} na CSP em meta; o navegador ignora"
                )

def sri(path):
    digest = hashlib.sha384(path.read_bytes()).digest()
    return "sha384-" + base64.b64encode(digest).decode("ascii")

def check_sentry_sdk(path):
    # O HTML não cita a CDN. O gancho que troca o endereço fica no JS.
    text = path.read_text()
    if "browser.sentry-cdn.com" in text:
        raise SystemExit(f"{path} cita a CDN do Sentry; o bundle tem de ser 'self'")
    require(text, 'id="sentry-cdn-rewrite"', path)
    require(text, 'src="sentry/sentry-cdn-rewrite.js"', path)
    require(text, 'id="sentry-sdk-local"', path)
    require(
        text,
        f'src="sentry/{sdk_version}/bundle.tracing.min.js"',
        path,
    )
    require(text, f'integrity="{sdk_bundles["bundle.tracing.min.js"]}"', path)
    require(text, 'crossorigin="anonymous"', path)
    canon = repo / "web" / "sentry"
    rewrite = path.parent / "sentry" / "sentry-cdn-rewrite.js"
    if not rewrite.is_file():
        raise SystemExit(f"ausente: {rewrite}")
    if rewrite.read_bytes() != (canon / "sentry-cdn-rewrite.js").read_bytes():
        raise SystemExit(f"{rewrite} difere de web/sentry/sentry-cdn-rewrite.js")
    if "browser.sentry-cdn.com/" not in rewrite.read_text():
        raise SystemExit(f"{rewrite} não reconhece a CDN do Sentry")
    for name, expected in sdk_bundles.items():
        file = path.parent / "sentry" / sdk_version / name
        if not file.is_file():
            raise SystemExit(f"ausente: {file}")
        got = sri(file)
        if got != expected:
            raise SystemExit(
                f"hash de {file} é {got}; o sentry_flutter 10.3.0 espera {expected}"
            )
        canonical = canon / sdk_version / name
        if file.read_bytes() != canonical.read_bytes():
            raise SystemExit(f"{file} difere de {canonical}")

def check_sentry_package():
    lock = (repo / "pubspec.lock").read_text()
    found = re.search(
        r"\n  sentry_flutter:\n(?:    .*\n)*?    version: \"([^\"]+)\"",
        lock,
    )
    if not found:
        raise SystemExit("pubspec.lock sem sentry_flutter")
    version = found.group(1)
    caches = []
    if os.environ.get("PUB_CACHE"):
        caches.append(pathlib.Path(os.environ["PUB_CACHE"]))
    caches.append(pathlib.Path.home() / ".pub-cache")
    dart = None
    for cache in caches:
        candidate = (
            cache / "hosted" / "pub.dev" / f"sentry_flutter-{version}"
            / "lib" / "src" / "web" / "sentry_js_sdk_version.dart"
        )
        if candidate.is_file():
            dart = candidate
            break
    if dart is None:
        return
    source = dart.read_text()
    js = re.search(r"sentryJsSdkVersion = '([^']+)'", source)
    prod = re.search(r"productionIntegrity =\s*'([^']+)'", source)
    debug = re.search(r"debugIntegrity =\s*'([^']+)'", source)
    if not js or not prod or not debug:
        raise SystemExit(f"não li a versão do JS SDK em {dart}")
    if js.group(1) != sdk_version:
        raise SystemExit(
            f"sentry_flutter {version} pede o JS {js.group(1)}; "
            f"o repo publica {sdk_version}"
        )
    if prod.group(1) != sdk_bundles["bundle.tracing.min.js"]:
        raise SystemExit(
            f"integrity de release mudou em {dart}: {prod.group(1)}"
        )
    if debug.group(1) != sdk_bundles["bundle.tracing.js"]:
        raise SystemExit(
            f"integrity de debug mudou em {dart}: {debug.group(1)}"
        )

def check_flutter(path, csp):
    text = path.read_text()
    require(text, referrer, path)
    require(text, f'<meta http-equiv="Content-Security-Policy" content="{csp}">', path)
    if "browser.sentry-cdn.com" in csp:
        raise SystemExit(f"{path} libera a CDN do Sentry na CSP")
    require(text, 'id="scape-frame-guard"', path)
    require(text, "flutter_bootstrap.js", path)
    require(text, 'rel="manifest"', path)
    if "api.pwnedpasswords.com" in csp or "tile.openstreetmap.org" in csp:
        pass
    elif "api.pwnedpasswords.com" in text or "tile.openstreetmap.org" in text:
        raise SystemExit(f"{path} abre rede que o Admin não usa")
    reject(text, path)
    check_sentry_sdk(path)
    check_sentry_package()

def check_landing(directory, csp):
    if (directory / "_headers").exists():
        raise SystemExit(f"{directory}/_headers não é aplicado pelo GitHub Pages")
    pages = sorted(directory.rglob("*.html"))
    if len(pages) < 5:
        raise SystemExit(f"esperava as páginas da landing em {directory}")
    guard = directory / "frame-guard.js"
    if not guard.is_file():
        raise SystemExit("frame-guard.js ausente")
    if "window.top === window.self" not in guard.read_text():
        raise SystemExit("frame-guard.js não testa o iframe")
    guard_tags = (
        '<script src="frame-guard.js"></script>',
        '<script src="/frame-guard.js"></script>',
    )
    def verificacao_google(path, text):
        # Arquivo que o Search Console pede na raiz, sem HTML em volta.
        # O conteúdo tem de ser exatamente a linha de verificação.
        if not re.fullmatch(r"google[A-Za-z0-9]{16,}\.html", path.name):
            return False
        return text.strip() == f"google-site-verification: {path.name}"

    for path in pages:
        text = path.read_text()
        if verificacao_google(path, text):
            continue
        require(text, referrer, path)
        require(text, f'<meta http-equiv="Content-Security-Policy" content="{csp}">', path)
        if not any(tag in text for tag in guard_tags):
            raise SystemExit(f"ausente em {path}: frame-guard.js")
        if "unsafe-eval" in text or "gstatic" in text or "supabase.co" in text:
            raise SystemExit(f"CSP da landing folgada em {path}")
        reject(text, path)

if mode == "flutter":
    check_flutter(target, flutter_csp)
elif mode == "admin":
    check_flutter(target, admin_csp)
elif mode == "landing":
    check_landing(target, landing_csp)
elif mode == "site":
    check_landing(target, site_csp)
else:
    raise SystemExit(f"modo desconhecido: {mode}")
PY
