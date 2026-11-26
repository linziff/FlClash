#!/usr/bin/env python3
"""Generate QNDXX-branded tray icons while preserving FlClash's four state IDs.

status_1: idle/stopped (slate)
status_2: running without TUN (green)
status_3: TUN enabled (blue)
status_4: safe mode (amber)
"""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
COLORS = {
    1: (100, 116, 139, 255),
    2: (34, 197, 94, 255),
    3: (14, 165, 233, 255),
    4: (245, 158, 11, 255),
}

def make_app_icon(size: int = 1024) -> Image.Image:
    """Load the approved QNDXX logo asset and scale it without distortion."""
    source_path = ROOT / "assets/images/logo.png"
    if not source_path.is_file():
        raise FileNotFoundError(f"Required QNDXX logo is missing: {source_path}")
    with Image.open(source_path) as source:
        logo = source.convert("RGBA")
    logo.thumbnail((size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(
        logo, ((size - logo.width) // 2, (size - logo.height) // 2)
    )
    return canvas

def make_icon(status: int, size: int) -> Image.Image:
    """Render the exact QNDXX app mark, tinted for the current connection state."""
    mark = make_app_icon(size)
    alpha = mark.getchannel("A")
    # Keep the same transparent Q silhouette on Windows and macOS. Only its
    # foreground color changes, matching FlClash's connection-state semantics.
    image = Image.new("RGBA", (size, size), COLORS[status])
    image.putalpha(alpha)
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
