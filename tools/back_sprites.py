#!/usr/bin/env python3
"""
Back-sprite treatments, rendered the way the engine actually draws them.

THE PROBLEM
Vanilla Gen 1 back pics are a 32x32 source that ScaleSpriteByTwo doubles into
a 7x7 (56x56) buffer, dropping the last 4 source rows and the last source
column -- so what reaches the screen is the top-left 28x28 at 2x
(src/ui/HallOfFame.lua). Vanilla art is drawn FOR that: it is a cropped,
zoomed view of the mon's upper body that fills the frame.

The first generator instead shrank the whole 56x56 front pic to 28x28. Every
limb survives, which sounds right and looks wrong: a tall mon becomes a
postage stamp with acres of empty space above it, and a short one ends up a
small blob adrift in the player's half of the screen.

TREATMENTS
  current      whole front pic squeezed into 28x28 (the original behaviour)
  clean_2x     INTEGER scaling only: trim the dead margin, then halve exactly
               once if the art does not already fit.  The engine doubles it
               back, so every pixel is a clean 2x2 block and nothing is cut.
               Fractional resampling is what reads as "blurry" even with
               NEAREST, because e.g. a 3:2 ratio keeps some source pixels and
               drops others unevenly.
  upper_body   trim to ink, scale so the WIDTH fills the frame, keep the top
               28 rows -- the legs fall off the bottom, as in vanilla
  zoom_left    scaled so ~70% of the mon's height fills the frame, and
               RIGHT-aligned rather than centred, so the right edge and the top
               are never cut.  The left side is what falls off, with the legs.
               This is what the mod ships.

FACING
Back pics show the player's own mon from behind, facing away -- i.e. RIGHT.
The /vp/ sheet already draws everything facing right, so back pics are built
from UNMIRRORED art.  tools/mirror_fronts.py flips the front pics to face left
and leaves a .mirrored sentinel; this script reads that sentinel and un-mirrors
on the way in, so the two tools can be run in either order and the back pics
come out identical.

Usage:
  python3 tools/back_sprites.py assets/front assets/back --treatment zoom_left
  python3 tools/back_sprites.py assets/front /tmp/x --contact-sheet sheet.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

CELL = 56
BACK_SRC = 32       # canvas the engine reads
BACK_VISIBLE = 28   # what survives the 2x bake

TREATMENTS = ("current", "clean_2x", "upper_body", "zoom_left")

# tools/mirror_fronts.py leaves this behind when it has flipped the front pics
# to face left.  Back pics must face RIGHT -- they are the player's own mon seen
# from behind -- so when the marker is present the source is un-mirrored on the
# way in.  Auto-detecting removes the ordering foot-gun.
MIRROR_SENTINEL = ".mirrored"


def source_faces_left(front_dir):
    return (Path(front_dir) / MIRROR_SENTINEL).exists()


def unmirror_if_needed(img, faces_left):
    return img.transpose(Image.FLIP_LEFT_RIGHT) if faces_left else img


def trim(img):
    box = img.getbbox()
    return img.crop(box) if box else img


def build(front, treatment):
    """Return the 32x32 back-pic canvas for one treatment."""
    canvas = Image.new("RGBA", (BACK_SRC, BACK_SRC), (0, 0, 0, 0))

    if treatment == "clean_2x":
        # Integer-only scaling.  "current" halves the whole 56x56 frame, dead
        # margin included, which is why small mons ended up adrift: half their
        # 28x28 was empty space.  Trimming first spends the frame on the mon.
        art = trim(front)
        if art.width == 0:
            return canvas
        if art.width > BACK_VISIBLE or art.height > BACK_VISIBLE:
            art = art.resize((max(1, art.width // 2), max(1, art.height // 2)),
                             Image.NEAREST)
        art = art.crop((0, 0, min(art.width, BACK_VISIBLE),
                        min(art.height, BACK_VISIBLE)))
        x = (BACK_VISIBLE - art.width) // 2
        y = BACK_VISIBLE - art.height  # bottom-anchored
        canvas.paste(art, (x, y), art)
        return canvas

    if treatment == "current":
        canvas.paste(front.resize((BACK_VISIBLE, BACK_VISIBLE), Image.NEAREST),
                     (0, 0))
        return canvas

    art = trim(front)
    if art.width == 0 or art.height == 0:
        return canvas

    if treatment == "upper_body":
        scale = BACK_VISIBLE / art.width
    else:  # zoom_left
        # scale so roughly the top 70% of the mon fills the frame height
        scale = max(BACK_VISIBLE / art.width,
                    BACK_VISIBLE / (art.height * 0.70))

    w = max(1, round(art.width * scale))
    h = max(1, round(art.height * scale))
    big = art.resize((w, h), Image.NEAREST)

    # Top-aligned so the legs are what falls off the bottom: cropping the head
    # would be worse than cropping the feet.
    #
    # Horizontal alignment differs by treatment.  Centring cuts BOTH sides,
    # which is what clipped the right edge; zoom_left right-aligns instead, so
    # the right edge is intact and only the left is lost.
    if treatment == "zoom_left":
        x = BACK_VISIBLE - w
    else:
        x = (BACK_VISIBLE - w) // 2
    crop = big.crop((0, 0, w, min(h, BACK_VISIBLE)))
    canvas.paste(crop, (x, 0), crop)
    return canvas


def as_drawn(back):
    """Simulate the engine: top-left 28x28, doubled to 56x56."""
    return back.crop((0, 0, BACK_VISIBLE, BACK_VISIBLE)) \
               .resize((CELL, CELL), Image.NEAREST)


def checker(w, h, s=8):
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = (205, 205, 212, 255) if ((x // s + y // s) % 2 == 0) \
                else (170, 170, 180, 255)
    return im


def contact_sheet(front_dir, dexes, labels, out):
    pad, head, lab = 6, 40, 74
    cols = len(dexes)
    rows = len(TREATMENTS) + 1  # +1 for the front pic reference
    W = lab + cols * (CELL + pad) + pad
    H = head + rows * (CELL + pad) + pad
    sheet = checker(W, H, 8)
    d = ImageDraw.Draw(sheet)
    d.rectangle([0, 0, W, head - 1], fill=(30, 30, 36, 255))
    d.text((6, 6), "back sprite treatments (drawn as the engine draws: 2x)",
           fill=(255, 255, 255))

    rownames = ["FRONT (ref)"] + [t.upper() for t in TREATMENTS]
    for r, name in enumerate(rownames):
        y = head + pad + r * (CELL + pad)
        d.text((4, y + CELL // 2 - 4), name, fill=(20, 20, 20))

    faces_left = source_faces_left(front_dir)
    for c, dex in enumerate(dexes):
        x = lab + pad + c * (CELL + pad)
        d.text((x, head - 14), labels[c][:9], fill=(20, 20, 20))
        fp = front_dir / f"{dex:03d}.png"
        if not fp.exists():
            continue
        shown = Image.open(fp).convert("RGBA")
        front = unmirror_if_needed(shown, faces_left)
        sheet.alpha_composite(shown, (x, head + pad))
        for r, t in enumerate(TREATMENTS, start=1):
            y = head + pad + r * (CELL + pad)
            sheet.alpha_composite(as_drawn(build(front, t)), (x, y))
    sheet.resize((W * 2, H * 2), Image.NEAREST).save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("front_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--treatment", choices=TREATMENTS, default="zoom_left")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()

    front_dir = Path(args.front_dir)

    if args.contact_sheet:
        dexes = [152, 155, 158, 249, 252, 257, 384, 448, 495, 500]
        labels = ["CHIKORITA", "CYNDAQUIL", "TOTODILE", "LUGIA", "TREECKO",
                  "BLAZIKEN", "RAYQUAZA", "LUCARIO", "SNIVY", "EMBOAR"]
        print("wrote", contact_sheet(front_dir, dexes, labels,
                                     args.contact_sheet))
        return 0

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    faces_left = source_faces_left(front_dir)
    if faces_left:
        print("front pics are mirrored (sentinel found); un-mirroring so the "
              "back pics face right")
    n = 0
    for fp in sorted(front_dir.glob("*.png")):
        front = unmirror_if_needed(Image.open(fp).convert("RGBA"), faces_left)
        build(front, args.treatment).save(out_dir / fp.name)
        n += 1
    print(f"wrote {n} back pics with treatment {args.treatment}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
