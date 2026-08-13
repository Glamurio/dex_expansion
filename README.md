# Dex Expansion (Gen 2-5) for Gen1Recomp

Registers National Dex **152-649** as real species, with the Gen 2-5 level-up
moves they need and the STEEL / DARK / FAIRY types those moves require.

## Install

Unzip into a folder inside your Gen1Recomp `mods/` directory, so you end up
with `mods/dex_expansion/main.lua`. Enable it in the mod manager (F10).

Use an underscore in the folder name, not a space.

**`main.lua` is generated.** A mod-relative `require` does not resolve at
runtime -- the loader runs the entry file with LOVE's package path pointing at
the game, not at the mod, so `require("data.species")` throws on the first
line. Engine requires (`require("src.core.Strings")`) still work; mod-relative
ones never do. So every module and every data table is inlined into one file
by `tools/bundle.py`. Edit `src/` and `data/`, then rebuild:

```
python3 tools/bundle.py
sh tests/run_all.sh /path/to/gen1recomp
```

Three gates, each added after a real failure:

1. **LuaJIT syntax.** LOVE runs LuaJIT, i.e. Lua 5.1 *syntax*. `~` `&` `|`
   `<<` `>>` and `//` are Lua 5.3+: `luac -p` from 5.4 accepts them and
   LuaJIT rejects the whole file, so a mod can pass a 5.4 check and still
   fail to load.
2. **Manifest**, validated by the engine's own `src/mods/Manifest.lua`. It is
   pure -- no filesystem, no LOVE -- so it runs standalone and is the only
   opinion that counts. Hand-checking against the docs does not work.
3. **Load**, both modes, with mod-relative `require` actively forbidden so the
   test cannot pass for the wrong reason.

### Auto-update

`github` is absent, which the engine reads as "no auto-update". To enable it,
create a repo and add one line -- it must be `owner/repo` or a github.com URL,
nothing else:

```json
"github": "Glamurio/gen1recomp-dex-expansion"
```

**Validate with LuaJIT, never with `lua5.4`.** LOVE runs LuaJIT, i.e. Lua 5.1
*syntax*. The operators `~` `&` `|` `<<` `>>` and `//` are Lua 5.3+: `luac -p`
from 5.4 accepts them and LuaJIT rejects the whole file, so a mod can pass a
5.4 check and still fail to load. `tests/syntax_check.sh` exists to make that
mistake impossible to repeat.

The test refuses to add the mod directory to `package.path` and errors if a
mod-relative require reaches the engine, so it cannot pass for the wrong
reason.

## The one rule this mod is built on

> **Existence is unconditional. Availability is optional.**

Every species, move and type is registered on **every** boot, whatever the
settings say. Nothing is ever withheld from a registry.

That is a save-safety requirement, not a style choice. The engine's save
scrubber (`src/core/SaveData.lua`) deletes Pokedex flags for species the
dataset does not know, and blanks Hall of Fame entries the same way. Because
mod options are *global* preferences rather than per-save state, a
settings-driven roster would mean flipping one option silently destroys dex
progress in every existing save. So the options below change where things
**appear**, never whether they **exist**.

Corollary: it is still safe to switch modes, but **never remove this mod from
a live save**.

## Options

| Option | Values | Default | Effect |
|---|---|---|---|
| `MOVES & TYPES` | MODERN / RETRO GEN 1 | MODERN | MODERN keeps real typings and the 373 new moves. RETRO retypes onto the original 15 (DARK->GHOST, STEEL->GROUND, FAIRY->NORMAL) and resolves every modern move to its nearest Gen 1 ancestor. |
| `WILD PLACEMENT` | EXTENDED SLOTS / VANILLA SLOTS / DATA ONLY | EXTENDED | EXTENDED widens per-map slot tables so the roster fits. DATA ONLY writes no encounters at all. |
| `SPECIES IN WILD` | ALL / RANDOM 151 | ALL | RANDOM 151 restricts which species *appear*, for a 1:1-feeling run. |
| `SUBSET SEED` | text | blank | Seeds the 151 pick. |
| `YIELD TO OTHER MODS` | on / off | on | Skip maps another mod already curated. |

**Use `DATA ONLY`** when the randomizer or a catchability mod owns wild
placement. That is the zero-conflict configuration.

## Compatibility

Verified by reading each mod's source:

| Mod | Overlap |
|---|---|
| `pokemon_randomizer` | None. It reads the merged registry, so MERGED DATA picks these species up automatically. Declared as an optional dependency so `registerSpeciesMeta` load order is deterministic. |
| `gen1recomp-modern-kanto` | Safe. It registers **no** types and **no** moves, only matchup multipliers and per-move `category`. Where we both write a matchup row the intent is identical. |
| `All_Pokemon_Catchable_151` | Safe *because* we never touch the global bucket table. It writes bare 10-slot lists; widening `constants.encounterBuckets` globally would have left its maps with 10 dead buckets and silently halved their encounter rate. |
| `Kanto-Reforged` | Real overlap - it authors encounters heavily. Use `DATA ONLY` or `YIELD TO OTHER MODS`. |
| QoL mod | None. It only touches `screens`. |

Two engine details make cooperation work:

1. `src/world/Encounter.lua` rolls `grass.buckets or buckets`, so an encounter
   record can carry **its own** bucket table. We never modify the global
   constant.
2. Encounter slots are written with `{ __append = rows }`. On a `record`
   registry a bare list *replaces* wholesale; the wrapper appends, so two mods
   adding rows to one map both land.

A `game.ready` pass rebuilds bucket thresholds from the slot count that
actually survived the merge, because a mod loading after us can still replace
a slot list and desync the counts.

## Known limitations

- **FAIRY has only 3 moves.** Learnsets come from Black 2/White 2, where Fairy
  did not exist, so only retconned Gen 5 moves are present. Fairy works
  correctly *defensively*. Rebuild against a Gen 6+ version group to fix.
- **264 of 373 new moves have no secondary effect.** Gen 1 has 82 effect
  constants and most modern effects have no equivalent. Those moves have
  correct type/power/accuracy/PP but do not proc.
- **Back sprites are placeholders**, downscaled from the front pic (the engine
  draws back pics at 2x from a 32x32 source).
- 23 item-based and 34 friendship-based evolutions are not yet mapped.
- 30 species fall back to a type-appropriate level-1 move.
- Wild placement tables are not authored yet (`Data.PLACEMENT` is empty), so
  EXTENDED currently behaves like DATA ONLY.

## Rebuilding the data

```
python3 tools/build_species_data.py --out data/species.lua
python3 tools/build_moves.py --out-moves data/moves.lua --out-retro data/retro.lua
python3 tools/split_spritesheet.py SHEET.png -o out/      # --mode dmg for 2bpp
python3 tools/bundle.py                                   # REQUIRED after edits
sh tests/syntax_check.sh                                  # LuaJIT parse gate
luajit tests/load_test.lua                                # both modes, offline
```

Data sources are PokeAPI's CSV dumps and pret/pokered's constant files - public
game facts, no ROM-derived bytes.

## Credits

Sprite sheet is community Gen 1-style art (/vp/ lineage). Concept owes a debt to
Sanqui's online randomizer.
