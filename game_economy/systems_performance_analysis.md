# Economy Resolution: PE vs RE Performance Comparison

## Introduction

We want to move BAR's economy resolution (excess resource sharing) from the engine into game-controlled Lua. There are two proposed approaches for how the engine communicates with the Lua solver. To compare them fairly, we built two engine branches with identical Tracy instrumentation running the same Lua waterfill algorithm.

For background on the Controller architecture and why we're proposing this change, see [Game Controllers & Policies: A New Architecture for Game Behavior](https://github.com/beyond-all-reason/RecoilEngine/issues/2781).

Engine PR: [Game Economy #2664](https://github.com/beyond-all-reason/RecoilEngine/pull/2664)

## Branch Setup

### PE: ProcessEconomy (`eco` branch)

Engine accumulates excess each frame in C++. Once per SlowUpdate (every 30 frames), it builds a Lua table with all team resource snapshots, calls the registered Lua controller via `lua_pcall`, and applies the returned results.

- Engine: [RecoilEngine `eco`](https://github.com/beyond-all-reason/RecoilEngine/tree/eco)
- Worktree: `~/code/RecoilEngine`
- Gadgets: `game_resource_transfer_controller.lua`, `game_unit_transfer_controller.lua`
- Invocation: 1x per SlowUpdate
- Boundary crossings: 2 per invocation (call + return)

### RE: ResourceExcess (`game-economy-re` branch)

Engine fires a `ResourceExcess` event every frame with that frame's per-team excess. Lua receives the excess, queries full team state via Spring API, runs the solver, and applies results via setter calls.

- Engine: [RecoilEngine-RE `game-economy-re`](https://github.com/beyond-all-reason/RecoilEngine/tree/game-economy-re)
- Worktree: `~/code/RecoilEngine-RE`
- Gadgets: `game_re_resource_transfer_controller.lua`, `game_re_unit_transfer_controller.lua`
- Invocation: every frame (up to 30x per SlowUpdate)
- Boundary crossings: O(10N) per invocation (N = active teams)

### Shared

Both paths use the identical Lua waterfill solver (`economy_waterfill_solver.lua`). After data marshaling, the solver inputs are structurally identical. This makes solver time a control variable.

## What We Measured

| Tracy Zone | Branch | What it captures |
|------------|--------|------------------|
| `ProcessEconomy` | PE | Top-level: entire PE economy cycle |
| `PE_AccumulateExcess` | PE | Per-frame excess accumulation into `resDelayedShare` |
| `PE_CppMunge` | PE | C++ building the teams Lua table |
| `PE_CppSetters` | PE | C++ applying returned results to team state |
| `ResourceExcess` | RE | Top-level: entire RE economy cycle |
| `RE_BuildTable` | RE | C++ building the excesses map |
| `RE_LuaTotal` | RE | Lua callin: query + solve + apply |

TracyPlot channels for live correlation with frame time:
- `Economy/TeamCount` -- number of active teams
- `Economy/TotalTime_us` -- total economy time per invocation
- `Economy/SolverTime_us` -- solver-only time per invocation

## Hypothesis

PE invokes the solver once per 30 frames. RE invokes it every frame -- in late game with full storages, potentially all 30 frames per SlowUpdate window.

We expect PE to show lower total economy time per SlowUpdate cycle because it batches work into a single invocation with 2 boundary crossings, while RE pays per-team query and setter overhead on every frame. In an 8v8 game (16 active teams), RE makes roughly 4800 Lua/C++ boundary crossings per SlowUpdate window vs PE's 2.

The data will show whether this holds and by what margin.

## Results

Results are generated from Tracy trace data. See `bar_economy_audit/systems_performance_analysis.qmd` for the interactive analysis -- render with `quarto render systems_performance_analysis.qmd`.

### Economy Time per SlowUpdate Cycle

*Pending data collection. See `.qmd` for chart.*

### Zone Breakdown

*Pending data collection. See `.qmd` for chart.*

### Economy Time vs Frame Time

*Pending data collection. See `.qmd` for chart.*

### Solver Time Comparison

*Pending data collection. See `.qmd` for chart.*

### Cumulative Economy Time

*Pending data collection. See `.qmd` for chart.*

## Conclusion

Pending data collection.

---

## Appendix: Reproduction

### Git Worktrees

```bash
cd ~/code/RecoilEngine
git worktree add ../RecoilEngine-RE game-economy-re

# Directory layout:
# ~/code/RecoilEngine       → eco branch
# ~/code/RecoilEngine-RE    → game-economy-re branch
```

### Build Both Engines

Tracy must be explicitly enabled -- it defaults to OFF.

```bash
# Build PE engine
cd ~/code/RecoilEngine
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON

# Build RE engine
cd ~/code/RecoilEngine-RE
docker-build-v2/build.sh linux -DTRACY_ENABLE=ON
```

### Testing Workflow

Play comparable games (not the same replay -- different engine versions would desync) of at least N minutes with high resource activity (8v8). The tooling syncs up frames and makes statistical comparisons.

```bash
# 1. Test PE build
cd ~/code/Beyond-All-Reason
ln -sf ~/code/RecoilEngine/build-linux local-build
# Play game with Tracy connected → save trace

# 2. Test RE build
ln -sf ~/code/RecoilEngine-RE/build-linux local-build
# Play comparable game with Tracy connected → save trace
```

### Dashboard Integration

Tracy traces are the primary data source for deep comparison. For presentation charts and aggregate stats, parse infolog output through the dashboard:

```bash
cd ~/code/bar_economy_audit
python parser.py ~/path/to/infolog-pe.txt
python parser.py ~/path/to/infolog-re.txt
# Dashboard shows both sessions with comparison overlays
# Export Plotly charts as PNG/HTML for presentations
```

### Files Modified

#### PE Branch (eco)
- `rts/Sim/Misc/TeamHandler.cpp` - removed HandleFrameExcess, simplified to only AccumulateFrameExcess + ProcessEconomy
- `rts/Sim/Misc/TeamHandler.h` - removed HandleFrameExcess declaration
- `rts/Sim/Misc/ModInfo.h` / `.cpp` - removed EconomyAuditMode enum and mode detection
- `rts/Lua/LuaSyncedRead.cpp` / `.h` - removed IsProcessEconomyActive / IsResourceExcessActive
- `rts/Lua/LuaSyncedCtrl.cpp` / `.h` - removed SetResourceExcessController / SolveWaterfill
- `rts/Lua/LuaHandleSynced.cpp` / `.h` - removed ResourceExcess callin and controller registration
- `rts/Lua/LuaConstGame.cpp` - removed Game.economyAuditMode
- `rts/System/EventClient.h` - removed ResourceExcess virtual
- `rts/System/Events.def` - removed ResourceExcess event
- `rts/System/EventHandler.h` / `.cpp` - removed ResourceExcess dispatch
- `rts/Sim/Economy/WaterfillSolver.cpp` / `.h` - deleted (C++ solver removed)
- `rts/Sim/CMakeLists.txt` - removed WaterfillSolver.cpp

#### RE Branch (game-economy-re)
- `rts/Sim/Misc/TeamHandler.cpp` - added ZoneScopedN("ResourceExcess") and ZoneScopedN("RE_BuildTable")
- `rts/Lua/LuaHandleSynced.cpp` - added ZoneScopedN("RE_LuaTotal") to ResourceExcess callin
- `docker-build-v2/build.sh` - fixed git worktree support for Docker builds

#### Lua (Beyond-All-Reason)
- `game_resource_transfer_controller.lua` - PE-only resource controller
- `game_unit_transfer_controller.lua` - PE-only unit transfer controller (unchanged)
- `game_re_resource_transfer_controller.lua` - RE resource controller (new)
- `game_re_unit_transfer_controller.lua` - RE unit transfer controller shim (new)

#### Both Branches (TODO)
- BAR Lua waterfill gadget - add tracy.ZoneBeginN/ZoneEnd calls for Solver and Setters
