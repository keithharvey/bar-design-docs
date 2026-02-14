# Tracy Analysis Guide: ProcessEconomy vs Master

A step-by-step guide to profile and compare the economy system performance.

---

## Quick Start: Prove the Blocking Hypothesis

For users with Tracy 0.11.1 compiled at `~/code/tracy-0.11.1`:

### One-Liner Test (Linux)

```bash
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON
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

## Visualizing Thread Blocking

The key question is: **while ProcessEconomy runs, is other work blocked?**

### Method 1: Timeline Thread View (Most Direct)

1. **Open Timeline**: The main view after loading a trace
2. **Find the main thread**: Look for `Main` or the thread with `Sim::GameFrame` zones
3. **Zoom to a SlowUpdate frame**: Use Ctrl+F → search `ProcessEconomy` → click a result
4. **Look for parallel activity**:

```
BLOCKING (bad):
┌─────────────────────────────────────────────────┐
│ Main Thread                                     │
│ ┌─────────────────────────────────────────────┐ │
│ │ GameFrame                                   │ │
│ │ ┌─────────────────────────────────────────┐ │ │
│ │ │ SlowUpdate                              │ │ │
│ │ │ ┌───────────────────────────────────┐   │ │ │
│ │ │ │ ProcessEconomy                    │   │ │ │ ← Everything waits
│ │ │ │ ┌─────────────────────────────┐   │   │ │ │
│ │ │ │ │ PE_Lua                      │   │   │ │ │
│ │ │ └─┴─────────────────────────────┴───┘   │ │ │
│ │ └─────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ Worker Thread 1                                 │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │ ← IDLE during PE!
│                                                 │
│ Worker Thread 2                                 │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │ ← IDLE during PE!
└─────────────────────────────────────────────────┘

NON-BLOCKING (good - hypothetical async design):
┌─────────────────────────────────────────────────┐
│ Main Thread                                     │
│ ┌────┐    ┌────────────────────────────────────┐│
│ │Kick│    │ Continue other work...             ││
│ └────┘    └────────────────────────────────────┘│
│      ↓                                     ↑    │
│ Lua Thread                                 │    │
│      ┌─────────────────────────────────┐   │    │
│      │ PE_Lua (runs in parallel)       │───┘    │
│      └─────────────────────────────────┘        │
└─────────────────────────────────────────────────┘
```

### Method 2: CPU Data View

1. **View → CPU Data** (or press `c`)
2. Look at CPU utilization during ProcessEconomy frames
3. If utilization drops to ~1 core during PE → confirms blocking

### Method 3: Frame Time Histogram

1. **View → Statistics** → find `Sim::GameFrame`
2. Click to see histogram
3. Look for **bimodal distribution**:
   - Normal frames: ~600μs
   - SlowUpdate frames (with PE): ~1500μs+ 
4. The gap indicates blocking overhead

### Interpreting Your Trace Data

From your `zones.csv`, here's what the data shows:

```
ProcessEconomy Blocking Analysis
================================

Zone Hierarchy (reconstructed from source locations):
  EventHandler::ProcessEconomy (41.3ms total)
  └── LuaHandleSynced::ProcessEconomy (41.3ms) ← same call, C++ wrapper
      └── PE_Lua (38.5ms)                       ← Lua execution time
          ├── PE_Solver (15.0ms)                ← Waterfill algorithm
          ├── PE_PolicyCache (18.8ms)           ← Policy updates
          └── PE_LuaMunge (0.08ms)              ← Data formatting

Time Breakdown:
  PE_Lua / ProcessEconomy = 38.5 / 41.3 = 93.2%  ← CONFIRMS BLOCKING
  
  C++ overhead (marshaling, call setup):
    ProcessEconomy - PE_Lua = 41.3 - 38.5 = 2.8ms (6.8%)
    
  Within PE_Lua:
    PE_Solver:      15.0ms (39.0% of PE_Lua)
    PE_PolicyCache: 18.8ms (48.9% of PE_Lua)  ← LARGEST BOTTLENECK
    PE_LuaMunge:     0.1ms ( 0.2% of PE_Lua)
    Unlabeled:       4.6ms (11.9% of PE_Lua)  ← API calls + misc

Variance Analysis:
  ProcessEconomy mean:  939μs
  ProcessEconomy max: 2,309μs  ← 2.5× mean, causes frame spikes!
  
  PE_PolicyCache max: 1,779μs  ← Likely cause of variance
```

### Confirming the Blocking Hypothesis

Your data **supports** the hypothesis from `do_not_block_cpp_plan.md`:

| Evidence | Finding | Conclusion |
|----------|---------|------------|
| PE_Lua ≈ ProcessEconomy | 93.2% ratio | C++ waits for Lua to complete |
| ProcessEconomy in EventHandler | Source: EventHandler.cpp:587 | Runs on main sim thread |
| No parallel zones during PE | (check Timeline view) | Other work is blocked |
| Max >> Mean (2.5×) | Variance in PE_PolicyCache | Causes frame time spikes |

### What the Trace CANNOT Tell You

1. **Absolute impact**: Is 0.94ms/call acceptable for your target hardware?
2. **Comparison to master**: You need a master branch trace to compare
3. **Real blocking proof**: Timeline view confirms, CSV summarizes

### Recommended Tracy Settings for Blocking Analysis

Add these to your Tracy capture for clearer visualization:

```cpp
// In LuaHandleSynced.cpp, around ProcessEconomy call:
FrameMarkStart("SlowUpdate");  // Mark frame boundaries

// At ProcessEconomy entry:
ZoneScopedN("ProcessEconomy::Blocking");
TracyMessageL("PE: Starting Lua call");

// At ProcessEconomy exit:
TracyMessageL("PE: Lua returned");
FrameMarkEnd("SlowUpdate");
```

This creates **frame marks** that show up as vertical lines in Tracy's timeline, making it easy to see what else runs (or doesn't run) during PE.

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
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON
mv build-linux/spring spring-master-tracy

# === ProcessEconomy Build ===
git checkout game_economy
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON
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

## Reference: Jaedrik's 6-Minute Trace Comparison (2026-01-14)

Comprehensive analysis comparing ProcessEconomy branch vs Master on a slower machine.

### ProcessEconomy Branch Metrics

| Zone | Total (ms) | Count | Mean (μs) | Max (μs) |
|------|-----------|-------|-----------|----------|
| ProcessEconomy | 73.2 | 355 | 206 | 1,620 |
| PE_Lua | 60.0 | 355 | 169 | 1,589 |
| PE_PolicyCache_Deferred | 186.2 | 355 | 525 | **4,751** |
| WaterfillSolver.Solve | 50.2 | 355 | 141 | 784 |
| PE_CppMunge | 9.8 | 355 | 28 | 368 |
| PE_CppSetters | 1.5 | 355 | 4 | 62 |

**Key ratio:** `PE_Lua / ProcessEconomy = 60.0 / 73.2 = 82%` → Blocking confirmed

### Overall Frame Time Comparison

| Metric | Master | ProcessEconomy | Δ |
|--------|--------|----------------|---|
| `GameFrame` mean (μs) | 571 | 527 | **-8% (PE faster!)** |
| `Sim::GameFrame` mean (μs) | 720 | 690 | **-4% (PE faster)** |
| `Update` mean (μs) | 668 | 700 | +5% (PE slower) |
| Trace duration | 11,318 frames | 10,647 frames | — |

### ⚠️ Surprising Finding: No Overall Slowdown!

The original hypothesis predicted a ~33% slowdown. The data shows:

| Original Hypothesis | Actual Result |
|---------------------|---------------|
| "PE causes 33% slowdown" | PE is **comparable or faster** than Master |
| "Blocking is the bottleneck" | Blocking exists but impact is **amortized** |

**Why no slowdown?**
1. PE runs only every 30 frames (SlowUpdate cadence)
2. Amortized cost: `(206 + 525) / 30 ≈ 24μs per frame`
3. Master's native sharing has its own overhead

### The REAL Problem: Variance

The issue isn't mean performance—it's **frame spikes**:

| Zone | Mean | Max | Max/Mean |
|------|------|-----|----------|
| ProcessEconomy | 206μs | 1,620μs | **7.9×** |
| PE_PolicyCache_Deferred | 525μs | 4,751μs | **9.0×** |
| **Combined worst case** | 731μs | **6,371μs** | — |

On bad frames, economy processing takes **6.4ms**—enough to cause visible stutters.

### Architecture Note: Deferred Policy Cache

The trace shows `PE_PolicyCache_Deferred` running as a **separate zone** from `ProcessEconomy`:
- Source: `game_resource_transfer_controller.lua:191`
- This is **outside** the ProcessEconomy call
- Suggests policy cache updates were already moved to be deferred

### Revised Hypothesis Status

| Original Claim | Evidence | Status |
|----------------|----------|--------|
| "C++ blocks on Lua during PE" | PE_Lua = 82% of ProcessEconomy | ✅ **Confirmed** |
| "PE causes ~33% slowdown" | Frame times comparable to Master | ❌ **Not observed** |
| "Blocking is THE problem" | Variance (max >> mean) is worse | ⚠️ **Partially** |

### Updated Bottleneck Priority

```
1. PE_PolicyCache_Deferred variance: max 4.75ms  ← BIGGEST SPIKE SOURCE
   └── Called every SlowUpdate, highly variable
   └── Consider: stagger across frames, or move to C++

2. PE_Lua variance: max 1.59ms
   └── WaterfillSolver itself is stable (max 784μs)
   └── Issue may be in data marshaling or API calls

3. Mean overhead is acceptable
   └── 731μs per SlowUpdate = 24μs amortized per frame
   └── No action needed for throughput
```

### Next Steps

1. [x] ~~Compare PE vs Master frame times~~ → **Done: comparable**
2. [ ] Investigate PE_PolicyCache_Deferred variance (why 9× max/mean?)
3. [ ] Consider moving PolicyCache to C++ or staggering updates
4. [ ] Profile specific games/scenarios where stuttering is reported

---

## Related Documents

- [tracy_setup_plan.md](tracy_setup_plan.md) - Planning and context
- [optimizations_plan.md](optimizations_plan.md) - Already-implemented optimizations
- [table_pooling_round2.md](table_pooling_round2.md) - Allocation analysis
- [cpp_waterfill_service.md](cpp_waterfill_service.md) - C++ solver proposal
