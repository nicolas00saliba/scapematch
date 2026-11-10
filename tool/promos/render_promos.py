#!/usr/bin/env python3
"""Gera os flyers de Promoções no desenho atual do EscapeMatch.

A fonte é a Poppins Medium do app (assets/fonts/Poppins-Medium.ttf). O texto
vira contorno, então o PNG não depende da fonte instalada na máquina. O pin é
o de assets/brand/logo_simbolo.svg (versão clara no fundo escuro). O letreiro
completo só entra quando há uma faixa de cabeçalho; nos cantos fica o símbolo.

Saída:
  tool/promos/src/*.svg
  assets/images/promos/*.png   (1920×1080, 16:9)

Uso, na raiz do repositório:
  python3 tool/promos/render_promos.py
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
FONT_PATH = ROOT / "assets" / "fonts" / "Poppins-Medium.ttf"
SVG_DIR = ROOT / "tool" / "promos" / "src"
PNG_DIR = ROOT / "assets" / "images" / "promos"
BUILD = Path("/tmp/scapematch-promos")

W = 1920
H = 1080

# Tema do app (lib/app/theme.dart) e da marca (lib/core/ui/scape_logo.dart).
PIN = "#0F4C4A"
PIN_ON_DARK = "#F4F1EA"
COPPER = "#D2642A"
CREAM = "#F5F1EA"
PAPER = "#FFFFFF"
INK = "#142421"
GOLD = "#E3A83F"
GOLD_SOFT = "#F2C46B"
NIGHT = "#0E1716"
PAGE_DARK = "#0E1716"

# Espaço entre letras do letreiro: o SVG da marca usa -1 px em 128 px.
WORDMARK_TRACKING = -1 / 128


class Face:
    """Poppins Medium desenhada como caminho SVG."""

    def __init__(self, path: Path) -> None:
        font = TTFont(path)
        self.glyphs = font.getGlyphSet()
        self.cmap = font.getBestCmap()
        self.upem = font["head"].unitsPerEm
        self.hmtx = font["hmtx"]
        self.cap = font["OS/2"].sCapHeight / self.upem

    def _glyph(self, char: str) -> tuple[str, int]:
        code = ord(char)
        if code not in self.cmap:
            raise SystemExit(f"Poppins não tem o glifo {char!r}")
        name = self.cmap[code]
        return name, self.hmtx[name][0]

    def width(self, text: str, size: float, tracking: float = 0.0) -> float:
        if not text:
            return 0.0
        scale = size / self.upem
        total = 0.0
        for index, char in enumerate(text):
            _, advance = self._glyph(char)
            total += advance * scale
            if index != len(text) - 1:
                total += tracking
        return total

    def draw(
        self,
        text: str,
        x: float,
        y: float,
        size: float,
        fill: str,
        tracking: float = 0.0,
        anchor: str = "start",
    ) -> tuple[str, float]:
        """Desenha [text] com a linha de base em [y]. Devolve o SVG e o x final."""
        if anchor == "middle":
            x -= self.width(text, size, tracking) / 2
        elif anchor == "end":
            x -= self.width(text, size, tracking)
        elif anchor != "start":
            raise ValueError(anchor)

        scale = size / self.upem
        parts: list[str] = []
        cursor = x
        for index, char in enumerate(text):
            name, advance = self._glyph(char)
            pen = SVGPathPen(self.glyphs)
            self.glyphs[name].draw(pen)
            commands = pen.getCommands()
            if commands:
                parts.append(
                    f'<path d="{commands}" fill="{fill}" '
                    f'transform="translate({cursor:.2f} {y:.2f}) '
                    f'scale({scale:.5f} {-scale:.5f})"/>'
                )
            cursor += advance * scale
            if index != len(text) - 1:
                cursor += tracking
        return "".join(parts), cursor


def tracking_of(size: float, em: float = -0.02) -> float:
    return size * em


def mark(x: float, y: float, height: float, on_dark: bool) -> str:
    """Símbolo do app. [height] é a altura do viewBox 200×260."""
    scale = height / 260
    pin = PIN_ON_DARK if on_dark else PIN
    return f'''<g transform="translate({x:.2f} {y:.2f}) scale({scale:.5f})">
      <path d="M100 250 L28 154 A90 90 0 1 1 172 154 Z" fill="{pin}"/>
      <circle cx="100" cy="100" r="64" fill="#FFFFFF"/>
      <circle cx="64" cy="78" r="11" fill="{COPPER}"/>
      <path d="M50 115 L50 107 A14 14 0 0 1 78 107 L78 115 Z" fill="{COPPER}"/>
      <circle cx="136" cy="78" r="11" fill="{COPPER}"/>
      <path d="M122 115 L122 107 A14 14 0 0 1 150 107 L150 115 Z" fill="{COPPER}"/>
      <circle cx="100" cy="66" r="14" fill="{COPPER}"/>
      <path d="M81 114 L81 103 A19 19 0 0 1 119 103 L119 114 Z" fill="{COPPER}"/>
      <circle cx="100" cy="134" r="10" fill="{PIN}"/>
      <path d="M94.5 139 L90 158 L110 158 L105.5 139 Z" fill="{PIN}"/>
    </g>'''


def lockup(face: Face, x: float, y: float, height: float, on_dark: bool) -> str:
    """Símbolo mais letreiro, na proporção de ScapeLogo (Poppins 500)."""
    size = height * 0.52
    tracking = size * WORDMARK_TRACKING
    # O círculo branco do pin fica perto de 38% da altura. O miolo das
    # maiúsculas alinha nesse centro, como o widget faz no topo largo.
    baseline = y + height * 0.385 + (size * face.cap) / 2
    pin_width = height * 200 / 260
    gap = height * 0.18
    scape_fill = PIN_ON_DARK if on_dark else PIN
    scape, end = face.draw(
        "Escape",
        x + pin_width + gap,
        baseline,
        size,
        scape_fill,
        tracking,
    )
    match, _end = face.draw("Match", end + tracking, baseline, size, COPPER, tracking)
    return mark(x, y, height, on_dark) + scape + match


def dots(
    x: float,
    y: float,
    cols: int,
    rows: int,
    gap: float,
    radius: float,
    fill: str,
    opacity: float,
) -> str:
    circles = []
    for row in range(rows):
        for col in range(cols):
            circles.append(
                f'<circle cx="{x + col * gap:.1f}" cy="{y + row * gap:.1f}" '
                f'r="{radius}" fill="{fill}" opacity="{opacity}"/>'
            )
    return "\n".join(circles)


def maze(x: float, y: float, scale: float, stroke: str, opacity: float = 1) -> str:
    # Espiral reta: o labirinto do escape, em traço limpo.
    path = "M0 10 H86 V86 H16 V26 H70 V70 H32 V42 H54"
    return (
        f'<path d="{path}" fill="none" stroke="{stroke}" stroke-width="7" '
        f'stroke-linecap="square" stroke-linejoin="miter" opacity="{opacity}" '
        f'transform="translate({x:.1f} {y:.1f}) scale({scale:.3f})"/>'
    )


def star(cx: float, cy: float, radius: float, fill: str) -> str:
    arm = radius * 0.22
    return (
        f'<path d="M{cx:.1f} {cy - radius:.1f} L{cx + arm:.1f} {cy - arm:.1f} '
        f'L{cx + radius:.1f} {cy:.1f} L{cx + arm:.1f} {cy + arm:.1f} '
        f'L{cx:.1f} {cy + radius:.1f} L{cx - arm:.1f} {cy + arm:.1f} '
        f'L{cx - radius:.1f} {cy:.1f} L{cx - arm:.1f} {cy - arm:.1f} Z" '
        f'fill="{fill}"/>'
    )


def medallion(cx: float, cy: float) -> str:
    """Círculo com a pessoa do meio do pin, no tamanho do selo."""
    return (
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="78" fill="none" '
        f'stroke="{GOLD}" stroke-width="3.5"/>'
        f'<g transform="translate({cx:.1f} {cy + 6:.1f}) scale(2.2) translate(-100 -84)" fill="{GOLD}">'
        f'<circle cx="100" cy="66" r="14"/>'
        f'<path d="M81 114 L81 103 A19 19 0 0 1 119 103 L119 114 Z"/>'
        f'</g>'
    )


def key(cx: float, cy: float, color: str) -> str:
    return f'''<g transform="translate({cx:.1f} {cy:.1f})" fill="none" stroke="{color}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="-18" cy="0" r="13"/>
      <path d="M-5 0 H32 M20 -10 V0 M32 -10 V0"/>
    </g>'''


def rules_around(
    face: Face,
    text: str,
    cx: float,
    baseline: float,
    size: float,
    color: str,
    line: float = 148,
) -> str:
    width = face.width(text, size, tracking_of(size, -0.01))
    gap = 26
    y = baseline - size * face.cap * 0.42
    left = cx - width / 2 - gap
    right = cx + width / 2 + gap
    return (
        f'<line x1="{left - line:.1f}" y1="{y:.1f}" x2="{left:.1f}" y2="{y:.1f}" '
        f'stroke="{color}" stroke-width="6" stroke-linecap="round"/>'
        f'<line x1="{right:.1f}" y1="{y:.1f}" x2="{right + line:.1f}" y2="{y:.1f}" '
        f'stroke="{color}" stroke-width="6" stroke-linecap="round"/>'
    )


def svg_document(title: str, body: str) -> str:
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="{title}">
  <title>{title}</title>
  <rect width="{W}" height="{H}" fill="{CREAM}"/>
  {body}
</svg>
'''


def banner_quarta(face: Face) -> str:
    """2 POR 1 ÀS QUARTAS. Cupom central; o canto só cabe o símbolo."""
    ticket_x, ticket_y, ticket_w, ticket_h = 250, 150, 1280, 790
    ticket_cx = ticket_x + ticket_w / 2
    notch_y = ticket_y + ticket_h / 2
    body = f'''
    <polygon points="0,0 360,0 0,250" fill="{PIN}"/>
    <polygon points="0,0 168,0 0,118" fill="{COPPER}"/>
    <polygon points="0,{H} 0,800 250,{H}" fill="{COPPER}"/>
    <polygon points="0,{H} 0,960 120,{H}" fill="{PIN}"/>
    <polygon points="{W},0 {W},300 1560,0" fill="{COPPER}"/>
    <polygon points="{W},{H} {W},640 1420,{H}" fill="{PIN}"/>
    {dots(1708, 250, 4, 6, 26, 4.5, PIN, 0.22)}
    {maze(48, 560, 1.35, PIN, 0.45)}
    <rect x="{ticket_x + 10}" y="{ticket_y + 16}" width="{ticket_w}" height="{ticket_h}" rx="36" fill="{INK}" opacity="0.06"/>
    <rect x="{ticket_x}" y="{ticket_y}" width="{ticket_w}" height="{ticket_h}" rx="36" fill="{PAPER}" stroke="{PIN}" stroke-width="10"/>
    <rect x="{ticket_x + 28}" y="{ticket_y + 28}" width="{ticket_w - 56}" height="{ticket_h - 56}" rx="22" fill="none" stroke="{COPPER}" stroke-width="3" stroke-dasharray="14 12"/>
    <circle cx="{ticket_x}" cy="{notch_y}" r="34" fill="{CREAM}" stroke="{PIN}" stroke-width="10"/>
    <circle cx="{ticket_x + ticket_w}" cy="{notch_y}" r="34" fill="{CREAM}" stroke="{PIN}" stroke-width="10"/>
    '''
    headline = tracking_of(158, -0.025)
    sub = tracking_of(52, -0.01)
    bottom = tracking_of(148, -0.03)
    line_two, _ = face.draw(
        "2 POR 1",
        ticket_cx,
        455,
        158,
        PIN,
        headline,
        "middle",
    )
    as_word, _ = face.draw("ÀS", ticket_cx, 590, 52, COPPER, sub, "middle")
    quartas, _ = face.draw(
        "QUARTAS",
        ticket_cx,
        800,
        148,
        PIN,
        bottom,
        "middle",
    )
    # O triângulo teal da direita é estreito: cabe o símbolo, não o letreiro.
    logo = mark(1724, 836, 188, on_dark=True)
    return svg_document(
        "2 POR 1 ÀS QUARTAS",
        body + rules_around(face, "ÀS", ticket_cx, 590, 52, COPPER, 160) + line_two + as_word + quartas + logo,
    )


def banner_dez(face: Face) -> str:
    """10% no primeiro jogo. A faixa de cima comporta o logo completo."""
    phrase = "no primeiro jogo"
    phrase_size = 58
    phrase_track = tracking_of(phrase_size, -0.015)
    phrase_w = face.width(phrase, phrase_size, phrase_track)
    bar_w = phrase_w + 112
    bar_h = 118
    bar_x = (W - bar_w) / 2
    bar_y = 786
    bar_cy = bar_y + bar_h / 2
    # Caixa eme centrada na barra (o texto tem descendentes em j e g).
    phrase_baseline = bar_cy + phrase_size * 0.28
    percent_size = 470
    percent_track = tracking_of(percent_size, -0.045)
    percent_w = face.width("10%", percent_size, percent_track)
    percent_x = (W - percent_w) / 2
    percent_baseline = 690
    body = f'''
    <polygon points="{W},0 1500,0 {W},250" fill="{COPPER}"/>
    <polygon points="{W},0 1740,0 {W},130" fill="{PIN}"/>
    <polygon points="{W},{H} {W},760 1560,{H}" fill="{PIN}"/>
    <polygon points="{W},{H} {W},940 1760,{H}" fill="{COPPER}"/>
    <polygon points="0,{H} 280,{H} 0,820" fill="{COPPER}"/>
    <polygon points="0,{H} 150,{H} 0,940" fill="{PIN}"/>
    {dots(1180, 78, 6, 4, 26, 4.5, PIN, 0.22)}
    {dots(360, 930, 5, 3, 24, 4, PIN, 0.2)}
    <g transform="translate(250 980) rotate(-28)" opacity="0.9">
      <rect width="210" height="10" rx="5" fill="{PIN}"/>
      <rect y="22" width="150" height="10" rx="5" fill="{COPPER}"/>
    </g>
    <rect x="{bar_x:.1f}" y="{bar_y}" width="{bar_w:.1f}" height="{bar_h}" rx="24" fill="{COPPER}"/>
    '''
    percent, _ = face.draw(
        "10%",
        percent_x,
        percent_baseline,
        percent_size,
        PIN,
        percent_track,
    )
    label, _ = face.draw(
        phrase,
        W / 2,
        phrase_baseline,
        phrase_size,
        PAPER,
        phrase_track,
        "middle",
    )
    # Cabeçalho largo: símbolo + EscapeMatch, como no topo do site.
    logo = lockup(face, 64, 48, 196, on_dark=False)
    return svg_document("10% no primeiro jogo", body + percent + label + logo)


def banner_combo(face: Face) -> str:
    """Combo grupo de 6. Fundo petróleo; o rodapé só cabe o símbolo claro."""
    body = f'''
    <rect width="{W}" height="{H}" fill="{PIN}"/>
    <rect x="40" y="40" width="{W - 80}" height="{H - 80}" rx="32" fill="none" stroke="{GOLD}" stroke-width="3"/>
    <rect x="58" y="58" width="{W - 116}" height="{H - 116}" rx="24" fill="none" stroke="{GOLD}" stroke-width="1.4" opacity="0.7"/>
    {maze(96, 96, 1.15, GOLD, 0.28)}
    {maze(1688, 120, 1.05, GOLD, 0.22)}
    {star(620, 188, 16, GOLD)}
    <line x1="400" y1="188" x2="580" y2="188" stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>
    <line x1="660" y1="188" x2="840" y2="188" stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>
    '''
    # A seta do carrossel ocupa uns 44 px na borda. O texto fica à direita dela.
    left = 340
    combo, _ = face.draw("Combo", left, 360, 136, CREAM, tracking_of(136, -0.03))
    grupo, _ = face.draw("grupo", left, 520, 136, CREAM, tracking_of(136, -0.03))
    de, de_end = face.draw("de", left, 742, 92, CREAM, tracking_of(92, -0.02))
    six, _ = face.draw("6", de_end + 36, 742, 220, GOLD, 0)
    icons = []
    for cy in (400, 640):
        for col in range(3):
            icons.append(medallion(1188 + col * 176, cy))
    footer_y = 918
    ornament = (
        f'<line x1="128" y1="{footer_y}" x2="780" y2="{footer_y}" stroke="{GOLD}" stroke-width="2.5" stroke-linecap="round"/>'
        f'<line x1="980" y1="{footer_y}" x2="1540" y2="{footer_y}" stroke="{GOLD}" stroke-width="2.5" stroke-linecap="round"/>'
        + key(910, footer_y, GOLD)
        + star(250, footer_y, 9, GOLD)
        + star(1420, footer_y, 9, GOLD)
        + dots(148, 980, 4, 1, 18, 3.5, GOLD, 0.9)
    )
    logo = mark(1648, 812, 176, on_dark=True)
    return svg_document(
        "Combo grupo de 6",
        body + combo + grupo + de + six + "".join(icons) + ornament + logo,
    )


def banner_sexta(face: Face) -> str:
    """SEXTA DO TERROR. Noite, lua de cobre e castelo; canto com o símbolo claro."""
    sky = f'<rect width="{W}" height="{H}" fill="{NIGHT}"/>'
    stars = "\n".join(
        [
            star(980, 120, 10, GOLD_SOFT),
            star(1120, 210, 7, GOLD),
            star(860, 250, 5, GOLD_SOFT),
            star(700, 140, 6, GOLD),
            star(1040, 70, 4, PAPER),
            f'<circle cx="760" cy="90" r="2.5" fill="{PAPER}" opacity="0.8"/>',
            f'<circle cx="900" cy="180" r="2" fill="{GOLD_SOFT}"/>',
            f'<circle cx="1180" cy="130" r="2.2" fill="{PAPER}" opacity="0.7"/>',
        ]
    )
    moon = f'''
    <defs>
      <radialGradient id="moon" cx="40%" cy="38%" r="68%">
        <stop offset="0%" stop-color="#FFF8E4"/>
        <stop offset="42%" stop-color="{GOLD_SOFT}"/>
        <stop offset="74%" stop-color="{GOLD}"/>
        <stop offset="100%" stop-color="{COPPER}"/>
      </radialGradient>
    </defs>
    <circle cx="1470" cy="390" r="360" fill="{COPPER}" opacity="0.16"/>
    <circle cx="1470" cy="390" r="318" fill="url(#moon)"/>
    <circle cx="1360" cy="300" r="46" fill="{COPPER}" opacity="0.16"/>
    <circle cx="1560" cy="340" r="28" fill="{COPPER}" opacity="0.14"/>
    <circle cx="1488" cy="470" r="62" fill="{COPPER}" opacity="0.12"/>
    <circle cx="1390" cy="450" r="18" fill="{PIN}" opacity="0.08"/>
    <circle cx="1470" cy="390" r="300" fill="none" stroke="#FFF6D8" stroke-width="2" opacity="0.35"/>
    '''
    branches = '''
    <g fill="none" stroke="#081413" stroke-linecap="round" stroke-linejoin="round">
      <path d="M1920 80 C1760 140 1700 80 1560 160" stroke-width="16"/>
      <path d="M1700 100 C1660 180 1740 220 1680 300" stroke-width="8"/>
      <path d="M1920 260 C1800 240 1760 340 1640 300" stroke-width="12"/>
      <path d="M1600 150 C1520 200 1560 250 1480 230" stroke-width="7"/>
      <path d="M1040 1080 C1100 860 1000 780 1080 640" stroke-width="18"/>
      <path d="M1080 760 C1160 740 1180 820 1260 790" stroke-width="8"/>
      <path d="M900 1080 C860 900 960 820 900 700" stroke-width="12"/>
    </g>
    '''
    ground = f'''
    <path d="M0 990 C220 930 420 1020 700 960 C980 900 1120 990 1400 940 C1620 900 1760 980 {W} 930 L{W} {H} L0 {H} Z" fill="#101918"/>
    '''
    castle_fill = "#081413"
    castle = f'''
    <g fill="{castle_fill}">
      <path d="M900 1080 C1040 900 1180 980 1360 910 C1560 840 1720 960 {W} 900 L{W} {H} Z"/>
      <rect x="1168" y="560" width="132" height="460"/>
      <polygon points="1148,560 1234,360 1320,560"/>
      <rect x="1300" y="620" width="320" height="430"/>
      <polygon points="1276,620 1460,400 1644,620"/>
      <polygon points="1424,400 1460,250 1496,400"/>
      <rect x="1608" y="590" width="124" height="420"/>
      <polygon points="1588,590 1670,410 1752,590"/>
      <rect x="1732" y="700" width="96" height="300"/>
      <polygon points="1716,700 1780,560 1844,700"/>
    </g>
    '''
    windows = []
    for wx, wy in (
        (1204, 640),
        (1204, 760),
        (1204, 880),
        (1360, 700),
        (1488, 700),
        (1360, 820),
        (1488, 820),
        (1650, 680),
        (1650, 800),
        (1760, 780),
    ):
        windows.append(
            f'<rect x="{wx}" y="{wy}" width="26" height="36" rx="4" fill="{GOLD_SOFT}"/>'
        )
    door = f'''
    <path d="M1418 1040 V900 A42 42 0 0 1 1502 900 V1040 Z" fill="{COPPER}"/>
    <path d="M1444 1040 V930 A16 16 0 0 1 1476 930 V1040 Z" fill="{GOLD_SOFT}"/>
    '''
    gate = f'''
    <g stroke="#243E3A" stroke-linecap="square">
      <path d="M150 1040 V910 A150 120 0 0 1 450 910 V1040" fill="none" stroke-width="8"/>
      <line x1="190" y1="1040" x2="190" y2="940" stroke-width="6"/>
      <line x1="230" y1="1040" x2="230" y2="920" stroke-width="6"/>
      <line x1="270" y1="1040" x2="270" y2="910" stroke-width="6"/>
      <line x1="310" y1="1040" x2="310" y2="910" stroke-width="6"/>
      <line x1="350" y1="1040" x2="350" y2="920" stroke-width="6"/>
      <line x1="390" y1="1040" x2="390" y2="940" stroke-width="6"/>
    </g>
    <rect x="138" y="860" width="16" height="190" rx="2" fill="#2C4A45"/>
    <rect x="442" y="860" width="16" height="190" rx="2" fill="#2C4A45"/>
    <polygon points="134,860 146,828 158,860" fill="{GOLD}" opacity="0.8"/>
    <polygon points="438,860 450,828 462,860" fill="{GOLD}" opacity="0.8"/>
    '''
    sex_size = 228
    terror_size = 118
    sex_track = tracking_of(sex_size, -0.03)
    terror_track = tracking_of(terror_size, -0.02)
    block_w = max(
        face.width("SEXTA", sex_size, sex_track),
        face.width("DO TERROR", terror_size, terror_track),
    )
    # À direita da seta esquerda do carrossel.
    text_x = 330
    sexta, _ = face.draw("SEXTA", text_x, 500, sex_size, GOLD_SOFT, sex_track)
    terror, _ = face.draw(
        "DO TERROR",
        text_x,
        650,
        terror_size,
        CREAM,
        terror_track,
    )
    rule_y = 730
    ornament = (
        f'<line x1="{text_x}" y1="{rule_y}" x2="{text_x + block_w / 2 - 24:.1f}" y2="{rule_y}" '
        f'stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>'
        f'<line x1="{text_x + block_w / 2 + 24:.1f}" y1="{rule_y}" x2="{text_x + block_w:.1f}" y2="{rule_y}" '
        f'stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>'
        + star(text_x + block_w / 2, rule_y, 11, GOLD)
    )
    # Canto superior, ao lado do título: só o símbolo claro.
    logo = mark(88, 64, 188, on_dark=True)
    return svg_document(
        "SEXTA DO TERROR",
        sky
        + stars
        + moon
        + branches
        + ground
        + castle
        + "".join(windows)
        + door
        + gate
        + sexta
        + terror
        + ornament
        + logo,
    )


BANNERS = (
    ("promo-quarta", banner_quarta),
    ("promo-dez", banner_dez),
    ("promo-combo", banner_combo),
    ("promo-sexta", banner_sexta),
)


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[12:16] != b"IHDR":
        raise SystemExit(f"{path} não é um PNG")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    return width, height


def rasterize(name: str, svg: str) -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    svg_path = SVG_DIR / f"{name}.svg"
    html_path = BUILD / f"{name}.html"
    png_path = PNG_DIR / f"{name}.png"
    svg_path.write_text(svg, encoding="utf-8")
    html_path.write_text(
        f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
html, body {{ margin: 0; padding: 0; width: {W}px; height: {H}px; overflow: hidden; background: #000; }}
svg {{ display: block; width: {W}px; height: {H}px; }}
</style></head><body>
{svg}
</body></html>
""",
        encoding="utf-8",
    )
    shot = BUILD / f"{name}.png"
    if shot.exists():
        shot.unlink()
    profile = BUILD / f"profile-{name}"
    command = [
        "google-chrome",
        "--headless=new",
        "--no-sandbox",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--hide-scrollbars",
        "--no-first-run",
        "--disable-extensions",
        "--force-device-scale-factor=1",
        "--force-color-profile=srgb",
        "--default-background-color=00000000",
        "--virtual-time-budget=4000",
        f"--user-data-dir={profile}",
        f"--window-size={W},{H}",
        f"--screenshot={shot}",
        html_path.as_uri(),
    ]
    proc = subprocess.Popen(
        command,
        cwd=BUILD,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 20
    ready = False
    while time.time() < deadline:
        if shot.exists() and shot.stat().st_size > 1000:
            time.sleep(0.35)
            if shot.exists() and shot.stat().st_size > 1000:
                ready = True
                break
        if proc.poll() is not None and shot.exists():
            ready = True
            break
        time.sleep(0.15)
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    if not ready:
        raise SystemExit(f"Chrome não gerou {name}")
    width, height = png_size(shot)
    if (width, height) != (W, H):
        raise SystemExit(f"{name} saiu {width}×{height}, esperado {W}×{H}")
    png_path.write_bytes(shot.read_bytes())
    print(f"{png_path.relative_to(ROOT)} {width}×{height} {png_path.stat().st_size} bytes")


def main() -> None:
    if not FONT_PATH.exists():
        raise SystemExit(f"fonte ausente: {FONT_PATH}")
    face = Face(FONT_PATH)
    PNG_DIR.mkdir(parents=True, exist_ok=True)
    for name, build in BANNERS:
        rasterize(name, build(face))
    for old in PNG_DIR.glob("*.jpg"):
        old.unlink()
        print(f"removido {old.relative_to(ROOT)}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
