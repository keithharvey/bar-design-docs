# Testing the Type Generation Pipeline

How to verify that the bifurcated type system (`SpringSynced`, `SpringUnsynced`) works correctly across the three repos.

## Architecture

```
lua-doc-extractor (npm package)
    --table-mapping, --strip-helpers flags
        |
RecoilEngine CI (generate-lua-library.yml)
    mise run lua_library              -> generated/*.cpp.lua  (Spring.*)
    mise run lua_library_bifurcated   -> generated/SpringSynced.lua
                                      -> generated/SpringUnsynced.lua
        |
recoil-lua-library (git repo, pre-built artifacts)
        |
Beyond-All-Reason (git submodule consumer)
```

## 1. lua-doc-extractor unit tests

Validates `--table-mapping` and `--strip-helpers` in isolation.

```bash
distrobox enter rust-dev -- bash -c "cd ~/code/lua-doc-extractor && npm test"
```

All 511 tests should pass. Key test files:
- `src/test/tableMapping.test.ts` -- remapping `Spring.X` to `SpringSynced.X`
- `src/test/stripHelpers.test.ts` -- stripping classes/enums/aliases, keeping functions

## 2. Local generation (simulating what CI does)

From the RecoilEngine checkout, generate both bifurcated files:

```bash
distrobox enter rust-dev -- bash -c "
  cd ~/code/RecoilEngine &&
  node ~/code/lua-doc-extractor/dist/src/cli.js \
    rts/Lua/LuaSyncedCtrl.cpp rts/Lua/LuaSyncedRead.cpp rts/Lua/LuaUnsyncedCtrl.cpp \
    --table-mapping 'Spring:SpringSynced' --strip-helpers \
    --file SpringSynced.lua --dest rts/Lua/library/generated &&
  node ~/code/lua-doc-extractor/dist/src/cli.js \
    rts/Lua/LuaSyncedRead.cpp rts/Lua/LuaUnsyncedCtrl.cpp rts/Lua/LuaUnsyncedRead.cpp \
    --table-mapping 'Spring:SpringUnsynced' --strip-helpers \
    --file SpringUnsynced.lua --dest rts/Lua/library/generated
"
```

Verify the output:

```bash
# Functions present, no duplicate helper types
grep -c '^function SpringSynced\.' RecoilEngine/rts/Lua/library/generated/SpringSynced.lua
# Expect ~646

grep -c '^function SpringUnsynced\.' RecoilEngine/rts/Lua/library/generated/SpringUnsynced.lua
# Expect ~600

# Zero standalone class/enum/alias (these live in the per-file Spring.* output)
grep -c '^---@class \|^---@enum \|^---@alias ' RecoilEngine/rts/Lua/library/generated/SpringSynced.lua
# Expect 0

grep -c '^---@class \|^---@enum \|^---@alias ' RecoilEngine/rts/Lua/library/generated/SpringUnsynced.lua
# Expect 0
```

## 3. LuaLS in the IDE

After the recoil-lua-library submodule is updated (or after local generation into the engine library dir), open BAR in Cursor/VS Code.

LuaLS picks up types from `.luarc.json`:
- `recoil-lua-library/library/` -- `Spring.*`, `SpringSynced.*`, `SpringUnsynced.*`, and all helper types
- `types/` -- `SpringSyncedMock : SpringSynced` and BAR-specific types

Things to verify:
- **No "Duplicate defined fields" errors** -- `--strip-helpers` prevents helper types from appearing in both `SpringSynced.lua` and the per-file `.cpp.lua` outputs
- **Autocomplete works** -- typing `SpringSynced.` shows only synced API functions; `SpringUnsynced.` shows only unsynced API functions
- **Mock inheritance** -- `SpringSyncedMock : SpringSynced` in `types/spring.lua` flags missing methods

## 4. BAR busted tests

Runtime tests that exercise the mock:

```bash
cd ~/code/Beyond-All-Reason && lux test
```

These don't depend on the generated types but validate the mock is functionally correct.

## Troubleshooting

**"Duplicate defined fields"**: A helper type exists in both a bifurcated file and the per-file output. Verify `--strip-helpers` was used during generation.

**LuaSyncedRead.cpp parse warning**: Pre-existing issue with `@return integer|boolean|nil` syntax. Harmless -- those functions are still in the per-file `Spring.*` output from recoil-lua-library.

**`node` not found**: Node.js is only available inside the `rust-dev` distrobox. Wrap all commands with `distrobox enter rust-dev -- bash -c "..."`.

**SpringSynced has more functions than SpringUnsynced**: Expected. `LuaSyncedCtrl` (synced-only) has more functions than `LuaUnsyncedRead` (unsynced-only). Shared sources (`LuaSyncedRead`, `LuaUnsyncedCtrl`) appear in both.
