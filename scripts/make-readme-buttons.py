#!/usr/bin/env python3
"""Regenerates the README's download and guide buttons in .github/assets.

Usage: python3 scripts/make-readme-buttons.py   (needs fontTools: pip3 install fonttools)

They copy the website's store buttons (.store-button in docs-site/src/styles.css, icons from
docs-site/scripts/build.mjs). The text is drawn as outlines from the site's Geist font, so the
buttons look the same wherever GitHub shows them, whatever fonts the viewer has.
"""

import re
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "docs-site/public/fonts/Geist-VariableFont_wght.ttf"
OUT = ROOT / ".github/assets"



def site_icon(name: str) -> str:
    """The inside of an icon's <svg> in docs-site/scripts/build.mjs, drawn in a 24 x 24 box."""
    source = (ROOT / "docs-site/scripts/build.mjs").read_text()
    match = re.search(rf"^const {name} = '(<svg[^>]*>)(.*?)</svg>';$", source, re.M)
    attributes = re.findall(r'(fill|stroke|stroke-width|stroke-linecap|stroke-linejoin)="([^"]*)"', match.group(1))
    group = " ".join(f'{key}="{value}"' for key, value in attributes)
    return f"<g {group}>{match.group(2)}</g>"


# .store-button: 58 px tall, padding 9 24 9 18, 15 px corners, 12 px gap, 22 px icon.
# small: 12 px, weight 450, 70% opacity. strong: 18 px, weight 650, -0.015em. 2 px between, line-height 1.15.
HEIGHT, LEFT, RIGHT, RADIUS, GAP, ICON = 58, 18, 24, 15, 12, 22
SMALL, STRONG = (12, 450, 0.0), (18, 650, -0.015)

STYLES = {
    "dark": {"fill": "#1c1c1e", "text": "#ffffff", "stroke": "#ffffff", "stroke_opacity": 0.12},
    "light": {"fill": "#e4ecfb", "text": "#151515", "stroke": "#c9d5ec", "stroke_opacity": 1},
}

_fonts: dict[int, TTFont] = {}


def font(weight: int) -> TTFont:
    if weight not in _fonts:
        _fonts[weight] = instantiateVariableFont(TTFont(FONT), {"wght": weight})
    return _fonts[weight]


def text_path(text: str, size: float, weight: int, tracking: float, x: float, baseline: float) -> tuple[str, float]:
    """The outlines of `text` with its left end at x, and its width."""
    f = font(weight)
    glyphs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f["hmtx"]
    scale = size / f["head"].unitsPerEm
    pen = SVGPathPen(glyphs)
    cursor = x
    for character in text:
        name = cmap[ord(character)]
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, cursor, baseline)))
        cursor += hmtx[name][0] * scale + tracking * size
    return pen.getCommands(), cursor - x - tracking * size


def width(text: str, size: float, weight: int, tracking: float) -> float:
    return text_path(text, size, weight, tracking, 0, 0)[1]


def baselines() -> tuple[float, float]:
    """Each line's baseline, with both lines centered in the button as CSS lays them out."""
    def line(size: float, weight: int) -> tuple[float, float]:
        f = font(weight)
        hhea, upm = f["hhea"], f["head"].unitsPerEm
        ascent, descent = hhea.ascent / upm * size, -hhea.descent / upm * size
        box = size * 1.15
        return box, (box - ascent - descent) / 2 + ascent

    small_box, small_base = line(SMALL[0], SMALL[1])
    strong_box, strong_base = line(STRONG[0], STRONG[1])
    top = (HEIGHT - (small_box + 2 + strong_box)) / 2
    return top + small_base, top + small_box + 2 + strong_base


def button(name: str, style: str, icon: str, small: str, strong: str, label: str) -> None:
    s = STYLES[style]
    text_x = LEFT + ICON + GAP
    total = round(text_x + max(width(small, *SMALL), width(strong, *STRONG)) + RIGHT)
    small_base, strong_base = baselines()
    small_d, _ = text_path(small, *SMALL, text_x, small_base)
    strong_d, _ = text_path(strong, *STRONG, text_x, strong_base)
    icon_y = (HEIGHT - ICON) / 2
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{total}" height="{HEIGHT}" viewBox="0 0 {total} {HEIGHT}" role="img" aria-label="{label}">
  <title>{label}</title>
  <rect x="0.5" y="0.5" width="{total - 1}" height="{HEIGHT - 1}" rx="{RADIUS - 0.5}" fill="{s["fill"]}" stroke="{s["stroke"]}" stroke-opacity="{s["stroke_opacity"]}"/>
  <g color="{s["text"]}" fill="{s["text"]}">
    <g transform="translate({LEFT} {icon_y:g}) scale({ICON / 24:g})">{icon}</g>
    <path opacity="0.7" d="{small_d}"/>
    <path d="{strong_d}"/>
  </g>
</svg>
'''
    (OUT / f"{name}.svg").write_text(svg)
    print(OUT / f"{name}.svg", f"{total}x{HEIGHT}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    button("download", "dark", site_icon("appleLogo"), "Download · Free", "macOS", "Download Folio for macOS")
    button("guide", "light", site_icon("guideIcon"), "Read the guide", "Get started", "Read the Folio guide")
