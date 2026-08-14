-- Party-menu icon assignment for Dex Expansion.
--
-- PartyMenu resolves an icon in this order (src/ui/PartyMenu.lua):
--     icons.bySpecies[species]  ->  def.icon  ->  icons.byDex[def.dex]
--
-- `icons.byDex` is dex-indexed and covers 1..151 only, so anything past that
-- needs an entry of its own or it draws nothing.
--
-- Gen 1 has ten icon classes (tools/extract/icons.py): MON, BALL, HELIX, FAIRY,
-- BIRD, WATER, BUG, GRASS, SNAKE, QUADRUPED.  They are shape classes rather
-- than per-species art, so the job is picking the closest fit.
--
-- data/overrides.lua ICON_GROUPS is the source of truth: built from PokeAPI
-- body shape, and meant to be hand-edited.  The type table below is a fallback
-- for anything missing from it.
--
-- Both slots are written -- the `icons` registry, which folds into
-- icons.bySpecies, and `def.icon` on the record -- since PartyMenu consults
-- either.

local Icons = {}

Icons.NAMES = {
  MON = true, BALL = true, HELIX = true, FAIRY = true, BIRD = true,
  WATER = true, BUG = true, GRASS = true, SNAKE = true, QUADRUPED = true,
}

-- Checked in order, first match wins, so Flying beating Normal is deliberate:
-- a Pidgey-shaped thing is a bird first.
--
-- Fallback only.  Type is a poor predictor of silhouette: it puts Torchic on
-- the quadruped figure, because Fire maps there.
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

-- Expand ICON_GROUPS ("BIRD = \"TORCHIC PIPLUP ...\"") into a species -> icon
-- lookup.  Stored inverted in the data file because moving a name between ten
-- lists is an easier edit than finding one row among 498.
function Icons.expand(groups)
  local out = {}
  for name, list in pairs(groups or {}) do
    if Icons.NAMES[name] then
      for id in tostring(list):gmatch("[A-Z0-9_]+") do out[id] = name end
    end
  end
  return out
end

-- `explicit` is that expanded lookup, and it wins over the type heuristic:
-- shape predicts the ten-way silhouette better than element does, and a human
-- needs one obvious place to correct a wrong figure.
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
