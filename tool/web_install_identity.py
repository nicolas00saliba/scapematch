"""Identidade de instalação de cada build web.

Espelha os hosts de lib/core/sharing/public_origins.dart. O id do
manifest sai como URL absoluta. Um id relativo "/" no app e na demo
vira a mesma string crua; o Android trata os dois como um atalho só.
A URL absoluta de cada host continua a mesma que o navegador já
resolvia, então quem instalou certo só atualiza o ícone. A demo da
casa é a exceção: o host próprio troca o atalho de propósito, para
sair do escopo da demo do jogador.
"""

LEGACY_ORIGIN = "https://nicolas00saliba.github.io"
PLAYER_ORIGIN = "https://app.escapematch.com.br"
PARTNER_ORIGIN = "https://parceiro.escapematch.com.br"
ADMIN_ORIGIN = "https://admin.scapematch.com.br"
DEMO_ORIGIN = "https://demo.escapematch.com.br"
PARTNER_DEMO_ORIGIN = "https://parceiro-demo.escapematch.com.br"


def install_identity(role, mode, base_href):
    """URL absoluta de id, start_url e scope."""
    if role not in ("player", "partner", "admin") or mode not in ("real", "demo"):
        raise ValueError(f"papel ou modo desconhecido: {role} {mode}")
    if role == "admin" and mode != "real":
        raise ValueError("o Admin não tem demonstração")
    if not base_href.startswith("/") or not base_href.endswith("/"):
        raise ValueError(f"base href inválido: {base_href}")

    if base_href == "/":
        if role == "player" and mode == "real":
            return PLAYER_ORIGIN + "/"
        if role == "player" and mode == "demo":
            return DEMO_ORIGIN + "/"
        if role == "partner" and mode == "real":
            return PARTNER_ORIGIN + "/"
        if role == "partner" and mode == "demo":
            return PARTNER_DEMO_ORIGIN + "/"
        if role == "admin":
            return ADMIN_ORIGIN + "/"
    if base_href.startswith("/scapematch/"):
        path_is_demo = "/demo/" in base_href
        if mode == "demo" and not path_is_demo:
            raise ValueError(f"demo fora do caminho da demo: {base_href}")
        if mode == "real" and path_is_demo:
            raise ValueError(f"app real no caminho da demo: {base_href}")
        return LEGACY_ORIGIN + base_href
    raise ValueError(f"sem identidade para {role} {mode} {base_href}")


def install_names(role, mode):
    """Nome longo e nome curto do atalho."""
    if role == "player" and mode == "demo":
        return "EscapeMatch Demo", "Escape Demo"
    if role == "player" and mode == "real":
        return "EscapeMatch", "EscapeMatch"
    if role == "partner" and mode == "demo":
        return "EscapeMatch Parceiro Demo", "Parceiro Demo"
    if role == "partner" and mode == "real":
        return "EscapeMatch Parceiro", "Parceiro"
    if role == "admin" and mode == "real":
        return "ScapeMatch Admin", "Admin"
    raise ValueError(f"papel ou modo desconhecido: {role} {mode}")
