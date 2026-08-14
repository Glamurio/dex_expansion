# Dex Expansion (Gen 2-5) for Gen1Recomp

Adds National Dex 152-649 to Gen1Recomp as real species: sprites, cries,
learnsets, evolutions, party icons and Pokedex entries. With them come the 276
Gen 2-5 level-up moves they need and the three types those moves require —
Steel, Dark and Fairy.

Optionally swaps Oak's starters for any generation's trio, spreads the whole
roster through Kanto's wild encounter tables, and modernises trainer rosters.
All of it folds back to Gen 1's original fifteen types with
`MOVES & TYPES = RETRO GEN 1`.

## Install

Copy the repository into a folder under your Gen1Recomp `mods/` directory so
you have `mods/dex_expansion/main.lua`, then enable it in the mod manager
(F10). Underscores in the folder name, not spaces.

Once, for Pokedex flavour text:

```
python3 tools/build_dex_entries.py
```

## Reading the log

There is no log file. `src/core/Logger.lua` uses `print`, so output goes to
stdout and nowhere else.

- **Windows:** run `Play-Windows-Log.bat` (included), or from a Command Prompt
  `gen1recomp.exe > log.txt 2>&1`
- **macOS/Linux:** run `love .` from a terminal

A fused `.exe` is a GUI binary and may swallow stdout regardless. The mod
therefore writes its own report every boot, which needs no console:

```
%APPDATA%\LOVE\pokemon-love2d\dex_expansion_report.txt
```

It lists the registration counts, the resolved options, and the live encounter
tables for six sample maps beside what placement intended to add — enough to
tell whether something reached the game or not.

A healthy boot prints:

```
registered 498 species (0 skipped)
registered 3 types, 38 matchups, 276 moves
dexSize set to 649 (3 digits)
registered 498 cries
retyped 7 vanilla species onto modern typings
assigned 498 party icons
wild reconcile: 455 slots added, 55 bucket tables widened
aliased 276 move animations
taught 42 Fairy attacking moves by level-up
trainers: 14 parties overridden, N duplicate slots replaced
```

## Options

| Option | Values | Default |
|---|---|---|
| `MOVES & TYPES` | MODERN / RETRO GEN 1 | MODERN |
| `STARTERS` | VANILLA / JOHTO / HOENN / SINNOH / UNOVA / RANDOM TRIO | VANILLA |
| `STARTER SEED` | text | blank |
| `SPECIAL STAT` | SP. ATTACK / SP. DEFENSE / AVERAGE | SP. ATTACK |
| `MODERN TRAINERS` | on / off | on |
| `WILD PLACEMENT` | EXTENDED SLOTS / VANILLA SLOTS / DATA ONLY | EXTENDED |
| `NEW SPECIES SHARE` | EVEN 50% / FAVOUR NEW 70% / MOSTLY NEW 85% | 70% |
| `SPECIES IN WILD` | ALL / RANDOM 151 | ALL |
| `SUBSET SEED` | text | blank |
| `YIELD TO OTHER MODS` | on / off | on |

**MOVES & TYPES.** MODERN keeps real typings and the Gen 2-5 moves. RETRO
retypes onto the original fifteen (Dark to Ghost, Steel to Ground, Fairy to
Normal) and resolves every modern move to its nearest Gen 1 ancestor; a status
move with no ancestor is dropped rather than faked into a damaging one.

**SPECIAL STAT.** Gen 1 has one Special stat and everything from Gen 2 has two.
SpA is the default because Gen 1's Special is the attacking number in practice.
Shuckle reads 10, 230 or 120 depending on the setting.

**STARTERS** replaces the three balls in Oak's Lab and retargets the rival's
rosters stage-for-stage along the evolution line, so his Kanto starters become
the matching members of your trio in every rival battle including the Champion.
Slot types are preserved — left fire, middle water, right grass — so his
counter-pick still works. Read at talk time, so changing it needs no restart.

**WILD PLACEMENT = DATA ONLY** when the randomizer or a catchability mod owns
wild encounters. That is the zero-conflict configuration.

## Wild placement

All 455 non-legendary species appear somewhere in Kanto, appended alongside each
table's vanilla ten rather than replacing them. Legendaries are excluded: a
static legendary is a designed encounter, not something to sprinkle into grass.

Placement is scored on terrain (from the map id, matched against PokeAPI habitat
where it exists and species types where it does not), BST against the map's
vanilla level band, and evolution stage. Route 1 gets Budew, Burmy, Cherubi and
Cottonee at level 2; Cerulean Cave gets Metagross and Hydreigon in the sixties.

A widened table keeps the vanilla rarity curve for the original ten, compressed
into whatever share of the roll they still hold. At the default 70% new:

```
15 31 42 50 57 65 69 73 76 77 | 95 113 131 149 167 184 202 220 238 256
vanilla ten, curve intact     | appended rows, even
```

An even spread across all twenty would make the 1% tail slot as common as the
20% lead slot. A table still at ten slots is left alone entirely, so it keeps
using `constants.encounterBuckets` exactly as vanilla does.

## Trainers

Gym leaders and the Elite Four get hand-authored rosters in
`data/trainer_overrides.lua`, with each vanilla team quoted above it. Levels
stay at vanilla values where a slot is unchanged, and new slots sit inside the
existing band.

Some of the reads: Koga's two Koffing become Qwilfish and Seviper. Lance's two
Dragonair become Flygon and Druddigon, plus Kingdra. Agatha keeps one Gengar and
the Haunter and loses Golbat and Arbok — never Ghosts — for Misdreavus, Drifblim
and Spiritomb, plus Mismagius. Giovanni's Kangaskhan becomes Krokorok in both
overworld fights and joins the gym team, since Kangaskhan is not Ground and never
fit a Ground gym. Bruno gets Hitmontop, completing the trio his team always
gestured at. Brock gets an Aron, which puts Steel in front of the player at the
first badge.

Every other trainer gets a generic pass that replaces only **repeats**: a Bug
Catcher with two Weedle keeps one and gets something else Bug. A trainer's first
of each species is never touched, so every roster still reads as the same
trainer. Replacements must share a distinguishing type — sharing Normal is a
match on paper and useless in practice — and are deterministic by trainer id, so
a team never reshuffles between boots. Shedinja and legendaries are excluded.

## Moves

276 moves are registered. 102 more were dropped: abilities, held items, weather,
entry hazards, turn order, double-battle moves and Protect-likes. Gen 1 has no
mechanism for any of them, and a button that visibly does nothing reads as a bug.

Secondary effects are mapped onto Gen 1's 82 effect constants, tiered by the
real effect chance so Heat Wave burns at 10% and Scald at 30%. Multi-stat boosts
keep their primary stat, since Gen 1 raises one stat per move: Bulk Up raises
Attack, Calm Mind raises Special.

Moves whose power is computed from something Gen 1 does not track — weight,
speed, HP, friendship, PP — get a flat value or an effect that captures the
intent. Sheer Cold is a real OHKO, Final Gambit is Explosion, Endeavor is Super
Fang, and Beat Up is a 2-5 hit, since Gen 1's multi-hit already means one hit per
party member.

Fairy needed attacking moves of its own; BW2 predates the type, so the dataset
yields only Charm, Moonlight and Sweet Kiss. `data/moves_extra.lua` adds the five
Gen 6 Fairy attacks and `data/fairy_learnsets.lua` gives 23 species 42 level-up
entries for them.

## Evolutions

Gen 1 has five stones and no concept of friendship, held items, time of day,
known moves or locations. Rather than drop those evolutions, 43 are mapped in
`data/evolutions_extra.lua`: sun to Leaf, dusk/dawn/shiny/peat to Moon, ice to
Water; conditions become plain level evolutions at commonly-cited levels (Pichu
10, Togepi 12, Yanma 33, Gligar 38, Feebas 40). One route per target — a stone
beats a level when both existed.

Nine are deliberately dropped, all targeting species past dex 649 (Basculegion,
Kingambit, Dudunsparce, Farigiraf, Overqwil, Sneasler, Wyrdeer, Ursaluna,
Runerigus). `evolutions[].species` is an `f.id("pokemon")` reference, so a target
nothing registers is a dangling ref that fails the post-merge cross-check and
takes the whole mod down.

## The rule this mod is built on

> Existence is unconditional. Availability is optional.

Every species, move and type is registered on every boot, whatever the settings
say. This is a save-safety requirement, not a style choice: the save scrubber
deletes Pokedex flags for species the dataset does not know and blanks Hall of
Fame entries the same way. Because options are global preferences rather than
per-save state, a settings-driven roster would mean flipping one option destroys
dex progress in every existing save.

Switching modes is therefore safe. Removing the mod from a live save is not.

## Compatibility

| Mod | Overlap |
|---|---|
| `pokemon_randomizer` | None on data — it reads the merged registry, so MERGED DATA picks these species up. It owns the Oak's Lab ball handlers, so `STARTERS` yields entirely when it is installed. Declared an optional dependency for deterministic load order. |
| `modern_kanto` | Safe. It registers no types and no moves, only matchup multipliers and per-move `category`. |
| `All_Pokemon_Catchable_151` | Safe. It writes bare 10-slot lists across 33 maps; those maps are yielded, but only when it is actually installed. |
| `Kanto-Reforged` | Real overlap — it authors encounters heavily. Use `DATA ONLY`. |
| `quality_of_life` | None. It only touches `screens`. |

The global `constants.encounterBuckets` is never modified, so no other mod's
tables are reweighted.

3D sprite mods should work: sprites resolve per-species through `spriteFront`
and `spriteBack`, and a mod loading after us patches our records normally. The
one thing to watch is `battle_sprite_scales` — if such a mod keys scales to its
own assets, our species keep the 1x/2x defaults and may look inconsistent
beside them.

## Generated data

`data/dex_entries.lua` (117 KB of flavour text) is generated locally rather than
committed:

```
python3 tools/build_dex_entries.py
```

Without it the mod still loads and plays; the Pokedex shows "Data unknown." for
the new species and says so in the log.

The generators need the PokeAPI CSV dumps and pret/pokered constant files in the
working directory. Both are public game facts — no ROM-derived bytes.

```
python3 tools/build_species_data.py --out data/species.lua
python3 tools/build_moves.py --out-moves data/moves.lua --out-retro data/retro.lua
python3 tools/build_dex_entries.py
luajit tools/build_placement.lua /path/to/encounters.lua
python3 tools/split_spritesheet.py SHEET.png -o out/
python3 tools/back_sprites.py assets/front assets/back --treatment zoom_left
python3 tools/mirror_fronts.py assets/front
python3 tools/lofi_cries.py cries --strength medium
python3 tools/whitespace_report.py assets/front --sheets out/
```

Sprite tooling notes: front pics face left (the enemy faces the player), back
pics face right (your own mon seen from behind). `mirror_fronts.py` leaves a
`.mirrored` sentinel that `back_sprites.py` reads and un-mirrors from, so the two
can be run in either order. Re-run `back_sprites.py` after editing any front pic.

`tools/build_placement.lua` wants the engine's extracted `encounters.lua`:

- **Windows** `%APPDATA%\LOVE\pokemon-love2d\data\generated\encounters.lua`
- **macOS** `~/Library/Application Support/LOVE/pokemon-love2d/data/generated/`
- **Linux** `~/.local/share/love/pokemon-love2d/data/generated/`

## Known limitations

- **Fairy learnsets are hand-authored**, 42 entries across 23 species. Nothing
  else learns a Fairy attack by level-up yet.
- **264 of the added moves have no secondary effect.** Gen 1 has 82 effect
  constants and most modern effects have no equivalent. Type, power, accuracy
  and PP are right; they just do not proc.
- **Move animations are aliased**, not authored. Metal Claw plays Scratch's
  animation. There is no new art here.
- **Party icons are shape classes**, as in vanilla: ten figures, each species
  assigned the closest fit.
- 30 species fall back to a type-appropriate level-1 move.
- Seven exotic evolution triggers are unmapped: the Hisui move-style pair,
  Shedinja's shed, Basculin's recoil, Bisharp's three-defeated-Bisharp.

## Development

A mod-relative `require` does not work: the loader runs the entry file with
LOVE's package path pointing at the game, not the mod, so `require("data.species")`
throws on the first line. Engine requires like `require("src.core.Strings")` are
fine. Modules load with `mod:read` plus `loadstring` — the Lua 5.1 spelling,
because LOVE runs LuaJIT.

```
sh tests/run_all.sh /path/to/gen1recomp
```

### The gates

Each exists because something broke:

1. **LuaJIT syntax.** LOVE runs LuaJIT, i.e. Lua 5.1 syntax. `~` `&` `|` `<<`
   `>>` and `//` are Lua 5.3+: `luac -p` from 5.4 accepts them and LuaJIT
   rejects the file. Never validate with lua5.4.
2. **Manifest**, checked by the engine's own `src/mods/Manifest.lua`.
3. **Load**, both move modes, with mod-relative `require` actively forbidden.
   Asserts 498 icons and dex texts, 43 mapped evolutions, 7 vanilla retypes,
   dexSize 649, 498 cries, no un-rewritten sprite paths, no dangling move
   references, no damaging move at 0 power, no move name over 12 characters.
4. **game.ready**, fired with the engine's real `{ game = ... }` payload shape,
   asserting placement lands, buckets widen, the vanilla curve survives, the
   rival's roster is retargeted, animations resolve and Fairy moves are taught.
5. **New types**, asserting species actually carry Steel, Dark and Fairy in
   modern and none in retro, that the dummy trio's moves deal damage, and that
   the key matchups are right.
6. **Trainers**, asserting the leader rosters apply and no duplicate, Shedinja,
   legendary or empty party survives.
7. **Starters**, driving a real handler to prove the option is read at talk time.
8. **Encounter payload** against the engine's own `Schemas.check`.

Test stubs are held to the same shape as the real API. Two bugs shipped because
a stub was looser than the engine: a `constants` stub that accepted a table
where the real registry wants a key, and registry stubs that referenced nil
globals so every write threw and was swallowed by a `pcall`.

## Credits

Sprite sheet is community Gen 1-style art (/vp/ lineage). Starter ball wiring
follows the seam established by `ciddmandude/PokemonRecompRandomizer`, and the
live-Data encounter fallback follows `1Jamie/Kanto-Reforged`. Concept owes a
debt to Sanqui's online randomizer.
