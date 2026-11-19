#!/usr/bin/env python3
"""Confere se os workflows marcados com `# saude: agenda` passaram dentro da janela.

A janela cobre a agenda diária com margem para o atraso do agendador do GitHub.
O próprio `saude-ferramentas.yml` fica de fora: depois de uma falha ele nunca
mais acharia o próprio sucesso e permaneceria vermelho. Workflows só de pull
request também ficam de fora: num dia sem PR eles não rodam, e a rotina diária
olha a agenda. O marcador fica no próprio arquivo do workflow.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

JANELA = timedelta(hours=30)
MARCADOR = "# saude: agenda"
# O comentário do arquivo cita o marcador, então a busca por texto o incluiria.
# Avaliar a si mesmo vira um laço: uma falha impede o próximo sucesso.
PROPRIO_WORKFLOW = "saude-ferramentas.yml"
RAIZ = Path(__file__).resolve().parents[1]
WORKFLOWS = RAIZ / ".github" / "workflows"


def rotulo_janela(janela: timedelta = JANELA) -> str:
    horas = janela.total_seconds() / 3600
    if horas.is_integer():
        return f"{int(horas)}h"
    return f"{horas:g}h"


def workflows_agendados(diretorio: Path) -> list[str]:
    nomes: list[str] = []
    for caminho in sorted(diretorio.glob("*.yml")):
        if caminho.name == PROPRIO_WORKFLOW:
            continue
        if MARCADOR in caminho.read_text(encoding="utf-8"):
            nomes.append(caminho.name)
    return nomes


def dentro_da_janela(criado_em: str, agora: datetime, janela: timedelta = JANELA) -> bool:
    instante = datetime.fromisoformat(criado_em.replace("Z", "+00:00"))
    if instante.tzinfo is None:
        instante = instante.replace(tzinfo=timezone.utc)
    return agora - instante <= janela


def avaliar(execucoes: list[dict], agora: datetime) -> list[str]:
    recentes = [
        item
        for item in execucoes
        if item.get("conclusion") == "success"
        and dentro_da_janela(item["createdAt"], agora)
    ]
    if recentes:
        return []
    if not execucoes:
        return ["nenhuma execução encontrada"]
    return [f"nenhum sucesso nas últimas {rotulo_janela()}"]


def listar_execucoes(workflow: str) -> list[dict]:
    completo = subprocess.run(
        [
            "gh",
            "run",
            "list",
            "--workflow",
            workflow,
            "--limit",
            "20",
            "--json",
            "conclusion,createdAt,workflowName",
        ],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ},
    )
    return json.loads(completo.stdout or "[]")


def main() -> int:
    agora = datetime.now(timezone.utc)
    nomes = workflows_agendados(WORKFLOWS)
    if not nomes:
        print("Nenhum workflow com o marcador de saúde.")
        return 1
    falhas: list[str] = []
    for nome in nomes:
        try:
            execucoes = listar_execucoes(nome)
        except subprocess.CalledProcessError as erro:
            falhas.append(f"{nome}: não foi possível listar execuções ({erro.returncode})")
            continue
        problemas = avaliar(execucoes, agora)
        if problemas:
            falhas.append(f"{nome}: {problemas[0]}")
        else:
            print(f"{nome}: sucesso nas últimas {rotulo_janela()}")
    if falhas:
        for linha in falhas:
            print(linha, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
