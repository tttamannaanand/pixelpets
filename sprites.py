"""Front-facing pixel sprites for Thea, Ivan and Kai.

Each pose is built from simple shapes on a 36 x 34 grid, every pixel tagged with the part
it belongs to (head, body, ear, leg, tail...). Then each pet gets its own coat: Thea's bold
silver-brown tabby, Ivan's fine sandy stripes, Kai's glossy black. A dark outline goes
around the silhouette, then the face is drawn on top. Eyes can look left, centre or right,
so the app can make them follow the cursor.

    python sprites.py      # writes sprites/<pet>/<pose>_<frame>.png and sprites/preview.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 36, 34
CX = 18  # centre line
GROUND = 32  # bottom row of the paws
OUT = Path(__file__).parent / "sprites"


def rgba(h: str) -> tuple[int, int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


class Grid:
    def __init__(self):
        self.tag: dict[tuple[int, int], str] = {}
        self.color: dict[tuple[int, int], tuple] = {}

    def put(self, x, y, tag):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < W and 0 <= y < H:
            self.tag[(x, y)] = tag

    def ellipse(self, cx, cy, rx, ry, tag):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.put(x, y, tag)

    def rect(self, x0, y0, x1, y1, tag):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.put(x, y, tag)

    def poly(self, pts, tag):
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            for x in range(int(min(xs)), int(max(xs)) + 1):
                if _inside(x + 0.5, y + 0.5, pts):
                    self.put(x, y, tag)

    def line(self, pts, tag, width=2):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:], strict=False):
            n = int(max(abs(x1 - x0), abs(y1 - y0)) * 3) + 1
            for i in range(n + 1):
                t = i / n
                x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                for dx in range(width):
                    for dy in range(width):
                        self.put(x + dx - width / 2 + 0.5, y + dy - width / 2 + 0.5, tag)

    def mirror_poly(self, pts, tag):
        self.poly(pts, tag)
        self.poly([(2 * CX - x, y) for x, y in pts], tag)


def _inside(x, y, pts):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
            c = not c
        j = i
    return c


# ---------------------------------------------------------------- cats


def cat_head(g, cy, big_ears=False, ear_drop=0.0, flat=False):
    g.ellipse(CX, cy, 8.8, 7.2, "head")
    g.ellipse(CX, cy + 4.3, 3.2, 2.0, "muzzle")
    e = 1.08 if big_ears else 1.0
    tip = cy - 10.8 * e + ear_drop
    if flat:  # ears pinned back and out to the sides
        g.mirror_poly([(CX - 7.6, cy - 1.6), (CX - 12.4 * e, cy - 4.4), (CX - 11.6 * e, cy - 5.6), (CX - 5.6, cy - 5.8)], "ear")
    else:
        g.mirror_poly([(CX - 8.6, cy - 1.2), (CX - 7.4 * e, tip), (CX - 6.6 * e, tip + 0.6), (CX - 2.2, cy - 6.4)], "ear")
    return {"head_cy": cy + 1, "eyes_y": int(cy + 1), "ear_tip": tip, "big_ears": big_ears, "flat": flat}


def cat_sit(g, frame=0, big_ears=False):
    g.ellipse(CX, 26.5, 6.6, 5.4, "body")
    g.ellipse(CX, 26, 3, 3.6, "chest")
    g.rect(CX - 4, 28, CX - 2, GROUND - 1, "leg")
    g.rect(CX + 2, 28, CX + 4, GROUND - 1, "leg")
    g.rect(CX - 5, GROUND, CX - 2, GROUND, "paw")
    g.rect(CX + 2, GROUND, CX + 5, GROUND, "paw")
    tails = [[(CX + 5, 31), (CX + 9, 30), (CX + 11, 27), (CX + 11, 24)], [(CX + 5, 31), (CX + 9, 31), (CX + 12, 29), (CX + 13, 26)]]
    g.line(tails[frame % 2], "tail", 2)
    return cat_head(g, 14, big_ears)


def cat_hiss(g, frame=0, big_ears=False):
    """Puffed up, ears flat, tail like a bottle brush."""
    g.ellipse(CX, 26, 7.8, 6.2, "body")
    g.ellipse(CX, 26, 3, 3.6, "chest")
    g.rect(CX - 5, 28, CX - 3, GROUND - 1, "leg")
    g.rect(CX + 3, 28, CX + 5, GROUND - 1, "leg")
    g.rect(CX - 6, GROUND, CX - 3, GROUND, "paw")
    g.rect(CX + 3, GROUND, CX + 6, GROUND, "paw")
    sway = frame % 2
    g.line([(CX + 6, 30), (CX + 10, 26), (CX + 11 + sway, 20), (CX + 11 + sway, 13)], "tail", 3)
    p = cat_head(g, 14, big_ears, flat=True)
    return p | {"angry": True, "hiss": True}


def cat_swipe(g, frame=0, big_ears=False):
    """Claws out: paw up, then a swipe across."""
    p = cat_hiss(g, 0, big_ears)
    hy = p["head_cy"]
    if frame % 2 == 0:
        g.line([(CX - 5, 27), (CX - 10, 21), (CX - 12, hy - 3)], "leg", 3)
        g.rect(CX - 14, hy - 5, CX - 11, hy - 3, "paw")
        p["claws"] = [(CX - 14, hy - 6), (CX - 13, hy - 7), (CX - 12, hy - 7), (CX - 11, hy - 6)]
    else:
        g.line([(CX - 5, 27), (CX + 1, 22), (CX + 9, hy + 2)], "leg", 3)
        g.rect(CX + 9, hy, CX + 12, hy + 2, "paw")
        p["claws"] = [(CX + 13, hy - 1), (CX + 13, hy), (CX + 13, hy + 1), (CX + 13, hy + 2)]
        p["slash"] = True
    return p


def cat_bap(g, frame=0, big_ears=False):
    """A casual bap: one paw out to the side, knocking something off the ledge."""
    g.ellipse(CX, 26.5, 6.6, 5.4, "body")
    g.ellipse(CX, 26, 3, 3.6, "chest")
    g.rect(CX - 4, 28, CX - 2, GROUND - 1, "leg")
    g.rect(CX - 5, GROUND, CX - 2, GROUND, "paw")
    g.line([(CX - 5, 31), (CX - 9, 31), (CX - 12, 29), (CX - 13, 26)], "tail", 2)
    p = cat_head(g, 14, big_ears)
    if frame % 2 == 0:  # paw raised, winding up
        g.line([(CX + 3, 28), (CX + 7, 24), (CX + 10, 21)], "leg", 3)
        g.rect(CX + 10, 19, CX + 12, 21, "paw")
    else:  # bap
        g.line([(CX + 3, 28), (CX + 9, 28), (CX + 14, 29)], "leg", 3)
        g.rect(CX + 14, 28, CX + 16, 30, "paw")
    return p


def cat_eat(g, frame=0, big_ears=False):
    """Head down in the bowl, eyes shut, bobbing."""
    g.ellipse(CX, 26.5, 6.6, 5.4, "body")
    g.ellipse(CX, 26, 3, 3.6, "chest")
    g.rect(CX - 4, 28, CX - 2, GROUND - 1, "leg")
    g.rect(CX + 2, 28, CX + 4, GROUND - 1, "leg")
    g.line([(CX + 5, 31), (CX + 9, 30), (CX + 11, 27), (CX + 12 - frame, 24)], "tail", 2)
    p = cat_head(g, 19 + frame * 0.8, big_ears)
    return p | {"closed": True, "nomouth": True}


def cat_lick(g, frame=0, big_ears=False):
    """Grooming: paw up to the mouth, eyes shut, tongue out."""
    g.ellipse(CX, 26.5, 6.6, 5.4, "body")
    g.ellipse(CX, 26, 3, 3.6, "chest")
    g.rect(CX - 4, 28, CX - 2, GROUND - 1, "leg")
    g.rect(CX - 5, GROUND, CX - 2, GROUND, "paw")
    g.line([(CX + 5, 31), (CX + 9, 31), (CX + 12, 29), (CX + 13, 26)], "tail", 2)
    p = cat_head(g, 14, big_ears)
    hy = p["head_cy"]
    lift = 0 if frame % 2 == 0 else 2
    g.line([(CX + 3, 29), (CX + 3, 24), (CX + 1, hy + 5 + lift)], "leg", 3)
    g.rect(CX - 1, hy + 3 + lift, CX + 2, hy + 5 + lift, "paw")
    return p | {"closed": True, "lick": frame % 2 == 0, "nomouth": True}


def cat_stand(g, frame=0, big_ears=False):
    """Standing on four legs, facing you. Frames 0-3 walk by lifting diagonal pairs."""
    bob = 1 if frame % 2 else 0
    lift = [(0, 0, 0, 0), (2, 0, 0, 2), (0, 0, 0, 0), (0, 2, 2, 0)][frame % 4]
    g.ellipse(CX, 22 + bob, 8.6, 5.6, "body")
    g.ellipse(CX, 22 + bob, 3, 4, "chest")
    xs = [CX - 9, CX - 5, CX + 3, CX + 7]  # back-left, front-left, front-right, back-right
    tops = [23, 25, 25, 23]
    for i, x in enumerate(xs):
        bottom = GROUND - lift[i]
        g.rect(x, tops[i] + bob, x + 1 + (i in (1, 2)), bottom - 1, "leg" if i in (1, 2) else "backleg")
        g.rect(x, bottom, x + 1 + (i in (1, 2)), bottom, "paw")
    sway = [(0, 0), (1, -1), (0, 0), (-1, -1)][frame % 4]
    g.line([(CX + 7, 19 + bob), (CX + 11, 15), (CX + 12 + sway[0], 10 + sway[1]), (CX + 10 + sway[0], 7)], "tail", 2)
    return cat_head(g, 12 + bob, big_ears)


def cat_loaf(g, frame=0, big_ears=False):
    breathe = 0.6 if frame % 2 else 0.0
    g.ellipse(CX, 27 - breathe / 2, 11.5, 4.8 + breathe, "body")
    g.ellipse(CX, 28, 3.5, 2.5, "chest")
    g.line([(CX - 11, 30), (CX - 6, 32), (CX + 2, 32), (CX + 7, 31)], "tail", 2)
    p = cat_head(g, 20.5, big_ears, ear_drop=0.8)
    p["closed"] = True
    return p


def cat_splat(g, frame=0, big_ears=True):
    """Ivan's move: flopped flat, front paws out, one reaching for something."""
    g.ellipse(CX, 28, 12.5, 3.6, "body")
    g.ellipse(CX, 28, 3.5, 2.5, "chest")
    reach = 3 if frame % 2 else 0
    g.rect(CX - 11, 30, CX - 5, 31, "leg")
    g.rect(CX + 5, 30 - reach // 3, CX + 11 + reach, 31 - reach // 3, "leg")
    g.rect(CX - 13, 30, CX - 11, 31, "paw")
    g.rect(CX + 11 + reach, 30 - reach // 3, CX + 13 + reach, 31 - reach // 3, "paw")
    g.line([(CX + 10, 27), (CX + 14, 24), (CX + 15, 20)], "tail", 2)
    return cat_head(g, 21, big_ears)


# ---------------------------------------------------------------- dog


def dog_head(g, cy, flap=0):
    g.ellipse(CX, cy, 8.4, 7.4, "head")
    g.ellipse(CX, cy + 4.6, 3.8, 3.0, "snout")
    # floppy ears hanging at the sides
    g.poly([(CX - 7.4, cy - 5.2), (CX - 4.0, cy - 6.4), (CX - 6.0 - flap, cy + 6.0), (CX - 10 - flap, cy + 4.4)], "ear")
    g.poly([(CX + 7.4, cy - 5.2), (CX + 4.0, cy - 6.4), (CX + 6.0 + flap, cy + 6.0), (CX + 10 + flap, cy + 4.4)], "ear")
    return {"head_cy": cy + 1, "eyes_y": int(cy), "dog": True}


def dog_tail(g, frame, base=(CX + 7, 27)):
    bx, by = base
    tips = [[(bx + 4, by - 3), (bx + 6, by - 8), (bx + 5, by - 11)],
            [(bx + 3, by - 4), (bx + 3, by - 9), (bx + 1, by - 12)],
            [(bx + 5, by - 2), (bx + 8, by - 6), (bx + 9, by - 10)]]
    g.line([(bx, by), *tips[frame % 3]], "tail", 2)


def dog_sit(g, frame=0, rope=False, tongue=False):
    dog_tail(g, frame)
    g.ellipse(CX, 26.5, 7, 5.4, "body")
    g.ellipse(CX, 26, 3.2, 3.6, "chest")
    g.rect(CX - 5, 28, CX - 3, GROUND - 1, "leg")
    g.rect(CX + 3, 28, CX + 5, GROUND - 1, "leg")
    g.rect(CX - 6, GROUND, CX - 3, GROUND, "paw")
    g.rect(CX + 3, GROUND, CX + 6, GROUND, "paw")
    p = dog_head(g, 13, flap=frame % 2)
    p["rope"] = rope
    p["tongue"] = tongue
    return p


def dog_happy(g, frame=0):
    """Tail going, tongue out, eyes squeezed shut, a little bounce."""
    bounce = frame % 2
    dog_tail(g, frame * 2)
    g.ellipse(CX, 26.5 - bounce * 0.5, 7, 5.4, "body")
    g.ellipse(CX, 26, 3.2, 3.6, "chest")
    g.rect(CX - 5, 28, CX - 3, GROUND - 1, "leg")
    g.rect(CX + 3, 28, CX + 5, GROUND - 1, "leg")
    g.rect(CX - 6, GROUND, CX - 3, GROUND, "paw")
    g.rect(CX + 3, GROUND, CX + 6, GROUND, "paw")
    p = dog_head(g, 13 - bounce, flap=1 + frame % 2)
    return p | {"happy": True, "bigtongue": True}


def dog_eat(g, frame=0):
    """Face in the bowl, tail going."""
    dog_tail(g, frame)
    g.ellipse(CX, 26.5, 7, 5.4, "body")
    g.rect(CX - 5, 28, CX - 3, GROUND - 1, "leg")
    g.rect(CX + 3, 28, CX + 5, GROUND - 1, "leg")
    p = dog_head(g, 18 + frame * 0.8, flap=1)
    return p | {"closed": True}


def dog_stand(g, frame=0, rope=False):
    bob = 1 if frame % 2 else 0
    lift = [(0, 0, 0, 0), (2, 0, 0, 2), (0, 0, 0, 0), (0, 2, 2, 0)][frame % 4]
    dog_tail(g, frame, base=(CX + 7, 20 + bob))
    g.ellipse(CX, 22 + bob, 9.4, 5.8, "body")
    g.ellipse(CX, 22 + bob, 3.4, 4.2, "chest")
    xs = [CX - 10, CX - 6, CX + 4, CX + 8]
    tops = [23, 25, 25, 23]
    for i, x in enumerate(xs):
        bottom = GROUND - lift[i]
        g.rect(x, tops[i] + bob, x + 1 + (i in (1, 2)), bottom - 1, "leg" if i in (1, 2) else "backleg")
        g.rect(x, bottom, x + 1 + (i in (1, 2)), bottom, "paw")
    p = dog_head(g, 11 + bob, flap=1 + frame % 2)
    p["rope"] = rope
    p["tongue"] = not rope and frame % 2 == 1
    return p


def dog_sleep(g, frame=0):
    breathe = 0.6 if frame % 2 else 0.0
    g.ellipse(CX, 27.5 - breathe / 2, 12.5, 4.6 + breathe, "body")
    g.rect(CX - 8, 30, CX - 2, 31, "leg")
    g.rect(CX + 2, 30, CX + 8, 31, "leg")
    g.rect(CX - 9, 31, CX - 6, 32, "paw")
    g.rect(CX + 6, 31, CX + 9, 32, "paw")
    p = dog_head(g, 22.5, flap=1)
    p["closed"] = True
    return p


# ---------------------------------------------------------------- coats

PETS = {
    "thea": {"kind": "cat", "base": "#5e5244", "mid": "#76695a", "dark": "#0d0b0a", "light": "#e6d8c2", "outline": "#050404",
             "nose": "#e39a86", "eye": "#dca23b", "pupil": "#17130f", "inner": "#e9a9a1", "earback": "#3a322a", "mouth": "#c25a5a"},
    "ivan": {"kind": "cat", "base": "#b2a690", "mid": "#c6bba6", "dark": "#665b4c", "light": "#f1ebe0", "outline": "#2f2922",
             "nose": "#e4a392", "eye": "#7fb24a", "pupil": "#1c180f", "inner": "#ecb2a8", "earback": "#6a5e4e", "mouth": "#c96060"},
    "kai": {"kind": "dog", "base": "#262221", "mid": "#3a302b", "sheen": "#5e4739", "dark": "#121010", "light": "#4b423d", "face": "#332d2a", "rim": "#54483f",
            "outline": "#060505", "nose": "#0c0b0b", "eye": "#82522a", "pupil": "#1b1009", "tongue": "#e37a86",
            "rope": "#d3262b", "rope2": "#98161b", "rope3": "#f15a5d"},
}


def paint(name: str, g: Grid, p: dict, look: int = 0):
    pal = {k: rgba(v) for k, v in PETS[name].items() if k != "kind"}
    cat = PETS[name]["kind"] == "cat"
    hy = p["head_cy"]
    for (x, y), t in g.tag.items():
        col = pal["base"]
        side = abs(x + 0.5 - CX)
        if cat:
            if t in ("muzzle", "chest"):
                col = pal["light"]
            elif t == "paw":
                col = pal["light"] if name == "ivan" else pal["mid"]
            elif t == "ear":
                col = pal["earback"]
            elif t == "backleg":
                col = pal["dark"] if y % 3 == 0 else pal["mid"]
            elif t == "leg":
                col = pal["dark"] if y % 3 == 0 and name == "thea" else (pal["dark"] if y % 4 == 0 else pal["base"])
            elif t == "tail":
                col = pal["dark"] if (x + y) % 4 < (2 if name == "thea" else 1) else pal["base"]
            elif t == "body":
                if name == "thea":
                    # bold bands that curve round the sides, darker towards the edges
                    if side > 3 and (y + int(side / 3)) % 3 != 1:
                        col = pal["dark"]
                    elif side > 6 and (y + x) % 2 == 0:
                        col = pal["dark"]
                else:
                    if side > 3.5 and (y + int(side / 2)) % 4 == 0 and (x * 7 + y) % 3:
                        col = pal["dark"]
            elif t == "head":
                # tabby lines on the cheeks
                pass
        else:
            if t in ("head", "body") and _rim(g, x, y):
                col = pal["sheen"]
            elif t == "ear":
                col = pal["dark"]
            elif t == "snout":
                col = pal["light"]
            elif t == "head" and side < 5 and abs(y - (hy - 1)) <= 2:
                col = pal["face"]
            elif t in ("paw", "backleg"):
                col = pal["dark"]
            elif t == "chest":
                col = pal["light"]
        g.color[(x, y)] = col

    # outline round the silhouette
    filled = set(g.tag)
    for x, y in list(filled):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in filled and 0 <= q[0] < W and 0 <= q[1] < H:
                g.color[q] = pal["outline"]

    face(name, g, p, pal, look)


def _rim(g, x, y):
    """Top edge of the silhouette: where the light catches Kai's coat."""
    return (x, y - 1) not in g.tag


def face(name, g, p, pal, look):
    cat = PETS[name]["kind"] == "cat"
    hy = int(p["head_cy"])
    ey = p["eyes_y"]
    set_ = lambda x, y, c: g.color.__setitem__((int(x), int(y)), c)  # noqa: E731
    if cat:
        # forehead M
        for x, y in [(CX - 3, hy - 4), (CX - 2, hy - 3), (CX - 1, hy - 4), (CX, hy - 3), (CX + 1, hy - 4), (CX + 2, hy - 3), (CX - 1, hy - 5), (CX, hy - 5)]:
            if (x, y) in g.tag:
                set_(x, y, pal["dark"])
        # inner ears
        tip = int(p["ear_tip"])
        for k, w in (() if p.get("flat") else ((3, 1), (4, 2), (5, 2))):
            for j in range(w):
                set_(CX - 6 + j, tip + k, pal["inner"])
                set_(CX + 5 - j, tip + k, pal["inner"])
        eyes = [(CX - 7, ey - 2), (CX + 3, ey - 2)]
        if p.get("closed"):
            for x, y in eyes:
                set_(x, y + 2, pal["dark"])
                set_(x + 1, y + 3, pal["dark"])
                set_(x + 2, y + 3, pal["dark"])
                set_(x + 3, y + 2, pal["dark"])
        else:
            for x, y in eyes:
                for dx in range(4):
                    for dy in range(4):
                        if (dx, dy) in ((0, 0), (3, 0), (0, 3), (3, 3)):
                            continue
                        set_(x + dx, y + dy, pal["eye"])
                pc = x + 1 + max(-1, min(1, look))
                for dy in (1, 2):
                    for w in (0, 1):
                        if 0 <= pc + w - x <= 3:
                            set_(pc + w, y + dy, pal["pupil"])
                set_(pc + (1 if look < 0 else 0), y + 1, (255, 255, 255, 255))
                set_(x - 1 if x < CX else x + 4, y + 3, pal["dark"])  # eyeliner flick
                if p.get("angry"):
                    # narrowed, glaring: lid comes down at a slant, pupil a thin slit
                    left = x < CX
                    for dx in range(4):
                        set_(x + dx, y, pal["dark"])
                    set_(x + (3 if left else 0), y + 1, pal["dark"])
                    set_(x + (2 if left else 1), y - 1, pal["dark"])
                    set_(x + (3 if left else 0), y - 1, pal["dark"])
                    for dy in (1, 2, 3):
                        for dx in range(4):
                            if g.color.get((x + dx, y + dy)) == pal["pupil"]:
                                set_(x + dx, y + dy, pal["eye"])
                    set_(x + (1 if left else 2), y + 1, pal["pupil"])
                    set_(x + (1 if left else 2), y + 2, pal["pupil"])
        set_(CX - 1, hy + 2, pal["nose"])
        set_(CX, hy + 2, pal["nose"])
        # blush
        for bx in (CX - 8, CX - 7, CX + 6, CX + 7):
            set_(bx, hy + 2, (240, 150, 150, 255))
        if p.get("hiss"):
            for y in (hy + 3, hy + 4, hy + 5):
                for dx in range(-3, 3):
                    set_(CX + dx, y, pal["mouth"])
            for dx in range(-2, 2):
                set_(CX + dx, hy + 6, pal["mouth"])
            for fx_, fy in ((CX - 3, hy + 3), (CX - 3, hy + 4), (CX + 2, hy + 3), (CX + 2, hy + 4)):
                set_(fx_, fy, (252, 252, 248, 255))  # fangs
        elif p.get("nomouth"):
            if p.get("lick"):
                set_(CX - 2, hy + 4, (232, 112, 132, 255))
                set_(CX - 2, hy + 5, (232, 112, 132, 255))
        elif p.get("meow"):
            for dx in (-2, -1, 0, 1):
                set_(CX + dx, hy + 4, pal["mouth"])
            set_(CX - 1, hy + 5, pal["mouth"])
            set_(CX, hy + 5, pal["mouth"])
            set_(CX - 2, hy + 4, (250, 250, 245, 255))  # fang
        else:
            # the little "w" mouth
            for x, y in ((CX - 3, hy + 3), (CX - 2, hy + 4), (CX - 1, hy + 3), (CX, hy + 3), (CX + 1, hy + 4), (CX + 2, hy + 3)):
                set_(x, y, pal["dark"])
        # whiskers
        for s in (-1, 1):
            for k in range(2):
                x = CX + s * (6 + k) - (1 if s > 0 else 0)
                set_(x, hy + 4 - (1 if p.get("angry") else 0), (245, 240, 232, 255))
        for cx_, cy_ in p.get("claws", []):
            set_(cx_, cy_, (252, 252, 248, 255))
        if p.get("slash"):
            for k in range(3):
                for j in range(4):
                    set_(CX + 14 + k * 2 - j // 2, hy - 6 + j + k, (255, 255, 255, 230))
    else:
        eyes = [(CX - 5, ey - 1), (CX + 2, ey - 1)]
        if p.get("happy"):
            for x, y in eyes:
                for px_, py_ in ((x - 1, y + 2), (x, y + 1), (x + 1, y), (x + 2, y + 1), (x + 3, y + 2)):
                    set_(px_, py_, (170, 146, 130, 255))
        elif p.get("closed"):
            for x, y in eyes:
                set_(x, y + 1, pal["sheen"])
                set_(x + 1, y + 1, pal["sheen"])
        else:
            for x, y in eyes:
                for dx in (-1, 3):
                    for dy in range(3):
                        set_(x + dx, y + dy, pal["rim"])
                for dx in range(3):
                    set_(x + dx, y - 1, pal["rim"])
                    for dy in range(3):
                        set_(x + dx, y + dy, pal["eye"])
                pc = x + 1 + max(-1, min(1, look))
                set_(pc, y + 1, pal["pupil"])
                set_(pc, y + 2, pal["pupil"])
                set_(x + (2 if look < 0 else 0), y, (255, 255, 255, 255))
            # eyebrow sheen dots: puppy eyebrows
            for dx in (-5, -4, 3, 4):
                set_(CX + dx - (0 if dx < 0 else 0), ey - 3, pal["sheen"])
        for bx in (CX - 8, CX - 7, CX + 6, CX + 7):
            set_(bx, hy + 1, (176, 104, 110, 255))
        # nose
        for dx in (-2, -1, 0, 1):
            set_(CX + dx, hy + 2, pal["nose"])
        set_(CX - 1, hy + 3, pal["nose"])
        set_(CX, hy + 3, pal["nose"])
        for dx in (-3, 2):
            set_(CX + dx, hy + 2, pal["nose"])
        set_(CX - 2, hy + 2, (150, 140, 134, 255))  # shine on the nose
        set_(CX - 1, hy + 4, pal["rim"])
        set_(CX, hy + 4, pal["rim"])
        for dx in (-3, -2, 1, 2):
            set_(CX + dx, hy + 5, pal["rim"])
        if p.get("tongue") or p.get("bigtongue"):
            rows = (6, 7, 8, 9) if p.get("bigtongue") else (6, 7)
            for dy in rows:
                set_(CX - 1, hy + dy, pal["tongue"])
                set_(CX, hy + dy, pal["tongue"])
            if p.get("bigtongue"):
                for dy in (6, 7, 8):
                    set_(CX - 2, hy + dy, pal["tongue"])
                    set_(CX + 1, hy + dy, pal["tongue"])
                set_(CX - 1, hy + 7, (196, 84, 104, 255))  # the middle line of the tongue
                set_(CX - 1, hy + 8, (196, 84, 104, 255))
        if p.get("rope"):
            cy = hy + 8
            for a in range(0, 360, 8):
                for r in (2.6, 1.9):
                    x = CX - 0.5 + r * 1.6 * math.cos(math.radians(a))
                    y = cy + r * math.sin(math.radians(a))
                    k = (a // 24) % 3
                    set_(round(x), round(y), [pal["rope"], pal["rope2"], pal["rope3"]][k])


def poses(name: str):
    if PETS[name]["kind"] == "cat":
        big = name == "ivan"
        p = {
            "sit": [lambda g, i=i: cat_sit(g, i, big) for i in range(2)],
            "blink": [lambda g: cat_sit(g, 0, big) | {"closed": True}],
            "walk": [lambda g, i=i: cat_stand(g, i, big) for i in range(4)],
            "sleep": [lambda g, i=i: cat_loaf(g, i, big) for i in range(2)],
            "meow": [lambda g: cat_sit(g, 0, big) | {"meow": True}],
            "lick": [lambda g, i=i: cat_lick(g, i, big) for i in range(2)],
            "hiss": [lambda g, i=i: cat_hiss(g, i, big) for i in range(2)],
            "swipe": [lambda g, i=i: cat_swipe(g, i, big) for i in range(2)],
            "bap": [lambda g, i=i: cat_bap(g, i, big) for i in range(2)],
            "eat": [lambda g, i=i: cat_eat(g, i, big) for i in range(2)],
        }
        if big:
            p["splat"] = [lambda g, i=i: cat_splat(g, i) for i in range(2)]
        return p
    return {
        "sit": [lambda g, i=i: dog_sit(g, i) for i in range(3)],
        "blink": [lambda g: dog_sit(g, 0) | {"closed": True}],
        "pant": [lambda g, i=i: dog_sit(g, i, tongue=True) for i in range(3)],
        "walk": [lambda g, i=i: dog_stand(g, i) for i in range(4)],
        "sleep": [lambda g, i=i: dog_sleep(g, i) for i in range(2)],
        "tug": [lambda g, i=i: dog_sit(g, i, rope=True) for i in range(3)],
        "carry": [lambda g, i=i: dog_stand(g, i, rope=True) for i in range(4)],
        "happy": [lambda g, i=i: dog_happy(g, i) for i in range(3)],
        "eat": [lambda g, i=i: dog_eat(g, i) for i in range(2)],
    }


PROPS = {
    # little things for the cats to knock off the top of the screen
    "pencil": [
        "..............",
        "............kk",
        "KPPPPPPPPPPPkG",
        "KPPpPPpPPpPPkG",
        "KppppppppppPkG",
        "............kk",
    ],
    "mug": [
        "..s.s....",
        ".s.s.....",
        "OWWWWWO..",
        "OWccccWOO",
        "OWWWWWWOW",
        "OWWRRWWOO",
        "OWWWWWWO.",
        ".OWWWWO..",
        "..OOOO...",
    ],
    "yarn": [
        "..OOOO...",
        ".ORrRrO..",
        "ORrRRrRO.",
        "ORRrRRrO.",
        "OrRRrRRO.",
        ".ORrRRO..",
        "..OOOO.rr",
        "........r",
    ],
}
PROP_COLORS = {
    "K": (60, 50, 50, 255), "P": (246, 160, 196, 255), "p": (220, 120, 162, 255), "k": (230, 210, 180, 255), "G": (90, 90, 96, 255),
    "O": (40, 32, 30, 255), "W": (248, 244, 236, 255), "c": (120, 76, 48, 255), "R": (214, 64, 74, 255), "r": (170, 40, 52, 255),
    "s": (220, 220, 220, 160),
}


def bowl(rim, body, food, level):
    """A 16 x 9 bowl, with `level` (0-3) of fish or a bone in it."""
    img = Image.new("RGBA", (16, 9), (0, 0, 0, 0))
    o = (40, 32, 30, 255)
    rows = ["................", "................", "................", "................",
            ".oooooooooooooo.", "orrrrrrrrrrrrrro", ".obbbbbbbbbbbbo.", "..obbbbbbbbbbo..", "...oooooooooo..."]
    pal = {"o": o, "r": rim, "b": body}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in pal:
                img.putpixel((x, y), pal[ch])
    if food == "fish":
        fish = [(2, 3, [".gggg.t", "gGgGgtt", ".gggg.t"]), (8, 2, ["t.gggg.", "ttgGgGg", "t.gggg."])]
        cols = {"g": (150, 176, 196, 255), "G": (98, 126, 150, 255), "t": (120, 150, 172, 255)}
        shown = fish[: 2 if level >= 2 else 1] if level >= 1 else []
        for ox, oy, shape in shown:
            for y, row in enumerate(shape):
                for x, ch in enumerate(row):
                    if ch in cols and 0 <= oy + y < 5:
                        img.putpixel((ox + x, oy + y), cols[ch])
        if level == 1:
            for x in range(9, 13):
                img.putpixel((x, 4), (150, 176, 196, 255))
    else:
        bone = ["w.......w", "wwwwwwwww", "w.......w"]
        if level >= 1:
            width = {3: 9, 2: 6, 1: 3}[level]
            for y, row in enumerate(bone):
                for x, ch in enumerate(row[:width]):
                    if ch == "w":
                        img.putpixel((3 + x, 2 + y), (246, 240, 226, 255))
    return img


def props():
    d = OUT / "props"
    d.mkdir(parents=True, exist_ok=True)
    for level in range(4):
        bowl((240, 150, 190, 255), (214, 110, 160, 255), "fish", level).save(d / f"fish_{level}.png")
        bowl((120, 170, 230, 255), (70, 120, 200, 255), "bone", level).save(d / f"bone_{level}.png")
    for name, rows in PROPS.items():
        w = max(len(r) for r in rows)
        img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in PROP_COLORS:
                    img.putpixel((x, y), PROP_COLORS[ch])
        img.save(d / f"{name}.png")


def render(g: Grid) -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for (x, y), col in g.color.items():
        if 0 <= x < W and 0 <= y < H:
            img.putpixel((x, y), col)
    return img


def build():
    sheets = {}
    for name in PETS:
        d = OUT / name
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.png"):
            old.unlink()
        sheets[name] = {}
        for pose, frames in poses(name).items():
            imgs = []
            for i, f in enumerate(frames):
                looks = (-1, 0, 1) if pose == "sit" and i == 0 else (0,)
                for look in looks:
                    g = Grid()
                    parts = f(g)
                    paint(name, g, parts, look)
                    img = render(g)
                    suffix = {-1: "_left", 0: "", 1: "_right"}[look]
                    img.save(d / f"{pose}_{i}{suffix}.png")
                    if look == 0:
                        imgs.append((f"{pose} {i + 1}", img))
                    else:
                        imgs.append((f"look {'left' if look < 0 else 'right'}", img))
            sheets[name][pose] = imgs
    return sheets


def preview(sheets, scale=7, path=OUT / "preview.png"):
    per_row = 8
    cw, ch = W * scale + 14, H * scale + 34
    try:
        big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 24)
        small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 14)
    except OSError:
        big = small = ImageFont.load_default()
    blocks = []
    for name, s in sheets.items():
        frames = [f for ims in s.values() for f in ims]
        rows = math.ceil(len(frames) / per_row)
        b = Image.new("RGBA", (cw * per_row + 20, 44 + rows * ch), (245, 243, 238, 255))
        d = ImageDraw.Draw(b)
        d.text((12, 10), name.upper(), fill=(20, 20, 20), font=big)
        for k, (label, im) in enumerate(frames):
            x = 10 + (k % per_row) * cw
            y = 44 + (k // per_row) * ch
            d.rectangle([x, y, x + W * scale, y + H * scale], fill=(226, 223, 214))
            b.alpha_composite(im.resize((W * scale, H * scale), Image.NEAREST), (x, y))
            d.text((x, y + H * scale + 5), label, fill=(80, 80, 80), font=small)
        blocks.append(b)
    total = Image.new("RGBA", (blocks[0].width, sum(b.height + 10 for b in blocks)), (255, 255, 255, 255))
    y = 0
    for b in blocks:
        total.alpha_composite(b, (0, y))
        y += b.height + 10
    total.save(path)
    return path


if __name__ == "__main__":
    props()
    print(preview(build()))
