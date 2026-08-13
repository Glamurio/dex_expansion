#!/usr/bin/env python3
"""
Generate data/dex_entries.lua: the `dexEntry` record for dex 152-649.

    python3 tools/build_dex_entries.py

Needs the PokeAPI CSV dumps in the working directory (pk_pokemon.csv,
pk_pokemon_species.csv, pk_pokemon_species_names.csv,
pk_pokemon_species_flavor_text.csv). The output is ~117 KB and is NOT
committed; main.lua treats it as optional and only loses the Pokedex flavour
text when it is absent.

WHY THIS EXISTS
The Pokedex screen renders a species' entry as:

    Font.draw(e.kind or "?", 72, 20)
    Font.draw(Strings("HT %d'%02d\\"", e.heightFt, e.heightIn or 0), ...)
    Font.draw(Strings("WT %.1flb", (e.weight or 0) / 10), ...)
    local text = owned and e.text and game.data.text[e.text] or nil
    ... else Font.draw(Strings("Data unknown."), 8, y)

    -- src/ui/DexEntryMenu.lua

so a species with no `dexEntry` shows "Data unknown." and no height or
weight. `text` is a KEY into the `text` registry, not a literal, which is why
this also emits the strings for main.lua to register.

UNITS, taken from a real extracted record (ABRA):
    heightFt = 2, heightIn = 11   -- 2'11"
    weight   = 430                -- tenths of a pound; Abra is 43.0 lb
PokeAPI stores height in decimetres and weight in hectograms.

Flavor text is the Black 2/White 2 entry where available, falling back to the
newest available version, and is hard-wrapped to 18 characters over at most
6 lines -- the Gen 1 dex window is 18 columns wide and DexEntryMenu stops
drawing at y > 132, so a longer line is simply clipped off-screen.
"""

from __future__ import annotations

import csv
import re
from pathlib import Path

ENGLISH = 9
DEX_MIN, DEX_MAX = 152, 649

# Prefer Gen 5 text, then walk back. Version ids: 21/22 = Black/White,
# 23/24 = Black 2/White 2.
VERSION_PREFERENCE = [24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13]

WRAP_COLS = 18
MAX_LINES = 6


def read(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def wrap(text):
    """Hard-wrap to the dex window and clip to what actually fits on screen."""
    text = re.sub(r"[\n\r\f\v\u000c]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.replace("\u2019", "'").replace("\u00e9", "e")
    words, lines, line = text.split(" "), [], ""
    for w in words:
        if not line:
            line = w
        elif len(line) + 1 + len(w) <= WRAP_COLS:
            line = line + " " + w
        else:
            lines.append(line)
            line = w
            if len(lines) == MAX_LINES:
                break
    if line and len(lines) < MAX_LINES:
        lines.append(line)
    return lines[:MAX_LINES]


def lua_str(s):
    # Order matters: escape backslashes first, then turn REAL newlines into a
    # Lua \n escape.  Joining the wrapped lines with a literal backslash-n
    # instead produced a two-character sequence that DexEntryMenu's
    # gmatch("(.-)\n") never split on, so the whole entry drew as one
    # overflowing line.
    return ('"' + s.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n") + '"')


def main():
    species = read("pk_pokemon_species.csv")
    pokemon = {int(r["species_id"]): r for r in read("pk_pokemon.csv")
               if r["is_default"] == "1"}
    names = {}
    for r in read("pk_pokemon_species_names.csv"):
        if int(r["local_language_id"]) == ENGLISH:
            names[int(r["pokemon_species_id"])] = r

    flavor = {}
    with open("pk_pokemon_species_flavor_text.csv", newline="",
              encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if int(r["language_id"]) != ENGLISH:
                continue
            sid = int(r["species_id"])
            if not (DEX_MIN <= sid <= DEX_MAX):
                continue
            flavor.setdefault(sid, {})[int(r["version_id"])] = r["flavor_text"]

    entries, texts = {}, {}
    missingText, missingGenus = [], []

    for row in species:
        dex = int(row["id"])
        if not (DEX_MIN <= dex <= DEX_MAX):
            continue
        poke = pokemon.get(dex)
        if not poke:
            continue
        ident = row["identifier"]
        sid = re.sub(r"[^A-Za-z0-9]+", "_", ident).upper().strip("_")

        # genus, e.g. "Leaf Pokemon" -> the dex prints the kind alone, upper
        genus = (names.get(dex) or {}).get("genus") or ""
        kind = genus.replace("Pokémon", "").replace("Pokemon", "").strip()
        kind = kind.upper()[:11]
        if not kind:
            kind = "???"
            missingGenus.append(sid)

        # decimetres -> feet/inches, hectograms -> tenths of a pound
        dm = int(poke["height"] or 0)
        hg = int(poke["weight"] or 0)
        total_in = round(dm * 3.93701)
        ft, inch = divmod(total_in, 12)
        weight_tenths = round(hg * 0.220462 * 10)

        key = None
        body = flavor.get(dex) or {}
        for v in VERSION_PREFERENCE:
            if body.get(v):
                key = "_" + sid.title().replace("_", "") + "DexEntry"
                texts[key] = "\n".join(wrap(body[v]))
                break
        if key is None:
            missingText.append(sid)

        entries[sid] = {
            "kind": kind,
            "heightFt": ft,
            "heightIn": inch,
            "weight": weight_tenths,
            "text": key,
        }

    out = ["-- GENERATED by tools/build_dex_entries.py -- do not edit.",
           "-- dexEntry records plus the text strings they key into.",
           "-- Units match the extractor: heightFt/heightIn are feet and",
           "-- inches, weight is TENTHS of a pound (Abra = 430 = 43.0 lb).",
           "return {", "  ENTRIES = {"]
    for sid in sorted(entries):
        e = entries[sid]
        out.append(("    %s = { kind = %s, heightFt = %d, heightIn = %d, "
                    "weight = %d%s },")
                   % (sid, lua_str(e["kind"]), e["heightFt"], e["heightIn"],
                      e["weight"],
                      (", text = " + lua_str(e["text"])) if e["text"] else ""))
    out.append("  },")
    out.append("  TEXT = {")
    for key in sorted(texts):
        out.append("    [%s] = %s," % (lua_str(key), lua_str(texts[key])))
    out.append("  },")
    out.append("}")

    Path("data/dex_entries.lua").write_text("\n".join(out) + "\n",
                                            encoding="utf-8")
    print("entries: %d   text strings: %d" % (len(entries), len(texts)))
    if missingText:
        print("no flavor text (%d): %s" % (len(missingText),
                                           " ".join(missingText[:12])))
    if missingGenus:
        print("no genus (%d): %s" % (len(missingGenus),
                                     " ".join(missingGenus[:12])))


if __name__ == "__main__":
    main()
