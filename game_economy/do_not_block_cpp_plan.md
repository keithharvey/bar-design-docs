# Hypothesis: ProcessEconomy Blocking Is the Performance Problem

## The Problem

The ProcessEconomy system was suspected to cause a ~33% performance drop on lower-end machines. The hypothesis was: **the engine blocks during Lua execution**.

When the engine calls into Lua for ProcessEconomy, it:
1. Stops the C++ simulation frame
2. Marshals team data from C++ → Lua tables
3. Waits for Lua to execute the waterfill solver
4. Marshals results from Lua tables → C++ team state
5. Only then continues with the rest of the frame

This blocking round-trip was the suspected bottleneck.

---

## ⚠️ Hypothesis Status: PARTIALLY CONFIRMED (2026-01-14)

Tracy analysis from Jaedrik's slower machine reveals a more nuanced picture:

| Original Claim | Evidence | Status |
|----------------|----------|--------|
| "C++ blocks on Lua during PE" | PE_Lua = 82% of ProcessEconomy time | ✅ **Confirmed** |
| "PE causes ~33% slowdown" | Frame times comparable to Master | ❌ **Not observed** |
| "Blocking is THE problem" | Variance (max >> mean) is the issue | ⚠️ **Revised** |

### What the Data Shows

**ProcessEconomy (6-minute trace, slower machine):**
- Mean: 206μs per call (every 30 frames)
- Max: 1,620μs (7.9× mean)
- PE_PolicyCache_Deferred: +525μs mean, **4,751μs max** (9× mean)
- Combined worst case: **~6.4ms**

**Frame Time Comparison:**
| Metric | Master | ProcessEconomy |
|--------|--------|----------------|
| GameFrame mean | 571μs | 527μs (**PE faster**) |
| Sim::GameFrame mean | 720μs | 690μs (**PE faster**) |

### Revised Understanding

The problem is **not throughput**—it's **variance causing frame spikes**:

```
Mean overhead per frame: (206 + 525) / 30 ≈ 24μs  ← Acceptable
Worst-case spike: 6,400μs                          ← Causes stutters
```

SlowUpdate frames with bad variance can take 6+ milliseconds of economy processing, causing visible hitches even when average performance is good.

---

## Evidence: Tracy Frame Analysis

The blocking hypothesis has been tested using Tracy profiling.

### Build for Profiling

```bash
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON
```

### Key Zones Measured

| Zone | What It Measures | Jaedrik's Result |
|------|-----------------|------------------|
| `ProcessEconomy` | Total C++ time blocked waiting for Lua | 206μs mean |
| `PE_Lua` | Lua-side processing time | 169μs (82% of PE) |
| `PE_PolicyCache_Deferred` | Deferred policy cache update | 525μs mean, 4.75ms max |

### The Smoking Gun

`PE_Lua / ProcessEconomy = 82%` → C++ is blocked during Lua execution.

However, the **overall frame impact is minimal** because:
1. ProcessEconomy runs only every 30 frames (SlowUpdate)
2. Amortized cost: ~24μs per frame
3. Master branch's native sharing has comparable overhead

### The Real Problem: Variance

```
ProcessEconomy max/mean ratio: 7.9×
PE_PolicyCache_Deferred max/mean ratio: 9.0×
```

Bad frames can spike to **6+ milliseconds** of economy processing.

---

## Revised Goal: Reduce Variance, Not Mean Throughput

Since mean throughput is acceptable, the goal shifts to **reducing frame spikes**.

### Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| ProcessEconomy mean | 206μs | — (acceptable) |
| ProcessEconomy max | 1,620μs | < 500μs |
| PE_PolicyCache_Deferred max | 4,751μs | < 1,000μs |
| Combined worst case | 6,400μs | < 1,500μs |

---

## Root Cause Analysis: Why the Variance?

### PE_PolicyCache_Deferred (Biggest Offender)

- **Max/Mean ratio: 9.0×**
- Runs at `game_resource_transfer_controller.lua:191`
- **Confirmed O(n²)**: Nested loop over all team pairs in `UpdatePolicyCache`
- For 16 teams: 256 pairs × 2 resources = 512 policy calculations per SlowUpdate

### GC Correlation: CONFIRMED ✅

Comparing GC spikes between branches:

| Metric | ProcessEconomy | Master | Δ |
|--------|----------------|--------|---|
| CollectGarbage mean | 158μs | 147μs | +7% |
| **CollectGarbage max** | **16,240μs** | **4,397μs** | **+269%** |

**PE has 3.7× higher GC spikes!** The policy cache updates allocate objects that trigger expensive garbage collection during SlowUpdate frames.

### Allocation Sources in UpdatePolicyCache

```lua
for _, senderID in ipairs(allTeams) do
  for _, receiverID in ipairs(allTeams) do
    local ctx = contextFactory.policy(...)  -- allocation
    local metalPolicy = resultFactory(...)   -- allocation
    local energyPolicy = resultFactory(...)  -- allocation
    -- 3 allocations × 256 pairs = 768 allocations per SlowUpdate
  end
end
```

### WaterfillSolver

- **Max/Mean ratio: 5.5×** (784μs max / 141μs mean)
- Lower variance than PolicyCache
- Already has C++ implementation available
- Variance likely from iteration count, not GC

---

## Proposed Fixes: Variance Reduction

### Current Flow

```
Frame N SlowUpdate:
├─ Collect team data (C++)
├─ Call ProcessEconomy(Lua)     ← 206μs mean, 1.6ms worst
├─ PE_PolicyCache_Deferred      ← 525μs mean, 4.75ms worst  ← BIGGEST SPIKE
├─ Apply Lua results (C++)
└─ Continue frame

Total worst case: ~6.4ms (causes visible stutter)
```

### Target Flow (Variance-Bounded)

```
Frame N SlowUpdate:
├─ Collect team data (C++)
├─ Call ProcessEconomy(Lua)     ← bounded to <500μs
├─ Staggered PolicyCache        ← only update 1/N teams, <100μs
├─ Apply Lua results (C++)
└─ Continue frame

Total worst case: <1.5ms (smooth)
```

### Implementation Options

#### Option A: Stagger PolicyCache Updates (Low Effort, High Impact)

Instead of updating all team policies every SlowUpdate:

1. Divide teams into N groups
2. Update 1 group per SlowUpdate
3. Full refresh every N×30 frames

**Pros**: Dramatically reduces per-frame work, simple change
**Cons**: Slightly stale policy data (acceptable for 30-frame cycles)
**Expected impact**: Reduces PE_PolicyCache_Deferred from 525μs to ~50μs mean

#### Option B: Move PolicyCache to C++ (Medium Effort)

1. Implement policy lookup in C++ (simple team→team share ratio map)
2. Keep Lua for policy configuration/UI only
3. C++ updates cache incrementally

**Pros**: Eliminates Lua overhead for hot path
**Cons**: More engine code, policy logic duplication

#### Option C: Bound Iteration Counts (Quick Fix)

1. Add early-exit conditions to waterfill solver
2. Cap maximum iterations per frame
3. Spread remaining work across multiple frames

**Pros**: Guarantees max frame time
**Cons**: Economy updates may take multiple frames to settle

#### Option D: Profile-Guided Optimization

1. Add Tracy zones inside PE_PolicyCache_Deferred
2. Identify which operations cause 9× variance
3. Optimize or batch those specific operations

**Pros**: Data-driven fixes
**Cons**: Requires more profiling

#### ~~Option E: Async ProcessEconomy~~ (Deprioritized)

Originally proposed to fix blocking overhead. Now deprioritized because:
- Mean blocking time is acceptable (~24μs amortized)
- Variance is the actual issue
- Async adds complexity without addressing root cause

---

## Engine-Side Solutions (Recoil Changes)

If Lua-side fixes aren't sufficient, these engine changes could help:

### Engine Option 1: C++ Policy Orchestrator

Instead of Lua maintaining the n² cache, the engine provides a policy configuration API:

```cpp
// Lua configures rules (rare, on policy change)
Spring.ConfigurePolicyRule({
  senderPattern = "ally",     -- "ally", "enemy", "all", or teamID
  receiverPattern = "ally",
  resourceType = "metal",
  canShare = true,
  taxRate = 0.1,
  threshold = 100
})

// Engine maintains the n² cache internally
// Lua queries via existing GetCachedPolicy (no change)
```

**Pros**: Zero Lua overhead for cache maintenance
**Cons**: Policy logic must be expressible declaratively

### Engine Option 2: Incremental/Dirty-Flag Cache

Engine tracks which pairs need recalculation:

```cpp
// When share level changes, engine marks pair dirty
Spring.SetTeamShareLevel(teamID, resource, level)  // auto-marks dirty

// Lua only updates dirty pairs
local dirtyPairs = Spring.GetDirtyPolicyPairs()
for _, pair in ipairs(dirtyPairs) do
  -- Calculate and cache only this pair
end
Spring.ClearDirtyPolicyPairs()
```

**Pros**: O(k) where k = changed pairs
**Cons**: In a flow-based economy k still trends toward n² because any
policy depends on global sender/receiver state (income, storage, share
levels, stalls). Change tracking is mostly as expensive as recompute.

### Engine Option 3: Batch SetCachedPolicy API

Reduce Lua↔C++ boundary crossings:

```cpp
// Instead of 512 individual SetCachedPolicy calls:
Spring.SetCachedPoliciesBatch({
  {sender=1, receiver=2, metal={...}, energy={...}},
  {sender=1, receiver=3, metal={...}, energy={...}},
  -- ...
})
```

**Pros**: Single C++ call for all policies
**Cons**: Still O(n²) work, but eliminates call overhead

### Engine Option 4: Native Policy Calculator

Move the policy calculation itself to C++:

```cpp
// Lua registers a policy formula once
Spring.RegisterPolicyFormula("resource_transfer", {
  canShare = "receiver.shareSlider > 0 AND sender.current > sender.storage * 0.9",
  taxRate = "0.1",
  threshold = "sender.shareSlider * sender.storage"
})

// Engine evaluates formula for all pairs in C++
// Results available via GetCachedPolicy
```

**Pros**: Eliminates all Lua overhead for policy calculation
**Cons**: Significant engine complexity, DSL design needed

Worth mentioning for completeness but extreme. A less DSL-heavy variant is native
behavior modules (Recoil-only rules engine) that keep behavior in engine code.
That still creates a serious con: behavior becomes engine-specific, harder to
iterate, and unmaintainable for mods. The policy logic is BAR-specific and changes
frequently - encoding it in C++ or a DSL trades Lua's 1ms overhead for months of
engine-side maintenance burden.

The ThreadPool async pattern (see below) is more practical if C++ ownership is
acceptable.

---

## Specific Timing Windows in Frame Lifecycle

The frame lifecycle has these relevant phases:

```cpp
// CGame::SimFrame()
├─ HandleEvents()           // Input processing
├─ SimulateFrame()          // Main simulation
│   ├─ UnitHandler::Update()
│   ├─ ProjectileHandler::Update()
│   └─ TeamHandler::SlowUpdate() ← ProcessEconomy called here
├─ LuaHandle::GameFrame()   // Lua callins
└─ Networking
```

### Safe Windows for Async Economy

At first glance, economy could run in parallel during:
- `UnitHandler::Update()` (unit movement/combat)
- `ProjectileHandler::Update()` (projectile physics)

**Problem**: Units consume resources during `UnitHandler::Update()` (cloaking,
construction, regeneration). Economy calculation depends on resource state that's
being mutated by unit updates. There's no clean "safe window" - economy reads
the same data units write.

The economy results would need to be ready before:
- Next SlowUpdate applies resource changes
- UI queries resource values (can tolerate 1-frame stale data)

### Recoil's Existing ThreadPool

The engine has a ThreadPool (`rts/System/Threading/ThreadPool.h`) already used in
synced sim code:

```cpp
// Fire-and-forget async with future
auto fut = ThreadPool::Enqueue([&]() { return HeavyCalculation(); });
// ... other work ...
auto result = fut.get();  // blocks if not done

// Parallel iteration (already used in LosHandler, UnitHandler)
for_mt(0, items.size(), [&](int i) { ProcessItem(i); });

// ITaskGroup::WaitFor(spring_time) provides timeout-based blocking
```

Existing usage in synced sim:
- `LosHandler::Update()` uses `for_mt` for raycast terrain
- `UnitHandler::SlowUpdateUnits()` uses `for_mt` for bounding volume updates
- `UnitHandler::UpdateUnitWeapons()` uses `for_mt_chunk`

**The catch**: ProcessEconomy is a *Lua callin*, and Lua must run on the sim
thread for determinism. The ThreadPool is for C++ work only. To use async
economy, the calculation would need to be fully C++ (Engine Option 4 territory).

A hypothetical async economy pattern would look like:

```cpp
// Early in SimFrame (before unitHandler.Update())
auto economyFuture = ThreadPool::Enqueue([&]() {
    return CalculateEconomyInCpp();  // pure C++, deterministic
});

// ... unitHandler.Update(), projectileHandler.Update() ...

// Before teamHandler.GameFrame()
if (!economyFuture.wait_for(500us)) {
    LOG_L(L_ERROR, "Economy calculation timeout!");
}
auto result = economyFuture.get();
ApplyEconomyResult(result);
```

This requires moving economy logic from Lua to C++, which is a significant
refactor but would enable true parallel execution. The ThreadPool machinery
is already there and battle-tested in the sim.

**Reality check**: Moving to C++ means capturing modoptions in engine config,
which defeats the purpose. The flexibility of Lua (iterate on policy logic
without engine rebuilds, mod-specific behaviors) is why it's in Lua. The
ThreadPool doesn't help us unless we're willing to give that up.

**Conclusion**: Economy stays in Lua, on the sim thread, where it is. Focus
optimization efforts on Lua-side efficiency (table pooling, caching, reducing
n² work) rather than threading.

---

## Verification Checklist

After implementing variance reduction fixes, verify with Tracy:

- [ ] `ProcessEconomy` max < 500μs (was 1,620μs)
- [ ] `PE_PolicyCache_Deferred` max < 1,000μs (was 4,751μs)
- [ ] Max/Mean ratio < 3× for economy zones (was 7-9×)
- [ ] No visible stuttering on SlowUpdate frames
- [ ] Economy updates still correct (test sharing behaviors)
- [ ] No desync issues in multiplayer (economy must be deterministic)

---

## Quick Tracy Test Commands

For the user with Tracy compiled at `~/code/tracy-0.11.1`:

```bash
# Terminal 1: Start Tracy profiler
cd ~/code/tracy-0.11.1 && ./tracy

# Terminal 2: Run game with Tracy-enabled engine
cd /path/to/game && ./spring-tracy --headless replay.sdfz
```

See `tracy_analysis_guide.md` for detailed capture instructions.

---

## Related Documents

- [tracy_analysis_guide.md](tracy_analysis_guide.md) - Detailed profiling workflow
- [optimizations_plan.md](optimizations_plan.md) - Already-implemented Lua optimizations
- [cpp_waterfill_service.md](cpp_waterfill_service.md) - C++ solver implementation
