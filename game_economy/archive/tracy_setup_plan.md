# Tracy Setup Plan for ProcessEconomy vs Master Comparison

## Goal

Produce a `tracy_analysis_guide.md` that enables anyone to:
1. Capture Tracy profiles of **master** (native excess sharing) vs **ProcessEconomy** (Lua solver)
2. Compare the captures side-by-side in Tracy
3. Identify the **exact source** of the 33% slowdown

---

## Background: The 33% Slowdown

ProcessEconomy replaces native C++ excess sharing with a Lua-based waterfill solver. On slow machines, this shows ~33% overhead. Possible causes:

| Hypothesis | How to Verify |
|------------|---------------|
| **GC Pressure** | Compare Lua memory plots; check for GC spikes during SlowUpdate |
| **Lua ↔ C++ Boundary** | Count API calls in tracy (GetTeamResources, SetTeamResource, etc.) |
| **Solver Math** | Compare `PE_Solver` zone to native excess sharing zone |
| **Table Allocations** | Already optimized but verify no new allocations in trace |
| **Policy Cache Overhead** | Check `PE_PolicyCache` zone duration |

---

## Tracy Zones Already Instrumented

### Lua Side (game_resource_transfer_controller.lua)
```lua
tracy.ZoneBeginN("PE_Lua")           -- Top-level wrapper
  tracy.ZoneBeginN("PE_LuaMunge")    -- Data prep before solver
  tracy.ZoneBeginN("PE_Solver")      -- WaterfillSolver.Solve()
  tracy.ZoneBeginN("PE_PostMunge")   -- Result formatting
  tracy.ZoneBeginN("PE_PolicyCache") -- Policy cache update
```

### Lua Side (economy_waterfill_solver.lua)
```lua
tracy.ZoneBeginN("WaterfillSolver.Solve")
  tracy.ZoneBeginN("CollectMembers:metal|energy")
  tracy.ZoneBeginN("ApplyDeltas")
```

### C++ Side (Team.cpp, TeamHandler.cpp)
- `RECOIL_DETAILED_TRACY_ZONE` in SlowUpdate paths
- Enable via `-DRECOIL_DETAILED_TRACY_ZONING=1`

---

## Required Engine Builds

| Build | Branch | CMake Flags |
|-------|--------|-------------|
| **master-tracy** | `master` or release tag | `-DTRACY_ENABLE=1 -DTRACY_ON_DEMAND=1` |
| **pe-tracy** | `game_economy` branch | `-DTRACY_ENABLE=1 -DTRACY_ON_DEMAND=1 -DRECOIL_DETAILED_TRACY_ZONING=1` |

### Build Commands (docker-build-v2)

```bash
# From RecoilEngine directory

# Master build
git checkout master
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON -DTRACY_ON_DEMAND=ON
cp build-linux/spring spring-master-tracy

# ProcessEconomy build
git checkout game_economy
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON -DTRACY_ON_DEMAND=ON -DRECOIL_DETAILED_TRACY_ZONING=ON
cp build-linux/spring spring-pe-tracy
```

---

## Test Scenario Requirements

For reproducible comparison, use an **identical replay/scenario**:

1. **Controlled Test Game**: 8 players, FFA, mid-game economy (~5 min mark)
2. **Same Frame Range**: Record frames 9000-10800 (5:00-6:00 game time = 60 seconds)
3. **Headless Mode**: Preferred to eliminate rendering variance

### Recommended Startscript
```txt
[GAME]
{
  Mapname=Red Comet Remake 1.8;
  GameType=Beyond All Reason test-25490-4c6a058;
  NumPlayers=8;
  NumTeams=8;
  NumAllyTeams=2;
  ...
}
```

---

## Capture Workflow

### Step 1: Launch Tracy Profiler
```bash
# Download from https://github.com/wolfpld/tracy/releases
./Tracy &
```

### Step 2: Run Master Capture
```bash
./spring-master-tracy --headless startscript.txt
# In Tracy: Connect → Record → Wait for target frames → Stop → Save as "master.tracy"
```

### Step 3: Run ProcessEconomy Capture
```bash
./spring-pe-tracy --headless startscript.txt
# In Tracy: Connect → Record → Wait for target frames → Stop → Save as "pe.tracy"
```

### Step 4: Compare in Tracy
1. Open both `.tracy` files
2. Use **Statistics** panel to compare zone times
3. Use **Compare** feature (if available in your Tracy version)

---

## Key Metrics to Extract

### 1. SlowUpdate Total Time
- **Master**: Find `Team::SlowUpdate` or equivalent C++ zone
- **PE**: Sum of `PE_Lua` zone

### 2. Per-Component Breakdown
| Zone | Expected % | If Higher → Indicates |
|------|------------|----------------------|
| PE_LuaMunge | 5% | BuildTeamData overhead |
| PE_Solver | 60% | Waterfill algorithm |
| PE_PostMunge | 5% | Result formatting |
| PE_PolicyCache | 20% | N² policy updates |
| (unlabeled) | 10% | Lua→C++ API calls |

### 3. GC Indicators
- Look for **Memory** plot in Tracy
- Check `Spring.GetSyncedGCInfo()` values around SlowUpdate
- Identify any GC pauses overlapping economy zones

### 4. API Call Frequency
Count calls to:
- `GetTeamResources` 
- `SetTeamResource`
- `SetTeamRulesParam`
- `ShareTeamResource` (should be 0 in PE mode)

---

## Gap Analysis: What's Missing

### Current Gaps in Tracy Instrumentation

1. **No zone for individual API calls** in Lua → Can't see cost of `SetTeamResource` boundary
2. **No zone for ledger serialization** in `team_transfer_serialization_helpers.lua`
3. **No GC tracking zone** around SlowUpdate
4. **No cumulative counter** for table allocations

### Recommended Additions

```lua
-- In economy_log.lua, add:
function EconomyLog.APICall(name, count)
  if tracyAvailable then
    tracy.Message(string.format("API:%s×%d", name, count))
  end
end

-- Or use tracy.LuaTracyPlot for continuous metrics:
tracy.LuaTracyPlot("Economy/APICalls", apiCallCount)
tracy.LuaTracyPlot("Economy/GCKb", Spring.GetSyncedGCInfo())
```

### C++ Side (for SetTeamResource overhead)
```cpp
// In LuaSyncedCtrl.cpp, SetTeamResource:
ZoneScopedN("SetTeamResource");
```

---

## Deliverable: tracy_analysis_guide.md

The guide should contain:

1. **Prerequisites**
   - Tracy version
   - Engine builds (with download links or build instructions)
   - Test scenario files

2. **Step-by-Step Capture Process**
   - How to start Tracy
   - How to connect to the game
   - Frame range to capture
   - Naming convention for captures

3. **Analysis Checklist**
   - [ ] Compare SlowUpdate total duration
   - [ ] Check PE_Solver vs native excess sharing
   - [ ] Look for GC spikes in memory plot
   - [ ] Count API call markers
   - [ ] Check PE_PolicyCache percentage

4. **Interpreting Results**
   - Decision tree: "If X is high, the cause is Y"
   - Links to relevant optimization docs

5. **Screenshot Examples**
   - Tracy Statistics view
   - Zone flamegraph
   - Memory plot overlay

---

## Implementation Tasks

1. [ ] Build `master-tracy` and `pe-tracy` binaries
2. [ ] Create standardized test scenario
3. [ ] Add missing Tracy zones (API calls, GC)
4. [ ] Capture baseline profiles
5. [ ] Document findings in tracy_analysis_guide.md
6. [ ] Identify top 3 slowdown sources
7. [ ] Create optimization tickets for each source

---

## Related Documents

- [optimizations_plan.md](optimizations_plan.md) - Current optimization status
- [table_pooling_round2.md](table_pooling_round2.md) - Allocation analysis
- [cpp_waterfill_service.md](cpp_waterfill_service.md) - Engine-side solver proposal
- [RecoilEngine/doc/site/content/development/profiling-with-tracy.md](../../RecoilEngine/doc/site/content/development/profiling-with-tracy.md) - Official Tracy guide
