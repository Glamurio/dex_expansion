-- Dex Expansion -- registers species beyond the original 151 for Gen1Recomp.
--
-- The one architectural rule this mod is built around:
--
--     Existence is unconditional.  Availability is optional.
--
-- Every species in data/species.lua is registered on every boot, regardless
-- of settings.  Nothing is ever withheld from the `pokemon` registry.
--
-- This is a save-safety requirement rather than a style preference.  The
-- engine's save scrubber (src/core/SaveData.lua) deletes dex flags for
-- species the dataset does not know:
--
--     for id in pairs(dex[key]) do
--       if not known(data.pokemon, id) then dex[key][id] = nil end
--     end
--
-- ...and blanks Hall of Fame entries the same way.  Because mod options are
-- global preferences rather than per-save state, a settings-driven roster
-- would mean flipping one option destroys dex progress in every existing save.
-- So the "151 subset" option restricts where species appear -- encounters, and
-- trainer parties -- never whether they exist.
--
-- The one exception is the twenty species KEP also provides; see
-- src/kep_compat.lua for why standing down there preserves the rule rather
-- than breaking it.
--
-- Species are string-keyed and saves are Lua source, so there is no 255-index
-- ceiling anywhere in the gameplay path.  dexSize is a different story -- see
-- the dex size section.

local mod = ...

-- ---------------------------------------------------------------- loading
-- A mod-relative `require` does not resolve at runtime: the loader runs this
-- file via chunk(api) with LOVE's package path pointing at the game, not at
-- the mod, so require("data.species") throws on the first line.  Engine
-- requires (require("src.core.Strings")) still work.  mod:read + loadstring is
-- the sanctioned seam -- the same one quality_of_life uses -- and `loadstring`
-- is the Lua 5.1 spelling, which matters because LOVE runs LuaJIT.

local compile = loadstring or load

local function loadModule(path, ...)
  local source, readError = mod:read(path)
  if not source then
    mod.log:error("cannot read %s: %s; reinstall the mod", path,
      tostring(readError))
    error("cannot read " .. path, 0)
  end
  local chunk, compileError = compile(source, "@" .. mod.path .. "/" .. path)
  if not chunk then
    mod.log:error("cannot compile %s: %s; reinstall the mod", path,
      tostring(compileError))
    error("cannot compile " .. path, 0)
  end
  return chunk(...)
end

local Data = loadModule("data/species.lua")
local NewMoves = loadModule("data/moves.lua")
local Retro = loadModule("data/retro.lua")
-- Attacking Fairy moves.  data/moves.lua is built from BW2, which predates the
-- type, so it yields only Charm, Moonlight and Sweet Kiss -- all power 0.
-- Merged into NewMoves here so registration, the retro ancestor map and the
-- attack guarantee treat them like any other added move.
do
  local extra = loadModule("data/moves_extra.lua")
  for id in pairs(extra) do Retro[id] = Retro[id] or "SWIFT" end
  for id, record in pairs(extra) do NewMoves[id] = record end
end
-- Vanilla retypes, per-species party icons, and the Gen 1 status-move set.
-- Hand-editable; see the header of that file.  Loaded before src/moves.lua,
-- which takes STATUS_MOVES as a chunk argument.
local Overrides = loadModule("data/overrides.lua")
-- Correct typings for the 88 species carrying Steel, Dark or Fairy slots.
local ModernTypes = loadModule("data/modern_types.lua")
local GrowthRates = loadModule("src/growth_rates.lua")
-- Move names that fit the 12-character field, flat powers for moves Gen 1
-- cannot compute, mapped secondary effects, and the removal list.
local MoveFixes = loadModule("data/move_fixes.lua")
local Moves = loadModule("src/moves.lua", NewMoves, Retro,
  Overrides.STATUS_MOVES, MoveFixes)
local Encounters = loadModule("src/encounters.lua")
local Starters = loadModule("src/starters.lua")
local Icons = loadModule("src/icons.lua")
local Trainers = loadModule("src/trainers.lua")
local TrainerOverrides = loadModule("data/trainer_overrides.lua")
-- Level-up entries for the Fairy attacks.  Applied to live Data because
-- `learnset` is a list and a record patch replaces lists wholesale.
local FairyLearnsets = loadModule("data/fairy_learnsets.lua")
-- Evolutions Gen 1 cannot express natively (stone remaps, and friendship /
-- held-item / time-of-day / known-move conditions turned into plain levels).
-- Kept out of data/species.lua so the hand-checked rows stay reviewable.
local EvolutionsExtra = loadModule("data/evolutions_extra.lua")
-- Writes a report file.  Logger only prints to stdout, and a fused
-- gen1recomp.exe has no console attached.
local Diagnostics = loadModule("src/diagnostics.lua")
-- Compatibility with the KEP total conversion; that file documents what
-- actually collides and why.
local Kep = loadModule("src/kep_compat.lua")

-- Collected as the entry chunk runs, then dumped at game.ready.
local report = {}

-- KEP renumbers the whole dex, hand-authors every encounter table, and
-- registers 20 species we also register.  Detected at entry time because the
-- species and cry responses have to happen before we write anything.
local kepPresent = Kep.detect(mod)
local kepShared = kepPresent and Kep.sharedSet() or {}
if kepPresent then
  mod.log:info("KEP detected: yielding 20 shared species, appending onto its "
    .. "encounter tables, and renumbering our dex above its own")
end

-- Optional: data/dex_entries.lua is 117 KB of flavour text and is generated
-- locally rather than committed (tools/build_dex_entries.py).  Without it the
-- Pokedex falls back to "Data unknown." for the new species, so a missing file
-- must not stop the mod loading.
local DexEntries = { ENTRIES = {}, TEXT = {} }
do
  -- read directly rather than via loadModule: that helper logs a
  -- "reinstall the mod" error, which is the wrong signal for a file that is
  -- meant to be optional
  local source = mod:read("data/dex_entries.lua")
  local chunk = source and compile(source, "@data/dex_entries.lua")
  local ok, loaded = false, nil
  if chunk then ok, loaded = pcall(chunk) end
  if ok and type(loaded) == "table" then
    DexEntries = loaded
    report.dexEntriesFile = true
  else
    report.dexEntriesFile = false
    mod.log:warn("data/dex_entries.lua not found; new species will show "
      .. "\"Data unknown.\" in the Pokedex.  Generate it with "
      .. "python3 tools/build_dex_entries.py")
  end
end

-- Wild placement lives in its own generated file, attached onto the same
-- Data table src/encounters.lua reads.  Rows are appended to the vanilla ten,
-- never substituted for them, so Kanto's own roster survives underneath
-- (tools/build_placement.lua).
-- Rows are stored compactly as { level, "SPECIES" }; normalise them to the
-- shape src/encounters.lua and the engine expect.
Data.PLACEMENT = loadModule("data/placement.lua")
for _, kinds in pairs(Data.PLACEMENT) do
  for _, rows in pairs(kinds) do
    for i, row in ipairs(rows) do
      if row.species == nil then
        rows[i] = { level = row[1], species = row[2] }
      end
    end
  end
end

-- Maps All_Pokemon_Catchable_151_Mod authors wholesale, taken from its source
-- rather than guessed.  With YIELD TO OTHER MODS on we skip these: appending is
-- non-destructive, but that mod's placement is deliberate and ours is
-- heuristic, so theirs should win where they overlap.
--
-- Conditional on that mod actually being installed.  Yielding unconditionally
-- would hand away 33 of 58 tables to a mod that may not be present.
local CATCHABLE_151_MAPS = {
  "CERULEAN_CAVE_1F", "CERULEAN_CAVE_2F", "CERULEAN_CAVE_B1F",
  "POKEMON_MANSION_B1F", "POWER_PLANT",
  "ROUTE_3", "ROUTE_4", "ROUTE_5", "ROUTE_6", "ROUTE_7", "ROUTE_8",
  "ROUTE_9", "ROUTE_11", "ROUTE_12", "ROUTE_13", "ROUTE_14", "ROUTE_15",
  "ROUTE_21", "ROUTE_22", "ROUTE_23", "ROUTE_24", "ROUTE_25",
  "SAFARI_ZONE_CENTER", "SAFARI_ZONE_EAST", "SAFARI_ZONE_NORTH",
  "SAFARI_ZONE_WEST",
  "SEAFOAM_ISLANDS_B2F", "SEAFOAM_ISLANDS_B3F", "SEAFOAM_ISLANDS_B4F",
  "VICTORY_ROAD_1F", "VICTORY_ROAD_2F", "VICTORY_ROAD_3F",
  "VIRIDIAN_FOREST",
}
if mod.find and mod.find("all_pokemon_catchable_151_mod") then
  Data.CONTESTED_MAPS = CATCHABLE_151_MAPS
  mod.log:info("all_pokemon_catchable_151_mod detected: yielding %d maps",
    #CATCHABLE_151_MAPS)
else
  Data.CONTESTED_MAPS = {}
end

-- ---------------------------------------------------------------- options

mod.options:define({
  { key = "encounterMode", label = "WILD PLACEMENT", type = "choice",
    default = "extended",
    choices = {
      { "EXTENDED SLOTS", "extended" },
      { "VANILLA SLOTS", "vanilla" },
      { "DATA ONLY", "dataonly" },
    } },
  { key = "available", label = "SPECIES IN WILD", type = "choice",
    default = "all",
    choices = { { "ALL", "all" }, { "RANDOM 151", "subset151" } } },
  { key = "subsetSeed", label = "SUBSET SEED", type = "text",
    default = "", maxLen = 24 },
  { key = "respectOtherMods", label = "YIELD TO OTHER MODS",
    type = "toggle", default = true },
  -- MODERN registers the new types and every Gen 2-5 level-up move.  RETRO
  -- registers them too -- existence is unconditional, so a saved mon can never
  -- know a move that stops existing -- but resolves learnsets through
  -- data/retro.lua and retypes species onto the original 15.
  { key = "moveMode", label = "MOVES & TYPES", type = "choice",
    default = "modern",
    choices = { { "MODERN", "modern" }, { "RETRO GEN 1", "retro" } } },
  -- Which trio sits in Oak's Lab.  Slot types are preserved (left fire,
  -- middle water, right grass) so the rival's counter-pick still works.
  -- src/starters.lua reads this at talk time, so it applies without a restart.
  { key = "starters", label = "STARTERS", type = "choice",
    default = "vanilla",
    choices = {
      { "VANILLA (KANTO)", "vanilla" },
      { "JOHTO", "johto" },
      { "HOENN", "hoenn" },
      { "SINNOH", "sinnoh" },
      { "UNOVA", "unova" },
      { "RANDOM TRIO", "random" },
      -- Temporary: Aron (Steel), Houndour (Dark), Togepi (Fairy), each with a
      -- level-1 move of that type.  Remove this choice and TRIOS.typetest in
      -- src/starters.lua when the types are confirmed working.
      { "TYPE TEST (DUMMY)", "typetest" },
    } },
  { key = "starterSeed", label = "STARTER SEED", type = "text",
    default = "", maxLen = 24 },
  -- Gen 1 has one Special stat; every species from Gen 2 on has two.  Which
  -- one the single stat becomes is a balance decision, not a detail: SpA makes
  -- special attackers hit as hard as they should and leaves them frail, SpD
  -- does the reverse, and the average flattens both.  Sanqui's randomizer
  -- exposes the same choice.  SpA is the default because Gen 1's own Special
  -- is the attacking number in practice.
  { key = "specialMode", label = "SPECIAL STAT", type = "choice",
    default = "spa",
    choices = {
      { "SP. ATTACK", "spa" },
      { "SP. DEFENSE", "spd" },
      { "AVERAGE", "average" },
    } },
  -- Hand-authored leader/E4 rosters, and duplicate slots replaced on ordinary
  -- trainers.  Off leaves Kanto exactly as the ROM had it.
  { key = "modernTrainers", label = "MODERN TRAINERS", type = "toggle",
    default = true },
  -- How much of a widened table's encounter roll goes to the new species.
  -- An even split leaves the vanilla ten at half the roll, and because Route 1
  -- fills several of its slots with the same Pidgey and Rattata, that reads as
  -- "still mostly Rattata" even when the additions are all present.
  { key = "newShare", label = "NEW SPECIES SHARE", type = "choice",
    default = "most",
    choices = {
      { "EVEN (50%)", "even" },
      { "FAVOUR NEW (70%)", "most" },
      { "MOSTLY NEW (85%)", "dominant" },
    } },
})

local encounterMode = mod.options:get("encounterMode") or "extended"
local available = mod.options:get("available") or "all"
local subsetSeed = mod.options:get("subsetSeed") or ""
local respect = mod.options:get("respectOtherMods")
if respect == nil then respect = true end
-- Read only for the diagnostics report; src/starters.lua reads the live value
-- at talk time so the setting applies without a restart.
local starterMode = mod.options:get("starters") or "vanilla"
local specialMode = mod.options:get("specialMode") or "spa"
local modernTrainers = mod.options:get("modernTrainers")
if modernTrainers == nil then modernTrainers = true end
local NEW_SHARE = { even = 0.50, most = 0.70, dominant = 0.85 }
local newShare = NEW_SHARE[mod.options:get("newShare") or "most"] or 0.70

-- ----------------------------------------------------------- growth rates
-- Gen 1 ships five curves; Gen 2+ species also use ERRATIC and FLUCTUATING.
-- The `growth_rates` registry takes an expForLevel function
-- (src/mods/Schemas.lua R.growth_rates), validated to be increasing.

for id, fn in pairs(GrowthRates.CURVES) do
  local ok, err = pcall(function()
    mod.content.growth_rates:register(id, { expForLevel = fn })
  end)
  if not ok then
    mod.log:warn("growth rate %s not registered: %s", id, tostring(err))
  end
end

-- --------------------------------------------------------- dex entries
-- Without a `dexEntry` the Pokedex draws "Data unknown." and prints no height
-- or weight (src/ui/DexEntryMenu.lua).  `text` is a key into the `text`
-- registry -- `game.data.text[e.text]` -- not a literal, so the strings have to
-- be registered too or the key resolves to nil and the screen falls back to
-- "Data unknown." anyway.

local textCount = 0
for key, body in pairs(DexEntries.TEXT or {}) do
  local ok = pcall(function() mod.content.text:register(key, body) end)
  if not ok then
    ok = pcall(function() mod.content.text:override(key, body) end)
  end
  if ok then textCount = textCount + 1 end
end
report.texts = textCount
mod.log:info("registered %d dex entry texts", textCount)

-- ------------------------------------------------------- types and moves
-- Runs before species registration: `types` and `level1Moves` are f.id()
-- cross-references, so the targets must be registered first or the post-merge
-- check fails the whole mod.

local moveMode = mod.options:get("moveMode") or "modern"
local resolveMove, resolveTypes = Moves.apply(mod, moveMode)

-- --------------------------------------------------------------- species
-- Field names below are the extractor's own, taken from
-- gen1recomp/tools/extract/pokemon.py rather than from the schema's idealized
-- shape, so these records sit alongside the vanilla ones exactly.
--
-- The randomizer's eligibility gate (species_manifest.lua) additionally
-- requires: id matching the registry key, positive integer dex, all five base
-- stats as integers 1..255, at least one type, non-empty growthRate, dense
-- level1Moves / learnset / evolutions arrays, and non-empty spriteFront and
-- spriteBack.  A record missing either sprite is silently excluded from the
-- randomizer's pool, which is why sprite paths are mandatory here.

local registered, skipped = 0, 0

local function validate(record)
  if type(record.id) ~= "string" or record.id == "" then return "id" end
  if type(record.dex) ~= "number" or record.dex < 1 then return "dex" end
  local s = record.baseStats
  if type(s) ~= "table" then return "baseStats" end
  for _, key in ipairs({ "hp", "attack", "defense", "speed", "special" }) do
    local v = s[key]
    if type(v) ~= "number" or v < 1 or v > 255 or v ~= math.floor(v) then
      return "baseStats." .. key
    end
  end
  if type(record.types) ~= "table" or #record.types < 1 then return "types" end
  if type(record.growthRate) ~= "string" or record.growthRate == "" then
    return "growthRate"
  end
  -- dense arrays: the gate rejects sparse ones outright
  for _, key in ipairs({ "level1Moves", "learnset", "evolutions" }) do
    if type(record[key]) ~= "table" then return key end
  end
  if type(record.spriteFront) ~= "string" or record.spriteFront == "" then
    return "spriteFront"
  end
  if type(record.spriteBack) ~= "string" or record.spriteBack == "" then
    return "spriteBack"
  end
  return nil
end

-- Sprite paths in data/species.lua are mod-relative ("assets/front/152.png"),
-- and src/pokemon/Sprites.lua uses def.spriteFront as-is from the game root.
-- An unrewritten path finds nothing, which leaves the Pokedex without a pic
-- and stops a battle building the mon at all.  mod.assets:path() is the
-- engine's helper for this.
local function absolutise(record)
  if mod.assets and mod.assets.path then
    for _, key in ipairs({ "spriteFront", "spriteBack" }) do
      local v = record[key]
      -- idempotent: only rewrite our own relative paths
      if type(v) == "string" and v:sub(1, 7) == "assets/" then
        record[key] = mod.assets:path(v)
      end
    end
  end
  return record
end

-- Resolve the single Special stat.  data/species.lua carries Sp. Attack in
-- baseStats.special and Sp. Defense in dexExpansion.specialDefense.
--
-- baseStats has to be copied first: Moves.rewrite returns a shallow copy, so
-- the table is still shared with the loaded dataset and writing through it
-- would make the choice sticky across a mode switch.
local function resolveSpecial(record)
  local ext = record.dexExpansion or {}
  local spd = ext.specialDefense
  if type(spd) ~= "number" or specialMode == "spa" then return record end
  local base = {}
  for k, v in pairs(record.baseStats) do base[k] = v end
  if specialMode == "spd" then
    base.special = spd
  else -- average
    base.special = math.floor((base.special + spd) / 2 + 0.5)
  end
  if base.special < 1 then base.special = 1 end
  if base.special > 255 then base.special = 255 end
  record.baseStats = base
  return record
end

-- Temporary, for the TYPE TEST trio: a level-1 move of each new type.  Unlike
-- the trio itself, which is read at talk time, this is baked at registration,
-- so switching to TYPE TEST takes one restart.
--
-- It applies to the species record, so a trainer's Aron gets Metal Claw too --
-- trainer parties draw moves from the same learnset the player's do.
local DUMMY_MOVES = {
  ARON = "METAL_CLAW",       -- Steel, 50 power, Scratch animation
  HOUNDOUR = "CRUNCH",       -- Dark, 80 power, Bite animation
  TOGEPI = "DAZZLING_GLEAM", -- Fairy, 80 power, Swift animation
}
local dummyActive = (mod.options:get("starters") == "typetest")
local function applyDummyMoves(record)
  if not dummyActive then return record end
  local want = DUMMY_MOVES[record.id]
  if not want then return record end
  for _, id in ipairs(record.level1Moves) do
    if id == want then return record end
  end
  record.level1Moves[#record.level1Moves + 1] = want
  return record
end

-- Typing is corrected before the rewrite so the retro resolver sees the real
-- types and can fold Dark to Ghost, Steel to Ground and Fairy to Normal,
-- collapsing a doubled result to one type.
local function applyModernTypes(record)
  local spec = ModernTypes[record.id]
  if not spec then return record end
  local types = {}
  for t in spec:gmatch("[A-Z_]+") do types[#types + 1] = t end
  if #types > 0 then record.types = types end
  return record
end

for _, record in ipairs(Data.SPECIES) do
  record = applyModernTypes(record)
  record = Moves.rewrite(record, resolveMove, resolveTypes)
  record = applyDummyMoves(record)
  record = absolutise(record)
  record = resolveSpecial(record)
  -- merge the mapped evolutions, skipping any target the record already
  -- reaches so a rebuild of species.lua cannot produce duplicates
  local extra = EvolutionsExtra[record.id]
  if extra then
    local have = {}
    for _, evo in ipairs(record.evolutions) do have[evo.species] = true end
    for _, evo in ipairs(extra) do
      if not have[evo.species] then
        record.evolutions[#record.evolutions + 1] = {
          method = evo.method, level = evo.level,
          item = evo.item, species = evo.species,
        }
        have[evo.species] = true
      end
    end
  end
  record.dexEntry = record.dexEntry
    or (DexEntries.ENTRIES and DexEntries.ENTRIES[record.id])
  local bad = validate(record)
  if kepShared[record.id] then
    -- KEP registers this one itself, and `pokemon` is a record registry whose
    -- register() errors on a duplicate.  Since KEP loads after us, going first
    -- here would make ITS call throw and take that whole mod down.
    skipped = skipped + 1
  elseif bad then
    skipped = skipped + 1
    mod.log:warn("species %s skipped: invalid %s",
      tostring(record.id), bad)
  else
    local ok, err = pcall(function()
      mod.content.pokemon:register(record.id, record)
    end)
    if ok then
      registered = registered + 1
    else
      skipped = skipped + 1
      mod.log:warn("species %s failed to register: %s",
        record.id, tostring(err))
    end
  end
end

report.species, report.skipped = registered, skipped
mod.log:info("registered %d species (%d skipped)", registered, skipped)

-- ------------------------------------------------------------- dex size
-- dexSize has to be set explicitly.  src/core/Game.lua does:
--
--     Data:load()            -- runs seedDefaults(), which derives dexSize
--     self.mods:load(Data)   -- and only then merges our 498 species
--
-- and seedDefaults only derives when the value is nil:
--
--     if constants.dexSize == nil then ... highest def.dex ... end
--
-- so it sees the vanilla 151 and stamps that.  PokedexMenu then loops
-- `for n = 1, constants.dexSize or 151`.  Seen and owned are keyed by species
-- id rather than index, so they follow once the loop covers the range.
--
-- Writing it here also puts us in front of KEP, which raises dexSize only if
-- it is still below its own maximum:
--
--     local currentDexSize = mod.content.constants:get("dexSize") or 151
--     if currentDexSize < 251 then mod.content.constants:patch("dexSize", 251)
--
-- Registry:get folds the ops recorded so far, so by the time KEP reads it the
-- value is already ours and its guarded raise is a no-op.  The game.ready pass
-- then raises again for anything that outgrows us.

do
  local highest = 0
  for _, record in ipairs(Data.SPECIES) do
    if record.dex > highest then highest = record.dex end
  end
  report.dexSize = highest
  -- R.constants is keyed (`keys = { dexSize = ..., dexDigits = ... }`), so
  -- each key is written on its own.  Passing a table as the id fails, and a
  -- pcall would hide that, hence the warning below rather than silence.
  local wrote = 0
  for key, value in pairs({
    dexSize = highest,
    dexDigits = math.max(3, #tostring(highest)),
  }) do
    local ok = pcall(function()
      mod.content.constants:register(key, value)
    end)
    if not ok then
      ok = pcall(function() mod.content.constants:patch(key, value) end)
    end
    if ok then wrote = wrote + 1 end
  end
  if wrote == 2 then
    mod.log:info("dexSize set to %d (%d digits)", highest,
      math.max(3, #tostring(highest)))
  else
    mod.log:warn("could not set dexSize (%d/2 keys written); the game.ready "
      .. "pass is the fallback", wrote)
  end
end

-- ---------------------------------------------------------------- cries
-- data.audio.cries is keyed by species id, and Sound.playCry takes a
-- { file = path } definition decoded by newFileSource, so one .ogg per species
-- is all this needs.  The record's `cry` field is not involved.
--
-- Gen 3-5 files are band-limited offline by tools/lofi_cries.py.  Filtering at
-- runtime is not an option: Source:setFilter needs an effects-capable device,
-- and Sound.playCry owns and caches the Source.

do
  local cries = 0
  for _, record in ipairs(Data.SPECIES) do
    -- skipped for the shared 20: same duplicate-register problem as the
    -- species themselves, since `cries` is a record registry too
    if not kepShared[record.id] then
      local rel = ("cries/%d.ogg"):format(record.dex)
      local path = (mod.assets and mod.assets.path)
        and mod.assets:path(rel) or rel
      local ok = pcall(function()
        mod.content.cries:register(record.id, { file = path })
      end)
      if not ok then
        ok = pcall(function()
          mod.content.cries:patch(record.id, { file = path })
        end)
      end
      if ok then cries = cries + 1 end
    end
  end
  report.cries = cries
  mod.log:info("registered %d cries", cries)
end

-- ------------------------------------------------------- vanilla retypes
-- Seven species in 1-151 changed typing after Gen 1.  They live in the
-- engine's dataset rather than ours, so registering the new types does nothing
-- to them and their records have to be patched directly.
--
-- Modern only; retro leaves the vanilla records as the ROM had them.

if moveMode ~= "retro" then
  local retyped = 0
  for id, types in pairs(Overrides.RETYPES or {}) do
    local ok = pcall(function()
      mod.content.pokemon:patch(id, { types = types })
    end)
    if ok then
      retyped = retyped + 1
    else
      mod.log:warn("could not retype %s", id)
    end
  end
  report.retyped = retyped
  mod.log:info("retyped %d vanilla species onto modern typings", retyped)
else
  report.retyped = 0
end

-- ------------------------------------------------------------ party icons
-- After species registration, so every id exists in the registry.
-- icons.byDex covers dex 1..151 only, so anything past that needs its own
-- entry.  ICON_GROUPS in data/overrides.lua is where a figure is chosen.

do
  local counts = Icons.apply(mod, Data.SPECIES,
    Icons.expand(Overrides.ICON_GROUPS))
  local n = 0
  for _, c in pairs(counts or {}) do n = n + c end
  report.icons = n
end

-- --------------------------------------------------------------- starters
-- After species registration on purpose: a non-Kanto trio names species this
-- mod itself registers, so they have to be in the registry first.
--
-- No option is passed in: src/starters.lua reads STARTERS at talk time, which
-- is what makes changing it apply without a restart.

Starters.apply(mod)

-- ------------------------------------------------- randomizer metadata
-- exports.registerSpeciesMeta(id, { legendary = bool, stage = "basic" |
-- "middle" | "final" }) freezes at mods.loaded, so this has to run in the
-- entry chunk.  Without it the randomizer derives stages itself and legendary
-- status falls back silently -- which is why the manifest declares
-- pokemon_randomizer as an optional dependency: that is what makes the load
-- order deterministic rather than incidental.

local function handOffMetadata()
  local randomizer = mod.find and mod.find("pokemon_randomizer")
  if not randomizer then return end
  local exports = randomizer.exports
  if not (exports and exports.registerSpeciesMeta) then
    mod.log:warn("pokemon_randomizer present but exposes no "
      .. "registerSpeciesMeta; stages will be derived")
    return
  end
  local sent = 0
  for _, record in ipairs(Data.SPECIES) do
    local meta = {}
    local ext = record.dexExpansion or {}
    if ext.legendary ~= nil then meta.legendary = ext.legendary end
    if ext.stage ~= nil then meta.stage = ext.stage end
    -- the API asserts at least one field is present
    if meta.legendary ~= nil or meta.stage ~= nil then
      local ok = pcall(exports.registerSpeciesMeta, record.id, meta)
      if ok then sent = sent + 1 end
    end
  end
  mod.log:info("handed %d species metadata rows to the randomizer", sent)
end

handOffMetadata()

-- ------------------------------------------------------------ encounters

if kepPresent then
  -- KEP hand-authors all 254 tables, and its picks are deliberate -- Route 1
  -- seeds COINPUR on purpose.  But standing out of them entirely would leave
  -- 478 species with nowhere to be caught, which is worse: an expansion nobody
  -- can find is not an expansion.
  --
  -- So we append rather than replace, exactly as we do over vanilla Kanto.
  -- KEP's ten slots keep the whole vanilla rarity curve and whatever share
  -- NEW SPECIES SHARE leaves them (30% at the default), and our rows split the
  -- rest.  Its curated picks stay the most common thing on the route.
  mod.log:info("KEP owns the encounter tables; appending onto them rather "
    .. "than replacing (its picks keep %d%% of the roll)",
    math.floor((1 - newShare) * 100 + 0.5))
end

if encounterMode == "dataonly" then
  mod.log:info("DATA ONLY: no encounter tables written; wild placement is "
    .. "left to the randomizer or another mod")
else
  report.registryPlaced = Encounters.apply(mod, Data, {
    extended = encounterMode == "extended",
    available = available,
    subsetSeed = subsetSeed,
    respectOtherMods = respect,
  })
end

do
  local rows, maps = 0, 0
  for _, kinds in pairs(Data.PLACEMENT or {}) do
    maps = maps + 1
    for _, list in pairs(kinds) do rows = rows + #list end
  end
  report.placementRows, report.placementMaps = rows, maps
  report.encounterMode = encounterMode
  report.available = available
  report.moveMode = moveMode
  report.starterMode = starterMode
  report.specialMode = specialMode
  report.modernTrainers = modernTrainers
  report.kepPresent = kepPresent
  report.respect = respect
  report.moves = 0
  for _ in pairs(NewMoves) do report.moves = report.moves + 1 end
  report.types, report.matchups = 3, 38
end

-- ------------------------------------- runtime bucket reconciliation
-- src/world/Encounter.lua rolls a slot as:
--     for i, threshold in ipairs(grass.buckets or buckets) do
--       if pick < threshold then local slot = grass.slots[i] ...
--
-- so bucket count and slot count must agree, and `buckets` cannot be declared
-- in the registry patch at all -- it is not a field of the encounters schema,
-- and including it makes validation reject the whole patch.

-- Vanilla Gen 1 slot weights (src/world/FieldDefaults.lua encounterBuckets).
-- Cumulative thresholds out of 256, so slot 1 is ~20% and slot 10 is ~1%.
local VANILLA_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
local VANILLA_SLOTS = #VANILLA_BUCKETS

-- Thresholds for a widened table.
--
-- An even spread across all twenty would flatten Gen 1's rarity curve, making
-- the 1% tail slot as common as the 20% lead slot.  Instead the original ten
-- keep their proportions, compressed into whatever share of the roll they
-- still hold, and the appended rows split the remainder evenly.
--
-- That share is the NEW SPECIES SHARE option, defaulting to 70% new.  An even
-- split by table is a lopsided split by species: Route 1 spends several of its
-- ten vanilla slots on the same two mons while each new one appears once.
local function widenBuckets(slots, share)
  local out = {}
  local base = math.min(VANILLA_SLOTS, slots)
  local extra = slots - base
  if extra <= 0 then return nil end -- nothing added: leave the table alone
  share = share or 0.70
  local split = math.floor(256 * (1 - share) + 0.5)
  -- leave room for one threshold per appended row
  if split > 256 - extra then split = 256 - extra end
  if split < base then split = base end
  for i = 1, base do
    out[i] = math.floor(VANILLA_BUCKETS[i] * split / 256 + 0.5)
    if i > 1 and out[i] <= out[i - 1] then out[i] = out[i - 1] + 1 end
  end
  for j = 1, extra do
    out[base + j] = math.floor(split + (256 - split) * j / extra + 0.5)
    if out[base + j] <= out[base + j - 1] then
      out[base + j] = out[base + j - 1] + 1
    end
  end
  out[slots] = 256 -- Encounter.lua requires the last entry to be exactly 256
  return out
end

-- Apply placement rows straight to live Data.
--
-- The registry patch in src/encounters.lua is kept, but not relied on.  This
-- reconciles against the table the game actually rolls on, which is the
-- fallback Kanto-Reforged uses for the same reason.  It is also what carries
-- placement over KEP, whose override erases our registry patch outright.
--
-- Idempotent by species membership: a no-op for any row the registry patch
-- already delivered, and safe to re-run.
local function applyPlacement(encounters, placement, contested)
  local added, maps = 0, 0
  for mapId, kinds in pairs(placement or {}) do
    local def = encounters[mapId]
    if def and not contested[mapId] then
      for kind, rows in pairs(kinds) do
        local table_ = def[kind]
        if type(table_) == "table" and type(table_.slots) == "table" then
          local present = {}
          for _, slot in ipairs(table_.slots) do
            if slot.species then present[slot.species] = true end
          end
          local before = #table_.slots
          for _, row in ipairs(rows) do
            if not present[row.species] then
              table_.slots[#table_.slots + 1] =
                { level = row.level, species = row.species }
              present[row.species] = true
              added = added + 1
            end
          end
          if #table_.slots > before then maps = maps + 1 end
        end
      end
    end
  end
  return added, maps
end

mod.events:on("game.ready", function(payload)
  -- The payload is a wrapper: ModRuntime.emit("game.ready", { game = self }).
  -- Reading payload.data instead of payload.game.data gives nil, and the pass
  -- returns without doing anything.
  local game = payload and (payload.game or payload)
  local encounters = game and game.data and game.data.encounters
  if type(encounters) ~= "table" then return end

  local addedSlots = 0
  if encounterMode ~= "dataonly" then
    local contested = {}
    if respect then
      for _, id in ipairs(Data.CONTESTED_MAPS or {}) do contested[id] = true end
    end
    addedSlots = applyPlacement(encounters, Data.PLACEMENT, contested)
  end

  local fixed = 0
  for mapId, def in pairs(encounters) do
    if type(def) == "table" then
      for _, kind in ipairs({ "grass", "water" }) do
        local table_ = def[kind]
        if type(table_) == "table" and type(table_.slots) == "table" then
          local slots = #table_.slots
          local current = table_.buckets and #table_.buckets or nil
          -- Only a table that grew past the vanilla ten needs thresholds of
          -- its own.  A 10-slot table is left completely alone so it keeps
          -- using constants.encounterBuckets, exactly as vanilla does.
          if slots > VANILLA_SLOTS and current ~= slots then
            local rebuilt = widenBuckets(slots, newShare)
            if rebuilt then
              table_.buckets = rebuilt
              fixed = fixed + 1
              mod.log:debug("%s.%s: %d buckets for %d slots",
                tostring(mapId), kind, #rebuilt, slots)
            end
          end
        end
      end
    end
  end
  -- Printed even at zero: "0 slots added" is the most useful line there is
  -- when routes look vanilla.  Logger uses print, so this reaches stdout only.
  mod.log:info("wild reconcile: %d slots added, %d bucket tables widened",
    addedSlots, fixed)

  -- Clear KEP's numbering before dexSize is settled, so the raise below sees
  -- the shifted values.  The offset is measured from the merged data rather
  -- than hardcoded, so it tracks whatever KEP's highest entry actually is.
  if kepPresent then
    local ours = {}
    for _, record in ipairs(Data.SPECIES) do
      if not kepShared[record.id] then ours[record.id] = true end
    end
    local shifted, offset, foreignMax =
      Kep.renumber(game.data.pokemon, ours, 152)
    report.kepOffset = offset
    if shifted > 0 then
      mod.log:info("renumbered %d species by +%d to clear KEP's dex "
        .. "(highest foreign entry %d)", shifted, offset, foreignMax)
    end
  end

  -- Re-derive from the MERGED dataset and only ever raise.  Another mod may
  -- add species past ours, and seedDefaults cannot help by then.  Lowering
  -- would truncate someone else's roster, so max() rather than assignment.
  local constants = game.data and game.data.constants
  if type(constants) == "table" then
    local highest = 0
    for _, def in pairs(game.data.pokemon or {}) do
      if type(def) == "table" and type(def.dex) == "number"
          and def.dex > highest then
        highest = def.dex
      end
    end
    if highest > (constants.dexSize or 0) then
      constants.dexSize = highest
      constants.dexDigits = math.max(3, #tostring(highest))
      mod.log:info("dexSize raised to %d after merge", highest)
    end
    report.dexSizeFinal = constants.dexSize
  end

  -- AnimPlayer:start resolves by move id -- `self.data.moveAnims[moveId]` --
  -- not by the `anim` field on the record, so a new move needs an entry under
  -- its own id or it draws nothing.
  --
  -- Aliasing by reference is enough: an animation is data, and pointing two
  -- ids at one script is what reusing Scratch's animation means.
  do
    local anims = game.data and game.data.moveAnims
    local aliased, missing = 0, 0
    if type(anims) == "table" then
      for id, def in pairs(game.data.moves or {}) do
        if anims[id] == nil and type(def.anim) == "string" then
          local source = anims[def.anim]
          if source then
            anims[id] = source
            aliased = aliased + 1
          else
            missing = missing + 1
          end
        end
      end
    end
    report.animAliased = aliased
    mod.log:info("aliased %d move animations (%d had no source)",
      aliased, missing)
  end

  -- Fairy learnsets, into live Data so the vanilla Fairies (Clefairy and
  -- friends, made Fairy by the retype pass) get them too.  Idempotent by move
  -- id, so the map.entered pass and a hot reload cannot double-add.
  do
    local added = 0
    for id, rows in pairs(FairyLearnsets) do
      local def = game.data.pokemon and game.data.pokemon[id]
      if type(def) == "table" and type(def.learnset) == "table" then
        local have = {}
        for _, entry in ipairs(def.learnset) do have[entry.move] = true end
        for _, row in ipairs(rows) do
          if not have[row[2]] then
            def.learnset[#def.learnset + 1] = { level = row[1], move = row[2] }
            have[row[2]] = true
            added = added + 1
          end
        end
        -- the engine walks the learnset in order, so keep it sorted by level
        table.sort(def.learnset, function(a, b)
          if a.level ~= b.level then return a.level < b.level end
          return tostring(a.move) < tostring(b.move)
        end)
      end
    end
    report.fairyMoves = added
    mod.log:info("taught %d Fairy attacking moves by level-up", added)
  end

  -- Trainers, after placement: both mutate live Data and neither depends on
  -- the other, but doing trainers last keeps the encounter numbers in the log
  -- next to each other.
  if modernTrainers then
    local ts = Trainers.apply(mod, game.data.pokemon, game.data.trainers,
      TrainerOverrides)
    report.trainerParties = ts.parties
    report.trainerOverridden = ts.overridden
    report.trainerDeduped = ts.deduped
  else
    mod.log:info("MODERN TRAINERS off: rosters left exactly as the ROM had them")
  end

  report.addedLive = addedSlots
  report.yielded = 0
  for _, id in ipairs(Data.CONTESTED_MAPS or {}) do
    if respect and Data.PLACEMENT[id] then report.yielded = report.yielded + 1 end
  end
  report.widened = fixed
  local wrote, where = Diagnostics.write(mod, report, encounters, Data.PLACEMENT)
  if wrote then
    mod.log:info("diagnostics written to %s", tostring(where))
  else
    mod.log:warn("could not write diagnostics: %s", tostring(where))
  end
end)

-- Re-apply on every map entry as well.
--
-- game.ready should be enough on its own: Data:load() runs once and
-- OverworldController reads `Game.data.encounters[self.map.id]` live on every
-- step.  This is belt and braces -- if anything reloads or re-folds Data after
-- boot, the next map entry repairs it.
--
-- applyPlacement is idempotent and widenBuckets only fires when a bucket count
-- disagrees with its slot count, so the steady state is two table scans.
mod.events:on("map.entered", function(payload)
  local game = payload and (payload.game or payload)
  if not (game and game.data) then
    -- map.entered does not promise to carry the game; the module singleton is
    -- the same table Data:load() populated
    local ok, GameModule = pcall(require, "src.core.Game")
    if ok then game = GameModule end
  end
  local encounters = game and game.data and game.data.encounters
  if type(encounters) ~= "table" then return end

  if encounterMode ~= "dataonly" then
    local contested = {}
    if respect then
      for _, id in ipairs(Data.CONTESTED_MAPS or {}) do contested[id] = true end
    end
    applyPlacement(encounters, Data.PLACEMENT, contested)
  end

  for _, def in pairs(encounters) do
    if type(def) == "table" then
      for _, kind in ipairs({ "grass", "water" }) do
        local table_ = def[kind]
        if type(table_) == "table" and type(table_.slots) == "table" then
          local slots = #table_.slots
          local current = table_.buckets and #table_.buckets or nil
          if slots > VANILLA_SLOTS and current ~= slots then
            local rebuilt = widenBuckets(slots, newShare)
            if rebuilt then table_.buckets = rebuilt end
          end
        end
      end
    end
  end
end)
