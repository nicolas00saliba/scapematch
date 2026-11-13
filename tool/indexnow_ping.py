#!/usr/bin/env python3
"""Envia as URLs do sitemap ao IndexNow.

O passo só deve rodar depois que o site foi publicado. A chave fica no
arquivo público da raiz, que é o jeito do protocolo provar o domínio.
O GitHub Pages pode demorar a servir esse arquivo, então o envio espera
a URL da chave responder 200 com o próprio texto da chave.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HOST = "escapematch.com.br"
API = "https://api.indexnow.org/indexnow"
CHAVE = re.compile(r"^[0-9a-f]{8,128}$")
SITEMAP = re.compile(r"^https://escapematch\.com\.br/sitemap(?:-index|-\d+)?\.xml$")
LIMITE = 10_000
ESPERA_SEGUNDOS = 300
INTERVALO_SEGUNDOS = 15


def achar_chave(publico: Path) -> str:
    achadas: list[str] = []
    if not publico.is_dir():
        raise SystemExit(f"pasta pública ausente: {publico}")
    for path in sorted(publico.iterdir()):
        if not path.is_file() or not path.name.endswith(".txt"):
            continue
        stem = path.name[: -len(".txt")]
        if CHAVE.fullmatch(stem) is None:
            continue
        if path.read_text(encoding="utf-8").strip() == stem:
            achadas.append(stem)
    if len(achadas) != 1:
        raise SystemExit(f"esperado um arquivo de chave IndexNow, achei {len(achadas)}")
    return achadas[0]


def urls_do_sitemap(dist: Path) -> list[str]:
    arquivos = sorted(dist.glob("sitemap*.xml"))
    if not arquivos:
        raise SystemExit(f"sitemap ausente em {dist}")
    locs: list[str] = []
    for arq in arquivos:
        locs.extend(re.findall(r"<loc>([^<]+)</loc>", arq.read_text(encoding="utf-8")))
    paginas: list[str] = []
    vistos: set[str] = set()
    for loc in locs:
        if SITEMAP.fullmatch(loc):
            continue
        if not loc.startswith(f"https://{HOST}/"):
            raise SystemExit(f"URL fora do host: {loc}")
        if loc not in vistos:
            vistos.add(loc)
            paginas.append(loc)
    if not paginas:
        raise SystemExit("sitemap sem URLs de página")
    if len(paginas) > LIMITE:
        raise SystemExit(f"IndexNow aceita no máximo {LIMITE} URLs")
    return paginas


def corpo(chave: str, urls: list[str]) -> dict[str, object]:
    return {
        "host": HOST,
        "key": chave,
        "keyLocation": f"https://{HOST}/{chave}.txt",
        "urlList": urls,
    }


def chave_publicada(chave: str, abrir) -> bool:
    url = f"https://{HOST}/{chave}.txt"
    try:
        with abrir(url, timeout=10) as resp:
            if int(resp.status) != 200:
                return False
            texto = resp.read().decode("utf-8", "replace").strip()
            return texto == chave
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return False


def esperar_chave(
    chave: str,
    abrir=urllib.request.urlopen,
    dormir=time.sleep,
    relogio=time.monotonic,
    limite: float = ESPERA_SEGUNDOS,
    intervalo: float = INTERVALO_SEGUNDOS,
) -> bool:
    prazo = relogio() + limite
    while True:
        if chave_publicada(chave, abrir):
            return True
        agora = relogio()
        if agora >= prazo:
            return False
        dormir(min(intervalo, prazo - agora))


def enviar(payload: dict[str, object]) -> int:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    pedido = urllib.request.Request(
        API,
        data=data,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(pedido, timeout=30) as resp:
            return int(resp.status)
    except urllib.error.HTTPError as exc:
        detalhe = exc.read().decode("utf-8", "replace")[:500]
        raise SystemExit(f"IndexNow respondeu {exc.code}: {detalhe}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Envia o sitemap ao IndexNow.")
    parser.add_argument("--dist", type=Path, required=True)
    parser.add_argument("--public", type=Path, required=True, dest="publico")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    payload = corpo(achar_chave(args.publico), urls_do_sitemap(args.dist))
    if args.dry_run:
        json.dump(payload, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0
    chave = str(payload["key"])
    print(
        f"IndexNow: esperando https://{HOST}/{chave}.txt "
        f"(até {ESPERA_SEGUNDOS // 60} min, a cada {INTERVALO_SEGUNDOS} s)."
    )
    if not esperar_chave(chave):
        print(
            f"IndexNow: a chave ainda não respondeu 200 em https://{HOST}/{chave}.txt. "
            "O site já foi publicado. Aviso não enviado.",
            file=sys.stderr,
        )
        return 0
    status = enviar(payload)
    if status not in (200, 202):
        raise SystemExit(f"IndexNow respondeu {status}")
    urls = payload["urlList"]
    print(f"IndexNow aceitou {len(urls)} URLs (HTTP {status}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
