#!/usr/bin/env python3
"""Rasterize master AppIcon into macOS AppIcon.appiconset sizes.

macOS wants a rounded-rect (“squircle”) silhouette with transparent corners and —
unlike iOS, where the OS masks and insets for you — a transparent **optical margin**
baked into the art. Filling the artboard edge-to-edge makes the Dock tile render
~1.24x its system peers. Apple’s template ≈ 100px pad / 824px grid on 1024.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "EggplantShot/Assets.xcassets/AppIcon.appiconset"
CANDIDATES = [
    DEST / "AppIcon-1024-master.png",
    Path.home()
    / ".cursor/projects/Users-cyper-code-eggplant-projects-EggplantShot/assets/EggplantShot-AppIcon-1024-raw.png",
]

CORNER_RADIUS_FRAC = 0.2237
ICON_GRID_PX = 824

SIZES: list[tuple[str, int, str, str]] = [
    ("icon_16.png", 16, "16x16", "1x"),
    ("icon_16_2x.png", 32, "16x16", "2x"),
    ("icon_32.png", 32, "32x32", "1x"),
    ("icon_32_2x.png", 64, "32x32", "2x"),
    ("icon_128.png", 128, "128x128", "1x"),
    ("icon_128_2x.png", 256, "128x128", "2x"),
    ("icon_256.png", 256, "256x256", "1x"),
    ("icon_256_2x.png", 512, "256x256", "2x"),
    ("icon_512.png", 512, "512x512", "1x"),
    ("icon_512_2x.png", 1024, "512x512", "2x"),
]


def _center_top_pad_frac(im: Image.Image) -> float:
    w, h = im.size
    cx = w // 2
    for y in range(h):
        if im.getpixel((cx, y))[3] > 16:
            return y / h
    return 1.0


def bake_macos_app_icon(im: Image.Image) -> Image.Image:
    """Inset to Apple's icon grid, then clip to squircle (transparent outside)."""
    im = im.convert("RGBA")
    w, h = im.size
    if w != h:
        raise SystemExit(f"expected square image, got {w}x{h}")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)

    pad_frac = _center_top_pad_frac(im)
    if 0.08 <= pad_frac <= 0.12 and im.getpixel((0, 0))[3] < 16:
        return im

    grid = ICON_GRID_PX
    pad = (1024 - grid) // 2
    inner = im.resize((grid, grid), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    canvas.paste(inner, (pad, pad), inner)

    radius = max(1, int(round(grid * CORNER_RADIUS_FRAC)))
    mask = Image.new("L", (1024, 1024), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (pad, pad, pad + grid - 1, pad + grid - 1), radius=radius, fill=255
    )
    out = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    out.paste(canvas, (0, 0), mask=mask)
    return out


def main() -> None:
    # Prefer raw full-bleed over an existing master so re-runs re-bake correctly.
    ordered = [p for p in CANDIDATES[1:] if p.exists()] + (
        [CANDIDATES[0]] if CANDIDATES[0].exists() else []
    )
    src = ordered[0] if ordered else None
    if src is None:
        raise SystemExit(f"missing master icon, tried: {CANDIDATES}")

    DEST.mkdir(parents=True, exist_ok=True)
    for p in DEST.glob("icon_*.png"):
        p.unlink()

    im = Image.open(src)
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    im = bake_macos_app_icon(im)

    master = DEST / "AppIcon-1024-master.png"
    im.save(master, format="PNG")

    images = []
    for name, px, size, scale in SIZES:
        out = DEST / name
        im.resize((px, px), Image.Resampling.LANCZOS).save(out, format="PNG")
        images.append(
            {"filename": name, "idiom": "mac", "scale": scale, "size": size}
        )
        print(f"{px:4d}px -> {name}")

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (DEST / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8"
    )
    print("updated Contents.json")
    print("source:", src)
    print("master:", master)


if __name__ == "__main__":
    main()
