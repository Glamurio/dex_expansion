#!/bin/sh
# Every gate, in the order that catches problems earliest.
# Optional arg: path to a gen1recomp checkout, which enables the manifest and
# schema gates.
#
#   sh tests/run_all.sh /path/to/gen1recomp
set -e
echo "--- 1. LuaJIT syntax (LOVE runs LuaJIT = Lua 5.1; lua5.4 is NOT a check)"
sh tests/syntax_check.sh
echo
echo "--- 2. manifest, validated by the engine's own src/mods/Manifest.lua"
luajit tests/manifest_check.lua "$1"
echo
echo "--- 3. load, both modes, mod-relative require forbidden"
luajit tests/load_test.lua
echo
echo "--- 4. starter trios: species exist, no soft-lock, rival chain intact"
luajit tests/starter_test.lua
echo
echo "--- 5. encounter payload vs the engine's own schema validator"
luajit tests/encounter_schema_test.lua "$1"
