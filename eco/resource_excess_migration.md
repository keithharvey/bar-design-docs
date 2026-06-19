# Migrating BAR Distribution off `ProcessEconomy` onto #2642 (`gadget:ResourceExcess`)

## 1. Context & Decision

After a long review thread on [RecoilEngine#2664](https://github.com/beyond-all-reason/RecoilEngine/pull/2664) (the `gameEconomy` modrule + `ProcessEconomy` controller), the outcome with sprunk is:

- **Drop the `gameEconomy` modrule.** For distribution-only it isn't justified, and the `SetTeamResource` unclamp it added was a proven no-op (already removed on `eco`).
- **Adopt sprunk's [#2642](https://github.com/beyond-all-reason/RecoilEngine/pull/2642) `gadget:ResourceExcess`** as the distribution hook. Cadence and payload — the only two things `ProcessEconomy` did better — are both solvable game-side in a few lines each.
- **Full game ownership of the economy** (production/consumption, not just distribution) remains the eventual goal, but it requires a native **ENTT/ECS** refactor with maintainer buy-in. That is a separate RFC, not this work. See the ECS scope at `~/.claude/plans/wondrous-pondering-cookie.md`. Per-step consumption (nanolathe/weapons) cannot move to interpreted Lua without unacceptable late-game perf cost; ECS is the realistic path.

This doc plans the **near-term BAR refactor**: move the waterfill distribution off `ProcessEconomy`/`SetEconomyController` and onto `gadget:ResourceExcess`. **Implemented.** The engine dependency is now `keithharvey/RecoilEngine` branch **`resource-excess-callin-stats`** — sprunk's `resource-excess-callin` plus one commit re-adding `Spring.AddTeamResourceStats` (see §5.2). BAR-Devtools `repos.local.conf` repointed to it (was `beyond-all-reason resource-excess-callin`, before that `keithharvey eco`).

## 2. The #2642 contract (verified against `resource-excess-callin`)

- `function gadget:ResourceExcess(excesses)` — **synced**, fires **every frame for every team**.
  `excesses[teamID] = { [1] = metalOverflow, [2] = energyOverflow }` (overflow above storage max, accumulated that frame). Source: `CSyncedLuaHandle::ResourceExcess` (LuaHandleSynced.cpp:1230); fired unconditionally from `CTeamHandler::HandleFrameExcess` in `GameFrame` (TeamHandler.cpp:117).
- **Return `true`** → take over: engine skips native buffering. **Return `false`/nil** → engine accumulates the overflow into `resDelayedShare` and shares it natively at slowupdate.
- `CONTROL` callin (`ControlIterateDefFalse`): any gadget returning true takes over. **Single-owner is a game-side convention** (run exactly one) — no engine guard, which sidesteps the bespoke-registration objection from the `eco` design.
- **Engine removes the overflow from the producer.** `AddMetal`/`AddEnergy`/`AddResources` clamp `res` to `resStorage` and accumulate `resExcessThisFrame` (Team.cpp:152-205). So the gadget receives overflow that has **already been deducted** from the producing team; its job is to hand it to recipients.

**Guaranteed cadence: solved.** The callin fires every frame regardless of whether any team overflowed (the map always contains all teams). The earlier worry ("no overflow → no trigger") does not apply to this branch.

## 3. Cadence & payload, game-side

- **Cadence** — rate-limit inside the handler with a frame counter (`frame % 15 == 0`, or whatever the design wants). The every-frame fire guarantees a tick is always available.
- **Payload** — the solver needs `current`/`storage`/`shareSlider` per team plus policy inputs. Get them game-side:
  - `Spring.GetTeamResources(teamID)` → current, storage, pull, income, expense, share.
  - Policy inputs (market building present? tier tax? — see `tech_core`) via existing `GG`/`Spring.GetUnit*` queries.
  - The batched `ProcessEconomy` snapshot is **not needed**. sprunk's salience point holds: a fat payload presumes what matters, but sharing designs vary (e.g., a "market building enables sharing" rule queries units, not a resource snapshot).

## 4. Refactor: `luarules/gadgets/game_resource_transfer_controller.lua`

**Current (`sharing_tab`)** registers `Spring.SetEconomyController({ ProcessEconomy = ... })`; `ProcessEconomy(frame, teams)` receives a batched per-team snapshot, runs `WaterfillSolver.SolveToResults`, applies via `Spring.SetTeamResource` + `Spring.AddTeamResourceStats`.

**New:**
- Remove `Spring.SetEconomyController` and the `ProcessEconomy` function.
- Add `function gadget:ResourceExcess(excesses)`:
  - **Every frame:** add `excesses[teamID][1|2]` into a per-team overflow accumulator; `return true` to own the overflow (so the engine doesn't waste/native-buffer it).
  - **On the cadence tick (`frame % N`):** build the waterfill input from `Spring.GetTeamResources` per team + the accumulated overflow; run the existing `WaterfillSolver`; apply results through existing setters (`Spring.SetTeamResource` for pools; `Spring.AddTeamResource`/`UseTeamResource` or the transfer path for moves); reset the accumulator.
- **Keep** `WaterfillSolver`, `ManualShareLedger`, `ContextFactory`, the policy/tech modules — they're engine-agnostic; only the *data source* changes from the snapshot to game-side queries.
- The tech-tax `AllowUnitBuildStep`/`AllowFeatureBuildStep` handlers are unaffected (already game-side).

## 5. Design decisions (resolved during implementation)

1. **Overflow-only vs. proactive share-slider equalization → (b) proactive equalization.** #2642 exposes only *overflow* (resources already over storage max), but the native path we're replacing — `CTeam::SlowUpdate`, gated by `modInfo.nativeExcessSharing` (BAR sets it **false**) — shares *everything above* `shareCursor = storage * shareSlider`, and the existing waterfill solver already reproduces that. Overflow-only (a) would silently drop the share slider's auto-sharing of stored resources — a gameplay regression. So the gadget queries `GetTeamResources` per team each cadence tick, injects the accumulated overflow as the snapshot's `excess`, and runs the unchanged solver. The data source moved game-side; the solver and its conservation tests are untouched.
2. **Stats attribution → re-add `AddTeamResourceStats` (small engine fork).** `Spring.AddTeamResourceStats` is absent on `resource-excess-callin`. The `sharing_tab` UI reads *native* stats (`GetTeamResources[7,8]` = `resPrevSent`/`resPrevReceived`; `GetTeamStatsHistory` for lifetime `metalSent`/`metalExcess`/…) — there is no new GG-based sharing widget. Keeping the tested solver + `SetTeamResource` (absolute pools) + `AddTeamResourceStats` (stats) is the smallest faithful change, so the one-function stats API was ported from `eco` onto the `resource-excess-callin-stats` fork. (New finding the doc didn't have: `Spring.ShareTeamResource` *does* track sent/received natively on this branch, but it can only move resources already in a team's pool — not the held overflow the engine deducted pre-callin — so it can't carry the absolute-set solver output without a net→pairwise + tax-burn rewrite. The fork was the cleaner path.)
3. **Single-owner → game-side, no engine guard.** Exactly one gadget (`game_resource_transfer_controller`) registers `ResourceExcess` and returns `true`.

**Cadence & timing.** `CADENCE = 30` (= `TEAM_SLOWUPDATE_RATE`), matching the native rate. The solve + apply + stats run entirely inside `gadget:ResourceExcess` (which fires in `HandleFrameExcess`, *before* `ResetResourceState` in the same slowupdate frame) — so our `resSent`/`resReceived` writes are rolled into `resPrevSent`/`resPrevReceived`, exactly the fields `GetTeamResources` returns, and the current frame's overflow is captured in the same tick (a `GameFrame`-based split would miss it, since `eventHandler.GameFrame` runs before `teamHandler.GameFrame`). Net effect: stats are correct and ~one slowupdate *fresher* than native (no one-period display lag). The enable gate changed from `Game.gameEconomy == true` to `Game.nativeExcessSharing == false`.

**Policy cache (folded in).** The deferred `ProcessEconomy` policy machinery (`pendingPolicyUpdate`/`DeferredPolicyUpdate`/`POLICY_UPDATE_RATE`) was removed. The per-team factor cache (O(teams); lazy pair reconstruction in `GetCachedPolicyResult`) is rebuilt on the **cadence tick**, in the same pass as the waterfill, reading post-redistribution currents.

## 6. Engine branch (`resource-excess-callin`) changes

- **None required** for cadence — it already fires every frame (verified).
- **One change made (§5.2):** ported `Spring.AddTeamResourceStats` from `eco` onto a `keithharvey/RecoilEngine` fork branch **`resource-excess-callin-stats`** (impl + `REGISTER_LUA_CFUNC` + header decl in `LuaSyncedCtrl`). All `CTeam` members it touches (`resSent`, `resReceived`, `resPrevExcess`, `GetCurrentStats()`) exist on this branch, so it is a faithful cherry of working code.
- `repos.local.conf` repointed `RecoilEngine` → `keithharvey/RecoilEngine.git resource-excess-callin-stats`. Note BAR-Devtools sync only fetches (no reset/auto-checkout), so `~/code/RecoilEngine` must be checked out on that branch before building.

## 7. Cleanup of the abandoned `gameEconomy` path

- **BAR (`sharing_tab`):** done — removed `ProcessEconomy`/`SetEconomyController` and the `gameEconomy` modrule (`modrules.lua`) + modoption (spec builder), and the `GameEconomyController`/`ProcessEconomy` `types/Spring.lua` defs. `AddTeamResourceStats` (Spring def, GG usage, spec mock) is **kept** per §5.2.
- **Engine `eco` (PR 2664):** **superseded** now that the BAR refactor has landed on `resource-excess-callin-stats`. Close the PR (or leave it dormant for already-opted-in games — low value, per the discord); the `gameEconomy` modrule + `ProcessEconomy`/`SetEconomyController` controller it added are no longer used by BAR.

## 8. Verification

- BAR busted green: `lx --lua-version 5.1 test`.
- In-game via BAR-Devtools (now building `resource-excess-callin`): overflow redistributes to allies on the chosen cadence; native waste is suppressed while the gadget owns `ResourceExcess`; sharing UI stats correct; tech-tax + market-building policy still drive sharing.

## 9. References

- Controller/Policy architecture: [`game_economy/explain_policies.md`](../game_economy/explain_policies.md)
- Market building / sharing policy: [`game_economy/tech_core_plan.md`](../game_economy/tech_core_plan.md)
- Full-ownership ECS RFC (future): `~/.claude/plans/wondrous-pondering-cookie.md`
- #2642 branch: `beyond-all-reason/RecoilEngine` `resource-excess-callin`; BAR builds against the fork `keithharvey/RecoilEngine` `resource-excess-callin-stats` (= #2642 + `AddTeamResourceStats`)
- Abandoned modrule PR: RecoilEngine#2664 (`eco`)
