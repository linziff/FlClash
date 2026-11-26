#!/usr/bin/env python3
"""Generate QNDXX-branded tray icons while preserving FlClash's four state IDs.

status_1: idle/stopped (slate)
status_2: running without TUN (green)
status_3: TUN enabled (blue)
status_4: safe mode (amber)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
COLORS = {
    1: (100, 116, 139, 255),
    2: (34, 197, 94, 255),
    3: (14, 165, 233, 255),
    4: (245, 158, 11, 255),
}

def make_app_icon(size: int = 1024) -> Image.Image:
    """Render the supplied high-resolution QNDXX brand mark into the app icon."""
    source_path = ROOT / "assets/images/QNDXXLG.png"
    if not source_path.is_file():
        raise FileNotFoundError(f"QNDXX logo was not downloaded: {source_path}")
    with Image.open(source_path) as source:
        logo = source.convert("RGBA")
    # The currently supplied brand asset is 64x64. Upscale it with a
    # high-quality reconstruction filter so packaging can proceed, while
    # retaining the source artwork. A genuinely crisp result still requires
    # replacing this asset with a larger original.
    if min(logo.size) < size:
        logo = logo.resize((size, size), Image.Resampling.LANCZOS)
        logo = logo.filter(ImageFilter.UnsharpMask(radius=1.2, percent=115, threshold=3))

    # Keep the app mark on a genuinely transparent canvas. The former
    # blue-gradient rounded square was baked into the Windows taskbar icon.
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Preserve the complete logo and its alpha channel without adding a
    # background. The native launcher generators consume this same PNG.
    logo = ImageOps.contain(
        logo, (int(size * 0.92), int(size * 0.92)),
        method=Image.Resampling.LANCZOS,
    )
    image.alpha_composite(
        logo, ((size - logo.width) // 2, (size - logo.height) // 2)
    )
    return image

def make_icon(status: int, size: int) -> Image.Image:
    color = COLORS[status]
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    inset = max(1, size // 24)
    draw.ellipse((inset, inset, size - inset - 1, size - inset - 1), fill=color)

    # Keep the app mark legible at 16px tray sizes.
    try:
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        if not Path(font_path).exists():
            font_path = "C:/Windows/Fonts/arialbd.ttf"
        font = ImageFont.truetype(font_path, max(8, int(size * 0.42)))
    except OSError:
        font = ImageFont.load_default()
    label = "QX"
    box = draw.textbbox((0, 0), label, font=font, stroke_width=0)
    x = (size - (box[2] - box[0])) / 2 - box[0]
    y = (size - (box[3] - box[1])) / 2 - box[1]
    draw.text((x, y), label, font=font, fill=(255, 255, 255, 255))
    return image

def save_png(path: Path, status: int, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    make_icon(status, size).save(path, format="PNG", optimize=True)

def main():
    (ROOT / "assets/images/qndxx_app_icon.png").parent.mkdir(parents=True, exist_ok=True)
    make_app_icon().save(ROOT / "assets/images/qndxx_app_icon.png", format="PNG", optimize=True)
    # Windows notification-area icons retain the original four-state mapping.
    windows = ROOT / "assets/images/tray/windows"
    windows.mkdir(parents=True, exist_ok=True)
    for status in range(1, 5):
        icon = make_icon(status, 256)
        icon.save(
            windows / f"status_{status}.ico",
            format="ICO",
            sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )

    for platform in ("unix", "macos"):
        base = ROOT / "assets/images/tray" / platform
        for status in range(1, 5):
            save_png(base / f"status_{status}.png", status, 72)
            for scale in (2, 3, 4):
                save_png(base / f"{scale}.0x" / f"status_{status}.png", status, 72 * scale)

    print("Generated QNDXX tray icons for all four original connection states.")

if __name__ == "__main__":
    main()
