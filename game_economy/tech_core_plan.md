# Tech Core: Migrating Tech Blocking into Modes & Policies

## 1. Context & Stakeholders

The existing tech blocking system lives in the experimental options tab ([modoptions.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/modoptions.lua) lines 1766-1832). Seth authored it and has moved on from maintaining it. C3BO has built a TechCore gameplay variant on top of it with active community testing, including dedicated "tech core" buildings, no-sharing + tax economy settings, and a per-team tech research mechanic.

The system has known bugs (click/selection issues, debug spam) and no integration with the modes/policies architecture from the `sharing_tab` branch. This document plans the migration.

For background on the Controller/Policy architecture, see [Game Controllers & Policies](https://github.com/keithharvey/bar-design-docs/blob/master/game_economy/explain_policies.md).

### Key Files (Current Implementation)

| File | Role |
|------|------|
| [game_tech_blocking.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/luarules/gadgets/game_tech_blocking.lua) | Synced gadget: tech point tracking, tech level transitions, build blocking |
| [gui_tech_points.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/luaui/RmlWidgets/gui_tech_points/gui_tech_points.lua) | UI widget: tech points bar, tech level display, popup notifications |
| [api_build_blocking.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/luarules/gadgets/api_build_blocking.lua) | Centralized build blocking API (`GG.BuildBlocking`) |
| [alldefs_post.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/gamedata/alldefs_post.lua) lines 519-533 | Unit def post-processing: injects `tech_points_gain` and `tech_build_blocked_until_level` |
| [modoptions.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/modoptions.lua) lines 1766-1832 | Mod options: `tech_blocking`, thresholds, `unit_creation_reward_multiplier` |

### Community Testing

Discord feedback threads and C3BO's direct messages document the bugs and gameplay vision. Key findings from testing:

- Click/selection bugs make the feature frustrating to use in its current state
- The passive XP system (labs generating tech points) incentivizes degenerate lab spam
- C3BO's TechCore variant replaces passive XP with dedicated buildings, producing better gameplay
- Tech level permanence (once researched, stays unlocked) is the intended and desired behavior

---

## 2. Bug Inventory

### Click/Selection Bug (Critical)

`game_tech_blocking.lua` line 231: the `AllowCommand` hook is **redundant** with `api_build_blocking.lua` line 318. Both gadgets register for `CMD.BUILD` via `gadgetHandler:RegisterAllowCommand(CMD.BUILD)`.

The tech blocking gadget already manages blocking state through the `GG.BuildBlocking` API:
- `GameStart` (line 138): calls `GG.BuildBlocking.AddBlockedUnit` for all units above current tech level
- `increaseTechLevel` (line 104): calls `GG.BuildBlocking.RemoveBlockedUnit` when a tech level is reached

Since `api_build_blocking.lua` enforces all blocking via its own `AllowCommand`, the second hook in `game_tech_blocking` creates a racing duplicate. Multiple testers report being unable to click units, labs becoming unselectable, and specific map locations becoming unclickable.

**Fix**: Remove `gadgetHandler:RegisterAllowCommand(CMD.BUILD)` (line 112) and the entire `AllowCommand` function (lines 231-242) from `game_tech_blocking.lua`. The gadget should only manage state via `GG.BuildBlocking.AddBlockedUnit`/`RemoveBlockedUnit`. This is not a policy architecture change -- `api_build_blocking.lua` already owns enforcement for all build blocking. The tech blocking gadget already delegates to it correctly. The redundant hook is just a leftover that needs cleaning up.

### Tech Level Permanence (NOT a Bug)

`GameFrame` recalculates `totalTechPoints` every second from alive buildings, but only calls `increaseTechLevel` on upward transitions (lines 216-226). When buildings are destroyed, points drop but tech level stays. **This is correct and intended.** Tech levels are permanent once researched -- like an RTS tech unlock, not a maintained buff. You need enough alive Catalysts to *reach* the threshold, but after that the level is latched. Losing buildings before reaching the threshold sets you back; losing them after doesn't.

### Debug Spam

Lines 68-69 and 73-74: `Spring.Echo` logs every tech-related unit def at init. This is debug code left in production. Remove.

### Nil-Safety

`spGetTeamRulesParam(teamID, "tech_level")` is not always defaulted. Add `or 1` consistently throughout the gadget and UI widget.

---

## 3. Mod Options Redesign

Replace Seth's options with cardinal options that follow the sharing tab philosophy: each option does exactly one thing.

### Drop Entirely

- **`tech_blocking_per_team`**: Unnecessary indirection. Raw thresholds are transparent -- the lobby host adjusts for their game size.

- **`unit_creation_reward_multiplier`**: Default 0 (disabled). When nonzero, every unit's `power` stat multiplied by the value is added to the team's tech points on construction. This incentivizes degenerate lab/unit spam. The explicit `tech_core_value` approach via dedicated Catalyst buildings is the clean replacement.

- **`tech_points_gain` (passive XP system)**: The entire passive XP accumulation from labs. C3BO already zeroes this out for all units via tweakunits. In the clean implementation, the only point source is `tech_core_value` from alive Catalyst buildings. Remove the `allyXPGains` / `xpGenerators` tracking from the gadget entirely.

### Keep / Rename

- **`tech_blocking`** (bool): Master toggle. Stays as-is.

- **`t2_tech_threshold`** (number): Raw number of tech points (Catalysts, each worth 1) needed to unlock T2. The value is absolute, not per-player. Lobby host adjusts for their game size. Default tuned for 8v8.

- **`t3_tech_threshold`** (number): Raw number of tech points (Catalysts) needed to unlock T3. Same: absolute, transparent.

### New Tech-Schedule ModOptions

These are the composition mechanism that allows transfer and tax policies to vary by tech level:

- **`unit_sharing_mode_at_t2`**: `UnitSharingMode` that activates when team reaches tech 2
- **`unit_sharing_mode_at_t3`**: `UnitSharingMode` that activates when team reaches tech 3
- **`tax_resource_sharing_amount_at_t2`**: Tax rate that applies when team reaches tech 2
- **`tax_resource_sharing_amount_at_t3`**: Tax rate that applies when team reaches tech 3

These are optional. When unset, the base `unit_sharing_mode` / `tax_resource_sharing_amount` applies at all tech levels. When set, `Synced.GetPolicy` resolves the effective value via a generic resolver:

```lua
local function resolveByTechLevel(modOptions, baseKey, techLevel)
  if techLevel >= 3 then
    local v = modOptions[baseKey .. "_at_t3"]
    if v then return v end
  end
  if techLevel >= 2 then
    local v = modOptions[baseKey .. "_at_t2"]
    if v then return v end
  end
  return modOptions[baseKey]
end
```

This keeps policy artifacts as data. The existing `ValidateUnits` / `IsShareableDef` / `classifyUnitDef` pipeline works unchanged -- it still receives a single `sharingMode` string. The resolver just picks which string based on `ctx.techLevel`.

---

## 4. Policy Composition Design

Tech level is published to `TeamRulesParams` as `tech_level` (the gadget already does this). The context factory adds it to `PolicyContext` so all policies can access `ctx.techLevel`.

### Unit Transfers

`Synced.GetPolicy` in [unit_transfer_synced.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/sharing_tab/common/luaUtilities/team_transfer/unit_transfer_synced.lua) currently reads `modOptions.unit_sharing_mode` to determine the sharing mode. Change to:

```lua
local mode = resolveByTechLevel(modOptions, "unit_sharing_mode", ctx.techLevel)
```

Everything downstream -- mode to unitDef classification, per-mode cache, validation -- is unchanged. The pipeline still receives a single `sharingMode` string; the resolver just picks which one based on tech level.

### Resource Transfers

The resource transfer policy reads `modOptions.tax_resource_sharing_amount`. Change to:

```lua
local taxRate = resolveByTechLevel(modOptions, "tax_resource_sharing_amount", ctx.techLevel)
```

### Build Blocking

Currently imperative: gadgets call `GG.BuildBlocking.AddBlockedUnit` / `RemoveBlockedUnit` at arbitrary times. This should eventually become policy-driven (see Future Work). For the immediate tech core work, the gadget continues using `GG.BuildBlocking` imperatively, but the design keeps concerns separated (state publisher vs. blocking decisions) so the transition is incremental.

### Tech Level Permanence

Tech levels are permanent once reached. The build blocking flow is one-directional: units get unblocked when a tech level is reached and never re-blocked for that reason. Tech points (sum of `tech_core_value` from alive Catalysts) can fluctuate, but the latched `tech_level` only goes up. This simplifies the blocking logic -- no regression path needed.

### Key Insight

Tech level does NOT produce its own PolicyResult. It's context data that existing policies consume. No new policy type, no pipeline composition, no ordering constraints. The `_at_t2` / `_at_t3` modOption pattern for transfers is the pragmatic implementation; build blocking as a full policy domain is the architectural direction.

---

## 5. Unit Definitions: Catalyst Buildings

Create new dedicated unit defs instead of monkey-patching existing Asylum shields via `alldefs_post.lua`.

### Names

`armcatalyst`, `corcatalyst`, `legcatalyst`

### Location

Ship in base game (e.g., `units/ArmBuildings/TechCore/armcatalyst.lua`). Always present in game data. Not on any constructor's `buildoptions` by default -- the tech blocking gadget adds them to T1 con build menus when the mode is active.

### Model Reuse

`objectname` points to existing Asylum (T3 shield) models. The Catalyst is a separate unit definition with completely different stats.

| Unit | Model |
|------|-------|
| `armcatalyst` | `Units/ARMGATET3.s3o` |
| `corcatalyst` | `Units/CORGATET3.s3o` |
| `legcatalyst` | `Units/LEGGATET3.s3o` |

### Stats

Based on C3BO's testing (refined from his tweakunits overrides):

- ~1000 metal, ~10000 energy, T1-buildable
- `tech_core_value = 1` in customParams
- Small/cosmetic shield (~200 power, ~100 radius), -100 energy upkeep
- Non-reclaimable, minimal wreck value
- Fusion-class explosion (investment is at risk)

### Remove from alldefs_post.lua

The entire tech blocking section (lines 519-533) that injects `tech_points_gain` and `tech_build_blocked_until_level` into existing unit customParams gets removed. The Catalyst unit defs declare `tech_core_value` directly. The gadget uses each unit def's existing `techlevel` field to determine what to block at which level -- this is already declarative data on the unit def, not runtime injection.

---

## 6. Mode File: Tech Core

```lua
-- modes/tech_core.lua
local ModeEnums = VFS.Include("modes/mode_enums.lua")

return {
    key = ModeEnums.Modes.TechCore,
    name = "Tech Core",
    desc = "Tech levels gate unit construction. Build Catalysts to advance. Sharing unlocks with tech.",
    allowRanked = false,
    modOptions = {
        [ModeEnums.ModOptions.TechBlocking]               = {value = true, locked = true},
        [ModeEnums.ModOptions.T2TechThreshold]             = {value = 8, locked = false},
        [ModeEnums.ModOptions.T3TechThreshold]             = {value = 12, locked = false},
        [ModeEnums.ModOptions.UnitSharingMode]             = {value = "disabled", locked = true},
        [ModeEnums.ModOptions.UnitSharingModeAtT2]         = {value = "t2_cons", locked = true},
        [ModeEnums.ModOptions.UnitSharingModeAtT3]         = {value = "enabled", locked = true},
        [ModeEnums.ModOptions.ResourceSharingEnabled]      = {value = true, locked = true},
        [ModeEnums.ModOptions.TaxResourceSharingAmount]    = {value = 0.30, locked = false},
        [ModeEnums.ModOptions.TaxResourceSharingAmountAtT2] = {value = 0.20, locked = false},
        [ModeEnums.ModOptions.TaxResourceSharingAmountAtT3] = {value = 0.10, locked = false},
    }
}
```

This is purely declarative data. The mode:

- Enables tech blocking with raw thresholds (8 Catalysts for T2, 12 for T3 -- tuned for 8v8, adjust in lobby)
- Starts with no unit sharing, unlocks T2 con sharing at tech 2, full sharing at tech 3
- Applies 30% tax, reduced to 20% at tech 2, 10% at tech 3
- All values are cardinal modOptions resolved by the existing infrastructure

---

## 7. UI: Tech Progress Display

The existing [gui_tech_points.lua](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/luaui/RmlWidgets/gui_tech_points/gui_tech_points.lua) widget shows a fill bar and tech level number. It needs to be reworked for the Catalyst-based system where values are small integers (e.g., 3/8 Catalysts) rather than large accumulated point totals.

The widget should display:

- **Current Catalyst count**: How many alive Catalysts the team has right now
- **Next threshold**: How many are needed for the next tech level (e.g., "3 / 8 for T2")
- **Final threshold**: The T3 target, so players can plan ahead
- **Progress bar**: Visual fill from current toward next threshold
- **"One more" indicator**: Clear visual emphasis when the team is one Catalyst away from the next level (aids team communication -- players need to know when to prioritize building the last one)

All data is already available via `TeamRulesParams`: `tech_points` (current alive Catalyst count), `tech_level` (current latched level), and the thresholds from mod options. The widget reads these -- no new synced infrastructure needed.

---

## 8. Global Enums Additions

```lua
-- additions to modes/global_enums.lua

M.Modes.TechCore = "tech_core"

M.ModOptions.TechBlocking = "tech_blocking"
M.ModOptions.T2TechThreshold = "t2_tech_threshold"
M.ModOptions.T3TechThreshold = "t3_tech_threshold"
M.ModOptions.UnitSharingModeAtT2 = "unit_sharing_mode_at_t2"
M.ModOptions.UnitSharingModeAtT3 = "unit_sharing_mode_at_t3"
M.ModOptions.TaxResourceSharingAmountAtT2 = "tax_resource_sharing_amount_at_t2"
M.ModOptions.TaxResourceSharingAmountAtT3 = "tax_resource_sharing_amount_at_t3"
```

---

## 9. Future Work (Mentioned, Not Scoped)

### Printer / T1.5 Mexes

C3BO's TechCore variant includes a constructor unit ("Printer") buildable from the Catalyst, and T1.5 metal extractors buildable by the Printer. These are interesting gameplay additions but are separate unit def / balance work. The mode infrastructure supports adding them as additional units gated by tech level.

### Build Blocking as a Policy Domain

The `GG.BuildBlocking` imperative API should eventually be replaced by policy-driven evaluation: context in, blocked set out, controller reconciles. This eliminates an entire class of bugs (racing AllowCommand hooks, scattered imperative state mutations) and makes build blocking composable and testable. Terrain, modoption, and tech-level blocking become policies with different evaluation frequencies (once at init vs. periodic). The `api_build_blocking.lua` enforcement mechanism stays; what changes is what drives it. This is the same pattern as transfer policies and should be designed as a peer domain alongside `team_transfer`.

### Tech Pacing Policy as DSL

Once the Phase 2 DSL (from [explain_policies.md](https://github.com/keithharvey/bar-design-docs/blob/master/game_economy/explain_policies.md) Section 6) lands, the tech-schedule modOptions could be expressed more elegantly as policy declarations. The `_at_t2` / `_at_t3` modOption pattern is the pragmatic Now implementation; the DSL is the elegant Next.

### Auto-Scaling Thresholds by Team Size

If a future modes infrastructure supports parameterizing defaults by lobby size, thresholds could auto-adjust. For now, raw values plus lobby host adjustment is sufficient and transparent.
