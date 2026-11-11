#!/usr/bin/env python3
"""Confere o build estático de apps/site/dist."""

import pathlib
import re
import sys
from html.parser import HTMLParser

ROOT = pathlib.Path(__file__).resolve().parents[1]
DIST = ROOT / "apps" / "site" / "dist"
SITE = "https://escapematch.com.br"
DOMINIO_ANTIGO = re.compile(r"(?<![A-Za-z])scapematch\.com\.br")

ROTAS = [
    "/",
    "/como-funciona",
    "/como-funciona/pagamento",
    "/experiencias",
    "/experiencias/escape-room",
    "/guia/escape-room-sozinho",
    "/seguranca",
    "/app",
    "/convite",
    "/vantagens",
    "/vantagens/indique-amigos",
    "/vantagens/indique-uma-casa",
    "/vantagens/niveis",
    "/vantagens/regulamento",
    "/para-casas",
    "/para-casas/como-funciona",
    "/para-casas/precos",
    "/para-casas/cadastro",
    "/para-casas/parceiros",
    "/para-casas/indique-uma-casa",
    "/para-casas/indique-jogadores",
    "/para-casas/horario-vazio",
    "/ajuda",
    "/ajuda/grupo",
    "/ajuda/pagamento",
    "/ajuda/cancelamento",
    "/ajuda/conta",
    "/ajuda/pontos",
    "/ajuda/casas",
    "/sobre",
    "/termos",
    "/termos/parceiro",
    "/privacidade",
    "/cancelamento",
    "/mapa-do-site",
    "/404",
]

NOINDEX = {"/convite", "/404"}
FORA_DO_BUILD = ("/contato", "/cidades/curitiba")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
CANCELAMENTO = (
    "Não há reembolso depois que o grupo é confirmado.",
    "se o grupo não fechar, nada é cobrado",
    "O Pix é estornado e o cartão não é capturado.",
    "Se a casa cancelar, o valor é devolvido integralmente.",
)
COMISSAO_OK = (
    "/para-casas",
    "/termos/parceiro",
    "/vantagens/regulamento",
    "/ajuda/casas",
)
EXTERNOS = {
    "https://app.escapematch.com.br/",
    "https://app.escapematch.com.br/login",
    "https://app.escapematch.com.br/cadastro",
    "https://parceiro.escapematch.com.br/",
}


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []
        self.title = []
        self.in_title = False
        self.metas = []
        self.canonical = ""

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        if tag == "a" and "href" in data:
            self.hrefs.append(data["href"])
        if tag == "title":
            self.in_title = True
            self.title = []
        if tag == "meta":
            self.metas.append(data)
        if tag == "link" and data.get("rel") == "canonical":
            self.canonical = data.get("href", "")

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title.append(data)


def arquivo(rota: str) -> pathlib.Path:
    if rota == "/":
        return DIST / "index.html"
    return DIST / f"{rota.lstrip('/')}.html"


def falha(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if not DIST.is_dir():
        falha("dist ausente. Rode o build em apps/site.")
    cname = (DIST / "CNAME").read_text().strip()
    if cname != "escapematch.com.br" or DOMINIO_ANTIGO.search(cname):
        falha(f"CNAME é {cname!r}")

    home = (DIST / "index.html").read_text()
    if "<title>EscapeMatch: ninguém pra jogar? Agora tem.</title>" not in home:
        falha("título da home ausente")
    if 'class="hero-badge"' not in home:
        falha("selo sem a classe hero-badge")
    if "Escape rooms, jogos de tabuleiro, laser tag e muito mais!" not in home:
        falha("texto do selo ausente")
    if home.find("<h1>") > home.find("hero-badge"):
        falha("o selo ficou antes do título")

    vistos = set()
    for rota in ROTAS:
        path = arquivo(rota)
        if not path.is_file():
            falha(f"rota sem HTML: {rota} ({path.relative_to(DIST)})")
        vistos.add(path.resolve())
        texto = path.read_text()
        parser = Links()
        parser.feed(texto)
        titulo = "".join(parser.title).strip()
        if not titulo:
            falha(f"{rota} sem título")
        if len(titulo) > 60:
            falha(f"{rota} título com {len(titulo)} caracteres: {titulo}")
        descricao = ""
        for meta in parser.metas:
            if meta.get("name") == "description":
                descricao = meta.get("content", "")
        if not descricao:
            falha(f"{rota} sem descrição")
        if len(descricao) > 155:
            falha(f"{rota} descrição com {len(descricao)} caracteres")
        esperado = SITE + ("/" if rota == "/" else rota)
        if parser.canonical != esperado:
            falha(f"{rota} canonical {parser.canonical!r} != {esperado}")
        noindex = any(m.get("name") == "robots" and "noindex" in m.get("content", "") for m in parser.metas)
        if (rota in NOINDEX) != noindex:
            falha(f"{rota} noindex={noindex}")
        if DOMINIO_ANTIGO.search(texto):
            falha(f"{rota} cita o domínio antigo")
        if re.search(r"divid\w* a reserva", texto, re.I):
            falha(f"{rota} usa a promessa antiga")
        if "exemplo.invalid" in texto or "Placeholder" in texto:
            falha(f"{rota} tem placeholder")
        if re.search(r"\b(C2C|B2B|B2C|C2B|bps)\b", texto):
            falha(f"{rota} usa sigla interna")
        sem_selo = re.sub(r"<!doctype html>", "", texto, flags=re.I)
        sem_selo = sem_selo.replace(
            "Escape rooms, jogos de tabuleiro, laser tag e muito mais!", ""
        )
        if "!" in sem_selo:
            falha(f"{rota} tem exclamação fora do selo")
        if "comissão" in texto.lower() or "comissao" in texto.lower():
            permitida = rota == "/ajuda" or any(
                rota == ok or rota.startswith(ok + "/") for ok in COMISSAO_OK
            )
            if not permitida:
                falha(f"{rota} fala em comissão para o jogador")
        for href in parser.hrefs:
            if href.startswith(("#", "mailto:")):
                continue
            if href.startswith("http://") or href.startswith("https://"):
                base = href.split("#")[0]
                if not any(base == item or base.startswith(item) for item in EXTERNOS):
                    if "escapematch.com.br" not in base and "parceiro.escapematch.com.br" not in base:
                        falha(f"{rota} link externo não previsto: {href}")
                if DOMINIO_ANTIGO.search(href) or "parceiro-demo" in href or "demo.escapematch" in href:
                    falha(f"{rota} link proibido: {href}")
                continue
            if not href.startswith("/"):
                falha(f"{rota} link relativo: {href}")
            limpo = href.split("#")[0].split("?")[0]
            if limpo in ("", "/"):
                alvo = DIST / "index.html"
            elif limpo.endswith(".html"):
                alvo = DIST / limpo.lstrip("/")
            else:
                alvo = DIST / f"{limpo.lstrip('/')}.html"
            if not alvo.is_file():
                falha(f"{rota} aponta para {href}, sem {alvo.relative_to(DIST)}")

    if not (DIST / "sitemap-index.xml").is_file() and not (DIST / "sitemap.xml").is_file():
        falha("sitemap ausente")
    sitemap = ""
    for nome in ("sitemap-index.xml", "sitemap-0.xml", "sitemap.xml"):
        arq = DIST / nome
        if arq.is_file():
            sitemap += arq.read_text()
    for rota in ("/convite", "/404", *FORA_DO_BUILD):
        if f"{SITE}{rota}<" in sitemap or f"{SITE}{rota}/" in sitemap:
            falha(f"{rota} entrou no sitemap")
    for rota in ("/termos", "/privacidade", "/cancelamento"):
        if f"{SITE}{rota}<" not in sitemap and f"{SITE}{rota}/" not in sitemap:
            falha(f"{rota} saiu do sitemap")

    for rota in FORA_DO_BUILD:
        path = arquivo(rota)
        if path.exists():
            falha(f"{rota} entrou no build")
    fontes = (
        ROOT / "apps/site/src/pages/_contato.astro",
        ROOT / "apps/site/src/pages/_cidades/[cidade].astro",
    )
    for fonte in fontes:
        if not fonte.is_file():
            falha(f"página saiu do código: {fonte.relative_to(ROOT)}")

    for html in DIST.rglob("*.html"):
        texto = html.read_text()
        if "mailto:" in texto or EMAIL.search(texto):
            falha(f"{html.relative_to(DIST)} mostra e-mail")
        for rota in FORA_DO_BUILD:
            if f'href="{rota}"' in texto or f"href='{rota}'" in texto:
                falha(f"{html.relative_to(DIST)} aponta para {rota}")
    for js in (DIST / "scripts").glob("*.js"):
        texto = js.read_text()
        for rota in FORA_DO_BUILD:
            if rota in texto:
                falha(f"{js.relative_to(DIST)} aponta para {rota}")

    cancelamento = (DIST / "cancelamento.html").read_text()
    for trecho in CANCELAMENTO:
        if trecho not in cancelamento:
            falha(f"cancelamento sem a regra: {trecho}")
    if re.search(r"janela|anteced[eê]ncia|sete dias", cancelamento, re.I):
        falha("cancelamento voltou à regra antiga")

    home_html = (DIST / "index.html").read_text()
    if "Jogue e ganhe pontos." not in home_html or "Junte pontos e jogue de graça." not in home_html:
        falha("a home não mostra a mensagem dos pontos")
    if "Cashback de até 5% em pontos a cada jogo." not in home_html:
        falha("a home não mostra o teto do cashback")
    if "limite mensal" in home_html:
        falha("a home ainda cita limite mensal")
    for rota in ("/vantagens", "/vantagens/niveis", "/vantagens/regulamento", "/ajuda"):
        texto = arquivo(rota).read_text()
        if "jogue de graça" not in texto or "R$ 0,01" not in texto or "vaga inteira" not in texto:
            falha(f"{rota} não mostra a vaga grátis")
        if "limite mensal" in texto:
            falha(f"{rota} ainda cita limite mensal")
        if "até 25%" in texto or "até 30%" in texto:
            falha(f"{rota} ainda promete um teto percentual")
    if '"@type":"Organization"' not in home_html or '"@type":"WebSite"' not in home_html:
        falha("a home saiu sem Organization ou WebSite")
    if '"@type":"FAQPage"' not in home_html:
        falha("a home saiu sem FAQPage")
    if "sameAs" in home_html:
        falha("Organization com sameAs sem perfil publicado no repositório")
    if 'rel="preload"' not in home_html or "woff2" not in home_html:
        falha("fonte sem preload")
    como = arquivo("/como-funciona").read_text()
    if '"@type":"HowTo"' not in como or '"@type":"Service"' not in como:
        falha("como funciona saiu sem HowTo ou Service")
    if '"@type":"BreadcrumbList"' not in como:
        falha("como funciona saiu sem BreadcrumbList")
    guia = arquivo("/guia/escape-room-sozinho").read_text()
    if '"@type":"FAQPage"' not in guia:
        falha("o guia saiu sem FAQPage")
    if "<lastmod>" not in sitemap:
        falha("sitemap sem lastmod")
    for nome in ("llms.txt", "llms-full.txt"):
        texto = (DIST / nome).read_text()
        if "Curitiba" not in texto or "R$ 0,01" not in texto:
            falha(f"{nome} incompleto")
        if "limite mensal" in texto:
            falha(f"{nome} ainda cita limite mensal")
    robots = (DIST / "robots.txt").read_text()
    for bot in (
        "Googlebot",
        "Bingbot",
        "GPTBot",
        "OAI-SearchBot",
        "ChatGPT-User",
        "ClaudeBot",
        "Claude-SearchBot",
        "PerplexityBot",
        "Google-Extended",
        "Applebot",
    ):
        if f"User-agent: {bot}\nAllow: /" not in robots:
            falha(f"robots.txt não libera {bot}")

    print(f"site ok: {len(ROTAS)} rotas")


if __name__ == "__main__":
    main()
