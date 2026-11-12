#!/usr/bin/env python3
"""Mede a carga do HTML dos apps Flutter e só avisa.

O canvas do Flutter não entra no orçamento do Lighthouse do site.
Este passo não falha o workflow.
"""

from __future__ import annotations

import sys
import time
import urllib.request

HOSTS = [
    "https://app.escapematch.com.br/",
    "https://parceiro.escapematch.com.br/",
    "https://admin.escapematch.com.br/",
    "https://demo.escapematch.com.br/",
    "https://parceiro-demo.escapematch.com.br/",
]
LIMITE_SEGUNDOS = 2.5


def medir(url: str) -> tuple[int, float]:
    inicio = time.monotonic()
    pedido = urllib.request.Request(url, headers={"User-Agent": "EscapeMatch-carga"})
    with urllib.request.urlopen(pedido, timeout=15) as resposta:
        resposta.read()
        return resposta.status, time.monotonic() - inicio


def main() -> int:
    for url in HOSTS:
        try:
            status, segundos = medir(url)
        except Exception as erro:  # noqa: BLE001
            print(f"::warning::{url} não respondeu: {erro}")
            continue
        linha = f"{url} {status} em {segundos:.2f}s"
        if status != 200 or segundos > LIMITE_SEGUNDOS:
            print(f"::warning::{linha}")
        else:
            print(linha)
    return 0


if __name__ == "__main__":
    sys.exit(main())
