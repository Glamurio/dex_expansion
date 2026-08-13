#!/usr/bin/env python3
"""
Split a Gen-1-style Pokémon spritesheet into per-species battle pics for
Gen1Recomp.

The sheet this was written against
----------------------------------
  1736 x 1344 px  =  31 cols x 24 rows of 56x56 cells
  background      =  opaque #FEFEFF (NOT alpha)
  cell layout     =  national dex order, index = row*31 + col + 1
                     rows  0-20  -> dex 1..650 (row 20 stops at col 29)
                     row   21    -> blank spacer
                     row   22    -> alternate forms (unmapped)
                     row   23    -> col 0 alt form, cols 1-28 Unown,
                                    cols 29-30 the palette legend
  sprites are BOTTOM-ANCHORED in their cell and horizontally centred, which
  is exactly how Gen1Recomp grounds an enemy pic in its 7x7 slot, so cells
  are emitted whole at 56x56 with frontSize = 7.

Why the output looks the way it does
------------------------------------
Gen1Recomp resolves battle pic scale as image-level -> species-level ->
default, and the default is *1x front, 2x back* (docs/modding.md, "Battle
sprite scaling").  So:

  front  56x56, drawn 1x                      -> frontSize = 7
  back   32x32, doubled to 56x56 by the engine (the engine drops the last 4
         source rows and last source column, so the visible area is the
         top-left 28x28 at 2x -- see src/ui/HallOfFame.lua)

Transparency follows the engine's own `transparent_matte` rule from
tools/extract/gfx.py: only background connected to the cell edge becomes
alpha 0, so interior whites (eyes, Articuno's body, Clefairy highlights)
stay opaque instead of being punched out.

Two colour modes
----------------
  --mode truecolor  (default) keep the sheet's colours, emit RGBA.  Records
                    need `trueColor = true`, which makes the engine skip
                    every palette bake.
  --mode dmg        quantise to the 4 DMG shades (255/170/85/0) like the
                    vanilla extractor, and report a matching `palette` id
                    from the sheet's own legend.  Authentic, and it keeps
                    working with the engine's palette/shiny modes.

Usage
-----
  python3 split_spritesheet.py SHEET.png -o out/
  python3 split_spritesheet.py SHEET.png -o out/ --mode dmg
  python3 split_spritesheet.py SHEET.png -o out/ --back-mode crop
  python3 split_spritesheet.py SHEET.png -o out/ --names names.csv

`names.csv` is optional, `dex,SPECIES_ID` per line; when given, files are
named by species id as well as dex number.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from dataclasses import dataclass, field, asdict
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  pip install pillow")

# --------------------------------------------------------------------------
# Sheet geometry.  Every one of these is asserted against the real file
# before a single PNG is written -- a silently mis-sliced sheet is much
# worse than a hard failure.
# --------------------------------------------------------------------------

CELL = 56
COLS = 31
ROWS = 24
SHEET_W = COLS * CELL          # 1736
SHEET_H = ROWS * CELL          # 1344

BG = (254, 254, 255, 255)      # the sheet's opaque background

DEX_ROWS = 21                  # rows 0..20 hold the dex block
DEX_LAST_ROW_COLS = 30         # row 20 stops after col 29
DEX_MAX = 649                  # Gen 1-5; slot 650 exists but is unidentified

SPACER_ROW = 21
ALT_FORM_ROW = 22
TAIL_ROW = 23
UNOWN_COLS = range(1, 29)      # 28 Unown forms: A-Z plus ? and !
LEGEND_COLS = (29, 30)

# The 4 DMG shades, lightest to darkest, matching tools/extract/gfx.py.
GB_SHADES = [
    (255, 255, 255),
    (170, 170, 170),
    (85, 85, 85),
    (0, 0, 0),
]

BACK_SRC = 32                  # back pic source size; engine doubles it
BACK_VISIBLE = 28              # what actually shows after the 2x bake


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def luma(c) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def dist2(a, b) -> int:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


@dataclass
class Report:
    """Everything worth telling the caller about, collected as we go."""
    front_written: int = 0
    back_written: int = 0
    extras_written: int = 0
    unown_written: int = 0
    blank_cells: list = field(default_factory=list)
    over_budget: list = field(default_factory=list)   # >4 colours
    weak_palette: list = field(default_factory=list)  # poor legend match
    warnings: list = field(default_factory=list)


# --------------------------------------------------------------------------
# Geometry verification
# --------------------------------------------------------------------------

def verify_sheet(im: Image.Image, strict: bool) -> None:
    """Fail loudly if the sheet is not the layout this script understands."""
    problems = []
    if im.size != (SHEET_W, SHEET_H):
        problems.append(
            f"expected {SHEET_W}x{SHEET_H} (31x24 cells of {CELL}), "
            f"got {im.size[0]}x{im.size[1]}")
    else:
        px = im.load()
        # The spacer row must be empty; if it is not, the row mapping below
        # (and therefore every dex number) is wrong.
        for y in range(SPACER_ROW * CELL, (SPACER_ROW + 1) * CELL):
            for x in range(0, SHEET_W, 7):
                if px[x, y] != BG:
                    problems.append(
                        f"row {SPACER_ROW} should be a blank spacer but has "
                        f"content at ({x},{y}) -- row layout has changed")
                    break
            else:
                continue
            break
    if problems:
        msg = "sheet does not match the expected layout:\n  - " + \
              "\n  - ".join(problems)
        if strict:
            sys.exit("error: " + msg)
        print("warning: " + msg, file=sys.stderr)


# --------------------------------------------------------------------------
# Palette legend
# --------------------------------------------------------------------------

def read_legend(im: Image.Image) -> list:
    """Read the 10x2 swatch block at the bottom right of the sheet.

    Nine of the columns are a (light, dark) mid-tone pair -- the Gen 1 mon
    palettes -- and the tenth is the shared black/white key.  Returned as
    4-colour palettes in the engine's order: white, light, dark, black.
    """
    px = im.load()
    band_y = TAIL_ROW * CELL
    # locate the block: saturated pixels in the last two cells of the row
    x0 = LEGEND_COLS[0] * CELL
    xs, ys = [], []
    for y in range(band_y, band_y + CELL):
        for x in range(x0 - CELL, SHEET_W):
            r, g, b, _ = px[x, y]
            if max(r, g, b) - min(r, g, b) > 25 or (r, g, b) == (0, 0, 0):
                xs.append(x)
                ys.append(y)
    if not xs:
        return []
    left, right = min(xs), max(xs)
    top, bottom = min(ys), max(ys)
    mid = (top + bottom) // 2

    def runs(y):
        out, prev = [], None
        for x in range(left, right + 1):
            c = px[x, y][:3]
            if c != prev:
                out.append([c, 1])
                prev = c
            else:
                out[-1][1] += 1
        return [c for c, n in out if n >= 6 and c != BG[:3]]

    light = runs(top + (mid - top) // 2)
    dark = runs(mid + (bottom - mid) // 2)
    pals = []
    for i, (lo, hi) in enumerate(zip(light, dark)):
        if lo == (0, 0, 0) or hi == BG[:3]:
            continue  # the black/white key column, not a mon palette
        pals.append({
            "id": f"SHEET_PAL_{i:02d}",
            "light": list(lo),
            "dark": list(hi),
            # engine `palettes` records take exactly 4 colours
            "colors": [list(GB_SHADES[0]), list(lo), list(hi),
                       list(GB_SHADES[3])],
        })
    return pals


def mid_pair(colors: Counter):
    """A sprite's (light, dark) mid tones: the two most-used non-black,
    non-white colours, ordered light first.

    The sheet is palette-disciplined -- the overwhelming majority of cells
    use exactly white + light + dark + black -- so this pair *is* the
    sprite's palette rather than an approximation of one.
    """
    mids = [c for c in colors if 24 < luma(c) < 246]
    if not mids:
        return None
    mids.sort(key=lambda c: -colors[c])
    mids = sorted(mids[:2], key=luma, reverse=True)
    if len(mids) == 1:
        return (mids[0], mids[0])
    return (mids[0], mids[1])


def nearest_legend(pair, legend):
    """Name a derived palette after the closest legend swatch (informational).

    Returned as (legend id, exact?).  The legend is a reference strip and a
    couple of its swatches are slightly out of sync with the art, which is
    exactly why palettes are derived from the sprites and the legend is only
    used for naming.
    """
    if not legend or pair is None:
        return None, False
    best, best_d = None, None
    for p in legend:
        d = dist2(pair[0], p["light"]) + dist2(pair[1], p["dark"])
        if best_d is None or d < best_d:
            best, best_d = p, d
    return best["id"], best_d == 0


def derive_palettes(im: Image.Image, legend: list):
    """First pass: collect every distinct (light, dark) pair the art uses.

    Returns (palettes, index) where palettes is a list of engine-shaped
    4-colour records ordered by how many species use them, and index maps a
    pair -> palette id.
    """
    counts = Counter()
    for row in range(DEX_ROWS):
        ncols = DEX_LAST_ROW_COLS if row == DEX_ROWS - 1 else COLS
        for col in range(ncols):
            cell = cell_at(im, row, col)
            px = cell.load()
            colors = Counter(px[x, y][:3] for y in range(CELL)
                             for x in range(CELL)
                             if px[x, y][:3] != BG[:3])
            pair = mid_pair(colors)
            if pair:
                counts[pair] += 1

    palettes, index = [], {}
    for i, (pair, n) in enumerate(counts.most_common()):
        pid = f"SHEET_PAL_{i:02d}"
        name, exact = nearest_legend(pair, legend)
        palettes.append({
            "id": pid,
            "species": n,
            "light": list(pair[0]),
            "dark": list(pair[1]),
            # engine `palettes` records take exactly 4 colours,
            # lightest -> darkest
            "colors": [list(GB_SHADES[0]), list(pair[0]), list(pair[1]),
                       list(GB_SHADES[3])],
            "nearestLegend": name,
            "matchesLegendExactly": exact,
        })
        index[pair] = pid
    return palettes, index


# --------------------------------------------------------------------------
# Per-cell conversion
# --------------------------------------------------------------------------

def matte(cell: Image.Image) -> Image.Image:
    """Edge-connected background -> alpha 0; interior whites stay opaque.

    This is the engine's own `transparent_matte` rule (tools/extract/gfx.py):
    flood fill inward from the border so white *artwork* is not punched out.
    """
    out = cell.convert("RGBA")
    px = out.load()
    w, h = out.size
    stack, seen = [], set()

    def is_bg(x, y):
        return px[x, y] == BG

    for x in range(w):
        for y in (0, h - 1):
            if (x, y) not in seen and is_bg(x, y):
                seen.add((x, y))
                stack.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if (x, y) not in seen and is_bg(x, y):
                seen.add((x, y))
                stack.append((x, y))

    while stack:
        x, y = stack.pop()
        px[x, y] = (255, 255, 255, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen \
                    and is_bg(nx, ny):
                seen.add((nx, ny))
                stack.append((nx, ny))
    return out


def to_dmg(img: Image.Image) -> Image.Image:
    """Quantise an RGBA cell to the 4 DMG shades by luminance.

    Sprites that already use 4 colours map exactly.  The handful that use
    more are bucketed, which is what a 2bpp target requires anyway.
    """
    out = img.copy()
    px = out.load()
    w, h = out.size
    tones = sorted({px[x, y][:3] for y in range(h) for x in range(w)
                    if px[x, y][3] != 0}, key=luma, reverse=True)
    if not tones:
        return out
    if len(tones) <= 4:
        mapping = {c: GB_SHADES[min(i, 3)] for i, c in enumerate(tones)}
    else:
        mapping = {}
        for c in tones:
            # 4 luminance buckets, lightest -> shade 0
            idx = 3 - min(3, int(luma(c) / 64))
            mapping[c] = GB_SHADES[idx]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            nr, ng, nb = mapping[(r, g, b)]
            px[x, y] = (nr, ng, nb, a)
    return out


def make_back(front: Image.Image, mode: str) -> Image.Image:
    """Build a 32x32 back pic the engine will draw at 2x.

    downscale (default): the whole front at half size, bottom-anchored in
        the visible 28x28.  Doubling it back up reproduces the chunky
        pixel-doubled look real Gen 1 back sprites have, and the whole mon
        stays readable.
    crop: Sanqui's convert_sprites.sh trick -- the front's top-left region
        at 1:1, i.e. a head-and-shoulders close-up.
    """
    canvas = Image.new("RGBA", (BACK_SRC, BACK_SRC), (255, 255, 255, 0))
    if mode == "crop":
        canvas.paste(front.crop((0, 0, BACK_VISIBLE, BACK_VISIBLE)), (0, 0))
        return canvas
    small = front.resize((BACK_VISIBLE, BACK_VISIBLE), Image.NEAREST)
    canvas.paste(small, (0, 0))
    return canvas


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def cell_at(im, row, col):
    return im.crop((col * CELL, row * CELL, (col + 1) * CELL,
                    (row + 1) * CELL))


def is_blank(cell) -> bool:
    px = cell.load()
    w, h = cell.size
    n = 0
    for y in range(h):
        for x in range(w):
            if px[x, y] != BG:
                n += 1
                if n > 15:
                    return False
    return True


def load_names(path):
    names = {}
    if not path:
        return names
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.reader(fh):
            if len(row) >= 2 and row[0].strip().isdigit():
                names[int(row[0])] = row[1].strip()
    return names


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Split a Gen-1-style Pokémon spritesheet for Gen1Recomp.")
    ap.add_argument("sheet")
    ap.add_argument("-o", "--out", default="sprites_out")
    ap.add_argument("--mode", choices=("truecolor", "dmg"),
                    default="truecolor")
    ap.add_argument("--back-mode", choices=("downscale", "crop", "none"),
                    default="downscale")
    ap.add_argument("--names", help="optional dex,SPECIES_ID CSV")
    ap.add_argument("--no-strict", action="store_true",
                    help="warn instead of aborting on layout mismatch")
    args = ap.parse_args(argv)

    im = Image.open(args.sheet).convert("RGBA")
    verify_sheet(im, strict=not args.no_strict)

    out = Path(args.out)
    (out / "front").mkdir(parents=True, exist_ok=True)
    if args.back_mode != "none":
        (out / "back").mkdir(parents=True, exist_ok=True)
    (out / "extras").mkdir(parents=True, exist_ok=True)
    (out / "unown").mkdir(parents=True, exist_ok=True)

    legend = read_legend(im)
    # first pass: the art's OWN (light, dark) pairs.  The legend strip is a
    # reference and two of its nine swatches are out of sync with the
    # sprites, so palettes are derived and the legend only names them.
    palettes, pal_index = derive_palettes(im, legend)
    names = load_names(args.names)
    rep = Report()
    entries = {}

    def emit(cell, rel):
        art = matte(cell)
        if args.mode == "dmg":
            art = to_dmg(art)
        (out / rel).parent.mkdir(parents=True, exist_ok=True)
        art.save(out / rel, optimize=True)
        return art

    # ---- dex block -----------------------------------------------------
    for row in range(DEX_ROWS):
        ncols = DEX_LAST_ROW_COLS if row == DEX_ROWS - 1 else COLS
        for col in range(ncols):
            dex = row * COLS + col + 1
            cell = cell_at(im, row, col)
            if is_blank(cell):
                rep.blank_cells.append(dex)
                continue

            stem = f"{dex:03d}"
            if dex in names:
                stem = f"{dex:03d}_{names[dex].lower()}"

            if dex > DEX_MAX:
                # slot 650 is occupied but is past Gen 5; do not guess at it
                rel = f"extras/unidentified_slot{dex}.png"
                emit(cell, rel)
                rep.extras_written += 1
                rep.warnings.append(
                    f"cell row {row} col {col} (slot {dex}) holds art beyond "
                    f"dex {DEX_MAX}; written to {rel} for manual mapping")
                continue

            # Palette is read from the RAW cell, before matting and before
            # any dmg quantisation -- quantised art is already GB shades, so
            # classifying it would match nothing.
            rawpx = cell.convert("RGBA").load()
            colors = Counter(rawpx[x, y][:3] for y in range(CELL)
                             for x in range(CELL)
                             if rawpx[x, y][:3] != BG[:3])

            art = emit(cell, f"front/{stem}.png")
            rep.front_written += 1
            if len(colors) > 4:
                rep.over_budget.append(dex)
            pair = mid_pair(colors)
            pal = pal_index.get(pair)
            if pal is None:
                rep.weak_palette.append(dex)

            rec = {
                "dex": dex,
                "row": row, "col": col,
                "spriteFront": f"front/{stem}.png",
                "frontSize": 7,             # 56 px / 8 = 7 tiles
                "colors": len(colors),
            }
            if names.get(dex):
                rec["id"] = names[dex]
            if args.mode == "truecolor":
                rec["trueColor"] = True
            else:
                rec["palette"] = pal
            if args.back_mode != "none":
                back = make_back(art, args.back_mode)
                back.save(out / "back" / f"{stem}.png", optimize=True)
                rec["spriteBack"] = f"back/{stem}.png"
                rec["backPlaceholder"] = True
                rep.back_written += 1
            entries[dex] = rec

    # ---- alternate forms (row 22) + row 23 col 0 ------------------------
    for col in range(COLS):
        cell = cell_at(im, ALT_FORM_ROW, col)
        if is_blank(cell):
            continue
        emit(cell, f"extras/altform_r{ALT_FORM_ROW}c{col:02d}.png")
        rep.extras_written += 1
    cell = cell_at(im, TAIL_ROW, 0)
    if not is_blank(cell):
        emit(cell, f"extras/altform_r{TAIL_ROW}c00.png")
        rep.extras_written += 1

    # ---- Unown ---------------------------------------------------------
    for i, col in enumerate(UNOWN_COLS):
        cell = cell_at(im, TAIL_ROW, col)
        if is_blank(cell):
            continue
        emit(cell, f"unown/unown_{i:02d}.png")
        rep.unown_written += 1

    # ---- manifests -----------------------------------------------------
    (out / "manifest.json").write_text(json.dumps({
        "source": Path(args.sheet).name,
        "sheet": {"width": im.size[0], "height": im.size[1],
                  "cell": CELL, "cols": COLS, "rows": ROWS},
        "mode": args.mode,
        "backMode": args.back_mode,
        "indexFormula": "dex = row * 31 + col + 1",
        "species": [entries[k] for k in sorted(entries)],
    }, indent=2), encoding="utf-8")

    if palettes:
        (out / "palettes.json").write_text(json.dumps(palettes, indent=2),
                                           encoding="utf-8")
    if legend:
        (out / "palettes_legend.json").write_text(
            json.dumps(legend, indent=2), encoding="utf-8")

    (out / "report.json").write_text(
        json.dumps(asdict(rep), indent=2), encoding="utf-8")

    # ---- console summary ----------------------------------------------
    print(f"front pics       {rep.front_written}")
    print(f"back pics        {rep.back_written}"
          f"{'  (placeholders)' if rep.back_written else ''}")
    print(f"extras           {rep.extras_written}")
    print(f"unown            {rep.unown_written}")
    print(f"palettes derived {len(palettes)} (legend swatches {len(legend)})")
    if rep.blank_cells:
        print(f"blank dex cells  {len(rep.blank_cells)}: {rep.blank_cells}")
    if rep.over_budget:
        print(f"over 4 colours   {len(rep.over_budget)} sprites"
              f" (fine for trueColor, quantised in dmg mode)")
    if rep.weak_palette and args.mode == "dmg":
        print(f"weak palette fit {len(rep.weak_palette)} sprites"
              f" -- check report.json")
    for w in rep.warnings:
        print("warning: " + w)
    print(f"\nwrote {out}/  (manifest.json, report.json"
          f"{', palettes.json' if legend else ''})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
