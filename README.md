# Dex Expansion (Gen 2-5) for Gen1Recomp

Adds National Dex **152-649** as real species with sprites, learnsets,
evolutions, party icons and Pokedex entries; the **373** Gen 2-5 level-up moves
they need; and the **STEEL / DARK / FAIRY** types those moves require.
Optionally swaps Oak's starters for any generation's trio and spreads the whole
roster across Kanto's wild encounter tables.

Everything can be folded back into Gen 1's original fifteen types with
`MOVES & TYPES = RETRO GEN 1`.

## Install

Copy the repository contents into a folder in your Gen1Recomp `mods/`
directory so you end up with `mods/dex_expansion/main.lua`, then enable it in
the mod manager (F10). Use an underscore in the folder name, not a space.

Then, once, for Pokedex flavour text (see *Generated data* below):

```
python3 tools/build_dex_entries.py
```

## Seeing the log

There is no log file. `src/core/Logger.lua` uses plain `print`, so output goes
to **stdout** and nowhere else. To read it:

- **Windows:** from a Command Prompt in the game folder,
  `Play-Windows.bat > log.txt 2>&1`, then open `log.txt`.
- **macOS/Linux:** run `love .` from a terminal, or `./Play-Mac.command`
  from a terminal rather than by double-clicking.

Lines this mod prints on a successful boot:

```
registered 498 species (0 skipped)
registered 3 types, 38 matchups, 373 moves
registered 498 dex entry texts
assigned 498 party icons (BIRD=63 ...)
placed 455 wild slots (0 maps yielded to other mods)
wild reconcile: 455 slots added, 55 bucket tables widened
starters: CYNDAQUIL / TOTODILE / CHIKORITA
retargeted N rival party slots onto the chosen trio
```

If the `wild reconcile` line reports 0 slots added, wild placement is not
reaching the game and that is the line to report.

## Options

| Option | Values | Default |
|---|---|---|
| `MOVES & TYPES` | MODERN / RETRO GEN 1 | MODERN |
| `STARTERS` | VANILLA (KANTO) / JOHTO / HOENN / SINNOH / UNOVA / RANDOM TRIO | VANILLA |
| `STARTER SEED` | text | blank |
| `WILD PLACEMENT` | EXTENDED SLOTS / VANILLA SLOTS / DATA ONLY | EXTENDED |
| `SPECIES IN WILD` | ALL / RANDOM 151 | ALL |
| `SUBSET SEED` | text | blank |
| `YIELD TO OTHER MODS` | on / off | on |

**MODERN** keeps real typings and the new moves. **RETRO GEN 1** retypes onto
the original fifteen (DARK to GHOST, STEEL to GROUND, FAIRY to NORMAL) and
resolves every modern move to its nearest Gen 1 ancestor; a status move with no
ancestor is dropped rather than faked into a damaging one.

**STARTERS** replaces the three balls in Oak's Lab and retargets the rival's
rosters stage-for-stage along the evolution line, so his Kanto starters become
the matching members of your trio in every rival battle including the Champion
fight. Slot types are preserved - left fire, middle water, right grass - so his
counter-pick still works. RANDOM TRIO is seeded.

**Use `WILD PLACEMENT = DATA ONLY`** when the randomizer or a catchability mod
owns wild encounters. That is the zero-conflict configuration.

## Wild placement

All 455 non-legendary species appear somewhere in Kanto, **appended alongside**
each table's vanilla ten rather than replacing them, so Kanto's own roster
survives underneath. Legendaries are excluded: a static legendary is a designed
encounter, not something to sprinkle into grass.

Placement is scored on terrain (from the map id, matched against PokeAPI
habitat where it exists and species types where it does not), BST against the
map's vanilla level band, and evolution stage. Route 1 gets Budew, Burmy,
Cherubi, Cottonee and friends at level 2; Cerulean Cave gets Rampardos,
Metagross and Hydreigon in the sixties.

Widening a table to 20 slots keeps the **vanilla rarity curve** for the
original ten, compressed into the half of the roll they still occupy:

```
26 51 71 83 96 108 115 121 127 128 | 141 154 166 179 192 205 218 230 243 256
vanilla ten, curve intact           | appended rows, even
```

An even spread across all twenty would make the 1%-tail slot as common as the
20% lead slot. A table still at ten slots is left completely alone so it keeps
using `constants.encounterBuckets` exactly as vanilla does.

Rows are written both through the `encounters` registry and, because that alone
did not reach the game, directly to live `Data.encounters` on `game.ready` and
again on every `map.entered`. Both passes are idempotent by species membership.

## Evolutions

Gen 1 has five stones and no concept of friendship, held items, time of day,
known moves or locations. Rather than drop those evolutions, they are mapped:

- **Stones**: sun to LEAF, dusk/dawn/shiny/peat to MOON, ice to WATER.
- **Conditions**: become plain LEVEL evolutions at commonly-cited levels -
  baby forms early (Pichu 10, Togepi 12), mid-line upgrades where the species
  is actually usable (Yanma 33, Gligar 38), Feebas late at 40 so Milotic stays
  a payoff.
- **One route per target**: a stone beats a level when both existed, because
  two paths to the same species reads as a bug in the dex.

43 evolutions are mapped this way in `data/evolutions_extra.lua`, kept separate
so they stay reviewable instead of vanishing into 500 KB of generated data.

Nine evolutions are **deliberately dropped**, all of them to species past dex
649 (Basculegion, Kingambit, Dudunsparce, Farigiraf, Overqwil, Sneasler,
Wyrdeer, Ursaluna, Runerigus). `evolutions[].species` is an `f.id("pokemon")`
reference, so a target nothing registers is a dangling ref that fails the
post-merge cross-check and takes the **whole mod** down, not just that row.

## The one rule this mod is built on

> **Existence is unconditional. Availability is optional.**

Every species, move and type is registered on **every** boot, whatever the
settings say.

That is a save-safety requirement, not a style choice. The save scrubber
deletes Pokedex flags for species the dataset does not know and blanks Hall of
Fame entries the same way. Because mod options are *global* preferences rather
than per-save state, a settings-driven roster would mean flipping one option
silently destroys dex progress in every existing save. So the options above
change where things **appear**, never whether they **exist**.

Switching modes is therefore safe. **Removing the mod from a live save is
not.**

## Compatibility

| Mod | Overlap |
|---|---|
| `pokemon_randomizer` | None on data - it reads the merged registry, so MERGED DATA picks these species up. It also owns the Oak's Lab ball handlers, so `STARTERS` **yields entirely** when it is installed. Declared an optional dependency for deterministic load order. |
| `modern_kanto` | Safe. It registers no types and no moves, only matchup multipliers and per-move `category`. Where both write a matchup row the intent is identical. |
| `All_Pokemon_Catchable_151` | Safe. It writes bare 10-slot lists across 33 maps; those maps are yielded entirely, but only when that mod is actually installed. |
| `Kanto-Reforged` | Real overlap - it authors encounters heavily. Use `DATA ONLY`. |
| `quality_of_life` | None. It only touches `screens`. |

The global `constants.encounterBuckets` is never modified, so no other mod's
tables are reweighted.

## Generated data

`data/dex_entries.lua` (117 KB of flavour text) is generated locally rather
than committed, because it is too large to be worth versioning:

```
python3 tools/build_dex_entries.py
```

Without it the mod still loads and plays; the Pokedex just shows
"Data unknown." with no height or weight for the new species, and says so in
the log.

The generators need the PokeAPI CSV dumps and pret/pokered constant files in
the working directory. Both are public game facts - no ROM-derived bytes.

```
python3 tools/build_species_data.py --out data/species.lua
python3 tools/build_moves.py --out-moves data/moves.lua --out-retro data/retro.lua
python3 tools/build_dex_entries.py
luajit tools/build_placement.lua /path/to/encounters.lua
python3 tools/split_spritesheet.py SHEET.png -o out/    # --mode dmg for 2bpp
```

`tools/build_placement.lua` wants the engine's extracted `encounters.lua` from
your own cache:

- **Windows** `%APPDATA%\LOVE\pokemon-love2d\data\generated\encounters.lua`
- **macOS** `~/Library/Application Support/LOVE/pokemon-love2d/data/generated/`
- **Linux** `~/.local/share/love/pokemon-love2d/data/generated/`

## Known limitations

- **FAIRY has only 3 level-up moves.** Learnsets come from Black 2/White 2,
  where the type did not exist. Fairy is correct *defensively*; nothing learns
  Moonblast. Rebuilding against a Gen 6+ version group fixes it.
- **264 of 373 new moves have no secondary effect.** Gen 1 has 82 effect
  constants and most modern effects have no equivalent. Type, power, accuracy
  and PP are right; they just do not proc.
- **Back sprites are placeholders** downscaled from the front pic (the engine
  draws back pics at 2x from a 32x32 source).
- **Party icons are shape classes, not per-species art.** Gen 1 has ten
  (MON, BALL, HELIX, FAIRY, BIRD, WATER, BUG, GRASS, SNAKE, QUADRUPED) and each
  species is assigned the closest fit, exactly as vanilla does.
- 30 species fall back to a type-appropriate level-1 move.
- Seven exotic evolution triggers are unmapped: the Hisui move-style pair,
  Shedinja's shed, Basculin's recoil, and Bisharp's three-defeated-Bisharp.

## Development

Nothing in `main.lua` is generated. A mod-relative `require` does **not** work:
the loader runs the entry file with LOVE's package path pointing at the game,
not at the mod, so `require("data.species")` throws on the first line. Engine
requires like `require("src.core.Strings")` still work. Modules are loaded with
`mod:read` plus `loadstring` - note `loadstring`, the Lua 5.1 spelling, because
LOVE runs LuaJIT.

```
sh tests/run_all.sh /path/to/gen1recomp
```

### The five gates

Each was added after a real failure, so none are ceremonial:

1. **LuaJIT syntax.** LOVE runs LuaJIT, i.e. Lua 5.1 *syntax*. `~` `&` `|`
   `<<` `>>` and `//` are Lua 5.3+: `luac -p` from 5.4 accepts them and LuaJIT
   rejects the whole file. **Never validate with lua5.4.**
2. **Manifest**, checked by the engine's own `src/mods/Manifest.lua`.
3. **Load**, both move modes, with mod-relative `require` actively forbidden so
   the test cannot pass for the wrong reason. Also asserts 498 icons, 498 dex
   texts, 43 mapped evolutions and zero un-rewritten sprite paths.
4. **game.ready**, fired with the engine's real `{ game = ... }` payload shape,
   asserting that placement lands, buckets widen, the vanilla curve survives
   and the rival's roster is retargeted. An earlier version only checked that a
   handler was *registered*, which passed through two shipped bugs.
5. **Encounter payload** against the engine's own `Schemas.check`, pinning that
   a `buckets` key is rejected (nested recs are strict) so that regression
   cannot return.

## Credits

Sprite sheet is community Gen 1-style art (/vp/ lineage). The starter ball
wiring follows the seam established by `ciddmandude/PokemonRecompRandomizer`,
and the live-Data encounter fallback follows `1Jamie/Kanto-Reforged`. Concept
owes a debt to Sanqui's online randomizer.
