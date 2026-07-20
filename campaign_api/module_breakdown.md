# Domain Module Breakdown for the Campaign Requirements

Mapping the campaign team's requirements doc ("BAR Campaign", Mission API
section + weather/asset sections) onto domain modules: what each module owns,
what its PolicyResult shapes look like, and the dependency chains between them.

The requirements doc is big: ~90 triggers and several hundred actions (shaped
like the StarCraft 2 editor), including a `Wave.*` AI scripting layer, mass
runtime changes to unit stats, difficulty variants, and state that persists
across missions. You can't build that as a pile of wrappers around engine
calls — at this scale CampaignAPI has to drive base-game systems that expose
real control points. The doc's own margin notes agree: several AI/eco entries
say "probably handled by missionapi". The ownership question keeps coming up
because the codebase has never had a pattern to answer it with.

## Two kinds of PolicyResult

The requirements need two different answer shapes from policies, and the
sharing/matchflow pipelines have only needed the first so far:

1. **Decisions** — one winner. Policies are asked in order, the first one with
   an opinion wins, and a final catch-all always answers. "Is the game over?"
   "Is this build option visible?" One question, one answer.
2. **Modifiers** — everyone contributes and the results combine. Weather says
   solar +100%, difficulty says all income ×1.2, a mission adds its own tweak —
   all three apply at once. Unit stat changes, income multipliers, vision
   ranges all work this way.

PolicyBuilder currently only does decisions, so it needs a second ending for
combined results (a "fold": multiply the numbers, AND the booleans, merge the
tables — each category says which). Worth building early: bolting combining
onto a winner-takes-all system later is the painful direction.

```lua
---Decision pipeline: first non-nil verdict wins.
---@generic V
---@alias DecisionPolicy fun(ctx): V|nil

---Modifier pipeline: every stage contributes; category declares the fold.
---@alias ModifierPolicy fun(ctx): table|nil  -- partial deltas, folded per-field
```

## Performance model: pipelines are not hot paths

The rule that makes combat (and everything else) feasible in Lua: **policies
run when something changes, hot callins read precomputed answers.** Damage
callins (`UnitPreDamaged`, `AllowWeaponTarget`) fire thousands of times per
second in a big fight; running policy code there would drown in table
allocation. But every source that changes the answers — weather starting, a
cutscene toggling, a mission marking a unit invulnerable — changes rarely, on
human timescales. So when a source registers or updates, the pipeline re-runs
once and writes flat lookup tables (`damageMult[unitID] = 0.5`,
`untargetable[unitID] = true`). The hot callin is one table index and a
multiply — no policy code, no allocation.

Three supporting rules:

- **Don't hook what you don't use.** Expensive callins are only installed when
  a policy is actually registered (the gadget handler already supports this).
  A normal multiplayer game with no mission and no weather pays nothing.
- **Consolidation beats the status quo.** ~15 gadgets each hooking AllowCommand
  today is more per-command overhead than one shared handler with a compiled
  command-ID table.
- **If a rule truly can't be precompiled** (fresh per-event logic per hit),
  the escape hatch is the same pattern one level down: ask the engine for a
  native per-event primitive (Recoil RFC) and keep Lua as the thing that sets
  the rule, not the thing that executes it per event. Taken per-primitive,
  when profiling demands it — not as an architecture decision.

--------------------------------------------------------------------------------

## Module: matchflow

Planned in detail separately (matchflow module plan, posting as its own
PR — it's the first-module exemplar). Doc requirements it
absorbs: Player Victory, Player Defeat, Pause Simulation, Sim Speed 0,
Autosave/Set Checkpoint, "PAUSE GAME FOR MID-MISSION INGAME CUTSCENE" (macro),
"Pause All Movement, Weapon Movement, and Damage Effects".

The cutscene-pause macro isn't purely matchflow's: "pause movement, weapons,
and damage but keep the camera alive" is a matchflow *decision* whose effects
land in other domains — combat turns damage off, movement freezes units.
MatchFlow just owns the flag ("cinematic pause is on"); the other modules have
policies that check it. This is the first real dependency between modules.

```lua
---@class GameOverVerdict
---@field over boolean
---@field winners integer[]      -- allyTeamIDs; empty = draw/shutdown
---@field reason string          -- "last_ally_standing"|"territorial"|"mission_scripted"|...

---@class SimFlowVerdict
---@field paused boolean
---@field simSpeed number|nil
---@field cinematic boolean      -- movement/damage/projectiles frozen, rendering live
```

Consumers day one: deathmode modoptions (neverend, territorial_domination),
faction exemptions (raptors/scavs), mission victory/defeat/pause actions,
cutscene system.

## Module: construction

Doc requirements: Enable/Disable Unit Type, Enable/Disable Build Option, Hide
Build Option (new tech), Darken Build Option, Set Unit Build Quota Target,
Clear (Lab) Build Queue, Difficulty.SetTechRestriction,
AI.SetAllowedTechTier ("handled by missionapi set buildlist stuff" — the doc
already routes this here), Construction Progress % trigger, Build Power Sum.

The question is always "can this team build this unit right now", asked in two
places: when the build menu draws its buttons (unsynced, cosmetic) and when a
build order actually enters the simulation (synced, enforced):

```lua
---@class BuildAccessVerdict
---@field allowed boolean
---@field visibility "shown"|"darkened"|"hidden"  -- doc asks for all three states
---@field reason string|nil                        -- surfaced in UI tooltip

---@alias BuildAccessPolicy fun(teamID, unitDefID): BuildAccessVerdict|nil
```

A decision pipeline, asked in order: mission overrides (scripted tech
unlocks), difficulty tech restrictions, modoption unit restrictions, faction
gating, then a catch-all "allowed". The three visibility states are why a
simple true/false in a rulesparam isn't enough: "darkened" (like sea units on
land maps) and "hidden" (tech the mission hasn't revealed yet) are promises to
the UI, so the module provides both a synced part (is it allowed) and an
unsynced part (how to show it).

**Blocking new orders isn't enough.** New build orders come in three ways, and
the verdict checks all three: factory queues, constructor build commands
(buildings outside factories, via AllowCommand), and `AllowUnitCreation` for
units spawned directly by Lua. But when an option gets disabled mid-game, the
module also has to clean up what already exists: remove it from factory
queues, cancel constructor commands pointing at it, and deal with any
half-built nanoframes on the ground. What happens to those nanoframes — finish
building, freeze, or self-destruct with a refund — is itself a policy, because
different missions genuinely want different answers.

Existing code absorbed: scattered `AllowUnitCreation`-adjacent checks,
modoption restriction preprocessing. Consumers: missions, difficulty,
modoptions, tweaks, AI (tech tiers), blueprints, ruins.

## Module: combat

Doc requirements: Disable/Enable Weapon Damage for select units, Set Unit
Invulnerable/Vulnerable, Set Unit Targetable/Untargetable, Set Unit
Stunned/EMP'd, attack/target slice of command restriction, Apply Area Damage,
Create Explosion at Point, Spawn Weapon, Unit Damaged By Weapon Type trigger.

Two questions with different shapes. "How much damage does this event do" is a
modifier — every source contributes a multiplier and they multiply together,
so "damage disabled" is just a 0 from any source. "Can this unit be targeted"
is a decision (routed through the engine's AllowWeaponTarget):

```lua
---Modifier: contributions multiply; any 0 means damage is off.
---@class DamageDelta
---@field multiplier number|nil
---@field impulseMultiplier number|nil

---Decision: can this unit be shot at?
---@class TargetabilityVerdict
---@field targetable boolean
---@field reason string|nil
```

Cinematic pause is just a combat policy that contributes `multiplier = 0`
while the matchflow flag is on. Making a story unit invulnerable is the same
two pieces — untargetable plus damage ×0 — not a special flag. Consumers:
missions, cutscenes, weather (acid rain, plasma storms), tutorial (safe
zones).

## Module: movement (orders)

Doc requirements: Freeze Command, Disable/Enable Unit Movement, the
move/guard/patrol slice of command restriction, Set Unit Speed Multiplier,
pathfinding-unsuccessful trigger, unit move state changes.

Blocking commands is **framework plumbing, not a module**: one shared
AllowCommand handler that sorts commands by kind and asks the right module —
combat's policies for attack commands, movement's for move/guard/patrol,
construction's for build commands. Today that logic lives in ~15 separate
gadgets that each hook AllowCommand independently; this replaces the pattern
without creating a "permissions module" that every domain would have to reach
into.

```lua
---@class CommandVerdict
---@field allowed boolean
---@field silent boolean|nil     -- deny without UI feedback (cutscene control lock)

---@class SpeedDelta
---@field multiplier number|nil  -- contributions multiply (weather × mission × ...)
```

## Module: attributes (unit runtime state)

Doc requirement, verbatim: "Adjust Unit Attributes ON THE FLY, EASILY,
EN-MASSE. Actually this is just needed for the Campaign (and modding support),
flat-out." Plus Set Unit Health/Experience/Speed, LoS/radar/cloak-cost
adjustments, reload-speed deltas.

The current owner is `unit_attributes.lua` (GG.UpdateUnitAttributes) — already
a stat-modifier system, but callers push values at it and the last caller
wins, so two systems touching the same unit silently fight. The module flips
the direction: each source (weather, the void-storm
distance-from-commander effects, missions, veterancy) registers a policy
saying what it contributes, and the module multiplies them together per unit
and applies the result on its own schedule.

```lua
---@class AttributeDelta            -- all fields optional; contributions multiply
---@field speed number|nil
---@field reload number|nil
---@field losRadius number|nil
---@field radarRadius number|nil
---@field cloakCost number|nil
---@field buildSpeed number|nil

---@alias AttributePolicy fun(unitID, unitDefID, teamID): AttributeDelta|nil
```

This is the cleanest example of combined results in the whole set, and it's
also the campaign team's single loudest ask.

## Module: economy

Doc requirements: Give/take Metal/Energy, Add Metal|Energy/s for Duration,
Eco.SetIncome, Eco.DisableUnitIncome, Difficulty.SetEconomyBonus, resource
stall/excess triggers, weather production effects (Solar +100%, Wind ±,
Tidal -100%, Fusion +100%, Geothermal +X%).

The sharing module already lives in this domain; economy grows beside it (or
absorbs it — decide when there's a second consumer). Income changes combine
per team and per income source:

```lua
---@class IncomeDelta               -- contributions multiply, per income source
---@field solar number|nil
---@field wind number|nil
---@field tidal number|nil
---@field fusion number|nil
---@field geothermal number|nil
---@field mex number|nil
---@field base number|nil           -- catch-all multiplier

---@alias IncomePolicy fun(teamID): IncomeDelta|nil
```

Weather contributes per-source multipliers; difficulty contributes `base` — a
plain flat multiplier (1.1×), deliberately boring. The game already has three
flat income multipliers with three owners: the engine's per-team handicap (the
lobby bonus), the `multiplier_resourceincome`-style modoptions, and the
scaling inside raptor/scav difficulty. They compose today only by accident.
The fold gives that one owner — and where the combined result is a flat
per-team multiplier, the module should apply it by setting the engine's team
income multiplier, keeping the hot path in C++; the per-source fields are the
part the engine knob can't express. One-shot resource grants ("give the player
500 metal") aren't policies at all — they're plain API calls
(`AddTeamResource`) and stay that way.

Side payoff: economy policies plus the sharing module's give/spend decisions
are exactly the control surface co-op and archon-style modes need ("2 players
split one economy", shared-control teams). Those modes become policy
registrations over machinery the campaign requires anyway — no new systems.

## Module: intel (vision/sensors)

Doc requirements: Give Vision X Range for X Seconds, Share Vision Between
Teams, Reveal/Unreveal LOS (the CampaignAPI stubs), Shroud + FoW discussion,
radar-fake weather (Ionization Layer: fake blips, duplicated signatures),
radar range deltas, cloak disable (Ion Storm).

```lua
---Sensor grants: everyone's grants apply at once (combined as a set union).
---Radar is a grant like any other — "layers" says which sensor kinds this
---grant provides (a mission telegraphing a wave grants radar, not vision:
---blips instead of units is the point).
---@class SensorGrant
---@field viewerAllyTeam integer
---@field layers ("los"|"airlos"|"radar"|"sonar")[]
---@field source "global"|"area"|"team_share"
---@field area {x:number, z:number, radius:number}|nil
---@field sharedFromAllyTeam integer|nil
---@field expiresFrame integer|nil

---Sensor changes: multipliers multiply; cloak needs every source to say yes
---(AND); ghost blips appear if any source wants them (OR).
---@class SensorDelta
---@field radarMultiplier number|nil
---@field cloakEnabled boolean|nil
---@field ghostBlips boolean|nil
```

Vision is a third way of combining: nobody's grant cancels anyone else's —
if anything gives you vision of an area, you have it.

## Module: environment (weather/map)

Doc requirements: the entire 17-event weather catalog, Wind Set/Read, Raise/
Lower Terrain or Water Level, Set Lighting/Time of Day, Set Fog/Skybox, lava
tides, frozen-water pathability, meteor/orbital strikes with dodge telegraphs.

Environment mostly *drives other modules* rather than owning decisions of its
own: a weather event is a bundle of contributions to other modules' pipelines
(stat changes into attributes, production changes into economy, radar effects
into intel, damage into combat) plus its own visuals and terrain work. The one
decision it owns is whether an event may start:

```lua
---@class WeatherVerdict            -- decision: may this event start here/now?
---@field allowed boolean
---@field intensity number|nil
---@field areaOverride table|nil
```

The interesting part is the direction of dependence: environment *uses* the
attributes/economy/intel APIs, making it the first module that depends on
several others (a long `requires` list in its manifest). That makes it the
integration test for cross-module dependency — a bad first pick but a great
third one. Several effects (units walking on frozen water, large-scale terrain
deformation, sky/lighting control) need engine support — check those against
RecoilEngine early, before the campaign schedule assumes them.

## Module: ai_director (waves/tactics/difficulty)

Doc requirements: the whole `Wave.*` DSL (define/spawn/route/retreat/escort/
difficulty variants), `Tact.*`, `Difficulty.*` (value, wave count, economy
bonus, tech restriction, APM limit), AI.SetState/Rebuild/etc.

Difficulty is *not* a module — it's a source of policies that plug into
everything else: an income multiplier into economy, tech restrictions into
construction, wave counts here, objective grace into the mission layer. The
doc reached the same conclusion in its margins ("likely could be handled by
missionapi"). The wave system is a real module though, and the existing code
to extract from is the raptor/scav spawners — `*_spawner_defense.lua`, 2500+
lines each of hand-rolled wave logic.

```lua
---@class WaveOrder                 -- decision per wave-slot evaluation
---@field spawn boolean
---@field composition {unitDefID:integer, count:integer}[]
---@field route string|nil          -- named path
---@field target string|nil         -- named region/unit-group
---@field tactics table|nil

---@alias WavePolicy fun(waveDef, gameState): WaveOrder|nil
```

Consumers: raptors, scavs, missions (attack waves), future survival modes.
Biggest extraction cost in the set; schedule after the pattern is proven.

## Module: presentation (unsynced)

Doc requirements: markers, ping/announce, chat/message log, objectives UI,
UI show/hide/flash/glow, tooltip highlights, portraits/transmissions, music/
sounds/ambience/audio filters, camera/turbocam, cutscene letterboxing, fade.

Almost all of this is "do a thing" rather than "decide a thing" — the module
earns its keep by giving scattered widgets one API, not through pipelines. The
one real decision is whether a notification may fire (doc: "Suspend
Notifications") —

```lua
---@class NotificationVerdict       -- decision
---@field allowed boolean
---@field deferUntil number|nil     -- re-emit after cutscene
```

If the camera work grows, split off a cutscene module (camera, control lock,
letterbox, portrait scripting) from presentation (HUD/audio/markers).
Cutscenes are another driver like weather: they flip matchflow's cinematic
pause, lock player control through movement, and letterbox through
presentation.

## Stays in CampaignAPI (mission-internal, no base-game overlap)

The trigger/condition engine (the ~90 trigger list plus AND/OR/NOT, debounce,
random pick), named regions/points/paths/groups/timers, objectives and stages,
campaign persistence (flags, counters, BarDex unlocks, loadout, veterancy
transfer, the mission unlock graph), and *choosing* the difficulty — the
chosen values then flow outward as policies into the modules. This layer
drives every module above and owns none of their decisions.

--------------------------------------------------------------------------------

## Dependency chains

```
framework (module_handler, both pipeline kinds,
           shared AllowCommand/AllowWeaponTarget handlers)
  ├── matchflow          (no module deps; liveness is internal)
  ├── construction       (no module deps)
  ├── attributes         (no module deps)
  ├── economy            (sharing precedent; no hard deps)
  ├── intel              (no module deps)
  ├── combat             (reads matchflow.cinematic)
  ├── movement           (reads matchflow.cinematic)
  ├── environment        (requires attributes, economy, intel, combat)
  ├── ai_director        (requires construction [tech tiers], attributes?)
  ├── presentation       (unsynced; reads matchflow)
  └── campaign_api       (requires ~everything; owns triggers/state/objectives)

difficulty: not a node — plugs policies into economy, construction,
            ai_director, campaign_api (objective grace)
cutscenes:  a driver like environment — plugs into matchflow,
            movement, combat, presentation
```

Build order that respects both dependency and politics:

1. **matchflow** — proves the format small, un-stubs 4 actions (in flight)
2. **framework: combined-result pipelines + shared command handler** — every
   later module needs one or both; do this before module #3
3. **attributes** — loudest campaign ask, cleanest combined-result example,
   and a single existing gadget to take over
4. **construction** — three stubbed actions, three consumer factions
5. **intel / economy-growth** — small, mostly mechanical
6. **combat / movement** — command-handler territory, politically heavier
7. **environment** — first module that depends on several others; the
   integration proof
8. **ai_director** — biggest extraction (spawner gadgets), do with traction
9. **cutscenes/presentation** — grows alongside campaign content production

## Open questions

- Where does each category declare how its results combine (multiply, AND, OR,
  union, merge) — in PolicyBuilder or per-module? Leaning PolicyBuilder:
  `Pipeline():Fold("product")` vs `:FirstWins()` endings.
- Cost control for combined results: recomputing every unit's stats every
  frame is off the table. Recompute only when a source registers/unregisters
  or its inputs change, on a slow tick, and keep the hot-path questions coarse
  (per unit type and team, not per individual unit).
- Engine dependencies: units on frozen water, terrain deformation, sky/
  lighting control, projectile freeze, AllowWeaponTarget coverage — check
  what current RecoilEngine callins actually support before the campaign
  schedule assumes them.
- Where does `GG.wipeoutAllyTeam` / team-death ceremony land — matchflow
  effect or combat? (Currently: stays GG per the matchflow plan.)
- Naming: ai_director vs waves; attributes vs unit_state; intel vs vision.
- Mission authoring surface (how triggers/actions get written, checked, and
  edited): see [PR #2](https://github.com/keithharvey/bar-design-docs/pull/2)
  (mission_authoring_dsl.md).
