# Dex Expansion (Gen 2-5)

Adds National Dex 152-649 to Gen1Recomp as real, catchable species — sprites,
cries, learnsets, evolutions, party icons and Pokedex entries — along with the
Gen 2-5 moves they need and the three types those moves require: **Steel, Dark
and Fairy**.

Every one of them is placed somewhere in Kanto, so the expansion is something
you find while playing rather than a list in a menu. Gym leaders and the Elite
Four get reworked teams, and ordinary trainers stop carrying three of the same
Weedle.

If you would rather keep Kanto's original fifteen types, set
`MOVES & TYPES = RETRO GEN 1` and everything folds back down.

## Options

| Option | What it does |
|---|---|
| `MOVES & TYPES` | **MODERN** keeps real typings and the Gen 2-5 moves. **RETRO GEN 1** retypes everything onto the original fifteen (Dark → Ghost, Steel → Ground, Fairy → Normal) and swaps modern moves for their closest Gen 1 ancestor. |
| `STARTERS` | Which trio waits in Oak's Lab: Kanto, Johto, Hoenn, Sinnoh, Unova, or a seeded random pick. Your rival's team follows suit for the whole game, Champion fight included. |
| `STARTER SEED` | Seeds RANDOM TRIO, so the same text always gives the same three. |
| `SPECIAL STAT` | Gen 1 has one Special stat where later games have two. Choose whether a species uses its **Sp. Attack**, its **Sp. Defense**, or the average. Shuckle is 10, 230 or 120 depending which you pick. |
| `MODERN TRAINERS` | Reworked gym and Elite Four teams, and duplicate Pokemon replaced on ordinary trainers. Off leaves every roster exactly as the ROM had it. |
| `WILD PLACEMENT` | **EXTENDED SLOTS** adds the new species to Kanto's tables. **VANILLA SLOTS** keeps tables at their original ten. **DATA ONLY** writes no encounters at all — use this if another mod owns them. |
| `NEW SPECIES SHARE` | How much of a route's encounter roll goes to the new species: 50%, 70% or 85%. Kanto's originals keep the rest, and keep their original rarity order. |
| `SPECIES IN WILD` | **ALL**, or **RANDOM 151** for a seeded subset roughly the size of the original dex. |
| `SUBSET SEED` | Seeds RANDOM 151. |
| `YIELD TO OTHER MODS` | Leaves routes alone where a catchability mod has already authored them. |

`STARTERS` takes effect immediately — change it and start a new game, no
restart needed. The rest are read at boot.

## What you will run into

**Wild encounters.** All 455 non-legendary species appear somewhere, placed by
terrain, level band and evolution stage rather than at random. Route 1 has
Budew, Burmy, Cherubi and Cottonee at level 2; Cerulean Cave has Metagross and
Hydreigon in the sixties. They are added alongside Kanto's originals, not
instead of them, and the originals keep their original rarity curve — Pidgey is
still the common thing on Route 1, just no longer the only thing.

Legendaries are deliberately excluded from grass. A static legendary should stay
something you go and find.

**Gyms and the Elite Four.** Brock leads with an Aron, so Steel shows up at the
first badge. Koga's two Koffing become Qwilfish and Seviper. Agatha drops Golbat
and Arbok — neither was ever a Ghost — for Misdreavus, Drifblim, Spiritomb and
Mismagius. Giovanni's Kangaskhan becomes Krokorok, which actually is a Ground
type. Bruno finally gets Hitmontop. Lance's two Dragonair become Flygon and
Druddigon, with Kingdra behind them.

Levels are unchanged where a slot is unchanged, and new additions sit inside the
existing band. It is more variety, not a difficulty mod.

**Ordinary trainers** only lose duplicates. A Bug Catcher with two Weedle keeps
one and gets another Bug type of similar strength; a Bird Keeper with three
Pidgey keeps one and gets two other Flying types. Everyone's first of each
species is untouched, so rosters still read like the trainer they belong to.

**Moves.** Species learn their real Gen 2-5 level-up moves — Aron picks up Metal
Claw at 11, Sandile learns Crunch at 28, Houndour gets Nasty Plot in the fifties.
Fairy is the exception: the type postdates the data this was built from, so its
attacking moves are hand-assigned across 23 species.

**Evolutions** that Gen 1 cannot express are mapped rather than dropped. Later
stones map onto the five that exist, and friendship, held items, time of day and
known-move conditions become plain level-ups at sensible levels — Pichu at 10,
Togepi at 12, Yanma at 33, Gligar at 38, Feebas at 40.

## Compatibility

| Mod | Works together? |
|---|---|
| **Kanto Expansion Pak** | Yes. See below. |
| **Pokemon Randomizer** | Yes. It picks up the expanded roster automatically in MERGED DATA mode. It also owns the starter balls, so `STARTERS` steps aside when it is installed. |
| **Modern Kanto** | Yes, no overlap. |
| **All Pokemon Catchable 151** | Yes. Routes it has authored are left to it. |
| **Kanto-Reforged** | Both write encounters heavily. Set `WILD PLACEMENT = DATA ONLY`. |
| **Quality of Life** | Yes, no overlap. |

Kanto's global encounter rarity settings are never modified, so no other mod's
tables are affected.

### Kanto Expansion Pak

Supported, and it needed real work — KEP renumbers the whole Pokedex, adds 100
species of its own and hand-authors every encounter table.

- **Twenty species we both add** (Scizor, Umbreon, Espeon, Blissey, Steelix and
  friends) are left to KEP, since its versions are built for its world. Without
  this the two mods cannot load together at all.
- **Its routes keep their hand-picked encounters.** We add to them rather than
  replace them, exactly as over vanilla Kanto, so KEP's choices stay the common
  sight and our 478 species are still findable.
- **Its Pokedex numbering is left intact.** Ours moves above it, so nothing
  overlaps and no entry goes missing.
- **Its type chart wins**, since it ships a deliberately different one.

Expect some jank at the seams — two large mods sharing one Kanto is always going
to have edges.

3D sprite mods should work: sprites are resolved per species, so a mod loading
after this one replaces them normally.

## Before you start

**Do not remove this mod from a save that has used it.** The game deletes
Pokedex records for species it no longer recognises, so removing it strips every
new species from that save's dex and Hall of Fame. Changing any of the options
above is safe — including switching between MODERN and RETRO — because nothing
is ever unregistered while the mod is installed.

## Known limitations

- **Some added moves have no secondary effect.** Gen 1 supports 82 effects and
  most modern ones have no equivalent. Type, power, accuracy and PP are right;
  some just will not proc.
- **Move animations are borrowed**, not new. Metal Claw plays Scratch's
  animation, and so on.
- **Party icons are shape classes**, as in vanilla. Gen 1 has ten figures and
  each species is assigned the closest fit rather than unique art.
- **Back sprites are derived from the front art**, cropped and zoomed to fill
  the frame the way Gen 1 back pics do.
- A handful of exotic evolution methods have no equivalent and are skipped —
  Shedinja's, Basculin's, Bisharp's, and the Hisui move-style pair.

## Credits

Sprite sheet is community Gen 1-style art (/vp/ lineage). Starter ball wiring
follows the seam established by `ciddmandude/PokemonRecompRandomizer`, and the
live-data encounter approach follows `1Jamie/Kanto-Reforged`. Concept owes a
debt to Sanqui's online randomizer.
