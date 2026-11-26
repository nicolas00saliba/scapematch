#!/usr/bin/env bash
# Dá uma versão a cada build web, para ninguém ficar com o bundle antigo.
# O Cloudflare na frente do GitHub Pages serve .js e .json por 4 horas
# (cache-control: max-age=14400) e os nomes não mudam entre builds. Com o
# index novo (10 min) apontando para o mesmo main.dart.js, o celular que já o
# tinha continuava com o app antigo. Aqui o index passa a chamar
# flutter_bootstrap.js?v=ID e o bootstrap, main.dart.js?v=ID: o ID é o hash do
# conteúdo, então um build novo sempre muda a URL. O mesmo ID entra numa meta
# e web_version_check.js recarrega a aba aberta quando o index publicado muda.
# Rode depois do flutter build e antes de copiar o index.html para 404.html.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "uso: $0 <diretório do build web>" >&2
  exit 1
fi

dest="$1"
tool_dir="$(cd "$(dirname "$0")" && pwd)"
for file in index.html flutter_bootstrap.js main.dart.js; do
  if [ ! -f "$dest/$file" ]; then
    echo "arquivo ausente: $dest/$file" >&2
    exit 1
  fi
done

python3 - "$dest" "$tool_dir" <<'PY'
import hashlib, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
check = (pathlib.Path(sys.argv[2]) / "web_version_check.js").read_text()
index_path = root / "index.html"
boot_path = root / "flutter_bootstrap.js"
index = index_path.read_text()
boot = boot_path.read_text()

if "scapematch-build" in index:
    raise SystemExit("o index.html já tem versão")

digest = hashlib.sha256()
for name in ("main.dart.js", "flutter_bootstrap.js", "index.html"):
    digest.update((root / name).read_bytes())
build_id = digest.hexdigest()[:12]

main_ref = '"mainJsPath":"main.dart.js"'
if boot.count(main_ref) != 1:
    raise SystemExit("flutter_bootstrap.js sem mainJsPath esperado")
boot = boot.replace(main_ref, '"mainJsPath":"main.dart.js?v=%s"' % build_id)

boot_ref = re.compile(r"""(\bsrc\s*=\s*)(['"])flutter_bootstrap\.js\2""")
if len(boot_ref.findall(index)) != 1:
    raise SystemExit("o index.html deve carregar flutter_bootstrap.js uma vez")
index = boot_ref.sub(
    lambda m: "%s%sflutter_bootstrap.js?v=%s%s" % (m.group(1), m.group(2), build_id, m.group(2)),
    index,
)

if "</head>" not in index:
    raise SystemExit("index.html sem </head>")
if "</script>" in check:
    raise SystemExit("web_version_check.js não pode conter </script>")
inject = (
    '  <meta name="scapematch-build" content="%s">\n'
    "  <script id=\"scape-version-check\">\n%s</script>\n"
) % (build_id, check)
index = index.replace("</head>", inject + "</head>", 1)

boot_path.write_text(boot)
index_path.write_text(index)
print("versão do build web: %s" % build_id)
PY
