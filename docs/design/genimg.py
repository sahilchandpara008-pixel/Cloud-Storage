import math, random, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def grad(w, h, stops):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                d.line([(0, y), (w, y)], fill=lerp(c0, c1, (t - p0) / max(p1 - p0, 1e-6)))
                break
    return im


def glow(im, xy, r, color, strength=0.9):
    layer = Image.new("RGB", im.size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = xy
    d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.6))
    return Image.blend(im, Image.eval(Image.merge("RGB", [Image.eval(c, lambda v: v) for c in layer.split()]), lambda v: v), 0).__class__.__call__ if False else add(im, layer, strength)


def add(a, b, s=1.0):
    from PIL import ImageChops
    b = Image.eval(b, lambda v: int(v * s))
    return ImageChops.add(a, b)


def mountains(d, w, h, base, color, rnd, peaks=5, amp=0.25):
    pts = [(0, h)]
    n = peaks * 2
    for i in range(n + 1):
        x = w * i / n
        y = base - (amp * h * (rnd.random() * 0.7 + 0.3) if i % 2 else amp * h * 0.15 * rnd.random())
        pts.append((x, y))
    pts.append((w, h))
    d.polygon(pts, fill=color)


def skyline(d, w, h, base, color, rnd, lit=None):
    x = 0
    while x < w:
        bw = rnd.randint(int(w * 0.06), int(w * 0.14))
        bh = rnd.randint(int(h * 0.12), int(h * 0.42))
        d.rectangle([x, base - bh, x + bw, h], fill=color)
        if lit:
            for wy in range(int(base - bh + 8), int(base), 14):
                for wx in range(x + 5, x + bw - 5, 10):
                    if rnd.random() < 0.35:
                        d.rectangle([wx, wy, wx + 4, wy + 6], fill=lit)
        x += bw + rnd.randint(0, 6)


def stars(d, w, h, rnd, n=120, maxy=0.7):
    for _ in range(n):
        x, y = rnd.random() * w, rnd.random() * h * maxy
        r = rnd.choice([0.6, 0.8, 1.2, 1.6])
        c = rnd.randint(170, 255)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(c, c, c))


def scene(kind, w, h, seed):
    rnd = random.Random(seed)
    if kind == "city":
        im = grad(w, h, [(0, (12, 10, 40)), (0.55, (90, 30, 90)), (0.8, (255, 110, 60)), (1, (30, 10, 30))])
        im = add(im, blob(w, h, (w * 0.5, h * 0.62), w * 0.35, (255, 120, 40)), 0.8)
        d = ImageDraw.Draw(im)
        stars(d, w, h, rnd, 60, 0.4)
        skyline(d, w, h, h * 0.86, (35, 15, 40), rnd)
        skyline(d, w, h, h * 0.95, (12, 8, 18), rnd, lit=(255, 190, 90))
    elif kind == "desert":
        im = grad(w, h, [(0, (255, 170, 90)), (0.5, (255, 110, 60)), (0.62, (200, 70, 50)), (1, (60, 20, 20))])
        im = add(im, blob(w, h, (w * 0.62, h * 0.5), w * 0.22, (255, 240, 180)), 1.0)
        d = ImageDraw.Draw(im)
        for i, c in enumerate([(170, 70, 45), (120, 45, 35), (70, 25, 25)]):
            base = h * (0.66 + i * 0.1)
            pts = [(0, h)] + [(x, base + math.sin(x / w * math.pi * (1.2 + i) + seed) * h * 0.04) for x in range(0, w + 1, 6)] + [(w, h)]
            d.polygon(pts, fill=c)
    elif kind == "ocean":
        im = grad(w, h, [(0, (10, 30, 70)), (0.5, (30, 110, 160)), (0.56, (190, 230, 240)), (0.58, (20, 80, 130)), (1, (5, 20, 45))])
        im = add(im, blob(w, h, (w * 0.4, h * 0.52), w * 0.3, (200, 240, 255)), 0.6)
        d = ImageDraw.Draw(im)
        for y in range(int(h * 0.6), h, 10):
            for x in range(0, w, 30):
                if rnd.random() < 0.5:
                    d.line([(x + rnd.randint(0, 10), y), (x + rnd.randint(14, 26), y)], fill=(120, 190, 220), width=1)
    elif kind == "mountain":
        im = grad(w, h, [(0, (25, 35, 70)), (0.5, (110, 130, 170)), (0.75, (230, 200, 190)), (1, (230, 200, 190))])
        d = ImageDraw.Draw(im)
        stars(d, w, h, rnd, 40, 0.35)
        mountains(d, w, h, h * 0.68, (110, 120, 155), rnd, 4, 0.3)
        mountains(d, w, h, h * 0.8, (60, 65, 95), rnd, 5, 0.25)
        mountains(d, w, h, h * 0.93, (22, 24, 40), rnd, 7, 0.18)
    elif kind == "forest":
        im = grad(w, h, [(0, (20, 60, 50)), (0.5, (120, 170, 120)), (1, (10, 30, 20))])
        im = add(im, blob(w, h, (w * 0.5, h * 0.35), w * 0.3, (255, 240, 180)), 0.7)
        d = ImageDraw.Draw(im)
        for layer, c in enumerate([(50, 90, 70), (25, 55, 40), (8, 25, 16)]):
            for _ in range(14):
                x = rnd.random() * w
                th = h * (0.25 + 0.12 * layer) * (0.7 + rnd.random() * 0.5)
                base = h * (0.75 + layer * 0.1)
                tw = th * 0.32
                d.polygon([(x, base - th), (x - tw, base), (x + tw, base)], fill=c)
            d.rectangle([0, h * (0.75 + layer * 0.1), w, h], fill=c)
    elif kind == "space":
        im = grad(w, h, [(0, (5, 5, 15)), (1, (20, 10, 40))])
        im = add(im, blob(w, h, (w * 0.3, h * 0.3), w * 0.5, (120, 40, 160)), 0.6)
        im = add(im, blob(w, h, (w * 0.8, h * 0.6), w * 0.4, (30, 80, 170)), 0.6)
        d = ImageDraw.Draw(im)
        stars(d, w, h, rnd, 220, 1.0)
        cx, cy, r = w * 0.62, h * 0.56, w * 0.28
        pl = grad(int(2 * r), int(2 * r), [(0, (255, 160, 90)), (1, (120, 40, 60))])
        mask = Image.new("L", pl.size, 0)
        ImageDraw.Draw(mask).ellipse([0, 0, 2 * r - 1, 2 * r - 1], fill=255)
        im.paste(pl, (int(cx - r), int(cy - r)), mask)
        d.ellipse([cx - r * 1.7, cy - r * 0.25, cx + r * 1.7, cy + r * 0.25], outline=(230, 200, 170), width=3)
    elif kind == "road":
        im = grad(w, h, [(0, (40, 20, 70)), (0.45, (240, 100, 120)), (0.55, (255, 180, 110)), (0.56, (30, 25, 40)), (1, (15, 12, 20))])
        d = ImageDraw.Draw(im)
        mountains(d, w, int(h * 0.56) + 2, h * 0.56, (60, 30, 70), rnd, 6, 0.08)
        hz = h * 0.56
        d.polygon([(w * 0.48, hz), (w * 0.52, hz), (w * 0.95, h), (w * 0.05, h)], fill=(45, 40, 55))
        for i in range(8):
            t0, t1 = (i / 8) ** 2, ((i + 0.5) / 8) ** 2
            y0, y1 = hz + (h - hz) * t0, hz + (h - hz) * t1
            d.polygon([(w / 2 - 1 - 6 * t0, y0), (w / 2 + 1 + 6 * t0, y0), (w / 2 + 1 + 6 * t1, y1), (w / 2 - 1 - 6 * t1, y1)], fill=(255, 210, 120))
    elif kind == "comedy":
        im = grad(w, h, [(0, (255, 200, 60)), (1, (255, 120, 40))])
        d = ImageDraw.Draw(im)
        cx, cy = w / 2, h * 0.5
        for i in range(24):
            a0 = i / 24 * 2 * math.pi
            a1 = (i + 0.5) / 24 * 2 * math.pi
            R = max(w, h)
            if i % 2 == 0:
                d.polygon([(cx, cy), (cx + R * math.cos(a0), cy + R * math.sin(a0)), (cx + R * math.cos(a1), cy + R * math.sin(a1))], fill=(255, 225, 110))
        r = w * 0.2
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(30, 20, 20))
        d.ellipse([cx - r * 0.45, cy - r * 0.35, cx - r * 0.15, cy - r * 0.05], fill=(255, 220, 90))
        d.ellipse([cx + r * 0.15, cy - r * 0.35, cx + r * 0.45, cy - r * 0.05], fill=(255, 220, 90))
        d.chord([cx - r * 0.55, cy - r * 0.2, cx + r * 0.55, cy + r * 0.6], 0, 180, fill=(255, 220, 90))
    elif kind == "music":
        im = grad(w, h, [(0, (20, 10, 50)), (1, (60, 10, 60))])
        im = add(im, blob(w, h, (w * 0.5, h * 0.5), w * 0.45, (255, 60, 140)), 0.55)
        d = ImageDraw.Draw(im)
        n = 26
        for i in range(n):
            x = w * (i + 0.5) / n
            bh = h * (0.08 + 0.45 * abs(math.sin(i * 0.7 + seed)) * rnd.random() ** 0.3)
            d.rounded_rectangle([x - w / n * 0.3, h * 0.62 - bh, x + w / n * 0.3, h * 0.62 + bh * 0.4], radius=3, fill=(255, 150, 200))
    elif kind == "food":
        im = grad(w, h, [(0, (70, 35, 20)), (1, (30, 15, 10))])
        d = ImageDraw.Draw(im)
        cx, cy, r = w / 2, h * 0.52, min(w, h) * 0.34
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(235, 230, 220))
        d.ellipse([cx - r * 0.8, cy - r * 0.8, cx + r * 0.8, cy + r * 0.8], fill=(215, 120, 40))
        for _ in range(18):
            a, rr = rnd.random() * 6.28, rnd.random() * r * 0.65
            x, y = cx + rr * math.cos(a), cy + rr * math.sin(a)
            s = r * 0.08
            d.ellipse([x - s, y - s, x + s, y + s], fill=rnd.choice([(90, 160, 60), (200, 40, 30), (250, 210, 90)]))
    else:
        im = grad(w, h, [(0, (40, 40, 50)), (1, (10, 10, 12))])
    return im


def blob(w, h, xy, r, color):
    layer = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = xy
    d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return layer.filter(ImageFilter.GaussianBlur(r * 0.55))


def vignette(im, bottom=0.6):
    w, h = im.size
    shade = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(shade)
    for y in range(h):
        t = max(0, (y / h - (1 - bottom)) / bottom)
        d.line([(0, y), (w, y)], fill=int(235 * t ** 1.4))
    black = Image.new("RGB", (w, h), (8, 8, 10))
    return Image.composite(black, im, shade)


def title(im, text, sub=None, font=BOLD, size=None):
    w, h = im.size
    d = ImageDraw.Draw(im)
    size = size or int(w * 0.13)
    f = ImageFont.truetype(font, size)
    lines = text.split("\n")
    y = h * 0.93 - len(lines) * size * 1.05 - (size * 0.5 if sub else 0)
    for ln in lines:
        tw = d.textlength(ln, font=f)
        d.text(((w - tw) / 2 + 2, y + 2), ln, font=f, fill=(0, 0, 0))
        d.text(((w - tw) / 2, y), ln, font=f, fill=(250, 248, 244))
        y += size * 1.05
    if sub:
        fs = ImageFont.truetype(BOLD, int(size * 0.32))
        tw = d.textlength(sub, font=fs)
        d.text(((w - tw) / 2, y + size * 0.15), sub, font=fs, fill=(255, 160, 80))


posters = [
    ("p1", "city", "MIDNIGHT\nRUN", "A FLIXVAULT ORIGINAL", BOLD),
    ("p2", "desert", "DESERT\nLINE", "NEW SERIES", SERIF),
    ("p3", "ocean", "DEEP\nBLUE", "DOCUMENTARY", BOLD),
    ("p4", "mountain", "ECHO\nPEAK", "SEASON 2", SERIF),
    ("p5", "space", "DRIFT", "SCI-FI", BOLD),
    ("p6", "forest", "THE\nTRAIL", "ADVENTURE", SERIF),
    ("p7", "road", "LONG\nROAD", "ROAD TRIP", BOLD),
    ("p8", "music", "LOUD", "LIVE SESSIONS", BOLD),
]
for name, kind, t, s, f in posters:
    im = scene(kind, 400, 600, hash(name) % 1000)
    im = vignette(im, 0.45)
    title(im, t, s, f)
    im.save(f"{OUT}/{name}.jpg", quality=84)

# wide hero / thumbnails (no titles, the app overlays text)
wides = [("h1", "city"), ("t1", "mountain"), ("t2", "road"), ("t3", "ocean"), ("t4", "comedy"), ("t5", "food"), ("t6", "space"), ("t7", "desert")]
for name, kind in wides:
    w, h = (780, 520) if name == "h1" else (720, 405)
    im = scene(kind, w, h, hash(name) % 1000)
    if name == "h1":
        im = vignette(im, 0.55)
    im.save(f"{OUT}/{name}.jpg", quality=84)

# channel avatars
avatars = [("a1", "city"), ("a2", "road"), ("a3", "comedy"), ("a4", "music"), ("a5", "mountain"), ("a6", "food"), ("a7", "space"), ("a8", "forest")]
for name, kind in avatars:
    im = scene(kind, 300, 300, hash(name) % 1000).resize((160, 160), Image.LANCZOS)
    im.save(f"{OUT}/{name}.jpg", quality=85)
print("ok", sorted(os.listdir(OUT)))
