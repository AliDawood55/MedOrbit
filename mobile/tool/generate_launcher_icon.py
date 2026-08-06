"""Generates the MedOrbit launcher icon and every platform-specific size.

There is no existing MedOrbit logo/icon image anywhere in the repository —
the web app's brand mark is CSS-only: a Font Awesome heartbeat glyph
(`fa-heartbeat`) centered on a rounded square filled with
`linear-gradient(135deg, #2563EB 0%, #7C3AED 100%)`
(`frontend/src/css/main.css`, `.brand-icon`/`.loader-logo`). This script
reproduces that exact treatment as a flat PNG rather than inventing a new
brand, then resizes it into every Android mipmap and iOS AppIcon.appiconset
file Flutter's default project structure expects.

Run once from the `mobile/` directory:
    ../.venv/Scripts/python.exe tool/generate_launcher_icon.py

Requires Pillow (already available in the repo's `.venv`). Not part of the
app build — this is a one-off/reproducible source-asset generator, not
runtime code.
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Exact brand colors from frontend/src/css/main.css:101-106.
GRADIENT_START = (37, 99, 235)  # #2563EB
GRADIENT_END = (124, 58, 237)  # #7C3AED

MASTER_SIZE = 1024


def _build_gradient(size: int) -> Image.Image:
    """135deg linear gradient (top-left -> bottom-right), built at low
    resolution and upscaled with LANCZOS — gradients have no high-frequency
    detail, so this is both fast and artifact-free, unlike a pure-Python
    per-pixel loop at full resolution."""
    low_res = 64
    small = Image.new("RGB", (low_res, low_res))
    pixels = small.load()
    for y in range(low_res):
        for x in range(low_res):
            t = (x + y) / (2 * (low_res - 1))
            r = round(GRADIENT_START[0] + (GRADIENT_END[0] - GRADIENT_START[0]) * t)
            g = round(GRADIENT_START[1] + (GRADIENT_END[1] - GRADIENT_START[1]) * t)
            b = round(GRADIENT_START[2] + (GRADIENT_END[2] - GRADIENT_START[2]) * t)
            pixels[x, y] = (r, g, b)
    return small.resize((size, size), Image.LANCZOS)


def _draw_heartbeat(canvas: Image.Image) -> None:
    """A simplified EKG/heartbeat pulse line, matching the silhouette of
    Font Awesome's `fa-heartbeat` glyph closely enough to read clearly even
    at 20x20 — small launcher sizes don't show fine detail, so a bold,
    legible zigzag matters more than exact glyph fidelity."""
    size = canvas.size[0]
    draw = ImageDraw.Draw(canvas)

    # Local coordinate space, centered on the canvas.
    local_w, local_h = 620, 220
    offset_x = (size - local_w) / 2
    offset_y = (size - local_h) / 2 + local_h * 0.05

    local_points = [
        (0, 110),
        (130, 110),
        (170, 70),
        (210, 150),
        (250, 20),
        (295, 200),
        (335, 110),
        (620, 110),
    ]
    points = [(offset_x + x, offset_y + y) for x, y in local_points]

    stroke_width = round(size * 0.045)
    white = (255, 255, 255)
    draw.line(points, fill=white, width=stroke_width, joint="curve")

    # Round caps — ImageDraw.line has square ends, so cap each end with a
    # filled circle matching the stroke width (mirrors stroke-linecap:round).
    radius = stroke_width / 2
    for point in (points[0], points[-1]):
        x, y = point
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=white)


def build_master_icon() -> Image.Image:
    icon = _build_gradient(MASTER_SIZE)
    _draw_heartbeat(icon)
    return icon


def save_resized(master: Image.Image, size: int, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    resized = master.resize((size, size), Image.LANCZOS)
    # No alpha channel — flat, fully opaque square. Both platforms apply
    # their own corner/shape masking; a pre-rounded or transparent source
    # is explicitly discouraged by Apple's Human Interface Guidelines and
    # unnecessary for Android's adaptive-icon-free legacy mipmap format
    # already in use here (no mipmap-anydpi-v26 exists in this project).
    resized.convert("RGB").save(destination, format="PNG")


ANDROID_DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# (filename, pixel size) — every unique file referenced by
# ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json.
IOS_ICON_FILES = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]


def main() -> None:
    master = build_master_icon()

    source_path = ROOT / "assets" / "icon" / "app_icon_source.png"
    source_path.parent.mkdir(parents=True, exist_ok=True)
    master.convert("RGB").save(source_path, format="PNG")
    print(f"Saved master source: {source_path}")

    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density_dir, size in ANDROID_DENSITIES.items():
        destination = android_res / density_dir / "ic_launcher.png"
        save_resized(master, size, destination)
        print(f"Saved Android {density_dir} ({size}x{size}): {destination}")

    ios_appiconset = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in IOS_ICON_FILES:
        destination = ios_appiconset / filename
        save_resized(master, size, destination)
        print(f"Saved iOS {filename} ({size}x{size}): {destination}")

    print("Done.")


if __name__ == "__main__":
    main()
