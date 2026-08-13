-- Types and moves for dex_expansion.
--
-- EXISTENCE IS UNCONDITIONAL.  AVAILABILITY IS OPTIONAL.  The same rule the
-- species layer uses, applied here for the same reason: a saved mon stores
-- the moves it knows, so a move that stops being registered between two
-- boots would be scrubbed off that mon.  Both modes therefore register
-- every type and every move.  Only what the LEARNSETS point at changes.
--
-- MODERN  species keep their real typing (STEEL / DARK / FAIRY included) and
--         learn the real Gen 2-5 level-up moves.
-- RETRO   species are retyped onto the original 15 (DARK->GHOST,
--         STEEL->GROUND, FAIRY->NORMAL) and every modern move resolves to
--         its nearest Gen 1 ancestor via data/retro.lua.  A modern status
--         move with no ancestor is REMOVED from the learnset rather than
--         faked into a damaging move.
--
-- Verified against the engine:
--   * src/mods/Schemas.lua R.type_chart takes types and matchups on ONE
--     registry, told apart by whether the id contains ">":
--         type    -> { name = ..., category = "physical"|"special" }
--         matchup -> { multiplier = n }   -- n is x10 fixed point
--   * src/battle/TypeChart.lua: "Gen 1 splits physical from special by TYPE,
--     not by move", and reads the per-type `category` from the merged
--     record.  So a new type carries its own damage class and works in the
--     Gen 1 damage model without the per-move split as a prerequisite.
--   * gen1recomp-modern-kanto registers NO types and NO moves -- it only
--     patches matchup multipliers and per-move `category`.  Nothing here
--     duplicates it; where both write the same matchup row the intent is
--     identical, so last-write-wins is harmless.

local NewMoves = require("data.moves")
local Retro = require("data.retro")

local Moves = {}

-- Gen 2's type split, which is what a Gen 1 engine can express.
local NEW_TYPES = {
  { id = "STEEL", name = "STEEL", category = "physical" },
  { id = "DARK", name = "DARK", category = "special" },
  { id = "FAIRY", name = "FAIRY", category = "special" },
}

Moves.RETRO_TYPE = { DARK = "GHOST", STEEL = "GROUND", FAIRY = "NORMAL" }

-- Matchups for the three new types, x10 fixed point (5 = 0.5x, 20 = 2x,
-- 0 = immune).  Only rows that differ from 1x are listed; the engine treats
-- a missing row as neutral.  Attacking rows first, then how the new types
-- are hit by the old ones.
local MATCHUPS = {
  -- STEEL attacking
  { "STEEL>ICE", 20 }, { "STEEL>ROCK", 20 }, { "STEEL>FAIRY", 20 },
  { "STEEL>STEEL", 5 }, { "STEEL>FIRE", 5 }, { "STEEL>WATER", 5 },
  { "STEEL>ELECTRIC", 5 },
  -- DARK attacking
  { "DARK>PSYCHIC_TYPE", 20 }, { "DARK>GHOST", 20 },
  { "DARK>DARK", 5 }, { "DARK>FIGHTING", 5 }, { "DARK>FAIRY", 5 },
  -- FAIRY attacking
  { "FAIRY>FIGHTING", 20 }, { "FAIRY>DRAGON", 20 }, { "FAIRY>DARK", 20 },
  { "FAIRY>FIRE", 5 }, { "FAIRY>POISON", 5 }, { "FAIRY>STEEL", 5 },
  -- old types attacking STEEL
  { "NORMAL>STEEL", 5 }, { "GRASS>STEEL", 5 }, { "ICE>STEEL", 5 },
  { "FLYING>STEEL", 5 }, { "PSYCHIC_TYPE>STEEL", 5 }, { "BUG>STEEL", 5 },
  { "ROCK>STEEL", 5 }, { "DRAGON>STEEL", 5 },
  { "FIRE>STEEL", 20 }, { "FIGHTING>STEEL", 20 }, { "GROUND>STEEL", 20 },
  { "POISON>STEEL", 0 },
  -- old types attacking DARK
  { "PSYCHIC_TYPE>DARK", 0 }, { "GHOST>DARK", 5 },
  { "FIGHTING>DARK", 20 }, { "BUG>DARK", 20 },
  -- old types attacking FAIRY
  { "DRAGON>FAIRY", 0 }, { "FIGHTING>FAIRY", 5 }, { "BUG>FAIRY", 5 },
  { "POISON>FAIRY", 20 },
}

-- Register the types, their matchups and every new move.  Always, in both
-- modes.  `register` is used rather than `patch` because these ids do not
-- exist in the vanilla dataset; if another mod got there first, fall back to
-- patch so we extend rather than fight.
local function registerAll(mod)
  local types, matchups, moves = 0, 0, 0

  for _, t in ipairs(NEW_TYPES) do
    local ok = pcall(function()
      mod.content.type_chart:register(t.id,
        { name = t.name, category = t.category })
    end)
    if not ok then
      pcall(function()
        mod.content.type_chart:patch(t.id, { category = t.category })
      end)
    else
      types = types + 1
    end
  end

  for _, row in ipairs(MATCHUPS) do
    local id, multiplier = row[1], row[2]
    local ok = pcall(function()
      mod.content.type_chart:register(id, { multiplier = multiplier })
    end)
    if not ok then
      ok = pcall(function()
        mod.content.type_chart:patch(id, { multiplier = multiplier })
      end)
    end
    if ok then matchups = matchups + 1 end
  end

  for id, record in pairs(NewMoves) do
    local ok, err = pcall(function()
      mod.content.moves:register(id, record)
    end)
    if ok then
      moves = moves + 1
    else
      mod.log:warn("move %s not registered: %s", id, tostring(err))
    end
  end

  mod.log:info("registered %d types, %d matchups, %d moves",
    types, matchups, moves)
end

-- Returns (resolveMove, resolveTypes) for the active mode.
-- resolveMove(id) -> id | nil   (nil means "drop this learnset entry")
-- resolveTypes(list) -> list
function Moves.apply(mod, mode)
  registerAll(mod)

  if mode ~= "retro" then
    return function(id) return id end, function(list) return list end
  end

  mod.log:info("RETRO GEN 1: learnsets resolve to Gen 1 moves and species "
    .. "are retyped onto the original 15")

  local function resolveMove(id)
    if NewMoves[id] == nil then return id end  -- already a Gen 1 move
    return Retro[id]                            -- may be nil: drop it
  end

  local function resolveTypes(list)
    local out, seen = {}, {}
    for _, t in ipairs(list or {}) do
      local mapped = Moves.RETRO_TYPE[t] or t
      if not seen[mapped] then
        seen[mapped] = true
        out[#out + 1] = mapped
      end
    end
    if #out == 0 then out[1] = "NORMAL" end
    return out
  end

  return resolveMove, resolveTypes
end

-- Rewrite one species record through the resolvers.  Returns a shallow copy
-- so the loaded dataset is never mutated -- a second boot in the other mode
-- has to start from the same source rows.
function Moves.rewrite(record, resolveMove, resolveTypes)
  local out = {}
  for k, v in pairs(record) do out[k] = v end

  out.types = resolveTypes(record.types)

  local lvl1, seen = {}, {}
  for _, id in ipairs(record.level1Moves or {}) do
    local r = resolveMove(id)
    if r and not seen[r] then
      seen[r] = true
      lvl1[#lvl1 + 1] = r
    end
  end
  -- level1Moves must stay non-empty: the randomizer's eligibility gate
  -- rejects a species whose array is empty, which would silently drop it
  -- from the pool entirely.
  if #lvl1 == 0 then lvl1[1] = "TACKLE" end
  out.level1Moves = lvl1

  local learn = {}
  for _, entry in ipairs(record.learnset or {}) do
    local r = resolveMove(entry.move)
    if r then learn[#learn + 1] = { level = entry.level, move = r } end
  end
  out.learnset = learn

  return out
end

return Moves
