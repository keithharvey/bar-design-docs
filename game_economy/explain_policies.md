# Game Controllers & Policies: A New Architecture for Game Behavior

## Introduction

Right now, the gadget system provides hooks for unit and resource transfers. Games *can* take full control of these subsystems—nothing in the engine prevents it. But there's no shared infrastructure for doing so cleanly. Each game that wants declarative, testable transfer logic has to reinvent the wheel.

I started my discovery process trying to remove the `capture` parameter from the `AllowUnitTransfer` hook, and to move `/take` out of the engine. Pretty quickly I asked the question:

> Why does the engine care about these transfers at all? Why does the synced layer, which owns the configuration and domain logic, not just tell the engine what to do so we can modularize this subsystem?

The answer for why we prefer per-team gadget hooks is mostly because it offers granular control to gadgets, and gadgets are a production-tested framework for devs to control game behavior.

But what if, when a behavioral subsystem called for it and that part of the sim DID belong entirely to the game, we had a different pattern? One where the game is assumed to control the state of that subsystem entirely?

### A Note on Scope: Now vs. Next

This document presents **two iterations** of this architecture:

1.  **Now** (`sharing_tab` branch): A working implementation using Controller gadgets and PolicyResult caching. This is what I'm proposing we merge.
2.  **Next** (prototyped in a separate worktree): A more ambitious DSL-based policy engine that the "Now" architecture directly enables.

I'll walk through the "Now" implementation in detail, then show a glimpse of "Next" to demonstrate where this pattern leads.

### UX Goals
* **Cardinal mod options**: Each mod option does exactly 1 functional game behavior. No "Nuclear Options" or "Easy Sharing Tax" that incorporate multiple surprising behaviors. Instead: "Unit Sharing Mode", "Tax Rate", "Ally Assist Mode", etc.
* **Sharing modes exist** [PR](https://github.com/beyond-all-reason/BYAR-Chobby/pull/1041): Can disable, hide, lock, and show specific mod options with declarative configuration. This preserves the ability for devs to name their modes while still preserving the cardinality of mod options.

### Architecture Goals
* **Synced domain layer**: Declarative, [idempotent](https://en.wikipedia.org/wiki/Idempotence), centralized behavior logic.
* **Performance**: Optimized Lua algorithms for redistribution (Waterfill), with optional C++ acceleration.
* **Testability**: Logic that can be tested without running the game.

### A Word on the Implementation

This branch is a stepping stone. I originally built a more complete framework, realized it was too big a leap, and backported the core patterns without the scaffolding. You'll see functions treated as atomic units with full EmmyLua decorators—this is intentional. When you're not sure where code will live long-term, portability matters.

The goal here is singular: **provide infrastructure that makes game-owned subsystems easy**. The game *can* already own subsystems—this PR provides the patterns, caching, and tested code to do it well. The "used once" value objects and explicit typing may look over-engineered for what's merged today, but they're load-bearing for what comes next.

---

## 1. The Existing System: "The Spaghetti"

The existing gadget system is powerful and flexible. Games *can* bypass the default hooks entirely. But if you use the hooks as intended, you end up with implicit coordination between gadgets that's hard to reason about and impossible to test in isolation.

```mermaid
flowchart TB
    subgraph Existing["Existing: Engine-Controlled"]
        E1[Engine]
        GH[GadgetHandler]
        G1[Gadget A]
        G2[Gadget B]
        UI[Unsynced UI]
        BL_S[Business Logic]
        BL_U[Business Logic]
        
        E1 -->|calls| GH
        GH <-->|hook + allow/deny| G1
        GH <-->|hook + allow/deny| G2
        G1 <-.->|coordinate via<br/>globals/state| G2
        G1 --> BL_S
        G2 --> BL_S
        
        UI <-->|ShareResources +<br/>query state| E1
        BL_S -.->|duplicated| BL_U
        BL_U --> UI
    end
```

### The "Loop of Death"
In the current system, a simple resource transfer request travels through a perilous journey of hooks, return values, and side effects.

```mermaid
sequenceDiagram
    participant UI as Unsynced UI
    participant Eng as Engine
    participant GH as GadgetHandler
    participant G1 as Gadget A
    participant G2 as Gadget B

    UI->>Eng: ShareResources(Team A -> B)
    Eng->>GH: AllowResourceTransfer?
    GH->>G1: AllowResourceTransfer?
    G1->>G2: (Implicit Coupling via Globals)
    G1-->>GH: true
    GH->>G2: AllowResourceTransfer?
    G2-->>GH: true
    GH-->>Eng: true
    Eng->>Eng: Execute Transfer
```

### Problems
1.  **Loop-back pattern**: `AllowResourceShare` returns to caller; order of gadget execution matters.
2.  **Gadget coupling**: Gadgets must know about each other to coordinate policies.
3.  **Duplicated logic**: UI and gadgets both implement "can share?" checks.
4.  **Untestable**: You cannot test `Gadget A` without running `Spring`, `Gadget B`, and `UI`.

---

## 2. The Solution: Controllers & Policies

To solve this, we invert the control. We introduce a **[Service Layer](https://en.wikipedia.org/wiki/Service_layer_pattern)** (Controllers) and a **[Strategy Pattern](https://en.wikipedia.org/wiki/Strategy_pattern)** (Policies).

### The Service Layer (Controllers)
Instead of the engine asking "Can I do this?", the game tells the engine "Do this." The game owns the logic; the engine executes the mutations.

The goal is to route all economy operations through the controller: gadgets call `GG.Function` instead of engine APIs directly. `GG.Function` → Controller → Engine. This gives us a centralized place for cache updates, policy evaluation, and eventually an economy state machine if we add native modules.

We add a switch `modInfo.game_economy = true`. When enabled, the engine delegates economy resolution to a synced gadget via [`Spring.SetEconomyController`](https://github.com/keithharvey/bar/blob/sharing_tab/luarules/gadgets/game_resource_transfer_controller.lua#L350).

### The Strategy Pattern (Policies)
Because the game controls execution, it can expose that execution to "policies" as swappable components.

```mermaid
flowchart LR
    subgraph Inputs
        ModOpts((Mod Options))
        Context[Team Context<br/>resources, storage,<br/>allied status]
    end
    
    subgraph Policy["Policy Function (Strategy)"]
        Calc[Calculate<br/>PolicyResult]
    end
    
    subgraph Output["PolicyResult (ViewModel)"]
        Result[canShare<br/>amountSendable<br/>amountReceivable<br/>taxedPortion<br/>untaxedPortion]
    end
    
    subgraph Consumers
        Cache[(TeamRulesParam<br/>Cache)]
        Gadgets[Other Gadgets]
        UI[Unsynced UI]
    end
    
    ModOpts --> Calc
    Context --> Calc
    Calc --> Result
    Result --> Cache
    Cache --> Gadgets
    Cache --> UI
```

A **Policy** is a [pure function](https://en.wikipedia.org/wiki/Pure_function). Given mod options and team context, it produces a `PolicyResult`. This result is cached in `TeamRulesParams` and acts as a **[ViewModel](https://en.wikipedia.org/wiki/Model%E2%80%93view%E2%80%93viewmodel)** for the UI. The UI never calculates business logic; it just reads the cached policy.

### Dynamic Behavior

Because policies are just functions, they can incorporate runtime state—not just static mod options. Want sharing to unlock when both players build a storage building? That's a policy that checks game state. Want tax rates to scale with game time? That's a policy too.

The architecture enables this today. We don't have concrete examples in the `sharing_tab` branch yet, but the "Next" section (Section 6) shows what this looks like with the DSL: policies like `building_unlocks_sharing.lua` that gate behavior on predicates like `hasBothStorages()`.

---

## 3. Deep Dive: A Policy In Action

Let's look at the actual tax policy from the `sharing_tab` branch.

**[resource_transfer_synced.lua](https://github.com/keithharvey/bar/blob/sharing_tab/common/luaUtilities/team_transfer/resource_transfer_synced.lua)** — The core policy logic.

```lua
---@param ctx PolicyContext
---@param resourceType ResourceType
---@return ResourcePolicyResult
local function calcResourcePolicyResult(ctx, resourceType)
  local receiverCapacity = receiverData.storage - receiverData.current
  local cumulativeSent = Shared.GetCumulativeSent(ctx.senderTeamId, resourceType, ctx.springRepo)
  local threshold = getThreshold(resourceType)
  local allowanceRemaining = math.max(0, threshold - cumulativeSent)
  local senderBudget = math.max(0, senderData.current)

  local untaxedPortion = math.min(allowanceRemaining, senderBudget)
  local effectiveRate = (taxRate < 1) and taxRate or 1
  local taxedSendable = math.max(0, (senderBudget - untaxedPortion) * (1 - effectiveRate))

  return {
    canShare = receiverCapacity > 0 and amountSendable > 0,
    amountSendable = amountSendable,
    taxedPortion = taxedPortion,
    untaxedPortion = untaxedPortion,
    taxRate = effectiveRate,
    -- ... other fields
  }
end
```

This is a **pure function**. It takes context, returns a result. No side effects, no engine calls, no global state mutation. This is the core insight: *the policy doesn't do the transfer, it describes the boundaries of what a transfer can be*.

### The Waterfill Solver

One major concern with moving logic to Lua is performance. Resource sharing involves solving a "Waterfill" problem (distributing excess resources fairly) across all allied teams every `SlowUpdate`.

**[economy_waterfill_solver.lua](https://github.com/keithharvey/bar/blob/sharing_tab/common/luaUtilities/economy/economy_waterfill_solver.lua)** — The algorithm.

The solver is implemented in optimized Lua 5.1. While we are bound by the runtime, we have structured the data flow to be efficient using [object pooling](https://en.wikipedia.org/wiki/Object_pool_pattern) and cache-friendly iteration. Tracy results are promising—SlowUpdate is a little faster in the new branch.

```mermaid
sequenceDiagram
    participant Engine
    participant LuaCtrl as GameResourceController
    participant Solver as Waterfill Solver
    participant Teams as Team Handler

    Engine->>LuaCtrl: ProcessEconomy(frame)
    LuaCtrl->>Solver: Solve(teamData)
    Note over Solver: Lua (or C++ if available)
    Solver-->>LuaCtrl: Results (Transfers)
    LuaCtrl->>Teams: Apply Transfers
```

Because it's a pure function, we can test it in isolation. Here's an actual test from **[game_resource_transfer_controller_spec.lua](https://github.com/keithharvey/bar/blob/sharing_tab/spec/luarules/gadgets/game_resource_transfer_controller_spec.lua)**:

```lua
it("balances metal between teams without tax", function()
  local teamA = Builders.Team:new()
    :WithMetal(800)
    :WithMetalStorage(1000)
    :WithMetalShareSlider(50)
  local teamB = Builders.Team:new()
    :WithMetal(200)
    :WithMetalStorage(1000)
    :WithMetalShareSlider(50)

  normalizeAllies({ teamA, teamB }, teamA.allyTeam)

  local spring = buildSpring({ taxRate = 0 }, { teamA, teamB })
  local teamsList = buildTeamsTable({ teamA, teamB })
  
  local results = WaterfillSolver.SolveToResults(spring, teamsList)
  
  -- ... extract teamAMetal, teamBMetal from results ...
  
  assert.is_near(500, teamAMetal.current, 0.1)
  assert.is_near(500, teamBMetal.current, 0.1)
  assert.is_near(300, teamAMetal.sent, 0.1)
  assert.is_near(300, teamBMetal.received, 0.1)
end)
```

The test uses builder patterns to construct mock Spring state, then asserts on the solver's pure output. No engine required.

---

## 4. The Controller: ProcessEconomy

The controller is the glue. It's called by the engine every `SlowUpdate` and orchestrates two distinct phases:

**[game_resource_transfer_controller.lua](https://github.com/keithharvey/bar/blob/sharing_tab/luarules/gadgets/game_resource_transfer_controller.lua#L176)**

```lua
---@param frame number
---@param teams table<number, TeamResourceData>
---@return EconomyTeamResult[]
local function ProcessEconomy(frame, teams)
  -- ...
  
  -- Step 1: Solve redistribution (the math)
  local results = WaterfillSolver.SolveToResults(springRepo, teams)
  
  -- Step 2: Flag policy cache for deferred update
  pendingPolicyUpdate = true
  pendingPolicyFrame = frame
  
  return results
end

local function DeferredPolicyUpdate()
  if not pendingPolicyUpdate then return end
  pendingPolicyUpdate = false
  
  -- ...
  lastPolicyUpdate = ResourceTransfer.UpdatePolicyCache(
    springRepo, pendingPolicyFrame, lastPolicyUpdate, POLICY_UPDATE_RATE, contextFactory
  )
end
```

**Step 1** (Waterfill) runs in the hot path and returns results to the engine immediately.
**Step 2** (Policy Cache) is deferred to `GameFrame` to avoid blocking.

---

## 5. Comparison Summary

```mermaid
flowchart TB
    subgraph Existing["Existing: Bidirectional Everywhere"]
        E1[Engine]
        S1[Synced]
        U1[Unsynced]
        
        E1 <-->|hooks| S1
        E1 <-->|commands +<br/>query state| U1
        S1 -.->|duplicated logic| U1
    end
    
    subgraph New["New: Synced as Single Authority"]
        E2[Engine]
        S2[Synced]
        C2[(Cache)]
        U2[Unsynced]
        
        S2 -->|commands| E2
        S2 -->|publish| C2
        C2 -->|read only| U2
        U2 -->|user intent| S2
    end
```

### Benefits of the New Architecture
1.  **[Inversion of Control](https://en.wikipedia.org/wiki/Inversion_of_control)**: Engine calls Controller, not gadgets intercepting engine.
2.  **[Single Source of Truth](https://en.wikipedia.org/wiki/Single_source_of_truth)**: Policy cache is read by all consumers.
3.  **Decoupled Gadgets**: Other gadgets query cache, they don't fight each other.
4.  **Performance**: Optimized Lua with optional C++ acceleration.
5.  **Quality Assurance**: Fully unit-testable Lua logic.

---

## 6. The Future: A Policy DSL

The `sharing_tab` branch establishes the foundation. But the architecture unlocks something more powerful: a **declarative [DSL](https://en.wikipedia.org/wiki/Domain-specific_language)** (Domain-Specific Language) for defining game policies.

In a separate prototype, I've explored what this looks like. Here's the same tax policy, reimagined:

```lua
---@param builder DSL
local function buildPolicy(builder)
  local taxRate = builder.mod_options[ModOptions.TaxResourceSharingAmount] or 0

  builder:Allied():MetalTransfers():Use(function(ctx)
    return calcResourcePolicyResult(ctx, ResourceType.METAL)
  end)

  builder:Allied():EnergyTransfers():Use(function(ctx)
    return calcResourcePolicyResult(ctx, ResourceType.ENERGY)
  end)

  builder:RegisterPostMetalTransfer(function(transferResult, springRepo)
    -- Track cumulative sent for tax-free threshold
    local current = springRepo:GetTeamRulesParam(transferResult.senderTeamId, cumMetal) or 0
    springRepo:SetTeamRulesParam(transferResult.senderTeamId, cumMetal, current + transferResult.sent)
  end)
end
```

The DSL provides:
*   **[Fluent API](https://en.wikipedia.org/wiki/Fluent_interface)**: `builder:Allied():MetalTransfers():Use(...)`
*   **Declarative intent**: Read what the policy *means*, not how it's wired.
*   **Composability**: Policies are independent modules; the engine composes them.
*   **Shared Infrastructure**: Common functionality (caching, validation, logging) lives in one place, not copy-pasted across gadgets.
*   **Low Barrier to Entry**: Adding a new policy is trivial. Intellisense guides you, the DSL constrains you to valid patterns, and you only worry about *your* policy—not the plumbing. Senior devs build the rails; junior devs ship features.

### Dynamic Behavior: Building Unlocks Sharing

This is where it gets exciting. Imagine a mod option where you can only share resources *after building specific structures*:

```lua
---@param builder DSL
local function policyFunction(builder)
    local function hasBothStorages(ctx)
        return hasBuiltCategories(ctx.senderTeamId, {
            BuildingCategories.METAL_STORAGE,
            BuildingCategories.ENERGY_STORAGE
        }, ctx.repositories.springRepo)
    end

    local function hasPinpointer(ctx)
        return hasBuiltCategories(ctx.senderTeamId, {
            BuildingCategories.PINPOINTER,
        }, ctx.repositories.springRepo)
    end

    builder:MetalTransfers():When(hasBothStorages):Allow()
    builder:EnergyTransfers():When(hasBothStorages):Allow()
    builder:UnitTransfers():When(hasPinpointer):Allow()
end
```

This is **game design expressed as code**. No engine changes required. No hook ordering nightmares. Just declare what you want.

### Potential File Layout

```
luarules/modules/
├── policy_engine.lua           # Shared rule pipeline (AST-like)
├── dsl.lua                     # Shared fluent builder API
│
├── team_transfer/              # Economy & sharing module
│   ├── controller.lua
│   ├── policies/
│   │   ├── tax_resource_sharing.lua
│   │   ├── building_unlocks_sharing.lua
│   │   ├── allied_assist.lua
│   │   └── unit_sharing_mode.lua
│   ├── actions/
│   └── default_results/
│
└── combat/                     # Hypothetical combat module
    ├── controller.lua
    ├── policies/
    │   ├── friendly_fire.lua
    │   ├── capture_rules.lua
    │   └── unit_veterancy.lua
    ├── actions/
    └── default_results/
```

The `policy_engine` and `dsl` are shared infrastructure. Each domain module (team_transfer, combat, etc.) brings its own controller, policies, and default results—but they all compose through the same pipeline.

### How Policies Compose

Each policy file uses the DSL to declare rules. The DSL registers those rules with the policy engine. At runtime, the controller asks the engine to evaluate a context, and the engine runs through all registered rules to produce a result.

```mermaid
flowchart LR
    subgraph Policies["Policy Files"]
        P1[tax_resource_sharing.lua]
        P2[building_unlocks.lua]
        P3[allied_assist.lua]
    end
    
    subgraph DSL["DSL Layer"]
        Builder[builder:Allied<br/>:MetalTransfers<br/>:Use/Allow/Deny]
    end
    
    subgraph Engine["Policy Engine"]
        Rules[(Registered Rules)]
        Eval[Evaluate Context]
    end
    
    subgraph Runtime["Runtime"]
        Ctrl[Controller]
        Result[PolicyResult]
    end
    
    P1 --> Builder
    P2 --> Builder
    P3 --> Builder
    Builder -->|registers| Rules
    Ctrl -->|context| Eval
    Rules --> Eval
    Eval --> Result
```

Each policy only knows about the DSL. The engine handles composition, ordering, and conflict resolution. Policies don't know about each other—they just declare what they care about.

### A Note on Lua 5.1 Performance

The architect-minded among you may be thinking: *"Isn't Lua 5.1 insanely slow? Don't design patterns thrash the GC because you can't build tables without pooling everything?"*

Yes. Yes it is.

The current implementation works around this with aggressive [object pooling](https://en.wikipedia.org/wiki/Object_pool_pattern) and cache-friendly iteration. But the architecture is intentionally designed to be *runtime-agnostic*. If we later transpile these modules to native code (via LLVM or similar), or port to a language with proper value types, the policy/controller separation still holds. The abstractions pay for themselves twice: once in testability today, once in portability tomorrow.

Taken further: native modules could enable Recoil to split into **core** (minimal simulation substrate) and **optional modules** (game behavior). The same pattern we're using here—swappable policies composed by a shared engine—could apply at the engine level. Recoil core handles physics, rendering, networking. Game modules handle economy, combat rules, unit transfers. Each game chooses which modules to load. BAR ships its opinionated defaults; other games swap in their own.

### High Level Orchestration

Because the module owns the policies, it can also orchestrate them—introducing dependencies between policies, composing outputs, or applying middleware-style transformations. That's a topic for a future doc.

---

## 7. Conclusion: Why This Matters

This isn't just about resource sharing. It's about establishing a pattern for how the game can own its own behavior.

The engine is a powerful simulation substrate. It doesn't need to know about "tax rates" or "unit stun durations" or "building unlock requirements." Those are *game design decisions*. They should live in the game.

What we're proposing:
1.  **The Sharing Tab PR (BAR-only)**: Controller pattern, PolicyResult caching, testable Lua logic. Works today by hooking `GameFrame`.
2.  **Engine changes (Recoil PR)**: A `ProcessEconomy` callback that formalizes the IoC pattern. This requires buy-in but isn't blocking—we can keep hooking `GameFrame` if needed.
3.  **Future PRs**: DSL, policy engine, more subsystems migrated to game control.

Resource Transfers, Unit Transfers, Combat behavior—each of these could follow the same pattern. The game owns the logic; the engine provides the simulation substrate.

**The game should be in charge of the game.**

---

## Reference: Key Files in `sharing_tab`

| File | Purpose |
|------|---------|
| [BAR PR - The Sharing Tab](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5704) | Game-side implementation (works standalone via GameFrame hooks) |
| [Recoil PR - Game Economy](https://github.com/beyond-all-reason/RecoilEngine/pull/2664) | Proposed engine changes (ProcessEconomy callback—optional but better long-term) |
| [game_resource_transfer_controller.lua](https://github.com/keithharvey/bar/blob/sharing_tab/luarules/gadgets/game_resource_transfer_controller.lua) | Main controller gadget |
| [resource_transfer_synced.lua](https://github.com/keithharvey/bar/blob/sharing_tab/common/luaUtilities/team_transfer/resource_transfer_synced.lua) | Policy calculation logic |
| [economy_waterfill_solver.lua](https://github.com/keithharvey/bar/blob/sharing_tab/common/luaUtilities/economy/economy_waterfill_solver.lua) | Redistribution algorithm |
| [game_resource_transfer_controller_spec.lua](https://github.com/keithharvey/bar/blob/sharing_tab/spec/luarules/gadgets/game_resource_transfer_controller_spec.lua) | Unit tests |