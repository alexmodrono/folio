#!/usr/bin/env python3
"""Regenerates the layer artwork in Folio/Resources/AppIcon.icon/Assets.

Usage: python3 scripts/make-icon.py

The icon is an Icon Composer document. icon.json (edit it in Icon Composer) stacks
three groups over the frame, which is the document's fill:

- Face: painted highlights (rim and caustic crescent), the eyes, and the face.
- Glass disc: a Liquid Glass circle over a sheen and the lens content, the panel
  magnified as the design draws it (1.12x, 1.32x at the rim).
- Panel: the painted panel.

Headless Chrome renders everything that uses SVG filters or embedded images. Icon
Composer trims the transparent edges of PNG layers and centers what's left, so
every layer that doesn't fill the canvas is wrapped in a full-canvas SVG to keep
its position.

Coordinates come from the design's 1024 master: the squircle body spans 100...924,
and Icon Composer's canvas is the full body, so everything is scaled by 1024/824.
"""
import base64
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Folio/Resources/AppIcon.icon/Assets"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

K = 1024 / 824
TRANSFORM = f"matrix({K:.6f} 0 0 {K:.6f} {-100 * K:.4f} {-100 * K:.4f})"

APPEARANCES = {
    "": dict(bg=["#18B3A3", "#5CCFB4", "#FF9A72", "#FFB84D"],
             a="#22C6D0", b="#0E9A82", c="#FF7E5F", d="#FFD45C", e="#C9F5DE",
             frame="#F8F8F9", crescent=0.95),
    "-dark": dict(bg=["#0B4A47", "#145A50", "#6B3828", "#7A5520"],
                  a="#15787E", b="#0A4B44", c="#A44C35", d="#B28628", e="#3E8C76",
                  frame="#303034", crescent=0.55),
}

# The glass disc sits in the lower-right corner; the face is 0.7 of its 200pt master.
GX = GY = 674
GR = 214
FACE_SCALE = 0.7
RIM_WIDTH = 3


def svg(body: str, defs: str = "") -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f"<defs>{defs}</defs><g transform=\"{TRANSFORM}\">{body}</g></svg>\n"
    )


def scale_about(s: float) -> str:
    return f"matrix({s} 0 0 {s} {GX * (1 - s):.1f} {GY * (1 - s):.1f})"


def panel(p: dict) -> str:
    bg = p["bg"]
    defs = f"""<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bg[0]}"/><stop offset="0.48" stop-color="{bg[1]}"/><stop offset="0.8" stop-color="{bg[2]}"/><stop offset="1" stop-color="{bg[3]}"/></linearGradient>
<clipPath id="panel"><rect x="180" y="180" width="664" height="664" rx="104"/></clipPath>
<filter id="paint" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency="0.004 0.011" numOctaves="2" seed="7" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale="140" xChannelSelector="R" yChannelSelector="G" result="warped"/><feGaussianBlur in="warped" stdDeviation="34"/></filter>"""
    body = f"""<g clip-path="url(#panel)"><rect x="180" y="180" width="664" height="664" fill="url(#bg)"/><g filter="url(#paint)">
<ellipse cx="300" cy="290" rx="230" ry="250" fill="{p['b']}"/><ellipse cx="720" cy="250" rx="260" ry="200" fill="{p['a']}"/>
<ellipse cx="650" cy="460" rx="230" ry="70" fill="{p['e']}" transform="rotate(-18 650 460)"/><ellipse cx="360" cy="610" rx="290" ry="160" fill="{p['c']}"/>
<ellipse cx="320" cy="820" rx="260" ry="110" fill="{p['d']}"/></g></g>"""
    return svg(body, defs)


def lens(p: dict, panel_png: bytes) -> str:
    """The scene under the disc, magnified; the rim band's inner edge is feathered."""
    data = base64.b64encode(panel_png).decode()
    # The panel PNG is already on the icon canvas, so undo the design transform for it.
    scene = (f'<g id="scene"><rect x="100" y="100" width="824" height="824" fill="{p["frame"]}"/>'
             f'<image x="100" y="100" width="824" height="824" href="data:image/png;base64,{data}"/></g>')
    defs = f"""{scene}<clipPath id="disc"><circle cx="{GX}" cy="{GY}" r="{GR}"/></clipPath>
<filter id="feather" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>
<mask id="band" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#fff"/><circle cx="{GX}" cy="{GY}" r="{GR - 30}" fill="#000" filter="url(#feather)"/></mask>"""
    body = f"""<g clip-path="url(#disc)"><use href="#scene" transform="{scale_about(1.12)}"/>
<g mask="url(#band)"><use href="#scene" transform="{scale_about(1.32)}"/></g></g>"""
    return svg(body, defs)


def highlights(p: dict) -> str:
    """The design's rim highlight and the caustic crescent along the lower right."""
    defs = f"""<linearGradient id="rim" x1="0.1" y1="0.05" x2="0.9" y2="0.95"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset="0.35" stop-color="#fff" stop-opacity="0.25"/><stop offset="0.65" stop-color="#fff" stop-opacity="0.2"/><stop offset="1" stop-color="#fff" stop-opacity="0.95"/></linearGradient>
<linearGradient id="crescent" x1="0" y1="0" x2="1" y2="1"><stop offset="0.35" stop-color="#fff" stop-opacity="0"/><stop offset="0.75" stop-color="#fff" stop-opacity="0.95"/><stop offset="1" stop-color="#fff" stop-opacity="1"/></linearGradient>
<filter id="feather" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="10"/></filter>
<mask id="cut" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><circle cx="{GX}" cy="{GY}" r="{GR - 8}" fill="#fff"/><circle cx="{GX - 30}" cy="{GY - 30}" r="{GR - 8}" fill="#000" filter="url(#feather)"/></mask>
<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.5"/></filter>"""
    body = f"""<g mask="url(#cut)"><circle cx="{GX}" cy="{GY}" r="{GR}" fill="url(#crescent)" filter="url(#soft)" opacity="{p['crescent']}"/></g>
<circle cx="{GX}" cy="{GY}" r="{GR - RIM_WIDTH / 2}" fill="none" stroke="url(#rim)" stroke-width="{RIM_WIDTH}"/>"""
    return svg(body, defs)


def sheen() -> str:
    defs = ('<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.45"/>'
            '<stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>')
    return svg(f'<ellipse cx="{GX - GR * 0.12:.1f}" cy="{GY - GR * 0.62:.1f}" rx="{GR * 0.7:.1f}" ry="{GR * 0.32:.1f}" fill="url(#sheen)"/>', defs)


def render(source: str, tmp: pathlib.Path, name: str) -> bytes:
    """Renders an SVG to a 1024 PNG with headless Chrome."""
    src = tmp / (name + ".svg")
    out = tmp / (name + ".png")
    src.write_text(source)
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--default-background-color=00000000",
        "--window-size=1024,1024", f"--screenshot={out}", src.as_uri(),
    ], check=True, stderr=subprocess.DEVNULL)
    return out.read_bytes()


def wrapped(png: bytes) -> str:
    """A full-canvas SVG around a PNG, so Icon Composer keeps the layer in place."""
    data = base64.b64encode(png).decode()
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<image width="1024" height="1024" href="data:image/png;base64,{data}"/></svg>\n')


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    face_at = f"translate({GX} {GY}) scale({FACE_SCALE})"
    (ASSETS / "disc.svg").write_text(svg(f'<circle cx="{GX}" cy="{GY}" r="{GR}" fill="#FFFFFF"/>'))
    (ASSETS / "face.svg").write_text(svg(
        f'<g transform="{face_at}"><circle r="200" fill="url(#face)"/></g>',
        '<radialGradient id="face" cx="0.4" cy="0.3" r="0.8"><stop offset="0" stop-color="#3A3D44"/>'
        '<stop offset="0.6" stop-color="#1C1E22"/><stop offset="1" stop-color="#0E0F12"/></radialGradient>',
    ))
    (ASSETS / "eyes.svg").write_text(svg(
        f'<g transform="{face_at}" fill="#FBF0DC"><rect x="-91" y="-56" width="38" height="112" rx="19"/>'
        '<rect x="53" y="-56" width="38" height="112" rx="19"/></g>'
    ))
    (ASSETS / "sheen.svg").write_text(sheen())
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for suffix, colors in APPEARANCES.items():
            panel_png = render(panel(colors), tmp, "panel" + suffix)
            (ASSETS / f"panel{suffix}.png").write_bytes(panel_png)
            (ASSETS / f"lens{suffix}.svg").write_text(wrapped(render(lens(colors, panel_png), tmp, "lens" + suffix)))
            (ASSETS / f"highlights{suffix}.svg").write_text(
                wrapped(render(highlights(colors), tmp, "highlights" + suffix)))
    print(f"Wrote layers to {ASSETS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
