#!/usr/bin/env python3
"""
Generate `data/moves.lua` and `data/retro.lua` for the dex_expansion mod.

Two products, because the mod ships two modes:

  MODERN  every move a Gen 2-5 species learns by level-up is registered as a
          real move, typed with STEEL / DARK / FAIRY where appropriate, its
          effect mapped onto one of Gen 1's 82 move-effect constants, and its
          animation pointed at an existing Gen 1 move that reads right.

  RETRO   nothing new is learned.  Each modern move resolves to its nearest
          Gen 1 ancestor, and species are retyped (DARK->GHOST, STEEL->GROUND,
          FAIRY->NORMAL) so the whole roster fits the original 15-type game.

Both datasets are ALWAYS registered.  Only which one the learnsets *point at*
changes with the option -- same existence/availability rule the species layer
uses, and the reason switching modes cannot corrupt a save: a move a saved mon
knows never stops existing.

Resolution for RETRO is data-driven rather than vibes.  A species' real
learnset is the body-plan signal: something that canonically learns
metal-claw / fury-cutter has claws, so it lands on SCRATCH/SLASH, while
something that learns crunch lands on BITE.  Curated overrides carry flavour;
everything else falls through to "same effective type, same damage class,
closest power", which keeps the tail sane without hand-writing 498 movesets.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

GEN5_VG = 14
METHOD_LEVEL_UP = 1
DEX_MIN, DEX_MAX = 152, 649

# PokéAPI type identifier -> engine type id.  The three new ones are
# registered by the mod itself; BIRD is Gen 1's unused slot and never used.
TYPE_MAP = {
    "normal": "NORMAL", "fighting": "FIGHTING", "flying": "FLYING",
    "poison": "POISON", "ground": "GROUND", "rock": "ROCK", "bug": "BUG",
    "ghost": "GHOST", "fire": "FIRE", "water": "WATER", "grass": "GRASS",
    "electric": "ELECTRIC", "psychic": "PSYCHIC_TYPE", "ice": "ICE",
    "dragon": "DRAGON", "steel": "STEEL", "dark": "DARK", "fairy": "FAIRY",
}

# RETRO retyping: the three modern types collapse onto Gen 1 neighbours.
RETRO_TYPE = {"DARK": "GHOST", "STEEL": "GROUND", "FAIRY": "NORMAL"}

# PokéAPI move_effect_id -> Gen 1 effect constant.  Only the ones Gen 1 can
# actually express; everything else becomes a plain damaging move, which is
# the honest downgrade rather than a broken one.
EFFECT_MAP = {
    1: "NO_ADDITIONAL_EFFECT", 2: "SLEEP_EFFECT", 3: "DRAIN_HP_EFFECT",
    5: "BURN_SIDE_EFFECT1", 6: "FREEZE_SIDE_EFFECT1",
    7: "PARALYZE_SIDE_EFFECT1", 8: "EXPLODE_EFFECT", 9: "DREAM_EATER_EFFECT",
    10: "MIRROR_MOVE_EFFECT", 11: "ATTACK_UP1_EFFECT",
    12: "DEFENSE_UP1_EFFECT", 13: "SPEED_UP1_EFFECT",
    14: "SPECIAL_UP1_EFFECT", 16: "EVASION_UP1_EFFECT",
    18: "SWITCH_AND_TELEPORT_EFFECT", 19: "ATTACK_DOWN1_EFFECT",
    20: "DEFENSE_DOWN1_EFFECT", 21: "SPEED_DOWN1_EFFECT",
    24: "EVASION_DOWN1_EFFECT", 26: "HAZE_EFFECT", 27: "BIDE_EFFECT",
    28: "THRASH_PETAL_DANCE_EFFECT", 29: "SWITCH_AND_TELEPORT_EFFECT",
    30: "TWO_TO_FIVE_ATTACKS_EFFECT", 31: "CONFUSION_EFFECT",
    32: "OHKO_EFFECT", 33: "RECOIL_EFFECT", 34: "POISON_EFFECT",
    35: "PARALYZE_EFFECT", 36: "NO_ADDITIONAL_EFFECT",
    38: "HEAL_EFFECT", 39: "LIGHT_SCREEN_EFFECT", 40: "REFLECT_EFFECT",
    41: "POISON_SIDE_EFFECT1", 42: "FLINCH_SIDE_EFFECT1",
    43: "TRAPPING_EFFECT", 44: "CHARGE_EFFECT", 45: "SUPER_FANG_EFFECT",
    46: "SPECIAL_DAMAGE_EFFECT", 47: "MIST_EFFECT",
    48: "FOCUS_ENERGY_EFFECT", 49: "CONFUSION_SIDE_EFFECT",
    50: "DISABLE_EFFECT", 66: "ATTACK_UP2_EFFECT", 67: "DEFENSE_UP2_EFFECT",
    68: "SPEED_UP2_EFFECT", 69: "SPECIAL_UP2_EFFECT",
    70: "ATTACK_DOWN2_EFFECT", 71: "DEFENSE_DOWN2_EFFECT",
    72: "SPEED_DOWN2_EFFECT", 73: "SPECIAL_DOWN2_EFFECT",
    77: "CONFUSION_EFFECT", 79: "PARALYZE_EFFECT", 84: "LEECH_SEED_EFFECT",
    86: "PARALYZE_EFFECT", 93: "SUBSTITUTE_EFFECT",
    108: "FLINCH_SIDE_EFFECT1", 112: "FLY_EFFECT", 139: "ATTACK_UP1_EFFECT",
    140: "DEFENSE_UP1_EFFECT", 141: "SPECIAL_UP1_EFFECT",
    151: "ATTACK_TWICE_EFFECT", 152: "JUMP_KICK_EFFECT",
}

# Animation reuse: a new move borrows an existing Gen 1 move's animation.
# Curated where the read matters, then a per-type default for the tail.
ANIM_BY_MOVE = {
    "METAL_CLAW": "SCRATCH", "IRON_TAIL": "SLAM", "STEEL_WING": "WING_ATTACK",
    "CRUNCH": "BITE", "BITE_DARK": "BITE", "FEINT_ATTACK": "QUICK_ATTACK",
    "PURSUIT": "QUICK_ATTACK", "SUCKER_PUNCH": "QUICK_ATTACK",
    "SHADOW_BALL": "NIGHT_SHADE", "SHADOW_CLAW": "SCRATCH",
    "DARK_PULSE": "NIGHT_SHADE", "NIGHT_SLASH": "SLASH",
    "DAZZLING_GLEAM": "SWIFT", "MOONBLAST": "SWIFT", "PLAY_ROUGH": "SLAM",
    "FAIRY_WIND": "GUST", "DRAINING_KISS": "ABSORB",
    "FLASH_CANNON": "SWIFT", "MIRROR_SHOT": "SWIFT",
    "AERIAL_ACE": "WING_ATTACK", "AIR_SLASH": "GUST",
    "ICE_FANG": "BITE", "FIRE_FANG": "BITE", "THUNDER_FANG": "BITE",
    "ZEN_HEADBUTT": "HEADBUTT", "IRON_HEAD": "HEADBUTT",
    "POWER_WHIP": "VINE_WHIP", "SEED_BOMB": "EGG_BOMB",
    "ENERGY_BALL": "SOLARBEAM", "MUD_SHOT": "MUD_SLAP" ,
    "ROCK_TOMB": "ROCK_THROW", "ROCK_BLAST": "ROCK_THROW",
    "AQUA_TAIL": "SLAM", "WATERFALL": "SURF", "BRINE": "WATER_GUN",
    "BULLET_PUNCH": "COMET_PUNCH", "DRAIN_PUNCH": "MEGA_PUNCH",
    "POISON_JAB": "POISON_STING", "CROSS_POISON": "SLASH",
    "X_SCISSOR": "SLASH", "BUG_BITE": "BITE", "SIGNAL_BEAM": "SWIFT",
}
ANIM_BY_TYPE = {
    "NORMAL": "TACKLE", "FIGHTING": "KARATE_CHOP", "FLYING": "GUST",
    "POISON": "POISON_STING", "GROUND": "DIG", "ROCK": "ROCK_THROW",
    "BUG": "TACKLE", "GHOST": "NIGHT_SHADE", "FIRE": "EMBER",
    "WATER": "WATER_GUN", "GRASS": "VINE_WHIP", "ELECTRIC": "THUNDERSHOCK",
    "PSYCHIC_TYPE": "CONFUSION", "ICE": "ICE_BEAM", "DRAGON": "DRAGON_RAGE",
    "STEEL": "SCRATCH", "DARK": "BITE", "FAIRY": "SWIFT",
}

# RETRO curated substitutions: flavour the power-matcher would miss.
RETRO_OVERRIDE = {
    "metal-claw": "SCRATCH", "shadow-claw": "SLASH", "night-slash": "SLASH",
    "x-scissor": "SLASH", "cross-poison": "SLASH", "fury-cutter": "SCRATCH",
    "crunch": "BITE", "bite": "BITE", "ice-fang": "BITE",
    "fire-fang": "BITE", "thunder-fang": "BITE", "poison-fang": "BITE",
    "iron-tail": "SLAM", "aqua-tail": "SLAM", "play-rough": "SLAM",
    "dragon-tail": "SLAM", "power-whip": "VINE_WHIP",
    "steel-wing": "WING_ATTACK", "aerial-ace": "WING_ATTACK",
    "brave-bird": "SKY_ATTACK", "air-slash": "GUST", "fairy-wind": "GUST",
    "shadow-ball": "NIGHT_SHADE", "dark-pulse": "NIGHT_SHADE",
    "zen-headbutt": "HEADBUTT", "iron-head": "HEADBUTT",
    "bullet-punch": "COMET_PUNCH", "mach-punch": "COMET_PUNCH",
    "drain-punch": "MEGA_PUNCH", "close-combat": "SUBMISSION",
    "energy-ball": "SOLARBEAM", "seed-bomb": "EGG_BOMB",
    "giga-drain": "MEGA_DRAIN", "draining-kiss": "ABSORB",
    "dazzling-gleam": "SWIFT", "moonblast": "SWIFT",
    "flash-cannon": "SWIFT", "signal-beam": "SWIFT",
    "waterfall": "SURF", "brine": "WATER_GUN", "aqua-jet": "QUICK_ATTACK",
    "sucker-punch": "QUICK_ATTACK", "feint-attack": "QUICK_ATTACK",
    "pursuit": "QUICK_ATTACK", "extreme-speed": "QUICK_ATTACK",
    "rock-tomb": "ROCK_THROW", "rock-blast": "ROCK_THROW",
    "stone-edge": "ROCK_SLIDE", "earth-power": "EARTHQUAKE",
    "mud-shot": "MUD_SLAP", "poison-jab": "POISON_STING",
    "sludge-bomb": "SLUDGE", "gunk-shot": "SLUDGE",
    "heat-wave": "FLAMETHROWER", "flare-blitz": "FIRE_BLAST",
    "wild-charge": "THUNDERBOLT", "volt-switch": "THUNDERSHOCK",
    "ice-shard": "ICE_BEAM", "icicle-crash": "ICE_BEAM",
    "dragon-claw": "SLASH", "dragon-pulse": "DRAGON_RAGE",
    "outrage": "THRASH", "psycho-cut": "SLASH", "zap-cannon": "THUNDER",
    "hyper-voice": "SCREECH", "body-press": "BODY_SLAM",
}

# Gen 1 status/utility moves are kept as-is when a modern status move maps
# cleanly; otherwise a status move with no ancestor is simply dropped in
# RETRO rather than becoming a damaging move.
NORM = lambda s: re.sub(r"[^A-Z0-9]", "", s.upper())


def load_constants(path):
    text = Path(path).read_text(encoding="utf-8")
    out, seen_end = [], False
    for m in re.finditer(r"^\s*const\s+([A-Z0-9_]+)", text, re.M):
        name = m.group(1)
        if name.endswith("_ANIM") or re.fullmatch(r"ANIM_[0-9A-F]{2}", name):
            seen_end = True
            continue
        if not seen_end:
            out.append(name)
    return out


def read_csv(p):
    with open(p, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def lua(v, indent=0):
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
        return "{\n" + ",\n".join(pad + "  " + lua(x, indent + 1)
                                  for x in v) + ",\n" + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        rows = []
        for k in v:
            key = k if re.fullmatch(r"[A-Za-z_]\w*", str(k)) else '["%s"]' % k
            rows.append(pad + "  " + key + " = " + lua(v[k], indent + 1))
        return "{\n" + ",\n".join(rows) + ",\n" + pad + "}"
    return "nil"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv-dir", default=".")
    ap.add_argument("--moves-asm", default="pokered_moves.asm")
    ap.add_argument("--out-moves", default="moves.lua")
    ap.add_argument("--out-retro", default="retro.lua")
    ap.add_argument("--report", default="moves_report.json")
    args = ap.parse_args(argv)

    d = Path(args.csv_dir)
    gen1 = [m for m in load_constants(args.moves_asm) if m != "NO_MOVE"]
    gen1_by_norm = {NORM(m): m for m in gen1}
    gen1_by_norm["PSYCHIC"] = "PSYCHIC_M"
    gen1_by_norm["HIGHJUMPKICK"] = "HI_JUMP_KICK"

    moves = read_csv(d / "pk_moves.csv")
    types = {r["id"]: r["identifier"] for r in read_csv(d / "pk_types.csv")}
    species = read_csv(d / "pk_pokemon_species.csv")
    pokes = {int(r["id"]): r for r in read_csv(d / "pk_pokemon.csv")
             if r["is_default"] == "1"}
    in_range = {int(r["id"]) for r in species
                if DEX_MIN <= int(r["id"]) <= DEX_MAX}

    # which moves are actually reachable by level-up in our dex range
    needed = set()
    with open(d / "pk_pokemon_moves.csv", newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if int(r["version_group_id"]) != GEN5_VG:
                continue
            if int(r["pokemon_move_method_id"]) != METHOD_LEVEL_UP:
                continue
            if int(r["pokemon_id"]) in in_range:
                needed.add(int(r["move_id"]))

    by_id = {int(r["id"]): r for r in moves}

    # Gen 1 move facts, for the retro power-matcher
    gen1_facts = []
    for r in moves:
        const = gen1_by_norm.get(NORM(r["identifier"]))
        if not const:
            continue
        gen1_facts.append({
            "const": const,
            "type": TYPE_MAP.get(types.get(r["type_id"], ""), "NORMAL"),
            "power": int(r["power"] or 0),
            "cls": int(r["damage_class_id"] or 1),
        })

    new_moves, retro, report = {}, {}, {
        "needed": len(needed), "registered": 0, "alreadyGen1": 0,
        "retroOverride": 0, "retroMatched": 0, "retroDropped": [],
        "effectFallback": 0, "newTypes": defaultdict(int),
    }

    for mid in sorted(needed):
        r = by_id.get(mid)
        if not r:
            continue
        ident = r["identifier"]
        const = gen1_by_norm.get(NORM(ident))
        if const:
            report["alreadyGen1"] += 1
            retro[const] = const
            continue

        name = re.sub(r"[^A-Za-z0-9]+", "_", ident).upper().strip("_")
        api_type = types.get(r["type_id"], "normal")
        etype = TYPE_MAP.get(api_type, "NORMAL")
        cls = int(r["damage_class_id"] or 1)
        power = min(255, int(r["power"] or 0))
        acc = min(100, int(r["accuracy"] or 100))
        pp = min(64, max(1, int(r["pp"] or 10)))
        eff_id = int(r["effect_id"] or 1)
        eff = EFFECT_MAP.get(eff_id)
        if eff is None:
            eff = "NO_ADDITIONAL_EFFECT"
            report["effectFallback"] += 1

        anim = ANIM_BY_MOVE.get(name) or ANIM_BY_TYPE.get(etype, "TACKLE")
        anim_const = gen1_by_norm.get(NORM(anim), "TACKLE")

        new_moves[name] = {
            "id": name,
            "name": ident.replace("-", " ").upper()[:12],
            "type": etype,
            "power": power,
            "accuracy": acc,
            "pp": pp,
            "effect": eff,
            "anim": anim_const,
            "category": {1: "status", 2: "physical", 3: "special"}.get(cls,
                                                                       "physical"),
        }
        if etype in ("STEEL", "DARK", "FAIRY"):
            report["newTypes"][etype] += 1
        report["registered"] += 1

        # ---- RETRO resolution
        ov = RETRO_OVERRIDE.get(ident)
        if ov and NORM(ov) in gen1_by_norm:
            retro[name] = gen1_by_norm[NORM(ov)]
            report["retroOverride"] += 1
            continue
        if cls == 1:
            # a status move with no Gen 1 ancestor is dropped, not faked
            report["retroDropped"].append(name)
            continue
        want = RETRO_TYPE.get(etype, etype)
        cands = [g for g in gen1_facts if g["type"] == want and g["cls"] == cls
                 and g["power"] > 0]
        if not cands:
            cands = [g for g in gen1_facts if g["cls"] == cls and g["power"] > 0]
        if not cands:
            report["retroDropped"].append(name)
            continue
        best = min(cands, key=lambda g: abs(g["power"] - power))
        retro[name] = best["const"]
        report["retroMatched"] += 1

    Path(args.out_moves).write_text(
        "-- GENERATED by build_moves.py -- do not edit by hand.\nreturn "
        + lua(new_moves) + "\n", encoding="utf-8")
    Path(args.out_retro).write_text(
        "-- GENERATED by build_moves.py -- modern move id -> Gen 1 ancestor.\n"
        "-- A move absent from this table has no Gen 1 equivalent and is\n"
        "-- removed from learnsets in RETRO mode.\nreturn "
        + lua(retro) + "\n", encoding="utf-8")
    report["newTypes"] = dict(report["newTypes"])
    report["retroDroppedCount"] = len(report["retroDropped"])
    report["retroDropped"] = sorted(report["retroDropped"])[:40]
    Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"level-up moves needed      {report['needed']}")
    print(f"  already in Gen 1         {report['alreadyGen1']}")
    print(f"  newly registered         {report['registered']}")
    print(f"  new-type moves           {report['newTypes']}")
    print(f"  effect fell back to none {report['effectFallback']}")
    print(f"retro: curated overrides   {report['retroOverride']}")
    print(f"retro: power-matched       {report['retroMatched']}")
    print(f"retro: dropped (status)    {report['retroDroppedCount']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
