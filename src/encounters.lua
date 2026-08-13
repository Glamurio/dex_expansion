-- Wild placement for Dex Expansion.
--
-- Everything here is built on one verified fact about the merge engine:
--
--   `encounters` is a RECORD registry, not a `deep` one.  In
--   gen1recomp/src/mods/Merge.lua, a bare list under record semantics is
--   copied over the destination -- it REPLACES.  Lists "extend only through
--   the __append/__prepend wrappers".
--
-- All_Pokemon_Catchable_151_Mod writes bare 10-slot lists across 33 maps
-- (VIRIDIAN_FOREST, ROUTE_3..25, the Safari Zone quadrants, Seafoam,
-- Victory Road, Cerulean Cave, Power Plant, Pokemon Mansion B1F).  If this
-- mod also wrote bare lists, whichever loaded last would silently erase the
-- other -- no warning, no diagnostic.
--
-- Load order is "priority ascending, ties by id" (src/mods/Loader.lua), and
-- every mod in the ecosystem ships priority 100, so ids decide:
--
--   all_pokemon_catchable_151_mod  <  dex_expansion  <  modern_kanto
--     <  pokemon_randomizer  <  quality_of_life
--
-- We therefore land AFTER the catchability mod, and appending is enough to
-- coexist with it.  The manifest still pins priority explicitly rather than
-- leaning on alphabetical luck.

local Encounters = {}

-- A deterministic string hash, reproducible across platforms and runs
-- without depending on Lua's PRNG (which differs by build).
--
-- LOVE runs LuaJIT, i.e. Lua 5.1 SYNTAX.  The bitwise operators `~`, `&`,
-- `|`, `<<`, `>>` and integer division `//` are Lua 5.3+ and are a SYNTAX
-- error under LuaJIT -- the whole file fails to parse, not just this
-- function.  (`luac` from Lua 5.4 accepts them happily, which is exactly how
-- a bad build slips through; validate with `luajit -bl`.)  So this is a plain
-- polynomial hash in pure arithmetic: no bit ops, same result everywhere.
local MASK = 2147483648 -- 2^31, keeps products inside a double exactly
local function hash32(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + str:byte(i)) % MASK
  end
  return h
end

-- A deterministic 151-species subset, drawn from the FULL registered roster.
--
-- This is the "one-to-one feel" option, and it is the direct descendant of
-- Sanqui's `game_pokemon`, which picked 150 of 721 and dropped them into the
-- cartridge's dex slots.  He had to: the ROM had ~253 slots.  We do not, so
-- the pick restricts APPEARANCE only -- every species stays registered and
-- every save stays scrub-safe.
function Encounters.subset(species, seed, size)
  size = size or 151
  local pool = {}
  for _, record in ipairs(species) do pool[#pool + 1] = record.id end
  table.sort(pool) -- stable input order regardless of registry iteration
  -- Fisher-Yates driven by a seeded LCG, so the same seed always yields the
  -- same roster on every machine.
  local state = (hash32(tostring(seed or "")) % 2147483647) + 1
  local function nextInt(n)
    -- modulo rather than a bitmask: see the note on hash32 above
    state = (1103515245 * state + 12345) % 2147483648
    return (state % n) + 1
  end
  for i = #pool, 2, -1 do
    local j = nextInt(i)
    pool[i], pool[j] = pool[j], pool[i]
  end
  local chosen = {}
  for i = 1, math.min(size, #pool) do chosen[pool[i]] = true end
  return chosen
end

-- Place `rows` onto a map, additively.
--
-- `extended` widens the slot table so added species have somewhere to go
-- instead of evicting vanilla ones; the widening itself happens at
-- game.ready, see below.
function Encounters.place(mod, mapId, kind, rows, opts)
  if #rows == 0 then return 0 end
  local payload = { slots = { __append = rows } }
  -- DO NOT put `buckets` in this payload.
  --
  -- THIS WAS A REAL BUG, and a silent one: every route kept showing only its
  -- vanilla encounters, with no error anywhere.  R.encounters types
  -- grass/water as a NESTED f.rec{ rate, slots }, and nested records are
  -- STRICT -- Schemas.lua: "Nested recs stay strict, that is where typos
  -- hide".  So `buckets` is an unknown field at register time and the WHOLE
  -- patch is rejected, even though Encounter.roll honours `buckets` happily
  -- at runtime.  Verified against the engine's own validator:
  --
  --   encounters.ROUTE_1.grass.buckets: unknown field
  --
  -- tests/encounter_schema_test.lua pins both directions of this.
  --
  -- Widening is done instead by the game.ready reconciliation in main.lua,
  -- which writes straight to live Data.encounters and so is not schema-bound.
  -- It rebuilds thresholds from the slot count that actually survived the
  -- merge, which is more correct than guessing the count here anyway.
  local ok, err = pcall(function()
    mod.content.encounters:patch(mapId, { [kind] = payload })
  end)
  if not ok then
    mod.log:warn("encounters %s.%s: %s", mapId, kind, tostring(err))
    return 0
  end
  return #rows
end

function Encounters.apply(mod, Data, opts)
  local allowed = nil
  if opts.available == "subset151" then
    allowed = Encounters.subset(Data.SPECIES, opts.subsetSeed, 151)
    mod.log:info("RANDOM 151: restricting wild appearances to a seeded "
      .. "subset (seed %q); all species remain registered",
      tostring(opts.subsetSeed))
  end

  -- Maps another mod is known to author wholesale.  With YIELD TO OTHER MODS
  -- on we leave these alone entirely rather than appending into a table
  -- someone else curated -- their placement is deliberate and ours is
  -- heuristic, so theirs should win.
  local contested = {}
  if opts.respectOtherMods then
    for _, id in ipairs(Data.CONTESTED_MAPS or {}) do contested[id] = true end
  end

  local placed, yielded = 0, 0
  for mapId, kinds in pairs(Data.PLACEMENT or {}) do
    if contested[mapId] then
      yielded = yielded + 1
    else
      for kind, rows in pairs(kinds) do
        local filtered = {}
        for _, row in ipairs(rows) do
          if not allowed or allowed[row.species] then
            filtered[#filtered + 1] = { level = row.level,
                                        species = row.species }
          end
        end
        placed = placed + Encounters.place(mod, mapId, kind, filtered, {
          extended = opts.extended,
          baseSlots = 10, -- vanilla Gen 1 table width
        })
      end
    end
  end

  mod.log:info("placed %d wild slots (%d maps yielded to other mods)",
    placed, yielded)
  if not opts.extended and placed > 0 then
    mod.log:warn("VANILLA SLOTS: appended slots beyond the 10 vanilla "
      .. "buckets are unreachable until buckets are widened")
  end
  return placed
end

return Encounters
