#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

import disponibilidade
from disponibilidade import Alvo, Resultado, carregar_alvos, decidir


class DecidirTeste(unittest.TestCase):
    def test_abre_quando_cai_sem_issue(self):
        self.assertEqual(decidir(False, False), "abrir")

    def test_atualiza_quando_continua_fora(self):
        self.assertEqual(decidir(True, False), "atualizar")

    def test_fecha_quando_volta(self):
        self.assertEqual(decidir(True, True), "fechar")

    def test_nao_faz_nada_quando_esta_no_ar(self):
        self.assertEqual(decidir(False, True), "nada")


class AlvosTeste(unittest.TestCase):
    def test_le_host_e_texto(self):
        with tempfile.TemporaryDirectory() as pasta:
            caminho = Path(pasta) / "alvos.tsv"
            caminho.write_text(
                "# comentario\n\nexemplo.invalid\ttexto esperado\n",
                encoding="utf-8",
            )
            alvos = carregar_alvos(caminho)
        self.assertEqual(alvos, [Alvo("exemplo.invalid", "texto esperado")])

    def test_arquivo_do_repositorio_tem_os_hosts_do_deploy(self):
        hosts = {alvo.host for alvo in carregar_alvos(disponibilidade.ALVOS_PADRAO)}
        self.assertEqual(
            hosts,
            {
                "escapematch.com.br",
                "app.escapematch.com.br",
                "parceiro.escapematch.com.br",
                "admin.escapematch.com.br",
                "demo.escapematch.com.br",
                "parceiro-demo.escapematch.com.br",
            },
        )


class CorpoTeste(unittest.TestCase):
    def test_nao_inclui_html_da_pagina(self):
        texto = disponibilidade.corpo(
            Resultado("app.escapematch.com.br", False, "HTTPS respondeu 500", 1.2)
        )
        self.assertNotIn("<html", texto)
        self.assertIn("500", texto)


if __name__ == "__main__":
    unittest.main()
