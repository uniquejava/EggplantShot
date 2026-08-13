#!/usr/bin/env python3
"""Rasterize master AppIcon into macOS AppIcon.appiconset sizes.

macOS Dock/Finder expect a rounded-rect (“squircle”) silhouette with
transparent corners. Classic asset-catalog PNGs are not reliably masked by
the system the way iOS icons are — bake the continuous corner into the art.
Corner radius ≈ 22.37% of edge (Big Sur+ icon grid).
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

# Apple continuous-corner approximation used across Big Sur+ templates.
CORNER_RADIUS_FRAC = 0.2237

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


def apply_macos_icon_mask(im: Image.Image) -> Image.Image:
    """Clip to rounded rect; corners become transparent."""
    im = im.convert("RGBA")
    w, h = im.size
    if w != h:
        raise SystemExit(f"expected square image, got {w}x{h}")
    # Already masked? (transparent near corner)
    if im.getpixel((0, 0))[3] < 16 and im.getpixel((w - 1, 0))[3] < 16:
        return im
    radius = max(1, int(round(min(w, h) * CORNER_RADIUS_FRAC)))
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask=mask)
    return out


def main() -> None:
    src = next((p for p in CANDIDATES if p.exists()), None)
    if src is None:
        raise SystemExit(f"missing master icon, tried: {CANDIDATES}")

    DEST.mkdir(parents=True, exist_ok=True)
    for p in DEST.glob("icon_*.png"):
        p.unlink()

    im = Image.open(src)
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    im = apply_macos_icon_mask(im)

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
    print("master:", master)


if __name__ == "__main__":
    main()
