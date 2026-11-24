#!/usr/bin/env python3
"""Cria as contas fantasmas (jogadores e donos de casa) no Supabase.

Por padrão só mostra o plano. Para gravar precisa de --executar,
--confirmo-producao, SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.

O que faz por conta do testes/apps_fantasma/contas.json:
  1. cria o usuário no Auth já confirmado (sem e-mail de confirmação);
  2. marca profiles.is_test = true (migration 20261124190000_test_accounts);
  3. entra com a senha e aceita os termos (jogador ou parceiro).

Não cria casa, sala, CPF, telefone nem cartão. A casa é cadastrada no app
"EM Casa N" e já nasce de teste porque o dono é de teste. O CPF de quem
paga entra no próprio app na hora do pagamento.

Senha: a mesma para todas as contas, lida de EM_TEST_PASSWORD no ambiente.
O script não gera, não grava e não imprime a senha.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

AQUI = Path(__file__).resolve().parent
CONTAS = AQUI.parent / "apps_fantasma" / "contas.json"
EMAIL_PADRAO = "saliban3-hc6272+em-{slug}@mail.grokbot.com"
NASCIMENTO = "1990-01-01"


def nome(conta):
    if conta["tipo"] == "jogador":
        return f"Jogador Fantasma {conta['numero']}"
    return f"Casa Fantasma {conta['numero']}"


class Supabase:
    def __init__(self, url, service_key):
        self.url = url.rstrip("/")
        self.key = service_key

    def pedir(self, metodo, caminho, corpo=None, token=None, extra=None):
        cabecalhos = {
            "apikey": self.key,
            "Authorization": f"Bearer {token or self.key}",
            "Content-Type": "application/json",
        }
        cabecalhos.update(extra or {})
        dados = None if corpo is None else json.dumps(corpo).encode()
        pedido = urllib.request.Request(
            self.url + caminho, data=dados, method=metodo, headers=cabecalhos
        )
        try:
            with urllib.request.urlopen(pedido, timeout=30) as resposta:
                texto = resposta.read().decode() or "null"
                return resposta.status, json.loads(texto)
        except urllib.error.HTTPError as erro:
            texto = erro.read().decode()
            try:
                return erro.code, json.loads(texto)
            except ValueError:
                return erro.code, {"erro": texto[:200]}

    def achar_usuario(self, email):
        pagina = 1
        while True:
            status, corpo = self.pedir(
                "GET", f"/auth/v1/admin/users?page={pagina}&per_page=200"
            )
            if status != 200:
                sys.exit(f"listar usuários falhou: HTTP {status}")
            usuarios = corpo.get("users", [])
            for usuario in usuarios:
                if (usuario.get("email") or "").lower() == email.lower():
                    return usuario
            if len(usuarios) < 200:
                return None
            pagina += 1


def executar(conta, email, senha, api):
    usuario = api.achar_usuario(email)
    if usuario is None:
        metadados = {"display_name": nome(conta)}
        if conta["tipo"] == "jogador":
            metadados["birth_date"] = NASCIMENTO
        status, corpo = api.pedir(
            "POST",
            "/auth/v1/admin/users",
            {
                "email": email,
                "password": senha,
                "email_confirm": True,
                "user_metadata": metadados,
            },
        )
        if status not in (200, 201):
            sys.exit(f"{conta['slug']}: criar usuário falhou (HTTP {status})")
        usuario = corpo
        acao = "criada"
    else:
        acao = "já existia"
    uid = usuario["id"]

    status, _ = api.pedir(
        "PATCH",
        f"/rest/v1/profiles?id=eq.{uid}",
        {"is_test": True},
        extra={"Prefer": "return=minimal"},
    )
    if status not in (200, 204):
        sys.exit(f"{conta['slug']}: marcar is_test falhou (HTTP {status})")

    status, sessao = api.pedir(
        "POST",
        "/auth/v1/token?grant_type=password",
        {"email": email, "password": senha},
    )
    if status != 200:
        sys.exit(f"{conta['slug']}: entrar com a senha falhou (HTTP {status})")
    publico = "player" if conta["tipo"] == "jogador" else "partner"
    status, _ = api.pedir(
        "POST",
        "/rest/v1/rpc/accept_terms",
        {"p_audience": publico},
        token=sessao["access_token"],
    )
    if status not in (200, 204):
        sys.exit(f"{conta['slug']}: aceitar termos falhou (HTTP {status})")
    print(f"{conta['slug']}: {acao}, is_test, termos aceitos ({uid})")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--email-modelo", default=EMAIL_PADRAO)
    parser.add_argument("--executar", action="store_true")
    parser.add_argument("--confirmo-producao", action="store_true")
    args = parser.parse_args()

    if "{slug}" not in args.email_modelo:
        sys.exit("--email-modelo precisa ter {slug}")
    contas = json.loads(CONTAS.read_text())["contas"]
    senha = os.environ.get("EM_TEST_PASSWORD") or ""

    print("Plano:")
    for conta in contas:
        email = args.email_modelo.format(slug=conta["slug"])
        print(f"  {conta['slug']:<9} {nome(conta):<20} {email}")
    print(f"EM_TEST_PASSWORD: {'definida' if senha else 'ausente'}")

    if not args.executar:
        print("Só o plano. Nada foi gravado. Use --executar --confirmo-producao.")
        return
    if not args.confirmo_producao:
        sys.exit("Falta --confirmo-producao.")
    if len(senha) < 8:
        sys.exit("Defina EM_TEST_PASSWORD (mínimo 8 caracteres) no ambiente.")
    url = os.environ.get("SUPABASE_URL")
    chave = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not chave:
        sys.exit("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.")
    api = Supabase(url, chave)
    for conta in contas:
        executar(conta, args.email_modelo.format(slug=conta["slug"]), senha, api)


if __name__ == "__main__":
    main()
