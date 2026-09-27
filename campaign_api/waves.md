# Waves & Scavengers — two modules on top of cm8-ashfall

Plan for implementation. Written 2026-07-31 against the working checkout
(`cm8-ashfall`, tip `b93c7ad7cd`).

## Context

CM8 Ashfall (`b93c7ad7cd`, tip of `cm8-ashfall`) plays as a static roster: the enemy
spawns once and waits. The mission's own `victory.lua` names the gap — "the raptor
waves wait on their modules." Meanwhile the base game's wave machinery is two
near-identical 2,500+ line monoliths (`scav_spawner_defense.lua`,
`raptor_spawner_defense.lua`, ~70% line-identical modulo naming) with no API, enabled
only by LuaAI-team presence. `module_breakdown.md` already called this extraction
"ai_director — biggest extraction in the set; schedule after the pattern is proven."
The pattern is now proven (nine modules on this stack), and the open naming question
is answered: **waves**.

The plan: a generic **waves** module (director machinery extracted from the scav
spawner) and a **scavengers** module on top (rosters, flavor, the multiplayer mode as
a `Mode("Scavengers")` preset). CM8 gains scav-flavored wave pressure through new
mission vocabulary. Raptors stays untouched — porting it later is the
second-consumer proof.

Decisions already made (2026-07-31):
1. **Hybrid extraction** — rewrite the orchestration as pure spec'd lib; port leaf
   mechanics (placement, drain, squad AI) near-verbatim behind seams.
2. **Replace scav, leave raptor** — the scavengers commit deletes
   `scav_spawner_defense.lua` (transfer-commit precedent); raptor files untouched.
3. **CM8's enemy is scavengers** — the mission exercises both new modules.
4. **Mode preset + AI team** — `Mode("Scavengers")` serializes the existing `scav_*`
   modoptions wire-compatibly; the lobby still adds the ScavengersAI bot; the gadget's
   activation predicate stays `IsScavengers() and not IsRaptors()`. The mode is a
   serializer and a lobby instruction, never a new wire key.

## The shape

**waves** is the genre engine: anger clocks, the archetype cooldown wheel, squad
composition, burrow/boss lifecycle, spawn drain, squad AI. **scavengers** is a flavor
pack: plain-data rosters, a spec builder turning modoptions into a `WaveSpec`, and the
scav-only mechanics (scum capture, boss stagger/resistance, commanders, minions). The
seam is one plain table — the `WaveSpec` — plus optional named hooks. The waves gadget
hosts **1..n directors keyed by name** (unique name + unique rulesParam prefix), so the
multiplayer mode and a mission's scripted pressure are the same machinery at different
intensities.

The hybrid rule maps onto directories: `lib/` is rewritten, pure, busted-spec'd;
`spring/` is ported leaf code touching Spring, included only by the gadget.

```
modules/waves/
  module.lua                  -- { name = "waves", requires = { "context" } }
  api.lua                     -- stateless forwarder over GG.Waves (combat style)
  types/waves.lua             -- WaveSpec, WaveDirectorState, WaveShape, WaveOrder, ...
  lib/anger.lua               -- PURE: techAnger 0-999 / bossAnger 0-100 / wave-size envelope
  lib/wheel.lua               -- PURE: 8-counter archetype wheel -> WaveShape (rng injected)
  lib/composer.lua            -- PURE: anger-bracketed weighted squad selection -> WavePlan
  lib/difficulty.lua          -- PURE: dynamic-difficulty clamp; endless NextCycle(params) -> new table
  lib/boss.lua                -- PURE: spawn decision, HP scaling, multi-boss counting
  lib/scheduler.lua           -- PURE: cadence brain -> WaveOrder[] (gadget is a dumb executor)
  lib/director.lua            -- PURE: Director.New(spec)/Tick(world); world injected, spec'd end-to-end
  lib/mission_verbs.lua       -- PURE: the Waves.* trigger vocabulary
  spring/placement.lua        -- PORTED: burrow placement cascade + growing spawn box (globals -> state.spawnBox)
  spring/drain.lua            -- PORTED: spawn-queue pop-every-5-frames + expanding-square probe
  spring/squads.lua           -- PORTED: createSquad/refreshSquad/manageAllSquads/orders/killer loop
  spring/structures.lua       -- PORTED: turret / creep-structure waves
  gadgets/wave_director.lua   -- synced host: directors table, order execution, events, save/load
  mission_dsl.lua  mode_dsl.lua
  spec/  (anger, wheel, composer, difficulty, boss, director, mission_verbs)

modules/scavengers/
  module.lua                  -- { name = "scavengers", requires = { "context", "waves", "combat" } }
  data/                       -- rosters/tiers/squads/commanders/turrets/behaviours/bosses/targets/difficulties
                              --   plain data, unit names as strings, no function calls (spec-enforced)
  lib/defs_build.lua          -- PURE program part: Build(opts) -> exact legacy config shape; FromEngine() adapter
  lib/economy_scale.lua       -- PURE: modoption snapshot -> economyScale
  lib/custom_squads.lua       -- PURE: scavcustomsquad customParams scan (injected UnitDefNames view)
  gadgets/scavengers.lua      -- gate + team discovery, spec build, hooks, GG.Waves.Start, minions loop
  gadgets/scav_capture.lua    -- scum capture -> _scav conversion (own cadence)
  gadgets/scav_boss.lua       -- UnitPreDamaged resistance + stagger bank; hooked only while boss alive
  modoptions.lua              -- the scav_* block moved from root modoptions.lua, byte-identical keys
  mode_dsl.lua  modes/scavengers.lua  mission_dsl.lua  types/  spec/ (+ golden fixtures)
```

Stays where it is (raptors still uses them): `SpawnerEnemyLib.lua`,
`damgam_lib/position_checks.lua`, `GG.PowerLib`, `gamedata/scavengers/*` (purple
`_scav` derivation), all `pve_*` satellite gadgets, both UI panels.

## The WaveSpec seam (abridged)

```lua
{
  name = "scavengers", teamID = <discovered>, rulesParamPrefix = "scav",  -- "scav" reproduces legacy params byte-for-byte
  params = { gracePeriod, bossTime, spawnRate, minWaveSize, maxWaveSize, economyScale,
             perPlayerMultiplier, endless, dynamicDifficulty = {min=0.85,max=1.05}, ... },  -- NUMBERS, precomputed
  buckets = { basicLand = { {minAnger, maxAnger, weight, units={{def="corak_scav",count=6}}}, ... }, ... },
  populations = { commanders = {...}, decoyCommanders = {...} },
  burrows = { defs = {"scavbeacon_t1_scav",...}, placement = "initialbox", ... },
  structures = {...} | nil,    boss = { defName, count, minHealthFraction } | nil,
  aggression = { burrowKilled = 5, ecoPenalty = {...} },
  events = { toLuaUI = "ScavEvent", useWaveMsg = true },
  hooks = { surfaceOf, onWaveComposed, onUnitSpawned, onBurrowSpawned, onBossSpawned,
            onBossKilled, onCycleComplete, behaviourOf, targetsOf },   -- all optional; the flavor seam
}
```

Key rules: the spec is **immutable after `Start`** — everything the monolith mutates on
`config` (endless reloop, `maxXP *= 1.01`, the `initialbox_post` flip) becomes
`state.params` / scheduler state (`difficulty.NextCycle` returns a fresh table). The
waves module never reads `Spring.GetModOptions`; def-name→defID resolution happens once
at `Start` into a derived roster index. The composer emits queue entries in the exact
legacy `{burrow, unitName, team, squadID}` shape (+ a `wave` tag) so the ported drain
and squad code consume them untouched.

`GG.Waves` / `api.lua` surface: `Start(spec)`, `Stop(name)`, `IsActive(name)`,
`Status(name)` → `{techAnger, bossAnger, waveNumber, wavesCleared, bossesKilled, cycle}`,
`SetIntensity(name, n)` (the mission dial — state, serialized), `Surge(name, overrides?)`.

## Policies — why there are none in v1, and where they arrive

Deliberate, and worth stating: waves ships no `policies/` directory. The in-tree
pipeline is decisions (Gate stages, first non-nil wins), and no waves question has
that shape with more than one live contributor today. "May a wave spawn now?" has one
owner — the scheduler — until matchflow's cinematic flag has consumers; when it does,
`policies/wave_flow.lua` is a natural decision gate. "How big/fast is this wave?" IS
policy-shaped, but as a **modifier fold** (difficulty row × mode dials × dynamic
difficulty × mission intensity — contributions multiply), and PolicyBuilder's fold
ending is framework build-order item 2 in `module_breakdown.md`, unbuilt. Building the
fold ad hoc inside waves would be the "bolt combining onto winner-takes-all later"
trap inverted.

So v1 uses two explicit dials: spec `params` (resolved once at `Start`) and
`SetIntensity` (runtime state, serialized). Both multiply through one point in the
scheduler, so when the fold ending lands, `policies/wave_scale.lua` absorbs all four
contributors and `SetIntensity` becomes a policy registration — a contained upgrade,
named here so nobody mistakes the dials for the final shape.

## Squad AI — waves, not an ai module (yet)

Squad AI stays in waves for this stack. It is the back half of the wave lifecycle,
not a separable brain: squads are born from the spawn drain's batch boundaries, their
lifetime is measured in waves (`squadLife` decrements per wave; 0 → self-destruct —
the anti-stalemate mechanism), and targets come from the director's aggression
bookkeeping. Cutting a module seam through the middle of ported code is the riskiest
possible place for one, and a waves module whose units stand around is not
independently shippable.

The future owner is the campaign's `Tact.*` layer (escort/retreat/route scripting —
`module_breakdown.md` lumped "waves/tactics" together in ai_director). That module
earns existence when missions want to order *non-wave* units; waves then becomes its
first consumer and `spring/squads.lua` lifts out — the same "decide when there's a
second consumer" rule applied to economy/sharing. The discipline enforced now so the
lift stays cheap: `squads.lua` takes plain squad state plus injected providers
(`behaviourOf`, `targetsOf` — already WaveSpec hooks) and never reads director
internals.

## Mission vocabulary

Four new members of the closed `MissionEventName` alias
(`modules/missions/types/missions.lua`): `"waves.wave_spawned"`, `"waves.wave_cleared"`,
`"waves.boss_spawned"`, `"waves.boss_defeated"`. Plumbing: `GG.Missions` exposes
`OnEvent` (same convention `mission.objective_changed` already uses internally); the
waves gadget notifies it when present. `MissionContext` gains a waves facet
(`StartWaves/StopWaves/SetWaveIntensity/SurgeWaves/WaveStatus`) via
`ModuleHandler.Get("waves")`, following the existing Transfer/Protect precedent in
`mission_loader.lua`. `modules/missions/module.lua` requires gains `"waves"` and
`"scavengers"` — the whitelist rule is the entire authorization story.

Mission files pick **packs** (flavor-module nouns) and turn dials; composition is
defined once in the flavor module, not per mission (`Waves.Define` with ad-hoc
composition is deliberately not v1). `scavengers/mission_dsl.lua` contributes
`Scavengers.Skirmish / Assault / Horde` pack refs. CM8's new trigger file
(`modules/missions/cm8_ashfall/triggers/waves.lua`):

```lua
When(MatchFlow.Started())
    .Do(Waves.Begin(Scavengers.Skirmish).Against(Team.Player).From(0.85, 0.15).Intensity(0.3))

When(Objective("relieve_the_outpost").IsComplete())
    .Do(Waves.Intensify(Scavengers.Skirmish, 0.6))

When(Objective("find_the_enclave").IsComplete())
    .Do(Waves.Surge(Scavengers.Skirmish))
    .Do(Waves.Intensify(Scavengers.Skirmish, 1.0))

When(Objective("kill_the_commander").IsComplete())
    .Do(Waves.End(Scavengers.Skirmish))
```

Conditions: `Waves.Spawned/Cleared/BossDefeated(pack)` — inputs are the new bus events,
evaluated against monotonic `Status` counters (latched). "Wave cleared" is new but
cheap: tag spawns with wave number, count down in `UnitDestroyed`.

## The mode

`waves/mode_dsl.lua` ships a generic PvE grammar factory —
`Pve.SerializersFor(keys)` + `Pve.Verbs` (`Difficulty/Boss/Grace/Pace/Endless/
Placement`) — parameterized by wire-key names, so raptors can bind `raptor_*` later.
`scavengers/mode_dsl.lua` binds it to `scav_difficulty`, `scav_boss_count`,
`scav_bosstimemult`, `scav_graceperiodmult`, `scav_spawntimemult`,
`scav_spawncountmult`, `scav_endless`, `scav_scavstart`. The preset:

```lua
return Mode("Scavengers")
    .Desc("Hold out against the scavenger swarm, then kill the boss.")
    .Difficulty(Scavengers.Horde, "normal").Unlocked()
    .Boss(Scavengers.Horde, 1)
    .Grace(Scavengers.Horde, 1.0)
    .Pace(Scavengers.Horde, 1.0, 1.0)
    .Placement(Scavengers.Horde, "initialbox")
    .Endless(Scavengers.Horde, false).Unlocked()
```

**Enablement, resolved:** no new modoption. Bot presence stays the runtime activation
predicate (existing SPADS lobbies keep working unchanged); the mode's exported JSON
(`export_game_modes.lua`) is what tells the lobby to pin the dials **and field the
ScavengersAI bot**. CM8's mission director binds through `GG.Waves.Start` directly —
no `IsScavengers()` gate on that path.

## State & savegame

Per director, one plain serializable table (`WaveDirectorState`): anger block (the
integrals — aggression, eco value — force saving the whole block), wheel counters,
`timeOfLastWave`, `waveNumber`, `intensity`, mutable `params` copy (endless cycle, XP
drift), `spawnQueue`, `squads` + unit→squad index, `burrows`, `spawnBox`, `bossState`,
`waveAlive` counters, and a `specRef` (`{module, builder, overrides}`) — **not the
spec**. On load the named module rebuilds the spec (hooks are code; progress is data)
and state lays over it; unit IDs validated with `Spring.ValidUnitID`. Derived, never
saved: resolved rosters, bucket indexes, world closures, GameRulesParams (republished).

## Commit stack (4 commits on b93c7ad7cd)

### 1. `waves: the director as a library`
Create `modules/waves/` complete (lib + spring ports + gadget + DSLs + specs + types).
The gadget is **inert unless a spec is registered** — no live behavior change;
`scav_spawner_defense.lua` untouched and still live.
Gates: `just bar::units` (anger/wheel/composer/director specs — fixture values computed
from the monolith's formulas, seeded RNG); `emmylua_check -c .emmyrc.json .` (zero new
errors in touched files); `luac5.1 -p` on every new file (distrobox); `just
bar::integrations` green (proves inertness).

### 2. `scavengers: the roster and the difficulty, as data`
Create `modules/scavengers/` data + `lib/defs_build.lua` + golden specs. Rewrite
`luarules/configs/scav_spawn_defs.lua` into a shim:
`return VFS.Include("modules/scavengers/lib/defs_build.lua").FromEngine()` — the 2,971
lines leave, the **old gadget keeps running through the shim**. Golden fixture: capture
the monolith config's return value (normal + epic difficulty) before writing the spec;
`Build(opts)` must deep-equal it. `defs_build` takes injected
`{modOptions, teamList, getTeamLuaAI, unitDefNames, log}` (the old file reads engine
state and `gadget:GetInfo()` at include time — the seams).
Gates: golden spec under busted; `luac5.1 -p` on data files (table constructors, never
local-per-entry — 200-local ceiling); token-equivalence diff of moved tables vs
`git show HEAD~1:luarules/configs/scav_spawn_defs.lua` + bare-reference scan for
orphaned upvalues; in-game scav smoke (old gadget boots via shim, `scavDifficulty`/
`scavGracePeriod` params appear).

### 3. `scavengers: the mode owns the director, and the monolith dies`
Create `gadgets/scavengers.lua` (gate `IsScavengers() and not IsRaptors()` exactly as
today; discover team; `GG.Waves.Start(spec)` with hooks; carries the unsynced
`ScavEvent` AddSyncAction wrapper verbatim from monolith lines 2581–2613),
`scav_capture.lua`, `scav_boss.lua`, mode_dsl + preset, modoptions fragment.
**Delete** `luarules/gadgets/scav_spawner_defense.lua` and the commit-2 shim. Remove
the scav block from root `modoptions.lua` (~726–895, CRLF-safe edit; `ruins`/
`lootboxes` options with `scav_only` items stay — not scav-owned). All satellite
gadgets, UI panels, `teamFunctions.lua`, `luaai.lua`, raptor files: untouched — their
inputs (bot, modoption keys, GameRulesParam names) are unchanged.
Wire contract preserved byte-identically: the 8 `scav_*` option keys/defs/items,
section `scav_defense_options` weight 3, and every GameRulesParam name
(`scavTechAnger`, `scavBossAnger`, `scavBossHealth`, `scavBossStagger*`,
`ScavBossAngerGain_*`, `pveBossInfo`, `BossFightStarted`, `scav_hiveCount`,
`scavKills`, `scavBossesKilled`, ...).
Gates: parity specs (endless reloop, stagger machine, composition at fixed anger);
token-equivalence + bare-reference scan on leaf ports vs
`git show HEAD~1:luarules/gadgets/scav_spawner_defense.lua` (the monolith's ~109 shared
upvalues are the hazard — every one threaded explicitly or it silently reads nil);
modoption wire diff (merged option set before/after, position-independent);
`luac5.1 -p` per new file; headless scav smoke via new
`tools/headless_testing/startscript_scav_smoke.txt` (ScavengersAI team, FixedRNGSeed,
`runtestsheadless scavengers`) + `luaui/Tests/scavengers/test_wave_spawns.lua`
(self-skips when not scav); `just bar::integrations` green.

### 4. `missions: CM8 Ashfall under pressure`
`modules/missions/module.lua` requires += `waves`, `scavengers`. New MissionEventName
entries + `GG.Missions.OnEvent` + ctx waves facet in `mission_loader.lua`. New
`cm8_ashfall/triggers/waves.lua` (above). `luaui/Tests/cm8_ashfall/test_waves.lua` in
the hello_pawns pattern (`luarules mission cm8_ashfall`, fast-forward, assert hostile
wave units + director rulesparams) — runs in the **standard** headless suite, no bot
needed, proving the mission path is bot-free.
Gates: busted (trigger file loads through the DSL env; pack names resolve),
`emmylua_check`, `just bar::integrations` (the CM8 waves test is the automated smoke),
manual dev-launch `/mission load cm8_ashfall`.

## Parity risk register (fate of every at-risk behavior)

Preserved-by-port: endless reloop, capture + decay, boss stagger/resistance +
`pveBossInfo`, XP assignment (PowerLib), per-difficulty bossName + boss count,
placement cascades + startbox growth + scum checks, ScavEvent notifications,
commander/decoy population caps, spawn CEGs (`scav_spawn_effect.lua` is ungated —
free for CM8 too), mixed-raptor self-disable.
Reimplemented (golden-spec'd): per-player spawn multipliers + humanTeamCount scan
(gaia off-by-one is the classic trap), economyScale formula, anger/aggression gain
curves, endless NextCycle as pure function.
Deliberate changes, called out for playtest review: composer's 1000-iteration
rejection sampling becomes an honest weighted pick over bracket-filtered candidates
(distribution-equivalent in the common case); dead `scav_swarmmode` key not
resurrected; dynamic difficulty stays scav-only via `params.dynamicDifficulty`.

## Hazards

- **CRLF everywhere** — never `sed -i`; Edit tool or byte-preserving python.
- **VFS rescan** — new `modules/waves|scavengers/` dirs need an engine restart, not
  `/luarules reload`; testers restart per commit.
- **200-local ceiling** — monolith's synced scope holds ~109 live locals; the file
  split is the guard, `luac5.1 -p` the gate.
- **No AI attribution in commits** (house rule for this stack).
- Headless scav scenario wiring into `just bar::integrations` is a **BAR-Devtools
  follow-up** (parameterize the startscript); until then the manual `spring-headless
  --isolation` invocation documented in commit 3 is the gate.
- Follow-ups named, not done here: raptors onto waves (kills the ~70% duplication),
  collapse the two 450-line stats panels via `rulesParamPrefix`, mode `.Uses`
  integration when `mode_as_configuration_root.md` lands, `policies/wave_scale.lua`
  once the fold ending exists, `Tact.*`/tactics module lifting `spring/squads.lua`
  out when missions need to command non-wave units.

## Verification (end-to-end)

Per commit: `just bar::units` · `emmylua_check -c .emmyrc.json .` (zero new errors in
touched files) · `luac5.1 -p` on new in-engine files · `just bar::integrations`.
Cutover extras: token-equivalence + bare-reference scans, modoption wire diff, headless
scav smoke. Final proof: dev launch with a ScavengersAI bot + the Scavengers mode
preset → waves/boss/UI panels behave as live; then `/mission load cm8_ashfall` →
skirmish pressure from the northeast, intensifying per objective, ending when the
commander dies.
