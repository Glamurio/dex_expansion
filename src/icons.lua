-- Party-menu icon assignment for Dex Expansion.
--
-- PartyMenu resolves an icon in this order (src/ui/PartyMenu.lua):
--     icons.bySpecies[species]  ->  def.icon  ->  icons.byDex[def.dex]
--
-- `icons.byDex` is the vanilla dex-indexed table and only covers 1..151, so
-- every species this mod adds fell through all three and drew NOTHING.
--
-- Gen 1 has exactly ten icon classes (tools/extract/icons.py): MON, BALL,
-- HELIX, FAIRY, BIRD, WATER, BUG, GRASS, SNAKE, QUADRUPED.  They are shape
-- classes, not per-species art -- any bird-ish thing gets BIRD -- so the job
-- is to pick the closest class from what we know about a species.
--
-- The authoritative source is data/overrides.lua ICON_GROUPS, which is built
-- from PokeAPI body shape and is meant to be hand-edited.  The type table
-- below is only a fallback for a species missing from it.
--
-- Both slots are written: the `icons` registry (which folds into
-- icons.bySpecies) and `def.icon` on the record, because PartyMenu consults
-- either and belt-and-braces costs nothing here.

local Icons = {}

Icons.NAMES = {
  MON = true, BALL = true, HELIX = true, FAIRY = true, BIRD = true,
  WATER = true, BUG = true, GRASS = true, SNAKE = true, QUADRUPED = true,
}

-- Checked in order; the first type that matches wins, so FLYING beating
-- NORMAL is deliberate (a Pidgey-shaped thing is a bird first).
--
-- This is a FALLBACK ONLY.  Type is a poor predictor of silhouette -- it is
-- what made Torchic a quadruped, because FIRE maps there and the shape branch
-- was reading a field that did not exist.
local BY_TYPE = {
  { "FLYING", "BIRD" },
  { "BUG", "BUG" },
  { "GRASS", "GRASS" },
  { "WATER", "WATER" },
  { "ICE", "WATER" },
  { "FAIRY", "FAIRY" },
  { "DRAGON", "SNAKE" },
  { "GROUND", "QUADRUPED" },
  { "ROCK", "HELIX" },
  { "STEEL", "HELIX" },
  { "POISON", "SNAKE" },
  { "FIGHTING", "MON" },
  { "GHOST", "MON" },
  { "DARK", "QUADRUPED" },
  { "PSYCHIC_TYPE", "MON" },
  { "FIRE", "QUADRUPED" },
  { "ELECTRIC", "BALL" },
  { "NORMAL", "QUADRUPED" },
}

-- Pick an icon class for one species record from its types alone.
function Icons.forRecord(record)
  local types = {}
  for _, t in ipairs(record.types or {}) do types[t] = true end
  for _, row in ipairs(BY_TYPE) do
    if types[row[1]] then return row[2] end
  end
  return "MON"
end

-- Expand data/overrides.lua ICON_GROUPS ("BIRD = \"TORCHIC PIPLUP ...\"") into
-- a species -> icon lookup.  Stored inverted in the data file because moving a
-- name between ten lists is a far easier edit than hunting one row out of 498.
function Icons.expand(groups)
  local out = {}
  for name, list in pairs(groups or {}) do
    if Icons.NAMES[name] then
      for id in tostring(list):gmatch("[A-Z0-9_]+") do out[id] = name end
    end
  end
  return out
end

-- `explicit` is that expanded lookup: a hand-editable id -> icon table
-- generated from PokeAPI body shape.  It wins over the heuristics above,
-- because shape predicts the ten-way silhouette far better than element does
-- and because a human needs one obvious place to correct a wrong figure.
function Icons.apply(mod, records, explicit)
  local counts, total = {}, 0
  for _, record in ipairs(records) do
    local name = (explicit and explicit[record.id]) or Icons.forRecord(record)
    if not Icons.NAMES[name] then name = Icons.forRecord(record) end
    record.icon = record.icon or name
    local ok = pcall(function()
      mod.content.icons:register(record.id, name)
    end)
    if not ok then
      pcall(function() mod.content.icons:patch(record.id, name) end)
    end
    counts[name] = (counts[name] or 0) + 1
    total = total + 1
  end
  local parts = {}
  for name, n in pairs(counts) do parts[#parts + 1] = name .. "=" .. n end
  table.sort(parts)
  mod.log:info("assigned %d party icons (%s)", total,
    table.concat(parts, " "))
  return counts
end

return Icons
