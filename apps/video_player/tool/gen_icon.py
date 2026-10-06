"""Draws the launcher icon and the notification icon. Needs Pillow.

Run from the repo root: python3 tool/gen_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


# Diagonal orange-to-magenta gradient tile.
grad = Image.new("RGBA", (S, S))
px = grad.load()
c0, c1 = (255, 150, 40), (226, 32, 110)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = lerp(c0, c1, t) + (255,)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=230, fill=255)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)

# Film strip holes along the top and bottom edges.
for row_y in (150, S - 150 - 56):
    for i in range(6):
        x = 170 + i * 124
        d.rounded_rectangle([x, row_y, x + 64, row_y + 56], radius=14,
                            fill=(255, 255, 255, 70))

# Play triangle with a soft shadow, slightly right of centre.
cx, cy, r = S / 2 + 40, S / 2, 250
tri = [(cx - r * 0.75, cy - r), (cx - r * 0.75, cy + r), (cx + r * 1.0, cy)]
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).polygon([(x + 14, y + 22) for x, y in tri], fill=(90, 0, 40, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
img = Image.alpha_composite(img, shadow)
d = ImageDraw.Draw(img)
# Rounded triangle: draw polygon plus circles on corners.
d.polygon(tri, fill="white")
d.line(tri + [tri[0]], fill="white", width=60, joint="curve")
for (x, y) in tri:
    d.ellipse([x - 30, y - 30, x + 30, y + 30], fill="white")

for name, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    img.resize((size, size), Image.LANCZOS).save(
        f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
img.resize((512, 512), Image.LANCZOS).save("tool/icon_512.png")

# Notification icon: white play symbol on transparent, as Android requires.
n = Image.new("RGBA", (S, S), (0, 0, 0, 0))
nd = ImageDraw.Draw(n)
cx, cy, r = S / 2 + 60, S / 2, 360
t2 = [(cx - r * 0.75, cy - r), (cx - r * 0.75, cy + r), (cx + r * 1.0, cy)]
nd.polygon(t2, fill="white")
nd.line(t2 + [t2[0]], fill="white", width=90, joint="curve")
for (x, y) in t2:
    nd.ellipse([x - 45, y - 45, x + 45, y + 45], fill="white")
for name, size in {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}.items():
    folder = f"android/app/src/main/res/drawable-{name}"
    os.makedirs(folder, exist_ok=True)
    n.resize((size, size), Image.LANCZOS).save(f"{folder}/ic_stat_play.png")
