-- Dex Expansion -- registers species beyond the original 151 for Gen1Recomp.
--
-- The one architectural rule this mod is built around:
--
--     EXISTENCE IS UNCONDITIONAL.  AVAILABILITY IS OPTIONAL.
--
-- Every species in data/species.lua is registered on every boot, regardless
-- of settings.  Nothing is ever withheld from the `pokemon` registry.
--
-- That is not a style preference, it is a save-safety requirement.  The
-- engine's save scrubber (src/core/SaveData.lua) deletes dex flags for
-- species the dataset does not know:
--
--     for id in pairs(dex[key]) do
--       if not known(data.pokemon, id) then dex[key][id] = nil end
--     end
--
-- ...and blanks Hall of Fame entries the same way.  Because mod options are
-- GLOBAL preferences rather than per-save state, a settings-driven roster
-- would mean flipping one option silently destroys dex progress in every
-- existing save.  So the "151 subset" option restricts where species APPEAR
-- (encounters, and trainer parties once that lands), never whether they
-- EXIST.
--
-- Verified against gen1recomp:
--   * species are string-keyed and saves are Lua source, so there is no
--     255-index ceiling anywhere in the gameplay path.
--   * constants.dexSize is derived, but TOO EARLY to see us -- see the dex
--     size section below, which is why the Pokedex was stuck at 151.

local mod = ...

-- ---------------------------------------------------------------- loading
-- A mod-relative `require` does NOT resolve at runtime: the loader runs this
-- file via chunk(api) with LOVE's package path pointing at the GAME, not at
-- the mod, so require("data.species") throws on the first line.  Engine
-- requires (require("src.core.Strings")) still work; mod-relative ones never
-- do.  mod:read + loadstring is the sanctioned seam -- the same one
-- quality_of_life uses -- and `loadstring` is the Lua 5.1 spelling, which
-- matters because LOVE runs LuaJIT.

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
-- Vanilla retypes, per-species party icons, and the Gen 1 status-move set.
-- Hand-editable; see the header of that file.  Loaded BEFORE src/moves.lua,
-- which takes STATUS_MOVES as a chunk argument.
local Overrides = loadModule("data/overrides.lua")
local GrowthRates = loadModule("src/growth_rates.lua")
local Moves = loadModule("src/moves.lua", NewMoves, Retro,
  Overrides.STATUS_MOVES)
local Encounters = loadModule("src/encounters.lua")
local Starters = loadModule("src/starters.lua")
local Icons = loadModule("src/icons.lua")
-- Evolutions Gen 1 cannot express natively (stone remaps, and friendship /
-- held-item / time-of-day / known-move conditions turned into plain levels).
-- Kept out of data/species.lua so the hand-checked rows stay reviewable.
local EvolutionsExtra = loadModule("data/evolutions_extra.lua")
-- Writes a report FILE, because Logger only prints to stdout and a fused
-- gen1recomp.exe has no console attached to read it from.
local Diagnostics = loadModule("src/diagnostics.lua")

-- Collected as the entry chunk runs, then dumped at game.ready.
local report = {}

-- Optional: data/dex_entries.lua is 117 KB of flavour text and is generated
-- locally rather than committed (tools/build_dex_entries.py).  Without it the
-- Pokedex falls back to "Data unknown." for the new species, which is a
-- cosmetic loss -- so a missing file must not stop the mod loading.
local DexEntries = { ENTRIES = {}, TEXT = {} }
do
  -- read directly rather than via loadModule: that helper logs a
  -- "reinstall the mod" ERROR, which is the wrong signal for a file that is
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
-- Data table src/encounters.lua reads.  Rows are APPENDED to the vanilla
-- ten, never substituted for them, so Kanto's own roster survives
-- underneath (tools/build_placement.lua).
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

-- Maps All_Pokemon_Catchable_151_Mod authors wholesale, taken from its
-- source rather than guessed.  With YIELD TO OTHER MODS on we skip these:
-- appending is non-destructive, but that mod's placement is deliberate and
-- ours is heuristic, so theirs should win where they overlap.
--
-- Conditional on that mod ACTUALLY being installed.  Yielding
-- unconditionally would hand away 33 of 58 tables -- most of the roster --
-- to a mod that may not be present, which is worse than not yielding at all.
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
  -- MODERN registers the new types and every Gen 2-5 level-up move.
  -- RETRO registers them too -- existence is unconditional, so a saved mon
  -- can never know a move that stops existing -- but resolves learnsets
  -- through data/retro.lua and retypes species onto the original 15.
  { key = "moveMode", label = "MOVES & TYPES", type = "choice",
    default = "modern",
    choices = { { "MODERN", "modern" }, { "RETRO GEN 1", "retro" } } },
  -- Which trio sits in Oak's Lab.  Slot types are preserved (left fire,
  -- middle water, right grass) so the rival's counter-pick still works.
  -- src/starters.lua reads this at TALK time, so it applies without a reboot.
  { key = "starters", label = "STARTERS", type = "choice",
    default = "vanilla",
    choices = {
      { "VANILLA (KANTO)", "vanilla" },
      { "JOHTO", "johto" },
      { "HOENN", "hoenn" },
      { "SINNOH", "sinnoh" },
      { "UNOVA", "unova" },
      { "RANDOM TRIO", "random" },
    } },
  { key = "starterSeed", label = "STARTER SEED", type = "text",
    default = "", maxLen = 24 },
  -- Gen 1 has ONE Special stat; every species from Gen 2 on has two.  Which
  -- one the single stat becomes is a real balance decision, not a detail:
  -- SpA makes special attackers hit as hard as they should and leaves them
  -- frail, SpD does the reverse, and the average flattens both.  Sanqui's
  -- randomizer exposes the same choice.  SpA is the default because Gen 1's
  -- own Special is the attacking number in practice -- it is what Alakazam
  -- and Mewtwo are famous for.
  { key = "specialMode", label = "SPECIAL STAT", type = "choice",
    default = "spa",
    choices = {
      { "SP. ATTACK", "spa" },
      { "SP. DEFENSE", "spd" },
      { "AVERAGE", "average" },
    } },
  -- How much of a widened table's encounter roll goes to the NEW species.
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
-- at talk time so the setting applies without a reboot.
local starterMode = mod.options:get("starters") or "vanilla"
local specialMode = mod.options:get("specialMode") or "spa"
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
-- Without a `dexEntry` the Pokedex draws "Data unknown." and prints no
-- height or weight (src/ui/DexEntryMenu.lua).  `text` is a KEY into the
-- `text` registry -- `game.data.text[e.text]` -- not a literal, so the
-- strings have to be registered too or the key resolves to nil and the
-- screen falls back to "Data unknown." anyway.

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

-- ------------------------------------------------------------- dex size
-- THE POKEDEX STAYED AT 151 BECAUSE OF LOAD ORDER, not because the constant
-- is hardcoded.  src/core/Game.lua does:
--
--     Data:load()            -- runs seedDefaults(), which derives dexSize
--     self.mods:load(Data)   -- ...and only THEN merges our 498 species
--
-- and seedDefaults only derives when the value is absent:
--
--     if constants.dexSize == nil then ... highest def.dex ... end
--
-- So the derivation ran against the vanilla 151, stamped 151, and by the time
-- our species existed the field was no longer nil.  PokedexMenu then loops
-- `for n = 1, constants.dexSize or 151`, which is where the cap was visible.
-- Seen and owned are keyed by species id rather than index, so they follow
-- once the loop covers the full range.
--
-- Patching the constant declaratively covers it, and the game.ready pass below
-- covers the case where another mod raises it higher than we would.

do
  local highest = 0
  for _, record in ipairs(Data.SPECIES) do
    if record.dex > highest then highest = record.dex end
  end
  report.dexSize = highest
  local ok = pcall(function()
    mod.content.constants:patch({
      dexSize = highest,
      dexDigits = math.max(3, #tostring(highest)),
    })
  end)
  if ok then
    mod.log:info("dexSize set to %d (%d digits)", highest,
      math.max(3, #tostring(highest)))
  else
    mod.log:warn("could not set dexSize; the Pokedex will stay capped")
  end
end

-- ---------------------------------------------------------------- cries
-- data.audio.cries is keyed by SPECIES ID, and Sound.playCry accepts a
-- { file = path } definition, decoded by newFileSource -- so an .ogg per
-- species is all this needs.  No `cry` field on the record is required; the
-- lookup is by species.
--
-- Gen 3-5 cries are cleaner recordings than the Game Boy chip cries they sit
-- beside, so tools/lofi_cries.py band-limits and bit-crushes them offline
-- (see its header).  Nothing here filters at runtime: LOVE's Source:setFilter
-- needs an effects-capable device and this mod never owns the Source anyway --
-- Sound.playCry creates and caches it.

do
  local cries = 0
  for _, record in ipairs(Data.SPECIES) do
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
  report.cries = cries
  mod.log:info("registered %d cries", cries)
end

-- ------------------------------------------------------- types and moves
-- Runs BEFORE species registration: `types` and `level1Moves` are
-- f.id() cross-references, so the targets must be registered first or the
-- post-merge check fails the whole mod.

local moveMode = mod.options:get("moveMode") or "modern"
local resolveMove, resolveTypes = Moves.apply(mod, moveMode)

-- --------------------------------------------------------------- species
-- Field names below are the extractor's own, taken from
-- gen1recomp/tools/extract/pokemon.py rather than from the schema's
-- idealized shape, so these records sit alongside the vanilla ones exactly.
--
-- The randomizer's eligibility gate (species_manifest.lua) additionally
-- requires: id matching the registry key, positive integer dex, all five
-- base stats as integers 1..255, >=1 type, non-empty growthRate, DENSE
-- level1Moves / learnset / evolutions arrays, and non-empty spriteFront AND
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

-- Sprite paths in data/species.lua are MOD-relative ("assets/front/152.png").
-- src/pokemon/Sprites.lua uses def.spriteFront as-is, resolved from the GAME
-- root, so an unrewritten path silently finds nothing: the Pokedex draws no
-- pic and a battle cannot build the mon at all -- the rival walks up and the
-- fight never starts.  mod.assets:path() is the engine's own helper for this
-- (Loader.lua: path = function(_, relative) return mod.path .. "/" .. relative).
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
-- baseStats MUST be copied: Moves.rewrite returns a shallow copy, so the
-- baseStats table is still shared with the loaded dataset, and writing into it
-- would make the choice sticky across a mode switch within one boot.
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

for _, record in ipairs(Data.SPECIES) do
  record = Moves.rewrite(record, resolveMove, resolveTypes)
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
  if bad then
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

-- ------------------------------------------------------- vanilla retypes
-- Registering STEEL / DARK / FAIRY does not retype anything by itself.
-- Magnemite stayed pure Electric because it lives in the ENGINE's dataset,
-- not ours, so its record has to be patched.  Seven species in 1-151 changed
-- typing after Gen 1; without this the new types are half-present, which is
-- worse than not having them (Magnemite reads as Steel-weak but is not).
--
-- MODERN only.  In RETRO the whole point is Kanto's original fifteen types,
-- so the vanilla records are left exactly as the ROM had them.

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
-- Assigned AFTER species registration so every id exists in the registry.
-- icons.byDex only covers dex 1..151, so without this every new species drew
-- no figure at all in the party menu.  ICON_GROUPS in data/overrides.lua is
-- the single place a species' figure is set.

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
-- is what makes changing it apply without a reboot.

Starters.apply(mod)

-- ------------------------------------------------- randomizer metadata
-- exports.registerSpeciesMeta(id, { legendary = bool, stage = "basic" |
-- "middle" | "final" }) freezes at mods.loaded, so this has to run in the
-- entry chunk.  Without it the randomizer derives stages itself and
-- legendary status falls back silently -- which is why the manifest
-- declares pokemon_randomizer as an OPTIONAL dependency: that is what makes
-- the load order deterministic rather than incidental.

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
-- so bucket count and slot count MUST agree, and `buckets` cannot be declared
-- in the registry patch at all -- it is not a field of the encounters schema,
-- and including it makes validation reject the whole patch.

-- Vanilla Gen 1 slot weights (src/world/FieldDefaults.lua encounterBuckets).
-- Cumulative thresholds out of 256, so slot 1 is ~20% and slot 10 is ~1%.
local VANILLA_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
local VANILLA_SLOTS = #VANILLA_BUCKETS

-- Thresholds for a widened table.
--
-- An EVEN spread here would be wrong, and was: it flattens Gen 1's rarity
-- curve, making the 1%-tail slot as common as the 20% lead slot.  Worse, the
-- pass below used to run on every map, so untouched vanilla routes got
-- reweighted too.
--
-- Instead the original ten keep their vanilla PROPORTIONS, compressed into
-- whatever share of the roll they still hold, and the appended rows split the
-- remainder evenly.  The vanilla curve survives; only its total weight shrinks.
--
-- That total is the NEW SPECIES SHARE option, and it defaults to 70% new
-- rather than an even split.  A 50/50 table still reads as "mostly Rattata",
-- because Route 1 spends several of its ten vanilla slots on the SAME two
-- species while each new one appears once -- so an even split by table is a
-- lopsided split by species.
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
-- The registry patch in src/encounters.lua is kept, but it is NOT trusted to
-- have landed: routes stayed vanilla through several rounds of fixes even
-- though the merge, the schema and the payload all check out in isolation.
-- Rather than keep guessing which layer eats the write, this reconciles
-- against the table the game actually rolls on -- the same live-Data approach
-- Kanto-Reforged falls back to, and the same game.ready pass that provably
-- works (it is what retargets the rival).
--
-- Idempotent by species membership, so it is a no-op for any row the registry
-- patch already delivered and cannot double-add on a hot reload.
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
  -- The game.ready payload is a WRAPPER: ModRuntime.emit("game.ready",
  -- { game = self }) in src/core/Game.lua.  Taking the argument as the Game
  -- itself makes payload.data nil, so the whole pass returned immediately and
  -- did nothing -- silently.  That single mistake broke BOTH the rival
  -- retarget and the encounter widening.
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
  -- Always printed, even at zero.  "0 slots added" is the single most useful
  -- diagnostic when routes look vanilla, and there is no log FILE to dig
  -- through -- Logger uses print, so this only appears on stdout.
  mod.log:info("wild reconcile: %d slots added, %d bucket tables widened",
    addedSlots, fixed)

  -- Re-derive dexSize from the MERGED dataset and only ever raise.  Another
  -- mod may add species past ours, and seedDefaults cannot help by then.
  -- Lowering would truncate someone else's roster, so max() not assignment.
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
-- game.ready alone SHOULD be enough: Data:load() runs once (src/core/Game.lua)
-- and game.ready is emitted after it, while OverworldController reads
-- `Game.data.encounters[self.map.id]` live on every step.  But routes stayed
-- vanilla through several rounds of otherwise-correct fixes, so this stops
-- assuming that reasoning is complete.  If anything reloads or re-folds Data
-- after boot, the next map entry repairs it.
--
-- Safe to run repeatedly: applyPlacement is idempotent by species membership
-- and widenBuckets only fires when a table's bucket count disagrees with its
-- slot count, so the steady state is a couple of table scans and no writes.
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
