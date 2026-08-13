-- Write a diagnostics report to a FILE.
--
-- WHY THIS EXISTS
-- src/core/Logger.lua uses plain `print`, so every log line goes to stdout and
-- nowhere else.  With a fused gen1recomp.exe on Windows there is no console
-- attached, so those lines are simply lost -- which left wild encounters being
-- debugged by guesswork across several rounds.
--
-- love.filesystem.write lands in the LOVE save directory, the same place the
-- engine writes its own pending-update marker (src/update/Boot.lua), so this
-- needs no permissions and no console:
--
--   Windows  %APPDATA%\LOVE\pokemon-love2d\dex_expansion_report.txt
--   macOS    ~/Library/Application Support/LOVE/pokemon-love2d/
--   Linux    ~/.local/share/love/pokemon-love2d/
--
-- The report is rewritten (not appended) on every game.ready, so it always
-- describes the current boot rather than growing forever.

local Diagnostics = {}

Diagnostics.FILE = "dex_expansion_report.txt"

-- Maps worth dumping in full: the early routes are where a placement failure
-- is noticed first, and one cave/water table each proves the other terrains.
local SAMPLE_MAPS = {
  "ROUTE_1", "ROUTE_2", "ROUTE_22", "VIRIDIAN_FOREST",
  "MT_MOON_1F", "ROUTE_21",
}

local function line(out, fmt, ...)
  out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
end

-- `encounters` is the live Data.encounters table.
function Diagnostics.build(info, encounters, placement)
  local out = {}
  line(out, "dex_expansion diagnostics")
  line(out, "=========================")
  line(out, "written at boot; rewritten every game.ready")
  line(out, "")
  line(out, "species registered      %s", tostring(info.species))
  line(out, "species skipped         %s", tostring(info.skipped))
  line(out, "moves registered        %s", tostring(info.moves))
  line(out, "types / matchups        %s / %s", tostring(info.types),
    tostring(info.matchups))
  line(out, "dex entry texts         %s", tostring(info.texts))
  line(out, "party icons             %s", tostring(info.icons))
  line(out, "dex_entries.lua present %s", tostring(info.dexEntriesFile))
  line(out, "")
  line(out, "OPTIONS")
  line(out, "  wild placement        %s", tostring(info.encounterMode))
  line(out, "  species in wild       %s", tostring(info.available))
  line(out, "  moves & types         %s", tostring(info.moveMode))
  line(out, "  starters              %s", tostring(info.starterMode))
  line(out, "  yield to other mods   %s", tostring(info.respect))
  line(out, "")
  line(out, "WILD PLACEMENT")
  line(out, "  rows in placement data  %s", tostring(info.placementRows))
  line(out, "  maps in placement data  %s", tostring(info.placementMaps))
  line(out, "  registry patch reported %s", tostring(info.registryPlaced))
  -- "this pass" matters: the pass is idempotent, so a second run legitimately
  -- adds 0.  The live table dump below is the real evidence.
  line(out, "  slots added this pass   %s", tostring(info.addedLive))
  line(out, "  bucket tables widened   %s", tostring(info.widened))
  line(out, "  maps yielded to others  %s", tostring(info.yielded or 0))
  line(out, "")

  if type(encounters) ~= "table" then
    line(out, "  !! Data.encounters is not a table -- nothing could be applied")
    return table.concat(out, "\n") .. "\n"
  end

  local totalMaps, widenedMaps = 0, 0
  for _, def in pairs(encounters) do
    if type(def) == "table" then
      for _, kind in ipairs({ "grass", "water" }) do
        local t = def[kind]
        if type(t) == "table" and type(t.slots) == "table" then
          totalMaps = totalMaps + 1
          if #t.slots > 10 then widenedMaps = widenedMaps + 1 end
        end
      end
    end
  end
  line(out, "  live tables total       %d", totalMaps)
  line(out, "  live tables over 10 slots %d", widenedMaps)
  line(out, "")
  line(out, "SAMPLE TABLES (as the game will roll them)")
  for _, mapId in ipairs(SAMPLE_MAPS) do
    local def = encounters[mapId]
    if not def then
      line(out, "  %-16s (no encounter table)", mapId)
    else
      for _, kind in ipairs({ "grass", "water" }) do
        local t = def[kind]
        if type(t) == "table" and type(t.slots) == "table" then
          line(out, "  %s.%s  rate=%s  slots=%d  buckets=%s", mapId, kind,
            tostring(t.rate), #t.slots,
            t.buckets and tostring(#t.buckets) or "global")
          for i, slot in ipairs(t.slots) do
            local threshold = t.buckets and t.buckets[i]
            line(out, "      %2d  %-14s lv%-3s %s", i,
              tostring(slot.species), tostring(slot.level),
              threshold and ("<" .. threshold) or "")
          end
        end
      end
    end
  end
  line(out, "")
  line(out, "PLACEMENT DATA FOR THOSE MAPS (what we tried to add)")
  for _, mapId in ipairs(SAMPLE_MAPS) do
    local kinds = placement and placement[mapId]
    if kinds then
      for kind, rows in pairs(kinds) do
        local names = {}
        for _, row in ipairs(rows) do
          names[#names + 1] = tostring(row.species) .. "/" .. tostring(row.level)
        end
        line(out, "  %s.%s  %s", mapId, kind, table.concat(names, " "))
      end
    else
      line(out, "  %-16s (nothing planned)", mapId)
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- Returns (ok, pathOrError).  Never throws: a diagnostics writer that takes
-- the mod down would be worse than no diagnostics at all.
function Diagnostics.write(mod, info, encounters, placement)
  local ok, body = pcall(Diagnostics.build, info, encounters, placement)
  if not ok then return false, tostring(body) end
  if not (love and love.filesystem and love.filesystem.write) then
    return false, "love.filesystem unavailable"
  end
  local wrote, err = pcall(love.filesystem.write, Diagnostics.FILE, body)
  if not wrote then return false, tostring(err) end
  local dir = love.filesystem.getSaveDirectory
    and love.filesystem.getSaveDirectory() or "?"
  return true, dir .. "/" .. Diagnostics.FILE
end

return Diagnostics
