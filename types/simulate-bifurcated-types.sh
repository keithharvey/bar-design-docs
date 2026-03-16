#!/usr/bin/env bash
set -euo pipefail

# Simulate what RecoilEngine CI will produce once lua-doc-extractor 3.4.0
# is published and the bifurcated generation task is merged.
#
# This copies generated SpringShared/SpringSynced/SpringUnsynced types into
# the local recoil-lua-library submodule so LuaLS can see them in the IDE.
#
# Prerequisites:
#   - RECOIL_ENGINE_DIR set to the RecoilEngine checkout (default: ../RecoilEngine)
#   - LUA_DOC_EXTRACTOR_DIR set to the lua-doc-extractor checkout (default: ../lua-doc-extractor)
#     Must have had `npm install && npm run build` run in it.
#   - Node.js available (run inside distrobox if needed)
#
# Usage:
#   distrobox enter rust-dev -- bash -c "./types/simulate-bifurcated-types.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RLL_GEN="$BAR_ROOT/recoil-lua-library/library/generated"

RECOIL_ENGINE_DIR="${RECOIL_ENGINE_DIR:-$BAR_ROOT/../RecoilEngine}"
LUA_DOC_EXTRACTOR_DIR="${LUA_DOC_EXTRACTOR_DIR:-$BAR_ROOT/../lua-doc-extractor}"
EXTRACTOR="$LUA_DOC_EXTRACTOR_DIR/dist/src/cli.js"

if [ ! -d "$RECOIL_ENGINE_DIR/rts/Lua" ]; then
  echo "ERROR: Cannot find engine Lua sources at $RECOIL_ENGINE_DIR/rts/Lua"
  echo "Set RECOIL_ENGINE_DIR to the RecoilEngine repo root."
  exit 1
fi

if [ ! -f "$EXTRACTOR" ]; then
  echo "ERROR: lua-doc-extractor not built at $LUA_DOC_EXTRACTOR_DIR"
  echo "Run 'npm install && npm run build' in the lua-doc-extractor directory first."
  exit 1
fi

cd "$RECOIL_ENGINE_DIR"

echo "Generating SpringShared (LuaSyncedRead + LuaUnsyncedCtrl)..."
node "$EXTRACTOR" \
  rts/Lua/LuaSyncedRead.cpp \
  rts/Lua/LuaUnsyncedCtrl.cpp \
  --table-mapping "Spring:SpringShared" \
  --strip-helpers \
  --file SpringShared.lua \
  --dest "$RLL_GEN"

sed -i '/^---@meta$/a\\n---@class SpringShared\nSpringShared = {}' "$RLL_GEN/SpringShared.lua"

echo "Generating SpringSynced (LuaSyncedCtrl only)..."
node "$EXTRACTOR" \
  rts/Lua/LuaSyncedCtrl.cpp \
  --table-mapping "Spring:SpringSynced" \
  --strip-helpers \
  --file SpringSynced.lua \
  --dest "$RLL_GEN"

sed -i '/^---@meta$/a\\n---@class SpringSynced : SpringShared\nSpringSynced = {}' "$RLL_GEN/SpringSynced.lua"

echo "Generating SpringUnsynced (LuaUnsyncedRead only)..."
node "$EXTRACTOR" \
  rts/Lua/LuaUnsyncedRead.cpp \
  --table-mapping "Spring:SpringUnsynced" \
  --strip-helpers \
  --file SpringUnsynced.lua \
  --dest "$RLL_GEN"

sed -i '/^---@meta$/a\\n---@class SpringUnsynced : SpringShared\nSpringUnsynced = {}' "$RLL_GEN/SpringUnsynced.lua"

# Ensure Spring.lua has the inheritance declaration
SPRING_LUA="$BAR_ROOT/recoil-lua-library/library/Spring.lua"
cat > "$SPRING_LUA" <<'SPRING_EOF'
---@meta

---@class Spring : SpringSynced, SpringUnsynced
Spring = {}
SPRING_EOF
echo "Updated Spring.lua with inheritance declaration."

echo ""
echo "Done. Files written to recoil-lua-library/library/generated/:"
echo "  SpringShared.lua   ($(grep -c '^function SpringShared\.' "$RLL_GEN/SpringShared.lua") functions)"
echo "  SpringSynced.lua   ($(grep -c '^function SpringSynced\.' "$RLL_GEN/SpringSynced.lua") functions)"
echo "  SpringUnsynced.lua ($(grep -c '^function SpringUnsynced\.' "$RLL_GEN/SpringUnsynced.lua") functions)"
echo ""
echo "Restart LuaLS (Cmd+Shift+P -> 'Lua: Restart') to pick up the changes."
