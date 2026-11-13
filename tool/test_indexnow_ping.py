#!/usr/bin/env python3
"""Confere o corpo do IndexNow sem chamar a rede."""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import indexnow_ping


CHAVE = "9360498fa2723ee1d3118bb648bbdbd7"


def url_do(pedido: object) -> str:
    if not isinstance(pedido, urllib.request.Request):
        raise AssertionError(f"esperado Request, veio {type(pedido).__name__}")
    return pedido.full_url


def assert_agente(caso: unittest.TestCase, pedido: urllib.request.Request) -> None:
    caso.assertEqual(pedido.get_header("User-agent"), indexnow_ping.AGENTE)
    caso.assertNotIn("Mozilla", indexnow_ping.AGENTE)
    caso.assertNotIn("Python-urllib", indexnow_ping.AGENTE)


class IndexNowTeste(unittest.TestCase):
    def test_corpo_usa_as_paginas_e_ignora_o_sitemap(self) -> None:
        with tempfile.TemporaryDirectory() as bruto:
            dist = Path(bruto)
            (dist / "sitemap-index.xml").write_text(
                "<sitemapindex><sitemap><loc>https://escapematch.com.br/sitemap-0.xml</loc></sitemap></sitemapindex>",
                encoding="utf-8",
            )
            (dist / "sitemap-0.xml").write_text(
                "<urlset>"
                "<url><loc>https://escapematch.com.br/</loc></url>"
                "<url><loc>https://escapematch.com.br/sobre</loc></url>"
                "<url><loc>https://escapematch.com.br/</loc></url>"
                "</urlset>",
                encoding="utf-8",
            )
            urls = indexnow_ping.urls_do_sitemap(dist)
            self.assertEqual(
                urls,
                ["https://escapematch.com.br/", "https://escapematch.com.br/sobre"],
            )
            payload = indexnow_ping.corpo(CHAVE, urls)
            self.assertEqual(payload["host"], "escapematch.com.br")
            self.assertEqual(payload["key"], CHAVE)
            self.assertEqual(
                payload["keyLocation"],
                f"https://escapematch.com.br/{CHAVE}.txt",
            )
            self.assertNotIn("https://escapematch.com.br/sitemap-0.xml", payload["urlList"])

    def test_chave_precisa_bater_com_o_arquivo(self) -> None:
        with tempfile.TemporaryDirectory() as bruto:
            publico = Path(bruto)
            (publico / "llms.txt").write_text("texto", encoding="utf-8")
            (publico / f"{CHAVE}.txt").write_text(f"{CHAVE}\n", encoding="utf-8")
            self.assertEqual(indexnow_ping.achar_chave(publico), CHAVE)

    def test_recusa_url_de_outro_host(self) -> None:
        with tempfile.TemporaryDirectory() as bruto:
            dist = Path(bruto)
            (dist / "sitemap-0.xml").write_text(
                "<urlset><url><loc>https://exemplo.invalid/</loc></url></urlset>",
                encoding="utf-8",
            )
            with self.assertRaises(SystemExit):
                indexnow_ping.urls_do_sitemap(dist)

    def test_dry_run_nao_posta(self) -> None:
        with tempfile.TemporaryDirectory() as bruto:
            raiz = Path(bruto)
            dist = raiz / "dist"
            publico = raiz / "public"
            dist.mkdir()
            publico.mkdir()
            (publico / f"{CHAVE}.txt").write_text(CHAVE, encoding="utf-8")
            (dist / "sitemap-0.xml").write_text(
                "<urlset><url><loc>https://escapematch.com.br/app</loc></url></urlset>",
                encoding="utf-8",
            )
            from io import StringIO
            import contextlib

            buf = StringIO()
            with contextlib.redirect_stdout(buf):
                codigo = indexnow_ping.main(
                    ["--dist", str(dist), "--public", str(publico), "--dry-run"]
                )
            self.assertEqual(codigo, 0)
            payload = json.loads(buf.getvalue())
            self.assertEqual(payload["urlList"], ["https://escapematch.com.br/app"])

    def test_espera_ate_a_chave_aparecer(self) -> None:
        relogio = {"t": 0.0}

        def agora() -> float:
            return relogio["t"]

        def dormir(segundos: float) -> None:
            relogio["t"] += segundos

        respostas = iter([urllib.error.URLError("404"), urllib.error.URLError("404"), corpo_http(200, CHAVE)])

        def abrir(pedido: urllib.request.Request, timeout: int = 10):
            self.assertEqual(url_do(pedido), f"https://escapematch.com.br/{CHAVE}.txt")
            assert_agente(self, pedido)
            self.assertIsNone(pedido.data)
            item = next(respostas)
            if isinstance(item, Exception):
                raise item
            return item

        ok = indexnow_ping.esperar_chave(CHAVE, abrir, dormir=dormir, relogio=agora, limite=60, intervalo=15)
        self.assertTrue(ok)
        self.assertEqual(relogio["t"], 30)

    def test_agente_proprio_na_chave_e_no_post(self) -> None:
        self.assertEqual(
            indexnow_ping.AGENTE,
            "EscapeMatch-IndexNow/1.0 (+https://escapematch.com.br)",
        )
        vistos: list[urllib.request.Request] = []

        def abrir(pedido: urllib.request.Request, timeout: int = 10):
            vistos.append(pedido)
            if pedido.full_url.endswith(".txt"):
                return corpo_http(200, CHAVE)
            return corpo_http(200, "")

        self.assertTrue(indexnow_ping.chave_publicada(CHAVE, abrir))
        status = indexnow_ping.enviar(indexnow_ping.corpo(CHAVE, ["https://escapematch.com.br/"]), abrir)
        self.assertEqual(status, 200)
        self.assertEqual(len(vistos), 2)
        assert_agente(self, vistos[0])
        assert_agente(self, vistos[1])
        self.assertEqual(vistos[1].get_method(), "POST")
        self.assertEqual(vistos[1].full_url, indexnow_ping.API)
        self.assertEqual(
            vistos[1].get_header("Content-type"),
            "application/json; charset=utf-8",
        )
        self.assertIn(b"escapematch.com.br", vistos[1].data or b"")

    def test_corpo_errado_ou_status_diferente_nao_libera(self) -> None:
        self.assertFalse(indexnow_ping.chave_publicada(CHAVE, lambda url, timeout=10: corpo_http(200, "outra")))
        self.assertFalse(indexnow_ping.chave_publicada(CHAVE, lambda url, timeout=10: corpo_http(404, CHAVE)))
        self.assertTrue(indexnow_ping.chave_publicada(CHAVE, lambda url, timeout=10: corpo_http(200, f"{CHAVE}\n")))

    def test_desiste_aos_cinco_minutos_sem_passar_do_prazo(self) -> None:
        relogio = {"t": 0.0}
        dormidas: list[float] = []

        def agora() -> float:
            return relogio["t"]

        def dormir(segundos: float) -> None:
            dormidas.append(segundos)
            relogio["t"] += segundos

        def abrir(url: str, timeout: int = 10):
            raise urllib.error.URLError("ainda não")

        ok = indexnow_ping.esperar_chave(CHAVE, abrir, dormir=dormir, relogio=agora)
        self.assertFalse(ok)
        self.assertEqual(relogio["t"], 300)
        self.assertEqual(sum(dormidas), 300)
        self.assertTrue(all(item <= 15 for item in dormidas))

    def test_ultimo_intervalo_nao_passa_do_prazo(self) -> None:
        relogio = {"t": 0.0}
        dormidas: list[float] = []

        def agora() -> float:
            return relogio["t"]

        def dormir(segundos: float) -> None:
            dormidas.append(segundos)
            relogio["t"] += segundos

        def abrir(url: str, timeout: int = 10):
            raise urllib.error.URLError("ainda não")

        ok = indexnow_ping.esperar_chave(
            CHAVE, abrir, dormir=dormir, relogio=agora, limite=20, intervalo=15
        )
        self.assertFalse(ok)
        self.assertEqual(dormidas, [15, 5])
        self.assertEqual(relogio["t"], 20)

    def test_sem_chave_no_ar_nao_envia_e_sai_zero(self) -> None:
        enviados: list[object] = []
        esperar = indexnow_ping.esperar_chave
        enviar = indexnow_ping.enviar
        indexnow_ping.esperar_chave = lambda chave: False
        indexnow_ping.enviar = lambda payload: enviados.append(payload) or 200
        try:
            with tempfile.TemporaryDirectory() as bruto:
                raiz = Path(bruto)
                dist = raiz / "dist"
                publico = raiz / "public"
                dist.mkdir()
                publico.mkdir()
                (publico / f"{CHAVE}.txt").write_text(CHAVE, encoding="utf-8")
                (dist / "sitemap-0.xml").write_text(
                    "<urlset><url><loc>https://escapematch.com.br/app</loc></url></urlset>",
                    encoding="utf-8",
                )
                err = io.StringIO()
                with contextlib.redirect_stderr(err):
                    codigo = indexnow_ping.main(["--dist", str(dist), "--public", str(publico)])
            self.assertEqual(codigo, 0)
            self.assertEqual(enviados, [])
            self.assertIn("O site já foi publicado", err.getvalue())
            self.assertIn(CHAVE, err.getvalue())
        finally:
            indexnow_ping.esperar_chave = esperar
            indexnow_ping.enviar = enviar


class RespostaHttp:
    def __init__(self, status: int, texto: str) -> None:
        self.status = status
        self._texto = texto

    def read(self) -> bytes:
        return self._texto.encode("utf-8")

    def __enter__(self) -> "RespostaHttp":
        return self

    def __exit__(self, *args: object) -> bool:
        return False


def corpo_http(status: int, texto: str) -> RespostaHttp:
    return RespostaHttp(status, texto)


if __name__ == "__main__":
    unittest.main()
