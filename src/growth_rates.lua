-- The two experience curves Gen 1 does not ship.
--
-- Gen 1 has MEDIUM_FAST, SLIGHTLY_FAST, SLIGHTLY_SLOW, MEDIUM_SLOW and FAST.
-- Gen 2+ species also use ERRATIC and FLUCTUATING, which is exactly why
-- Sanqui's pokered fork had to add them; here they are ordinary registry
-- records.  R.growth_rates takes `expForLevel = f.fn` and validates that the
-- curve increases, so these are plain functions of level.
local GrowthRates = {}

local function erratic(n)
  if n < 50 then return math.floor(n^3 * (100 - n) / 50) end
  if n < 68 then return math.floor(n^3 * (150 - n) / 100) end
  if n < 98 then return math.floor(n^3 * math.floor((1911 - 10 * n) / 3) / 500) end
  return math.floor(n^3 * (160 - n) / 100)
end

local function fluctuating(n)
  if n < 15 then
    return math.floor(n^3 * (math.floor((n + 1) / 3) + 24) / 50)
  end
  if n < 36 then return math.floor(n^3 * (n + 14) / 50) end
  return math.floor(n^3 * (math.floor(n / 2) + 32) / 50)
end

GrowthRates.CURVES = {
  ERRATIC = erratic,
  FLUCTUATING = fluctuating,
}

return GrowthRates
