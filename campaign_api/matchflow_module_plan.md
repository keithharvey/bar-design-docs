# MatchFlow Module Plan

A small, isolated exemplar of the modules format built against master: the match-lifecycle domain (game over, victory/defeat, pause) refactored into `modules/matchflow/`. Chosen as the second exemplar because it is the smallest domain with a real policy surface, it un-stubs four CampaignAPI actions (`victory`, `defeat`, `pause`, `unpause`), and its current implementation is the clearest in-repo demonstration of the failure mode modules fix.

## Why this domain

The stub list in Mission API PR #8226 is the requirements list for domain modules: every implemented action is a thin engine wrapper; every `yet_to_implement` stub is stubbed because the behavior is owned by base-game gadgets with no API to call. MatchFlow covers the game-flow slice of that list at roughly a quarter of the surface of Construction or Combat, and nobody is territorial about game_end.

The current landscape is organizational momentum around the only design pattern the codebase had for a decade — gadgets coordinating through the engine, GG, and modoption strings. Not wrong for its era; it just has no way to express "this mode/faction/mission wants to bend this decision" except forking the decision.

## Current state (the evidence)

`luarules/gadgets/game_end.lua` (574 lines) is three tangled responsibilities:

1. **Liveness tracking** — `allyTeamInfos` bookkeeping: controlled/resigned state, grace periods, AI-host tracking, decoration-unit counting, the savegame-load 30-frame hack. State maintenance, not decision-making.
2. **The end-condition decision** — `CheckSingleAllyVictoryEnd` vs `CheckSharedAllyVictoryEnd`, selected by `sharedDynamicAllianceVictory` and `fixedallies` modoptions. `deathmode == "neverend"` is handled by the gadget removing itself in `Initialize` — mode variation expressed as gadget suicide.
3. **Outcome ceremony** — global LOS reveal for winners, delayed `Spring.GameOver`, commander dance animation, scenario stats handoff. Effects, not decisions.

Satellite gadgets that fork or defensively duplicate the decision:

- `game_territorial_domination.lua` — a second end-condition living as a parallel gadget, guarded by `deathmode ~= "territorial_domination"`; coordinates with game_end by modoption string only.
- `mo_ffa.lua:67` — *"ensure the wipeout is initiated (for some reason game_end doesnt kill the allyteam I think)"* — a mode gadget re-doing the base gadget's job because no coordination contract exists. This comment is the one-slide justification for the module.
- `mo_battle_royale.lua`, `raptor_spawner_defense.lua`, `scav_spawner_defense.lua` — independent `GameOver` hooks; meanwhile game_end special-cases Raptors/Scavengers by string-matching the LuaAI name (`luaAI:find("Raptors")`) — faction knowledge hardcoded in the base gadget, the inverse of factions registering their own exemption.
- The scenario/mission path is wedged in as `scenariooptions` conditionals in both the synced and unsynced halves of game_end — exactly the flag-setting CampaignAPI would do through a module API instead.

## Target shape

```
modules/matchflow/
  module.lua                     -- manifest: name, provides, requires
  api.lua                        -- contract (or provides = {shared/synced/unsynced})
  gadgets/
    game_end.lua                 -- slimmed: liveness events + ceremony, decision delegated
  policies/
    game_over/
      010_neverend.lua           -- deathmode == neverend => never ends (one line)
      020_territorial_domination.lua
      030_mission_override.lua   -- CampaignAPI's scripted outcome flag
      100_compute_last_ally_standing.lua  -- terminal: single/shared-alliance checks
  lib/
    liveness.lua                 -- allyTeamInfos tracking extracted from game_end
    ceremony.lua                 -- LOS reveal, delayed GameOver, commander dance
  spec/
    game_over_spec.lua           -- busted specs for the pipeline + liveness edges
  modoptions.lua                 -- deathmode fragment, if we take that step
```

### The decision surface

One policy signature, evaluated on the module's cadence (mirroring game_end's current every-15/30-frames check):

```lua
---@param liveness MatchLiveness  -- read-only view of allyTeamInfos
---@return GameOverVerdict|nil    -- nil = no opinion, defer to later stages
```

`GameOverVerdict` carries winners (allyTeamID list) and a reason tag. First non-nil wins; `100_compute_last_ally_standing` always returns (possibly a "still playing" sentinel — decide during implementation whether nil-all-the-way or an explicit continue verdict reads better; the sharing module precedent prefers explicit).

### API surface (what CampaignAPI orchestrates through)

- `Victory(allyTeamIDs)`, `Defeat(allyTeamIDs)` — push a scripted verdict through the same pipeline (implemented as the mission override policy's input, not as a bypass — everything exits through one control flow).
- `Pause()` / `Unpause()` — thin over engine pause; included for the action stubs, not a design showcase.
- Policy registration via the standard `policies/` directory for in-repo consumers; the API exposes flag-setters for out-of-module orchestrators (missions) rather than arbitrary runtime policy injection.

### What stays out of scope

- Pause plumbing beyond the thin wrapper (`cmd_paused_is_paused.lua` untouched).
- Migrating `mo_ffa`/`mo_battle_royale`/faction gadgets in the first PR — the first PR proves shape-parity with current behavior. Satellite migrations are follow-ups, each a one-file policy registration replacing string matching, and each its own small reviewable PR. List them in the PR description as the roadmap.
- `wipeoutAllyTeam` / team-death effects (`game_team_death_effect.lua`) — stays GG for now; the module consumes it as game_end does today.

## Sequencing

1. **Bootstrap on master.** New module = new files; formatting/typing from birth with zero conflict surface. Extract the minimal loader bootstrap: `modules/module_handler.lua` (+ `policy_builder.lua`, `modules/types/`) cherry-picked/reauthored against master, plus enough emmylua config to check the new directory. Verify typechecking works without the formatting branch before claiming it does. Known risks from the modules branch: synced Lua strips `rawset` (plain assignment in lazy contracts); `_G` absent in unsynced widget sandboxes (CHUNK_ENV getfenv fallback).
2. **Extract liveness** from game_end into `lib/liveness.lua` with specs — pure-ish state machine, the most test-starved and least-understood part (savegame hack, grace periods). Behavior-preserving.
3. **Cut the decision** into the policy pipeline: neverend + the two Check functions. game_end's GameFrame becomes: tick liveness, evaluate pipeline, hand verdict to ceremony.
4. **Ceremony to lib**, gadget becomes a thin event-forwarder living in `modules/matchflow/gadgets/`.
5. **PR it against master** as "The MatchFlow Module" — reviewable on GitHub, no stack archaeology. Target size: loader bootstrap + ~600 lines moved + policies. The diff story is "one gadget refactored, one directory added."
6. **Follow-ups** (separate PRs, each tiny): territorial_domination as a policy; mission override wired to CampaignAPI actions (un-stubs victory/defeat/pause/unpause); faction exemptions replacing LuaAI string matching; mo_ffa's defensive wipeout deleted once the contract exists.

## Risks / open questions

- **Determinism parity**: the end-condition refactor must be bit-identical in behavior for replays/multiplayer; the specs should encode current behavior first (including the weird edges: early-drop grace in FFA, decoration-count team kill, RecvLuaMsg spectator shutdown) before any cleanup.
- **Loader bootstrap size**: if module_handler's master-rebase pulls more than expected (types/ dependencies), consider a matchflow-local trimmed loader as a stopgap — but that weakens the "this is the format" claim; prefer the real loader.
- **Naming**: MatchFlow vs GameFlow vs match_flow directory naming — pick once, it becomes the exemplar convention.
- **game_end removal cases** (sandbox, <2 allyteams) become an early policy or stay as gadget-level guards? Leaning policy (`000_sandbox.lua`) — it's the same "mode variation as gadget suicide" pattern being replaced.
- **Political**: game_end is Floris-era code with real hard-won hacks. The plan deliberately preserves every hack behavior-for-behavior and moves them into named, spec'd locations — the PR description should say so explicitly.

## Relationship to CampaignAPI

The pitch to WtF/Rasoul stays: CampaignAPI becomes an orchestrator, not a parallel implementation. MatchFlow is the proof at minimum viable size — the mission override policy is the pattern for every other domain, and the four un-stubbed actions are the receipts. Construction is the natural third module (alter_buildlist, enable/disable_build_option) once the format has traction; Combat after that, it's the most political.
