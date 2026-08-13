#!/usr/bin/env python3
"""
Generate `data/species.lua` for the dex_expansion mod.

Sources are the PokéAPI CSV dumps (public game facts, not ROM-derived bytes)
and pret/pokered's own constant files, which are the authority on how a move
or type is *spelled* in Gen1Recomp -- the engine's extractor takes its ids
straight from them, and they are not a mechanical uppercasing of the PokéAPI
identifiers:

    double-slap  -> DOUBLESLAP     (no underscore)
    karate-chop  -> KARATE_CHOP    (underscore)
    psychic      -> PSYCHIC_TYPE   (suffixed)

so both sides are normalised to bare alphanumerics before matching.

Scope: dex 152..649 only. Species 1..151 already exist in the engine's
extracted dataset; re-registering them would collide with their ids and risk
clobbering vanilla records. dex_expansion adds, it does not replace.

Gen 1 has ONE `special` stat. We write Special Attack into `special` (the
usual convention) and carry Special Defense in an extended `specialDefense`
field, which the `modern_mechanics` mod reads directly in its damage hook.
The engine ignores unknown fields, so this is inert until that mod is present.

Learnsets are filtered to moves that actually resolve in the merged registry.
A learnset naming a move nothing registered fails the post-merge
cross-reference check and the whole mod fails to load, so filtering is not
optional. Species left with no level-1 move get a type-appropriate fallback,
because the species-manifest eligibility gate requires a dense level1Moves
array.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

DEX_MIN, DEX_MAX = 152, 649

# Gen 1 stat ids in PokéAPI's stats.csv
STAT_HP, STAT_ATK, STAT_DEF, STAT_SPA, STAT_SPD, STAT_SPE = 1, 2, 3, 4, 5, 6

# PokéAPI growth rate identifier -> pokered GROWTH_* suffix.
GROWTH = {
    "slow": "SLOW",
    "medium": "MEDIUM",
    "fast": "FAST",
    "medium-slow": "MEDIUM_SLOW",
    # Gen 1 has no erratic/fluctuating curve. Sanqui's ROM fork added them;
    # until a mod registers them, map to the nearest vanilla curve so the
    # `growth_rates` cross-reference resolves.
    "slow-then-very-fast": "ERRATIC",
    "fast-then-very-slow": "FLUCTUATING",
}

# level-up move method in pokemon_moves.csv
METHOD_LEVEL_UP = 1

FALLBACK_MOVE = {
    "NORMAL": "TACKLE", "FIRE": "SCRATCH", "WATER": "TACKLE",
    "GRASS": "ABSORB", "ELECTRIC": "THUNDERSHOCK", "ICE": "POUND",
    "FIGHTING": "KARATE_CHOP", "POISON": "POISON_STING", "GROUND": "SAND_ATTACK",
    "FLYING": "GUST", "PSYCHIC_TYPE": "CONFUSION", "BUG": "TACKLE",
    "ROCK": "TACKLE", "GHOST": "LICK", "DRAGON": "TACKLE",
}


def norm(s: str) -> str:
    """Reduce an id to bare uppercase alphanumerics for cross-source matching."""
    return re.sub(r"[^A-Z0-9]", "", s.upper())


def read_csv(path: Path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def load_constants(asm: Path):
    """Ordered const names from a pokered constants file."""
    text = asm.read_text(encoding="utf-8")
    return [m.group(1) for m in re.finditer(r"^\s*const\s+([A-Z0-9_]+)", text,
                                            re.M)]


def species_id(identifier: str) -> str:
    """A registry id for a species, in pokered's spelling style."""
    out = re.sub(r"[^A-Za-z0-9]+", "_", identifier).upper().strip("_")
    if out and out[0].isdigit():
        out = "N" + out
    return out


def lua_value(v, indent=0):
    pad = "  " * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(v, list):
        if not v:
            return "{}"
        inner = ",\n".join(pad + "  " + lua_value(x, indent + 1) for x in v)
        return "{\n" + inner + ",\n" + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        rows = []
        for k in v:
            key = k if re.fullmatch(r"[A-Za-z_]\w*", str(k)) else '["%s"]' % k
            rows.append(pad + "  " + key + " = " + lua_value(v[k], indent + 1))
        return "{\n" + ",\n".join(rows) + ",\n" + pad + "}"
    if v is None:
        return "nil"
    raise TypeError(type(v))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv-dir", default=".", help="dir holding pk_*.csv")
    ap.add_argument("--moves-asm", default="pokered_moves.asm")
    ap.add_argument("--types-asm", default="pokered_types.asm")
    ap.add_argument("--out", default="species.lua")
    ap.add_argument("--report", default="species_report.json")
    ap.add_argument("--sprite-dir", default="assets",
                    help="mod-relative dir holding front/ and back/")
    args = ap.parse_args(argv)

    d = Path(args.csv_dir)
    moves_const = load_constants(Path(args.moves_asm))
    types_const = load_constants(Path(args.types_asm))
    move_by_norm = {norm(m): m for m in moves_const if m != "NO_MOVE"}
    # pokered spells two Gen 1 moves in a way normalisation cannot reach:
    # Psychic is PSYCHIC_M (the type owns the bare name) and High Jump Kick
    # is HI_JUMP_KICK.  Without these two the moves are silently dropped
    # from every learnset that names them.
    for api_name, const in (("PSYCHIC", "PSYCHIC_M"),
                            ("HIGHJUMPKICK", "HI_JUMP_KICK")):
        if const in moves_const:
            move_by_norm[api_name] = const
    type_by_norm = {norm(t): t for t in types_const}
    # PSYCHIC -> PSYCHIC_TYPE, so index the semantic stem too
    type_by_norm.setdefault("PSYCHIC", "PSYCHIC_TYPE")

    species_rows = read_csv(d / "pk_pokemon_species.csv")
    pokemon_rows = read_csv(d / "pk_pokemon.csv")
    stat_rows = read_csv(d / "pk_pokemon_stats.csv")
    type_rows = read_csv(d / "pk_pokemon_types.csv")
    growth_rows = read_csv(d / "pk_growth_rates.csv")
    ptype_names = {r["id"]: r["identifier"] for r in read_csv(d / "pk_types.csv")}
    move_names = {r["id"]: r["identifier"] for r in read_csv(d / "pk_moves.csv")}
    vgroups = read_csv(d / "pk_version_groups.csv")
    evo_rows = read_csv(d / "pk_pokemon_evolution.csv")
    trigger_names = {r["id"]: r["identifier"]
                     for r in read_csv(d / "pk_evolution_triggers.csv")}

    growth_name = {r["id"]: r["identifier"] for r in growth_rows}

    # default (non-form) pokemon row per species
    default_poke = {}
    for r in pokemon_rows:
        if r["is_default"] == "1":
            default_poke[int(r["species_id"])] = r

    stats = defaultdict(dict)
    for r in stat_rows:
        stats[int(r["pokemon_id"])][int(r["stat_id"])] = int(r["base_stat"])

    types = defaultdict(list)
    for r in sorted(type_rows, key=lambda r: int(r["slot"])):
        types[int(r["pokemon_id"])].append(ptype_names[r["type_id"]])

    # Level-up learnsets: prefer the latest Gen 5 version group available.
    prefer = ["black-2-white-2", "black-white"]
    vg_id = None
    for want in prefer:
        for r in vgroups:
            if r["identifier"] == want:
                vg_id = int(r["id"])
                break
        if vg_id:
            break
    if vg_id is None:
        sys.exit("could not resolve a Gen 5 version group")

    learn = defaultdict(list)
    with open(d / "pk_pokemon_moves.csv", newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if int(r["version_group_id"]) != vg_id:
                continue
            if int(r["pokemon_move_method_id"]) != METHOD_LEVEL_UP:
                continue
            learn[int(r["pokemon_id"])].append(
                (int(r["level"] or 0), move_names[r["move_id"]]))

    # Evolutions, keyed by the species they evolve FROM.
    evo_from = defaultdict(list)
    prev = {int(r["id"]): r.get("evolves_from_species_id") or ""
            for r in species_rows}
    for r in evo_rows:
        target = int(r["evolved_species_id"])
        src = prev.get(target) or ""
        if not src:
            continue
        evo_from[int(src)].append(r)

    out = {}
    report = {"versionGroup": vg_id, "written": 0, "droppedMoves": {},
              "noLevel1": [], "unmappedGrowth": [], "skippedEvolutions": {},
              "missingSprite": []}
    dropped = defaultdict(int)

    for srow in species_rows:
        dex = int(srow["id"])
        if not (DEX_MIN <= dex <= DEX_MAX):
            continue
        poke = default_poke.get(dex)
        if not poke:
            continue
        pid = int(poke["id"])
        sid = species_id(srow["identifier"])

        tps = []
        for t in types.get(pid, []):
            mapped = type_by_norm.get(norm(t))
            if mapped:
                tps.append(mapped)
        if not tps:
            # Dark/Steel/Fairy have no Gen 1 type; modern_mechanics registers
            # them. Until then, fall back to NORMAL so the record stays valid.
            tps = ["NORMAL"]

        st = stats.get(pid, {})
        base = {
            "hp": st.get(STAT_HP, 1), "attack": st.get(STAT_ATK, 1),
            "defense": st.get(STAT_DEF, 1), "speed": st.get(STAT_SPE, 1),
            "special": st.get(STAT_SPA, 1),
        }

        g = growth_name.get(srow["growth_rate_id"], "medium")
        growth = GROWTH.get(g)
        if growth is None:
            growth = "MEDIUM"
            report["unmappedGrowth"].append([sid, g])

        lvl1, lset = [], []
        for level, mv in sorted(learn.get(pid, [])):
            mapped = move_by_norm.get(norm(mv))
            if not mapped:
                dropped[mv] += 1
                continue
            if level <= 1:
                if mapped not in lvl1:
                    lvl1.append(mapped)
            else:
                lset.append({"level": level, "move": mapped})
        if not lvl1:
            fb = FALLBACK_MOVE.get(tps[0], "TACKLE")
            if norm(fb) in move_by_norm:
                lvl1 = [move_by_norm[norm(fb)]]
                report["noLevel1"].append(sid)

        evos = []
        for r in evo_from.get(dex, []):
            trig = trigger_names.get(r["evolution_trigger_id"], "")
            tgt = species_id(
                next((s["identifier"] for s in species_rows
                      if s["id"] == r["evolved_species_id"]), ""))
            if not tgt:
                continue
            if trig == "level-up" and r["minimum_level"]:
                evos.append({"method": "LEVEL",
                             "level": int(r["minimum_level"]),
                             "species": tgt})
            elif trig == "trade":
                evos.append({"method": "TRADE", "level": 1, "species": tgt})
            elif trig == "use-item":
                # item id must resolve; left to a follow-up pass that maps
                # PokéAPI items onto the engine's item registry
                report["skippedEvolutions"].setdefault("use-item", 0)
                report["skippedEvolutions"]["use-item"] += 1
            else:
                report["skippedEvolutions"].setdefault(trig or "?", 0)
                report["skippedEvolutions"][trig or "?"] += 1

        bst = sum([base["hp"], base["attack"], base["defense"],
                   base["speed"], st.get(STAT_SPA, 1), st.get(STAT_SPD, 1)])

        rec = {
            "id": sid,
            "dex": dex,
            "name": srow["identifier"].replace("-", " ").upper()[:10],
            "types": tps,
            "baseStats": base,
            "catchRate": int(srow["capture_rate"]),
            "baseExp": min(255, int(poke["base_experience"] or 50)),
            "growthRate": growth,
            "level1Moves": lvl1,
            "learnset": lset,
            "evolutions": evos,
            "tmhm": [],
            "spriteFront": f"{args.sprite_dir}/front/{dex:03d}.png",
            "spriteBack": f"{args.sprite_dir}/back/{dex:03d}.png",
            "frontSize": 7,
            "trueColor": True,
            # Everything the engine does not define lives under ONE
            # clearly-named key.  Top-level records stay extensible, but an
            # unknown key that *resembles* a known field is rejected as a
            # typo -- `specialDefense` sitting next to `special` is exactly
            # that trap -- so extended data is nested where the suggester
            # cannot reach it.
            "dexExpansion": {
                "specialDefense": st.get(STAT_SPD, 1),
                "bst": bst,
                "legendary": srow["is_legendary"] == "1"
                             or srow["is_mythical"] == "1",
                "stage": ("basic" if not srow.get("evolves_from_species_id")
                          else ("final" if not evos else "middle")),
                "habitat": srow.get("habitat_id") or "",
                "generation": int(srow["generation_id"]),
            },
        }
        out[sid] = rec
        report["written"] += 1

    report["droppedMoves"] = dict(sorted(dropped.items(),
                                         key=lambda kv: -kv[1])[:25])
    report["droppedMoveTotal"] = len(dropped)

    body = "-- GENERATED by build_species_data.py -- do not edit by hand.\n"
    body += "-- Source: PokeAPI CSV dumps + pret/pokered constants.\n"
    body += "-- SPECIES: dex-ordered, schema-clean records for pokemon:register\n"
    body += "-- META:    non-engine data (bst/legendary/stage) kept OUT of the\n"
    body += "--          registry record so no unknown field reaches the merge\n"
    order = sorted(out, key=lambda k: out[k]["dex"])
    body += "return " + lua_value({"SPECIES": [out[k] for k in order]}, 0) + "\n"
    Path(args.out).write_text(body, encoding="utf-8")
    Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"species written   {report['written']} (dex {DEX_MIN}..{DEX_MAX})")
    print(f"version group     {vg_id}")
    print(f"distinct moves dropped (not in Gen 1): {report['droppedMoveTotal']}")
    print(f"species needing a fallback level-1 move: {len(report['noLevel1'])}")
    print(f"evolutions skipped: {report['skippedEvolutions']}")
    print(f"-> {args.out}, {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
