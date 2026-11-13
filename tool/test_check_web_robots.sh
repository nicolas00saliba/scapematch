#!/usr/bin/env bash
# A checagem passa nos quatro apps e recusa shell sem noindex,
# link escondido, _headers e robots.txt com Disallow.
set -euo pipefail

raiz=$(cd "$(dirname "$0")/.." && pwd)
check="$raiz/tool/check_web_robots.sh"

bash "$check"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pagina() {
  cat > "$tmp/index.html" <<EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  $1
</head>
<body>
  $2
</body>
</html>
EOF
}

recusa() {
  if bash "$check" "$tmp/index.html"; then
    echo "a checagem aceitou: $1" >&2
    exit 1
  fi
}

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<p><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>'
bash "$check" "$tmp/index.html"

pagina '' \
  '<p><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>'
recusa "sem meta robots"

pagina '<meta name="robots" content="noindex">' \
  '<p><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>'
recusa "noindex sem nofollow"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<p><a href="https://escapematch.com.br.evil/">Site oficial do EscapeMatch</a></p>'
recusa "host parecido"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<p style="display:none"><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>'
recusa "link escondido"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<noscript><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></noscript>'
recusa "link só no noscript"

pagina '<!-- <meta name="robots" content="noindex, nofollow"> -->' \
  '<p><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>'
recusa "meta só em comentário"

printf 'User-agent: *\n# Disallow: /\nDisallow:\nAllow: /\n' > "$tmp/robots.txt"
pagina '<meta name="robots" content="noindex, nofollow">' \
  '<p><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>'
bash "$check" "$tmp/index.html"

printf 'User-agent: *\nDisallow: /\n' > "$tmp/robots.txt"
recusa "robots.txt com Disallow"
rm "$tmp/robots.txt"

printf '/\n  X-Robots-Tag: noindex, nofollow\n' > "$tmp/_headers"
recusa "_headers ignorado pelo Pages"
rm "$tmp/_headers"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<p><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></p>
   <script src="flutter_bootstrap.js"></script>'
recusa "link solto no app"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<div id="scape-splash"><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></div>
   <p><a href="https://escapematch.com.br/">Outro</a></p>
   <script>
     window.addEventListener("flutter-first-frame", function () {
       var splash = document.getElementById("scape-splash");
       if (splash) splash.remove();
     });
   </script>
   <script src="flutter_bootstrap.js"></script>'
recusa "link extra fora da abertura"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<div id="scape-splash"><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></div>
   <script src="flutter_bootstrap.js"></script>'
recusa "abertura sem flutter-first-frame"

pagina '<meta name="robots" content="noindex, nofollow">' \
  '<div id="scape-splash"><a href="https://escapematch.com.br/">Site oficial do EscapeMatch</a></div>
   <script>
     window.addEventListener("flutter-first-frame", function () {
       var splash = document.getElementById("scape-splash");
       if (splash) splash.remove();
     });
   </script>
   <script src="flutter_bootstrap.js"></script>'
bash "$check" "$tmp/index.html"

echo "checagem de noindex ok"
