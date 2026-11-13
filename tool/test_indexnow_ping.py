#!/usr/bin/env python3
"""Confere o corpo do IndexNow sem chamar a rede."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import indexnow_ping


CHAVE = "9360498fa2723ee1d3118bb648bbdbd7"


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


if __name__ == "__main__":
    unittest.main()
