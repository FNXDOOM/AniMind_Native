"""
make_ico.py — generates animind.ico using only Pillow (no cairo needed).
Fast version: uses numpy arrays for gradient fill instead of pixel-by-pixel.

Usage:
    pip install Pillow numpy
    cd qt_host/resources
    python make_ico.py
"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ICO_PATH   = os.path.join(SCRIPT_DIR, "icons", "animind.ico")
PNG_PATH   = os.path.join(SCRIPT_DIR, "icons", "animind_512.png")
os.makedirs(os.path.join(SCRIPT_DIR, "icons"), exist_ok=True)


def make_gradient(size, c_start, c_end, diagonal=True):
    """Fast RGBA gradient image using numpy."""
    s = size
    xs = np.linspace(0, 1, s, dtype=np.float32)
    ys = np.linspace(0, 1, s, dtype=np.float32)
    xg, yg = np.meshgrid(xs, ys)
    t = (xg + yg) / 2 if diagonal else yg   # diagonal or vertical
    r = (c_start[0] + (c_end[0] - c_start[0]) * t).astype(np.uint8)
    g = (c_start[1] + (c_end[1] - c_start[1]) * t).astype(np.uint8)
    b = (c_start[2] + (c_end[2] - c_start[2]) * t).astype(np.uint8)
    a = np.full((s, s), 255, dtype=np.uint8)
    return Image.fromarray(np.stack([r, g, b, a], axis=2), mode="RGBA")


def shrink_triangle(pts, amount):
    cx = sum(p[0] for p in pts) / 3
    cy = sum(p[1] for p in pts) / 3
    result = []
    for x, y in pts:
        dx, dy = cx - x, cy - y
        dist = math.sqrt(dx * dx + dy * dy)
        if dist == 0:
            result.append((x, y))
        else:
            f = amount / dist
            result.append((int(x + dx * f), int(y + dy * f)))
    return result


def make_icon(size):
    s = size
    sc = s / 1024.0
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ── Rounded square background ─────────────────────────────────────────
    radius = int(s * 0.22)
    draw.rounded_rectangle([0, 0, s-1, s-1], radius=radius, fill=(16, 14, 28, 255))

    # ── Gradient layers ───────────────────────────────────────────────────
    # Purple→pink for play outline
    grad = make_gradient(s, (192, 40, 255), (240, 90, 150), diagonal=True)
    # Indigo→blue for bolt
    bolt_grad = make_gradient(s, (120, 50, 230), (70, 60, 220), diagonal=False)

    # ── Play triangle outline ─────────────────────────────────────────────
    tri = [
        (int(300 * sc), int(210 * sc)),
        (int(300 * sc), int(814 * sc)),
        (int(785 * sc), int(512 * sc)),
    ]
    stroke_w = max(3, int(68 * sc))

    outer_mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(outer_mask).polygon(tri, fill=255)

    inner_mask = Image.new("L", (s, s), 0)
    inner_tri = shrink_triangle(tri, stroke_w)
    ImageDraw.Draw(inner_mask).polygon(inner_tri, fill=255)

    outline_mask = ImageChops.subtract(outer_mask, inner_mask)

    # Apply play gradient through outline mask
    grad_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    grad_layer.paste(grad, mask=outline_mask)

    # Soft glow behind the outline
    if size >= 64:
        glow = grad_layer.copy()
        blur_r = max(2, int(s * 0.018))
        glow = glow.filter(ImageFilter.GaussianBlur(radius=blur_r))
        img = Image.alpha_composite(img, glow)

    img = Image.alpha_composite(img, grad_layer)

    # ── Lightning bolt ────────────────────────────────────────────────────
    bolt_1024 = [
        (462, 210),
        (365, 505),
        (448, 505),
        (325, 814),
        (535, 540),
        (448, 540),
    ]
    bolt_pts = [(int(x * sc), int(y * sc)) for x, y in bolt_1024]

    bolt_mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(bolt_mask).polygon(bolt_pts, fill=255)

    bolt_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bolt_layer.paste(bolt_grad, mask=bolt_mask)

    # Bolt glow
    if size >= 64:
        bglow = bolt_layer.copy().filter(ImageFilter.GaussianBlur(radius=max(2, int(s * 0.012))))
        img = Image.alpha_composite(img, bglow)

    img = Image.alpha_composite(img, bolt_layer)

    # ── Subtle inner border (glass edge) ─────────────────────────────────
    border_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border_layer)
    bd.rounded_rectangle([1, 1, s-2, s-2], radius=radius,
                         outline=(180, 100, 255, 35), width=max(1, int(2 * sc)))
    img = Image.alpha_composite(img, border_layer)

    return img


# ── Generate sizes ────────────────────────────────────────────────────────
print("Generating icon sizes: ", end="", flush=True)
sizes = [16, 24, 32, 48, 64, 128, 256]
images = []
for sz in sizes:
    print(f"{sz} ", end="", flush=True)
    images.append(make_icon(sz))
print()

# Save .ico
images[0].save(
    ICO_PATH, format="ICO",
    sizes=[(s, s) for s in sizes],
    append_images=images[1:],
)
print(f"Saved ICO: {ICO_PATH}")

# Save 512px PNG preview
preview = make_icon(512)
preview.save(PNG_PATH)
print(f"Saved PNG preview: {PNG_PATH}")
print("Done.")
