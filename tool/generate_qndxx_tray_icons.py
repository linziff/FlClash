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
    """Draw a crisp, transparent QNDXX monogram for adaptive and desktop icons."""
    # Supersampling keeps the circular mark smooth at launcher and taskbar sizes.
    scale = 3
    canvas_size = size * scale
    mask = Image.new("L", (canvas_size, canvas_size), 0)
    draw = ImageDraw.Draw(mask)

    # A clean Q-shaped ring with a rounded diagonal tail. The mark sits inside
    # Android's adaptive-icon safe area and remains legible at small sizes.
    outer = (int(canvas_size * 0.17), int(canvas_size * 0.13),
             int(canvas_size * 0.81), int(canvas_size * 0.77))
    inner = (int(canvas_size * 0.285), int(canvas_size * 0.245),
             int(canvas_size * 0.695), int(canvas_size * 0.655))
    draw.ellipse(outer, fill=255)
    draw.ellipse(inner, fill=0)
    tail_width = int(canvas_size * 0.115)
    draw.line(
        (int(canvas_size * 0.625), int(canvas_size * 0.625),
         int(canvas_size * 0.835), int(canvas_size * 0.835)),
        fill=255, width=tail_width
    )
    tail_radius = tail_width // 2
    tail_end = (int(canvas_size * 0.835), int(canvas_size * 0.835))
    draw.ellipse(
        (tail_end[0] - tail_radius, tail_end[1] - tail_radius,
         tail_end[0] + tail_radius, tail_end[1] + tail_radius),
        fill=255
    )

    # Cool cyan-to-indigo gradient; no baked blue tile or opaque square.
    gradient = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    pixels = gradient.load()
    top = (43, 211, 224)
    bottom = (91, 82, 235)
    for y in range(canvas_size):
        for x in range(canvas_size):
            t = min(1.0, max(0.0, (0.58 * x + 0.42 * y) / (canvas_size - 1)))
            pixels[x, y] = tuple(
                round(top[i] * (1 - t) + bottom[i] * t) for i in range(3)
            ) + (255,)
    gradient.putalpha(mask)
    return gradient.resize((size, size), Image.Resampling.LANCZOS)

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
