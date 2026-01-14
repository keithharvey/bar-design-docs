# Tracy Analysis Guide: ProcessEconomy vs Master

A step-by-step guide to profile and compare the economy system performance.

---

## Quick Start: Prove the Blocking Hypothesis

For users with Tracy 0.11.1 compiled at `~/code/tracy-0.11.1`:

### One-Liner Test (Linux)

```bash
# Terminal 1: Start Tracy
~/code/tracy-0.11.1/Tracy &

# Terminal 2: Run headless game (adjust paths as needed)
cd /path/to/BAR && ./spring-pe-tracy --headless /path/to/replay.sdfz
```

### What to Look For

1. Open Tracy, click **Connect** → `127.0.0.1`
2. Let it capture ~30 seconds of gameplay
3. Press **Ctrl+F** and search for `SlowUpdate`
4. Look at the zone breakdown:

| If You See This... | It Means... |
|-------------------|-------------|
| `SlowUpdate` contains `PE_Lua` as largest child | C++ is blocking on Lua |
| `PE_Lua` ≈ `SlowUpdate` total time | 100% blocking, no parallelism |
| Large gap between zone end and next zone | Thread is idle/waiting |

### Quick Verification Zones

Search for these zones to confirm blocking:

```
Zone: SlowUpdate::ProcessEconomy
├── Zone: PE_Lua           ← Time spent in Lua
│   ├── PE_Solver         ← Waterfill algorithm
│   └── PE_PostMunge      ← Result formatting
└── (gap = idle time)     ← If visible, thread is blocked
```

### Share These Metrics

When reporting results, capture:
- Mean `SlowUpdate::ProcessEconomy` duration (μs)
- Mean `PE_Lua` duration (μs)
- Ratio: `PE_Lua / SlowUpdate` (should be close to 1.0 if blocking)

---

## Prerequisites

### Tracy Profiler
Download Tracy v0.11.x or later from:
https://github.com/wolfpld/tracy/releases

### Engine Builds

You need two Tracy-enabled engine builds:

| Build | Purpose | Branch |
|-------|---------|--------|
| `spring-master-tracy` | Baseline (native excess sharing) | `master` or latest release |
| `spring-pe-tracy` | ProcessEconomy (Lua solver) | `game_economy` branch |

#### Build Commands (docker-build-v2)

```bash
cd /path/to/RecoilEngine

# === Master Build ===
git checkout master
git pull
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON -DTRACY_ON_DEMAND=ON
mv build-linux/spring spring-master-tracy

# === ProcessEconomy Build ===
git checkout game_economy
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON -DTRACY_ON_DEMAND=ON -DRECOIL_DETAILED_TRACY_ZONING=ON
mv build-linux/spring spring-pe-tracy
```

## Capture Process

### Step 1: Start Tracy Profiler

```bash
./Tracy      # Linux
Tracy.exe    # Windows
```

Tracy will show "Waiting for connection..." in the status bar.

### Step 2: Run the Game with Master Build

```bash
# Option A: With UI (for live games)
./spring-master-tracy

# Option B: Headless (for replays/consistent timing)
./spring-master-tracy --headless replay.sdfz
```

### Step 3: Connect and Record

1. In Tracy, click **Connect** → Enter `127.0.0.1` (default)
2. Wait for connection to establish
3. Let the game run through your target time range (e.g., 5:00-6:00 game time)
4. Click **Pause** (or the game will keep recording)
5. **File → Save trace** as `master-YYYYMMDD.tracy`

### Step 4: Repeat for ProcessEconomy Build

```bash
./spring-pe-tracy --headless replay.sdfz
```

Save as `pe-YYYYMMDD.tracy`

---

## Analysis Workflow

### Opening Traces

Open both `.tracy` files in Tracy:
- **File → Open** for the first trace
- **File → Open in new window** for the second (to compare side-by-side)

### Finding Economy Zones

Use **Find Zone** (Ctrl+F) to search for:

| Zone Name | What It Measures |
|-----------|------------------|
| `PE_Lua` | Total ProcessEconomy Lua time |
| `PE_Solver` | Waterfill solver algorithm |
| `PE_PolicyCache` | Policy update overhead |
| `WaterfillSolver.Solve` | Detailed solver breakdown |
| `Team::SlowUpdate` | C++ team update (master only) |
| `GameFrame` | Total frame time |

### Using Statistics View

1. **View → Statistics** (or press `s`)
2. Find your zone of interest
3. Note: **Mean**, **Median**, **Max**, **Total**

Compare between master and PE traces.

---

## Key Comparisons

### 1. SlowUpdate Total Time

**Question**: How much slower is PE overall?

| Metric | Master | PE | Δ% |
|--------|--------|----|----|
| Mean SlowUpdate (μs) | ___ | ___ | ___ |
| Max SlowUpdate (μs) | ___ | ___ | ___ |

### 2. Component Breakdown (PE only)

| Zone | Mean (μs) | % of PE_Lua | Notes |
|------|-----------|-------------|-------|
| PE_LuaMunge | ___ | ___% | Data prep |
| PE_Solver | ___ | ___% | Core algorithm |
| PE_PostMunge | ___ | ___% | Result formatting |
| PE_PolicyCache | ___ | ___% | N² cache update |
| **Unlabeled** | ___ | ___% | API boundary + GC |

**Insight**: If "Unlabeled" is high, the overhead is in Lua↔C++ API calls.

### 3. GC Indicators

Open **View → Memory** plot:

- Look for **sawtooth patterns** (allocate→GC→allocate)
- Check if GC spikes **correlate with SlowUpdate**
- Compare memory growth rate between master and PE

**From Lua console** (in-game):
```lua
/luarules echo Spring.GetSyncedGCInfo(true)
```

### 4. Frame Time Distribution

In the **Timeline View**:
1. Find a SlowUpdate frame (every 30 game frames)
2. Zoom in on the thread
3. Look for **stalls** or **long zones**

---

## Decision Tree

Use this to identify the slowdown source:

```
Is PE_Lua > 1.5× master SlowUpdate?
├── YES: Check zone breakdown
│   ├── PE_Solver > 50% of PE_Lua?
│   │   └── YES → Solver algorithm is the bottleneck
│   │       → Consider C++ waterfill (cpp_waterfill_service.md)
│   │
│   ├── PE_PolicyCache > 30% of PE_Lua?
│   │   └── YES → Policy cache is the bottleneck
│   │       → Implement staggered updates
│   │
│   ├── Unlabeled > 20% of PE_Lua?
│   │   └── YES → API boundary overhead
│   │       → Add zones to SetTeamResource calls
│   │       → Consider batch APIs
│   │
│   └── Memory sawtooth visible?
│       └── YES → GC pressure
│           → Review table_pooling_round2.md
│           → Check warmup period (first 30 frames)
│
└── NO: Performance is acceptable
```

---

## Adding More Instrumentation

If you need finer granularity:

### Lua Side

```lua
-- In any hot path:
local tracyAvailable = tracy and tracy.ZoneBeginN and tracy.ZoneEnd

if tracyAvailable then tracy.ZoneBeginN("MyZoneName") end
-- ... hot code ...
if tracyAvailable then tracy.ZoneEnd() end

-- For metrics:
tracy.LuaTracyPlot("Economy/MetricName", value)

-- For events:
tracy.Message("Something happened: " .. detail)
```

### C++ Side

```cpp
#include "System/Misc/TracyDefs.h"

// Auto zone (scoped):
ZoneScopedN("MyZoneName");

// Or manual:
ZoneNamedN(___zone, "MyZoneName", true);
// ... code ...
// Zone ends when ___zone goes out of scope
```

---

## Recording GC Metrics

Add this to economy_log.lua for continuous GC tracking:

```lua
function EconomyLog.TrackGC()
  if tracyAvailable and tracy.LuaTracyPlot then
    local gcKb = Spring.GetSyncedGCInfo(false)
    tracy.LuaTracyPlot("Economy/SyncedGC_Kb", gcKb or 0)
  end
end
```

Call from ProcessEconomy:
```lua
EconomyLog.TrackGC() -- Before and after solver
```

---

## Common Pitfalls

1. **Tracy version mismatch**: Engine and profiler must use same Tracy version
2. **On-demand not working**: Ensure `TRACY_ON_DEMAND=1` is set
3. **No zones visible**: Check that Tracy connected BEFORE the zones executed
4. **Memory plot empty**: Build without `TRACY_PROFILE_MEMORY` may hide some data

---

## Example Findings Template

Fill this in after analysis:

### Summary

| Build | SlowUpdate Mean | SlowUpdate Max |
|-------|-----------------|----------------|
| Master | ___μs | ___μs |
| ProcessEconomy | ___μs | ___μs |
| **Overhead** | **___×** | **___×** |

### Top 3 Bottlenecks

1. **___** (___% of overhead)
   - Root cause: ___
   - Fix: ___

2. **___** (___% of overhead)
   - Root cause: ___
   - Fix: ___

3. **___** (___% of overhead)
   - Root cause: ___
   - Fix: ___

### Recommended Actions

- [ ] ___
- [ ] ___
- [ ] ___

---

## Related Documents

- [tracy_setup_plan.md](tracy_setup_plan.md) - Planning and context
- [optimizations_plan.md](optimizations_plan.md) - Already-implemented optimizations
- [table_pooling_round2.md](table_pooling_round2.md) - Allocation analysis
- [cpp_waterfill_service.md](cpp_waterfill_service.md) - C++ solver proposal
