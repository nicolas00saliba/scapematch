#!/usr/bin/env python3
"""Monta os ícones do Parceiro a partir do logo com fundo preto.

A arte é o PNG em apps/parceiro/assets/parceiro/logo_parceiro.png (os pixels
do JPEG aprovado, sem redesenho). Cada arquivo do jogador define a tela
e a caixa do pin. O logo entra inteiro, em escala uniforme, centrado nessa
caixa. O que sobra da tela quadrada ou do maskable é o mesmo preto do
arquivo, #111111. Não corta o fundo, não usa transparência e não estica.
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps/parceiro/assets/parceiro/logo_parceiro.png"
PLAYER = ROOT / "web"
PARTNER = ROOT / "apps/parceiro/web"
BLACK = (17, 17, 17)
NAMES = (
    "favicon.png",
    "icons/Icon-192.png",
    "icons/Icon-512.png",
    "icons/Icon-maskable-192.png",
    "icons/Icon-maskable-512.png",
)


def is_partner_black(color: tuple[int, int, int]) -> bool:
    return max(abs(color[0] - 17), abs(color[1] - 17), abs(color[2] - 17)) <= 12


def is_player_white(color: tuple[int, int, int]) -> bool:
    return color[0] >= 246 and color[1] >= 246 and color[2] >= 246


def content_box(image: Image.Image, background) -> tuple[int, int, int, int]:
    width, height = image.size
    pixels = image.load()
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            if background(pixels[x, y]):
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if max_x < 0:
        raise SystemExit("imagem sem pin")
    return min_x, min_y, max_x, max_y


def render(source: Image.Image, player: Image.Image) -> Image.Image:
    source_box = content_box(source, is_partner_black)
    player_box = content_box(player, is_player_white)
    source_w = source_box[2] - source_box[0] + 1
    source_h = source_box[3] - source_box[1] + 1
    player_w = player_box[2] - player_box[0] + 1
    player_h = player_box[3] - player_box[1] + 1
    scale = min(player_w / source_w, player_h / source_h)
    # A altura inteira trava a proporção. A largura segue o arquivo.
    resized_h = max(1, round(source.height * scale))
    resized_w = max(1, round(source.width * resized_h / source.height))
    resized = source.resize((resized_w, resized_h), Image.Resampling.LANCZOS)
    fitted_w = source_w * resized_w / source.width
    fitted_h = source_h * resized_h / source.height
    content_x = source_box[0] * resized_w / source.width
    content_y = source_box[1] * resized_h / source.height
    paste_x = round(player_box[0] + (player_w - fitted_w) / 2 - content_x)
    paste_y = round(player_box[1] + (player_h - fitted_h) / 2 - content_y)
    canvas = Image.new("RGB", player.size, BLACK)
    canvas.paste(resized, (paste_x, paste_y))
    return canvas


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")
    if source.getpixel((0, 0)) != BLACK:
        raise SystemExit(f"fundo do arquivo é {source.getpixel((0, 0))}, não {BLACK}")
    for name in NAMES:
        player = Image.open(PLAYER / name).convert("RGB")
        icon = render(source, player)
        dest = PARTNER / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        icon.save(dest, format="PNG", optimize=True)
        box = content_box(icon, is_partner_black)
        width = box[2] - box[0] + 1
        height = box[3] - box[1] + 1
        print(
            f"{name} {icon.size[0]}x{icon.size[1]} "
            f"pin {width}x{height} em ({box[0]},{box[1]})"
        )


if __name__ == "__main__":
    sys.exit(main())
