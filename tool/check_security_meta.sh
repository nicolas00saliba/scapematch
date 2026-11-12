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

python3 - "$1" "$2" <<'PY'
import pathlib, re, sys

mode, target = sys.argv[1], pathlib.Path(sys.argv[2])
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

def check_flutter(path, csp):
    text = path.read_text()
    require(text, referrer, path)
    require(text, f'<meta http-equiv="Content-Security-Policy" content="{csp}">', path)
    require(text, 'id="scape-frame-guard"', path)
    require(text, "flutter_bootstrap.js", path)
    require(text, 'rel="manifest"', path)
    if "api.pwnedpasswords.com" in csp or "tile.openstreetmap.org" in csp:
        pass
    elif "api.pwnedpasswords.com" in text or "tile.openstreetmap.org" in text:
        raise SystemExit(f"{path} abre rede que o Admin não usa")
    reject(text, path)

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
    for path in pages:
        text = path.read_text()
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
