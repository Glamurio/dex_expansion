-- Starter selection for Dex Expansion.
--
-- Replaces the three starter ball talk handlers in Oak's Lab so the trio can
-- come from any generation up to 5.  `map_scripts` is a compose registry
-- (src/mods/Schemas.lua R.map_scripts), so this contributes only the three
-- talk keys and the rest of Oak's Lab stays engine-owned.
--
-- Slots keep their vanilla types: left is fire, middle is water, right is
-- grass, exactly as Charmander / Squirtle / Bulbasaur are.  Every trio in
-- every generation has that shape, so the rival's "takes the one that beats
-- yours" chain keeps working with no extra wiring -- rivalBall stays the
-- vanilla neighbour and only the species behind each ball changes.
--
-- The script rows mirror the vanilla ball sequence: the got-starter and
-- followed-Oak guards, the dex entry popup, the yes/no ask, give_pokemon,
-- EVENT_GOT_STARTER plus the per-ball chose flag, hiding your ball, walking
-- the rival to the ball he takes, then hiding his.  Skipping any of the flag
-- writes soft-locks the intro, because Oak's own script advances off them.

local Starters = {}

-- LEFT = fire, MIDDLE = water, RIGHT = grass.
Starters.TRIOS = {
  kanto  = { LEFT = "CHARMANDER", MIDDLE = "SQUIRTLE",  RIGHT = "BULBASAUR" },
  johto  = { LEFT = "CYNDAQUIL",  MIDDLE = "TOTODILE",  RIGHT = "CHIKORITA" },
  hoenn  = { LEFT = "TORCHIC",    MIDDLE = "MUDKIP",    RIGHT = "TREECKO" },
  sinnoh = { LEFT = "CHIMCHAR",   MIDDLE = "PIPLUP",    RIGHT = "TURTWIG" },
  unova  = { LEFT = "TEPIG",      MIDDLE = "OSHAWOTT",  RIGHT = "SNIVY" },
}

Starters.RANDOM_POOL = {
  LEFT = { "CHARMANDER", "CYNDAQUIL", "TORCHIC", "CHIMCHAR", "TEPIG" },
  MIDDLE = { "SQUIRTLE", "TOTODILE", "MUDKIP", "PIPLUP", "OSHAWOTT" },
  RIGHT = { "BULBASAUR", "CHIKORITA", "TREECKO", "TURTWIG", "SNIVY" },
}

-- Vanilla ball wiring.  These ids are fixed by the extracted Oak's Lab map;
-- only `species` is ours to change.
local SLOTS = {
  LEFT = {
    slot = "LEFT",
    talkKey = "TEXT_OAKSLAB_CHARMANDER_POKE_BALL",
    askText = "_OaksLabYouWantCharmanderText",
    choseFlag = "EVENT_CHOSE_CHARMANDER",
    ballObject = "OAKSLAB_CHARMANDER_POKE_BALL",
    rivalBall = "OAKSLAB_SQUIRTLE_POKE_BALL",
    rivalSlot = "MIDDLE",
  },
  MIDDLE = {
    slot = "MIDDLE",
    talkKey = "TEXT_OAKSLAB_SQUIRTLE_POKE_BALL",
    askText = "_OaksLabYouWantSquirtleText",
    choseFlag = "EVENT_CHOSE_SQUIRTLE",
    ballObject = "OAKSLAB_SQUIRTLE_POKE_BALL",
    rivalBall = "OAKSLAB_BULBASAUR_POKE_BALL",
    rivalSlot = "RIGHT",
  },
  RIGHT = {
    slot = "RIGHT",
    talkKey = "TEXT_OAKSLAB_BULBASAUR_POKE_BALL",
    askText = "_OaksLabYouWantBulbasaurText",
    choseFlag = "EVENT_CHOSE_BULBASAUR",
    ballObject = "OAKSLAB_BULBASAUR_POKE_BALL",
    rivalBall = "OAKSLAB_CHARMANDER_POKE_BALL",
    rivalSlot = "LEFT",
  },
}

-- Where the rival walks to before taking his ball, by ball object.
local BALL_X = {
  OAKSLAB_CHARMANDER_POKE_BALL = 6,
  OAKSLAB_SQUIRTLE_POKE_BALL = 7,
  OAKSLAB_BULBASAUR_POKE_BALL = 8,
}

local LEVEL = 5

-- Deterministic pick, seeded from the option text, so RANDOM TRIO is stable
-- for a given seed on every machine.  Pure arithmetic: LuaJIT is Lua 5.1
-- syntax and has no bitwise operators.
local function hash32(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + str:byte(i)) % 2147483648
  end
  return h
end

function Starters.resolve(mode, seed, data)
  local trio = Starters.TRIOS[mode]
  if trio then
    local out = {}
    for slot, species in pairs(trio) do out[slot] = species end
    return out
  end
  -- random trio
  local state = (hash32(tostring(seed or "")) % 2147483647) + 1
  local function nextInt(n)
    state = (1103515245 * state + 12345) % 2147483648
    return (state % n) + 1
  end
  local out = {}
  for _, slot in ipairs({ "LEFT", "MIDDLE", "RIGHT" }) do
    local pool = Starters.RANDOM_POOL[slot]
    -- only offer a species the merged dataset actually knows, so a random
    -- pick can never hand out a species that failed to register
    local usable = {}
    for _, id in ipairs(pool) do
      if data == nil or data[id] then usable[#usable + 1] = id end
    end
    if #usable == 0 then usable = { Starters.TRIOS.kanto[slot] } end
    out[slot] = usable[nextInt(#usable)]
  end
  return out
end

-- The vanilla ask lines name a specific species, so they can only be reused
-- when the species behind that ball is unchanged.  Otherwise fall back to a
-- generic line with the name substituted.
local function askFor(slotDef, species)
  if species == Starters.TRIOS.kanto[slotDef.slot] then
    return slotDef.askText, nil
  end
  -- A real newline.  Written "\\n" in Lua source this is a backslash and an
  -- "n" rather than a line break, and the renderer drops the backslash.
  return "So! You want\n{RAM}?", true
end

function Starters.rows(slotDef, chosen)
  local species = chosen[slotDef.slot]
  local rivalSpecies = chosen[slotDef.rivalSlot]
  local askText, generic = askFor(slotDef, species)
  local ask = generic
    and { "ask", askText, { RAM = species } }
    or { "ask", askText }
  return {
    { "check_flag", "EVENT_GOT_STARTER" },
    { "jump_if_true", "blocked" },
    { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
    { "jump_if_false", "blocked" },
    { "push_screen", "DexEntryMenu", { species = species, forceOwned = true } },
    ask,
    { "jump_if_false", "done" },
    { "play_sound", "Get_Key_Item" },
    { "show_text", "_OaksLabReceivedMonText", { RAM = species } },
    { "give_pokemon", species, LEVEL },
    { "set_flag", "EVENT_GOT_STARTER" },
    { "set_flag", slotDef.choseFlag },
    { "hide_object", "OAKS_LAB", slotDef.ballObject },
    { "move_npc_to", 1, BALL_X[slotDef.rivalBall], 4 },
    { "face_object", 1, "up" },
    { "show_text", "_OaksLabRivalIllTakeThisOneText" },
    { "hide_object", "OAKS_LAB", slotDef.rivalBall },
    { "play_sound", "Get_Key_Item" },
    { "show_text", "_OaksLabRivalReceivedMonText", { RAM = rivalSpecies } },
    { "jump", "done" },
    { "label", "blocked" },
    { "show_text", "_OaksLabThoseArePokeBallsText" },
    { "label", "done" },
  }
end

local function handler(slotDef, resolveChosen)
  return function(game, overworld, npc, onDone)
    if type(overworld) ~= "table"
        or type(overworld.runner) ~= "table"
        or type(overworld.runner.run) ~= "function" then
      if onDone then onDone() end
      return
    end
    overworld.runner:run(Starters.rows(slotDef, resolveChosen(game)), {
      npc = npc,
      onDone = onDone,
    })
  end
end

-- ------------------------------------------------------- rival retargeting
-- Setting the chose flag is not enough.  data/scripts/oaks_lab.lua picks the
-- rival's roster with
--     local party = flags.EVENT_CHOSE_BULBASAUR and 3
--                   or flags.EVENT_CHOSE_SQUIRTLE and 2 or 1
--     { "start_battle", "trainer", "OPP_RIVAL1", party }
-- and those parties are vanilla trainer data, so the party index is already
-- right and only the species in it are wrong.
--
-- Substitution runs stage-for-stage along the evolution line, so the later
-- rival battles and the Champion fight stay consistent: Charmander, Charmeleon
-- and Charizard become the fire trio's three stages, and so on.
--
-- Done at game.ready against live Data rather than through the trainers
-- registry, because `parties` is f.list(f.list(...)) and arrays replace
-- wholesale on a record patch -- rewriting one species would mean restating
-- every rival roster, levels included.

local VANILLA_LINES = {
  LEFT = { "CHARMANDER", "CHARMELEON", "CHARIZARD" },
  MIDDLE = { "SQUIRTLE", "WARTORTLE", "BLASTOISE" },
  RIGHT = { "BULBASAUR", "IVYSAUR", "VENUSAUR" },
}

-- Walk `evolutions` to get a species' own line, so a trio member with only
-- two stages (or an odd chain) maps onto whatever it actually has.
function Starters.lineOf(pokemon, id)
  local line, seen = { id }, { [id] = true }
  for _ = 1, 4 do
    local def = pokemon and pokemon[line[#line]]
    local nextId = nil
    for _, evo in ipairs((def and def.evolutions) or {}) do
      if evo.species and not seen[evo.species] then
        nextId = evo.species
        break
      end
    end
    if not nextId then break end
    seen[nextId] = true
    line[#line + 1] = nextId
  end
  return line
end

-- Returns a map of vanilla species id -> replacement id.
function Starters.substitutions(pokemon, chosen)
  local map = {}
  for slot, vanilla in pairs(VANILLA_LINES) do
    local ours = Starters.lineOf(pokemon, chosen[slot])
    for i, vanillaId in ipairs(vanilla) do
      -- clamp to the last stage we have, so a two-stage line still fills the
      -- third slot rather than leaving a vanilla starter behind
      local replacement = ours[math.min(i, #ours)]
      if replacement and replacement ~= vanillaId then
        map[vanillaId] = replacement
      end
    end
  end
  return map
end

-- Rewrite rival rosters in place.  Restricted to classes whose id names the
-- rival: other trainers may legitimately carry a starter line, and silently
-- rewriting those would be a different bug.
function Starters.retargetRivals(mod, currentTrio)
  mod.events:on("game.ready", function(payload)
    -- The payload is { game = <Game> }, not the Game itself; reading
    -- payload.data gives nil and the handler returns without doing anything.
    local game = payload and (payload.game or payload)
    local data = game and game.data
    local trainers = data and data.trainers
    if type(trainers) ~= "table" then return end
    -- resolved here, not at boot: the option may have changed since
    local map = Starters.substitutions(data.pokemon, currentTrio(game))
    if not next(map) then return end
    local swapped = 0
    for id, def in pairs(trainers) do
      if type(id) == "string" and id:find("RIVAL")
          and type(def) == "table" and type(def.parties) == "table" then
        for _, party in ipairs(def.parties) do
          for _, mon in ipairs(party) do
            local to = mon.species and map[mon.species]
            if to then
              mon.species = to
              swapped = swapped + 1
            end
          end
        end
      end
    end
    mod.log:info("retargeted %d rival party slots onto the chosen trio",
      swapped)
  end)
end

-- Install the contribution.  Returns the resolved trio for logging, or nil
-- when the mod deliberately stays out of the way.
function Starters.apply(mod)
  -- The randomizer replaces the same three talk keys at priority 100.  A tie
  -- between two compose contributions on identical keys is not something to
  -- race, so yield to it: its starter randomization is the more specific
  -- feature and the player opted into it.
  local randomizer = mod.find and mod.find("pokemon_randomizer")
  if randomizer then
    mod.log:info("starter selection skipped: pokemon_randomizer is installed "
      .. "and owns the Oak's Lab ball handlers")
    return nil
  end

  -- Options are read at talk time, not captured here.  The entry chunk runs
  -- once at boot, so capturing the value means a change in the options menu
  -- does not apply until the game restarts.
  --
  -- Handlers are registered unconditionally, including on VANILLA.  Registering
  -- only for a non-vanilla trio has the same problem in reverse: booting on
  -- vanilla leaves no handlers, so a later switch cannot apply.  With the Kanto
  -- trio these rows are the vanilla ball script -- same species, same flags,
  -- and askFor() reuses the vanilla ask text -- so owning them always is free.
  local function currentTrio(game)
    local mode = (mod.options and mod.options:get("starters")) or "vanilla"
    local seed = (mod.options and mod.options:get("starterSeed")) or ""
    if mode == "vanilla" then mode = "kanto" end
    local data = type(game) == "table" and type(game.data) == "table"
      and game.data.pokemon or nil
    return Starters.resolve(mode, seed, data)
  end

  local talk = {}
  for _, slot in ipairs({ "LEFT", "MIDDLE", "RIGHT" }) do
    local slotDef = SLOTS[slot]
    talk[slotDef.talkKey] = handler(slotDef, currentTrio)
  end

  local ok, err = pcall(function()
    mod.content.map_scripts:register("OAKS_LAB", {
      priority = 100,
      talk = talk,
    })
  end)
  if not ok then
    mod.log:warn("starter selection not installed: %s", tostring(err))
    return nil
  end

  -- Same reasoning for the rival: resolved at game.ready from the option as it
  -- stands then, so a new game after changing the setting gets a matching
  -- rival without a restart.
  Starters.retargetRivals(mod, currentTrio)

  local preview = currentTrio(nil)
  mod.log:info("starters (at boot): %s / %s / %s",
    preview.LEFT, preview.MIDDLE, preview.RIGHT)
  return preview
end

Starters.SLOTS = SLOTS

return Starters
