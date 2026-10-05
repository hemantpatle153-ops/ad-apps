"""Generates the Android launcher icons for every app in apps/.

Each app gets an adaptive icon (gradient background + white glyph foreground,
also used as the Android 13 themed monochrome layer), legacy square and round
icons for older launchers, and a 512 px Play Store icon in apps/<app>/store/.

Run from the repo root:  python tool/generate_icons.py   (needs Pillow)
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
U = 20  # pixels per dp unit on the 108 x 108 master canvas
MASTER = 108 * U
WHITE = (255, 255, 255, 255)
CUT = (0, 0, 0, 0)
FONT = Path("C:/Windows/Fonts/segoeuib.ttf")
if not FONT.exists():
    FONT = Path("C:/Windows/Fonts/arialbd.ttf")

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def p(*xy):
    return [v * U for v in xy]


def cap_line(d, x1, y1, x2, y2, w, fill):
    d.line(p(x1, y1, x2, y2), fill=fill, width=int(w * U))
    r = w / 2
    for x, y in ((x1, y1), (x2, y2)):
        d.ellipse(p(x - r, y - r, x + r, y + r), fill=fill)


def polyline(d, pts, w, fill):
    for a, b in zip(pts, pts[1:]):
        cap_line(d, *a, *b, w, fill)


def glyph_qr(d, accent):
    lo, hi, arm, w = 33, 75, 10, 4.2
    for cx, cy, sx, sy in ((lo, lo, 1, 1), (hi, lo, -1, 1), (lo, hi, 1, -1), (hi, hi, -1, -1)):
        cap_line(d, cx, cy, cx + sx * arm, cy, w, WHITE)
        cap_line(d, cx, cy, cx, cy + sy * arm, w, WHITE)
    for x, y in ((40, 40), (56, 40), (40, 56)):
        d.rounded_rectangle(p(x, y, x + 12, y + 12), radius=2.5 * U, fill=WHITE)
        d.rounded_rectangle(p(x + 2.6, y + 2.6, x + 9.4, y + 9.4), radius=1.2 * U, fill=CUT)
        d.rounded_rectangle(p(x + 4.4, y + 4.4, x + 7.6, y + 7.6), radius=0.8 * U, fill=WHITE)
    for x, y in ((56, 56), (63, 56), (59.5, 60), (56, 63.5), (63, 63.5)):
        d.rounded_rectangle(p(x, y, x + 4.5, y + 4.5), radius=0.9 * U, fill=WHITE)


def glyph_sudoku(d, accent):
    lo, hi = 33, 75
    d.rounded_rectangle(p(lo, lo, hi, hi), radius=6 * U, fill=WHITE)
    d.rounded_rectangle(p(lo + 3.5, lo + 3.5, hi - 3.5, hi - 3.5), radius=3 * U, fill=CUT)
    step = (hi - lo) / 3
    for i in (1, 2):
        v = lo + step * i
        d.line(p(v, lo + 2, v, hi - 2), fill=WHITE, width=int(2.2 * U))
        d.line(p(lo + 2, v, hi - 2, v), fill=WHITE, width=int(2.2 * U))
    a, b = lo + step, lo + 2 * step
    d.rectangle(p(a, a, b, b), fill=WHITE)
    font = ImageFont.truetype(str(FONT), int(12 * U))
    d.text(p(54, 53.2), "9", font=font, fill=CUT, anchor="mm")


def glyph_doc(d, accent):
    l, t, r, b, fold = 38, 30, 70, 78, 10
    d.polygon(p(l, t, r - fold, t, r, t + fold, r, b, l, b), fill=WHITE)
    d.polygon(p(r - fold, t, r - fold, t + fold, r, t + fold), fill=CUT)
    d.polygon(p(r - fold + 1.6, t + 1.8, r - fold + 1.6, t + fold - 1.6, r - 1.8, t + fold - 1.6), fill=WHITE)
    for y, x2 in ((44, 62), (50, 62), (64, 62), (70, 54)):
        cap_line(d, 44, y, x2, y, 2.6, CUT)
    cap_line(d, 30, 57, 78, 57, 3.6, accent)


def glyph_wallet(d, accent):
    d.rounded_rectangle(p(38, 31, 68, 46), radius=3 * U, fill=WHITE)
    d.rounded_rectangle(p(41, 34, 65, 46), radius=2 * U, fill=CUT)
    d.rounded_rectangle(p(31, 40, 77, 76), radius=6 * U, fill=WHITE)
    d.rounded_rectangle(p(58, 51, 81, 65), radius=4 * U, fill=WHITE)
    d.rounded_rectangle(p(61, 54, 78, 62), radius=2.5 * U, fill=CUT)
    d.ellipse(p(65.5, 55.5, 70.5, 60.5), fill=WHITE)


def glyph_drop(d, accent):
    tip, cx, cy, r = 29, 54, 61, 17
    alpha = math.degrees(math.asin(r / (cy - tip)))
    pts = [(cx, tip)]
    for i in range(0, 241):
        th = math.radians(90 - alpha + (360 - 2 * (90 - alpha)) * i / 240)
        pts.append((cx + r * math.sin(th), cy - r * math.cos(th)))
    d.polygon([v * U for pt in pts for v in pt], fill=WHITE)
    polyline(d, [(46, 62), (51.5, 67.5), (62, 56.5)], 4, CUT)


APPS = {
    "qr_scanner": (glyph_qr, (61, 90, 254), (40, 53, 147)),
    "daily_sudoku": (glyph_sudoku, (149, 82, 230), (94, 53, 177)),
    "doc_scanner": (glyph_doc, (255, 112, 87), (214, 54, 64)),
    "expense_tracker": (glyph_wallet, (46, 196, 120), (17, 128, 86)),
    "water_habit": (glyph_drop, (41, 200, 246), (0, 120, 212)),
}
ACCENT = (255, 214, 102, 255)


def background(top, bottom):
    img = Image.new("RGBA", (MASTER, MASTER))
    d = ImageDraw.Draw(img)
    for i in range(MASTER):
        t = i / (MASTER - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        d.line([(0, i), (MASTER, i)], fill=c + (255,))
    return img


def foreground(glyph, accent):
    img = Image.new("RGBA", (MASTER, MASTER), CUT)
    glyph(ImageDraw.Draw(img), accent)
    return img


def rounded_mask(size, radius_frac):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_frac), fill=255)
    return m


def scaled(img, px):
    return img.resize((px, px), Image.LANCZOS)


def main():
    for app, (glyph, top, bottom) in APPS.items():
        res = ROOT / "apps" / app / "android/app/src/main/res"
        bg = background(top, bottom)
        fg = foreground(glyph, ACCENT)
        mono = foreground(glyph, WHITE)
        full = Image.alpha_composite(bg, fg)
        inset = 18 * U  # the visible 72 dp viewport of the 108 dp adaptive canvas
        visible = full.crop((inset, inset, MASTER - inset, MASTER - inset))

        for dens, k in DENSITIES.items():
            folder = res / f"mipmap-{dens}"
            folder.mkdir(exist_ok=True)
            layer = round(108 * k)
            scaled(bg, layer).convert("RGB").save(folder / "ic_launcher_background.png", optimize=True)
            scaled(fg, layer).save(folder / "ic_launcher_foreground.png", optimize=True)
            scaled(mono, layer).save(folder / "ic_launcher_monochrome.png", optimize=True)
            px = round(48 * k)
            icon = scaled(visible, px)
            sq = Image.new("RGBA", (px, px), CUT)
            sq.paste(icon, (0, 0), rounded_mask(px, 0.22))
            sq.save(folder / "ic_launcher.png", optimize=True)
            circ = Image.new("L", (px, px), 0)
            ImageDraw.Draw(circ).ellipse([0, 0, px - 1, px - 1], fill=255)
            rnd = Image.new("RGBA", (px, px), CUT)
            rnd.paste(icon, (0, 0), circ)
            rnd.save(folder / "ic_launcher_round.png", optimize=True)

        anydpi = res / "mipmap-anydpi-v26"
        anydpi.mkdir(exist_ok=True)
        xml = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
            "</adaptive-icon>\n"
        )
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            (anydpi / name).write_text(xml, encoding="utf-8")

        store = ROOT / "apps" / app / "store"
        store.mkdir(exist_ok=True)
        scaled(visible, 512).convert("RGB").save(store / "play_icon_512.png", optimize=True)
        print("generated", app)


if __name__ == "__main__":
    main()
