"""Generates the Android launcher icons and Play Store art for the apps in apps/.

Each app gets an adaptive icon (gradient background + white glyph foreground,
also used as the Android 13 themed monochrome layer), legacy square and round
icons for older launchers, a 512 px Play Store icon and a 1024 x 500 Play
Store feature graphic in apps/<app>/store/.

Run from the repo root (needs Pillow):
    python tool/generate_icons.py                       # everything, all apps
    python tool/generate_icons.py video_player qr_scanner   # only these apps
    python tool/generate_icons.py --only feature        # feature graphics only
    python tool/generate_icons.py --only icons multi_speaker
"""

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
U = 20  # pixels per dp unit on the 108 x 108 master canvas
MASTER = 108 * U
WHITE = (255, 255, 255, 255)
CUT = (0, 0, 0, 0)


def first_font(*candidates):
    for c in candidates:
        if Path(c).exists():
            return Path(c)
    raise SystemExit("no usable font found among: " + ", ".join(candidates))


FONT = first_font(
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
)
FONT_REGULAR = first_font(
    "C:/Windows/Fonts/segoeui.ttf",
    "C:/Windows/Fonts/arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/Library/Fonts/Arial.ttf",
)

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


def cap_arc(d, cx, cy, r, start, end, w, fill):
    """Arc of radius r (dp) from start to end degrees (0 = east, clockwise), round caps."""
    d.arc(p(cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2), start, end, fill=fill, width=int(w * U))
    for a in (start, end):
        x, y = cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
        d.ellipse(p(x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=fill)


def rotated_rounded_square(cx, cy, size, radius, angle):
    """Polygon points (in px) of a rounded square rotated by angle degrees."""
    h, rr = size / 2 - radius, radius
    pts = []
    for qx, qy, a0 in ((h, h, 0), (-h, h, 90), (-h, -h, 180), (h, -h, 270)):
        for i in range(19):
            a = math.radians(a0 + 90 * i / 18)
            pts.append((qx + rr * math.cos(a), qy + rr * math.sin(a)))
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    return [((cx + x * ca - y * sa) * U, (cy + x * sa + y * ca) * U) for x, y in pts]


def die(d, cx, cy, size, angle, pips, gap):
    """A tilted die face with cut-out pips, separated from what is behind by a gap."""
    radius = size * 0.22
    if gap:
        d.polygon(rotated_rounded_square(cx, cy, size + 2 * gap, radius + gap, angle), fill=CUT)
    d.polygon(rotated_rounded_square(cx, cy, size, radius, angle), fill=WHITE)
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    o, pr = size * 0.27, size * 0.095
    for px_, py_ in pips:
        x, y = px_ * o, py_ * o
        x, y = cx + x * ca - y * sa, cy + x * sa + y * ca
        d.ellipse(p(x - pr, y - pr, x + pr, y + pr), fill=CUT)


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


def glyph_speaker(d, accent):
    # Cabinet with a woofer and tweeter, broadcasting sound waves to both sides.
    d.rounded_rectangle(p(43, 31, 65, 77), radius=5 * U, fill=WHITE)
    d.ellipse(p(54 - 7.5, 61 - 7.5, 54 + 7.5, 61 + 7.5), fill=CUT)
    d.ellipse(p(54 - 3, 61 - 3, 54 + 3, 61 + 3), fill=WHITE)
    d.ellipse(p(54 - 3.6, 41.5 - 3.6, 54 + 3.6, 41.5 + 3.6), fill=CUT)
    for r in (16.5, 23.5):
        cap_arc(d, 54, 54, r, -38, 38, 3.4, WHITE)
        cap_arc(d, 54, 54, r, 142, 218, 3.4, WHITE)


def glyph_play(d, accent):
    # Rounded screen on a small stand, with a cut-out play triangle.
    d.rounded_rectangle(p(30, 32, 78, 68), radius=7 * U, fill=WHITE)
    d.polygon(p(48.5, 41.5, 48.5, 58.5, 63.5, 50), fill=CUT)
    cap_line(d, 54, 68, 54, 74, 3.6, WHITE)
    cap_line(d, 45, 76, 63, 76, 3.6, WHITE)


def glyph_dice(d, accent):
    # Two tumbling dice: a big five in front, a small three bouncing behind.
    die(d, 64, 43, 20, 22, ((-1, -1), (0, 0), (1, 1)), 0)
    die(d, 48.5, 60.5, 30, -12, ((-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)), 2.6)


APPS = {
    "qr_scanner": (glyph_qr, (61, 90, 254), (40, 53, 147)),
    "daily_sudoku": (glyph_sudoku, (149, 82, 230), (94, 53, 177)),
    "doc_scanner": (glyph_doc, (255, 112, 87), (214, 54, 64)),
    "expense_tracker": (glyph_wallet, (46, 196, 120), (17, 128, 86)),
    "water_habit": (glyph_drop, (41, 200, 246), (0, 120, 212)),
    "multi_speaker": (glyph_speaker, (236, 64, 160), (106, 27, 154)),
    "video_player": (glyph_play, (255, 152, 0), (230, 40, 100)),
    "snakes_ladders": (glyph_dice, (130, 200, 40), (21, 128, 61)),
}

# Play Store listing name and tagline for each app's feature graphic.
STORE_TEXT = {
    "qr_scanner": ("QR Scanner", "Scan and create QR codes"),
    "daily_sudoku": ("Daily Sudoku", "A fresh puzzle every day"),
    "doc_scanner": ("Doc Scanner", "Scan documents to PDF"),
    "expense_tracker": ("Expense Tracker", "Track daily spending"),
    "water_habit": ("Water Reminder", "Drink water, build habits"),
    "multi_speaker": ("Multi Speaker", "One song, many speakers"),
    "video_player": ("Video Player", "Play any video, watch with friends"),
    "snakes_ladders": ("Dice Dhamaal", "Ludo and Snakes & Ladders"),
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


def fit_font(path, text, max_size, max_width, min_size=20):
    size = max_size
    while size > min_size:
        font = ImageFont.truetype(str(path), size)
        if font.getlength(text) <= max_width:
            return font
        size -= 2
    return ImageFont.truetype(str(path), min_size)


def wrap(text, font, max_width):
    if font.getlength(text) <= max_width:
        return [text]
    head, sep, tail = text.partition(", ")
    if sep and font.getlength(head + ",") <= max_width and font.getlength(tail) <= max_width:
        return [head + ",", tail]  # break at the comma for a balanced two-line tagline
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if line and font.getlength(trial) > max_width:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def feature_graphic(app, glyph, top, bottom):
    """1024 x 500 Play Store feature graphic: gradient, glyph, name and tagline."""
    W, H, k = 1024, 500, 2  # drawn at 2x, then downscaled
    w, h = W * k, H * k
    # Diagonal gradient, slightly deepened so white text keeps its contrast.
    top = tuple(round(c * 0.92) for c in top)
    bottom = tuple(round(c * 0.80) for c in bottom)
    across = Image.linear_gradient("L").transpose(Image.Transpose.ROTATE_90).resize((w, h))
    down = Image.linear_gradient("L").resize((w, h))
    ramp = Image.blend(across, down, 0.25)
    bg = Image.merge(
        "RGB", [ramp.point([round(a + (b - a) * t / 255) for t in range(256)]) for a, b in zip(top, bottom)]
    ).convert("RGBA")

    # Soft decorative circles.
    deco = Image.new("RGBA", (w, h), CUT)
    dd = ImageDraw.Draw(deco)
    dd.ellipse([w - 0.30 * w, -0.45 * h, w + 0.20 * w, 0.55 * h], fill=(255, 255, 255, 18))
    dd.ellipse([-0.12 * w, 0.62 * h, 0.16 * w, 1.40 * h], fill=(255, 255, 255, 14))
    bg = Image.alpha_composite(bg, deco)

    # Glyph on a translucent disc, left of centre.
    gx, gy, gr = int(0.215 * w), h // 2, int(0.36 * h)
    disc = Image.new("RGBA", (w, h), CUT)
    ImageDraw.Draw(disc).ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=(255, 255, 255, 40))
    bg = Image.alpha_composite(bg, disc)
    fg = foreground(glyph, ACCENT).crop((24 * U, 24 * U, 84 * U, 84 * U))
    gs = int(gr * 1.62)
    fg = fg.resize((gs, gs), Image.LANCZOS)
    layer = Image.new("RGBA", (w, h), CUT)
    layer.paste(fg, (gx - gs // 2, gy - gs // 2))
    bg = Image.alpha_composite(bg, layer)

    # Name and tagline, left aligned in the right part, inside the safe area.
    name, tagline = STORE_TEXT[app]
    tx, max_w = int(0.42 * w), int(0.48 * w)
    nfont = fit_font(FONT, name, 92 * k, max_w)
    tfont = fit_font(FONT_REGULAR, tagline, 40 * k, max_w, min_size=34 * k)
    tlines = wrap(tagline, tfont, max_w)
    nh = nfont.getbbox(name, anchor="ls")
    name_h = -nh[1]
    line_h = int(tfont.size * 1.25)
    gap = int(0.06 * h)
    bar_h = 8 * k
    block = bar_h + gap + name_h + gap + line_h * len(tlines)
    y0 = (h - block) // 2 + bar_h + gap + name_h
    text = Image.new("RGBA", (w, h), CUT)
    shadow = Image.new("RGBA", (w, h), CUT)
    td, sd = ImageDraw.Draw(text), ImageDraw.Draw(shadow)
    for drw, fill, off in ((sd, (0, 0, 0, 70), 3 * k), (td, WHITE, 0)):
        drw.text((tx + off, y0 + off), name, font=nfont, fill=fill, anchor="ls")
        y = y0 + gap + int(tfont.size * 0.95)
        for line in tlines:
            drw.text((tx + off, y + off), line, font=tfont, fill=fill if drw is sd else (255, 255, 255, 235), anchor="ls")
            y += line_h
    # Short accent bar above the name.
    bar_y = y0 - name_h - gap - bar_h
    td.rounded_rectangle([tx + 4 * k, bar_y, tx + 4 * k + 72 * k, bar_y + bar_h], radius=bar_h // 2, fill=ACCENT)
    shadow = shadow.filter(ImageFilter.GaussianBlur(4 * k))
    bg = Image.alpha_composite(Image.alpha_composite(bg, shadow), text)

    out = bg.convert("RGB").resize((W, H), Image.LANCZOS)
    store = ROOT / "apps" / app / "store"
    store.mkdir(exist_ok=True)
    out.save(store / "feature_graphic.png", optimize=True)


def launcher_icons(app, glyph, top, bottom):
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("apps", nargs="*", help="app folders to generate (default: all)")
    ap.add_argument("--only", choices=("icons", "feature"), help="generate only launcher/store icons or only feature graphics")
    args = ap.parse_args()
    unknown = [a for a in args.apps if a not in APPS]
    if unknown:
        ap.error(f"unknown app(s): {', '.join(unknown)}; known: {', '.join(APPS)}")
    for app in args.apps or APPS:
        glyph, top, bottom = APPS[app]
        if args.only != "feature":
            launcher_icons(app, glyph, top, bottom)
        if args.only != "icons":
            feature_graphic(app, glyph, top, bottom)
        print("generated", app, f"({args.only})" if args.only else "")


if __name__ == "__main__":
    main()
