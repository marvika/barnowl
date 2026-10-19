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
(build/hero-owl.png). Run from the repo root."""
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


def quick_panel():
    """The quick panel with Keep Awake on, the owlets and the disk: the Rules,
    the toggles and the 'is asking' row are lifted out (the island shows the
    question). Its background is a flat #14141C, so the joins are invisible."""
    parts = (("quick-panel.png", 0, 266),               # Keep Awake, counting down
             ("quick-panel-agents.png", 770, 1044),     # Owlets
             ("quick-panel-agents.png", 1252, None))    # plan limits, disk, footer
    rows = []
    for name, a, b in parts:
        src = body(load(name), 60)  # the opaque box starts at (40, 40)
        rows.append(src.crop((0, max(0, a - 40), src.width, src.height if b is None else b - 40)))
    out = layer((rows[0].width, sum(r.height for r in rows)))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height
    return out


def roost_window(cut):
    """The Roost (tree) at 2/3: its pixels are 3 px on a grid at phase (1, 2), so
    cropping on that grid and box-filtering keeps every sprite pixel a crisp 2 x 2.
    The window is cut at `cut` (before its sidebar, which sits under the quick
    panel) and given back its right edge and top-right corner."""
    src = load("roost-tree.png")
    w = body(src, 150)
    x0, y0 = Image.fromarray(np.array(src)[:, :, 3] > 150).getbbox()[:2]  # where body() cropped
    sx, sy = (1 - x0) % 3, (2 - y0) % 3
    w = w.crop((sx, sy, w.width - (w.width - sx) % 3, w.height - (w.height - sy) % 3))
    w = w.resize((w.width * 2 // 3, w.height * 2 // 3), Image.BOX)
    edge = w.crop((w.width - 3, 30, w.width, w.height))
    corner = w.crop((w.width - 30, 0, w.width, 30))
    w = w.crop((0, 0, cut, w.height))
    w.paste(edge, (cut - 3, 30))
    w.paste(corner, (cut - 30, 0))
    return w


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


# ------------------------------------------------------------------ hero
def hero():
    W, H, K = 1800, 1000, 0.8  # UI at 0.8 of Retina; the README shows it at half
    notch_x = 610               # a 1,490-pt screen, its left third out of frame
    img = wallpaper(W, H, round(66 * K))
    owl_x = menu_bar(img.copy(), K, notch_x)
    # The Roost, lower left: two branches of owlets, the frame cutting below them
    wx, wy, cut = 56, 562, 1012
    place(img, rim(roost_window(cut)), (wx, wy))
    # The quick panel under the owl
    qp = rim(scaled(quick_panel(), K))
    qx = int(max(min(owl_x - qp.width / 2, W - 44 - qp.width), wx + cut + 50))
    menu_bar(img, K, notch_x)
    place(img, qp, (qx, round(66 * K) + 8))
    # The island out of the notch, over everything
    isl = scaled(island(), K)
    ix, neck = int(notch_x - isl.width / 2), round(66 * K)
    shadow(img, isl.crop((0, neck, isl.width, isl.height)), (ix, neck), 0.9)
    img.alpha_composite(isl, (ix, 0))
    return img.convert("RGB")


# ------------------------------------------------------------------ social preview
def social():
    W, H, K = 1280, 640, 0.6
    img = wallpaper(W, H, round(66 * K))
    owl_x = menu_bar(img.copy(), K, -999, clock=("Tue Oct 20", "20:34"))
    qp = rim(scaled(quick_panel(), K))
    qx = int(min(owl_x - qp.width / 2, W - 48 - qp.width))
    menu_bar(img, K, -999)
    place(img, qp, (qx, round(66 * K) + 6), 0.9)
    # The owl, the name and the line under it
    owl = Image.open("build/hero-owl.png").convert("RGBA")
    owl = owl.crop(owl.getbbox())
    owl = scaled(owl, 230 / owl.height)
    lx = 96
    shadow(img, owl, (lx, 92), 0.35)
    img.alpha_composite(owl, (lx, 92))
    d = ImageDraw.Draw(img)
    d.text((lx - 6, 430), "Barn Owl", font=font(104, "Bold"), fill=(255, 255, 255), anchor="ls")
    d.text((lx - 2, 488), "The owl that runs your menu bar.", font=font(34, "Medium"),
           fill=(236, 232, 255), anchor="ls")
    d.text((lx - 2, 548), "Tidy menu bar · Keep awake · Disk space · Coding agents",
           font=font(23, "Medium"), fill=(222, 220, 255, 255), anchor="ls")
    return img.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else IMG
    hero().save(os.path.join(out, "hero.png"), optimize=True)
    social().save(os.path.join(out, "social-preview.png"), optimize=True)
    print(f"Wrote {out}/hero.png and {out}/social-preview.png")
PY
