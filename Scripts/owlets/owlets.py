"""Pixel owlets for The Roost: the sprites behind BarnOwl/Roost/OwletArt.swift.

Public API: PAL, W, H, STATES, svg, ICONS, template_svg, png_sheet,
plus PALS / AGENT_PALS (palette swaps),
svg(..., pal=), recolor(), blink(), owl() / put() / wing_at() for composing new scenes.

A sprite is a list of frames; a frame is a dict {(x, y): palette-key}. The owl is a
20x23 drawing (tuft, heart face with rim, blush, belly chevrons, folded wings, feet)
on a 32x30 stage whose bottom two rows are the branch. Poses are built from parts:
body (rest / squash / stretch), eyes, each wing, head props, then hand props.

Palette keys (golden = Claude):
  o outline (warm brown)   e eye          h gold light   g gold   d gold shade
  r rust (deep shade)      f face rim     w face/white   c cream  q cream shade
  b blush / coral          a amber        l lilac        L lilac dark   m lilac light
  n bark (branch)          t s k: v1 names for g d o, kept for old legends
"""

_ALIAS = {"t": "g", "s": "d", "k": "o"}   # v1 key names (tan, shade, ink), kept for old legends


def _with_alias(p):
    return dict(p, **{a: p[b] for a, b in _ALIAS.items()})


PAL = {
    "o": "#4a2c1e",  # outline: warm dark brown, never pure black
    "e": "#24182a",  # eyes
    "h": "#f8cf7e",  # gold light (top-left)
    "g": "#f0b04f",  # gold
    "d": "#c8742c",  # gold shade
    "r": "#a9572a",  # rust: deepest shade, feather lines
    "f": "#a5532a",  # heart-face rim (a hair off rust so recolor() can tell them apart)
    "w": "#fff9f0",  # face / highlights
    "c": "#f2e2c8",  # cream
    "q": "#d9bc96",  # cream shade, chevrons
    "b": "#ff8a7a",  # blush, coral
    "a": "#f5a633",  # amber: beak, feet, sparks
    "l": "#a9a5ff",  # lilac accent
    "L": "#6e68ea",  # lilac dark
    "m": "#dedcff",  # lilac light: glow, steam, Zs
    "n": "#8c5a3c",  # bark
    "v": "#7ce0a0",  # green: done
}
PAL = _with_alias(PAL)

# Agent palette swaps. Prop colours (l, L, m) stay lilac except on the lilac owl,
# where props go warm so they still read against the body.
PALS = {
    "golden": dict(PAL),
    "ghost": dict(PAL, o="#3d3a8f", e="#1c1a40", h="#ffffff", g="#eeebfa", d="#c9c4f0",
                  r="#9c95e8", f="#8c87ff", w="#ffffff", c="#eceaf8", q="#c9c4f0",
                  b="#ff9dbb"),
    "lilac": dict(PAL, o="#2e2a86", e="#1c1a40", h="#c9c6ff", g="#a5a1ff", d="#7c76ee",
                  r="#5852d2", f="#f5a633", w="#fff5e4", c="#eeedff", q="#c9c6f2",
                  b="#ff9fb2", l="#f5c46b", L="#c8742c", m="#ffe2a8"),
    "ember": dict(PAL, o="#6e2410", e="#2a1b30", h="#ffb27a", g="#ff8a50", d="#e2552c",
                  r="#b83a1e", f="#b83a1e", w="#fff3e4", c="#ffe6d2", q="#f2c2a0",
                  b="#ff5c7a", a="#ffc24d"),
}
PALS = {k: _with_alias(v) for k, v in PALS.items()}
AGENT_PALS = {"claude": "golden", "codex": "ghost", "copilot": "lilac", "opencode": "ember"}
ORDER = "nordhgfwcqbaLlme"  # paint order inside one layer (pixels never overlap anyway)

W, H = 32, 30          # stage, in sprite pixels
TOP = 2                # headroom rows; scenes are composed on a 32x28 grid then moved down
_HB = H - TOP          # height scenes are composed in
OX, OY = 6, 3          # owl origin while composing (OY becomes 5 on the final stage)

# ------------------------------------------------------------------ the owl
BODY = [
    "..........oo........",  # 0  tuft
    ".........ohdo.......",  # 1
    "......ooohgooo......",  # 2
    "....oohhhhhgggoo....",  # 3
    "...ohffffhgffffgo...",  # 4  heart lobes
    "..ohfwwwwffwwwwfdo..",  # 5
    "..ohfwwwwwwwwwwfdo..",  # 6
    ".ohfwwwwwwwwwwwwfdo.",  # 7
    ".ohfwwwwwwwwwwwwfdo.",  # 8  eyes 8-10
    ".ogfwwwwwwwwwwwcfdo.",  # 9
    ".ogfwwwwwwwwwwwcfdo.",  # 10
    ".odgfwwwwwwwwwcfgdo.",  # 11 beak, blush
    ".oddgffwwwwwcffgddo.",  # 12
    ".odddggfwwwcfggrddo.",  # 13
    ".odddrggfccfggrdddo.",  # 14
    ".odddrgggffgggrdddo.",  # 15 heart point
    ".oddrggwwwwwcggrddo.",  # 16 belly
    ".odrgggqwqqwqcggrdo.",  # 17
    "..orggwwqwwqwcggro..",  # 18
    "...ogggwwqqwccgdo...",  # 19
    "....oggdwwwccddo....",  # 20
    ".....oooooooooo.....",  # 21
    "......aaa..aaa......",  # 22 feet
]
# Same owl with the folded wings painted out (used when a wing is raised).
BARE = BODY[:11] + [
    ".ohgfwwwwwwwwwcfgdo.",  # 11
    ".ohggffwwwwwcffggdo.",  # 12
    ".ogggggfwwwcfgggddo.",  # 13
    ".oggggggfccfggggddo.",  # 14
    ".ogggggggffgggggddo.",  # 15
    ".ogggggwwwwwcgggddo.",  # 16
    ".oggggwqwqqwqcggddo.",  # 17
    "..ogggwwqwwqwcggdo..",  # 18
    "...ogggwwqqwccgdo...",  # 19
    "....oggdwwwccddo....",  # 20
] + BODY[21:]
assert all(len(r) == 20 for r in BODY + BARE) and len(BODY) == len(BARE) == 23


def _grid(rows):
    return {(x, y): ch for y, r in enumerate(rows) for x, ch in enumerate(r) if ch != "."}


_BODY, _BARE = _grid(BODY), _grid(BARE)
# Selective outline: where the outline touches lit gold on the top-left it softens to rust.
for (x, y), ch in list(_BODY.items()):
    if ch == "o" and y < 14 and x <= 10 and any(_BODY.get((x + dx, y + dy)) == "h"
                                                 for dx, dy in ((1, 0), (0, 1), (1, 1))):
        _BODY[(x, y)] = _BARE[(x, y)] = "r"
WING_L = {p: c for p, c in _BODY.items() if p[0] < 10 and _BARE.get(p) != c}
WING_R = {p: c for p, c in _BODY.items() if p[0] >= 10 and _BARE.get(p) != c}

EYE_L, EYE_R = (5, 8), (12, 8)
EYES = {  # art for the left eye (right eye mirrors when in MIRROR_EYES), offset from EYE_L/EYE_R
    "open":      (["wee", "eee", "eee"], 0, 0),
    "down":      (["wee", "eee", "eee"], 0, 1),
    "up":        (["wee", "eee", "eee"], 0, -1),
    "left":      (["wee", "eee", "eee"], -1, 0),
    "right":     (["wee", "eee", "eee"], 1, 0),
    "upright":   (["wee", "eee", "eee"], 1, -1),
    "upleft":    (["wee", "eee", "eee"], -1, -1),
    "downleft":  (["wee", "eee", "eee"], -1, 1),
    "downright": (["wee", "eee", "eee"], 1, 1),
    "wide":      (["wee", "eee", "eew"], 0, 0),      # sparkly, alert
    "happy":     ([".e.", "e.e"], 0, 0),             # ^ ^
    "closed":    (["e.e", ".e."], 0, 1),             # sleeping
    "blink":     (["eee"], 0, 1),
    "half":      (["eee", "eee"], 0, 1),             # drowsy, content (flat lids)
    "small":     ([".e", "ee"], 0, 1),               # startled pin-pupils
    "squint":    (["e..", ".ee", "e.."], 0, 0),      # >  <  (effort)
    "glow":      (["haa", "aea", "aaa"], 0, 1),      # night: lamp-lit eyes, looking down
    "grit":      (["o..", ".oo", "eee", "eee"], 0, -1),   # brows down: determined
    "sad":       ([".oo", "o..", "eee", "wee"], 0, -1),   # brows up: worried
}
MIRROR_EYES = {"squint", "grit", "sad"}

# Wings outside the body (left side; the right side mirrors). (art, ax, ay): the art's
# top-left goes at owl-local (ax, ay). A raised wing also paints out the folded one.
WINGS = {
    "wave": ([".oo...", "ohgo..", "ohgdo.", "ohgdo.", ".ogddo", ".ogddo", "..oddo", "...odd"], -4, 4),
    "high": ([".oo.", "ohgo", "ohgo", "ogdo", "ogdo", "ogddo", ".oddo", "..odd"], -2, 2),
    "out":  (["ooo....", "ohgooo.", ".ohgggd", "..oodddd", "....oo.."], -5, 10),
    "low":  (["..od", ".odd", "odgd", "odd.", "oo.."], -2, 13),
    "hold": (["od....", "oddoo.", "odgggo", ".ooooo"], 1, 14),
    "tap":  (["od...", "oddo.", "odggo", ".ooo."], 1, 12),
    "chin": (["....ooo", "..oohgo", ".ohggdo", "ogddoo.", "odoo...", "od....."], 2, 11),
}


def _mirror_art(art):
    return [r[::-1] for r in art]


def put(f, art, x0, y0, keep=False):
    """Stamp ASCII art (rows of palette keys, '.' = clear) into frame f."""
    for dy, row in enumerate(art):
        for dx, ch in enumerate(row):
            if ch != ".":
                x, y = x0 + dx, y0 + dy
                if 0 <= x < W and -TOP <= y < _HB and not (keep and (x, y) in f):
                    f[(x, y)] = ch
    return f


def dots(f, pts, ch):
    for x, y in pts:
        if 0 <= x < W and -TOP <= y < _HB:
            f[(x, y)] = ch
    return f


def _owl_local(eyes="open", wl="fold", wr="fold", blush=True, beak="shut", tuft=0, extra=None):
    """The owl in its own 20x23 coordinates (wings may poke outside)."""
    p = dict(_BODY)
    for side, pose in (("l", wl), ("r", wr)):
        if pose == "fold":
            continue
        bare = {q: c for q, c in _BARE.items() if (q[0] < 10) == (side == "l") and q[1] >= 11}
        p.update(bare)
        if pose == "none":
            continue
        art, ax, ay = WINGS[pose]
        if side == "r":
            art, ax = _mirror_art(art), 19 - ax - len(art[0]) + 1
        for dy, row in enumerate(art):
            for dx, ch in enumerate(row):
                if ch != ".":
                    p[(ax + dx, ay + dy)] = ch
    art, dx, dy = EYES[eyes]
    for side, (ex, ey) in (("l", EYE_L), ("r", EYE_R)):
        a = _mirror_art(art) if side == "r" and eyes in MIRROR_EYES else art
        ox = ex + dx + (3 - len(a[0]) if side == "r" and eyes in MIRROR_EYES else 0)
        for yy, row in enumerate(a):
            for xx, ch in enumerate(row):
                if ch != ".":
                    p[(ox + xx, ey + dy + yy)] = ch
    if blush and eyes not in ("down", "downleft", "downright"):
        for x in (4, 5, 14, 15) if eyes in ("happy", "closed", "squint") else (5, 6, 13, 14):
            if p.get((x, 11)) == "w" or p.get((x, 11)) == "c":
                p[(x, 11)] = "b"
    if beak == "shut":
        p[(9, 11)] = p[(10, 11)] = "a"
    elif beak == "open":
        p[(9, 11)] = p[(10, 11)] = "a"
        p[(9, 12)], p[(10, 12)] = "r", "a"
    elif beak == "o":  # small "oh"
        p[(9, 11)] = p[(10, 11)] = "a"
        p[(9, 12)] = p[(10, 12)] = "o"
    if tuft == 1:      # tuft flicks up
        p.pop((10, 0), None); p.pop((11, 0), None)
        p[(11, -1)] = p[(12, -1)] = "o"; p[(10, 0)] = "o"; p[(11, 0)] = "h"; p[(12, 0)] = "o"
    elif tuft == -1:   # tuft droops
        p.pop((10, 0), None); p.pop((11, 0), None)
        p[(12, 1)] = "o"; p[(13, 2)] = "o"
        p[(11, 1)] = "d"
    elif tuft == 2:    # ruffled
        p[(8, 0)] = p[(13, 0)] = "o"; p[(7, 1)] = p[(14, 1)] = "o"
        p[(8, 1)] = "h"; p[(13, 1)] = "d"
    if extra:
        extra(p)
    return p


def _remap(p, body):
    """Squash/stretch by dropping or doubling one belly row; feet stay planted."""
    if body == "rest":
        return p
    out = {}
    if body == "squash":      # drop row 19
        for (x, y), c in p.items():
            if y == 19:
                continue
            out[(x, y + 1 if y < 19 else y)] = c
        return out
    if body == "stretch":     # double row 16
        for (x, y), c in p.items():
            if y <= 16:
                out[(x, y - 1)] = c
            if y >= 16:
                out.setdefault((x, y), c)
        return out
    if body == "tall":        # stretch by two
        return _remap(_remap(p, "stretch"), "stretch")
    raise ValueError(body)


def owl(eyes="open", ox=OX, oy=OY, f=None, wl="fold", wr="fold", body="rest", lift=0,
        blush=True, beak="shut", tuft=0, feet=True, extra=None):
    """Stamp the owl into frame f. lift raises the whole owl (a hop), feet and all."""
    f = {} if f is None else f
    p = _remap(_owl_local(eyes, wl, wr, blush, beak, tuft, extra), body)
    for (x, y), c in p.items():
        if not feet and y >= 22:
            continue
        X, Y = ox + x, oy + y - lift
        if 0 <= X < W and -TOP <= Y < _HB:
            f[(X, Y)] = c
    return f


def branch(f, x0=0, x1=W, knots=True):
    for x in range(x0, x1):
        f[(x, _HB - 2)] = "n"
        f[(x, _HB - 1)] = "o"
    if knots:
        for x in (3, 19, 28):
            if x0 <= x < x1:
                f[(x, _HB - 1)] = "n"; f[(x, _HB - 2)] = "d" if x != 19 else "n"
    return f


def toes(f, ox=OX, oy=OY):
    """Toes curled over the branch."""
    for x in (6, 8, 11, 13):
        f[(ox + x, oy + 23)] = "a"
    return f


def scene(f, ox=OX, oy=OY, feet=True):
    branch(f)
    if feet:
        toes(f, ox, oy)
    return f


# ------------------------------------------------------------------ props
LAPTOP = [  # lid seen from behind, Barn Owl's heart on it
    "oooooooooooooo",
    "ommmmmmmmmmmlo",
    "omllllllllllLo",
    "omllwllwllllLo",
    "omlwwwwwwlllLo",
    "omllwwwwllllLo",
    "omlllwwlllllLo",
    "omllllllllllLo",
    "oLLLLLLLLLLLLo",
    "oooooooooooooo",
]
LENS = [  # held out at arm's length
    "..ooo..",
    ".oLLLo.",
    "oL..wLo",
    "oL...Lo",
    "oL...Lo",
    ".oLLLo.",
    "..ooo..",
]
LENS_EYE = [  # held over the right eye: a big magnified eye
    "..ooooo..",
    ".oLLLLLo.",
    "oLweeewLo",
    "oLewweeLo",
    "oLewweeLo",
    "oLeeeeeLo",
    "oLweeewLo",
    ".oLLLLLo.",
    "..ooooo..",
]
BOARD = [  # a little terminal on a stand
    "ooooooooooo",
    "olllllllllo",
    "oleeeeeeeLo",
    "oleeeeeeeLo",
    "oleeeeeeeLo",
    "oleeeeeeeLo",
    "oleeeeeeeLo",
    "oLLLLLLLLLo",
    "ooooooooooo",
    "....oLo....",
    "....oLo....",
    "...oLLLo...",
]
MUG = [
    "ooooooo..",
    "odddddo..",
    "owbwbwooo",
    "owbbbwo.o",
    "owwbwwooo",
    "ocwwwco..",
    ".ooooo...",
]
CAP = [  # Barn Owl's nightcap: lilac with stripes, cream band, tip flopping right
    "......ooooo.........",
    "....oomlllmooo......",
    "...olmlllmllLLoo....",
    "..olmlllmlllLLLLo...",
    "..olllllllllLLLLLo..",
    ".occwwwwwwwwwwwccoLo",
    "..oooooooooooooooLo.",
    "................owwo",
    "................owwo",
    ".................oo.",
]
PARTY = [  # party hat: stripes, gold pompom
    "...ah...",
    "...aa...",
    "..olLo..",
    "..obbo..",
    ".olllLo.",
    ".oaaaao.",
    "olllllLo",
    "oooooooo",
]
EGG = [
    "....oooo....",
    "..oowwwcoo..",
    ".owwwwwwcco.",
    ".owwwqwwwco.",
    "owwwwwwwwcco",
    "owwwwwwqwcco",
    "owqwwwwwwcco",
    "owwwwwwwwcco",
    "owwwwwqwccqo",
    "occwwwwwccqo",
    ".occcccccqo.",
    ".oqcccccqqo.",
    "..ooqqqqoo..",
    "....oooo....",
]
CRACK = ["o.....o.....", ".o.o.o.o.o.o", "..o...o...o."]
KID = [  # a hatchling: 9 wide, heart face, two pin eyes
    "....o....",
    "..oohoo..",
    ".owwgwwo.",
    "ohwewewdo",
    "ogwwawwdo",
    "ogdwwwddo",
    ".ogdwddo.",
    "..ooooo..",
    "..a...a..",
]
CHICK = [  # hatchling peeking out of the shell
    ".....oo.....",
    "...oohgoo...",
    "..offhgffo..",
    ".ofwwffwwfo.",
    "ohfwwwwwwfdo",
    "ogfwewwewfdo",
    "ogfwewwewfdo",
    "ogdfwaawfddo",
    "ogddfwwfdddo",
    ".oddgffgddo.",
]
KID = [  # 7-wide owlet watching from the branch
    "...o...",
    ".oohdo.",
    "owwgwwo",
    "owewewo",
    "ogwawdo",
    ".ogwdo.",
    "..ooo..",
    "..a.a..",
]
SCROLL_BIG = [
    "occcccccccco",
    "owwwwwwwwwqo",
    "owLLLLLLLwqo",
    "owwwwwwwwwqo",
    "owLLLLLwwwqo",
    "owwwwwwwwwqo",
    "owLLLLLLwwqo",
    "occcccccccco",
]
SCROLL_MID = ["occcccco", "owwwwwqo", "owLLLwqo", "owwwwwqo", "owLLwwqo", "occcccco"]
SCROLL_SMALL = [".oooo.", "owLLqo", "owLLqo", ".oooo."]   # squeezed and tied
PLANE = [
    "oo......",
    "owwo....",
    ".owwwoo.",
    ".oqqwwwo",
    "..oqqoo.",
    "...oo...",
]
PAGE = [
    "ooooooooo",
    "owwwwwwqo",
    "owLLLLwqo",
    "owwwwwwqo",
    "owLLLwwqo",
    "owwwwwwqo",
    "owLLLLwqo",
    "oqqqqqqqo",
    "ooooooooo",
]
PARCEL = [
    "..oaao..",
    "..oooo..",
    "oooaaooo",
    "olllalLo",
    "ommmammo",
    "olllalLo",
    "oLLLaLLo",
    "oooooooo",
]
CLOUD = [
    "....oooo......",
    "..oommmmoo....",
    ".ommmmmmmmoo..",
    "ommmmmmmmmmmo.",
    "ommmmmmmmmmmlo",
    ".ollllllllllLo",
    "..oooooooooooo",
]
BANG = [".oooo.", "oaaaao", "oaeeao", "oaeeao", "oaeeao", "oaaaao", "oaeeao", "oaaaao", ".oooo.", "..o...", ".o...."]
QUERY = [".ooooo.", "ommmmmo", "omeeemo", "ommmemo", "ommeemo", "ommmmmo", "ommemmo", "ommmmmo",
         ".ooooo.", "...o...", "....o.."]
THOUGHT = [
    "..ooooo..",
    ".ommmmmo.",
    "ommmaaamo",
    "ommahaamo",
    "ommmaaamo",
    ".ommLmmo.",
    "..ooooo..",
]
THOUGHT_EMPTY = [r.replace("a", "m").replace("h", "m").replace("L", "m") for r in THOUGHT]
FLAG = [
    ["ooooooooo", "ollllllLo", "olllllwLo", "owllwwlLo", "ollwwllLo", "olllllLLo", "ooooooooo"],
    ["oooooooo.", "olllllLoo", "ollllwlLo", "owllwwlLo", "ollwwllLo", "olllllLo.", "ooooooo.."],
]
Z_SMALL = ["mmm", "..m", ".m.", "mmm"]  # a Z, not an I
Z_BIG = ["mmmm", "..m.", ".m..", "mmmm"]
SPARK = [".a.", "awa", ".a."]
NO_SIGNAL = [
    "..mmmmm..b",
    ".m.....mb.",
    "m..mmm.b.m",
    "..m...b...",
    "....mb....",
    "....b.....",
]
BRACE = [".mm", ".m.", "m..", ".m.", ".mm"]


def put_local(p, art, x0, y0):
    for dy, row in enumerate(art):
        for dx, ch in enumerate(row):
            if ch != ".":
                p[(x0 + dx, y0 + dy)] = ch


def wing_at(f, pose, side, ox=OX, oy=OY, dy=0):
    """Stamp a wing pose straight onto the stage (for wings behind/over props)."""
    art, ax, ay = WINGS[pose]
    if side == "r":
        art, ax = _mirror_art(art), 19 - ax - len(art[0]) + 1
    return put(f, art, ox + ax, oy + ay + dy)


# ------------------------------------------------------------------ states
def typing(night=False):
    out = []
    for i in range(4 if not night else 2):
        f = {}
        cap = (lambda p: put_local(p, CAP, 0, -3)) if night else None
        owl("glow" if night else "down", f=f, wl="none", wr="none", extra=cap)
        up_l = i % 2 == 0
        put(f, LAPTOP, OX + 3, OY + 13)
        paw = [".oo.", "ohgo", "oddo"]
        put(f, paw, OX + 4, OY + (10 if up_l else 11))
        put(f, _mirror_art(paw), OX + 12, OY + (11 if up_l else 10))
        if not night:
            if i in (1, 3):   # screen light on the face
                dots(f, [(OX + x, OY + 12) for x in range(8, 12) if f.get((OX + x, OY + 12)) == "w"], "m")
            gy = [11, 8, 11, 8][i]
            art = BRACE if i < 2 else _mirror_art(BRACE)
            put(f, art, 27, gy)
            if i in (1, 3):
                f[(28, gy + 6)] = "l"
        else:
            put(f, [".mm", "mm.", "mm.", "mm.", ".mm"], 1, 1)             # moon
            dots(f, [(27, 3), (5, 9), (30, 10)] if i == 0 else [(29, 1), (4, 7), (26, 9)], "w")
            dots(f, [(29, 6)] if i == 0 else [(24, 4)], "m")
            dots(f, [(OX + x, OY + 12) for x in range(8, 12) if f.get((OX + x, OY + 12)) == "w"], "m")
        scene(f, feet=False)
        out.append(f)
    return out


def searching():
    out = []
    for i in range(4):
        f = {}
        if i in (0, 2):
            owl("open", f=f, wr="hold", tuft=1 if i == 2 else 0)
            put(f, LENS_EYE, OX + 10, OY + 5)
            put(f, ["on", "on"], OX + 14, OY + 14)
            if i == 2:   # glint sweeps
                f[(OX + 12, OY + 7)] = "e"; f[(OX + 15, OY + 10)] = "w"
        elif i == 1:
            owl("left", f=f, wl="out")
            put(f, LENS, 0, OY + 3)
            put(f, ["n", "n", "o"], 3, OY + 10)
        else:
            owl("right", f=f, wr="out")
            put(f, LENS, W - 7, OY + 3)
            put(f, ["n", "n", "o"], W - 4, OY + 10)
        scene(f)
        out.append(f)
    return out


def command():
    ox = 1
    out = []
    for i in range(4):
        f = {}
        owl("right" if i != 3 else "happy", ox=ox, f=f, wr="out" if i != 3 else "fold",
            body="squash" if i == 3 else "rest", lift=0)
        bx, by = 21, 13
        put(f, BOARD, bx, by)
        put(f, ["a.", ".a", "a."], bx + 2, by + 2)            # prompt >
        if i % 2 == 0:
            dots(f, [(bx + 5, by + 3)], "w")                  # blinking cursor
        dots(f, [(bx + 2 + k, by + 6) for k in range(min(7, 2 + i * 2))], "l" if i < 3 else "a")
        if i == 3:
            dots(f, [(bx + 5, by + 3), (bx + 6, by + 3), (bx + 7, by + 3)], "w")
        scene(f, ox=ox)
        out.append(f)
    return out


def thinking():
    out = []
    for i in range(4):
        f = {}
        owl("upright" if i < 3 else "up", f=f, wl="chin", tuft=1 if i == 3 else 0)
        dots(f, [(OX + 17, 5)], "m")
        if i >= 1:
            put(f, ["mm", "mm"], OX + 18, 2)
        if i == 2:
            put(f, THOUGHT_EMPTY, 23, 0)
        if i == 3:
            put(f, THOUGHT, 23, 0)
        scene(f)
        out.append(f)
    # Still pictures show the first frame: start on the one with the thought.
    return out[3:] + out[:3]


def web():
    out = []
    for i in range(4):
        f = {}
        if i == 0:
            owl("upleft", f=f)
            put(f, PLANE, 0, 3)
            dots(f, [(0, 1), (2, 0)], "m")
        elif i == 1:
            owl("upleft", f=f, wl="wave", body="stretch", beak="o")
            put(f, PLANE, OX - 6, 0)
        else:
            owl("down" if i == 2 else "downright", f=f, wl="hold", wr="hold")
            put(f, PAGE, OX + 5, OY + 14)
            dots(f, [(OX + 7 + k, OY + 16 + (2 if i == 3 else 0)) for k in range(4)], "l")
        scene(f, feet=i < 2)
        out.append(f)
    # Still pictures show the first frame: start reading the fetched page.
    return out[2:] + out[:2]


def needs_you():
    out = []
    plan = [("rest", "wave", 0, "shut"), ("stretch", "high", 1, "open"), ("rest", "wave", 0, "shut"),
            ("squash", "out", 0, "shut")]
    for i, (body, wing, lift, beak) in enumerate(plan):
        f = {}
        owl("wide", f=f, wr=wing, body=body, lift=lift, beak=beak)
        put(f, BANG, 0, 2 - lift)
        scene(f, feet=lift == 0)
        out.append(f)
    return out


def asking():
    out = []
    for i in range(2):
        f = {}
        owl("upleft" if i == 0 else "left", f=f, wr="chin", tuft=1 if i == 1 else 0)
        put(f, QUERY, 0, 1 if i == 0 else 0)
        scene(f)
        out.append(f)
    return out


def napping():
    out = []
    for i in range(4):
        f = {}
        owl("closed", f=f, body=["rest", "stretch", "stretch", "rest"][i],
            extra=lambda p: put_local(p, CAP, 0, -3))
        if i >= 1:
            put(f, Z_SMALL, 24, 10 - i * 2)
        if i >= 2:
            put(f, Z_BIG, 27, 3 - (i - 2) * 2)
        scene(f)
        out.append(f)
    return out


def tea():
    out = []
    for i in range(3):
        f = {}
        sip = i == 2
        owl("closed" if sip else "half", f=f, wl="hold", wr="hold", body="stretch" if sip else "rest")
        mx, my = (OX + 6, OY + 9) if sip else (OX + 6, OY + 14)
        put(f, MUG, mx, my)
        wisp = [[".l", "l.", ".l"], ["l.", ".l", "l."], [".l", "l."]][i]
        put(f, wisp, mx + 2, my - 4)
        put(f, wisp[::-1], mx + 4, my - 5)
        scene(f)
        out.append(f)
    return out


def done():
    out = []
    # (body, wings, hop, beak, hat offset: + lags low on the way up, - floats on the way down)
    plan = [("squash", "low", 0, "shut", 0), ("stretch", "wave", 1, "open", 1),
            ("rest", "wave", 1, "open", -1), ("squash", "fold", 0, "shut", 0)]
    confetti = {1: [(3, 1, "a"), (28, 0, "l"), (5, 6, "b"), (26, 5, "m"), (1, 10, "l"), (30, 11, "b")],
                2: [(3, 3, "a"), (28, 2, "l"), (5, 8, "b"), (26, 7, "m"), (1, 12, "l"), (30, 13, "b")],
                3: [(3, 6, "a"), (28, 5, "l"), (5, 11, "b"), (26, 10, "m"), (1, 15, "l"), (30, 16, "b")]}
    for i, (body, wing, lift, beak, lag) in enumerate(plan):
        f = {}
        owl("happy", f=f, wl=wing, wr=wing, body=body, lift=lift, beak=beak,
            extra=lambda p, lag=lag: put_local(p, PARTY, 6, -4 + lag))
        for x, y, c in confetti.get(i, []):
            f[(x, y)] = c
        if i == 1:
            put(f, SPARK, 0, -2); put(f, SPARK, 29, -2)
        scene(f, feet=lift == 0)
        out.append(f)
    return out


def hatching():
    out = []
    ex, ey = 10, _HB - 2 - len(EGG)
    for i in range(4):
        f = {}
        if i == 0:
            put(f, EGG, ex, ey)
        elif i == 1:
            put(f, EGG, ex - 1, ey + 0)
            dots(f, [(ex - 3, ey + 2), (ex - 3, ey + 4)], "m")
        elif i == 2:
            put(f, EGG, ex + 1, ey)
            put(f, CRACK, ex + 1, ey + 5)
            dots(f, [(ex + 14, ey + 2), (ex + 14, ey + 4)], "m")
        else:
            put(f, CHICK, ex, ey - 1)
            put(f, ["o.o..o..o.oo", "owoowoowowco"] + EGG[8:], ex, ey + 6)
            put(f, ["..oooo..", ".owwwco.", "owwwwcco", "o.oo.o.o"], 23, 1)    # shell cap flying off
            put(f, SPARK, 4, 6); f[(8, 2)] = "a"; f[(27, 11)] = "m"; f[(5, 13)] = "l"
        scene(f, feet=False)
        out.append(f)
    return out


def night_shift():
    return typing(night=True)


def error():
    out = []
    ox = 1
    plan = [("small", "stretch", 1, "o", 2), ("small", "squash", 0, "shut", 2), ("grit", "rest", 0, "shut", 0)]
    for i, (eyes, body, lift, beak, tuft) in enumerate(plan):
        f = {}
        owl(eyes, ox=ox, f=f, wl="out" if i == 0 else "fold", wr="out" if i < 2 else "hold",
            body=body, tuft=tuft, beak=beak, lift=lift)
        bx, by = 21, 13
        put(f, BOARD, bx, by)
        put(f, ["b.b", ".b.", "b.b"], bx + 4, by + 3)            # coral x
        put(f, ["o.", ".o", "o.", ".o"], bx + 7, by + 1)          # crack in the glass
        puff = [["..mm...", ".mmmmm.", "mmmmmmm", ".mmlmm.", "..m...."],
                [".mmm...", "mmmmm..", ".mmmm..", "..m...."],
                ["..m....", ".m.m...", "..m...."]][i]
        put(f, puff, bx + 2, by - 5 - i)
        if i == 1:
            put(f, ["m", "m", "l"], ox + 2, OY + 4)            # sweat drop
        scene(f, ox=ox, feet=lift == 0)
        out.append(f)
    return out


def retrying():
    out = []
    ox = 1
    for i in range(4):
        f = {}
        owl("grit", ox=ox, f=f, wr="high" if i % 2 == 0 else "out", body="stretch" if i % 2 == 0 else "squash")
        bx, by = 21, 13
        put(f, BOARD, bx, by)
        put(f, ["a.", ".a", "a."], bx + 2, by + 2)
        dots(f, [(bx + 2 + k, by + 6) for k in range(1 + i * 2)], "l")
        if i % 2 == 0:   # hammer up
            put(f, ["ooooooo", "ommmmLo", "ooooooo", "...n...", "...n...", "...n..."], bx - 4, by - 7)
        else:            # and down on the bolt
            put(f, ["....ooo", "....omo", "nnnnomo", "....oLo", "....ooo"], bx - 4, by - 4)
            put(f, SPARK, bx + 4, by - 4); f[(bx + 1, by - 5)] = "a"; f[(bx + 6, by - 1)] = "a"
        scene(f, ox=ox)
        out.append(f)
    return out


def passed():
    out = []
    for i in range(2):
        f = {}
        lift = 1 if i == 0 else 0
        ox = 3
        owl("happy", ox=ox, f=f, wr="high", body="stretch" if i == 0 else "rest", lift=lift,
            beak="open" if i == 0 else "shut")
        px = ox + 19
        top = 1 - lift
        for y in range(top, OY + 5 - lift):
            f[(px, y)] = "n"
        f[(px, top - 1 if top else 0)] = "a"
        put(f, FLAG[i], px + 1, top)
        if i == 0:
            put(f, SPARK, 1, 4); f[(4, 1)] = "l"
        else:
            f[(2, 7)] = "a"; f[(5, 3)] = "l"
        scene(f, ox=ox, feet=lift == 0)
        out.append(f)
    return out


def compacting():
    out = []
    for i in range(4):
        f = {}
        if i == 0:
            owl("wide", f=f, wl="out", wr="out")
            put(f, SCROLL_BIG, OX + 4, OY + 13)
        elif i == 1:
            owl("squint", f=f, wl="hold", wr="hold", body="squash")
            put(f, SCROLL_MID, OX + 6, OY + 15)
            dots(f, [(OX + 1, OY + 15), (OX, OY + 17), (OX + 18, OY + 15), (OX + 19, OY + 17)], "m")
        elif i == 2:
            owl("squint", f=f, wl="hold", wr="hold", body="squash")
            put(f, SCROLL_SMALL, OX + 7, OY + 15)
            dots(f, [(OX + 1, OY + 16), (OX + 18, OY + 16)], "m")
        else:
            owl("happy", f=f, wr="high")
            put(f, SCROLL_SMALL, OX + 18, OY - 2)
            put(f, SPARK, 2, 6); f[(28, 9)] = "a"
        scene(f)
        out.append(f)
    return out


def shipping():
    out = []
    for i in range(3):
        f = {}
        if i == 0:
            owl("down", f=f, wl="hold", wr="hold")
            put(f, PARCEL, OX + 6, OY + 14)
        elif i == 1:
            owl("squint", f=f, wl="hold", wr="hold", body="squash")
            put(f, PARCEL, OX + 6, OY + 15)
        else:
            owl("upright", f=f, wr="high", body="stretch", beak="open")
            put(f, PARCEL, W - 8, 0)
            dots(f, [(OX + 15, 7), (OX + 16, 6), (OX + 17, 9), (OX + 18, 8)], "m")
        scene(f)
        out.append(f)
    return out


def offline():
    out = []
    for i in range(2):
        f = {}
        owl("closed", f=f, body="squash", tuft=-1, blush=False,
            extra=lambda p: put_local(p, ["..co", ".cqc", "cqc.", "oc.."], 12, 2))
        # No connection: the Wi-Fi sign, crossed out. (The rain cloud means stuck.)
        put(f, NO_SIGNAL, OX + 13, 0)
        if i == 1:
            dots(f, [(OX + 12, 7)], "m")
        scene(f)
        out.append(f)
    return out


def waiting():
    out = []
    plan = [("downright", 0, 1), ("downright", 1, 0), ("downleft", 0, 1), ("downleft", 1, 0)]
    for i, (eyes, b1, b2) in enumerate(plan):
        f = {}
        owl(eyes, ox=OX, f=f)
        put(f, KID, 0, _HB - 2 - len(KID) + 1 - b1)
        put(f, KID, W - 7, _HB - 2 - len(KID) + 1 - b2)
        scene(f)
        out.append(f)
    return out


def idle():
    out = []
    for i, (eyes, tuft) in enumerate((("open", 0), ("left", 0), ("open", 1), ("right", 0))):
        f = {}
        owl(eyes, f=f, tuft=tuft)
        scene(f)
        out.append(f)
    return out


def _stage(frames):
    """Move composed frames down onto the final 32x30 stage."""
    return [{(x, y + TOP): c for (x, y), c in f.items() if 0 <= y + TOP < H} for f in frames]


STATES = [
    ("typing", "Typing", "Editing or writing", _stage(typing()), 0.8),
    ("search", "Searching", "Read, grep, glob, Explore", _stage(searching()), 2.0),
    ("command", "Running", "A shell command", _stage(command()), 2.0),
    ("think", "Thinking", "Planning, long think", _stage(thinking()), 2.4),
    ("web", "Browsing", "WebFetch, WebSearch", _stage(web()), 2.0),
    ("needs", "Needs you", "Permission to continue", _stage(needs_you()), 1.0),
    ("ask", "Asking", "Has a question for you", _stage(asking()), 2.0),
    ("nap", "Napping", "Idle at the prompt", _stage(napping()), 3.2),
    ("tea", "Tea break", "Rate-limited till 15:00", _stage(tea()), 2.4),
    ("done", "Done", "Finished, unread", _stage(done()), 1.2),
    ("hatch", "Hatching", "A subagent starts", _stage(hatching()), 2.4),
    ("night", "Night shift", "Working while you sleep", _stage(night_shift()), 1.0),
    ("error", "Oops", "A command or test failed", _stage(error()), 1.8),
    ("retry", "Fixing", "Trying again after an error", _stage(retrying()), 1.2),
    ("passed", "Tests pass", "A green test run", _stage(passed()), 0.8),
    ("compact", "Compacting", "Context nearly full", _stage(compacting()), 2.0),
    ("ship", "Shipping", "Committed, pushed or PR opened", _stage(shipping()), 1.5),
    ("offline", "Stopped", "Crashed, killed or exited", _stage(offline()), 1.2),
    ("waiting", "Waiting", "Watching its subagents", _stage(waiting()), 2.4),
    ("idle", "Perched", "Between turns, wide awake", _stage(idle()), 4.0),
]


OY += TOP              # owl origin on the final stage


# ------------------------------------------------------------------ output
def paths(pixels, pal=None):
    pal = pal or PAL
    by = {}
    for (x, y), c in pixels.items():
        by.setdefault(c, set()).add((x, y))
    out = []
    for c in sorted(by, key=lambda k: ORDER.index(k) if k in ORDER else 99):
        pts = by[c]
        d = []
        for y in sorted({p[1] for p in pts}):
            xs = sorted(p[0] for p in pts if p[1] == y)
            start = prev = xs[0]
            for x in xs[1:] + [None]:
                if x is not None and x == prev + 1:
                    prev = x
                    continue
                d.append(f"M{start} {y}h{prev - start + 1}v1H{start}z")
                if x is not None:
                    start = prev = x
        fill = pal.get(c, c) if c in pal else c
        out.append(f'<path fill="{fill}" d="{"".join(d)}"/>')
    return "".join(out)


def svg(frames, scale=3, dur=1.0, w=W, h=H, cls="", pal=None):
    """Frames -> one inline SVG. Shared pixels go in a static layer; the rest go in
    <g class="px-f px-fN"> groups stepped by CSS (.px-nN, --px-d)."""
    if isinstance(pal, str):
        pal = PALS[AGENT_PALS.get(pal, pal)]
    n = len(frames)
    static = dict(frames[0])
    for f in frames[1:]:
        static = {p: c for p, c in static.items() if f.get(p) == c}
    body = paths(static, pal)
    if n > 1:
        for i, f in enumerate(frames):
            diff = {p: c for p, c in f.items() if static.get(p) != c}
            body += f'<g class="px-f px-f{i}">{paths(diff, pal)}</g>'
    anim = f" px-n{n}" if n > 1 else ""
    style = f' style="--px-d:{dur}s"' if n > 1 else ""
    return (f'<svg class="px-s{anim}{(" " + cls) if cls else ""}"{style} viewBox="0 0 {w} {h}" '
            f'width="{w * scale}" height="{h * scale}" shape-rendering="crispEdges" aria-hidden="true">'
            f"{body}</svg>")


def recolor(svg_text, pal):
    """Swap the golden palette in an svg() string for another one (name or dict)."""
    if isinstance(pal, str):
        pal = PALS[AGENT_PALS.get(pal, pal)]
    keys = [k for k in PAL if k not in _ALIAS and pal.get(k, PAL[k]) != PAL[k]]
    # placeholders first so swaps never chain
    for k in keys:
        svg_text = svg_text.replace(f'fill="{PAL[k]}"', f'fill="@{k}@"')
    for k in keys:
        svg_text = svg_text.replace(f'fill="@{k}@"', f'fill="{pal[k]}"')
    return svg_text


def blink(frame, ox=OX, oy=OY):
    """Copy of a staged frame with the eyes shut: an app-timed 100-150 ms blink that
    works on any open-eyed frame (squash, stretch and hops included)."""
    f = dict(frame)
    for lo, hi in ((ox + 3, ox + 10), (ox + 10, ox + 17)):
        eye = [(x, y) for (x, y), c in f.items()
               if c == "e" and lo <= x < hi and oy + 4 <= y <= oy + 13]
        if not eye:
            continue
        xs, ys = [p[0] for p in eye], [p[1] for p in eye]
        for x in range(min(xs), max(xs) + 1):
            for y in range(min(ys), max(ys) + 1):
                if f.get((x, y)) in ("e", "w"):
                    f[(x, y)] = "w"
            f[(x, max(ys) - (max(ys) - min(ys)) // 2 + (1 if max(ys) > min(ys) else 0))] = "e"
    return f


def png_sheet(path, scale=6, pal=None, states=None):
    from PIL import Image, ImageDraw
    pal = PALS[AGENT_PALS.get(pal, pal)] if isinstance(pal, str) else (pal or PAL)
    rows = states or STATES
    cols = max(len(s[3]) for s in rows)
    img = Image.new("RGB", (cols * (W + 2) * scale, len(rows) * (H + 2) * scale), "#1d1b45")
    d = ImageDraw.Draw(img)
    for r, (_, _, _, frames, _) in enumerate(rows):
        for c, f in enumerate(frames):
            x0, y0 = c * (W + 2) * scale, r * (H + 2) * scale
            for (x, y), ch in f.items():
                d.rectangle([x0 + x * scale, y0 + y * scale, x0 + (x + 1) * scale - 1,
                             y0 + (y + 1) * scale - 1], fill=pal[ch])
    img.save(path)


# ------------------------------------------------------------------ 16x16 icons
ICON_OWL = [  # an egg, not a tile: a big round head over a body that tapers to the feet
    ".......oo.......",
    ".....oohgoo.....",
    "...oohfffhfffo..",
    "..ohfwwwffwwwfo.",
    ".ohfwwwwwwwwwwfo",
    ".ogfwwwwwwwwwcfo",
    ".ogfwwwwwwwwwcfo",
    ".oggfwwwwwwwcfdo",
    ".odggfwwwwwcfgdo",
    ".odrggfwwwcfgrdo",
    "..odrgggffggrdo.",
    "..odrgwwwwwgrdo.",
    "...odwqwwqwcdo..",
    "....odwqqwcdo...",
    ".....oooooooo...",
    ".....aa....aa...",
]
assert all(len(r) == 16 for r in ICON_OWL) and len(ICON_OWL) == 16


def _eyes(l, r, cells):
    """cells: (dx, dy, key) for the left eye at l; mirrored positions reuse the art."""
    return [(l[0] + dx, l[1] + dy, c) for dx, dy, c in cells] + [(r[0] + dx, r[1] + dy, c) for dx, dy, c in cells]


# Tall dark eyes with a catch-light: friendly at 16 px.
_E2 = [(0, 0, "e"), (0, 1, "e")]
ICON_EYES = {
    "open": _eyes((5, 5), (10, 5), _E2),
    "down": _eyes((5, 6), (10, 6), _E2),
    "left": _eyes((4, 5), (9, 5), _E2),
    "right": _eyes((6, 5), (11, 5), _E2),
    # Round and bright, looking at you: not cross.
    "wide": _eyes((5, 4), (10, 4), [(0, 0, "e"), (0, 1, "e"), (0, 2, "e")]),
    "closed": _eyes((4, 6), (9, 6), [(0, 0, "e"), (1, 1, "e"), (2, 0, "e")]),
    "happy": _eyes((4, 6), (9, 6), [(0, 0, "e"), (1, -1, "e"), (2, 0, "e")]),
    "small": _eyes((6, 6), (10, 6), [(0, 0, "e")]),
    "flat": _eyes((5, 6), (10, 6), [(0, 0, "e"), (1, 0, "e")]),
}


def _ic(eyes, extra=None, blush=True):
    f = _grid(ICON_OWL)
    for x, y, c in ICON_EYES[eyes]:
        f[(x, y)] = c
    f[(7, 8)] = f[(8, 8)] = "a"
    if blush and eyes not in ("down", "flat"):
        f[(4, 8)] = f[(11, 8)] = "b"
    if extra:
        extra(f)
    return f


def _art(art, x0, y0):
    """Lays a prop over the owlet; '.' leaves what's beneath."""
    def go(f):
        for dy, row in enumerate(art):
            for dx, ch in enumerate(row):
                if ch != ".":
                    f[(x0 + dx, y0 + dy)] = ch
    return go


def _both(*props):
    def go(f):
        for prop in props:
            prop(f)
    return go


# One bold prop each, the same ones the big owlets carry.
ICON_LAPTOP = ["..oooooooo..", "..olllllmo..", "..ollllllo..", ".oooooooooo."]
ICON_LAPTOP_GLOW = ["..oooooooo..", "..olmllllo..", "..ollllllo..", ".oooooooooo."]
# Stuck: the same laptop, gone coral with a cross. Offline: gone dark.
ICON_LAPTOP_STUCK = ["..oooooooo..", "..obebebbo..", "..obbebbbo..", "..obebebbo..", ".oooooooooo."]
ICON_LAPTOP_OFF = ["..oooooooo..", "..oeeeeeeo..", "..oeeeeeeo..", ".oooooooooo."]
# A magnifier held up to the right eye: the eye looks big through it.
ICON_LENS = [".ooo..", "owmmo.", "omemo.", "omemo.", ".oooo.", "....o.", ".....o"]
# Signs held up on a stick, as the big owlets do.
ICON_BANG = ["oooo", "oaao", "oaao", "oaao", "oooo", "oaao", "oooo", ".o..", ".o.."]
ICON_QUESTION = ["ooooo", "owweo", "oeewo", "oeweo", "oeeeo", "oeweo", "ooooo", "..o..", "..o.."]
ICON_MUG = ["..m.m..", ".m.m...", "oooooo.", "olllloo", "ollllo.o", "olllloo", ".oooo.."]
ICON_CARD = ["oooooooo", "ovvvvvwo", "ovwvvwvo", "ovvwwvvo", "oooooooo"]
ICON_CONFETTI = ["a.............", "..............", "............l.", ".l............", "..............", "..............", "a...........a."]
ICON_TRYING = ["m.m.m"]
ICON_CAP = [  # a nightcap, its pompom flopped over to one side
    "...oooooo..",
    "..olmllllooo",
    ".olllllllowo",
    "ommmmmmmmmoo",
    ".oooooooooo.",
]
ICON_ZED = ["mmm", "..m", ".m.", "mmm"]
ICON_TRYING = ["m.m.m"]

ICONS = {
    # name: (frames, seconds per loop). Each owlet is doing something with
    # its prop, as the working one does with its laptop.
    "typing": ([_ic("down", _art(ICON_LAPTOP, 2, 11)), _ic("down", _art(ICON_LAPTOP_GLOW, 2, 11))], 0.8),
    "search": ([_ic("open", _art(ICON_LENS, 9, 3)), _ic("left", _art(ICON_LENS, 9, 3))], 1.2),
    "needs": ([_ic("wide", _art(ICON_BANG, 12, 0)), _ic("wide", _art(ICON_BANG, 12, 1))], 0.8),
    "ask": ([_ic("right", _art(ICON_QUESTION, 11, 0)), _ic("open", _art(ICON_QUESTION, 11, 0))], 1.6),
    "nap": ([_ic("flat", _both(_art(ICON_CAP, 1, 0), _art(ICON_ZED, 13, 0)))], 0),
    "tea": ([_ic("down", _art(ICON_MUG, 5, 9))], 0),
    "done": ([_ic("open", _both(_art(ICON_CARD, 4, 10), _art(ICON_CONFETTI, 1, 0)))], 0),
    "error": ([_ic("down", _art(ICON_LAPTOP_STUCK, 2, 10), blush=False)], 0),
    "offline": ([_ic("flat", _both(_art(ICON_LAPTOP_OFF, 2, 11), _art(ICON_TRYING, 11, 0)), blush=False)], 0),
}


def _mono(f):
    """1-bit mask for the menu bar: everything but the heart face (and blush/beak)."""
    face = {p for p, c in f.items() if c in ("w", "c", "b", "a") and 3 <= p[1] <= 10 and 3 <= p[0] <= 12}
    return {p: "o" for p in f if p not in face}


def template_svg(frames, size=16, dur=1.0):
    """1-bit owl for the menu bar: silhouette in currentColor with the heart face cut
    out; eyes, belly and badges stay solid. Use as a template image."""
    s = svg([_mono(f) for f in frames], scale=1, dur=dur, w=16, h=16)
    return s.replace(f'fill="{PAL["o"]}"', 'fill="currentColor"').replace(
        'width="16" height="16"', f'width="{size}" height="{size}"')


if __name__ == "__main__":
    import sys
    png_sheet(sys.argv[1] if len(sys.argv) > 1 else "sheet2.png")
