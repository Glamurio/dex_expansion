# Dex Expansion (Gen 2-5) for Gen1Recomp

Adds National Dex **152-649** as real species, the **373** Gen 2-5 level-up
moves they need, and the **STEEL / DARK / FAIRY** types those moves require.
Optionally swaps Oak's starters for any generation's trio.

Everything can also be folded back into Gen 1's original fifteen types with
`MOVES & TYPES = RETRO GEN 1`.

## Install

Copy the repository contents into a folder in your Gen1Recomp `mods/`
directory so you end up with `mods/dex_expansion/main.lua`, then enable it in
the mod manager (F10). Use an underscore in the folder name, not a space.

To confirm it loaded, open the Pokedex: it should show **649** entries instead
of 151. `dexSize` is derived from the highest `dex` in the merged registry, so
that number is the whole data layer reporting in.

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
resolves every modern move to its nearest Gen 1 ancestor; a status move with
no ancestor is dropped rather than faked into a damaging one.

**STARTERS** replaces the three balls in Oak's Lab. Slot types are preserved -
left is fire, middle is water, right is grass, exactly as Charmander /
Squirtle / Bulbasaur are - so the rival's counter-pick still works. RANDOM
TRIO is seeded, so the same `STARTER SEED` always gives the same three.

**Use `WILD PLACEMENT = DATA ONLY`** when the randomizer or a catchability mod
owns wild encounters. That is the zero-conflict configuration.

## The one rule this mod is built on

> **Existence is unconditional. Availability is optional.**

Every species, move and type is registered on **every** boot, whatever the
settings say.

That is a save-safety requirement, not a style choice. The engine's save
scrubber deletes Pokedex flags for species the dataset does not know, and
blanks Hall of Fame entries the same way. Because mod options are *global*
preferences rather than per-save state, a settings-driven roster would mean
flipping one option silently destroys dex progress in every existing save. So
the options above change where things **appear**, never whether they
**exist**.

Switching modes is therefore safe. **Removing the mod from a live save is
not.**

## Compatibility

| Mod | Overlap |
|---|---|
| `pokemon_randomizer` | None on data - it reads the merged registry, so MERGED DATA picks these species up. It also owns the Oak's Lab ball handlers, so `STARTERS` **yields entirely** when it is installed. Declared an optional dependency for deterministic load order. |
| `modern_kanto` | Safe. It registers no types and no moves, only matchup multipliers and per-move `category`. Where both write a matchup row the intent is identical. |
| `All_Pokemon_Catchable_151` | Safe, because this mod never touches the global bucket table. It writes bare 10-slot lists; widening `constants.encounterBuckets` globally would leave its maps with 10 dead buckets and silently halve their encounter rate. |
| `Kanto-Reforged` | Real overlap - it authors encounters heavily. Use `DATA ONLY`. |
| `quality_of_life` | None. It only touches `screens`. |

Three engine details make cooperation work:

1. `Encounter.roll` reads `grass.buckets or buckets`, so an encounter record
   carries **its own** bucket table. The global constant is never modified.
2. Encounter slots are written with `{ __append = rows }`. On a `record`
   registry a bare list *replaces* wholesale; the wrapper appends.
3. `map_scripts` is a **compose** registry, so the starter contribution
   replaces only three talk keys and leaves the rest of Oak's Lab
   engine-owned.

A `game.ready` pass rebuilds bucket thresholds from the slot count that
survived the merge, since a mod loading later can still replace a slot list.

## Known limitations

- **Wild placement is not authored yet.** `Data.PLACEMENT` is empty, so
  `EXTENDED SLOTS` currently behaves like `DATA ONLY` and every route stays
  vanilla - Route 1 really is still just Rattata and Pidgey. This is the next
  feature, and it needs the map ids from a `data/generated/encounters.lua`.
- **FAIRY has only 3 level-up moves.** Learnsets come from Black 2/White 2,
  where the type did not exist. Fairy is correct *defensively*; nothing learns
  Moonblast. Rebuilding against a Gen 6+ version group fixes it.
- **264 of 373 new moves have no secondary effect.** Gen 1 has 82 effect
  constants and most modern effects have no equivalent. Type, power, accuracy
  and PP are right; they just do not proc.
- **Back sprites are placeholders** downscaled from the front pic (the engine
  draws back pics at 2x from a 32x32 source).
- 23 item-based and 34 friendship-based evolutions are not mapped.
- 30 species fall back to a type-appropriate level-1 move.

## Building

`main.lua` is a thin entry point that loads `src/` and `data/` at runtime with
`mod:read` plus `loadstring`, which is the sanctioned seam (and the one
`quality_of_life` uses). A mod-relative `require` does **not** work: the loader
runs the entry file with LOVE's package path pointing at the game, not at the
mod, so `require("data.species")` throws on the first line. Engine requires
like `require("src.core.Strings")` still work; mod-relative ones never do.
Note `loadstring` rather than `load` - LOVE runs LuaJIT, i.e. Lua 5.1.

Nothing is generated, so editing `src/` or `data/` takes effect directly:

```
sh tests/run_all.sh /path/to/gen1recomp
```

To regenerate the data itself:

```
python3 tools/build_species_data.py --out data/species.lua
python3 tools/build_moves.py --out-moves data/moves.lua --out-retro data/retro.lua
python3 tools/split_spritesheet.py SHEET.png -o out/    # --mode dmg for 2bpp
```

Sources are PokeAPI's CSV dumps and pret/pokered's constant files - public
game facts, no ROM-derived bytes.

### The four gates

Each was added after a real failure, so none of them are ceremonial:

1. **LuaJIT syntax.** LOVE runs LuaJIT, i.e. Lua 5.1 *syntax*. The operators
   `~` `&` `|` `<<` `>>` and `//` are Lua 5.3+: `luac -p` from 5.4 accepts
   them and LuaJIT rejects the whole file. **Never validate with lua5.4.**
2. **Manifest**, checked by the engine's own `src/mods/Manifest.lua`. It is
   pure - no filesystem, no LOVE - so it runs standalone and is the only
   opinion that counts.
3. **Load**, both move modes, with mod-relative `require` actively forbidden
   so the test cannot pass for the wrong reason. Modules load through a
   `mod:read` stub, the way the engine provides them.
4. **Starters**, asserting on the generated script rows: every trio names a
   registered species, `give_pokemon` fires with the right species and level,
   `EVENT_GOT_STARTER` and the per-ball chose flag are both set, and the rival
   never takes your species. Missing a flag write soft-locks the intro,
   because Oak's script advances off them.

## Credits

Sprite sheet is community Gen 1-style art (/vp/ lineage). The starter ball
wiring follows the seam established by `ciddmandude/PokemonRecompRandomizer`.
Concept owes a debt to Sanqui's online randomizer.
