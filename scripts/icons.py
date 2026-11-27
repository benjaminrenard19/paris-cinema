#!/usr/bin/env python3
"""App icons in each of the app's colours (Settings › Colours), from the Sloth red icon.

Replaces the red background (and the ticket's notches) with the same top-to-bottom gradient in
another colour, keeping the anti-aliased edges, and writes one alternate icon set per colour:
ParisCinema/Assets.xcassets/AppIcon-<Name>.appiconset. The app switches to the icon of the
colour you pick (the nearest one for a colour from the colour wheel).

    python3 scripts/icons.py
"""
import json
import os
from collections import deque

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
ASSETS = os.path.join(ROOT, "ParisCinema", "Assets.xcassets")
SOURCE = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon.png")

# Same list as Theme.presets in Theme.swift. Sloth red is the main icon (AppIcon).
PRESETS = [
    ("Velvet", 0x6B1E3A), ("Popcorn", 0xD98200), ("Neon", 0xE0217A), ("Ocean", 0x1F5FBF),
    ("Forest", 0x1D7A4A), ("Violet", 0x6B3FD6), ("Graphite", 0x4A4A55),
]
RED = (163, 20, 47)
BOTTOM = 0.577          # the bottom row is this share of the top colour
TICKET = (255, 210, 63)


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def shade(c, y, size):
    f = 1 - (1 - BOTTOM) * y / (size - 1)
    return tuple(v * f for v in c)


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def background_mask(im):
    """1.0 where the pixel is background, a fraction on the soft edges, 0 elsewhere."""
    w, h = im.size
    px = im.load()
    alpha = [[0.0] * w for _ in range(h)]
    seen = [[False] * w for _ in range(h)]
    queue = deque([(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)])
    while queue:
        x, y = queue.popleft()
        if not (0 <= x < w and 0 <= y < h) or seen[y][x]:
            continue
        seen[y][x] = True
        p = px[x, y]
        bg = shade(RED, y, h)
        d = dist(p, bg)
        if d < 12:
            alpha[y][x] = 1.0
            queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
        else:
            # edge pixel: how much of it is background, between the red and the ticket's yellow
            alpha[y][x] = max(0.0, min(1.0, 1 - d / dist(TICKET, bg)))
    return alpha


def recolour(im, alpha, colour):
    w, h = im.size
    src = im.load()
    out = im.copy()
    dst = out.load()
    for y in range(h):
        old = shade(RED, y, h)
        new = shade(colour, y, h)
        for x in range(w):
            a = alpha[y][x]
            if a:
                dst[x, y] = tuple(int(round(min(255, max(0, s + a * (n - o))))) for s, o, n in zip(src[x, y], old, new))
    return out


def main():
    im = Image.open(SOURCE).convert("RGB")
    alpha = background_mask(im)
    for name, hexv in PRESETS:
        folder = os.path.join(ASSETS, f"AppIcon-{name}.appiconset")
        os.makedirs(folder, exist_ok=True)
        recolour(im, alpha, rgb(hexv)).save(os.path.join(folder, "AppIcon.png"), optimize=True)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                       "info": {"author": "xcode", "version": 1}}, f, indent=2)
        print("wrote", folder)


if __name__ == "__main__":
    main()
