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
--   * constants.dexSize is DERIVED from the highest `dex` in the merged
--     registry (src/core/Data.lua seedDefaults), so registering 649 species
--     widens the Pokedex UI with no constant to set.
--   * species are string-keyed and saves are Lua source, so there is no
--     255-index ceiling anywhere in the gameplay path.

local mod = ...

local Data = require("data.species")
local GrowthRates = require("src.growth_rates")
local Encounters = require("src.encounters")
local Moves = require("src.moves")

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
})

local encounterMode = mod.options:get("encounterMode") or "extended"
local available = mod.options:get("available") or "all"
local subsetSeed = mod.options:get("subsetSeed") or ""
local respect = mod.options:get("respectOtherMods")
if respect == nil then respect = true end

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

for _, record in ipairs(Data.SPECIES) do
  record = Moves.rewrite(record, resolveMove, resolveTypes)
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

mod.log:info("registered %d species (%d skipped)", registered, skipped)

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
  Encounters.apply(mod, Data, {
    extended = encounterMode == "extended",
    available = available,
    subsetSeed = subsetSeed,
    respectOtherMods = respect,
  })
end

-- ------------------------------------- runtime bucket reconciliation
-- The safety net, and the reason this mod does not simply trust its own
-- arithmetic.
--
-- src/world/Encounter.lua rolls a slot as:
--     for i, threshold in ipairs(grass.buckets or buckets) do
--       if pick < threshold then local slot = grass.slots[i] ...
--
-- so bucket count and slot count MUST agree.  Registries are not readable
-- during the entry chunk (merge has not happened yet), and other mods
-- append or replace slots on the same maps, so the final count is not
-- knowable at registration time.  Two failure modes follow:
--
--   more slots than buckets -> the tail slots are unreachable (harmless)
--   more buckets than slots -> `slot` is nil and the roll yields NO
--                              encounter, silently cutting the encounter
--                              rate
--
-- The second one is a real bug, and it happens whenever a mod that loads
-- after this one replaces a slot list wholesale.  So rather than trusting
-- the merge, rebuild the thresholds from the slot count that actually
-- survived, evenly spaced to 256.

local function evenBuckets(n)
  local out = {}
  for i = 1, n do out[i] = math.floor(i * 256 / n + 0.5) end
  out[n] = 256 -- Encounter.lua requires the last entry to be exactly 256
  return out
end

mod.events:on("game.ready", function(game)
  local encounters = game and game.data and game.data.encounters
  if type(encounters) ~= "table" then return end
  local fixed = 0
  for mapId, def in pairs(encounters) do
    if type(def) == "table" then
      for _, kind in ipairs({ "grass", "water" }) do
        local table_ = def[kind]
        if type(table_) == "table" and type(table_.slots) == "table" then
          local slots = #table_.slots
          local current = table_.buckets and #table_.buckets or nil
          if slots > 0 and current ~= slots then
            table_.buckets = evenBuckets(slots)
            fixed = fixed + 1
            mod.log:debug("%s.%s: rebuilt %d buckets for %d slots",
              tostring(mapId), kind, current or 0, slots)
          end
        end
      end
    end
  end
  if fixed > 0 then
    mod.log:info("reconciled encounter buckets on %d tables", fixed)
  end
end)
