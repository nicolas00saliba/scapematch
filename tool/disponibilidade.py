#!/usr/bin/env python3
"""Checa os hosts publicados e abre ou fecha uma issue por host.

Sem --aplicar (ou sem GH_TOKEN), só imprime o resultado. O workflow
agendado passa --aplicar. O texto esperado está em disponibilidade_alvos.tsv.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

LIMITE_SEGUNDOS = 8.0
DIRETORIO = Path(__file__).resolve().parent
ALVOS_PADRAO = DIRETORIO / "disponibilidade_alvos.tsv"
USER_AGENT = "EscapeMatch-disponibilidade"


@dataclass(frozen=True)
class Alvo:
    host: str
    texto: str


@dataclass(frozen=True)
class Resultado:
    host: str
    ok: bool
    detalhe: str
    segundos: float


def carregar_alvos(caminho: Path) -> list[Alvo]:
    alvos: list[Alvo] = []
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#"):
            continue
        host, texto = linha.split("\t", 1)
        alvos.append(Alvo(host.strip(), texto))
    if not alvos:
        raise SystemExit(f"nenhum alvo em {caminho}")
    return alvos


def decidir(aberto: bool, ok: bool) -> str:
    if not ok and not aberto:
        return "abrir"
    if not ok and aberto:
        return "atualizar"
    if ok and aberto:
        return "fechar"
    return "nada"


class _SemRedirecionar(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


def _pedido(url: str, timeout: float) -> tuple[int, str | None, bytes]:
    abertura = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    abridor = urllib.request.build_opener(_SemRedirecionar)
    try:
        with abridor.open(abertura, timeout=timeout) as resposta:
            return resposta.status, resposta.headers.get("Location"), resposta.read()
    except urllib.error.HTTPError as erro:
        return erro.code, erro.headers.get("Location"), erro.read()


def checar(alvo: Alvo, timeout: float = LIMITE_SEGUNDOS) -> Resultado:
    ultimo: Resultado | None = None
    for _ in range(2):
        ultimo = _checar_uma(alvo, timeout)
        if ultimo.ok:
            return ultimo
    assert ultimo is not None
    return ultimo


def _checar_uma(alvo: Alvo, timeout: float) -> Resultado:
    inicio = time.monotonic()
    try:
        status_http, destino, _ = _pedido(f"http://{alvo.host}/", timeout)
    except Exception as erro:  # noqa: BLE001
        return Resultado(alvo.host, False, f"HTTP falhou: {erro}", time.monotonic() - inicio)

    if status_http not in (301, 302, 307, 308):
        return Resultado(
            alvo.host,
            False,
            f"HTTP respondeu {status_http}, esperava redirecionar para HTTPS",
            time.monotonic() - inicio,
        )
    if not destino or not destino.startswith("https://"):
        return Resultado(
            alvo.host,
            False,
            f"redirecionamento sem destino HTTPS ({destino})",
            time.monotonic() - inicio,
        )

    try:
        status, _, corpo = _pedido(f"https://{alvo.host}/", timeout)
    except Exception as erro:  # noqa: BLE001
        return Resultado(alvo.host, False, f"HTTPS falhou: {erro}", time.monotonic() - inicio)

    segundos = time.monotonic() - inicio
    if status != 200:
        return Resultado(alvo.host, False, f"HTTPS respondeu {status}", segundos)
    if segundos > timeout:
        return Resultado(
            alvo.host,
            False,
            f"respondeu 200 em {segundos:.1f}s, acima de {timeout:.0f}s",
            segundos,
        )
    texto = corpo.decode("utf-8", "replace")
    if alvo.texto not in texto:
        return Resultado(
            alvo.host,
            False,
            "respondeu 200 sem o texto esperado",
            segundos,
        )
    return Resultado(
        alvo.host,
        True,
        f"200 em {segundos:.2f}s com o texto esperado",
        segundos,
    )


def titulo_da_issue(host: str) -> str:
    return f"Disponibilidade: {host}"


def corpo(resultado: Resultado) -> str:
    estado = "no ar" if resultado.ok else "fora do ar"
    return (
        f"O host `{resultado.host}` está {estado}.\n\n"
        f"- Detalhe: {resultado.detalhe}\n"
        f"- Tempo medido: {resultado.segundos:.2f}s\n"
        f"- Limite: {LIMITE_SEGUNDOS:.0f}s\n\n"
        "Checagem automática do workflow `disponibilidade.yml`. "
        "Não inclui o corpo da página."
    )


def _gh(argumentos: list[str]) -> str:
    completo = subprocess.run(
        ["gh", *argumentos],
        check=True,
        capture_output=True,
        text=True,
    )
    return completo.stdout


def issues_abertas() -> dict[str, int]:
    saida = _gh(
        [
            "issue",
            "list",
            "--state",
            "open",
            "--limit",
            "100",
            "--json",
            "number,title",
            "--search",
            "Disponibilidade: in:title",
        ]
    )
    import json

    abertas: dict[str, int] = {}
    for item in json.loads(saida or "[]"):
        abertas[item["title"]] = item["number"]
    return abertas


def sincronizar(resultados: list[Resultado], aplicar: bool) -> None:
    abertas = issues_abertas() if aplicar else {}
    for resultado in resultados:
        titulo = titulo_da_issue(resultado.host)
        acao = decidir(titulo in abertas, resultado.ok)
        print(f"{resultado.host}: {acao} — {resultado.detalhe}")
        if not aplicar or acao == "nada":
            continue
        if acao == "abrir":
            _gh(
                [
                    "issue",
                    "create",
                    "--title",
                    titulo,
                    "--body",
                    corpo(resultado),
                ]
            )
            continue
        numero = str(abertas[titulo])
        if acao == "atualizar":
            _gh(["issue", "edit", numero, "--body", corpo(resultado)])
            continue
        _gh(
            [
                "issue",
                "comment",
                numero,
                "--body",
                "O host voltou. " + resultado.detalhe,
            ]
        )
        _gh(["issue", "close", numero, "--reason", "completed"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--alvos", type=Path, default=ALVOS_PADRAO)
    parser.add_argument(
        "--aplicar",
        action="store_true",
        help="abre, atualiza ou fecha issues. Sem isto, só imprime.",
    )
    args = parser.parse_args(argv)
    resultados = [checar(alvo) for alvo in carregar_alvos(args.alvos)]
    sincronizar(resultados, aplicar=args.aplicar)
    return 0 if all(item.ok for item in resultados) else 1


if __name__ == "__main__":
    sys.exit(main())
