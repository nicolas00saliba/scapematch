#!/usr/bin/env python3
"""Gera os ícones do site a partir do símbolo oficial.

O desenho sai de assets/brand/logo_simbolo.svg (o mesmo arquivo
publicado em apps/site/public/assets/). O pino fica centralizado
num quadrado creme #F4F1EA, na mesma proporção do apple-touch que
o site já usava, para continuar legível em fundo claro e no tamanho
pequeno da busca.

Rode na raiz do repositório: python3 tool/render_site_icons.py
Precisa de Pillow e CairoSVG, como tool/render_admin_logo.py.
Não publica o site e não mexe no app, no Parceiro nem no Admin.
"""

from __future__ import annotations

import io
import re
import struct
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SYMBOL = ROOT / "assets" / "brand" / "logo_simbolo.svg"
SITE = ROOT / "apps" / "site" / "public"
CREME = "#F4F1EA"
# Altura do viewBox em relação ao quadrado. O traço do pino ocupa
# cerca de 72% do lado, igual ao apple-touch de 180 px já publicado.
ALTURA = 0.775
PNG = (48, 96, 192, 512)
ICO = (16, 32, 48, 64, 96, 128, 192, 256)


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


def plate(symbol: str) -> str:
    x, y, width, height = view_box(symbol)
    scale = ALTURA / height
    drawn_w = width * scale
    drawn_h = height * scale
    tx = (1 - drawn_w) / 2 - x * scale
    ty = (1 - drawn_h) / 2 - y * scale
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">\n'
        f'  <rect width="1" height="1" fill="{CREME}"/>\n'
        f'  <g transform="translate({tx:.6f} {ty:.6f}) scale({scale:.8f})">\n'
        f"{inner(symbol)}\n"
        "  </g>\n"
        "</svg>\n"
    )


def render(svg: str, size: int) -> Image.Image:
    png = cairosvg.svg2png(
        bytestring=svg.encode(),
        output_width=size,
        output_height=size,
    )
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    if image.size != (size, size):
        raise SystemExit(f"render saiu {image.size}, esperado {size}")
    return image


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def save_ico(images: list[Image.Image], path: Path) -> None:
    """ICO com um PNG por tamanho. O navegador e o Google leem esse formato."""
    ordered = sorted(images, key=lambda item: item.width)
    payloads: list[bytes] = []
    for image in ordered:
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        payloads.append(buffer.getvalue())
    count = len(ordered)
    header = struct.pack("<HHH", 0, 1, count)
    entries = bytearray()
    body = bytearray()
    offset = 6 + 16 * count
    for image, blob in zip(ordered, payloads):
        width = 0 if image.width >= 256 else image.width
        height = 0 if image.height >= 256 else image.height
        entries += struct.pack("<BBBBHHII", width, height, 0, 0, 1, 32, len(blob), offset)
        body += blob
        offset += len(blob)
    path.write_bytes(header + entries + body)


def main() -> None:
    symbol = SYMBOL.read_text()
    published = (
        SITE / "assets" / "logo-simbolo.svg",
        SITE / "assets" / "favicon.svg",
    )
    for path in published:
        if path.read_text() != symbol:
            raise SystemExit(f"{path.relative_to(ROOT)} divergiu do símbolo oficial")
    svg = plate(symbol)
    frames = {size: render(svg, size) for size in sorted(set(PNG + ICO + (32, 180)))}

    for size in PNG:
        save_png(frames[size], SITE / "assets" / f"favicon-{size}.png")
    save_png(frames[512], SITE / "assets" / "logo-512.png")
    save_png(frames[32], SITE / "assets" / "favicon-32.png")
    save_png(frames[180], SITE / "apple-touch-icon.png")
    save_png(frames[180], SITE / "assets" / "apple-touch.png")
    save_ico([frames[size] for size in ICO], SITE / "favicon.ico")
    print("ícones do site gravados")


if __name__ == "__main__":
    main()
