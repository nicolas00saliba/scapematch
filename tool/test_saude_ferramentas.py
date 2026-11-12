#!/usr/bin/env python3
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from saude_ferramentas import avaliar, dentro_da_janela, workflows_agendados


AGORA = datetime(2026, 11, 12, 15, tzinfo=timezone.utc)


class JanelaTeste(unittest.TestCase):
    def test_sucesso_recente_passa(self):
        execucoes = [
            {
                "conclusion": "success",
                "createdAt": "2026-11-12T14:00:00Z",
            }
        ]
        self.assertEqual(avaliar(execucoes, AGORA), [])

    def test_sucesso_antigo_falha(self):
        execucoes = [
            {
                "conclusion": "success",
                "createdAt": "2026-11-11T10:00:00Z",
            }
        ]
        self.assertEqual(avaliar(execucoes, AGORA), ["nenhum sucesso nas últimas 24h"])

    def test_falha_recente_nao_conta(self):
        execucoes = [
            {
                "conclusion": "failure",
                "createdAt": "2026-11-12T14:30:00Z",
            }
        ]
        self.assertEqual(avaliar(execucoes, AGORA), ["nenhum sucesso nas últimas 24h"])

    def test_sem_execucao(self):
        self.assertEqual(avaliar([], AGORA), ["nenhuma execução encontrada"])

    def test_limite_de_24_horas(self):
        criado = (AGORA - timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.assertTrue(dentro_da_janela(criado, AGORA))
        atras = (AGORA - timedelta(hours=24, seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.assertFalse(dentro_da_janela(atras, AGORA))


class MarcadorTeste(unittest.TestCase):
    def test_so_entra_quem_tem_o_marcador(self):
        with tempfile.TemporaryDirectory() as pasta:
            diretorio = Path(pasta)
            (diretorio / "disponibilidade.yml").write_text(
                "name: Disponibilidade\n# saude: agenda\n",
                encoding="utf-8",
            )
            (diretorio / "lighthouse.yml").write_text(
                "name: Lighthouse\n",
                encoding="utf-8",
            )
            self.assertEqual(
                workflows_agendados(diretorio),
                ["disponibilidade.yml"],
            )


if __name__ == "__main__":
    unittest.main()
