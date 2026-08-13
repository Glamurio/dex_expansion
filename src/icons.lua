-- Party-menu icon assignment for Dex Expansion.
--
-- PartyMenu resolves an icon in this order (src/ui/PartyMenu.lua):
--     icons.bySpecies[species]  ->  def.icon  ->  icons.byDex[def.dex]
--
-- `icons.byDex` is the vanilla dex-indexed table and only covers 1..151, so
-- every species this mod adds fell through all three and drew NOTHING.  That
-- is why Treecko had no figure in the party menu.
--
-- Gen 1 has exactly ten icon classes (tools/extract/icons.py): MON, BALL,
-- HELIX, FAIRY, BIRD, WATER, BUG, GRASS, SNAKE, QUADRUPED.  They are shape
-- classes, not per-species art -- any bird-ish thing gets BIRD -- so the job
-- is to pick the closest class from what we know about a species.
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

-- PokeAPI body shapes, where we have them, beat the type guess: shape is a
-- much better predictor of which ten-way silhouette fits.  Ids come from
-- pokemon_shapes: 1 ball, 2 squiggle, 3 fish, 4 arms, 5 blob, 6 upright,
-- 7 legs, 8 quadruped, 9 wings, 10 tentacles, 11 heads, 12 humanoid,
-- 13 bug-wings, 14 armor.  Only the unambiguous ones are mapped; the rest
-- fall through to type, which handles them better than a wrong silhouette.
local BY_SHAPE = {
  ["1"] = "BALL",       -- ball
  ["2"] = "SNAKE",      -- squiggle
  ["3"] = "WATER",      -- fish
  ["8"] = "QUADRUPED",  -- quadruped
  ["9"] = "BIRD",       -- wings
  ["10"] = "WATER",     -- tentacles
  ["13"] = "BUG",       -- bug-wings
  ["14"] = "BUG",       -- armor
}

-- Pick an icon class for one species record.
function Icons.forRecord(record)
  local ext = record.dexExpansion or {}
  local byShape = BY_SHAPE[tostring(ext.shape or "")]
  if byShape then return byShape end
  local types = {}
  for _, t in ipairs(record.types or {}) do types[t] = true end
  for _, row in ipairs(BY_TYPE) do
    if types[row[1]] then return row[2] end
  end
  return "MON"
end

function Icons.apply(mod, records)
  local counts, total = {}, 0
  for _, record in ipairs(records) do
    local name = Icons.forRecord(record)
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
