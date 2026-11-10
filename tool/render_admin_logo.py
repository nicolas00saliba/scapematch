#!/usr/bin/env python3
"""Gera o ícone do EscapeMatch Admin a partir do símbolo transparente.

O desenho do pino, dos três jogadores e da fechadura está em
apps/admin/assets/brand/logo_admin_simbolo.svg (os mesmos caminhos de
assets/brand/logo_simbolo.svg). Este script só monta o fundo e os PNG.
Não mexe no logo do jogador, do Parceiro, da demo nem da landing.

Rode na raiz do repositório: python3 tool/render_admin_logo.py
"""

from __future__ import annotations

import io
import re
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ADMIN = ROOT / "apps" / "admin"
SYMBOL = ADMIN / "assets" / "brand" / "logo_admin_simbolo.svg"
ICON_SVG = ADMIN / "assets" / "brand" / "logo_admin_icone.svg"
WEB = ADMIN / "web"
BLACK = (0, 0, 0)
PLATE = 512
RADIUS = 114


def view_box(svg: str) -> tuple[float, float, float, float]:
    match = re.search(r'viewBox="([^"]+)"', svg)
    if not match:
        raise SystemExit("símbolo sem viewBox")
    x, y, width, height = (float(part) for part in match.group(1).split())
    return x, y, width, height


def inner(svg: str) -> str:
    start = svg.find(">", svg.find("<svg")) + 1
    end = svg.rfind("</svg>")
    return svg[start:end].strip()


def plate_svg(symbol: str) -> str:
    x, y, width, height = view_box(symbol)
    scale = (PLATE * 0.9) / height
    drawn_w = width * scale
    drawn_h = height * scale
    tx = (PLATE - drawn_w) / 2 - x * scale
    ty = (PLATE - drawn_h) / 2 - y * scale
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">\n'
        f'  <rect width="512" height="512" rx="{RADIUS}" fill="#000000"/>\n'
        f'  <g transform="translate({tx:.3f} {ty:.3f}) scale({scale:.6f})">\n'
        f"{inner(symbol)}\n"
        "  </g>\n"
        "</svg>\n"
    )


def render(svg: str | Path, size: int) -> Image.Image:
    data = svg.read_bytes() if isinstance(svg, Path) else svg.encode()
    png = cairosvg.svg2png(bytestring=data, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def on_black(image: Image.Image) -> Image.Image:
    canvas = Image.new("RGB", image.size, BLACK)
    canvas.paste(image, mask=image.split()[-1])
    return canvas


def content_box(image: Image.Image) -> tuple[int, int, int, int]:
    pixels = image.load()
    width, height = image.size
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha < 40 or max(red, green, blue) < 28:
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if max_x < 0:
        raise SystemExit("símbolo sem desenho")
    return min_x, min_y, max_x, max_y


def maskable(symbol_png: Image.Image, size: int) -> Image.Image:
    """Fundo preto até a borda. A marca cabe no círculo seguro de 80%."""
    box = content_box(symbol_png)
    content_h = box[3] - box[1] + 1
    scale = (size * 0.70) / content_h
    resized = symbol_png.resize(
        (max(1, round(symbol_png.width * scale)), max(1, round(symbol_png.height * scale))),
        Image.Resampling.LANCZOS,
    )
    scaled_box = tuple(round(value * scale) for value in box)
    content_w = scaled_box[2] - scaled_box[0] + 1
    content_h = scaled_box[3] - scaled_box[1] + 1
    paste_x = round((size - content_w) / 2 - scaled_box[0])
    paste_y = round((size - content_h) / 2 - scaled_box[1])
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    canvas.paste(resized, (paste_x, paste_y), resized)
    check_safe_zone(canvas)
    return on_black(canvas)


def check_safe_zone(image: Image.Image) -> None:
    pixels = image.load()
    size = image.width
    center = (size - 1) / 2
    limit = (size * 0.40) ** 2
    for y in range(size):
        for x in range(size):
            red, green, blue, alpha = pixels[x, y]
            if alpha < 40 or max(red, green, blue) < 48:
                continue
            if (x - center) ** 2 + (y - center) ** 2 > limit:
                raise SystemExit(f"marca fora da zona segura do maskable em {x},{y}")


def main() -> None:
    symbol = SYMBOL.read_text()
    icon = plate_svg(symbol)
    ICON_SVG.write_text(icon)
    (WEB / "favicon.svg").write_text(icon)
    (WEB / "icons").mkdir(parents=True, exist_ok=True)
    (WEB / "icons" / "logo.svg").write_text(symbol)

    plate = render(icon, 512)
    symbol_png = render(SYMBOL, 1024)
    favicon = render(icon, 32)

    on_black(plate).resize((192, 192), Image.Resampling.LANCZOS).save(
        WEB / "icons" / "Icon-192.png"
    )
    on_black(plate).save(WEB / "icons" / "Icon-512.png")
    maskable(symbol_png, 192).save(WEB / "icons" / "Icon-maskable-192.png")
    maskable(symbol_png, 512).save(WEB / "icons" / "Icon-maskable-512.png")
    on_black(plate).resize((180, 180), Image.Resampling.LANCZOS).save(
        WEB / "apple-touch-icon.png"
    )
    favicon.save(WEB / "favicon.png")
    print("ícones do Admin gravados")


if __name__ == "__main__":
    main()
