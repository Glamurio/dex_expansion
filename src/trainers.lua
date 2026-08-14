-- Trainer modernization.
--
-- TWO SEPARATE JOBS, deliberately.
--
-- 1. Gym leaders and the Elite Four get HAND-AUTHORED rosters
--    (data/trainer_overrides.lua).  A leader's team is designed -- which mon
--    leads, which one is the wall, what the ace is -- and no heuristic should
--    be inventing that.
--
-- 2. Every other trainer gets a GENERIC pass: any species appearing more than
--    once in a party has the duplicate replaced by a same-type, similar-power
--    species.  That is the whole idea -- a Bug Catcher with two Weedle becomes
--    a Bug Catcher with a Weedle and something else Bug -- and it is a
--    mechanical enough rule to trust to code, because it only ever replaces a
--    REPEAT.  A trainer's first of each species is never touched, so Kanto's
--    identity survives and every roster still reads as the same trainer.
--
-- Runs at game.ready against live Data rather than through the `trainers`
-- registry, because `parties` is f.list(f.list(...)) and arrays REPLACE
-- wholesale on a record patch -- touching one species would mean restating
-- every roster in the game.

local Trainers = {}

-- Never handed out by a trainer:
--   SHEDINJA  1 HP.  Any trainer holding it is holding a free KO, and it also
--             makes the AI look broken.  Excluded by request.
--   legendaries  a static legendary is a designed encounter; handing them to
--             a Bug Catcher devalues the ones the player hunts for.
Trainers.EXCLUDED = { SHEDINJA = true }

-- Gen 1 has one Special stat where later games have two, so counting it twice
-- is the fair way to line a vanilla mon up against one of ours: same formula
-- for both, from the five stats the engine actually stores.
local function power(def)
  local s = def and def.baseStats
  if type(s) ~= "table" then return 0 end
  return (s.hp or 0) + (s.attack or 0) + (s.defense or 0) + (s.speed or 0)
    + 2 * (s.special or 0)
end

-- Deterministic, so a given trainer always gets the same replacement: a team
-- that reshuffles between boots would make the game feel unstable and would
-- make bug reports useless.  Pure arithmetic -- LuaJIT is Lua 5.1 syntax and
-- has no bitwise operators.
local function hash32(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + str:byte(i)) % 2147483648
  end
  return h
end

-- Candidates that share a type with `def` and sit closest to it in power.
local function candidatesFor(pokemon, def, exclude)
  local wanted = {}
  for _, t in ipairs((def and def.types) or {}) do wanted[t] = true end
  local target = power(def)
  local out = {}
  for id, cand in pairs(pokemon) do
    if not Trainers.EXCLUDED[id] and not exclude[id]
        and type(cand) == "table" and type(cand.types) == "table" then
      local ext = cand.dexExpansion
      -- only OUR species are candidates: swapping a vanilla mon for another
      -- vanilla mon would not modernize anything
      local legendary = ext and ext.legendary
      if ext and not legendary then
        -- Count shared types, but rank a NORMAL-only match LAST.
        --
        -- Sharing NORMAL is technically a match and thematically useless: it
        -- let a Bird Keeper's third Pidgey become Whismur, because Pidgey is
        -- NORMAL/FLYING and Whismur is NORMAL.  The distinguishing type is the
        -- one that makes the trainer a Bird Keeper, so matches on it win.
        local shares, specific = false, 0
        for _, t in ipairs(cand.types) do
          if wanted[t] then
            shares = true
            if t ~= "NORMAL" then specific = specific + 1 end
          end
        end
        if shares then
          out[#out + 1] = { id = id, gap = math.abs(power(cand) - target),
                            spec = specific }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    -- most distinguishing types shared first, then closest in power
    if a.spec ~= b.spec then return a.spec > b.spec end
    if a.gap ~= b.gap then return a.gap < b.gap end
    return a.id < b.id -- stable regardless of pairs() order
  end)
  -- If any candidate matched on something other than NORMAL, drop the
  -- NORMAL-only ones entirely rather than leaving them in the random pick.
  if out[1] and out[1].spec > 0 then
    local kept = {}
    for _, c in ipairs(out) do
      if c.spec > 0 then kept[#kept + 1] = c end
    end
    out = kept
  end
  return out
end

-- Replace repeats in one party.  Returns the number of slots changed.
function Trainers.dedupe(pokemon, trainerId, partyIndex, party)
  local seen, changed = {}, 0
  -- everything already on the team is off-limits as a replacement, so we never
  -- trade one duplicate for another
  local onTeam = {}
  for _, mon in ipairs(party) do
    if mon.species then onTeam[mon.species] = true end
  end
  for slot, mon in ipairs(party) do
    local id = mon.species
    if id then
      if seen[id] then
        local pool = candidatesFor(pokemon, pokemon[id], onTeam)
        if #pool > 0 then
          -- pick from the closest few rather than always the single closest,
          -- so two Bug Catchers with two Weedle each do not both end up with
          -- the identical replacement
          local top = math.min(6, #pool)
          local pick = pool[(hash32(trainerId .. ":" .. partyIndex .. ":"
            .. slot) % top) + 1]
          mon.species = pick.id
          onTeam[pick.id] = true
          changed = changed + 1
        end
      else
        seen[id] = true
      end
    end
  end
  return changed
end

-- `overrides` is data/trainer_overrides.lua.
function Trainers.apply(mod, pokemon, trainers, overrides)
  local stats = { overridden = 0, deduped = 0, parties = 0, missing = {} }
  if type(trainers) ~= "table" or type(pokemon) ~= "table" then
    return stats
  end

  for id, def in pairs(trainers) do
    if type(def) == "table" and type(def.parties) == "table" then
      local override = overrides and overrides[id]
      for partyIndex, party in ipairs(def.parties) do
        stats.parties = stats.parties + 1
        local wanted = override and override[partyIndex]
        if wanted then
          -- rebuild the party in place: the table is the one the battle reads,
          -- so replacing the reference would be a no-op from its point of view
          for i = #party, 1, -1 do party[i] = nil end
          local ok = true
          for _, row in ipairs(wanted) do
            if not pokemon[row[2]] then
              ok = false
              stats.missing[row[2]] = true
            end
          end
          if ok then
            for i, row in ipairs(wanted) do
              party[i] = { level = row[1], species = row[2] }
            end
            stats.overridden = stats.overridden + 1
          else
            -- a missing species would leave an empty party and a soft-locked
            -- battle, so keep whatever DOES resolve rather than nothing
            for i, row in ipairs(wanted) do
              if pokemon[row[2]] then
                party[i] = { level = row[1], species = row[2] }
              end
            end
          end
        else
          stats.deduped = stats.deduped
            + Trainers.dedupe(pokemon, tostring(id), partyIndex, party)
        end
      end
    end
  end

  local missing = {}
  for id in pairs(stats.missing) do missing[#missing + 1] = id end
  if #missing > 0 then
    table.sort(missing)
    mod.log:warn("trainer overrides reference unknown species: %s",
      table.concat(missing, " "))
  end
  mod.log:info("trainers: %d parties overridden, %d duplicate slots replaced "
    .. "across %d parties", stats.overridden, stats.deduped, stats.parties)
  return stats
end

return Trainers
