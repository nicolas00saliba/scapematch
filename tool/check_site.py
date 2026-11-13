#!/usr/bin/env python3
"""Confere o build estático de apps/site/dist."""

import json
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
    "/escape-room-curitiba",
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
    "/contato",
    "/termos",
    "/termos/parceiro",
    "/privacidade",
    "/cancelamento",
    "/mapa-do-site",
    "/404",
]

NOINDEX = {"/convite", "/404"}
FORA_DO_BUILD = ("/cidades/curitiba",)
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
EMAIL_CONTATO = "contato@escapematch.com.br"
DEFINICAO = (
    "O EscapeMatch é o aplicativo brasileiro que conecta pessoas para jogar escape room "
    "e, em breve, outros jogos em grupo. Você chega sozinho, entra num grupo e paga só a sua vaga. "
    "Lançamento em Curitiba. Não é um jogo de celular."
)
SELO = "Escape room agora. Jogos de tabuleiro e laser tag em breve."
CHAVE_INDEXNOW = re.compile(r"^[0-9a-f]{32}\.txt$")
TOKEN_BUSCADOR = re.compile(r"^[A-Za-z0-9_-]{16,128}$")
TOKEN_BLOQUEADO = re.compile(
    r"(example|exemplo|changeme|placeholder|fake|teste|sample|your[-_]?token)",
    re.I,
)
ARQUIVO_GOOGLE = re.compile(r"google[A-Za-z0-9]{16,}\.html")
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


def blocos_ld(html: str) -> list:
    saida = []
    for bruto in re.findall(
        r'<script type="application/ld\+json">(.*?)</script>',
        html,
        flags=re.S,
    ):
        dado = json.loads(bruto)
        saida.extend(dado if isinstance(dado, list) else [dado])
    return saida


def exigir_faq(html: str, rota: str, perguntas: tuple[str, ...]) -> None:
    faqs = [bloco for bloco in blocos_ld(html) if bloco.get("@type") == "FAQPage"]
    if len(faqs) != 1:
        falha(f"{rota} saiu com {len(faqs)} FAQPage")
    nomes = [item.get("name") for item in faqs[0].get("mainEntity", [])]
    for pergunta in perguntas:
        if pergunta not in html:
            falha(f"{rota} não mostra a pergunta: {pergunta}")
        if pergunta not in nomes:
            falha(f"{rota} FAQPage sem a pergunta: {pergunta}")


def falha(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def token_ok(valor: str) -> bool:
    if not TOKEN_BUSCADOR.fullmatch(valor) or TOKEN_BLOQUEADO.search(valor):
        return False
    if re.fullmatch(r"(todo|test|x+)", valor, re.I):
        return False
    return len(set(valor)) > 1


def arquivo_google_ok(path: pathlib.Path, texto: str) -> bool:
    if not ARQUIVO_GOOGLE.fullmatch(path.name):
        return False
    if re.search(r"(example|exemplo|placeholder|changeme|fake)", path.name, re.I):
        return False
    return texto.strip() == f"google-site-verification: {path.name}"


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
    if SELO not in home:
        falha("texto do selo ausente")
    if "muito mais!" in home:
        falha("o selo ainda anuncia tabuleiro e laser tag como disponíveis")
    if DEFINICAO not in home:
        falha("a home não mostra a definição canônica")
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
        if "!" in sem_selo:
            falha(f"{rota} tem exclamação")
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
    for rota in ("/termos", "/privacidade", "/cancelamento", "/contato", "/escape-room-curitiba"):
        if f"{SITE}{rota}<" not in sitemap and f"{SITE}{rota}/" not in sitemap:
            falha(f"{rota} saiu do sitemap")

    for rota in FORA_DO_BUILD:
        path = arquivo(rota)
        if path.exists():
            falha(f"{rota} entrou no build")
    fontes = (
        ROOT / "apps/site/src/pages/contato.astro",
        ROOT / "apps/site/src/pages/escape-room-curitiba.astro",
        ROOT / "apps/site/src/pages/_cidades/[cidade].astro",
    )
    for fonte in fontes:
        if not fonte.is_file():
            falha(f"página saiu do código: {fonte.relative_to(ROOT)}")

    for html in DIST.rglob("*.html"):
        texto = html.read_text()
        if html.name.startswith("google") and html.suffix == ".html":
            if not arquivo_google_ok(html, texto):
                falha(f"arquivo de verificação do Google inválido: {html.name}")
            continue
        parser_meta = Links()
        parser_meta.feed(texto)
        for meta in parser_meta.metas:
            if meta.get("name") in ("google-site-verification", "msvalidate.01"):
                if not token_ok(meta.get("content", "")):
                    falha(f"{html.relative_to(DIST)} tem verificação inválida")
        if html.name == "contato.html":
            resto = texto.replace(f"mailto:{EMAIL_CONTATO}", "").replace(EMAIL_CONTATO, "")
            if f"mailto:{EMAIL_CONTATO}" not in texto or EMAIL_CONTATO not in texto:
                falha("contato sem o e-mail publicado")
            if "mailto:" in resto or EMAIL.search(resto):
                falha("contato mostra outro e-mail")
            for trecho in (
                "ESCAPEMATCH TECNOLOGIA LTDA",
                "70.100.608/0001-73",
                "Curitiba-PR",
                'href="/app"',
                'href="https://app.escapematch.com.br/"',
                'href="/para-casas/cadastro"',
                'href="https://parceiro.escapematch.com.br/"',
                '"@type":"ContactPage"',
            ):
                if trecho not in texto:
                    falha(f"contato sem {trecho}")
            if "<form" in texto.lower() or "tel:" in texto.lower():
                falha("contato tem formulário ou telefone")
        else:
            sem_email_org = texto.replace(f'"email":"{EMAIL_CONTATO}"', "")
            if "mailto:" in sem_email_org or EMAIL.search(sem_email_org):
                falha(f"{html.relative_to(DIST)} mostra e-mail")
        if not (html.name.startswith("google") and html.suffix == ".html"):
            try:
                blocos_ld(texto)
            except json.JSONDecodeError:
                falha(f"{html.relative_to(DIST)} tem JSON-LD inválido")
            if "sameAs" in texto or "streetAddress" in texto or "GameApplication" in texto:
                falha(f"{html.relative_to(DIST)} tem sameAs, rua ou GameApplication")
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
    orgs = [
        bloco
        for bloco in blocos_ld(home_html)
        if bloco.get("@type") == "Organization" and bloco.get("legalName")
    ]
    if len(orgs) != 1:
        falha(f"a home saiu com {len(orgs)} Organization com legalName")
    org = orgs[0]
    endereco = org.get("address") or {}
    if org.get("legalName") != "ESCAPEMATCH TECNOLOGIA LTDA":
        falha("legalName ausente")
    if org.get("taxID") != "70.100.608/0001-73":
        falha("taxID ausente")
    if org.get("alternateName") != ["Escape Match"]:
        falha("alternateName ausente")
    if org.get("email") != EMAIL_CONTATO:
        falha("Organization sem o e-mail já publicado")
    if org.get("description") != DEFINICAO:
        falha("description da Organization divergiu")
    if not str(org.get("logo", "")).endswith("/assets/logo-simbolo.svg"):
        falha("logo da Organization mudou")
    if (
        endereco.get("@type") != "PostalAddress"
        or endereco.get("addressLocality") != "Curitiba"
        or endereco.get("addressRegion") != "PR"
        or endereco.get("addressCountry") != "BR"
        or "streetAddress" in endereco
    ):
        falha("endereço da Organization divergiu")
    app_html = arquivo("/app").read_text()
    apps = [bloco for bloco in blocos_ld(app_html) if bloco.get("@type") == "WebApplication"]
    if len(apps) != 1:
        falha(f"/app saiu com {len(apps)} WebApplication")
    oferta = apps[0].get("offers") or {}
    if apps[0].get("applicationCategory") != "SocialNetworkingApplication":
        falha("applicationCategory divergiu")
    if apps[0].get("operatingSystem") != "Web, Android, iOS":
        falha("operatingSystem divergiu")
    if oferta.get("price") != 0 or oferta.get("priceCurrency") != "BRL":
        falha("offers do app divergiu")
    if any(campo in apps[0] for campo in ("aggregateRating", "review")):
        falha("o app publicou avaliação")
    if DEFINICAO not in app_html or "O aplicativo é gratuito." not in app_html:
        falha("a página do app não mostra o que o WebApplication afirma")
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
    if DEFINICAO not in guia or DEFINICAO not in arquivo("/sobre").read_text():
        falha("definição canônica ausente no guia ou no sobre")
    exigir_faq(
        guia,
        "/guia/escape-room-sozinho",
        (
            "Onde achar gente para jogar escape room sozinho?",
            "Dá para jogar escape room sem conhecer ninguém?",
            "O que é o EscapeMatch?",
        ),
    )
    exigir_faq(como, "/como-funciona", ("Como completar o grupo de uma sala de escape?",))
    exigir_faq(arquivo("/ajuda/grupo").read_text(), "/ajuda/grupo", ("O EscapeMatch é um jogo?",))
    cidade = arquivo("/escape-room-curitiba").read_text()
    for trecho in (
        '"@type":"WebPage"',
        '"@type":"FAQPage"',
        '"@type":"Service"',
        '"@type":"City"',
        "Curitiba",
        "ranking",
        "avalia",
        'property="og:title"',
        'property="og:description"',
        'property="og:url"',
    ):
        if trecho not in cidade:
            falha(f"escape room em Curitiba sem {trecho}")
    if re.search(r"R\$\s*\d", cidade) or "<form" in cidade.lower():
        falha("a página de Curitiba publica preço ou formulário")
    contato = arquivo("/contato").read_text()
    for trecho in ('property="og:title"', 'property="og:description"', 'property="og:url"'):
        if trecho not in contato:
            falha(f"contato sem {trecho}")
    bing = DIST / "BingSiteAuth.xml"
    if bing.is_file():
        miolo = re.fullmatch(
            r"<\?xml version=\"1.0\"\?>\n<users>\n  <user>([^<]+)</user>\n</users>\n",
            bing.read_text(),
        )
        if not miolo or not token_ok(miolo.group(1)):
            falha("BingSiteAuth.xml inválido")
    base = (ROOT / "apps/site/src/layouts/Base.astro").read_text()
    if re.search(r'name="google-site-verification" content="[^"]+"', base):
        falha("token do Google foi parar no código")
    if re.search(r'name="msvalidate\.01" content="[^"]+"', base):
        falha("token do Bing foi parar no código")
    if "<lastmod>" not in sitemap:
        falha("sitemap sem lastmod")
    for nome in ("llms.txt", "llms-full.txt"):
        texto = (DIST / nome).read_text()
        if "Curitiba" not in texto or "R$ 0,01" not in texto:
            falha(f"{nome} incompleto")
        if DEFINICAO not in texto or "Não confundir com jogos de celular chamados Escape Match." not in texto:
            falha(f"{nome} sem a definição ou a desambiguação")
        if "limite mensal" in texto:
            falha(f"{nome} ainda cita limite mensal")
    def chaves_indexnow(pasta: pathlib.Path) -> list[str]:
        return sorted(
            path.name
            for path in pasta.iterdir()
            if path.is_file() and CHAVE_INDEXNOW.fullmatch(path.name) and path.read_text().strip() == path.stem
        )

    chaves = chaves_indexnow(DIST)
    if chaves != chaves_indexnow(ROOT / "apps/site/public") or len(chaves) != 1:
        falha("chave IndexNow ausente ou divergente entre public e dist")
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
    if "Sitemap: https://escapematch.com.br/sitemap-index.xml" not in robots:
        falha("robots.txt sem o sitemap")

    print(f"site ok: {len(ROTAS)} rotas")


if __name__ == "__main__":
    main()
