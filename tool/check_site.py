#!/usr/bin/env python3
"""Confere o build estático de apps/site/dist."""

import json
import pathlib
import re
import struct
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
    "/guia",
    "/guia/escape-room-sozinho",
    "/guia/escape-room-sozinho-curitiba",
    "/guia/como-achar-grupo-escape-room",
    "/guia/escape-room-com-desconhecidos",
    "/guia/escape-room-para-2-pessoas",
    "/guia/nao-tenho-amigos-para-escape-room",
    "/guia/escape-room-em-grupo-curitiba",
    "/guia/primeira-vez-em-escape-room",
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
INSTAGRAM = "https://www.instagram.com/escapematch/"
DEFINICAO = (
    "O EscapeMatch é o aplicativo brasileiro que conecta pessoas para jogar escape room "
    "e, em breve, outros jogos em grupo. Você chega sozinho, entra num grupo e paga só a sua vaga. "
    "Lançamento em Curitiba. Não é um jogo de celular."
)
NOMES_ALTERNATIVOS = ["ScapeMatch", "Scape Match", "Escape Match"]
HOME_DESCRICAO = (
    "Aplicativo brasileiro para jogar escape room em grupo quando se está sozinho. "
    "Chamava-se ScapeMatch. Lançamento em Curitiba. Não é um jogo de celular."
)
FRASE_NOME = (
    "O EscapeMatch se chamava ScapeMatch até novembro de 2026; "
    "é o mesmo aplicativo, só o nome mudou."
)
REFORCO_PRESENCIAL = (
    "Não é um jogo de celular nem um jogo de quebra-cabeça ou match-3. "
    "É um app que junta pessoas para jogar escape room presencial."
)
RESPOSTA_ANTIGO = (
    "Sim. O EscapeMatch se chamava ScapeMatch até novembro de 2026. "
    "É o mesmo aplicativo, só o nome mudou."
)
RESPOSTA_QUEBRA = (
    "Não. O jogo acontece presencialmente na casa de escape room. "
    "O app só forma o grupo e cobra a vaga quando o grupo confirma."
)
PERGUNTA_ANTIGO = "O EscapeMatch é o antigo ScapeMatch?"
PERGUNTA_QUEBRA = "O EscapeMatch é um jogo de quebra-cabeça de celular?"
LINHA_NOME_ANTIGO = (
    "O EscapeMatch se chamava ScapeMatch até novembro de 2026. "
    "Não confundir com Scape Match 3, Mahjong Scapes, Scapewatch ou Escape Match Room Tiles."
)
GUIAS_MARCA = (
    "/guia/escape-room-sozinho",
    "/guia/escape-room-sozinho-curitiba",
    "/guia/como-achar-grupo-escape-room",
    "/guia/escape-room-com-desconhecidos",
    "/guia/escape-room-para-2-pessoas",
    "/guia/nao-tenho-amigos-para-escape-room",
    "/guia/escape-room-em-grupo-curitiba",
    "/guia/primeira-vez-em-escape-room",
    "/sobre",
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


def exigir_resposta(html: str, rota: str, pergunta: str, resposta: str) -> None:
    faqs = [bloco for bloco in blocos_ld(html) if bloco.get("@type") == "FAQPage"]
    if len(faqs) != 1:
        falha(f"{rota} saiu com {len(faqs)} FAQPage")
    for item in faqs[0].get("mainEntity", []):
        if item.get("name") != pergunta:
            continue
        texto = (item.get("acceptedAnswer") or {}).get("text", "")
        if texto != resposta or resposta not in html:
            falha(f"{rota} resposta divergiu: {pergunta}")
        return
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
    for rota in (
        "/termos",
        "/privacidade",
        "/cancelamento",
        "/contato",
        "/escape-room-curitiba",
        "/guia",
        "/guia/escape-room-sozinho",
        "/guia/escape-room-sozinho-curitiba",
        "/guia/como-achar-grupo-escape-room",
        "/guia/escape-room-com-desconhecidos",
        "/guia/escape-room-para-2-pessoas",
        "/guia/nao-tenho-amigos-para-escape-room",
        "/guia/escape-room-em-grupo-curitiba",
        "/guia/primeira-vez-em-escape-room",
    ):
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
            if "streetAddress" in texto or "GameApplication" in texto:
                falha(f"{html.relative_to(DIST)} tem rua ou GameApplication")
            blocos = blocos_ld(texto)
            same = [bloco.get("sameAs") for bloco in blocos if "sameAs" in bloco]
            if any(item != [INSTAGRAM] for item in same):
                falha(f"{html.relative_to(DIST)} tem sameAs fora do Instagram oficial")
            tem_org = any(
                bloco.get("@type") == "Organization" and bloco.get("legalName") for bloco in blocos
            )
            if tem_org and same != [[INSTAGRAM]]:
                falha(f"{html.relative_to(DIST)} sem o Instagram oficial em sameAs")
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
    if org.get("alternateName") != NOMES_ALTERNATIVOS:
        falha("alternateName da Organization divergiu")
    if org.get("email") != EMAIL_CONTATO:
        falha("Organization sem o e-mail já publicado")
    if org.get("sameAs") != [INSTAGRAM]:
        falha("sameAs da Organization divergiu")
    if org.get("description") != DEFINICAO:
        falha("description da Organization divergiu")
    if not str(org.get("logo", "")).endswith("/assets/logo-512.png"):
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
    if apps[0].get("alternateName") != NOMES_ALTERNATIVOS:
        falha("alternateName do WebApplication divergiu")
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
    if f'<meta name="description" content="{HOME_DESCRICAO}">' not in home_html:
        falha("descrição da home divergiu")
    if len(HOME_DESCRICAO) > 155:
        falha(f"descrição da home com {len(HOME_DESCRICAO)} caracteres")
    for rota in GUIAS_MARCA:
        html_marca = arquivo(rota).read_text()
        if rota == "/sobre":
            if FRASE_NOME not in html_marca or REFORCO_PRESENCIAL not in html_marca:
                falha("sobre sem a frase do nome antigo ou o reforço presencial")
        exigir_faq(html_marca, rota, (PERGUNTA_ANTIGO, PERGUNTA_QUEBRA))
        exigir_resposta(html_marca, rota, PERGUNTA_ANTIGO, RESPOSTA_ANTIGO)
        exigir_resposta(html_marca, rota, PERGUNTA_QUEBRA, RESPOSTA_QUEBRA)
    exigir_faq(
        guia,
        "/guia/escape-room-sozinho",
        (
            "Onde achar gente para jogar escape room sozinho?",
            "Dá para jogar escape room sem conhecer ninguém?",
            "O que é o EscapeMatch?",
        ),
    )
    guia_curitiba = arquivo("/guia/escape-room-sozinho-curitiba").read_text()
    guia_grupo = arquivo("/guia/como-achar-grupo-escape-room").read_text()
    for rota, html_guia in (
        ("/guia/escape-room-sozinho-curitiba", guia_curitiba),
        ("/guia/como-achar-grupo-escape-room", guia_grupo),
    ):
        if DEFINICAO not in html_guia:
            falha(f"definição canônica ausente em {rota}")
        if '"@type":"FAQPage"' not in html_guia:
            falha(f"{rota} saiu sem FAQPage")
    exigir_faq(
        guia_curitiba,
        "/guia/escape-room-sozinho-curitiba",
        (
            "Onde jogar escape room sozinho em Curitiba?",
            "Como o EscapeMatch junta o grupo em Curitiba?",
            "O que esperar da sessão?",
            "O que é o EscapeMatch?",
        ),
    )
    exigir_faq(
        guia_grupo,
        "/guia/como-achar-grupo-escape-room",
        (
            "Dá para montar o grupo com amigos?",
            "Grupos de WhatsApp, Reddit ou Meetup servem?",
            "A casa pode completar a sala?",
            "Como o EscapeMatch acha o grupo?",
            "O que é o EscapeMatch?",
        ),
    )
    if "não lista casas parceiras" not in guia_curitiba.lower():
        falha("o guia de Curitiba não avisa que o site não lista casas")
    guias_novos = {
        "/guia/escape-room-com-desconhecidos": (
            "Dá para jogar escape room com desconhecidos?",
            "Como é a sessão com desconhecidos?",
            "Qual é a regra de convivência?",
            "Quem paga quando o grupo é de desconhecidos?",
            "O que é o EscapeMatch?",
        ),
        "/guia/escape-room-para-2-pessoas": (
            "Dá para jogar escape room para 2 pessoas?",
            "A dupla paga a sala inteira?",
            "Já somos duas pessoas. Dá para usar o app?",
            "A dupla precisa conhecer o resto do grupo?",
            "O que é o EscapeMatch?",
        ),
        "/guia/nao-tenho-amigos-para-escape-room": (
            "Não tenho amigos para jogar escape room. Dá para ir?",
            "Preciso levar uma turma?",
            "Vou ficar de fora do grupo?",
            "E se faltar gente no grupo?",
            "O que é o EscapeMatch?",
        ),
        "/guia/escape-room-em-grupo-curitiba": (
            "Como jogar escape room em grupo em Curitiba?",
            "Quem entra nesse grupo?",
            "Quando o grupo em Curitiba confirma?",
            "Onde vejo as salas de grupo em Curitiba?",
            "O que é o EscapeMatch?",
        ),
        "/guia/primeira-vez-em-escape-room": (
            "Primeira vez em escape room: o que saber?",
            "Preciso ter jogado escape room antes?",
            "O que fazer na hora da sessão?",
            "E se for a primeira vez e o grupo não fechar?",
            "O que é o EscapeMatch?",
        ),
    }
    for rota, perguntas in guias_novos.items():
        html_guia = arquivo(rota).read_text()
        if DEFINICAO not in html_guia:
            falha(f"definição canônica ausente em {rota}")
        if '"@type":"FAQPage"' not in html_guia:
            falha(f"{rota} saiu sem FAQPage")
        exigir_faq(html_guia, rota, perguntas)
    guia_grupo_cidade = arquivo("/guia/escape-room-em-grupo-curitiba").read_text()
    if "não lista casas parceiras" not in guia_grupo_cidade.lower():
        falha("o guia de grupo em Curitiba não avisa que o site não lista casas")
    hub = arquivo("/guia").read_text()
    if DEFINICAO not in hub:
        falha("definição canônica ausente no índice de guias")
    for rota in guias_novos:
        if f'href="{rota}"' not in hub:
            falha(f"o índice de guias não aponta para {rota}")
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
        if LINHA_NOME_ANTIGO not in texto:
            falha(f"{nome} sem o nome antigo")
        if INSTAGRAM not in texto:
            falha(f"{nome} sem o Instagram oficial")
        if "Não há perfil oficial de Instagram" in texto:
            falha(f"{nome} ainda diz que não há Instagram")
        for rota in (
            "/guia",
            "/guia/escape-room-sozinho-curitiba",
            "/guia/como-achar-grupo-escape-room",
            "/guia/escape-room-com-desconhecidos",
            "/guia/escape-room-para-2-pessoas",
            "/guia/nao-tenho-amigos-para-escape-room",
            "/guia/escape-room-em-grupo-curitiba",
            "/guia/primeira-vez-em-escape-room",
        ):
            if rota not in texto:
                falha(f"{nome} sem {rota}")
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
    conferir_icones(robots)

    print(f"site ok: {len(ROTAS)} rotas")


LOGO_PNG = "assets/logo-512.png"
LOGO_JSON = '"logo":"https://escapematch.com.br/assets/logo-512.png"'
LOGO_SVG_JSON = '"logo":"https://escapematch.com.br/assets/logo-simbolo.svg"'
LINKS_ICONE = (
    '<link rel="icon" href="/favicon.ico" sizes="16x16 32x32 48x48 64x64 96x96 128x128 192x192 256x256">',
    '<link rel="icon" href="/assets/favicon-48.png" type="image/png" sizes="48x48">',
    '<link rel="icon" href="/assets/favicon-96.png" type="image/png" sizes="96x96">',
    '<link rel="icon" href="/assets/favicon-192.png" type="image/png" sizes="192x192">',
    '<link rel="icon" href="/assets/favicon-512.png" type="image/png" sizes="512x512">',
    '<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">',
    '<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">',
)
CAMINHOS_ICONE = (
    "/favicon.ico",
    "/apple-touch-icon.png",
    "/assets/logo-512.png",
    "/assets/favicon-48.png",
    "/assets/favicon-96.png",
    "/assets/favicon-192.png",
    "/assets/favicon-512.png",
    "/assets/favicon.svg",
)
AGENTES_ICONE = ("Googlebot", "Googlebot-Image", "*")


def png_tamanho(path: pathlib.Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or not data.startswith(b"\x89PNG\r\n\x1a\n") or data[12:16] != b"IHDR":
        falha(f"{path.relative_to(DIST)} não é PNG")
    return struct.unpack(">II", data[16:24])


def tamanhos_ico(path: pathlib.Path) -> list[tuple[int, int]]:
    data = path.read_bytes()
    if len(data) < 6 or data[:4] != b"\x00\x00\x01\x00":
        falha("favicon.ico ausente ou inválido")
    quantidade = struct.unpack_from("<H", data, 4)[0]
    if quantidade < 1 or len(data) < 6 + 16 * quantidade:
        falha("favicon.ico sem imagens")
    tamanhos = []
    for indice in range(quantidade):
        entrada = 6 + 16 * indice
        largura = data[entrada] or 256
        altura = data[entrada + 1] or 256
        tamanhos.append((largura, altura))
    return tamanhos


def regras_disallow(texto: str) -> dict[str, list[str]]:
    atual = "*"
    regras: dict[str, list[str]] = {}
    for linha in texto.splitlines():
        linha = linha.split("#", 1)[0].strip()
        if not linha or ":" not in linha:
            continue
        chave, valor = (parte.strip() for parte in linha.split(":", 1))
        if chave.lower() == "user-agent":
            atual = valor
            regras.setdefault(atual, [])
        elif chave.lower() == "disallow":
            regras.setdefault(atual, []).append(valor)
    return regras


def caminho_bloqueado(regras: dict[str, list[str]], agente: str, caminho: str) -> bool:
    if agente in regras:
        lista = regras[agente]
    else:
        lista = regras.get("*", [])
    for regra in lista:
        if regra and caminho.startswith(regra):
            return True
    return False


def conferir_icones(robots: str) -> None:
    """O Google ignora favicon SVG e pede quadrado acima de 48 px.

    O logo da Organization precisa de PNG com pelo menos 112 px.
    """
    ico = DIST / "favicon.ico"
    if not ico.is_file():
        falha("favicon.ico sumiu do build")
    tamanhos = tamanhos_ico(ico)
    if (48, 48) not in tamanhos or any(largura != altura for largura, altura in tamanhos):
        falha(f"favicon.ico sem o quadrado de 48 px: {tamanhos}")

    logo = DIST / LOGO_PNG
    if not logo.is_file():
        falha("logo PNG sumiu do build")
    largura, altura = png_tamanho(logo)
    if largura != altura or largura < 112:
        falha(f"logo PNG {largura}x{altura}; o Google pede quadrado de pelo menos 112 px")

    for lado in (48, 96, 192, 512):
        arquivo_png = DIST / "assets" / f"favicon-{lado}.png"
        if not arquivo_png.is_file():
            falha(f"favicon-{lado}.png sumiu do build")
        if png_tamanho(arquivo_png) != (lado, lado):
            falha(f"favicon-{lado}.png não tem {lado} px")
    toque = DIST / "apple-touch-icon.png"
    if not toque.is_file() or png_tamanho(toque) != (180, 180):
        falha("apple-touch-icon.png ausente ou fora de 180 px")

    regras = regras_disallow(robots)
    for agente in AGENTES_ICONE:
        for caminho in CAMINHOS_ICONE:
            if caminho_bloqueado(regras, agente, caminho):
                falha(f"robots.txt bloqueia {caminho} para {agente}")

    manifestos = {
        path.resolve()
        for path in DIST.rglob("*")
        if path.is_file()
        and (path.name == "manifest.json" or path.suffix == ".webmanifest")
    }
    for path in manifestos:
        dados = json.loads(path.read_text())
        origens = " ".join(str(icone.get("src", "")) for icone in dados.get("icons") or [])
        if not any(
            nome in origens
            for nome in ("favicon-192.png", "favicon-512.png", "logo-512.png")
        ):
            falha(f"{path.relative_to(DIST)} não aponta para os ícones novos")

    for html in DIST.rglob("*.html"):
        if html.name.startswith("google") and html.suffix == ".html":
            continue
        texto = html.read_text()
        if "<head>" not in texto:
            continue
        for link in LINKS_ICONE:
            if link not in texto:
                falha(f"{html.relative_to(DIST)} sem {link}")
        for tag in re.findall(r'<link[^>]*rel="manifest"[^>]*>', texto):
            href = re.search(r'href="([^"]+)"', tag)
            if not href or not href.group(1).startswith("/"):
                falha(f"{html.relative_to(DIST)} tem manifest sem URL no site")
            alvo = (DIST / href.group(1).lstrip("/").split("?", 1)[0]).resolve()
            if alvo not in manifestos:
                falha(f"{html.relative_to(DIST)} aponta manifest sem os ícones novos")
        if LOGO_SVG_JSON in texto:
            falha(f"{html.relative_to(DIST)} ainda declara o logo SVG na Organization")
        if LOGO_JSON not in texto:
            falha(f"{html.relative_to(DIST)} sem o logo PNG na Organization")


if __name__ == "__main__":
    main()
