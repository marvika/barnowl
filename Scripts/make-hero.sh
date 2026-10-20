#!/bin/zsh
# Composes the README's hero (docs/images/hero.png, 1800 x 1000, shown at 900 px)
# and GitHub's social preview (docs/images/social-preview.png, 1280 x 640) from
# the demo-mode screenshots in docs/images, the owlets in Scripts/owlets and the
# owl the app draws. The app is built and asked for the owl (and owl-moods.png)
# only when build/hero-owl.png is missing, or with --render.
set -euo pipefail
cd "${0:A:h}/.."

if [[ "${1:-}" == "--render" || ! -f build/hero-owl.png ]]; then
  xcodegen generate --quiet
  xcodebuild -project BarnOwl.xcodeproj -scheme BarnOwl -configuration Debug \
    -derivedDataPath build/DerivedData build -quiet
  app="build/DerivedData/Build/Products/Debug/Barn Owl.app/Contents/MacOS/Barn Owl"
  "$app" --render-owl build/hero-owl.png
  "$app" --render-owl-strip docs/images/owl-moods.png
fi

python3 -I -B - <<'PY'
"""Composes docs/images/hero.png (1800 x 1000, shown at 900 px) and
docs/images/social-preview.png (1280 x 640) from the demo screenshots in
docs/images, the owlet sprites in Scripts/owlets and the owl the app draws
(build/hero-owl.png). Run from the repo root.

The hero: the owl, the name and the tagline on the left; on the right the
island growing out of the notch and the quick panel under the owl in the menu
bar; along the bottom, owlets on a bough in the Roost's dusk landscape."""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

IMG = "docs/images"
sys.path.insert(0, "Scripts/owlets")
import owlets as OW  # noqa: E402

SF = "/System/Library/Fonts/SFNS.ttf"
SHADE = (8, 6, 24)  # shadows are a deep indigo, never grey


def font(size, weight="Regular"):
    f = ImageFont.truetype(SF, int(round(size)))
    f.set_variation_by_name(weight)
    return f


def load(name):
    return Image.open(os.path.join(IMG, name)).convert("RGBA")


def scaled(img, k):
    return img if k == 1 else img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)


def layer(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


# ------------------------------------------------------------------ cut-outs
def body(img, s):
    """A window without its baked-in shadow: alpha at or below s is shadow."""
    a = np.array(img).astype(np.float32)
    a[:, :, 3] = np.clip((a[:, :, 3] - s) / (255 - s), 0, 1) * 255
    out = Image.fromarray(a.astype(np.uint8), "RGBA")
    return out.crop(out.getbbox())


def quick_panel(healthy=False):
    """The quick panel with Keep Awake on, the owlets and the disk: the Rules,
    the toggles and the 'is asking' row are lifted out (the island shows the
    question). Its background is a flat #14141C, so the joins are invisible.
    healthy: the disk as the app shows it when it isn't nearly full."""
    parts = (("quick-panel.png", 0, 266),               # Keep Awake, counting down
             ("quick-panel-agents.png", 770, 1044),     # Owlets
             ("quick-panel-agents.png", 1252, None))    # plan limits, disk, footer
    rows = []
    for name, a, b in parts:
        src = body(load(name), 60)  # the opaque box starts at (40, 40)
        if healthy and b is None:
            src = healthy_disk(src)
        rows.append(src.crop((0, max(0, a - 40), src.width, src.height if b is None else b - 40)))
    out = layer((rows[0].width, sum(r.height for r in rows)))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height
    return out


LAVENDER = (140, 135, 255)


def healthy_disk(panel):
    """The disk card as the app draws a healthy disk (QuickPanelView's DiskGlance):
    a lavender ring for the used share, "182 GB free" over a secondary "of 494 GB".
    Coordinates are the 2x screenshot's; body() cropped 40 px off the top left."""
    img = panel.copy()
    o = -40
    d = ImageDraw.Draw(img)
    d.rectangle((80 + o, 1424 + o, 440 + o, 1490 + o), fill=(31, 31, 38, 255))  # the card
    S, c, rad, wdt = 4, 128, 96, 32  # at 4x: a 24-pt ring with a 4-pt stroke
    ring = layer((64 * S, 64 * S))
    rd = ImageDraw.Draw(ring)
    box = (c - rad - wdt / 2, c - rad - wdt / 2, c + rad + wdt / 2, c + rad + wdt / 2)
    rd.ellipse(box, outline=(255, 255, 255, 31), width=wdt)
    used = 1 - 182 / 494
    rd.arc(box, -90, -90 + 360 * used, fill=LAVENDER + (255,), width=wdt)
    for ang in (-90, -90 + 360 * used):  # round caps
        x, y = c + rad * math.cos(math.radians(ang)), c + rad * math.sin(math.radians(ang))
        rd.ellipse((x - wdt / 2, y - wdt / 2, x + wdt / 2, y + wdt / 2), fill=LAVENDER + (255,))
    img.alpha_composite(ring.resize((64, 64), Image.LANCZOS), (80 + o, 1424 + o))
    d = ImageDraw.Draw(img)
    d.text((156 + o, 1426 + o), "182 GB free", font=font(26, "Semibold"), fill=(244, 244, 244), anchor="la")
    d.text((156 + o, 1457 + o), "of 494 GB", font=font(23, "Regular"), fill=(160, 160, 166), anchor="la")
    return img


def island():
    """The island, lifted off island.png's indigo backdrop (the island is pure black,
    so edge alpha is 1 - blue / backdrop blue)."""
    a = np.array(Image.open(os.path.join(IMG, "island.png")).convert("RGB")).astype(np.float32)
    bg = a[:, 2:3, 2]
    raw = np.clip((np.clip(1 - a[:, :, 2] / np.maximum(bg, 1), 0, 1) - 0.06) / 0.94, 0, 1)
    solid = raw > 0.5
    filled = np.zeros_like(solid)
    for y in range(solid.shape[0]):
        xs = np.where(solid[y])[0]
        if len(xs):
            filled[y, xs.min():xs.max() + 1] = True
    inner = np.array(Image.fromarray((filled * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 0
    alpha = np.where(inner, 1.0, raw)
    a[~inner] = 0
    img = Image.fromarray(np.dstack([a, alpha * 255]).astype(np.uint8), "RGBA")
    return img.crop(img.getbbox())


def glyph(x0, x1, pad=6):
    """A white template glyph lifted off menu-bar-countdown.png's wallpaper."""
    a = np.array(load("menu-bar-countdown.png").convert("RGB")).astype(np.float32).mean(axis=2)
    left, right = a[:, x0 - pad:x0 - pad + 1], a[:, x1 + pad:x1 + pad + 1]
    t = (np.arange(x0 - 2, x1 + 3) - (x0 - pad)) / (x1 - x0 + 2 * pad)
    bg = left * (1 - t) + right * t
    al = np.clip((a[:, x0 - 2:x1 + 3] - bg) / (250 - bg), 0, 1)
    out = np.zeros(al.shape + (4,), np.uint8)
    out[:, :, :3] = 255
    out[:, :, 3] = (al * 255).astype(np.uint8)
    img = Image.fromarray(out[4:-4], "RGBA")
    return img.crop(img.getbbox())


# ------------------------------------------------------------------ light
def shadow(canvas, img, xy, strength=1.0):
    """Key light from straight above: a wide soft shadow and a tight contact one."""
    m = img.split()[3]
    for blur, dy, op in ((46, 32, 0.55), (12, 8, 0.40), (2, 1, 0.30)):
        pad = blur * 3 + 10
        sh = Image.new("L", (img.width + pad * 2, img.height + pad * 2), 0)
        sh.paste(m, (pad, pad))
        sh = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * op * strength))
        col = Image.new("RGBA", sh.size, SHADE + (0,))
        col.putalpha(sh)
        full = layer(canvas.size)
        full.paste(col, (int(xy[0]) - pad, int(xy[1]) - pad + dy))
        canvas.alpha_composite(full)


def rim(img, alpha=30):
    """A hairline light edge, like a glass window catching the light."""
    m = img.split()[3]
    edge = ImageChops.subtract(m, m.filter(ImageFilter.MinFilter(3))).point(lambda v: v * alpha // 255)
    top = Image.new("RGBA", img.size, (255, 255, 255, 0))
    top.putalpha(edge)
    out = img.copy()
    out.alpha_composite(top)
    return out


def place(canvas, img, xy, strength=1.0):
    shadow(canvas, img, xy, strength)
    full = layer(canvas.size)
    full.paste(img, (int(xy[0]), int(xy[1])))
    canvas.alpha_composite(full)


# ------------------------------------------------------------------ desktop
def wallpaper(w, h, top):
    """Dusk: deep indigo overhead, lavender lower down, a warm glow on the horizon,
    two soft hills and a few stars. Dithered so the gradient never bands."""
    ys = np.linspace(0, 1, h)
    stops = [(0, (27, 26, 62)), (0.35, (48, 45, 110)), (0.7, (88, 75, 152)), (1, (156, 114, 160))]
    col = np.stack([np.interp(ys, [s[0] for s in stops], [s[1][i] for s in stops]) for i in range(3)], 1)
    a = np.repeat(col[:, None, :], w, axis=1)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    g = np.exp(-(((xx - w * 0.8) / (w * 0.45)) ** 2 + ((yy - h * 1.02) / (h * 0.3)) ** 2))[:, :, None] * 0.38
    a = a * (1 - g) + np.array((240, 162, 118), np.float32) * g
    a += np.random.default_rng(3).uniform(-0.6, 0.6, a.shape)
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    rng = random.Random(11)
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(int(90 * w * h / 1.8e6)):
        x, y, s = rng.uniform(0, w), rng.uniform(top, h * 0.6), rng.uniform(1.2, 3.0) * w / 1800
        al = int(255 * rng.uniform(0.15, 0.55) * (1 - (y - top) / (h * 0.6 - top) * 0.7))
        d.ellipse((x - s / 2, y - s / 2, x + s / 2, y + s / 2), fill=(255, 250, 240, al))
    for base, amp, seed, phase, fill in ((0.86, 26, 5, 0.0, (52, 42, 98)), (0.93, 18, 9, 1.0, (32, 27, 66))):
        r = random.Random(seed)
        waves = [(r.uniform(0.6, 1.4) * 2 * math.pi / w * k, r.uniform(0, 6.28), amp * h / 1000 / k ** 1.3)
                 for k in (1, 2, 3, 5, 8)]
        pts = [(x, h * base + sum(am * math.sin(f * x + p + phase) for f, p, am in waves)) for x in range(0, w + 8, 4)]
        d.polygon(pts + [(w, h), (0, h)], fill=fill + (255,))
    return img


def menu_bar(img, k, notch_x, countdown="2:14", clock=("Tue Oct 20", "20:34")):
    """macOS 26's clear menu bar: the clock, Control Center, the Perch's chevron
    and Barn Owl's owl with its keep-awake countdown, highlighted because its
    panel is open; the notch in the middle. Returns the owl item's centre x."""
    w = img.width
    mb = round(66 * k)
    scrim = layer((w, mb + 30))
    sd = ImageDraw.Draw(scrim)
    for y in range(mb + 30):
        sd.line([(0, y), (w, y)], fill=(10, 8, 30, int(70 * max(0, 1 - y / (mb + 30)))))
    img.alpha_composite(scrim)
    d = ImageDraw.Draw(img, "RGBA")
    cy = mb / 2 + 1
    f, fb = font(26 * k, "Medium"), font(26 * k, "Semibold")
    white = (255, 255, 255, 240)
    x = w - 38 * k
    for s in reversed(clock):
        tw = d.textlength(s, font=f)
        d.text((x - tw, cy), s, font=f, fill=white, anchor="lm")
        x -= tw + 22 * k
    x -= 25 * k
    for x0, x1, gap in ((764, 789, 55), (701, 713, 50)):  # Control Center, the chevron
        g = scaled(glyph(x0, x1), k)
        img.alpha_composite(g, (int(x - g.width), int(cy - g.height / 2)))
        x -= g.width + gap * k
    owl = scaled(glyph(565, 590), k)
    tw = d.textlength(countdown, font=fb)
    total = owl.width + 12 * k + tw
    x0 = x - total
    cap = layer(img.size)
    ImageDraw.Draw(cap).rounded_rectangle((x0 - 17 * k, cy - 22 * k, x0 + total + 17 * k, cy + 22 * k),
                                          22 * k, fill=(255, 255, 255, 40))
    img.alpha_composite(cap)
    img.alpha_composite(owl, (int(x0), int(cy - owl.height / 2)))
    d.text((x0 + owl.width + 12 * k, cy), countdown, font=fb, fill=white, anchor="lm")
    nw = round(370 * k)
    d.rounded_rectangle((notch_x - nw / 2, -40, notch_x + nw / 2, mb), 18 * k, fill=(0, 0, 0, 255))
    return x0 + total / 2


# ------------------------------------------------------------------ hero: the Roost's dusk
# Colours from RoostScene.swift's dusk palette.
DUSK = dict(sky=[(0x1D, 0x20, 0x50), (0x36, 0x34, 0x70), (0x66, 0x4E, 0x87), (0xAC, 0x6B, 0x8C), (0xE8, 0xA2, 0x8C)],
            ridge=(0x5E, 0x4F, 0x86), ridge_rim=(0xC3, 0xA0, 0xC6), hill=(0x3A, 0x2F, 0x58), meadow=(0x33, 0x29, 0x4F),
            leaves=[(0x1F, 0x2E, 0x46), (0x2C, 0x44, 0x58), (0x48, 0x66, 0x7A)])
P = 3  # landscape pixels are 3 x 3, like the Roost's sprites


def dusk_sky(w, h, top):
    """The dusk sky as one smooth, dithered gradient, with a few stars up high."""
    ys = np.linspace(0, 1, h)
    cols = DUSK["sky"]
    col = np.stack([np.interp(ys, [0, 0.3, 0.62, 0.86, 1.0], [c[i] for c in cols]) for i in range(3)], 1)
    a = np.repeat(col[:, None, :], w, axis=1) + np.random.default_rng(3).uniform(-0.6, 0.6, (h, w, 3))
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    rng = random.Random(11)
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(int(80 * w * h / 1.8e6)):
        x, y, s = rng.uniform(0, w), rng.uniform(top, h * 0.55), rng.uniform(1.2, 3.0)
        al = int(255 * rng.uniform(0.15, 0.55) * (1 - (y - top) / (h * 0.55 - top) * 0.8))
        d.ellipse((x - s / 2, y - s / 2, x + s / 2, y + s / 2), fill=(255, 250, 240, al))
    return img


def ridge_line(n, base, amp, seed, phase=0.0):
    r = random.Random(seed)
    waves = [(r.uniform(0.7, 1.3) * 2 * math.pi / n * k, r.uniform(0, 6.28), amp / k ** 1.2) for k in (1, 2, 3, 5)]
    return [int(round(base + sum(a * math.sin(f * x + p + phase) for f, p, a in waves))) for x in range(n)]


def landscape(w, h, p=P, rows=(292, 306, 322)):
    """Ridge (with a lit rim), hill and meadow as pixel silhouettes, full width, on a
    p-px grid with their crests at `rows` (grid rows). Returns the far layers and the
    meadow separately, so the bough can root between them."""
    n, m = -(-w // p), -(-h // p)
    back, front = Image.new("RGBA", (n, m)), Image.new("RGBA", (n, m))
    for layer_img, line, col, rim_col in (
            (back, ridge_line(n, rows[0], 7, 5), DUSK["ridge"], DUSK["ridge_rim"]),
            (back, ridge_line(n, rows[1], 5, 9, 1.3), DUSK["hill"], None),
            (front, ridge_line(n, rows[2], 3, 17, 2.1), DUSK["meadow"], None)):
        px = layer_img.load()
        for x in range(n):
            for y in range(max(0, line[x]), m):
                px[x, y] = col + (255,)
            if rim_col and 0 <= line[x] < m:
                px[x, line[x]] = tuple((a + b) // 2 for a, b in zip(col, rim_col)) + (255,)
    grow = lambda g: g.resize((n * p, m * p), Image.NEAREST).crop((0, 0, w, h))
    return grow(back), grow(front)


def hexrgb(h):
    return tuple(int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))


def bough(n_len, owls, rise=34, root=46, p=P):
    """A low bough on the landscape's grid: it grows up out of the meadow on the left,
    runs level, tapers to a leafy tip and is lit from above. Owlets (Scripts/owlets
    sprites, whole pixels) stand on it, toes curled over the bark.
    Returns (image, y of the level branch's top, left padding), in px."""
    pad, base = 8, 32
    g = Image.new("RGBA", (n_len + 2 * pad, base + rise + 12))
    px = g.load()
    bark, dark, lit = (0x5C, 0x43, 0x63), (0x33, 0x24, 0x3C), (0xB8, 0x92, 0xB4)

    def put(x, y, c):
        if 0 <= x + pad < g.width and 0 <= y < g.height:
            px[x + pad, y] = c + (255,)

    def y_at(i):
        if i >= root:
            return base + int(round(1.2 * math.sin((i - root) / 41.0)))
        return base + int(round(rise * (1 - i / root) ** 2))

    for i in range(n_len):
        t = i / n_len
        th = 6 if t < 0.08 else 5 if t < 0.3 else 4 if t < 0.6 else 3 if t < 0.85 else 2
        y0 = y_at(i)
        y1 = max(y0, y_at(i - 1) if i else y0)
        for y in range(y0, y1 + th):
            put(i, y, lit if y == y0 else (dark if y == y1 + th - 1 else bark))
    tx = int(n_len * 0.86)  # a twig near the tip
    for k in range(7):
        put(tx + k, y_at(tx) - 1 - k // 2, bark)
        put(tx + k, y_at(tx) - 2 - k // 2, lit)
    rng = random.Random(4)
    for cx, cy, rr in ((n_len - 2, y_at(n_len - 1) - 1, 5), (tx + 8, y_at(tx) - 6, 3)):
        for dx in range(-rr - 2, rr + 3):
            for dy in range(-rr, rr + 1):
                if dx * dx / (rr + 2) ** 2 + dy * dy / rr ** 2 <= 1 and rng.random() > 0.1:
                    put(cx + dx, cy + dy, DUSK["leaves"][2 if dy < -rr / 3 else (1 if dy < rr / 3 else 0)])
    frames = {s[0]: s[3] for s in OW.STATES}
    for state, palname, i in owls:
        pal = OW.PALS[OW.AGENT_PALS.get(palname, palname)]
        foot = y_at(i)
        for (x, y), c in frames[state][0].items():
            if c != "n" and y < OW.H - 2:  # leave out the sprite's own branch
                put(i + x - 16, foot - (OW.H - 2) + y, hexrgb(pal[c]))
        for x in (12, 14, 17, 19):
            put(i + x - 16, foot, hexrgb(pal["a"]))
    return g.resize((g.width * p, g.height * p), Image.NEAREST), base * p, pad * p


def notch_and_island(img, cx, mb, k):
    """The island at scale k (0.75 keeps its 4-px owlet a crisp 3 px), hanging from a
    notch as tall as the menu bar."""
    isl = scaled(island(), k)
    xs = np.where(np.array(isl)[2, :, 3] > 128)[0]
    neck = round(66 * k)
    ix, iy = int(cx - (xs.min() + xs.max()) / 2), mb - neck
    ImageDraw.Draw(img).rectangle((ix + xs.min(), 0, ix + xs.max(), iy + 4), fill=(0, 0, 0, 255))
    shadow(img, isl.crop((0, neck, isl.width, isl.height)), (ix, iy + neck), 0.9)
    img.alpha_composite(isl, (ix, iy))


def brand(img, x, y, owl_h, size):
    """The owl the app draws, with its soft shadow, over the name, the tagline and the four jobs."""
    owl = Image.open("build/hero-owl.png").convert("RGBA")
    owl = scaled(owl.crop(owl.getbbox()), owl_h / owl.crop(owl.getbbox()).height)
    shadow(img, owl, (x, y), 0.35)
    img.alpha_composite(owl, (x, y))
    d = ImageDraw.Draw(img)
    yb = y + owl_h + round(size * 1.02)
    d.text((x - round(size * 0.06), yb), "Barn Owl", font=font(size, "Bold"), fill=(255, 255, 255), anchor="ls")
    yt = yb + round(size * 0.58)
    d.text((x - 2, yt), "The owl that runs your menu bar.", font=font(size * 0.34, "Medium"),
           fill=(240, 236, 255), anchor="ls")
    d.text((x - 2, yt + round(size * 0.5)), "Tidy menu bar · Keep awake · Disk space · Coding agents",
           font=font(size * 0.235, "Medium"), fill=(222, 220, 255), anchor="ls")


def hero():
    W, H, K, KI = 1800, 1000, 0.8, 0.75  # UI at 0.8 of Retina (the README shows it at half)
    mb = round(66 * K)
    img = dusk_sky(W, H, mb)
    back, front = landscape(W, H)
    img.alpha_composite(back)
    b, top, pad = bough(330, [("ask", "golden", 84), ("typing", "golden", 142),
                              ("command", "ghost", 200), ("nap", "lilac", 258)])
    img.alpha_composite(b, (40 - pad, 905 - top))
    img.alpha_composite(front)
    # The quick panel under the owl in the menu bar, the island beside it
    owl_x = menu_bar(img.copy(), K, -999)
    qp = rim(scaled(quick_panel(healthy=True), K))
    qx = int(min(owl_x - qp.width / 2, W - 44 - qp.width))
    menu_bar(img, K, -999)
    place(img, qp, (qx, mb + 8))
    notch_and_island(img, qx - 56 - scaled(island(), KI).width / 2, mb, KI)
    brand(img, 110, 120, 290, 140)
    return img.convert("RGB")


# ------------------------------------------------------------------ social preview
def social():
    """GitHub's card, the hero's little sibling: the owl, the name and the tagline,
    the quick panel under the owl in the menu bar, owlets on a bough at dusk.
    Everything that matters sits at least 40 px in, for crops."""
    W, H, K, p = 1280, 640, 0.6, 3
    mb = round(66 * K)
    img = dusk_sky(W, H, mb)
    back, front = landscape(W, H, p, (187, 194, 204))
    img.alpha_composite(back)
    b, top, pad = bough(200, [("ask", "golden", 58), ("command", "ghost", 106), ("nap", "lilac", 152)],
                        rise=18, root=28, p=p)
    img.alpha_composite(b, (30 - pad, 585 - top))
    img.alpha_composite(front)
    owl_x = menu_bar(img.copy(), K, -999)
    qp = rim(scaled(quick_panel(healthy=True), K))
    qx = int(min(owl_x - qp.width / 2, W - 48 - qp.width))
    menu_bar(img, K, -999)
    place(img, qp, (qx, mb + 6), 0.9)
    owl = Image.open("build/hero-owl.png").convert("RGBA")
    owl = owl.crop(owl.getbbox())
    owl = scaled(owl, 200 / owl.height)
    shadow(img, owl, (84, 64), 0.35)
    img.alpha_composite(owl, (84, 64))
    d = ImageDraw.Draw(img)
    d.text((77, 382), "Barn Owl", font=font(118, "Bold"), fill=(255, 255, 255), anchor="ls")
    d.text((82, 443), "The owl that runs your menu bar.", font=font(40, "Medium"), fill=(240, 236, 255), anchor="ls")
    return img.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else IMG
    hero().save(os.path.join(out, "hero.png"), optimize=True)
    social().save(os.path.join(out, "social-preview.png"), optimize=True)
    print(f"Wrote {out}/hero.png and {out}/social-preview.png")
PY
