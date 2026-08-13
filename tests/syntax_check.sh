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
[ "$fail" = 0 ] && echo "LuaJIT syntax: PASS" || echo "LuaJIT syntax: FAIL"
exit $fail
