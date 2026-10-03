# CM8 "Ashfall", Written Twice

One real mission from the campaign spec, implemented beat by beat under two systems:

- **A — today**: the current Mission API (the refactored actions/triggers of PR #8226) plus the base game's existing gadgets, used as honestly as a competent contributor would use them. Where today's tools are fine, this doc says so.
- **B — modules**: the domain modules from [module_breakdown.md](module_breakdown.md) plus the trigger DSL from [mission_authoring_dsl.md](mission_authoring_dsl.md). Module verbs marked "(needs: X)" don't exist yet; the code is written as it would actually run.

One thing up front: **full CM8 cannot be built today under either system.** The mission's planet (Teizer V), its tileset, and several assets are pre-production. This comparison is about the *logic* layer — what each beat needs from the game, and what it costs to get it.

## The mission

From the campaign spec (refs/campaign_reqs_extraction.txt, ~line 1145): volcanic Line World, stepped volcanic shelves. The player relieves a failing Cortex outpost whose human pilots are gone but whose automated units remain. Each map tier is anchored by T2 geothermals that regulate the lava level — destroy a geo and the lava rises a tier (Gideon warns you, repeatedly). Hidden nearby: a cloaked, jammed Armada enclave around a Tenebrium device that's drawing the Raptors. Raptors attack throughout. Win by killing the Armada Commander. Mission end unlocks the T2 Vehicle Lab and records that Tenebrium attracts Raptors.

--------------------------------------------------------------------------------

## Beat 1 — Mission setup: spawn the world, restrict the tech

The mission starts with the player's forces, the failing outpost, the Armada presence, and a tech ceiling: T1 vehicles plus whatever earlier missions unlocked. Mid-mission, the T2 Vehicle Lab becomes buildable (that's the reward beat).

**A — today.** Spawning is solved: the Mission API's loadout system (`SpawnUnits` + `loadout.lua`) places named forces cleanly. This part is fine.

The tech ceiling is not. `EnableBuildOption` / `DisableBuildOption` / `AlterBuildlist` are `yet_to_implement` stubs in PR #8226 — and they're stubbed because there is nothing to call: unit restrictions today are static (modoptions read at load time, def preprocessing). A mission that wants "T2 lab not buildable until beat 6" writes a custom gadget hooking `AllowCommand` + `AllowUnitCreation`, and even then the build menu still *shows* the lab as buildable — the menu widget has no idea your gadget exists, so the player clicks a button that silently fails. Making the button appear darkened or hidden means patching the build menu widget too. Two custom patches, owned by the mission, for one requirement.

```lua
-- A: the custom gadget every restricted mission rewrites (abridged)
local restricted = { [UnitDefNames.cortex_t2_veh_lab.id] = true }
function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID)
    if restricted[-cmdID] and teamID == PLAYER_TEAM then return false end
    return true
end
-- ...plus AllowUnitCreation, plus a widget patch to grey the button.
```

**B — modules.** The construction module owns "can this team build this unit," and the build menu already consults it, because that's where the answer lives for every consumer (modoptions, factions, difficulty — not just missions).

```lua
-- B: missions/cm8_ashfall/triggers/tech.lua
Build.Restrict(Team.Player, UnitDef("cortex_t2_veh_lab"))
    :Visibility("darkened")        -- player sees it exists, can't have it yet
    :Until(Objective("silence_the_device"):IsComplete())
```

When the objective completes, the restriction lifts, the queue-purge rules don't trigger (nothing was queued — it was restricted), and the button un-darkens, because UI and enforcement read the same verdict. (needs: construction module)

## Beat 2 — The automated base: dozens of units, no pilots

The player inherits a base of automated units, gets control of them, and some structures are story-critical — the mission breaks if the player loses the outpost's command hub before the enclave reveal.

**A — today.** Naming and transfer are solved and fine: `NameUnits` tracks groups by name, `TransferUnits` hands them over, `IssueOrders` moves them. This is exactly what those actions were built for.

Story-protection is not. There is no invulnerability anywhere in the game or the Mission API — `SetUnitInvulnerable` is not among PR #8226's actions even as a stub. Today: a custom gadget hooking `UnitPreDamaged` to zero incoming damage for listed units, plus (if you want attackers to not even try) `AllowWeaponTarget`. Both are per-mission code touching the hottest callins in the engine.

**B — modules.** Invulnerability is two registrations into the combat module — untargetable (a decision) plus damage ×0 (a modifier). The module already owns those callins and precomputes flat lookups, so the mission adds a table entry, not a hook.

```lua
-- B
Units.Name("outpost_auto", Spring.GetTeamUnits(OUTPOST_TEAM))  -- (assumed helper)
Units.Transfer("outpost_auto", Team.Player)

Combat.Protect(Unit("outpost_command_hub"))
    :Until(Objective("find_the_enclave"):IsComplete())
```

(needs: combat module; matchflow's cinematic flag if the reveal is a cutscene)

## Beat 3 — Lava tiers: destroy a geo, the lava rises

The signature mechanic. Each tier's T2 geo regulates the lava; killing one raises the level a tier, drowning whatever's below. Gideon cautions the player each time.

**A — today.** Better news than you'd expect: lava is already a game-side system, not an engine one. `luarules/gadgets/map_lava.lua` runs a Lua-driven lava level (`lavaLevel`, `lavaGrow`, tide rhythms) with damage and unit-slow handled, and `modules/lava.lua` renders it. The engine is not the blocker here.

The blocker is that none of it has an API. The level and its schedule come from map config at load; nothing external can say "rise one tier now." A mission does one of: fork the gadget (a copy that diverges from every future fix), or reach into its locals via `GG`/`_G` upvalue surgery (fragile, sync-risky). The trigger side is fine — `UnitKilled` on each geo exists in the trigger schema, wired to a `SendMessage` for Gideon.

```lua
-- A: the trigger half works today; the action half has no legal target
geo_tier2_killed = {
    type = triggerTypes.UnitKilled,
    parameters = { unitName = 'geo_tier2' },
    actions = { 'warnGideonTier2', 'raiseLavaTier2' },  -- <- no such action can exist
},
```

**B — modules.** The environment module absorbs `map_lava` and exposes the level as a controlled verb. The mechanic becomes three lines per tier:

```lua
-- B
T.When(Unit("geo_tier2"):IsDestroyed())
    :Then(function(ctx)
        Environment.Lava:RaiseTo(Tier(2).level, { seconds = 20 })
        Presentation.Transmission("gideon", "lava_warning_tier2")
    end)
    :Register()
```

(needs: environment module wrapping the existing lava gadget — an extraction, not new tech. The honest caveat lives elsewhere: CM8's *map* must be built lava-enabled, and Teizer V doesn't exist yet under either system.)

## Beat 4 — The cloaked enclave: jammers, cloaked buildings, the reveal

A hidden Armada enclave — cloaked structures inside a jammer field — that the player discovers by proximity, or that the mission reveals dramatically at a story beat.

**A — today.** The passive half works: cloaked units and jammer radii are unit-def features, and the `UnitSpotted` trigger (in the schema) fires when the player stumbles in. Spawn the enclave from a loadout, wait for `UnitSpotted`, fire the dialogue. Fine, and this doc says so.

The *scripted* half doesn't: "reveal the enclave to the player now" is `RevealLOS` — a `yet_to_implement` stub. There's no mission-facing way to grant vision of an area (the engine calls exist — `Spring.SetGlobalLos` is all-or-nothing, per-area grants mean spawning invisible sensor units — but nobody owns that trick, so each mission reinvents it).

**B — modules.** The intel module owns sensor grants, including the spawn-an-eye implementation detail nobody should write twice:

```lua
-- B
T.When(Objective("silence_the_device"):Activated())
    :Then(function(ctx)
        Intel.Grant(Team.Player, { layers = { "los", "radar" } })
            :Over(Region("enclave"))
            :For(seconds(12))                  -- long enough for the camera beat
        Presentation.Transmission("gideon", "enclave_reveal")
    end)
    :Register()
```

(needs: intel module)

## Beat 5 — Raptor pressure: waves that scale

Raptors attack throughout the mission, in waves that should scale with difficulty and escalate as lava tiers fall (the device is *calling* them).

**A — today.** The hardest gap in the mission. The base game's raptor wave logic lives in `raptor_spawner_defense.lua` — 2,500+ lines, driven entirely by modoptions, built for the survival mode. A mission cannot call it: it has no API, and enabling it via modoptions brings the whole survival ruleset with it. So the mission hand-rolls waves: repeating `TimeElapsed` triggers, `SpawnUnits` from loadouts, `IssueOrders` toward the base. That *works* — but you've re-implemented wave spawning with none of the spawner's tuning: no difficulty scaling machinery (the trigger `difficulties` filter can select between hand-authored variants, which means authoring each wave N times), no escalation curve, no retreat logic, dumb pathing.

```lua
-- A: hand-rolled wave, authored once per difficulty
wave_2_hard = {
    type = triggerTypes.TimeElapsed,
    settings = { repeating = true, difficulties = { 'hard' } },
    parameters = { gameFrame = 9000, interval = 5400 },
    actions = { 'spawnWave2Hard', 'orderWave2Attack' },
},
```

**B — modules.** The ai_director module is the raptor spawner's wave logic extracted behind verbs, so missions and the survival mode drive the same machinery:

```lua
-- B
local assault = Wave.Define("device_call")
    :Composition({ raptor_land_swarmer_basic = 40, raptor_land_assault_basic = 8 })
    :Route(Path("north_shelf"))
    :Target(Region("player_base"))
    :ScaleWith(Difficulty)                  -- one authoring, N difficulties

T.Every(minutes(3)):While(Objective("silence_the_device"):IsActive())
    :Then(function() assault:Spawn() end)
    :Register()

T.When(Environment.Lava:TierFell())         -- escalation: the device feeds
    :Then(function() assault:Intensify(1.25) end)
    :Register()
```

(needs: ai_director module — the biggest extraction in the breakdown doc, and this beat is why it earns its cost.)

## Beat 6 — Objectives and victory: kill the Commander

Staged objectives (relieve the outpost → find the enclave → silence the device → kill the Commander), then mission end: victory, T2 Veh Lab unlocked for future missions, a campaign fact recorded.

**A — today.** Objectives and stages are solved: `UpdateObjective`, `ChangeStage`, and the objectives loader are implemented and fine. `Victory` works — with one structural wrinkle: it calls `Spring.GameOver` directly while `game_end.lua` is still running its own end-condition checks. Two independent owners of "is the game over" that don't know about each other; missions today also lean on the `scenariooptions` special-case wedged into game_end. It works, it's just nobody's contract.

Campaign persistence (the T2 unlock, the Tenebrium fact) has no home yet in either system's shipped code — the draft spec lists `Campaign.SetFlag` / `Campaign.UnlockMission`; today there's the scenario-stats message to the lobby. Roughly even; this doc won't score it.

**B — modules.** Victory is a scripted verdict through matchflow — the same pipeline the base game, deathmodes, and factions use, so there's exactly one owner of game-over:

```lua
-- B
T.When(Unit("armada_commander"):IsDestroyed())
    :Then(function(ctx)
        Objective("kill_the_commander"):Complete()
        Campaign.SetFlag("tenebrium_attracts_raptors")
        Campaign.Unlock("cortex_t2_veh_lab")
        MatchFlow.Victory(Team.Player.allyTeam)
    end)
    :Register()
```

(needs: matchflow module — planned in detail, first in the build order)

## Beat 7 — Difficulty (short)

**A:** the per-trigger `difficulties` filter exists and works — but it selects between hand-authored variants, so every scaled beat is authored per difficulty, and economy/tech knobs (`Difficulty.SetEconomyBonus`, `SetTechRestriction` in the spec) are stubs with nothing to call. **B:** difficulty isn't mission content at all — it's a set of policies plugged into the modules (income ×1.2 into economy, wave scaling into ai_director, tech limits into construction). The mission is authored once; `:ScaleWith(Difficulty)` in beat 5 is what that looks like from the mission's side.

## Beat 8 — Checkpoints (short)

The spec requires autosave/checkpoint. **A:** trigger definitions are data tables (good — serializable), but progress state (which repeats fired, stage positions) and every `Custom`-action function sit wherever each mission put them; there's no save/restore layer yet. **B:** same problem, solved by rule rather than per mission: definitions are stateless and reload from source; progress lives in the trigger engine's own tables and serializes with the game (the source-vs-save split in mission_authoring_dsl.md). Neither system has shipped this; B has decided where it goes.

--------------------------------------------------------------------------------

## Summary

| Beat | Possible today? | Today's cost | Module surface used |
|---|---|---|---|
| Spawn/loadouts | Yes — fine as-is | — | (same) |
| Tech restriction | Partly | Custom gadget + build-menu widget patch per mission | construction |
| Name/transfer units | Yes — fine as-is | — | (same) |
| Story invulnerability | No | Custom hot-path gadget per mission | combat |
| Lava tier control | No | Fork map_lava or poke its internals | environment (extraction) |
| Enclave, stumbled into | Yes — fine as-is | — | (same) |
| Enclave, scripted reveal | No (`RevealLOS` stub) | Hand-rolled invisible sensor units | intel |
| Raptor waves | Hand-rolled only | Re-implement wave logic; author per difficulty | ai_director |
| Objectives/stages | Yes — fine as-is | — | (same) |
| Victory | Yes, uncontracted | Two owners of game-over | matchflow |
| Campaign flags | No (both) | — | campaign layer (both) |
| Difficulty scaling | Filter only | Author every scaled beat N times | policies into modules |
| Checkpoints | Not shipped (both) | Per-mission | trigger engine owns state |

Six of thirteen rows are fine today, and the Mission API's implemented actions cover them well — that's worth saying plainly. The other seven are the `yet_to_implement` stubs and their neighbors, and they share one cause: the behavior belongs to base-game systems that expose no API. Every "today's cost" cell above is a fork, a patch, or a reimplementation that some mission author maintains alone. The module column is the same list of work — done once, owned by the subsystem, shared by every mission after CM8.
