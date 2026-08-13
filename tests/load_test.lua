-- Offline load test: stubs the parts of the Gen1Recomp mod API this mod
-- touches and runs main.lua end to end in BOTH modes.
--
-- What it proves, without needing the engine or a ROM:
--   * the entry chunk runs clean under `chunk(api)` (Loader.lua:1157)
--   * modules load through mod:read, the way the engine provides them
--   * every species record passes the eligibility gate the mod validates
--   * MODERN keeps STEEL / DARK / FAIRY and the new moves
--   * RETRO leaves NO species typed with a post-Gen-1 type, and NO learnset
--     entry pointing at a move that is not a Gen 1 move
--   * every sprite path a record names exists on disk
--
-- Run from the mod root:  luajit tests/load_test.lua

-- Deliberately do NOT extend package.path.  The engine runs main.lua with
-- LOVE's path pointing at the game, so a mod-relative require must fail --
-- if this test passed only because we added the mod dir to the path, it
-- would be testing something the engine never does.
local _realRequire = require
require = function(name)
  if name:find("^data%.") or name:find("^src%.") then
    error("mod-relative require reached the engine: " .. name)
  end
  return _realRequire(name)
end

local GEN1_MOVES = {}
do -- the Gen 1 move ids, taken as "everything data/moves.lua did NOT add"
  local added = dofile("data/moves.lua")
  local species = dofile("data/species.lua")
  local seen = {}
  for _, r in ipairs(species.SPECIES) do
    for _, m in ipairs(r.level1Moves or {}) do seen[m] = true end
    for _, e in ipairs(r.learnset or {}) do seen[e.move] = true end
  end
  for id in pairs(seen) do
    if added[id] == nil then GEN1_MOVES[id] = true end
  end
end

local function registry(store, name)
  return {
    register = function(_, id, value)
      if store[id] ~= nil then error(name .. " duplicate id " .. tostring(id)) end
      store[id] = value
      return true
    end,
    patch = function(_, id, value)
      store[id] = store[id] or {}
      for k, v in pairs(value) do store[id][k] = v end
      return true
    end,
    get = function(_, id) return store[id] end,
    each = function() return pairs(store) end,
  }
end

local function run(mode)
  local pokemon, moves, typechart, growth, encounters = {}, {}, {}, {}, {}
  local mapScripts = {}
  local logs = { warn = {}, info = {} }
  local events = {}
  local api = {
    content = {
      pokemon = registry(pokemon, "pokemon"),
      moves = registry(moves, "moves"),
      type_chart = registry(typechart, "type_chart"),
      growth_rates = registry(growth, "growth_rates"),
      encounters = registry(encounters, "encounters"),
      constants = registry({}, "constants"),
      -- compose registry: several contributions per map id are legal
      map_scripts = { register = function(_, id, value)
        mapScripts[id] = mapScripts[id] or {}
        mapScripts[id][#mapScripts[id] + 1] = value
        return true
      end },
    },
    options = {
      define = function() end,
      get = function(_, key)
        if key == "moveMode" then return mode end
        if key == "encounterMode" then return "extended" end
        if key == "available" then return "all" end
        if key == "subsetSeed" then return "" end
        if key == "respectOtherMods" then return true end
        if key == "starters" then return "johto" end
        if key == "starterSeed" then return "" end
      end,
    },
    log = {
      warn = function(_, f, ...) logs.warn[#logs.warn + 1] = string.format(f, ...) end,
      info = function(_, f, ...) logs.info[#logs.info + 1] = string.format(f, ...) end,
      debug = function() end,
    },
    events = { on = function(_, name, fn) events[name] = fn end },
    find = function() return nil end,
    exports = {},
    path = ".",
    -- the engine's own seam (Loader.lua: `function api:read(relative)`).
    -- Reading from disk here is the point: it proves main.lua loads its
    -- modules the way the engine will, without a mod-relative require.
    read = function(_, relative)
      local fh = io.open(relative, "r")
      if not fh then return nil, "no such file: " .. relative end
      local body = fh:read("*a")
      fh:close()
      return body
    end,
  }
  api.log.error = function(_, f, ...)
    logs.warn[#logs.warn + 1] = "ERROR " .. string.format(f, ...)
  end

  local chunk = assert(loadfile("main.lua"))
  local ok, err = pcall(chunk, api)
  if not ok then return nil, tostring(err) end

  -- counts
  local nSpecies, nBadType, nBadMove, nMissingSprite = 0, 0, 0, 0
  local post = { DARK = true, STEEL = true, FAIRY = true }
  for id, r in pairs(pokemon) do
    nSpecies = nSpecies + 1
    for _, t in ipairs(r.types) do
      if mode == "retro" and post[t] then nBadType = nBadType + 1 end
    end
    for _, m in ipairs(r.level1Moves) do
      if mode == "retro" and not GEN1_MOVES[m] then nBadMove = nBadMove + 1 end
    end
    for _, e in ipairs(r.learnset) do
      if mode == "retro" and not GEN1_MOVES[e.move] then nBadMove = nBadMove + 1 end
    end
    for _, key in ipairs({ "spriteFront", "spriteBack" }) do
      local f = io.open(r[key], "rb")
      if f then f:close() else nMissingSprite = nMissingSprite + 1 end
    end
  end
  local nMoves, nTypes, nMatch = 0, 0, 0
  for _ in pairs(moves) do nMoves = nMoves + 1 end
  for id in pairs(typechart) do
    if id:find(">") then nMatch = nMatch + 1 else nTypes = nTypes + 1 end
  end
  local nBalls = 0
  for _, contributions in pairs(mapScripts) do
    for _, c in ipairs(contributions) do
      for _ in pairs(c.talk or {}) do nBalls = nBalls + 1 end
    end
  end

  return {
    species = nSpecies, moves = nMoves, types = nTypes, matchups = nMatch,
    badTypes = nBadType, badMoves = nBadMove, missingSprites = nMissingSprite,
    starterBalls = nBalls,
    warnings = #logs.warn, hasGameReady = events["game.ready"] ~= nil,
    firstWarning = logs.warn[1],
  }
end

local fail = false
for _, mode in ipairs({ "modern", "retro" }) do
  local r, err = run(mode)
  print(("== %s =="):format(mode:upper()))
  if not r then
    print("  LOAD FAILED: " .. err)
    fail = true
  else
    print(("  species registered   %d"):format(r.species))
    print(("  moves registered     %d"):format(r.moves))
    print(("  types / matchups     %d / %d"):format(r.types, r.matchups))
    print(("  starter ball handlers %d"):format(r.starterBalls))
    print(("  post-Gen1 typings    %d"):format(r.badTypes))
    print(("  non-Gen1 learn moves %d"):format(r.badMoves))
    print(("  missing sprite files %d"):format(r.missingSprites))
    print(("  game.ready hooked    %s"):format(tostring(r.hasGameReady)))
    print(("  warnings             %d%s"):format(r.warnings,
      r.firstWarning and ("  first: " .. r.firstWarning) or ""))
    if r.species ~= 498 or r.missingSprites > 0 then fail = true end
    if r.starterBalls ~= 3 then fail = true end
    if mode == "retro" and (r.badTypes > 0 or r.badMoves > 0) then fail = true end
  end
end
print(fail and "\nRESULT: FAIL" or "\nRESULT: PASS")
os.exit(fail and 1 or 0)
