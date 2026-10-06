"""Draws the launcher icon: one speaker sending waves to two more. Needs Pillow.

Run from apps/multi_speaker: python3 tool/gen_icon.py
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Rounded tile, purple to magenta diagonal gradient.
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    for_x = y / S
    gd.line([(0, y), (S, y)], fill=(int(74 + 120 * for_x), int(20 + 10 * for_x), int(140 - 10 * for_x), 255))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=220, fill=255)
img.paste(grad, (0, 0), mask)


def speaker(cx, cy, w, h, layer):
    """A speaker box with a big and a small cone, plus a soft shadow."""
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [cx - w / 2 + 12, cy - h / 2 + 22, cx + w / 2 + 12, cy + h / 2 + 22], radius=w * 0.18, fill=(0, 0, 0, 110))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], radius=w * 0.18, fill=(250, 250, 255))
    r = w * 0.32
    by = cy + h * 0.16
    d.ellipse([cx - r, by - r, cx + r, by + r], fill=(40, 30, 60))
    d.ellipse([cx - r * 0.55, by - r * 0.55, cx + r * 0.55, by + r * 0.55], fill=(255, 64, 129))
    d.ellipse([cx - r * 0.18, by - r * 0.18, cx + r * 0.18, by + r * 0.18], fill=(40, 30, 60))
    r2 = w * 0.13
    ty = cy - h * 0.28
    d.ellipse([cx - r2, ty - r2, cx + r2, ty + r2], fill=(40, 30, 60))


layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# Sound waves from the middle speaker.
d = ImageDraw.Draw(layer)
for i, rr in enumerate([190, 260, 330]):
    a = 230 - i * 60
    for side, (start, end) in {"l": (150, 210), "r": (-30, 30)}.items():
        d.arc([512 - rr, 470 - rr, 512 + rr, 470 + rr], start, end, fill=(255, 255, 255, a), width=26)
speaker(512, 470, 250, 360, layer)
speaker(215, 720, 170, 240, layer)
speaker(809, 720, 170, 240, layer)
img.alpha_composite(layer)

# Clip everything to the tile.
out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
out.paste(img, (0, 0), mask)

for name, px_ in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    out.resize((px_, px_), Image.LANCZOS).save(
        f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
out.resize((512, 512), Image.LANCZOS).save("tool/icon_512.png")
