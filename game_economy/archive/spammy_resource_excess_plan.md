# Plan: Adopting Sprung's ResourceExcess Approach

> ⚠️ **SUPERSEDED**: This plan's session-based comparison approach won't work because replays just replay network traffic — they don't re-run economy logic differently. See **[dual_branch_comparison_plan.md](dual_branch_comparison_plan.md)** for the revised approach using two separate engine builds.

## Context

PR #2664 (Game Economy) has been stalled. Sprung has a different vision for `ResourceExcess` that calls the event handler more frequently (per-frame or per-excess-event) rather than deferring to SlowUpdate like `ProcessEconomy` does.

**Current branch behavior:**
- `ProcessEconomy`: Accumulates excess every frame → calls Lua once per SlowUpdate (32 frames) → Lua runs waterfill once
- `ResourceExcess`: Currently also deferred to SlowUpdate, receives accumulated excess as parameter

**Sprung's vision:**
- `ResourceExcess` fires immediately when excess is generated (potentially multiple times per frame)
- More "reactive" but means waterfill runs much more frequently

## The Strategy: Concede Ground, Gather Evidence

Rather than continuing to argue for the deferred approach, adopt Sprung's implementation and instrument it for Tracy comparison. The performance data will speak for itself.

### Goals

1. **Get the PR merged** — stop blocking on design philosophy debates
2. **Prove performance with data** — Tracy instrumentation will show the cost difference
3. **Simplify audit modes** — drop complexity that creates friction

## Implementation Plan

### Phase 1: Adopt Sprung's ResourceExcess Semantics

1. **Change `ResourceExcess` to fire per-excess-event** instead of once per SlowUpdate:
   - In `Team.cpp`, call `eventHandler.ResourceExcess()` directly from `AddMetal`/`AddEnergy`/`AddResources` when overflow occurs
   - Remove accumulation into `resExcessThisFrame` for this path
   - Lua receives excess immediately, runs waterfill immediately

2. **Keep `ProcessEconomy` as the deferred alternative**:
   - Accumulates excess over the frame
   - Fires once per SlowUpdate
   - Runs waterfill once per SlowUpdate

3. **Simplify `economy_audit_mode`**:
   - `"off"` → Native engine behavior (no Lua economy controller)
   - `"process_economy"` → Deferred/batched approach (current implementation)
   - `"resource_excess"` → Sprung's per-event approach
   - **Drop `"alternate"`** — too complex to maintain with fundamentally different timing semantics

### Phase 2: Tracy Instrumentation

Add Tracy zones to measure the cost difference:

```cpp
// In Team.cpp - ResourceExcess path (Sprung's approach)
void CTeam::AddMetal(float amount, bool useIncomeMultiplier) {
    // ... existing code ...
    if (res.metal > resStorage.metal) {
        float excess = res.metal - resStorage.metal;
        res.metal = resStorage.metal;
        
        ZoneScopedN("ResourceExcess_Immediate");
        TracyPlot("Economy/ImmediateExcess", static_cast<double>(excess));
        eventHandler.ResourceExcess(teamNum, excess);  // fires immediately
    }
}

// In TeamHandler.cpp - ProcessEconomy path (deferred)
void CTeamHandler::GameFrame(int frameNum) {
    // ...
    if (modInfo.ShouldRunProcessEconomy(frameNum)) {
        ZoneScopedN("ProcessEconomy_Batched");
        eventHandler.ProcessEconomy(frameNum);
    }
}
```

Key metrics to capture:
- **Frame time variance** — spammy approach may cause spikes
- **Total waterfill calls per second** — expect 30x difference (30 fps vs once per SlowUpdate)
- **Lua time per SlowUpdate cycle** — batched should be lower

### Phase 3: Side-by-Side Profiling

Run the same replay twice:
1. `economy_audit_mode = "process_economy"` (deferred)
2. `economy_audit_mode = "resource_excess"` (spammy)

Capture Tracy traces for both. The visualization will show:
- ProcessEconomy: one waterfill spike every 32 frames
- ResourceExcess: constant waterfill noise throughout each frame

## What We're Giving Up

1. **ALTERNATE audit mode** — can't meaningfully alternate when the approaches have different timing
2. **Fair performance comparison** — comparing deferred (1 call/slowupdate) vs immediate (N calls/frame) is apples-to-oranges, but that's the point

## What We're Gaining

1. **PR velocity** — stop blocking on Sprung's review
2. **Performance evidence** — Tracy data to justify future optimization
3. **Simpler codebase** — fewer modes = less complexity

## File Changes Required

### RecoilEngine

| File | Change |
|------|--------|
| `rts/Sim/Misc/Team.cpp` | Call ResourceExcess immediately on overflow |
| `rts/Sim/Misc/TeamHandler.cpp` | Remove ResourceExcess from SlowUpdate path |
| `rts/Sim/Misc/ModInfo.h` | Remove `ECONOMY_AUDIT_ALTERNATE` |
| `rts/Sim/Misc/ModInfo.cpp` | Update mode parsing, simplify predicates |
| `rts/System/EventHandler.cpp` | Keep as-is (already supports both patterns) |
| `rts/Lua/LuaHandleSynced.cpp` | Update ResourceExcess to handle per-team calls |

### Beyond-All-Reason

| File | Change |
|------|--------|
| `gamedata/modrules.lua` | Remove `alternate` as valid option |
| `luarules/gadgets/game_resource_transfer_controller.lua` | Handle immediate excess events |

## Dashboard Changes for Session Comparison

Since we're dropping ALTERNATE mode (which allowed within-session comparison), we need cross-session comparison in the dashboard.

### UI Changes to `dashboard.py`

Add a **Comparison Session** dropdown to the Timing Analysis tab:

```
┌─────────────────────────────────────────────────────────────────┐
│ Session: [#5 [PE] F:0-3600 (4T)  ▼]                             │
│ Compare: [(none)                 ▼]  ← NEW: optional comparison │
│ Time Range: [────●────────●────]                                │
└─────────────────────────────────────────────────────────────────┘
```

### Workflow
1. Run a game with `economy_audit_mode = "process_economy"` → generates Session A
2. Run same replay with `economy_audit_mode = "resource_excess"` → generates Session B
3. In dashboard: Primary = Session A, Compare = Session B
4. Charts overlay both sessions with different colors (PE=cyan, RE=red)

### Implementation Sketch

```python
# New dropdown in timing tab header
dbc.Col([
    dbc.Label("Compare With", style={'fontSize': '12px'}),
    dbc.Select(
        id='comparison-session-dropdown',
        options=[{'label': '(none)', 'value': ''}],
        value='',
        placeholder="Select comparison session..."
    )
], width=3),

# Modified load function
def load_solver_timing_data_comparison(primary_id, comparison_id, time_range):
    """Load timing data from two sessions, tagged by source."""
    primary_df = load_solver_timing_data(primary_id, time_range)
    primary_df['session_label'] = 'Primary'
    
    if comparison_id:
        compare_df = load_solver_timing_data(comparison_id, time_range)
        compare_df['session_label'] = 'Comparison'
        return pd.concat([primary_df, compare_df])
    
    return primary_df
```

### Time Alignment Strategy
- Use **game time** (frame / 30.0) as the x-axis, not absolute frame numbers
- Both sessions start from game time 0:00, so they naturally align
- The global time range filter applies to both sessions independently

### Chart Modifications
- `create_timing_over_time_chart`: Already supports multiple source_paths → reuse for session comparison
- `create_timing_summary_table`: Already shows Δ columns when two sources present → works as-is
- `create_timing_histograms`: Already overlays by source → works as-is

Key insight: The existing code treats `source_path` (RE/PE) as the differentiator. For cross-session comparison, we can synthesize this by labeling one session as "RE" and another as "PE" based on their `session_types` field.

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Performance regression visible to players | Medium | Tracy instrumentation will catch it before release |
| Waterfill called with tiny excess amounts | High | Add minimum threshold check in Lua |
| Desync between paths | Low | Only one path active at a time |
| Session comparison misaligned | Medium | Use game time, not frame numbers |

## Success Criteria

1. PR #2664 is merged
2. Tracy data clearly shows cost difference between modes
3. `economy_audit_mode = "process_economy"` remains the BAR default
4. Documentation explains why deferred is preferred
5. Dashboard supports cross-session comparison for PE vs RE

## Notes

Sprung hasn't engaged with the `explain_policies.md` doc. More documentation won't help. The Tracy data will make the argument better than prose ever could.

If the performance gap is as large as expected (30x more waterfill calls), we can propose making `process_economy` the only supported mode in a future PR, citing the evidence.
