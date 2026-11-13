#!/usr/bin/env bash
# Confere noindex, nofollow no shell web de app, demo, parceiro e admin.
# O deploy (deploy-web.yml) publica no GitHub Pages, que ignora _headers
# e não envia X-Robots-Tag. A meta robots é o sinal que o Google lê.
# Não pode haver Disallow: o rastreador precisa baixar o HTML.
set -euo pipefail

raiz=$(cd "$(dirname "$0")/.." && pwd)

python3 - "$raiz" "$@" <<'PY'
import pathlib, sys
from html.parser import HTMLParser

raiz = pathlib.Path(sys.argv[1])
alvos = sys.argv[2:]
meta = "noindex, nofollow"
oficial = "https://escapematch.com.br"

fontes = (
    ("app", raiz / "web/index.html"),
    ("demo", raiz / "web/index.html"),
    ("parceiro", raiz / "apps/parceiro/web/index.html"),
    ("admin", raiz / "apps/admin/web/index.html"),
    ("demo/parceiro", raiz / "tool/parceiro_demo_redirect/index.html"),
)
pastas = (
    raiz / "web",
    raiz / "apps/parceiro/web",
    raiz / "apps/admin/web",
)


class Pagina(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.robots = []
        self.links = []
        self._pilha = []
        self._ancora = None
        self._texto = []

    def handle_starttag(self, tag, attrs):
        atributos = {chave.lower(): valor for chave, valor in attrs}
        estilo = (atributos.get("style") or "").lower().replace(" ", "")
        escondido = (
            any(item[1] for item in self._pilha)
            or any(item[0] == "noscript" for item in self._pilha)
            or "hidden" in atributos
            or atributos.get("aria-hidden") == "true"
            or "display:none" in estilo
            or "visibility:hidden" in estilo
        )
        self._pilha.append((tag, escondido))
        if tag == "meta" and (atributos.get("name") or "").lower() == "robots":
            self.robots.append((atributos.get("content") or "").strip())
        if tag == "a":
            self._ancora = {
                "href": atributos.get("href") or "",
                "escondido": escondido,
            }
            self._texto = []

    def handle_endtag(self, tag):
        if tag == "a" and self._ancora is not None:
            self._ancora["texto"] = "".join(self._texto).strip()
            self.links.append(self._ancora)
            self._ancora = None
            self._texto = []
        for indice in range(len(self._pilha) - 1, -1, -1):
            if self._pilha[indice][0] == tag:
                del self._pilha[indice]
                break

    def handle_data(self, data):
        if self._ancora is not None:
            self._texto.append(data)


def eh_oficial(href):
    base = href.split("#", 1)[0].split("?", 1)[0]
    return base.rstrip("/") == oficial


def bloqueia(texto):
    for linha in texto.splitlines():
        linha = linha.split("#", 1)[0].strip()
        if not linha.lower().startswith("disallow:"):
            continue
        caminho = linha.split(":", 1)[1].strip()
        if caminho:
            return True
    return False


def conferir_html(path):
    if not path.is_file():
        raise SystemExit(f"ausente: {path}")
    pagina = Pagina()
    pagina.feed(path.read_text())
    if pagina.robots != [meta]:
        raise SystemExit(
            f"{path}: a meta robots tem de ser {meta!r}, veio {pagina.robots!r}"
        )
    links = [item for item in pagina.links if eh_oficial(item["href"])]
    if not links:
        raise SystemExit(f"{path}: falta o link visível para {oficial}/")
    if not any(item["texto"] and not item["escondido"] for item in links):
        raise SystemExit(
            f"{path}: o link para {oficial}/ está escondido ou sem texto"
        )


def conferir_pasta(pasta):
    cabecalho = pasta / "_headers"
    if cabecalho.exists():
        raise SystemExit(
            f"{cabecalho} não vale: o GitHub Pages ignora _headers "
            "e não envia X-Robots-Tag. O noindex fica na meta robots."
        )
    robots = pasta / "robots.txt"
    if robots.is_file() and bloqueia(robots.read_text()):
        raise SystemExit(
            f"{robots} bloqueia o rastreio. O Google precisa ler o noindex."
        )


if alvos:
    pares = [(pathlib.Path(item).as_posix(), pathlib.Path(item)) for item in alvos]
    pastas_alvo = []
else:
    pares = [(rotulo, caminho) for rotulo, caminho in fontes]
    pastas_alvo = list(pastas)

for rotulo, caminho in pares:
    conferir_html(caminho)
    if alvos:
        conferir_pasta(caminho.parent)
    print(f"noindex ok: {rotulo}")

for pasta in pastas_alvo:
    conferir_pasta(pasta)
PY
