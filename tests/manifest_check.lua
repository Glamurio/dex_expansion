-- Validate manifest.json with the ENGINE'S OWN validator.
--
-- Hand-checking a manifest against the docs does not work: three separate
-- loads failed on manifest/parse problems that a schema check would have
-- caught in one shot (a bogus `github` value, an `experimental` flag that
-- should never have been there, a strict `game_version` floor).
-- src/mods/Manifest.lua is pure -- no filesystem, no LOVE -- so it runs
-- standalone under LuaJIT and is the only opinion that counts.
--
-- Usage, from the mod root:
--     luajit tests/manifest_check.lua /path/to/gen1recomp
--
-- Skips with a clear message when the engine path is not given, so the rest
-- of the test suite stays runnable without a checkout.

local enginePath = arg and arg[1]
if not enginePath or enginePath == "" then
  print("SKIP: pass the gen1recomp checkout path to validate the manifest")
  print("      luajit tests/manifest_check.lua /path/to/gen1recomp")
  os.exit(0)
end

package.path = enginePath .. "/?.lua;" .. enginePath .. "/?/init.lua;"
  .. package.path

-- Minimal JSON reader: enough for a manifest (objects, arrays, strings,
-- numbers, booleans, null). Not a general parser and does not try to be.
local function decode(text)
  local pos = 1
  local function ws()
    while true do
      local c = text:sub(pos, pos)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1
      else break end
    end
  end
  local value

  local function str()
    assert(text:sub(pos, pos) == '"', "expected string at " .. pos)
    pos = pos + 1
    local out = {}
    while true do
      local c = text:sub(pos, pos)
      assert(c ~= "", "unterminated string")
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = text:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f",
                      ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[n] then
          out[#out + 1] = map[n]; pos = pos + 2
        elseif n == "u" then
          -- keep it simple: manifests are scrubbed to UTF-8 by the engine
          out[#out + 1] = "?"; pos = pos + 6
        else
          out[#out + 1] = n; pos = pos + 2
        end
      else
        out[#out + 1] = c; pos = pos + 1
      end
    end
    return table.concat(out)
  end

  function value()
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws()
        local k = str()
        ws()
        assert(text:sub(pos, pos) == ":", "expected : at " .. pos)
        pos = pos + 1
        obj[k] = value()
        ws()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        assert(d == ",", "expected , or } at " .. pos)
      end
    elseif c == "[" then
      pos = pos + 1
      local arr = {}
      ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value()
        ws()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return arr end
        assert(d == ",", "expected , or ] at " .. pos)
      end
    elseif c == '"' then
      return str()
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4; return nil
    else
      local num = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
      assert(num and num ~= "", "unexpected value at " .. pos)
      pos = pos + #num
      return tonumber(num)
    end
  end

  local v = value()
  return v
end

local fh = assert(io.open("manifest.json", "r"), "no manifest.json here")
local raw = decode(fh:read("*a"))
fh:close()

local Manifest = require("src.mods.Manifest")

-- api 2 treats vocabulary violations as hard errors, which is what we want:
-- the gate should fail on anything the loader would reject.
local ok, result = pcall(Manifest.validate, raw, ".")
if not ok then
  print("MANIFEST INVALID: " .. tostring(result))
  os.exit(1)
end

print("manifest valid")
for _, key in ipairs({ "id", "name", "version", "api", "entry", "profile",
                       "category", "priority", "github" }) do
  local v = result[key]
  if v ~= nil then print(("  %-10s %s"):format(key, tostring(v))) end
end
if result.games then
  print(("  %-10s %s"):format("games", table.concat(result.games, ", ")))
end
if result.permissions and next(result.permissions) then
  local list = {}
  for k in pairs(result.permissions) do list[#list + 1] = k end
  print(("  %-10s %s"):format("perms", table.concat(list, ", ")))
end
print("MANIFEST: PASS")
