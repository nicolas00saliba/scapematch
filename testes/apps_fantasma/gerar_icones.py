#!/usr/bin/env python3
"""Gera o ícone de cada app fantasma a partir do contas.json.

Azul = jogador, laranja = casa. O número grande diz qual conta é.
Os PNGs saem em android/app/src/<slug>/res e não entram no git.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]
FONTE = RAIZ / "apps/parceiro/assets/fonts/Poppins-Medium.ttf"
CORES = {"jogador": "#1E88E5", "casa": "#E65100"}
LETRA = {"jogador": "J", "casa": "C"}
TAMANHOS = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def fonte(tamanho):
    try:
        return ImageFont.truetype(str(FONTE), tamanho)
    except OSError:
        return ImageFont.load_default(tamanho)


def icone(tipo, numero, lado):
    escala = 4
    big = lado * escala
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, big - 1, big - 1), radius=big // 5, fill=CORES[tipo])
    texto = f"{LETRA[tipo]}{numero}"
    f = fonte(int(big * 0.46))
    caixa = d.textbbox((0, 0), texto, font=f)
    w, h = caixa[2] - caixa[0], caixa[3] - caixa[1]
    d.text(((big - w) / 2 - caixa[0], big * 0.40 - h / 2 - caixa[1]), texto, font=f, fill="white")
    faixa = int(big * 0.24)
    d.rectangle((0, big - faixa - big // 10, big, big - big // 10), fill=(0, 0, 0, 90))
    f2 = fonte(int(faixa * 0.62))
    caixa = d.textbbox((0, 0), "TESTE", font=f2)
    w, h = caixa[2] - caixa[0], caixa[3] - caixa[1]
    y0 = big - faixa - big // 10
    d.text(((big - w) / 2 - caixa[0], y0 + (faixa - h) / 2 - caixa[1]), "TESTE", font=f2, fill="white")
    return img.resize((lado, lado), Image.LANCZOS)


def main():
    config = json.loads((AQUI / "contas.json").read_text())
    for conta in config["contas"]:
        for pasta, lado in TAMANHOS.items():
            destino = AQUI / "android/app/src" / conta["slug"] / "res" / f"mipmap-{pasta}"
            destino.mkdir(parents=True, exist_ok=True)
            icone(conta["tipo"], conta["numero"], lado).save(destino / "ic_launcher.png")
        prévia = AQUI / "android/app/build/icones"
        prévia.mkdir(parents=True, exist_ok=True)
        icone(conta["tipo"], conta["numero"], 192).save(prévia / f"{conta['slug']}.png")
    print(f"{len(config['contas'])} ícones gerados")


if __name__ == "__main__":
    main()
