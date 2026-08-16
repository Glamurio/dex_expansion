-- Types and moves for dex_expansion.
--
-- EXISTENCE IS UNCONDITIONAL.  AVAILABILITY IS OPTIONAL.  The same rule the
-- species layer uses, applied here for the same reason: a saved mon stores
-- the moves it knows, so a move that stops being registered between two
-- boots would be scrubbed off that mon.  Both modes therefore register
-- every type and every move.  Only what the LEARNSETS point at changes.
--
-- MODERN  species keep their real typing (Steel, Dark and Fairy included) and
--         learn the real Gen 2-5 level-up moves.
-- RETRO   species are retyped onto the original 15 (Dark to Ghost, Steel to
--         Ground, Fairy to Normal) and every modern move resolves to its
--         nearest Gen 1 ancestor via data/retro.lua.  A modern status move
--         with no ancestor leaves the learnset rather than being faked into a
--         damaging move.
--
-- Two engine facts this relies on:
--   * src/mods/Schemas.lua R.type_chart takes types and matchups on ONE
--     registry, told apart by whether the id contains ">":
--         type    -> { name = ..., category = "physical"|"special" }
--         matchup -> { multiplier = n }   -- n is x10 fixed point
--   * src/battle/TypeChart.lua: "Gen 1 splits physical from special by TYPE,
--     not by move", and reads the per-type `category` from the merged record.
--     So a new type carries its own damage class and works in the Gen 1 damage
--     model without the per-move split as a prerequisite.
--
-- gen1recomp-modern-kanto registers no types and no moves -- it only patches
-- matchup multipliers and per-move `category` -- so nothing here duplicates it.

-- Data tables arrive as chunk arguments rather than through `require`: a
-- mod-relative require does not resolve at runtime (the loader runs with
-- LOVE's package path pointing at the game).  main.lua reads and compiles
-- these with mod:read + loadstring, the same seam quality_of_life uses.
local NewMoves, Retro, statusList, fixes = ...
fixes = fixes or {}

-- data/move_fixes.lua holds display names that fit the 12-character field,
-- flat powers for moves Gen 1 cannot compute, secondary effects mapped onto
-- its 82 constants, and the removal list.  Applied here rather than baked into
-- data/moves.lua so the judgement calls stay in one reviewable file.
local Removed = {}
for id in tostring(fixes.REMOVE or ""):gmatch("[A-Z_0-9]+") do
  Removed[id] = true
  NewMoves[id] = nil   -- never registered, so it can never be selected
  Retro[id] = nil
end
for id, name in pairs(fixes.NAMES or {}) do
  if NewMoves[id] then NewMoves[id].name = name end
end
for id, power in pairs(fixes.POWERS or {}) do
  if NewMoves[id] then NewMoves[id].power = power end
end
for id, effect in pairs(fixes.EFFECTS or {}) do
  if NewMoves[id] then NewMoves[id].effect = effect end
end
-- data/overrides.lua ships STATUS_MOVES as one space-separated string; expand
-- it to a set once here rather than scanning a list per species.
local StatusMoves = {}
for id in tostring(statusList or ""):gmatch("[A-Z0-9_]+") do
  StatusMoves[id] = true
end
assert(type(NewMoves) == "table", "src/moves.lua needs data/moves.lua")
assert(type(Retro) == "table", "src/moves.lua needs data/retro.lua")

local Moves = {}

Moves.REMOVED = Removed

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

-- Register the types, their matchups and every new move, in both modes.
-- `register` rather than `patch` because these ids do not exist in the vanilla
-- dataset; if another mod got there first, fall back to patch so we extend
-- rather than fight.
--
-- `skipTypeChart` leaves the chart alone entirely; see Moves.apply.
local function registerAll(mod, skipTypeChart)
  local types, matchups, moves = 0, 0, 0

  for _, t in ipairs(skipTypeChart and {} or NEW_TYPES) do
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

  for _, row in ipairs(skipTypeChart and {} or MATCHUPS) do
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

  if skipTypeChart then
    mod.log:info("type chart left to the mod that owns it; registered %d moves",
      moves)
  else
    mod.log:info("registered %d types, %d matchups, %d moves",
      types, matchups, moves)
  end
end

-- Returns (resolveMove, resolveTypes) for the active mode.
-- resolveMove(id) -> id | nil   (nil means "drop this learnset entry")
-- resolveTypes(list) -> list
--
-- `skipTypeChart` is set when a mod that owns the type chart is installed.
-- KEP registers STEEL / DARK / FAIRY itself and ships a deliberately different
-- chart -- its Dark hits Dark for 2x and Normal for 0.5x, neither of which is
-- the Gen 6 reading -- and it validates with ensureMatchup, which rejects a
-- value that disagrees with its own.  Registering ours first makes its check
-- fail on every row we got to first.  Its chart is a design decision for its
-- world, so it wins; our species reference the types either way.
function Moves.apply(mod, mode, skipTypeChart)
  registerAll(mod, skipTypeChart)

  if mode ~= "retro" then
    return function(id) return id end, function(list) return list end
  end

  mod.log:info("RETRO GEN 1: learnsets resolve to Gen 1 moves and species "
    .. "are retyped onto the original 15")

  local function resolveMove(id)
    if NewMoves[id] == nil then return id end  -- already a Gen 1 move
    return Retro[id]                            -- may be nil: drop it
  end

  -- Dedupe matters here: a Steel/Ground species maps to Ground/Ground, and a
  -- doubled type is not a dual type -- it collapses to a single Ground.
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
    local r = not Removed[id] and resolveMove(id) or nil
    if r and not seen[r] then
      seen[r] = true
      lvl1[#lvl1 + 1] = r
    end
  end
  -- level1Moves must stay non-empty: the randomizer's eligibility gate
  -- rejects a species whose array is empty, which would silently drop it
  -- from the pool entirely.
  if #lvl1 == 0 then lvl1[1] = "TACKLE" end
  -- It also has to contain something that attacks.  41 species had only status
  -- moves at level 1 -- Ralts knew Growl and nothing else, which cannot win a
  -- battle or chip a wild mon enough to catch it.  STATUS_MOVES in
  -- data/overrides.lua lists the Gen 1 moves that deal no damage; fixed-damage
  -- and OHKO moves are deliberately absent, being perfectly good attacks.
  local canAttack = false
  for _, id in ipairs(lvl1) do
    local newMove = NewMoves[id]
    if newMove then
      if (newMove.power or 0) > 0 then canAttack = true end
    elseif not StatusMoves[id] then
      canAttack = true
    end
  end
  if not canAttack then lvl1[#lvl1 + 1] = "TACKLE" end
  out.level1Moves = lvl1

  -- A removed move has to leave every learnset too: learnset[].move is an
  -- f.id("moves") reference, and a dangling one fails the post-merge
  -- cross-check and takes the whole mod down, not just that row.
  local learn = {}
  for _, entry in ipairs(record.learnset or {}) do
    local r = not Removed[entry.move] and resolveMove(entry.move) or nil
    if r then learn[#learn + 1] = { level = entry.level, move = r } end
  end
  out.learnset = learn

  return out
end

return Moves
