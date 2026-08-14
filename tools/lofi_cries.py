#!/usr/bin/env python3
"""
Band-limit and bit-crush the Gen 3-5 cries so they sit beside the Game Boy
ones instead of standing out as clean recordings.

WHY THE GENERATIONS DO NOT MATCH
Measured from the committed cries/:

    Gen 2  (152-251)   10512 Hz   ~0.24 s
    Gen 3  (252-386)   10512 Hz   ~0.55 s
    Gen 4  (387-493)   13379 Hz   ~1.64 s   <- Infernape
    Gen 5  (494-649)   16000 Hz   ~0.72 s

So Gen 3 is already at the Game Boy rate and only needs the bit-crush; Gen 4
and 5 are wider-band as well.  The later ones are also much LONGER, which is
the more audible difference -- but see the note on PRESETS: length is left
alone on purpose.

WHAT THIS DOES
  --strength light   resample to 10512 Hz (matches Gen 2/3) only
  --strength medium  resample + quantise to 8-bit                      [default]
  --strength heavy   resample to 8 kHz + quantise to 6-bit

Gen 1 is not touched (the engine's own chip cries), and Gen 2 is left alone by
default because it is already at the Game Boy rate -- pass --from-dex 152 to
include it if you want the 8-bit crush uniform across everything.

Resampling is plain linear interpolation with no anti-aliasing filter, which is
deliberate: the aliasing is part of what makes a downsampled sample sound like
period hardware rather than like a modern file played quietly.

Usage:
  python3 tools/lofi_cries.py cries/                       # in place, medium
  python3 tools/lofi_cries.py cries/ --out out/ --strength heavy
  python3 tools/lofi_cries.py cries/ --out examples/ --only 252,392,495
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import soundfile as sf

# Gen 1 is engine-owned; Gen 2 already sits at the Game Boy sample rate.
DEFAULT_FROM_DEX = 252

# LENGTH IS NEVER TRUNCATED BY DEFAULT.  An earlier draft capped it, on the
# reasoning that a 1.64 s Infernape does not read as a cry -- but truncation is
# the one step here that destroys information rather than degrading it, and a
# clipped cry is a worse artefact than a long one.  Opt in with --max-sec.
PRESETS = {
    "light": dict(rate=10512, bits=None),
    "medium": dict(rate=10512, bits=8),
    "heavy": dict(rate=8000, bits=6),
}


def resample(x, src_rate, dst_rate):
    if src_rate == dst_rate:
        return x
    n = max(1, int(round(len(x) * dst_rate / src_rate)))
    # linear interpolation, no anti-aliasing: see the note in the docstring
    idx = np.linspace(0.0, len(x) - 1, n)
    return np.interp(idx, np.arange(len(x)), x)


def crush(x, bits):
    if not bits:
        return x
    levels = 2 ** bits
    peak = np.max(np.abs(x)) or 1.0
    y = x / peak
    y = np.round(y * (levels / 2 - 1)) / (levels / 2 - 1)
    return y * peak


def cap(x, rate, max_sec):
    """Trim to max_sec with a short fade, so the cut is not an audible click."""
    if not max_sec:
        return x
    limit = int(rate * max_sec)
    if len(x) <= limit:
        return x
    y = x[:limit].copy()
    fade = min(int(rate * 0.02), len(y))  # 20 ms
    if fade > 1:
        y[-fade:] *= np.linspace(1.0, 0.0, fade)
    return y


def process(path, out_path, preset):
    x, sr = sf.read(str(path), always_2d=False)
    if getattr(x, "ndim", 1) > 1:
        x = x.mean(axis=1)
    x = np.asarray(x, dtype=np.float64)

    rate = preset["rate"]
    y = resample(x, sr, rate)
    y = crush(y, preset["bits"])
    y = cap(y, rate, preset.get("max_sec"))

    # keep the original peak so cries stay level with the Gen 2 ones
    peak = np.max(np.abs(y))
    if peak > 0:
        y = y / peak * min(0.98, float(np.max(np.abs(x))) or 0.98)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out_path), y, rate, format="OGG", subtype="VORBIS")
    return sr, rate, len(x) / sr, len(y) / rate


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cries_dir")
    ap.add_argument("--out", help="default: in place")
    ap.add_argument("--strength", choices=tuple(PRESETS), default="medium")
    ap.add_argument("--from-dex", type=int, default=DEFAULT_FROM_DEX,
                    help=f"lowest dex to process (default {DEFAULT_FROM_DEX})")
    ap.add_argument("--only", help="comma-separated dex numbers, for examples")
    ap.add_argument("--max-sec", type=float, default=None,
                    help="optional length cap in seconds; off by default")
    args = ap.parse_args()

    src = Path(args.cries_dir)
    dst = Path(args.out) if args.out else src
    preset = dict(PRESETS[args.strength])
    preset["max_sec"] = args.max_sec
    only = {int(v) for v in args.only.split(",")} if args.only else None

    done, skipped = 0, 0
    for path in sorted(src.glob("*.ogg")):
        try:
            dex = int(path.stem)
        except ValueError:
            continue
        if only is not None:
            if dex not in only:
                continue
        elif dex < args.from_dex:
            skipped += 1
            continue
        sr, rate, before, after = process(path, dst / path.name, preset)
        done += 1
        if only is not None:
            print(f"  {dex:>3}  {sr} Hz {before:.2f}s  ->  "
                  f"{rate} Hz {after:.2f}s")
    print(f"processed {done} cries at strength {args.strength}"
          f" ({skipped} below dex {args.from_dex} left alone)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
