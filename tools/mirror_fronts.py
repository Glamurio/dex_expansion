#!/usr/bin/env python3
"""
Mirror the front sprites so they face LEFT.

The /vp/ sheet draws every mon facing RIGHT.  That is backwards for a front
pic: the enemy stands on the right of the battle screen and faces the player,
so it must face left.  Vanilla front pics all do.

The back pic is the opposite -- it is the player's own mon seen from behind,
facing away, i.e. RIGHT -- so back sprites are built from the UNMIRRORED art.
tools/back_sprites.py handles that automatically; see the sentinel note below.

IDEMPOTENCE
A horizontal flip is its own inverse, so running this twice would silently undo
it and leave no trace that anything was wrong.  A sentinel file records that
the directory has been mirrored:

    assets/front/.mirrored

Running again with the sentinel present is a no-op that says so.  Pass --force
to flip regardless (which is how you un-mirror: --force once more).

Usage:
  python3 tools/mirror_fronts.py assets/front
  python3 tools/mirror_fronts.py assets/front --force
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

SENTINEL = ".mirrored"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("front_dir")
    ap.add_argument("--force", action="store_true",
                    help="flip even if the sentinel says it is already done")
    args = ap.parse_args()

    front = Path(args.front_dir)
    if not front.is_dir():
        raise SystemExit(f"not a directory: {front}")

    marker = front / SENTINEL
    if marker.exists() and not args.force:
        print(f"{marker} exists: already mirrored, nothing to do.")
        print("Pass --force to flip anyway (running it twice un-mirrors).")
        return 0

    n = 0
    for path in sorted(front.glob("*.png")):
        im = Image.open(path).convert("RGBA")
        im.transpose(Image.FLIP_LEFT_RIGHT).save(path)
        n += 1

    if marker.exists():
        marker.unlink()
        print(f"flipped {n} front sprites and REMOVED the sentinel "
              f"(they now face right again)")
    else:
        marker.write_text(
            "Front sprites in this directory have been mirrored to face LEFT\n"
            "by tools/mirror_fronts.py.  tools/back_sprites.py reads this file\n"
            "and un-mirrors on the way in, so back pics still face RIGHT.\n"
            "Delete this file only if you also un-mirror the sprites.\n")
        print(f"flipped {n} front sprites to face left; wrote {marker}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
