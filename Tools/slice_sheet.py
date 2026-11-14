#!/usr/bin/env python3
"""Slice a character sprite sheet into per-animation frames (no numpy needed).

  detect:  python3 Tools/slice_sheet.py detect <sheet.png> <preview.png>
           prints numbered boxes (row-major, left→right) and writes a labelled preview
  export:  python3 Tools/slice_sheet.py export <sheet.png> <out_dir> [--anchor=right] walk=1-8 alert=17-20
           writes <out_dir>/<role>/<role>_NN.png on one shared canvas (sized from the whole sheet, so
           separate export runs match), feet on the bottom edge. --anchor=right pins the nose instead of
           the centre: use it for walk cycles so a wagging tail can't shift the whole body.
"""
from PIL import Image, ImageDraw
import sys, os

DS, GAP = 4, 2                      # label on a 1/4 grid; merge parts within GAP cells


def lit_fn(img):
    px = img.load()
    w, h = img.size
    if img.mode == "RGBA" and img.getchannel("A").getextrema()[0] < 250:
        a = img.getchannel("A").load()
        return lambda x, y: a[x, y] > 40, True
    # Baked background (solid black, or a white/light checkerboard some generators bake in
    # instead of real alpha). Colour alone can't tell background from a light interior detail
    # (an eye highlight is exactly as "background-coloured" as the checker squares around the
    # character), so flood-fill background-looking pixels inward from the crop's edge instead:
    # only pixels actually *connected* to the border count as background.
    def bg_like(x, y):
        r, g, b = px[x, y][:3]
        return (max(r, g, b) - min(r, g, b)) < 30 and (r + g + b) > 450   # low-saturation & light
    from collections import deque
    reached = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_like(x, y) and not reached[y * w + x]:
                reached[y * w + x] = 1; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if bg_like(x, y) and not reached[y * w + x]:
                reached[y * w + x] = 1; q.append((x, y))
    while q:
        cx, cy = q.popleft()
        for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
            if 0 <= nx < w and 0 <= ny < h and not reached[ny * w + nx] and bg_like(nx, ny):
                reached[ny * w + nx] = 1; q.append((nx, ny))
    return lambda x, y: not reached[y * w + x], False


def detect(img):
    w, h = img.size
    on, _ = lit_fn(img)
    W, H = w // DS, h // DS
    grid = [[any(on(x, y) for y in range(Y * DS, min(Y * DS + DS, h), 2)
                              for x in range(X * DS, min(X * DS + DS, w), 2))
             for X in range(W)] for Y in range(H)]
    dil = [[False] * W for _ in range(H)]
    for Y in range(H):
        for X in range(W):
            if grid[Y][X]:
                for yy in range(max(0, Y - GAP), min(H, Y + GAP + 1)):
                    for xx in range(max(0, X - GAP), min(W, X + GAP + 1)):
                        dil[yy][xx] = True
    seen = [[False] * W for _ in range(H)]
    boxes = []
    for Y in range(H):
        for X in range(W):
            if dil[Y][X] and not seen[Y][X]:
                stack = [(Y, X)]; seen[Y][X] = True
                x0 = x1 = X; y0 = y1 = Y
                while stack:
                    cy, cx = stack.pop()
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                        if 0 <= ny < H and 0 <= nx < W and dil[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True; stack.append((ny, nx))
                # refine to exact lit pixels
                xs, ys = [], []
                for y in range(y0 * DS, min((y1 + 1) * DS, h)):
                    for x in range(x0 * DS, min((x1 + 1) * DS, w)):
                        if on(x, y): xs.append(x); ys.append(y)
                if xs: boxes.extend(split_columns(on, (min(xs), min(ys), max(xs) + 1, max(ys) + 1)))
    big = max((b[2] - b[0]) * (b[3] - b[1]) for b in boxes)
    boxes = [b for b in boxes if (b[2] - b[0]) * (b[3] - b[1]) > big * 0.05]
    rows = []
    for b in sorted(boxes, key=lambda b: (b[1] + b[3]) / 2):
        cy = (b[1] + b[3]) / 2
        for r in rows:
            if any(bb[1] <= cy <= bb[3] for bb in r): r.append(b); break
        else: rows.append([b])
    rows.sort(key=lambda r: min(b[1] for b in r))
    for r in rows:
        r.sort(key=lambda b: b[0])
        # frames that touch: a box far wider than its row-mates gets split at its thinnest column
        med = sorted(b[2] - b[0] for b in r)[len(r) // 2]
        i = 0
        while i < len(r):
            b = r[i]
            if b[2] - b[0] > med * 1.6:
                r[i:i + 1] = split_valley(on, b)
            i += 1
        r.sort(key=lambda b: b[0])
    return rows


def split_columns(on, box, min_gap=15):
    """Split a box wherever a run of >= min_gap empty columns separates two frames.
    Sound marks sit ~10px from the mouth (kept); neighbouring frames are 20px+ apart (split)."""
    x0, y0, x1, y1 = box
    occupied = [any(on(x, y) for y in range(y0, y1)) for x in range(x0, x1)]
    parts, start, gap = [], None, 0
    for i, occ in enumerate(occupied):
        if occ:
            if start is None: start = i
            gap = 0
        else:
            gap += 1
            if start is not None and gap >= min_gap:
                parts.append((start, i - gap + 1)); start = None
    if start is not None: parts.append((start, len(occupied)))
    out = []
    for a, b in parts:
        ys = [y for y in range(y0, y1) if any(on(x, y) for x in range(x0 + a, x0 + b))]
        out.append((x0 + a, min(ys), x0 + b, max(ys) + 1))
    return out


def split_valley(on, box):
    x0, y0, x1, y1 = box
    counts = [sum(1 for y in range(y0, y1) if on(x, y)) for x in range(x0, x1)]
    lo, hi = int(len(counts) * 0.3), int(len(counts) * 0.7)
    cut = x0 + min(range(lo, hi), key=lambda i: counts[i])
    out = []
    for a, b in ((x0, cut), (cut, x1)):
        ys = [y for y in range(y0, y1) if any(on(x, y) for x in range(a, b))]
        xs = [x for x in range(a, b) if any(on(x, y) for y in range(y0, y1))]
        if xs and ys: out.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    return out


def parse_idx(spec):
    out = []
    for part in spec.split(","):
        if "-" in part: a, b = part.split("-"); out += list(range(int(a), int(b) + 1))
        else: out.append(int(part))
    return out


def main():
    mode, sheet = sys.argv[1], sys.argv[2]
    img = Image.open(sheet).convert("RGBA")
    rows = detect(img)
    boxes = [b for r in rows for b in r]
    if mode == "detect":
        prev = img.copy(); d = ImageDraw.Draw(prev)
        for i, b in enumerate(boxes, 1):
            d.rectangle(b, outline=(255, 0, 255, 255), width=3)
            d.rectangle([b[0], b[1] - 26, b[0] + 44, b[1]], fill=(255, 0, 255, 255))
            d.text((b[0] + 6, b[1] - 24), str(i), fill=(255, 255, 255, 255))
            print(f"{i:2d}: row {[k for k, r in enumerate(rows) if b in r][0] + 1}  x={b[0]}..{b[2]} y={b[1]}..{b[3]}  {b[2] - b[0]}x{b[3] - b[1]}")
        prev.convert("RGB").resize((prev.width // 2, prev.height // 2)).save(sys.argv[3])
        return
    out_dir = sys.argv[3]
    flags = [a for a in sys.argv[4:] if a.startswith("--")]
    anchor = next((f.split("=")[1] for f in flags if f.startswith("--anchor=")), "center")
    assign = {k: parse_idx(v) for k, v in (a.split("=") for a in sys.argv[4:] if not a.startswith("--"))}
    pad = 6                                       # canvas from ALL boxes so every export shares it
    W = max(b[2] - b[0] for b in boxes) + 2 * pad
    H = max(b[3] - b[1] for b in boxes) + pad
    on, has_alpha = lit_fn(img)
    for role, idxs in assign.items():
        d = os.path.join(out_dir, role); os.makedirs(d, exist_ok=True)
        for k, i in enumerate(idxs, 1):
            bx0, by0, bx1, by1 = boxes[i - 1]
            crop = img.crop((bx0, by0, bx1, by1))
            if not has_alpha:
                alpha = Image.new("L", crop.size, 0)
                ap = alpha.load()
                for yy in range(crop.size[1]):
                    for xx in range(crop.size[0]):
                        if on(bx0 + xx, by0 + yy):
                            ap[xx, yy] = 255
                crop.putalpha(alpha)
            canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            x = W - pad - crop.width if anchor == "right" else (W - crop.width) // 2
            canvas.alpha_composite(crop, (x, H - crop.height))
            canvas.save(os.path.join(d, f"{role}_{k:02d}.png"))
        print(f"{role}: {len(idxs)} frames")
    print(f"canvas {W}x{H} (aspect {W / H:.2f})")


if __name__ == "__main__":
    main()
