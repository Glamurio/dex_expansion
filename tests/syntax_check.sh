#!/bin/sh
# Parse every Lua file with LuaJIT, which is what LOVE actually runs.
#
# THIS GATE EXISTS BECAUSE lua5.4 IS NOT A VALID CHECK.  LOVE uses LuaJIT,
# i.e. Lua 5.1 SYNTAX.  The operators `~` `&` `|` `<<` `>>` and `//` are
# Lua 5.3+; `luac -p` from 5.4 accepts them and LuaJIT rejects the entire
# file.  A mod that "compiles" under 5.4 can still fail to load.
set -e
fail=0
for f in main.lua mod.card src/*.lua data/*.lua tests/*.lua; do
  [ -e "$f" ] || continue
  if luajit -bl "$f" /dev/null >/dev/null 2>&1; then
    echo "ok   $f"
  else
    echo "FAIL $f"
    luajit -bl "$f" /dev/null 2>&1 | head -2
    fail=1
  fi
done
# mod.log exposes info, warn and error only (src/mods/Loader.lua).  A call to
# any other level is a runtime crash the moment that line is reached, which is
# how mod.log:debug shipped: it sat on a path that only ran with a dangling
# evolution present.
bad=$(grep -rn "log:[a-z]*(" --include="*.lua" . \
  | grep -vE "log:(info|warn|error)\(" || true)
if [ -n "$bad" ]; then
  echo "FAIL: mod.log has no such level:"
  echo "$bad"
  exit 1
fi
echo "log levels: only info/warn/error used"

[ "$fail" = 0 ] && echo "LuaJIT syntax: PASS" || echo "LuaJIT syntax: FAIL"
exit $fail