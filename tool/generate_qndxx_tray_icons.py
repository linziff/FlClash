#!/usr/bin/env python3
"""Generate rounded, transparent QNDXX icons with the original four states."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
COLORS = {
    1: (100, 116, 139, 255),
    2: (34, 197, 94, 255),
    3: (14, 165, 233, 255),
    4: (245, 158, 11, 255),
}


def make_app_icon(size: int = 1024) -> Image.Image:
    """Use the supplied logo edge-to-edge, preserving its transparent corners."""
    source_path = ROOT / "assets/images/logo.png"
    if not source_path.is_file():
        raise FileNotFoundError(f"Required QNDXX logo is missing: {source_path}")
    with Image.open(source_path) as source:
        logo = source.convert("RGBA")

    # Remove only transparent outer padding. Do not trim opaque logo details.
    alpha = logo.getchannel("A")
    bounds = alpha.getbbox()
    if bounds:
        logo = logo.crop(bounds)

    # Fill the icon canvas instead of thumbnailing into a smaller padded square.
    side = min(logo.width, logo.height)
    left = (logo.width - side) // 2
    top = (logo.height - side) // 2
    logo = logo.crop((left, top, left + side, top + side))
    logo = logo.resize((size, size), Image.Resampling.LANCZOS)

    # Rounded transparent corners match the QNDXX app mark on both platforms.
    corner = Image.new("L", (size, size), 0)
    ImageDraw.Draw(corner).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=round(size * 0.22), fill=255
    )
    logo.putalpha(Image.composite(logo.getchannel("A"), Image.new("L", (size, size), 0), corner))
    return logo


def make_adaptive_foreground(size: int = 1024) -> Image.Image:
    """Inset the mark into Android's adaptive-icon safe zone.

    Android 12 reuses the adaptive foreground for the system splash screen.
    A full-bleed foreground is clipped/oversized there, so keep the artwork
    inside the central 66% while leaving the surrounding pixels transparent.
    """
    mark = make_app_icon(round(size * 0.66))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - mark.width) // 2
    canvas.alpha_composite(mark, (offset, offset))
    return canvas


def make_icon(status: int, size: int) -> Image.Image:
    """Preserve the original QNDXX logo and show FlClash state as a small badge.

    The old implementation replaced every visible logo pixel with a flat
    status color. That erased the blue background and the logo artwork, making
    the tray icon look like a featureless square at small Windows sizes.
    """
    image = make_app_icon(size)
    draw = ImageDraw.Draw(image)

    # Keep the QNDXX brand artwork untouched; indicate connection state with
    # a compact lower-right dot instead of recoloring the entire logo.
    diameter = max(5, round(size * 0.30))
    margin = max(0, round(size * 0.035))
    right = size - 1 - margin
    bottom = size - 1 - margin
    left = right - diameter + 1
    top = bottom - diameter + 1

    # White keyline keeps the state marker legible on both blue and light logos.
    outline = max(1, round(size * 0.055))
    draw.ellipse(
        (left - outline, top - outline, right, bottom),
        fill=(255, 255, 255, 255),
    )
    draw.ellipse(
        (left, top, right - outline, bottom - outline),
        fill=COLORS[status],
    )
    return image

def save_png(path: Path, status: int, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    make_icon(status, size).save(path, format="PNG", optimize=True)


def main():
    (ROOT / "assets/images/qndxx_app_icon.png").parent.mkdir(parents=True, exist_ok=True)
    make_app_icon().save(ROOT / "assets/images/qndxx_app_icon.png", format="PNG", optimize=True)
    make_adaptive_foreground().save(
        ROOT / "assets/images/qndxx_adaptive_foreground.png",
        format="PNG",
        optimize=True,
    )

    windows = ROOT / "assets/images/tray/windows"
    windows.mkdir(parents=True, exist_ok=True)
    for status in range(1, 5):
        make_icon(status, 256).save(
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

    print("Generated rounded transparent QNDXX icons for all four connection states.")


if __name__ == "__main__":
    main()
