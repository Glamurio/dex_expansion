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

-- Stub just enough of love.filesystem for src/diagnostics.lua.  Writing the
-- report is the only observability the mod has on a fused .exe, so the test
-- has to prove it actually produces a file with the numbers in it.
local writtenReport = nil
love = love or {}
love.filesystem = love.filesystem or {}
love.filesystem.write = function(name, body) writtenReport = body; return true end
love.filesystem.getSaveDirectory = function() return "/tmp/fake-save" end

local GEN1_MOVES = {}
do
  -- "Gen 1 move" means exactly what src/moves.lua means by it: anything this
  -- mod does not add.  The old definition -- moves appearing in species.lua's
  -- learnsets -- silently broke once those learnsets gained entries, and
  -- flagged 123 perfectly valid retro ancestors that simply never appeared in
  -- the original data.
  local added = dofile("data/moves.lua")
  for id, def in pairs(dofile("data/moves_extra.lua")) do added[id] = def end
  local retro = dofile("data/retro.lua")
  for id in pairs(retro) do
    if added[id] == nil then GEN1_MOVES[id] = true end
  end
  for _, id in ipairs({ "TACKLE", "SWIFT", "GROWL", "LEER", "EMBER",
    "SCRATCH", "BITE", "POUND", "HARDEN", "STRING_SHOT" }) do
    GEN1_MOVES[id] = true
  end
  setmetatable(GEN1_MOVES, { __index = function(_, id)
    -- anything we did not add is the engine's, i.e. Gen 1
    return added[id] == nil or nil
  end })
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

-- evolution targets the ENGINE provides, so absent from our registry stub
local VANILLA_EVO_TARGETS = { PIKACHU = true, CLEFAIRY = true,
  JIGGLYPUFF = true, CHANSEY = true, MR_MIME = true, SNORLAX = true }
local specialMode = "spa"
local startersOpt = nil
local kepInstalled = false
local function run(mode)
  local pokemon, moves, typechart, growth, encounters = {}, {}, {}, {}, {}
  -- These two were previously nil GLOBALS: the registry stubs referenced them
  -- and every text/icon register threw, silently swallowed by main.lua's
  -- pcall.  A stub that errors is indistinguishable from a feature that works.
  local textStore, iconStore, constantStore, cryStore = {}, {}, {}, {}
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
      -- KEYED, like the real R.constants: register(key, value).  The old stub
      -- accepted a whole table and so happily passed the exact call shape that
      -- silently failed in game.
      constants = { register = function(_, key, value)
        if type(key) ~= "string" then
          error("constants registry is keyed: expected a key, got "
            .. type(key))
        end
        constantStore[key] = value
        return true
      end },
      icons = registry(iconStore, "icons"),
      cries = registry(cryStore, "cries"),
      text = registry(textStore, "text"),
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
        if key == "starters" then return startersOpt or "johto" end
        if key == "starterSeed" then return "" end
        if key == "newShare" then return "most" end
        if key == "specialMode" then return specialMode or "spa" end
      end,
    },
    log = {
      warn = function(_, f, ...) logs.warn[#logs.warn + 1] = string.format(f, ...) end,
      info = function(_, f, ...) logs.info[#logs.info + 1] = string.format(f, ...) end,
      debug = function() end,
    },
    events = { on = function(_, name, fn)
      events[name] = events[name] or {}
      events[name][#events[name] + 1] = fn
    end },
    -- main.lua calls mod.find("id") with a DOT, so the id arrives as the first
    -- argument; accept either shape rather than silently returning nil.
    find = function(a, b)
      local id = b or a
      return (kepInstalled and id == "kep") and {} or nil
    end,
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
  -- The retype pass PATCHES vanilla ids (Magnemite et al), so the store also
  -- holds partial records that are not ours.  Only full records carry
  -- dexExpansion; counting the patches as species would inflate the total and
  -- crash on their missing arrays.
  local retypedIds = {}
  for id, r in pairs(pokemon) do
    if not r.dexExpansion then
      retypedIds[id] = r.types
    else
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
    icons = iconStore, texts = textStore, pokemon = pokemon,
    encounters = encounters,
    moveDefs = moves, typechart = typechart,
    constants = constantStore, cries = cryStore,
    retypedIds = retypedIds,
    badTypes = nBadType, badMoves = nBadMove, missingSprites = nMissingSprite,
    starterBalls = nBalls,
    warnings = #logs.warn, hasGameReady = events["game.ready"] ~= nil,
    fireGameReady = function(gameStub)
      -- EXACTLY the shape the engine emits: ModRuntime.emit("game.ready",
      -- { game = self }).  Passing the Game directly here would let the old
      -- payload bug pass the test.
      for _, fn in ipairs(events["game.ready"] or {}) do
        fn({ game = gameStub })
      end
    end,
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
    local LEGAL_ICONS = { MON = true, BALL = true, HELIX = true,
      FAIRY = true, BIRD = true, WATER = true, BUG = true, GRASS = true,
      SNAKE = true, QUADRUPED = true }
    local nIcons, nBadIcon = 0, 0
    for _, name in pairs(r.icons or {}) do
      nIcons = nIcons + 1
      if not LEGAL_ICONS[name] then nBadIcon = nBadIcon + 1 end
    end
    local nTexts = 0
    for _ in pairs(r.texts or {}) do nTexts = nTexts + 1 end
    -- Magnemite stayed pure Electric until the retype pass existed: the new
    -- types mean nothing on vanilla species unless their records are patched
    local nRetyped = 0
    for _ in pairs(r.retypedIds or {}) do nRetyped = nRetyped + 1 end
    local magnemite = (r.retypedIds or {}).MAGNEMITE
    local magOK = magnemite and magnemite[1] == "ELECTRIC"
      and magnemite[2] == "STEEL"
    print(("  vanilla retypes      %d (Magnemite Electric/Steel: %s)")
      :format(nRetyped, tostring(magOK and true or false)))
    if mode == "modern" and (nRetyped ~= 7 or not magOK) then fail = true end
    if mode == "retro" and nRetyped ~= 0 then fail = true end
    -- The Pokedex stayed at 151 because seedDefaults derives dexSize BEFORE
    -- mods merge, so it must be patched explicitly.
    print(("  dexSize / dexDigits  %s / %s"):format(
      tostring(r.constants.dexSize), tostring(r.constants.dexDigits)))
    if r.constants.dexSize ~= 649 or r.constants.dexDigits ~= 3 then
      fail = true
    end
    local nCries = 0
    for _, def in pairs(r.cries or {}) do
      if type(def) == "table" and def.file then nCries = nCries + 1 end
    end
    print(("  cries registered     %d"):format(nCries))
    if nCries ~= 498 then fail = true end
    -- The headline feature was invisible: registering STEEL/DARK/FAIRY does
    -- nothing if no species carries them, and build_species_data.py had
    -- silently dropped every one of those slots.
    local newTypeCounts = { STEEL = 0, DARK = 0, FAIRY = 0 }
    for _, rec in pairs(r.pokemon or {}) do
      for _, t in ipairs(rec.types or {}) do
        if newTypeCounts[t] then newTypeCounts[t] = newTypeCounts[t] + 1 end
      end
    end
    print(("  species typed STEEL/DARK/FAIRY  %d / %d / %d"):format(
      newTypeCounts.STEEL, newTypeCounts.DARK, newTypeCounts.FAIRY))
    if mode == "modern" then
      if newTypeCounts.STEEL < 30 or newTypeCounts.DARK < 30
          or newTypeCounts.FAIRY < 10 then
        fail = true
      end
    else
      -- RETRO must fold them away entirely
      if newTypeCounts.STEEL + newTypeCounts.DARK
          + newTypeCounts.FAIRY > 0 then
        fail = true
      end
    end
    -- Every move a learnset names must be registered.  A dangling
    -- f.id("moves") reference fails the post-merge cross-check and takes the
    -- WHOLE mod down, so removing 102 unsupported moves is only safe if they
    -- also leave every learnset.
    local MF = dofile("data/move_fixes.lua")
    local removed = {}
    for id in tostring(MF.REMOVE):gmatch("[A-Z_0-9]+") do removed[id] = true end
    local dangling, zeroPower, longName = 0, 0, 0
    for _, rec in pairs(r.pokemon or {}) do
      if rec.dexExpansion then
        for _, mv in ipairs(rec.level1Moves or {}) do
          if removed[mv] then dangling = dangling + 1 end
        end
        for _, e in ipairs(rec.learnset or {}) do
          if removed[e.move] then dangling = dangling + 1 end
        end
      end
    end
    for id, def in pairs(r.moveDefs or {}) do
      -- a damaging move at 0 power deals literally nothing (the Beat Up bug)
      if def.category ~= "status" and (def.power or 0) == 0 then
        zeroPower = zeroPower + 1
        print("  FAIL: " .. id .. " is damaging but has 0 power")
      end
      if type(def.name) == "string" and #def.name > 12 then
        longName = longName + 1
        print(("  FAIL: name %q is %d chars, field holds 12")
          :format(def.name, #def.name))
      end
      if removed[id] then
        print("  FAIL: " .. id .. " was removed but still registered")
        dangling = dangling + 1
      end
    end
    print(("  removed moves still referenced %d"):format(dangling))
    print(("  damaging moves at 0 power      %d"):format(zeroPower))
    print(("  move names over 12 chars       %d"):format(longName))
    if dangling > 0 or zeroPower > 0 or longName > 0 then fail = true end
    -- growth rates and evolution targets must all resolve, or the post-merge
    -- cross-check fails the whole mod
    local LEGAL_GROWTH = { FAST = true, MEDIUM_FAST = true,
      MEDIUM_SLOW = true, SLOW = true, ERRATIC = true, FLUCTUATING = true }
    local badGrowth, danglingEvo = 0, 0
    for id, rec in pairs(r.pokemon or {}) do
      if rec.dexExpansion then
        if not LEGAL_GROWTH[rec.growthRate] then
          badGrowth = badGrowth + 1
          if badGrowth <= 3 then
            print(("  FAIL: %s has growth rate %q"):format(
              id, tostring(rec.growthRate)))
          end
        end
        for _, evo in ipairs(rec.evolutions or {}) do
          if not r.pokemon[evo.species] and not VANILLA_EVO_TARGETS[evo.species]
          then
            danglingEvo = danglingEvo + 1
            if danglingEvo <= 3 then
              print(("  FAIL: %s evolves into unregistered %s"):format(
                id, tostring(evo.species)))
            end
          end
        end
      end
    end
    print(("  bad growth rates %d, dangling evolutions %d")
      :format(badGrowth, danglingEvo))
    if badGrowth > 0 or danglingEvo > 0 then fail = true end
    print(("  party icons assigned %d (illegal %d)"):format(nIcons, nBadIcon))
    print(("  dex entry texts      %d"):format(nTexts))
    -- every mapped evolution must have landed, with a legal method and a
    -- target that exists; a dangling species id fails the merge cross-check
    local extra = dofile("data/evolutions_extra.lua")
    local nEvo, nBadEvo = 0, 0
    for id, list in pairs(extra) do
      local rec = r.pokemon and r.pokemon[id]
      for _, want in ipairs(list) do
        nEvo = nEvo + 1
        local found = false
        for _, got in ipairs((rec and rec.evolutions) or {}) do
          -- match on TARGET only: when the record already reaches that
          -- species by another route (Feebas->Milotic is already TRADE,
          -- Darumaka->Darmanitan already LEVEL 35) the merge correctly skips
          -- ours, and that is not a failure
          if got.species == want.species then found = true end
        end
        -- targets in the vanilla 151 are registered by the ENGINE, not by
        -- us, so they are legitimately absent from this harness's registry
        local VANILLA_TARGETS = { PIKACHU = true, CLEFAIRY = true,
          JIGGLYPUFF = true, CHANSEY = true, MR_MIME = true, SNORLAX = true }
        if not found
            or not (r.pokemon[want.species] or VANILLA_TARGETS[want.species])
        then
          nBadEvo = nBadEvo + 1
        end
      end
    end
    print(("  mapped evolutions    %d (bad %d)"):format(nEvo, nBadEvo))
    if nEvo < 40 or nBadEvo > 0 then fail = true end
    -- every species needs an icon: icons.byDex only covers 1..151, so without
    -- one the party menu draws nothing at all
    if nIcons ~= 498 or nBadIcon > 0 then fail = true end
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

-- ------------------------------------------------------------------------
-- game.ready: prove the two live-Data passes actually DO something.
--
-- Both the encounter widening and the rival retarget run off game.ready, and
-- both silently did nothing because the handler treated the payload as the
-- Game object when it is really { game = <Game> }.  A test that only checked
-- "a handler was registered" passed throughout.  This one fires the event
-- with the engine's real payload shape and asserts on the mutations.

local VANILLA_SLOTS_EXPECTED = 10

do
  local r = run("modern")
  assert(r, "modern load failed")

  -- a Game stub holding vanilla-shaped data
  local game = {
    data = {
      encounters = {
        ROUTE_1 = { grass = { rate = 25, slots = {} } },
        -- an untouched vanilla-width table: must be left completely alone so
        -- it keeps using constants.encounterBuckets
        ROUTE_99 = { grass = { rate = 25, slots = {} } },
      },
      trainers = {
        OPP_RIVAL1 = { parties = {
          { { level = 5, species = "SQUIRTLE" } },
          { { level = 5, species = "BULBASAUR" } },
          { { level = 5, species = "CHARMANDER" } },
        } },
        OPP_RIVAL3 = { parties = {
          { { level = 53, species = "BLASTOISE" } },
        } },
        -- a non-rival trainer carrying a starter must NOT be touched
        OPP_BUG_CATCHER = { parties = { { { level = 9, species = "SQUIRTLE" } } } },
      },
      pokemon = {},
      -- AnimPlayer:start looks up self.data.moveAnims[moveId], NOT the `anim`
      -- field, so a new move needs its own entry or it draws nothing.
      moveAnims = { SCRATCH = { seq = { "scratch" } },
                    SWIFT = { seq = { "swift" } },
                    BITE = { seq = { "bite" } } },
      moves = {
        METAL_CLAW = { anim = "SCRATCH" },
        DAZZLING_GLEAM = { anim = "SWIFT" },
        CRUNCH = { anim = "BITE" },
        SCRATCH = { anim = "SCRATCH" },
      },
    },
  }
  -- the Fairy pass needs real records with learnsets, including the vanilla
  -- Fairies the retype pass creates
  for _, id in ipairs({ "CLEFAIRY", "CLEFABLE", "JIGGLYPUFF", "WIGGLYTUFF",
                        "MR_MIME" }) do
    game.data.pokemon[id] = { types = { "NORMAL" }, learnset = {},
      baseStats = { hp = 60, attack = 60, defense = 60, speed = 60,
                    special = 60 } }
  end
  -- ROUTE_1 starts with ONLY its vanilla ten, exactly as the game reports:
  -- the registry patch is assumed NOT to have landed, so game.ready has to
  -- both add the rows and widen the buckets.
  for i = 1, 10 do
    game.data.encounters.ROUTE_1.grass.slots[i] =
      { level = 3, species = "PIDGEY" }
  end
  for i = 1, 10 do
    game.data.encounters.ROUTE_99.grass.slots[i] =
      { level = 3, species = "PIDGEY" }
  end
  -- the species table the retarget walks for evolution lines
  local sp = dofile("data/species.lua")
  for _, rec in ipairs(sp.SPECIES) do game.data.pokemon[rec.id] = rec end

  r.fireGameReady(game)

  local fail2 = 0

  -- the reported bug: Route 1 still had only Rattata and Pidgey
  local slots = game.data.encounters.ROUTE_1.grass.slots
  if #slots <= 10 then
    print(("  FAIL: ROUTE_1 still has %d slots; placement never landed")
      :format(#slots))
    fail2 = fail2 + 1
  end
  local sawNew = false
  for _, s2 in ipairs(slots) do
    if s2.species ~= "PIDGEY" then sawNew = true end
  end
  if not sawNew then
    print("  FAIL: ROUTE_1 has no new species")
    fail2 = fail2 + 1
  end
  -- running twice must not double-add
  local n1 = #slots
  r.fireGameReady(game)
  if #slots ~= n1 then
    print(("  FAIL: not idempotent (%d -> %d)"):format(n1, #slots))
    fail2 = fail2 + 1
  end

  local buckets = game.data.encounters.ROUTE_1.grass.buckets
  if type(buckets) ~= "table" or #buckets ~= #slots then
    print(("  FAIL: %d buckets for %d slots")
      :format(buckets and #buckets or 0, #slots))
    fail2 = fail2 + 1
  elseif buckets[#buckets] ~= 256 then
    print("  FAIL: last bucket is not 256")
    fail2 = fail2 + 1
  else
    -- the vanilla ten must keep their share and their curve, not be flattened
    -- default NEW SPECIES SHARE is 70% new, so the vanilla ten keep 30%
    local wantSplit = math.floor(256 * 0.30 + 0.5)
    if buckets[VANILLA_SLOTS_EXPECTED] ~= wantSplit then
      print(("  FAIL: vanilla block ends at %d, expected %d")
        :format(buckets[VANILLA_SLOTS_EXPECTED], wantSplit))
      fail2 = fail2 + 1
    end
    -- the vanilla curve must survive the compression, not be flattened
    local evenStep = buckets[2] - buckets[1] == buckets[9] - buckets[8]
    if evenStep then
      print("  FAIL: buckets look evenly spread; vanilla rarity was flattened")
      fail2 = fail2 + 1
    end
    local prev = 0
    for _, v in ipairs(buckets) do
      if v <= prev then
        print("  FAIL: buckets not strictly increasing")
        fail2 = fail2 + 1
        break
      end
      prev = v
    end
  end
  if game.data.encounters.ROUTE_99.grass.buckets ~= nil then
    print("  FAIL: a vanilla-width table was given its own buckets")
    fail2 = fail2 + 1
  end

  -- STARTERS option in the harness is "johto", so the rival's Kanto species
  -- must be replaced by the Johto line, stage for stage
  local rival = game.data.trainers.OPP_RIVAL1.parties
  local want = { [1] = "TOTODILE", [2] = "CHIKORITA", [3] = "CYNDAQUIL" }
  for i, id in pairs(want) do
    if rival[i][1].species ~= id then
      print(("  FAIL: rival party %d is %s, expected %s")
        :format(i, tostring(rival[i][1].species), id))
      fail2 = fail2 + 1
    end
  end
  if game.data.trainers.OPP_RIVAL3.parties[1][1].species ~= "FERALIGATR" then
    print(("  FAIL: late rival final stage is %s, expected FERALIGATR")
      :format(tostring(game.data.trainers.OPP_RIVAL3.parties[1][1].species)))
    fail2 = fail2 + 1
  end
  if game.data.trainers.OPP_BUG_CATCHER.parties[1][1].species ~= "SQUIRTLE" then
    print("  FAIL: a non-rival trainer was rewritten")
    fail2 = fail2 + 1
  end

  print("")
  print(("game.ready: ROUTE_1 %d slots, buckets %s, rival %s"):format(
    #slots,
    (buckets and #buckets == #slots) and ("->" .. #buckets) or "BROKEN",
    rival[1][1].species .. "/" .. rival[2][1].species
      .. "/" .. rival[3][1].species))
  -- Every move must resolve to an animation, or it plays a sound and shakes
  -- the screen while drawing nothing.
  do
    local anims = game.data.moveAnims
    for _, id in ipairs({ "METAL_CLAW", "DAZZLING_GLEAM", "CRUNCH" }) do
      if anims[id] == nil then
        print("  FAIL: " .. id .. " has no animation entry")
        fail2 = fail2 + 1
      elseif anims[id] ~= anims[game.data.moves[id].anim] then
        print("  FAIL: " .. id .. " is not aliased to its source animation")
        fail2 = fail2 + 1
      end
    end
    print(("  move animations aliased: METAL_CLAW->%s DAZZLING_GLEAM->%s")
      :format(tostring(game.data.moves.METAL_CLAW.anim),
              tostring(game.data.moves.DAZZLING_GLEAM.anim)))
  end

  -- Fairy must be offensively real: the moves exist AND someone learns them,
  -- sorted by level so the engine's walk finds them.
  do
    local FL = dofile("data/fairy_learnsets.lua")
    local checked, bad = 0, 0
    for id, rows in pairs(FL) do
      local def = game.data.pokemon and game.data.pokemon[id]
      if def and type(def.learnset) == "table" then
        for _, row in ipairs(rows) do
          checked = checked + 1
          local found = false
          for _, e in ipairs(def.learnset) do
            if e.move == row[2] and e.level == row[1] then found = true end
          end
          if not found then
            print(("  FAIL: %s never learns %s at %d")
              :format(id, row[2], row[1]))
            bad = bad + 1
          end
        end
        local prev = 0
        for _, e in ipairs(def.learnset) do
          if e.level < prev then
            print("  FAIL: " .. id .. " learnset not sorted by level")
            bad = bad + 1
            break
          end
          prev = e.level
        end
      end
    end
    print(("  fairy level-up moves %d taught (%d bad)"):format(checked, bad))
    if bad > 0 then fail2 = fail2 + 1 end
  end

  -- the diagnostics report must exist and carry the real numbers
  if not writtenReport then
    print("  FAIL: no diagnostics report was written")
    fail2 = fail2 + 1
  else
    for _, want in ipairs({ "dex_expansion diagnostics",
                            "species registered      498",
                            "slots added this pass",
                            "SAMPLE TABLES", "ROUTE_1.grass" }) do
      if not writtenReport:find(want, 1, true) then
        print(("  FAIL: report missing %q"):format(want))
        fail2 = fail2 + 1
      end
    end
    local f = io.open("/tmp/report_sample.txt", "w")
    if f then f:write(writtenReport); f:close() end
  end
  print(fail2 == 0 and "GAME.READY: PASS" or "GAME.READY: FAIL")
  if fail2 > 0 then fail = true end
end

-- ------------------------------------------------------------------------
-- The three new types, and the dummy that demonstrates them.
--
-- This exists because registering STEEL/DARK/FAIRY was NOT enough and the gap
-- was invisible: build_species_data.py mapped types through pokered's
-- constants, which hold only Gen 1's fifteen, so every new-type slot was
-- dropped.  Aron read as pure ROCK, Umbreon and Togepi as NORMAL, and no
-- species anywhere carried one of the three.  Types were registered, matchups
-- were registered, and nothing used them.
do
  local r = run("modern")
  assert(r, "modern load failed")
  local fail3 = 0

  -- Species must carry the new types, and each type must have a damaging
  -- move that something actually learns -- a type nothing can attack with is
  -- only half a type.
  local want = {
    ARON = "STEEL", HOUNDOUR = "DARK", TOGEPI = "FAIRY",
    SCIZOR = "STEEL", UMBREON = "DARK", GARDEVOIR = "FAIRY",
  }
  for id, wantType in pairs(want) do
    local rec = r.pokemon[id]
    if not rec then
      print("  FAIL: " .. id .. " not registered")
      fail3 = fail3 + 1
    else
      local hasType = false
      for _, t in ipairs(rec.types) do
        if t == wantType then hasType = true end
      end
      if not hasType then
        print(("  FAIL: %s is %s, expected %s"):format(
          id, table.concat(rec.types, "/"), wantType))
        fail3 = fail3 + 1
      end
    end
  end

  -- one damaging move per new type, and someone who learns it
  for _, row in ipairs({ { "STEEL", "METAL_CLAW" }, { "DARK", "CRUNCH" },
                         { "FAIRY", "DAZZLING_GLEAM" } }) do
    local mv = r.moveDefs[row[2]]
    if not (mv and (mv.power or 0) > 0 and mv.type == row[1]) then
      print(("  FAIL: %s is not a damaging %s move"):format(row[2], row[1]))
      fail3 = fail3 + 1
    end
    local learners = 0
    for _, rec in pairs(r.pokemon) do
      for _, e in ipairs(rec.learnset or {}) do
        if e.move == row[2] then learners = learners + 1 end
      end
      for _, m in ipairs(rec.level1Moves or {}) do
        if m == row[2] then learners = learners + 1 end
      end
    end
    if learners == 0 then
      -- KNOWN BLOCKER: build_species_data.py maps learnset moves through
      -- pokered's constants, so every non-Gen-1 move was dropped from every
      -- learnset.  All 276 added moves are registered and nothing learns one.
      -- data/fairy_learnsets.lua patches 42 entries back for Fairy; Steel and
      -- Dark have none at all.  Needs the 4252 missing level-up entries.
      print(("  FAIL: nothing learns %s (known: added moves are registered "
        .. "but absent from every learnset)"):format(row[2]))
      fail3 = fail3 + 1
    end
  end

  -- and the matchups those types need in order to mean anything
  for _, row in ipairs({ { "FAIRY>DRAGON", 20 }, { "DARK>PSYCHIC_TYPE", 20 },
                         { "STEEL>FAIRY", 20 }, { "PSYCHIC_TYPE>DARK", 0 },
                         { "DRAGON>FAIRY", 0 } }) do
    local got = r.typechart and r.typechart[row[1]]
    local mult = got and got.multiplier
    if mult ~= row[2] then
      print(("  FAIL: matchup %s is %s, expected %d")
        :format(row[1], tostring(mult), row[2]))
      fail3 = fail3 + 1
    end
  end

  print(fail3 == 0 and "NEW TYPES: PASS" or "NEW TYPES: FAIL")
  if fail3 > 0 then fail = true end
end

-- ------------------------------------------------------------------------
-- Trainer modernization.
--
-- The generic pass only ever replaces a REPEAT, which is what makes it safe to
-- automate: a trainer's first of each species is never touched, so every roster
-- still reads as the same trainer.  These assert that, plus the three things
-- that would be actively bad -- a duplicate surviving, Shedinja on a team, or
-- a leader roster that failed to apply.
do
  local T = dofile("src/trainers.lua")
  local OV = dofile("data/trainer_overrides.lua")
  local sp = dofile("data/species.lua")
  local MT = dofile("data/modern_types.lua")
  local pokemon = {}
  for _, r in ipairs(sp.SPECIES) do
    local types = r.types
    local m = MT[r.id]
    if m then
      types = {}
      for t in m:gmatch("[A-Z_]+") do types[#types + 1] = t end
    end
    pokemon[r.id] = { types = types, baseStats = r.baseStats,
                      dexExpansion = r.dexExpansion }
  end
  -- stand-ins for the vanilla mons the rosters name
  local function V(id, types)
    pokemon[id] = { types = types,
      baseStats = { hp = 60, attack = 60, defense = 60, speed = 60,
                    special = 60 } }
  end
  V("WEEDLE", { "BUG", "POISON" })
  V("PIDGEY", { "NORMAL", "FLYING" })
  for id in pairs({ GEODUDE = 1, ONIX = 1, STARYU = 1, STARMIE = 1,
    VOLTORB = 1, PIKACHU = 1, RAICHU = 1, TANGELA = 1, VICTREEBEL = 1,
    VILEPLUME = 1, MUK = 1, WEEZING = 1, RAPIDASH = 1, ARCANINE = 1,
    MR_MIME = 1, ALAKAZAM = 1, RHYHORN = 1, NIDORINO = 1, NIDOQUEEN = 1,
    NIDOKING = 1, RHYDON = 1, DUGTRIO = 1, CLOYSTER = 1, DEWGONG = 1,
    JYNX = 1, LAPRAS = 1, HITMONCHAN = 1, HITMONLEE = 1, MACHAMP = 1,
    HAUNTER = 1, GENGAR = 1, GYARADOS = 1, AERODACTYL = 1,
    DRAGONITE = 1 }) do
    V(id, { "NORMAL" })
  end

  local trainers = {
    OPP_BUG_CATCHER = { parties = { {
      { level = 9, species = "WEEDLE" }, { level = 9, species = "WEEDLE" },
      { level = 9, species = "WEEDLE" } } } },
    OPP_BIRD_KEEPER = { parties = { {
      { level = 29, species = "PIDGEY" },
      { level = 29, species = "PIDGEY" } } } },
  }
  for id, parties in pairs(OV) do
    trainers[id] = { parties = {} }
    for i = 1, #parties do
      trainers[id].parties[i] = { { level = 5, species = "PIDGEY" } }
    end
  end

  local quiet = { log = { info = function() end, warn = function() end } }
  local st = T.apply(quiet, pokemon, trainers, OV)
  local fail4 = 0

  if st.overridden ~= 14 then
    print(("  FAIL: %d parties overridden, expected 14"):format(st.overridden))
    fail4 = fail4 + 1
  end
  if st.deduped ~= 3 then
    print(("  FAIL: %d duplicates replaced, expected 3"):format(st.deduped))
    fail4 = fail4 + 1
  end

  for id, def in pairs(trainers) do
    for i, party in ipairs(def.parties) do
      local seen = {}
      for _, mon in ipairs(party) do
        if mon.species == "SHEDINJA" then
          print("  FAIL: SHEDINJA on " .. id)
          fail4 = fail4 + 1
        end
        if seen[mon.species] then
          print(("  FAIL: duplicate %s on %s party %d")
            :format(mon.species, id, i))
          fail4 = fail4 + 1
        end
        seen[mon.species] = true
        local ext = pokemon[mon.species] and pokemon[mon.species].dexExpansion
        if ext and ext.legendary then
          print("  FAIL: legendary " .. mon.species .. " on " .. id)
          fail4 = fail4 + 1
        end
      end
      if #party == 0 then
        print("  FAIL: empty party on " .. id .. " -- battle would soft-lock")
        fail4 = fail4 + 1
      end
    end
  end

  -- the replacements must share a DISTINGUISHING type, not just NORMAL
  local bird = trainers.OPP_BIRD_KEEPER.parties[1][2].species
  local flying = false
  for _, t in ipairs(pokemon[bird].types) do
    if t == "FLYING" then flying = true end
  end
  if not flying then
    print("  FAIL: Bird Keeper's duplicate became " .. bird .. ", not Flying")
    fail4 = fail4 + 1
  end
  local bug = trainers.OPP_BUG_CATCHER.parties[1][2].species
  local isBug = false
  for _, t in ipairs(pokemon[bug].types) do
    if t == "BUG" or t == "POISON" then isBug = true end
  end
  if not isBug then
    print("  FAIL: Bug Catcher's duplicate became " .. bug)
    fail4 = fail4 + 1
  end

  print(("  bug catcher -> WEEDLE, %s, %s"):format(bug,
    trainers.OPP_BUG_CATCHER.parties[1][3].species))
  print(("  bird keeper -> PIDGEY, %s"):format(bird))
  print(("  agatha      -> %s"):format((function()
    local n = {}
    for _, m in ipairs(trainers.OPP_AGATHA.parties[1]) do
      n[#n + 1] = m.species
    end
    return table.concat(n, " ")
  end)()))
  print(fail4 == 0 and "TRAINERS: PASS" or "TRAINERS: FAIL")
  if fail4 > 0 then fail = true end
end



-- ------------------------------------------------------------------------
-- KEP compatibility.
--
-- KEP registers 20 species we also register, and `pokemon` is a record
-- registry whose register() errors on a duplicate.  KEP loads after us and
-- does not pcall, so if we go first on those ids its whole mod fails to load.
-- These assert that we stand down, stay out of its encounter tables, and
-- renumber clear of its dex.
do
  local Kep = dofile("src/kep_compat.lua")
  local shared = Kep.sharedSet()
  local nShared = 0
  for _ in pairs(shared) do nShared = nShared + 1 end
  local fail5 = 0
  if nShared ~= 20 then
    print(("  FAIL: %d shared species, expected 20"):format(nShared))
    fail5 = fail5 + 1
  end

  kepInstalled = true
  local r = run("modern")
  kepInstalled = false
  assert(r, "modern load with KEP failed")

  -- the shared ids must NOT be registered by us
  for id in pairs(shared) do
    if r.pokemon[id] and r.pokemon[id].dexExpansion then
      print("  FAIL: registered " .. id .. " despite KEP providing it")
      fail5 = fail5 + 1
    end
    if r.cries[id] then
      print("  FAIL: registered a cry for " .. id)
      fail5 = fail5 + 1
    end
  end

  -- ...and everything else still must be
  local registered = 0
  for _, def in pairs(r.pokemon) do
    if def.dexExpansion then registered = registered + 1 end
  end
  if registered ~= 498 - 20 then
    print(("  FAIL: registered %d species, expected %d")
      :format(registered, 498 - 20))
    fail5 = fail5 + 1
  end

  -- Placement must still run under KEP.  Disabling it would leave 478 species
  -- uncatchable, which is a worse outcome than sharing a route with KEP's own
  -- picks -- we append, we do not replace.
  local encTables = 0
  for _ in pairs(r.encounters or {}) do encTables = encTables + 1 end
  if encTables == 0 then
    print("  FAIL: no placement under KEP; 478 species would be uncatchable")
    fail5 = fail5 + 1
  end
  -- and the rows we place may name a yielded species, which is fine: KEP
  -- registers those, so the reference still resolves
  local placed, yieldedRefs = 0, 0
  for _, def in pairs(r.encounters or {}) do
    for _, kind in ipairs({ "grass", "water" }) do
      local t = def[kind]
      local rows = t and t.slots
      if type(rows) == "table" then
        local list = rows.__append or rows
        for _, row in ipairs(list) do
          placed = placed + 1
          if shared[row.species] then yieldedRefs = yieldedRefs + 1 end
        end
      end
    end
  end
  if placed == 0 then
    print("  FAIL: placement wrote tables but no rows")
    fail5 = fail5 + 1
  end

  -- renumbering: KEP's highest is 251, so ours must start at 252 and no dex
  -- number may be claimed twice
  local pokemon = {}
  for _, rec in ipairs(dofile("data/species.lua").SPECIES) do
    if not shared[rec.id] then
      pokemon[rec.id] = { dex = rec.dex }
    end
  end
  local ours = {}
  for id in pairs(pokemon) do ours[id] = true end
  pokemon.KEP_TOP = { dex = 251 }      -- stand-in for KEP's roster
  pokemon.KEP_LOW = { dex = 152 }
  local shifted, offset, foreignMax = Kep.renumber(pokemon, ours, 152)
  if foreignMax ~= 251 or offset ~= 100 then
    print(("  FAIL: offset %d against foreign max %d, expected 100/251")
      :format(offset, foreignMax))
    fail5 = fail5 + 1
  end
  local byDex, clashes, lowest = {}, 0, math.huge
  for id, def in pairs(pokemon) do
    if byDex[def.dex] then clashes = clashes + 1 end
    byDex[def.dex] = id
    if ours[id] and def.dex < lowest then lowest = def.dex end
  end
  if clashes > 0 then
    print(("  FAIL: %d dex numbers claimed twice after renumbering")
      :format(clashes))
    fail5 = fail5 + 1
  end
  if lowest ~= 252 then
    print(("  FAIL: our lowest dex is %d, expected 252"):format(lowest))
    fail5 = fail5 + 1
  end

  -- and renumbering must be a no-op when KEP is absent
  local solo = {}
  for id, def in pairs(pokemon) do solo[id] = { dex = def.dex } end
  solo.KEP_TOP, solo.KEP_LOW = nil, nil
  local s2, o2 = Kep.renumber(solo, ours, 252)
  if s2 ~= 0 or o2 ~= 0 then
    print("  FAIL: renumbered with nothing foreign in range")
    fail5 = fail5 + 1
  end

  print(("  KEP: %d yielded, %d registered, %d tables / %d rows placed "
    .. "(%d name a yielded species), dex +%d"):format(
    nShared, registered, encTables, placed, yieldedRefs, offset))
  print(fail5 == 0 and "KEP COMPAT: PASS" or "KEP COMPAT: FAIL")
  if fail5 > 0 then fail = true end
end

os.exit(fail and 1 or 0)