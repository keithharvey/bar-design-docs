# Spring-Split Triage: Remaining Unmapped `Spring.X` References

After running `spring-split` and `detach-bar-modules`, ~432 `Spring.X` references remained
unmapped across 28 unique method/field names. This document records what was done for each.

## Category 1: Deprecated Aliases (~348 refs) — FIXED (codemod)

The engine registers these as `REGISTER_NAMED_LUA_CFUNC` aliases in `LuaUnsyncedRead.cpp`:

```cpp
REGISTER_NAMED_LUA_CFUNC("GetMyPlayerID", GetLocalPlayerID);
REGISTER_NAMED_LUA_CFUNC("GetMyTeamID", GetLocalTeamID);
REGISTER_NAMED_LUA_CFUNC("GetMyAllyTeamID", GetLocalAllyTeamID);
```

The canonical names (`GetLocalTeamID` etc.) are fully documented and present in the generated
stubs as `SpringUnsynced.*`. The `GetMy*` aliases have no doc comments and are not extracted.

| Alias | Canonical | Refs |
|-------|-----------|------|
| `GetMyTeamID` | `GetLocalTeamID` | 127 |
| `GetMyAllyTeamID` | `GetLocalAllyTeamID` | 113 |
| `GetMyPlayerID` | `GetLocalPlayerID` | 108 |

**Done:** `bar-lua-codemod rename-aliases` rewrites the method name. Wired into `fmt-mig`
pipeline between `bracket-to-dot` and `detach-bar-modules`. Dry run confirmed 348 conversions.

## Category 2: BAR Polyfills on Spring (~5 refs) — FIXED (codemod)

`GetModOptionsCopy` is defined in `common/springOverrides.lua` as a BAR-side function
stapled onto the `Spring` table:

```lua
Spring.GetModOptionsCopy = function()
    return table.copy(modOptions)
end
```

Same pattern as `I18N`, `Utilities`, `Debug`, `Lava`.

**Done:** Added `"GetModOptionsCopy"` to the `BAR_MODULES` list in `detach-bar-modules`.
After detach, call sites become `GetModOptionsCopy()` and the declaration in
`springOverrides.lua` becomes a plain global.

## Category 3: Dead/Nonexistent Engine APIs — FIXED (manual BAR edits)

### SetUnitCOBValue / GetUnitCOBValue (9 refs) — migrated to UnitScript API

These are registered as backwards-compat aliases in `LuaUnitScript.cpp:1083-1084` (NOT
commented out as originally thought — the `//FIXME:` in `LuaSyncedCtrl.cpp` is a different
registration path). They work at runtime but are undocumented legacy names for
`Spring.UnitScript.SetUnitValue` / `GetUnitValue`.

Migrated all call sites to the canonical API:

| File | Change |
|------|--------|
| `unit_crashing_aircraft.lua` | `Spring.SetUnitCOBValue` → `Spring.UnitScript.SetUnitValue` |
| `unit_paralyze_on_off.lua` | Same |
| `unit_mex_upgrade_reclaimer.lua` | Same |
| `unit_geo_upgrade_reclaimer.lua` | Same |
| `unit_dragons_disguise.lua` | `Spring.GetUnitCOBValue` → `Spring.UnitScript.GetUnitValue` |
| `unit_attributes.lua` | `Spring.SetUnitCOBValue` → `Spring.UnitScript.SetUnitValue` |
| `unit_carrier_spawner.lua` | Same (3 call sites) |

### GetProjectileName (3 refs) — replaced with GetProjectileDefID

`GetProjectileName` was never registered in the engine. Only mentioned in a doc comment.
All 3 call sites were debug `spEcho` logging. Replaced with `GetProjectileDefID` which
exists and returns the weapon def ID (sufficient for debug output).

| File | Change |
|------|--------|
| `gfx_distortion_gl4.lua` | `Spring.GetProjectileName` → `Spring.GetProjectileDefID` |
| `gfx_deferred_rendering_GL4.lua` | Same (2 call sites) |

### GameFrame (1 ref) — fixed typo

`Spring.GameFrame()` in `ai/shard_runtime/spring_lua/unit.lua` — should be
`Spring.GetGameFrame()`. Fixed.

### Controller APIs (7 refs) — left as-is

`DisconnectController`, `ConnectController`, `GetAvailableControllers`, `GetControllerState`
in `gui_controller_test.lua`. Already guarded by `if not Spring.GetAvailableControllers then`
with early return. This is forward-compatible code for a planned engine feature. No fix needed.

### TimeCheck (1 ref) — reclassified: NOT a bug

`Spring.TimeCheck` in `gamedata/defs.lua` IS a real engine function. It's registered in
`LuaParser.cpp` via `GetTable("Spring") / AddFunc("TimeCheck", TimeCheck) / EndTable()`.
Only available in the LuaParser environment (defs loading). Not a bug.

### GetGroupAIName (1 ref) — removed dead code

`Spring.GetGroupAIName` in `luaui/debug.lua` does not exist in the engine. The call was
nil-guarded but the surrounding code was dead. Simplified the debug print to remove it.

## Category 4: Engine Sub-tables (~43 refs) — FIXED (type stubs)

These are nested tables the engine pushes onto `Spring` via the C API, not individual methods.
The codemod correctly leaves them as `Spring.UnitScript.CallAsUnit()` etc.

| Sub-table | Context | Registered in | Refs |
|-----------|---------|---------------|------|
| `UnitScript` | Synced | `LuaUnitScript.cpp` via `CLuaHandleSynced` | 31 |
| `UnitRendering` | Unsynced | `LuaRules.cpp::AddUnsyncedCode` | 6 |
| `FeatureRendering` | Unsynced | `LuaRules.cpp::AddUnsyncedCode` | 6 |

**Done:** Added `UnitScriptTable` and `ObjectRenderingTable` class stubs to
`Beyond-All-Reason/types/Spring.lua` with all methods from the engine registration code.
Added `@field UnitScript UnitScriptTable` to `SpringSynced` and
`@field UnitRendering/FeatureRendering ObjectRenderingTable` to `SpringUnsynced`.

## Category 5: Engine Constants (~5 refs) — FIXED (type stubs)

Numeric constants pushed via `LuaPushNamedNumber` in `LuaSyncedRead::PushEntries`:

| Constant | Refs |
|----------|------|
| `ENEMY_UNITS` | 2 |
| `ALL_UNITS` | 1 |
| `ALLY_UNITS` | 1 |
| `CMD` | 1 |

`CMD` in `spec/builders/spring_synced_builder.lua` is test code — `CMD` is a standalone
global, not a Spring field. The `@field CMD table` already existed in the SpringSynced stub.

**Done:** Added `@field ALL_UNITS number`, `@field ALLY_UNITS number`,
`@field ENEMY_UNITS number` to the `SpringSynced` class in `types/Spring.lua`.

## Category 6: Unstubbed C++ Files — FIXED (engine annotations + BAR bug fix)

### LuaPathFinder.cpp (synced, ~3 refs) — annotated

`RequestPath`, `SetPathNodeCost`, `GetPathNodeCost`, `SetPathNodeCosts`,
`GetPathNodeCosts`, `InitPathNodeCostsArray`, `FreePathNodeCostsArray` are registered in
`LuaPathFinder::PushEntries`, called from `LuaSyncedRead::PushEntries`.

**Done:** Added `@function Spring.X` doc annotations to all 7 functions in
`RecoilEngine/rts/Lua/LuaPathFinder.cpp`. These will be extracted by `lua-doc-extractor`
on next `just lua::library` run and inherit the synced context from LuaSyncedRead.

### ZlibCompress / ZlibDecompress (2 refs) — BAR bug fixed

Registered on `VFS` table in `LuaVFS.cpp`, not on `Spring`. BAR was calling
`Spring.ZlibCompress` / `Spring.ZlibDeCompress` (also wrong capitalization).

**Done:** Fixed `cmd_selected_units.lua` to use `VFS.ZlibCompress` / `VFS.ZlibDecompress`.

### SetShockFrontFactors (1 ref) — annotated

Registered only in `CLuaUI` context (`LuaUI.cpp:318`). Had no doc annotation.

**Done:** Added `@function Spring.SetShockFrontFactors` doc annotation to
`RecoilEngine/rts/Lua/LuaUI.cpp`.

## Summary

| Category | Refs | Disposition | Status |
|----------|------|-------------|--------|
| Deprecated aliases | 348 | `rename-aliases` codemod | Done |
| BAR polyfills | 5 | `detach-bar-modules` codemod | Done |
| Dead/nonexistent APIs | 22 | Manual BAR fixes + reclassification | Done |
| Engine sub-tables | 43 | Type stubs in `types/Spring.lua` | Done |
| Engine constants | 5 | Type stubs in `types/Spring.lua` | Done |
| Unstubbed C++ files | 6 | Engine annotations + BAR bug fix | Done |
| **Total** | **429** | | **All resolved** |
