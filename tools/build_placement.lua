-- Generate data/placement.lua: which new species appear on which map.
--
--   luajit tools/build_placement.lua /path/to/encounters.lua
--
-- ENCOUNTERS.lua is the engine's extracted table, from your own cache:
--   Windows  %APPDATA%\LOVE\pokemon-love2d\data\generated\encounters.lua
--   macOS    ~/Library/Application Support/LOVE/pokemon-love2d/data/generated/
--   Linux    ~/.local/share/love/pokemon-love2d/data/generated/
--
-- Written in Lua rather than Python so it can dofile() both that table and
-- our own data/species.lua directly, with no format bridge in between.
--
-- WHAT IT IS SOLVING
-- Kanto has 58 encounter tables of exactly 10 slots = 580 vanilla slots.
-- There are 455 non-legendary species in dex 152-649. So every species can
-- appear roughly once, with a little slack -- there is no room for the
-- vanilla texture of the same Pidgey on six routes. Appended rows therefore
-- go *alongside* the vanilla ten (EXTENDED SLOTS widens the table) rather
-- than replacing them, which keeps Kanto's own identity intact underneath.
--
-- SCORING
-- Three signals, in descending trustworthiness:
--
--   1. Terrain.  Inferred from the map id, matched against the species'
--      PokeAPI habitat where it exists and its TYPES where it does not.
--      Habitat is FR/LG data and only covers Gen 1-3, so 263 of our 498
--      species have none -- types carry those, and a Water type in a cave
--      pool or a Rock type in tall grass is the thing to avoid.
--   2. Level fit.  Each map has a vanilla level band; BST is compared against
--      the band's expected power. A 600-BST pseudo-legendary on Route 1 is
--      the failure this prevents.
--   3. Evolution stage.  Basic forms early, final forms late. A first-stage
--      species in Cerulean Cave is merely odd; a final form on Route 1 is a
--      broken difficulty curve.
--
-- Legendaries (43) are excluded entirely: a static legendary is a designed
-- encounter, not something to sprinkle into grass.
--
-- COVERAGE
-- Assignment is hardest-to-place first, so nothing is left uncatchable. A
-- plain greedy fill strands the awkward species with nowhere to go.

local encPath = arg and arg[1]
if not encPath then
  io.stderr:write("usage: luajit tools/build_placement.lua ENCOUNTERS.lua\n")
  os.exit(1)
end

local encounters = assert(dofile(encPath), "cannot load " .. encPath)
local species = assert(dofile("data/species.lua"), "cannot load species")

-- ---------------------------------------------------------------- terrain

-- Terrain tag per map, by id. Order matters: the first match wins, so the
-- specific patterns sit above ROUTE_.
local TERRAIN_RULES = {
  { "^SEAFOAM", "ice_cave" },
  { "^CERULEAN_CAVE", "cave_deep" },
  { "^MT_MOON", "cave" },
  { "^ROCK_TUNNEL", "cave" },
  { "^DIGLETTS_CAVE", "cave" },
  { "^VICTORY_ROAD", "cave_deep" },
  { "^POKEMON_TOWER", "haunted" },
  { "^POKEMON_MANSION", "ruin" },
  { "^POWER_PLANT", "industrial" },
  { "^VIRIDIAN_FOREST", "forest" },
  { "^SAFARI_ZONE", "grassland" },
  { "^ROUTE_", "grassland" },
}

local function terrainOf(mapId)
  for _, rule in ipairs(TERRAIN_RULES) do
    if mapId:find(rule[1]) then return rule[2] end
  end
  return "grassland"
end

-- PokeAPI habitat ids.
local HABITAT = {
  ["1"] = "cave", ["2"] = "forest", ["3"] = "grassland", ["4"] = "mountain",
  ["5"] = "rare", ["6"] = "rough-terrain", ["7"] = "sea", ["8"] = "urban",
  ["9"] = "waters-edge",
}

-- How well a habitat suits a terrain. Absent pairs score 0.
local HABITAT_FIT = {
  grassland = { grassland = 3, forest = 2, ["rough-terrain"] = 1, urban = 1 },
  forest = { forest = 3, grassland = 1, cave = 1 },
  cave = { cave = 3, mountain = 2, ["rough-terrain"] = 1 },
  cave_deep = { cave = 3, mountain = 2, ["rough-terrain"] = 2, rare = 1 },
  ice_cave = { cave = 2, sea = 2, mountain = 1, ["waters-edge"] = 1 },
  haunted = { cave = 1, urban = 1, rare = 1 },
  ruin = { cave = 1, ["rough-terrain"] = 1, urban = 1 },
  industrial = { urban = 3, cave = 1 },
  water = { sea = 3, ["waters-edge"] = 3 },
}

-- Types that belong in a terrain, and types that clearly do not. This is the
-- signal that carries the 263 species with no habitat data at all.
local TYPE_FIT = {
  grassland = { good = { NORMAL = 2, GRASS = 2, BUG = 2, FLYING = 2,
                         POISON = 1, GROUND = 1, ELECTRIC = 1, FAIRY = 1 },
                bad = { WATER = -3, ICE = -2, STEEL = -1, DRAGON = -2 } },
  forest = { good = { BUG = 3, GRASS = 3, POISON = 1, FLYING = 1, FAIRY = 1 },
             bad = { WATER = -3, ICE = -3, ROCK = -2, STEEL = -2, FIRE = -1 } },
  cave = { good = { ROCK = 3, GROUND = 3, STEEL = 2, BUG = 1, POISON = 1,
                    FIGHTING = 1, DARK = 1 },
           bad = { WATER = -2, GRASS = -3, FLYING = -1, FAIRY = -1 } },
  cave_deep = { good = { ROCK = 2, GROUND = 2, STEEL = 2, FIGHTING = 2,
                         DARK = 2, DRAGON = 2, PSYCHIC_TYPE = 1 },
                bad = { GRASS = -3, WATER = -2, BUG = -1 } },
  ice_cave = { good = { ICE = 3, WATER = 2, ROCK = 1, STEEL = 1 },
               bad = { GRASS = -3, FIRE = -3, BUG = -2, GROUND = -1 } },
  haunted = { good = { GHOST = 3, POISON = 2, DARK = 2, PSYCHIC_TYPE = 1 },
              bad = { GRASS = -2, WATER = -2, NORMAL = -1, FIGHTING = -1 } },
  ruin = { good = { FIRE = 3, POISON = 2, DARK = 1, STEEL = 1, GHOST = 1 },
           bad = { WATER = -3, ICE = -3, GRASS = -2 } },
  industrial = { good = { ELECTRIC = 3, STEEL = 3, POISON = 1 },
                 bad = { GRASS = -3, WATER = -2, ICE = -2, BUG = -1 } },
  water = { good = { WATER = 3, ICE = 1, FLYING = 1 },
            bad = { FIRE = -3, GROUND = -3, ROCK = -2, GRASS = -1,
                    ELECTRIC = -1, STEEL = -2 } },
}

-- --------------------------------------------------------------- map data

local maps = {}
for mapId, def in pairs(encounters) do
  for _, kind in ipairs({ "grass", "water" }) do
    local t = def[kind]
    if t and t.slots and #t.slots > 0 then
      local lo, hi, sum = 999, 0, 0
      for _, s in ipairs(t.slots) do
        if s.level < lo then lo = s.level end
        if s.level > hi then hi = s.level end
        sum = sum + s.level
      end
      maps[#maps + 1] = {
        id = mapId,
        kind = kind,
        lo = lo,
        hi = hi,
        avg = sum / #t.slots,
        -- water pools read as water regardless of where the map sits
        terrain = (kind == "water") and "water" or terrainOf(mapId),
        rows = {},
      }
    end
  end
end
table.sort(maps, function(a, b)
  if a.avg ~= b.avg then return a.avg < b.avg end
  return a.id < b.id
end)

-- Expected BST for a map's level band. Kanto runs level 2 to 67; a linear
-- ramp from ~300 to ~540 tracks the real curve closely enough, and the
-- tolerance below is what actually does the work.
local function expectedBst(avg)
  local t = (avg - 2) / 65
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return 300 + t * 240
end

local STAGE_TARGET = { basic = 0, middle = 0.5, final = 1 }

-- ------------------------------------------------------------------ score

local function score(sp, map)
  local e = sp.dexExpansion
  local s = 0

  -- 1. terrain via habitat
  local hab = HABITAT[tostring(e.habitat)]
  if hab then
    local fit = HABITAT_FIT[map.terrain]
    s = s + ((fit and fit[hab]) or 0)
  end

  -- 2. terrain via types (always available)
  local tf = TYPE_FIT[map.terrain]
  if tf then
    for _, ty in ipairs(sp.types) do
      s = s + (tf.good[ty] or 0) + (tf.bad[ty] or 0)
    end
  end

  -- 3. level fit: penalise the gap between BST and the band's expectation
  local want = expectedBst(map.avg)
  local gap = math.abs(e.bst - want)
  s = s - gap / 60

  -- 4. stage fit: basic early, final late
  local t = (map.avg - 2) / 65
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local target = STAGE_TARGET[e.stage] or 0.5
  s = s - math.abs(target - t) * 2.5

  return s
end

-- ------------------------------------------------------------- assignment

local pool = {}
for _, r in ipairs(species.SPECIES) do
  if not r.dexExpansion.legendary then pool[#pool + 1] = r end
end

local CAP = 10 -- appended rows per table, doubling a vanilla 10-slot table
local capacity = #maps * CAP
io.write(("species to place: %d   tables: %d   capacity: %d\n")
  :format(#pool, #maps, capacity))
if #pool > capacity then
  io.stderr:write("WARNING: more species than capacity; some will be omitted\n")
end

-- Precompute each species' ranked map preferences.
local best = {}
for i, sp in ipairs(pool) do
  local ranked = {}
  for j, map in ipairs(maps) do
    ranked[#ranked + 1] = { j = j, s = score(sp, map) }
  end
  table.sort(ranked, function(a, b) return a.s > b.s end)
  best[i] = ranked
end

-- Hardest-to-place first, so nobody is stranded. "Hardest" = the largest gap
-- between a species' best and tenth-best map, i.e. the species with the
-- fewest genuinely good homes.
local order = {}
for i = 1, #pool do order[#order + 1] = i end
table.sort(order, function(a, b)
  local ga = best[a][1].s - best[a][math.min(10, #best[a])].s
  local gb = best[b][1].s - best[b][math.min(10, #best[b])].s
  if ga ~= gb then return ga > gb end
  return pool[a].dex < pool[b].dex
end)

local function levelFor(map, sp)
  -- Spread appended species across the map's own band.  Stage alone is not
  -- enough: a species with no pre-evolution reads as "basic" even when it is
  -- a 485-BST standalone like Druddigon, and stage-only placement dropped
  -- those at the band's FLOOR -- Druddigon at level 22, Wailmer at level 5.
  -- So blend stage with BST, and let BST dominate for the standalones.
  local e = sp.dexExpansion
  local stageT = STAGE_TARGET[e.stage] or 0.5
  local bstT = (e.bst - 250) / 320
  if bstT < 0 then bstT = 0 elseif bstT > 1 then bstT = 1 end
  local t = stageT * 0.4 + bstT * 0.6
  local lv = map.lo + (map.hi - map.lo) * t
  lv = math.floor(lv + 0.5)
  if lv < map.lo then lv = map.lo end
  if lv > map.hi then lv = map.hi end
  if lv < 2 then lv = 2 end
  return lv
end

local placedCount = 0
local unplaced = {}
for _, i in ipairs(order) do
  local sp = pool[i]
  local done = false
  for _, cand in ipairs(best[i]) do
    local map = maps[cand.j]
    if #map.rows < CAP then
      map.rows[#map.rows + 1] = { level = levelFor(map, sp),
                                  species = sp.id, score = cand.s }
      placedCount = placedCount + 1
      done = true
      break
    end
  end
  if not done then unplaced[#unplaced + 1] = sp.id end
end

-- ------------------------------------------------------------------ emit

local function quote(s) return '"' .. s .. '"' end

local out = {}
out[#out + 1] = "-- GENERATED by tools/build_placement.lua -- do not edit."
out[#out + 1] = "-- Appended wild slots for dex 152-649, scored by terrain,"
out[#out + 1] = "-- BST-to-level fit and evolution stage.  Vanilla rows are"
out[#out + 1] = "-- never touched: these are appended alongside them."
out[#out + 1] = "return {"

local byMap = {}
for _, map in ipairs(maps) do
  byMap[map.id] = byMap[map.id] or {}
  byMap[map.id][map.kind] = map
end

local ids = {}
for id in pairs(byMap) do ids[#ids + 1] = id end
table.sort(ids)

for _, id in ipairs(ids) do
  -- Skip maps that ended up with nothing: an empty record is noise, and
  -- Encounters.apply would iterate it for no reason.
  local any = false
  for _, kind in ipairs({ "grass", "water" }) do
    local m = byMap[id][kind]
    if m and #m.rows > 0 then any = true end
  end
  if any then
  out[#out + 1] = "  " .. id .. " = {"
  for _, kind in ipairs({ "grass", "water" }) do
    local map = byMap[id][kind]
    if map and #map.rows > 0 then
      out[#out + 1] = ("    %s = { -- levels %d-%d, terrain %s")
        :format(kind, map.lo, map.hi, map.terrain)
      table.sort(map.rows, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.species < b.species
      end)
      -- Compact rows: { level, "SPECIES" }.  main.lua normalises these to
      -- { level = , species = } on load.  455 rows in longhand is 23 KB of
      -- mostly field names; this is a third of that and reads as a table.
      local line = "      "
      for _, row in ipairs(map.rows) do
        local cell = ("{%d,%s},"):format(row.level, quote(row.species))
        if #line + #cell > 76 then
          out[#out + 1] = line
          line = "      "
        end
        line = line .. cell
      end
      if line:find("%S") then out[#out + 1] = line end
      out[#out + 1] = "    },"
    end
  end
  out[#out + 1] = "  },"
  end
end
out[#out + 1] = "}"

local fh = assert(io.open("data/placement.lua", "w"))
fh:write(table.concat(out, "\n"), "\n")
fh:close()

io.write(("placed %d species across %d tables\n"):format(placedCount, #maps))
if #unplaced > 0 then
  io.write(("UNPLACED (%d): %s\n"):format(#unplaced,
    table.concat(unplaced, " ")))
end

-- A short readable digest, so the placement can be eyeballed rather than
-- trusted.
io.write("\nsample:\n")
for _, id in ipairs({ "ROUTE_1", "VIRIDIAN_FOREST", "MT_MOON_1F",
                      "POKEMON_TOWER_3F", "POWER_PLANT", "SEAFOAM_ISLANDS_B1F",
                      "CERULEAN_CAVE_1F", "ROUTE_20" }) do
  local m = byMap[id] and (byMap[id].grass or byMap[id].water)
  if m then
    local names = {}
    for _, row in ipairs(m.rows) do
      names[#names + 1] = row.species .. "(" .. row.level .. ")"
    end
    io.write(("  %-22s %s\n"):format(id, table.concat(names, " ")))
  end
end
