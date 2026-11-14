#!/usr/bin/env python3
"""Subtle sleep loop from ONE still frame: the character lies still, only little Zzz rise.
usage: python3 Tools/add_zzz.py <still.png> <out_dir> [frames=4]
The still is read before anything is written, so <still.png> may live inside <out_dir>."""
from PIL import Image, ImageDraw
import sys, os


def z(d, x, y, s, w, col):
    d.line([(x, y), (x + s, y), (x, y + s), (x + s, y + s)], fill=col, width=w, joint="curve")


still = Image.open(sys.argv[1]).convert("RGBA")
out = sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 4
os.makedirs(out, exist_ok=True)
x0, y0, x1, y1 = still.getchannel("A").getbbox()
px = still.load()
col = min((px[x, y][:3] for y in range(y0, y1, 3) for x in range(x0, x1, 3) if px[x, y][3] > 200), key=sum)
k = (x1 - x0) / 280.0                       # sizes tuned for a ~280px-wide character
head_x = x1 - int(62 * k)                   # head is at the front (right)
base_y = y0 - int(4 * k)
for i in range(n):
    im = still.copy(); d = ImageDraw.Draw(im)
    rise = int(i * 4 * k)
    z(d, head_x, base_y - rise, int(8 * k), max(2, int(2.4 * k)), col)
    z(d, head_x + int(13 * k), base_y - int(18 * k) - rise, int(11 * k), max(2, int(2.6 * k)), col)
    if i >= n // 2:
        z(d, head_x + int(28 * k), base_y - int(38 * k) - rise, int(14 * k), max(2, int(2.8 * k)), col)
    im.save(os.path.join(out, f"sleep_{i + 1:02d}.png"))
print(f"{n} sleep frames -> {out}  (still {x1 - x0}x{y1 - y0}, Zzz from x={head_x} y={base_y}, colour {col})")
