# Spec & Recoil-Lua-Library Type Alignment Plan

## Problem Statement

We have type definitions in two places:
1. **`Beyond-All-Reason/types/spring.lua`** - Custom ISpring interface for our codebase
2. **`Beyond-All-Reason/recoil-lua-library/library/generated/`** - Auto-generated from engine source

These need to be aligned to:
- Fix linter errors in spec tests
- Enable the Lua language server to provide accurate type checking
- Eventually replace custom types with generated ones

---

## Current State

### Custom Types (`types/spring.lua`)

```lua
---@class ISpring
---@field GetModOptions fun(): table
---@field GetGameFrame fun(): number, any
---@field SetEconomyController fun(controller: GameEconomyController)
-- ... ~40 more fields
```

**Pros**:
- Tailored to our specific use cases
- Includes `ISpring` interface pattern used by SpringBuilder

**Cons**:
- Manual maintenance required
- May drift from actual engine API

### Generated Types (`recoil-lua-library/library/generated/`)

Auto-generated from C++ source comments:
- `LuaSyncedCtrl.cpp.lua` - Synced control functions
- `LuaSyncedRead.cpp.lua` - Synced read functions
- etc.

**Pros**:
- Authoritative, always matches engine
- Covers entire API surface

**Cons**:
- Doesn't define `ISpring` interface
- May have different function signatures than expected

---

## Alignment Tasks

### Phase 1: Audit Existing Types

1. **List all functions in `types/spring.lua`**
2. **Find corresponding definitions in recoil-lua-library**
3. **Document discrepancies**

| Function | Custom Type | Generated Type | Action |
|----------|-------------|----------------|--------|
| `GetModOptions` | `fun(): table` | `fun(): table<string, string>` | Align to generated |
| `SetEconomyController` | `fun(controller: GameEconomyController)` | (missing) | Keep custom |
| `GetTeamResources` | 9 return values | `number?, ...` | Verify return count |

### Phase 2: Create Merged Type Definitions

Create a new file that:
1. Re-exports generated types
2. Adds custom extensions for game_economy features

```lua
-- types/spring_extended.lua

-- Import generated types
local Generated = require("recoil-lua-library.library.generated.rts.Lua.LuaSyncedCtrl.cpp")

-- Extend with custom interfaces
---@class ISpring : Generated.Spring
---@field SetEconomyController fun(controller: GameEconomyController)
---@field GetAuditTimer fun(): number
```

### Phase 3: Update SpringBuilder

The `SpringBuilder` mock needs to:
1. Implement all methods defined in `ISpring`
2. Return correct types for each function
3. Handle new engine functions added for game_economy

**Current gaps in SpringBuilder**:

| Function | Status | Notes |
|----------|--------|-------|
| `IsEconomyAuditEnabled` | ✅ Added | Returns false in tests |
| `SolveWaterfill` | ✅ Added | Pure Lua implementation |
| `SetCachedPolicy` | ✅ Added | Stores in local table |
| `EconomyAuditLog` | ✅ Added | No-op in tests |
| `SetEconomyController` | ❌ Missing | Not needed for unit tests |
| `GetTeamInfo` | ✅ Added | Returns mock data |

### Phase 4: Fix Remaining Spec Failures

Current failing tests in `bar_economy_waterfill_solver_spec.lua`:

1. **Test 1**: `GetTeamRulesParam` returns nil for cumulative key
   - Cause: Passive cumulative param set, but active cumulative param checked
   - Fix: Either update test or update code to set both

2. **Tests 2 & 3**: Incorrect `current` values after waterfill
   - Cause: Algorithm differences between Lua mock and expected behavior
   - Fix: Debug pure Lua `SolveWaterfill` implementation

---

## SpringBuilder Ownership Question

> Should SpringBuilder be an artifact of recoil-lua-library?

### Current Recommendation: Keep Duplicated

**Reasons**:
1. SpringBuilder is test infrastructure, not game code
2. It needs to mock engine functions that don't exist in the library
3. Recoil-lua-library is focused on type definitions, not mocking
4. Our SpringBuilder has BAR-specific helpers (`WithTeam`, `WithAlliance`, etc.)

**Future Consideration**:
Once we confirm the types align, we could:
1. Contribute a minimal `SpringMock` to recoil-lua-library
2. Have our `SpringBuilder` extend that base mock
3. Keep game-specific builders in our repo

---

## Action Items

### Immediate (This Spike)

- [x] Add missing mock functions to SpringBuilder
- [x] Add `SolveWaterfill` pure Lua implementation
- [x] Add economy audit mocks to spec_helper
- [ ] Debug waterfill spec test value mismatches
- [ ] Verify cumulative param key alignment

### Near-Term

- [ ] Create type mapping document (custom → generated)
- [ ] Identify missing generated types for game_economy features
- [ ] Update recoil-lua-library generator if needed

### Long-Term

- [ ] Migrate from `types/spring.lua` to `types/spring_extended.lua`
- [ ] Remove duplicate type definitions
- [ ] Consider contributing SpringMock base class to recoil-lua-library

---

## Type Mapping Reference

### Functions Used by game_economy

| Function | Used In | Custom Type Def | Generated Type Def |
|----------|---------|-----------------|-------------------|
| `Spring.GetModOptions` | SharedConfig | ✅ | ✅ |
| `Spring.GetGameFrame` | EconomyLog | ✅ | ✅ |
| `Spring.GetTeamList` | ResourceTransfer | ✅ | ❌ (check LuaSyncedRead) |
| `Spring.GetTeamResources` | ContextFactory | ✅ | ✅ |
| `Spring.SetTeamResource` | ResourceTransfer | ✅ | ✅ |
| `Spring.SetTeamRulesParam` | CumulativeTracking | ✅ | ✅ |
| `Spring.GetTeamRulesParam` | PolicyResult | ✅ | ✅ |
| `Spring.AreTeamsAllied` | PolicyContext | ✅ | ✅ |
| `Spring.AddTeamResource` | ResourceTransfer | ✅ | ✅ |
| `Spring.SetEconomyController` | Gadget | ✅ | ❌ (new, needs gen) |
| `Spring.SolveWaterfill` | WaterfillSolver | ❌ | ❌ (new, needs gen) |
| `Spring.IsEconomyAuditEnabled` | EconomyLog | ❌ | ❌ (new, needs gen) |
| `Spring.EconomyAuditLog` | EconomyLog | ❌ | ❌ (new, needs gen) |
| `Spring.SetCachedPolicy` | PolicyCache | ❌ | ❌ (new, needs gen) |
| `Spring.GetAuditTimer` | Stopwatch | ❌ | ❌ (new, needs gen) |

### Missing from Generator

The following functions were added for game_economy and need type definitions added to the generator or custom types:

```lua
-- New functions needing type definitions
Spring.SetEconomyController(controller: GameEconomyController)
Spring.SolveWaterfill(members: WaterfillMember[], taxRate: number): WaterfillResult
Spring.IsEconomyAuditEnabled(): boolean
Spring.EconomyAuditLog(eventType: string, ...): nil
Spring.EconomyAuditLogRaw(eventType: string, ...): nil
Spring.EconomyAuditBreakpoint(name: string): nil
Spring.SetCachedPolicy(policyType: PolicyType, senderId: number, receiverId: number, result: table): nil
Spring.GetCachedPolicy(policyType: PolicyType, senderId: number, receiverId: number): table?
Spring.GetAuditTimer(): number
```

---

## Related Documents

- [types/spring.lua](../../Beyond-All-Reason/types/spring.lua) - Current custom types
- [recoil-lua-library/](../../Beyond-All-Reason/recoil-lua-library/) - Generated types
- [spec/builders/spring_builder.lua](../../Beyond-All-Reason/spec/builders/spring_builder.lua) - Test mock
