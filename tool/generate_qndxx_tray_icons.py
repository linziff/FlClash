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


def _load_logo() -> Image.Image:
    source_path = ROOT / "assets/images/logo.png"
    if not source_path.is_file():
        raise FileNotFoundError(f"Required QNDXX logo is missing: {source_path}")
    with Image.open(source_path) as source:
        logo = source.convert("RGBA")

    # Preserve artwork proportions and remove only transparent outer padding.
    bounds = logo.getchannel("A").getbbox()
    if bounds:
        logo = logo.crop(bounds)
    side = min(logo.width, logo.height)
    left = (logo.width - side) // 2
    top = (logo.height - side) // 2
    return logo.crop((left, top, left + side, top + side))


def make_app_icon(size: int = 1024) -> Image.Image:
    """Return a clean square master; macOS applies its own Dock corner mask."""
    return _load_logo().resize((size, size), Image.Resampling.LANCZOS)


def make_rounded_icon(size: int, radius_ratio: float = 0.22) -> Image.Image:
    """Render rounded corners with a 4x supersampled alpha mask."""
    scale = 4
    large_size = size * scale
    image = _load_logo().resize((large_size, large_size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (large_size, large_size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, large_size - 1, large_size - 1),
        radius=round(large_size * radius_ratio),
        fill=255,
    )
    image.putalpha(Image.composite(
        image.getchannel("A"),
        Image.new("L", (large_size, large_size), 0),
        mask,
    ))
    return image.resize((size, size), Image.Resampling.LANCZOS)

def make_adaptive_foreground(size: int = 1024) -> Image.Image:
    """Use the exact startup-animation artwork for Android launcher/splash.

    Keep the original logo at full canvas size so the launcher icon and the
    Flutter animated first screen use the same artwork and visual scale.
    Android applies its own adaptive-icon mask at display time.
    """
    return make_app_icon(size)


def make_icon(status: int, size: int) -> Image.Image:
    """Preserve the original QNDXX logo and show FlClash state as a small badge.

    The old implementation replaced every visible logo pixel with a flat
    status color. That erased the blue background and the logo artwork, making
    the tray icon look like a featureless square at small Windows sizes.
    """
    image = make_rounded_icon(size)
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

    # Windows has no automatic Dock-style mask; generate its rounded ICO
    # separately while keeping the shared app-icon master square for macOS.
    windows_app_icon = ROOT / "windows/runner/resources/app_icon.ico"
    windows_app_icon.parent.mkdir(parents=True, exist_ok=True)
    make_rounded_icon(256).save(
        windows_app_icon,
        format="ICO",
        sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
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
