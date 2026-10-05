"""Draws the launcher icon (ladder, snake and die). Needs Pillow.

Run from apps/snakes_ladders: python3 tool/gen_icon.py
"""
import math
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Rounded green tile with a soft vertical gradient.
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=(int(67 - 30 * t), int(160 - 70 * t), int(71 - 30 * t), 255))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=220, fill=255)
img.paste(grad, (0, 0), mask)

# Checker hint in the background.
over = Image.new("RGBA", (S, S), (0, 0, 0, 0))
od = ImageDraw.Draw(over)
for r in range(4):
    for c in range(4):
        if (r + c) % 2 == 0:
            x0, y0 = 120 + c * 196, 120 + r * 196
            od.rounded_rectangle([x0, y0, x0 + 196, y0 + 196], radius=30, fill=(255, 255, 255, 34))
img = Image.alpha_composite(img, over)
d = ImageDraw.Draw(img)

# Ladder from bottom-left to top-right.
a, b = (250, 860), (720, 170)
dx, dy = b[0] - a[0], b[1] - a[1]
L = math.hypot(dx, dy)
px, py = -dy / L * 85, dx / L * 85
for k in range(1, 8):
    t = k / 8
    m = (a[0] + dx * t, a[1] + dy * t)
    d.line([(m[0] - px, m[1] - py), (m[0] + px, m[1] + py)], fill=(92, 52, 20), width=48)
    d.line([(m[0] - px, m[1] - py), (m[0] + px, m[1] + py)], fill=(214, 150, 80), width=30)
for s in (-1, 1):
    p0 = (a[0] + px * s, a[1] + py * s)
    p1 = (b[0] + px * s, b[1] + py * s)
    d.line([p0, p1], fill=(92, 52, 20), width=66)
    d.line([p0, p1], fill=(176, 106, 46), width=46)

# Snake: wavy body from top-left down to bottom-right.
pts = []
n = 120
h, tl = (300, 250), (800, 800)
ddx, ddy = tl[0] - h[0], tl[1] - h[1]
LL = math.hypot(ddx, ddy)
nx, ny = -ddy / LL, ddx / LL
for i in range(n + 1):
    t = i / n
    w = math.sin(t * 2.4 * 2 * math.pi) * 110 * min(1, t * 5)
    pts.append((h[0] + ddx * t + nx * w, h[1] + ddy * t + ny * w))
for i in range(n):
    t = i / n
    wd = int(120 - 85 * t)
    d.line([pts[i], pts[i + 1]], fill=(25, 60, 20), width=wd + 18)
for i in range(n):
    t = i / n
    wd = int(120 - 85 * t)
    col = (255, 214, 0) if (i // 7) % 2 == 0 else (229, 57, 53)
    d.line([pts[i], pts[i + 1]], fill=col, width=wd)
    d.ellipse([pts[i][0] - wd / 2, pts[i][1] - wd / 2, pts[i][0] + wd / 2, pts[i][1] + wd / 2], fill=col)
# Head.
hx, hy = pts[0]
d.ellipse([hx - 105, hy - 90, hx + 105, hy + 90], fill=(25, 60, 20))
d.ellipse([hx - 92, hy - 78, hx + 92, hy + 78], fill=(229, 57, 53))
for ex in (-42, 42):
    d.ellipse([hx + ex - 28, hy - 50, hx + ex + 28, hy + 6], fill="white")
    d.ellipse([hx + ex - 12, hy - 34, hx + ex + 14, hy - 6], fill="black")
d.line([(hx, hy + 70), (hx, hy + 130)], fill=(213, 0, 0), width=14)
d.line([(hx, hy + 130), (hx - 24, hy + 160)], fill=(213, 0, 0), width=12)
d.line([(hx, hy + 130), (hx + 24, hy + 160)], fill=(213, 0, 0), width=12)

# Die in the bottom-left corner.
x0, y0, s = 120, 640, 250
d.rounded_rectangle([x0 + 10, y0 + 18, x0 + s + 10, y0 + s + 18], radius=50, fill=(0, 0, 0, 90))
d.rounded_rectangle([x0, y0, x0 + s, y0 + s], radius=50, fill="white", outline=(30, 30, 30), width=10)
for (u, v) in [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)]:
    cx, cy = x0 + u * s, y0 + v * s
    d.ellipse([cx - 24, cy - 24, cx + 24, cy + 24], fill=(33, 33, 33))

for name, px_ in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    img.resize((px_, px_), Image.LANCZOS).save(
        f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
img.resize((512, 512), Image.LANCZOS).save("tool/icon_512.png")
