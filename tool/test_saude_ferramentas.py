#!/usr/bin/env python3
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from saude_ferramentas import JANELA, avaliar, dentro_da_janela, workflows_agendados


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

    def test_sucesso_ha_24h05_conta_como_ok(self):
        criado = (AGORA - timedelta(hours=24, minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
        execucoes = [{"conclusion": "success", "createdAt": criado}]
        self.assertEqual(avaliar(execucoes, AGORA), [])

    def test_sucesso_ha_31h_falha(self):
        criado = (AGORA - timedelta(hours=31)).strftime("%Y-%m-%dT%H:%M:%SZ")
        execucoes = [{"conclusion": "success", "createdAt": criado}]
        self.assertEqual(avaliar(execucoes, AGORA), ["nenhum sucesso nas últimas 30h"])

    def test_falha_recente_nao_conta(self):
        execucoes = [
            {
                "conclusion": "failure",
                "createdAt": "2026-11-12T14:30:00Z",
            }
        ]
        self.assertEqual(avaliar(execucoes, AGORA), ["nenhum sucesso nas últimas 30h"])

    def test_sem_execucao(self):
        self.assertEqual(avaliar([], AGORA), ["nenhuma execução encontrada"])

    def test_limite_da_janela(self):
        self.assertEqual(JANELA, timedelta(hours=30))
        criado = (AGORA - JANELA).strftime("%Y-%m-%dT%H:%M:%SZ")
        self.assertTrue(dentro_da_janela(criado, AGORA))
        atras = (AGORA - JANELA - timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
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

    def test_proprio_workflow_nao_e_avaliado(self):
        with tempfile.TemporaryDirectory() as pasta:
            diretorio = Path(pasta)
            (diretorio / "saude-ferramentas.yml").write_text(
                "name: Saúde das ferramentas\n# saude: agenda\n",
                encoding="utf-8",
            )
            (diretorio / "links-quebrados.yml").write_text(
                "name: Links quebrados\n# saude: agenda\n",
                encoding="utf-8",
            )
            self.assertEqual(
                workflows_agendados(diretorio),
                ["links-quebrados.yml"],
            )


if __name__ == "__main__":
    unittest.main()
