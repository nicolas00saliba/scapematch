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


class LinksProducaoTeste(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        caminho = (
            Path(__file__).resolve().parents[1]
            / ".github"
            / "workflows"
            / "links-quebrados.yml"
        )
        cls.texto = caminho.read_text(encoding="utf-8")

    def args_producao(self):
        marcador = "LYCHEE_ARGS_PRODUCAO: >-\n"
        inicio = self.texto.index(marcador) + len(marcador)
        fim = self.texto.index("\n    steps:", inicio)
        return self.texto[inicio:fim]

    def test_retries_espera_e_concorrencia(self):
        args = self.args_producao()
        self.assertIn("--max-retries 4", args)
        self.assertIn("--retry-wait-time 10", args)
        self.assertIn("--max-concurrency 8", args)
        self.assertIn("--timeout 20", args)

    def test_nao_aceita_503_nem_tira_url(self):
        args = self.args_producao()
        self.assertIn("--accept 200,206,429", args)
        self.assertNotIn("503", args)
        self.assertIn("'https://escapematch.com.br'", args)
        self.assertIn("app|parceiro|parceiro-demo|demo|admin", args)

    def test_build_agendado_segue_com_duas_tentativas(self):
        trecho = self.texto.split("name: Links do build", 1)[1]
        trecho = trecho.split("\n      # continue-on-error:", 1)[0]
        self.assertIn("--max-retries 2", trecho)
        self.assertIn("--accept 200,206,429", trecho)
        self.assertNotIn("--retry-wait-time", trecho)
        self.assertNotIn("503", trecho)

    def test_repete_por_fora_quando_o_binario_nao_retenta_503(self):
        trecho = self.texto.split("name: Links de produção", 1)[1]
        self.assertIn("continue-on-error: true", trecho)
        self.assertIn("steps.links_producao.outcome == 'failure'", trecho)
        repetir = trecho.split("name: Repetir produção se a borda falhou", 1)[1]
        self.assertIn("for i in 1 2 3 4", repetir)
        self.assertIn("sleep 10", repetir)
        self.assertIn("lychee ${LYCHEE_ARGS_PRODUCAO}", repetir)
        self.assertIn("exit 1", repetir)


if __name__ == "__main__":
    unittest.main()
