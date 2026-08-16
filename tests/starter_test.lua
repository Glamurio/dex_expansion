-- Starter selection checks.
--
-- The failure mode here is a soft-locked intro: a ball you can talk to that
-- never gives a Pokemon, or gives one without setting the flags Oak's own
-- script advances off. So this asserts on the actual script rows rather than
-- just on the species table.

package.path = "./?.lua;" .. package.path
local Starters = dofile("src/starters.lua")
local species = dofile("data/species.lua")

local known = {}
for _, r in ipairs(species.SPECIES) do known[r.id] = true end
-- the vanilla 151 are in the engine's dataset, not ours
for _, id in ipairs({ "CHARMANDER", "SQUIRTLE", "BULBASAUR" }) do
  known[id] = true
end

local fail = 0
local function check(cond, msg)
  if not cond then
    print("  FAIL: " .. msg)
    fail = fail + 1
  end
end

-- 1. every trio names species that actually exist
for mode, trio in pairs(Starters.TRIOS) do
  for slot, id in pairs(trio) do
    check(known[id], ("%s %s names unknown species %s"):format(mode, slot, id))
  end
end
print("trios reference known species")

-- 2. the random pool is fully registered too
for slot, pool in pairs(Starters.RANDOM_POOL) do
  for _, id in ipairs(pool) do
    check(known[id], ("random pool %s has unknown %s"):format(slot, id))
  end
end
print("random pool references known species")

-- 3. resolve() is deterministic per seed and varies across seeds
local a1 = Starters.resolve("random", "seed-one", nil)
local a2 = Starters.resolve("random", "seed-one", nil)
local b = Starters.resolve("random", "seed-two", nil)
for _, slot in ipairs({ "LEFT", "MIDDLE", "RIGHT" }) do
  check(a1[slot] == a2[slot], "resolve not deterministic for " .. slot)
end
check(a1.LEFT ~= b.LEFT or a1.MIDDLE ~= b.MIDDLE or a1.RIGHT ~= b.RIGHT,
  "different seeds produced an identical trio")
print("random trio deterministic per seed: " ..
  a1.LEFT .. "/" .. a1.MIDDLE .. "/" .. a1.RIGHT ..
  "  vs  " .. b.LEFT .. "/" .. b.MIDDLE .. "/" .. b.RIGHT)

-- 4. resolve() respects the dataset filter
local filtered = Starters.resolve("random", "seed-one", { CHARMANDER = true,
  SQUIRTLE = true, BULBASAUR = true })
for _, slot in ipairs({ "LEFT", "MIDDLE", "RIGHT" }) do
  check(filtered[slot] == Starters.TRIOS.kanto[slot],
    "dataset filter ignored for " .. slot)
end
print("unregistered species are never offered")

-- 5. script rows carry every step the intro depends on
for mode in pairs(Starters.TRIOS) do
  local chosen = Starters.resolve(mode, "", nil)
  for slot, slotDef in pairs(Starters.SLOTS) do
    local rows = Starters.rows(slotDef, chosen)
    local seen, gave = {}, nil
    for _, row in ipairs(rows) do
      seen[row[1]] = true
      if row[1] == "give_pokemon" then gave = row end
      if row[1] == "set_flag" then seen["flag:" .. tostring(row[2])] = true end
    end
    local what = mode .. "/" .. slot
    check(seen.give_pokemone == nil, what .. " typo guard")
    check(gave ~= nil, what .. " never calls give_pokemon")
    check(gave and gave[2] == chosen[slot],
      what .. " gives the wrong species")
    check(gave and gave[3] == 5, what .. " wrong level")
    check(seen["flag:EVENT_GOT_STARTER"],
      what .. " does not set EVENT_GOT_STARTER -- intro would soft-lock")
    check(seen["flag:" .. slotDef.choseFlag],
      what .. " does not set " .. slotDef.choseFlag)
    check(seen.hide_object, what .. " never hides a ball")
    check(seen.ask, what .. " never asks for confirmation")
    check(seen.label, what .. " has no jump labels")
  end
end
print("script rows complete for every trio and slot")

-- 6. the rival always takes a different species from a different slot
for mode in pairs(Starters.TRIOS) do
  local chosen = Starters.resolve(mode, "", nil)
  for slot, slotDef in pairs(Starters.SLOTS) do
    check(slotDef.rivalSlot ~= slot, slot .. " rival slot points at itself")
    check(chosen[slotDef.rivalSlot] ~= chosen[slot],
      mode .. "/" .. slot .. " rival takes the same species as the player")
  end
end
print("rival counter-pick chain intact")

-- 7. apply() yields when the randomizer is present
local yielded = true
local fakeMod = {
  find = function() return { exports = {} } end,
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k)
    if k == "starters" then return "johto" end
    return ""
  end },
  events = { on = function() end },
  content = { map_scripts = { register = function()
    yielded = false
  end } },
}
Starters.apply(fakeMod)
check(yielded, "apply() registered OAKS_LAB despite the randomizer being present")
print("yields to pokemon_randomizer")

-- 8. The option is read at TALK time, not captured at boot.
--
-- Changing STARTERS in the options menu and starting a new game used to keep
-- the old trio until the game was rebooted, because apply() captured the value
-- once in the entry chunk.  This asserts the handler sees the CURRENT value,
-- and that the handlers exist even when the setting is VANILLA at boot -- the
-- other half of the same bug, where booting on vanilla registered nothing so a
-- later switch could not apply.
local setting = "vanilla"
local registeredTalk = nil
local liveMod = {
  find = function() return nil end,
  log = { info = function() end, warn = function() end },
  options = { get = function(_, k)
    if k == "starters" then return setting end
    return ""
  end },
  events = { on = function() end },
  content = { map_scripts = { register = function(_, _, value)
    registeredTalk = value.talk
  end } },
}
Starters.apply(liveMod)
check(registeredTalk ~= nil,
  "no handlers registered while the setting was VANILLA")
local seen = 0
for _ in pairs(registeredTalk or {}) do seen = seen + 1 end
check(seen == 3, "expected 3 ball handlers, got " .. seen)

-- drive one handler and read back which species it would give
local function speciesFromHandler(slotKey)
  local got
  local runner = { run = function(_, rows) 
    for _, row in ipairs(rows) do
      if row[1] == "give_pokemon" then got = row[2] end
    end
  end }
  registeredTalk[slotKey](nil, { runner = runner }, nil, nil)
  return got
end
local before = speciesFromHandler("TEXT_OAKSLAB_CHARMANDER_POKE_BALL")
check(before == "CHARMANDER",
  "vanilla setting gave " .. tostring(before) .. ", expected CHARMANDER")
setting = "hoenn"   -- as if the player just changed it in the options menu
local after = speciesFromHandler("TEXT_OAKSLAB_CHARMANDER_POKE_BALL")
check(after == "TORCHIC",
  "after switching to HOENN the ball still gave " .. tostring(after))
print("option read at talk time: " .. tostring(before) .. " -> "
  .. tostring(after) .. " with no reload")

print(fail == 0 and "\nSTARTERS: PASS" or "\nSTARTERS: FAIL")
os.exit(fail == 0 and 0 or 1)