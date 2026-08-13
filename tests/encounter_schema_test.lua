-- Prove the encounter payload passes the ENGINE'S OWN validator.
--
-- This gate exists because of a bug that was invisible in-game: every route
-- kept showing only its vanilla encounters and nothing errored. The cause was
-- schema validation silently rejecting the whole patch.
--
-- R.encounters types grass/water as a NESTED f.rec{ rate, slots }, and
-- Schemas.lua says of nested records: "Nested recs stay strict, that is where
-- typos hide". So an extra `buckets` key -- which Encounter.roll DOES honour
-- at runtime -- is an unknown field at register time and kills the patch.
--
--   luajit tests/encounter_schema_test.lua /path/to/gen1recomp

local engine = arg and arg[1]
if not engine or engine == "" then
  print("SKIP: pass the gen1recomp checkout path")
  print("      luajit tests/encounter_schema_test.lua /path/to/gen1recomp")
  os.exit(0)
end
package.path = engine .. "/?.lua;" .. engine .. "/?/init.lua;" .. package.path

local Schemas = require("src.mods.Schemas")
-- Schemas.REGISTRIES is the real spec table.  Schemas.GEN1/GEN2 are ROUTING
-- tables, and passing one of those here makes every check trivially pass --
-- which is how a first attempt at this test "confirmed" nothing at all.
local spec = Schemas.REGISTRIES and Schemas.REGISTRIES.encounters
assert(spec and spec.fields, "could not find the encounters spec")

local fail = 0
local function check(payload, shouldPass, label)
  -- Schemas.check returns (ok, errors); ok is nil on failure
  local ok, errs = Schemas.check(spec, "encounters", "ROUTE_1", payload,
    "patch")
  local passed = ok == true
  local verdict = passed == shouldPass
  print(("  %-46s %s%s"):format(label, verdict and "as expected" or "WRONG",
    (not passed and type(errs) == "table" and errs[1])
      and ("  [" .. tostring(errs[1]) .. "]") or ""))
  if not verdict then fail = fail + 1 end
end

local rows = { { level = 5, species = "CHIKORITA" } }

check({ grass = { slots = { __append = rows } } }, true,
  "append rows, no buckets (what we ship)")
check({ grass = { buckets = { 128, 256 }, slots = { __append = rows } } },
  false, "with buckets (the bug: must be REJECTED)")

print(fail == 0 and "\nENCOUNTER SCHEMA: PASS" or "\nENCOUNTER SCHEMA: FAIL")
os.exit(fail == 0 and 0 or 1)
