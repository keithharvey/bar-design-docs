# Hypothesis: ProcessEconomy Blocking Is the Performance Problem

## The Problem

The ProcessEconomy system shows a ~33% performance drop on lower-end machines. The hypothesis is simple: **the engine blocks during Lua execution**.

When the engine calls into Lua for ProcessEconomy, it:
1. Stops the C++ simulation frame
2. Marshals team data from C++ → Lua tables
3. Waits for Lua to execute the waterfill solver
4. Marshals results from Lua tables → C++ team state
5. Only then continues with the rest of the frame

This blocking round-trip is the suspected bottleneck.

---

## How to PROVE the Blocking Hypothesis

### Method 1: Tracy Frame Analysis

Using Tracy, we can measure the exact duration of the blocking call:

1. **Build with detailed Tracy zones**:
   ```bash
   docker-build-v2/build.sh linux -DTRACY_ENABLE=ON -DTRACY_ON_DEMAND=ON -DRECOIL_DETAILED_TRACY_ZONING=ON
   ```

2. **Look for these zones in Tracy**:
   | Zone | What It Measures |
   |------|-----------------|
   | `SlowUpdate::ProcessEconomy` | Total C++ time blocked waiting for Lua |
   | `PE_Lua` | Lua-side processing time |
   | `LuaSyncedCall` | Lua↔C++ boundary crossing overhead |

3. **The smoking gun**: If `SlowUpdate::ProcessEconomy` duration ≈ `PE_Lua` duration, then C++ is fully blocked during Lua execution. There's no parallelism.

### Method 2: Compare SlowUpdate Timing

Compare frame timing with ProcessEconomy enabled vs disabled:

| Scenario | Expected SlowUpdate Duration |
|----------|------------------------------|
| ProcessEconomy OFF (engine native) | Baseline |
| ProcessEconomy ON (Lua solver) | Baseline + Lua execution time |

If the overhead is additive (not overlapping), blocking is confirmed.

### Method 3: Thread Analysis

In Tracy's thread view:
- Look at the main simulation thread during SlowUpdate
- If it shows a single continuous block with no interleaving, the thread is blocked
- No work is happening in parallel on the main thread

---

## What "Not Blocking" Would Look Like

If we fixed the blocking issue, we'd expect:
- C++ could continue processing non-economy work while Lua calculates
- The Lua result would be applied at the start of the next SlowUpdate
- One-frame latency in economy updates (acceptable for a 30-frame-per-second update cycle)

---

## Proposed Fix: Async ProcessEconomy

### Current Flow (Blocking)

```
Frame N SlowUpdate:
├─ Collect team data (C++)
├─ Call ProcessEconomy(Lua) ← BLOCKS HERE
├─ Wait for Lua to finish ← NO WORK DONE
├─ Apply Lua results (C++)
└─ Continue frame
```

### Proposed Flow (Non-Blocking)

```
Frame N SlowUpdate:
├─ Apply results from Frame N-1 (if ready)
├─ Start async: Collect team data → queue for Lua
├─ Continue with other SlowUpdate work (doesn't need economy)
└─ Lua processes in parallel (or deferred)

Frame N+1 SlowUpdate:
├─ Check if Lua result ready
├─ Apply economy updates
└─ ...
```

### Implementation Options

#### Option A: Deferred Lua Execution (Simplest)

1. During SlowUpdate, collect team data into a snapshot
2. Schedule Lua ProcessEconomy to run AFTER SlowUpdate completes
3. Apply results at the START of next SlowUpdate

**Pros**: Minimal engine changes
**Cons**: One-frame latency in economy updates

#### Option B: Separate Lua State Thread

1. Create a dedicated thread for economy Lua execution
2. Main thread continues while economy calculates
3. Sync results at frame boundary

**Pros**: True parallelism
**Cons**: Significant engine complexity, sync issues

#### Option C: Move Solver to C++

1. Keep Lua for configuration/policy only
2. Move the hot waterfill loop to C++ (already done with SolveWaterfill)
3. Reduce Lua boundary crossings to minimum

**Pros**: Best performance
**Cons**: Already partially implemented, need to measure remaining overhead

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

The economy calculation could safely run in parallel during:
- `UnitHandler::Update()` (unit movement/combat)
- `ProjectileHandler::Update()` (projectile physics)
- Rendering (unsynced, but could overlap)

The economy results just need to be ready before:
- Next SlowUpdate applies resource changes
- UI queries resource values (can tolerate 1-frame stale data)

---

## Verification Checklist

After implementing a fix, verify with Tracy:

- [ ] `SlowUpdate` duration decreases by ~`PE_Lua` time
- [ ] Economy updates still arrive correctly (1 frame delayed is OK)
- [ ] No desync issues in multiplayer (economy must be deterministic)
- [ ] Memory usage stable (no accumulating queued snapshots)

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
