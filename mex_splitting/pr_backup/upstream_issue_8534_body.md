<!-- https://github.com/beyond-all-reason/Beyond-All-Reason/issues/8534 — RFC: BAR Modules — body as of 2026-09-29, before it was replaced by the overview -->

## Intro

This is an RFC for **modules**: a way for BAR's Lua to declare its own boundaries.

Pick any behaviour in the game and try to answer "what owns this?". Take transfer — units and resources changing hands between allies. The answer today is spread across a handful of gadgets, a couple of widgets, some modoptions, and a cache or two, and the only way to find the full set is to grep for it. Nothing declares that those pieces belong together, so nothing can be reasoned about as a unit: not tested in isolation, not documented as a whole, not handed to a new contributor intact, and not reused by the next feature that needs the same behaviour.

A module is that missing declaration. It names what it owns, what it depends on, and what vocabulary it publishes. The framework loads it and wires it up. When one module requires another, the required module's vocabulary becomes available — so composition happens by declaring a dependency rather than by reaching across the tree.

That has a second effect, which is really the point. Once boundaries are written down, "what module owns this behaviour?" becomes a question with an answer you can point at in code, instead of a discussion about control flow. That is the conversation I want to be having with maintainers, and it is the one this RFC is trying to make possible.

What follows is a working demonstration rather than a proposal on paper: eighteen PRs of runtime and modules, a mission written entirely in the resulting DSL, and an editor that is a live view over that Lua rather than a separate format.

### Intended audience

This one is aimed at BAR developers, QA ninjas and, last but not least, technical leaders. Please ask me if something is not making sense to you.

### A note to maintainers

I had to restack this branch and in the process I squashed the atomic commits. Sorry, not sorry. Aint nobody that wants to read my vibe coded commit history anyway.

## Branch Structure

Eighteen PRs, each based on the one below it. Listed bottom-up, so the first one
targets `master` and each subsequent one targets its predecessor. They are grouped
into three review stacks, split where the story splits:

**Stack 1 — the machinery** (everything below is framework; the last PR is the
smallest thing built ON it, and a deliberate stopping point for review):

1. [#8484](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8484) `modules: the module runtime` — manifests, requires, auto-loading
2. [#8485](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8485) `modules: context` — one factory for every kind of context
3. [#8486](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8486) `modules: the mode grammar` — what a game mode is allowed to say, and the game axis
4. [#8487](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8487) `modules: one owner of the verdict` — match start, win, loss
5. [#8488](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8488) `modules: the trigger runtime and the authoring DSL` — `When ... Do ...`
6. [#8489](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8489) `modules: the served editor` — the language server, the form, the VS Code plugin
7. [#8689](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8689) `missions: hello pawns` — the smallest mission that can win, two triggers and a test

**Stack 2 — the policy modules**:

8. [#8490](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8490) `modules: tech tiers`
9. [#8520](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8520) `modules: construction policy` — what may be built, and by whom
10. [#8524](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8524) `modules: economy` — how a shared pool is distributed
11. [#8521](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8521) `modules: allied transfer` — one place that moves units and resources between teams
12. [#8522](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8522) `modules: combat, protection as a lifetime` — `Protect ... Until`

**Stack 3 — the PvE modules, and the mission that uses all of it**:

13. [#8632](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8632) `modules: placement` — where a thing can legally stand, answered once
14. [#8576](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8576) `modules: waves` — the PvE wave director as a library
15. [#8577](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8577) `modules: scavengers` — the roster and the difficulty as data, and the monolith dies
16. [#8687](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8687) `modules: raptors` — the options as a module, and a seat on the game axis
17. [#8882](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8882) `missions: the pressure` — waves, packs and placement on the mission surface
18. [#8494](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8494) `missions: CM8 Ashfall` — the demo, and nothing but the mission: 556 lines of DSL and the specs of its own shapes

They are all drafts, rebased onto current master. Comments across the stack are WHY-only: if the code needs a HOW comment, the code needs a refactor.

That order is a queue, not a dependency — most of these only need the runtime at the bottom, so most of them could land in any order. The real shape is the module dependency graph.

That module dependency graph is in our new VSCode BAR plugin:

<img width="1114" height="537" alt="Image" src="https://github.com/user-attachments/assets/3d39a69a-3677-4e37-b890-9531ae463124" />

So the branch exists with foundational commits, then modules layered on top.

## Demo v1

### Mission 8: Ashfall

![The cm8_ashfall mission directory](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/cm8_dir.png)

#### Spawning Units

##### `cm8_ashfall/units.lua`

```lua
Spawn(UnitDef("corlab"), "gaia").At(0.42, 0.42).Named("outpost_command_hub").Grouped("outpost_auto").Neutral()
Spawn(UnitDef("corllt"), "gaia").At(0.39, 0.40).Grouped("outpost_auto").Neutral()
...
Claim(UnitDef("armcom"), "enemy").Named("armada_commander").OrSpawnAt(0.77, 0.77)
Claim(UnitDef("corcom"), "player").Named("player_commander").OrSpawnAt(0.15, 0.15)
```

Spawn a unit and give it to gaia, in this named group, after the mission is activated. `.Neutral()` keeps the derelict outpost out of everyone's auto-targeting until the story hands it over. `Claim` is the other verb: the commanders are CLAIMED, not spawned — dropped into a game whose seat is already occupied, the mission binds its name to the commander that team already has, and only builds one (`OrSpawnAt`) when the seat is empty. Spawns go through the placement module, so a position written as a map fraction lands on ground that exists.

In editor:

![The roster, as a form in the editor](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/spawn.png)

This form in the editor is just a _view_ over the lua file.

#### Triggers

Here is our outpost trigger as shown in the VSCode Editor:

![The outpost trigger, in the editor](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/trigger_1_outpost.png)

If you click on the trigger row, it takes you to the code:

##### `cm8_ashfall/triggers/outpost.lua`
```lua
When(MatchFlow.Started()).Do(
	Combat.Protect(Unit("outpost_command_hub")).Until(Objective("find_the_enclave").IsComplete())
)

When(MatchFlow.Started())
	.When(Unit("outpost_command_hub").IsSpotted(Team.Player))
	.Do(Transfer.Give("outpost_auto", Team.Player))
```

The protection starts at match start; the handover waits until the player has actually FOUND the outpost — two `When`s on one statement are an AND.

 `MatchFlow.Started()` works because that tells our behavior engine "hey, once the match started, I need you to do x, y, and z". You don't care about the order, you just need that stuff to happen when the prerequisites are met. So you declare your intent and trust that it will happen.

##### Architectural Note

1) Notice how the handover is a `Transfer.*` action — the same module that moves units between allies in multiplayer. One module owns "things change hands", so a scripted mission handover and a player pressing the share button are the same pipeline, and the policies driving it change through knobs on the transfer module API.

   The mission says `Transfer.Give` rather than `Transfer.Units` on purpose, and the distinction is the whole argument in miniature. `Transfer.Units` asks the active mode whether it's allowed and what it costs; `Give` is fiat — the giver is the game itself, not a team choosing to share. A scripted handover must not be silently refused because the lobby happens to be running a no-sharing preset. That's not a special case bolted on: `Give` simply declares no mode facet, so no mode can speak about it, and you can see that in the action table rather than having to find out at runtime.
2) The `Combat.Protect` clause is an _effect_ the trigger runs; the interesting part is `.Until(...)`, which arms a companion trigger at the moment protection is applied - that's the event hook, and it's why the lifetime can't leak. This may be obvious, but it's worth stating because it's not always clear to people who don't have a lot of experience in functional code: just because this implementation factors this through a functional lens, doesn't mean we can't install things like Event hooks through this DSL. We don't have to go on an exhaustive hunt and rip out all state from every module and make a perfect functional reduction right away. We can do that incrementally while we also version and publish our own API -- in a way that it is _honest_ about the current limitations, explicit in its own API expression.

##### `cm8_ashfall/triggers/victory.lua`

In editor:
![The victory triggers, in the editor](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/trigger_2_victory.png)

The code:
```lua
When(Unit("player_commander").IsDestroyed()).Do(MatchFlow.Defeat(Team.Player))

When(Objective("kill_the_commander").IsComplete()).Do(MatchFlow.Victory(Team.Player))
```

The objective board itself moved into its own declaration file, `objectives.lua` — identity, wording, completion gates and reveal cadence, one declaration per line:

```lua
Objective("find_the_enclave")
	.Title("Find the Enclave")
	.CompletedWhen(Unit("enclave_beacon").IsSpotted(Team.Player))
	.When(Objective("relieve_the_outpost").IsComplete())
	.CompletedWhen(Unit("enclave_beacon").IsDestroyed())
	.When(Objective("relieve_the_outpost").IsComplete())
```

And the pressure arc is four beats in `triggers/waves.lua`, riding the same wave director a multiplayer scavengers game runs — with no bot on the field to activate it:

```lua
When(MatchFlow.Started())
	.After(60)
	.Do(Waves.Begin(Scavengers.Skirmish).Against(Team.Player).From(0.85, 0.15).Intensity(0.3))

When(Objective("relieve_the_outpost").IsComplete()).Do(Waves.Intensify(Scavengers.Skirmish, 0.6))

When(Objective("find_the_enclave").IsComplete())
	.Do(Waves.Surge(Scavengers.Skirmish))
	.Do(Waves.Intensify(Scavengers.Skirmish, 1.0))

When(Objective("kill_the_commander").IsComplete()).Do(Waves.End(Scavengers.Skirmish))
```

Everything is intent. You tell us what you want to do declaratively, the framework makes sure it's done for you at the right moment.

## The editor

### The form understands the Lua

The editor itself is by design guaranteed to be a (isomorphic) representation of the LUA file. Because our language server understands our code, the editor can surface that understanding to the user in a way that is structured and enriched with domain understanding.

### Editor Form Features

The **Mission Editor Overview** breaks down module complexity by category and contains breadcrumbs for navigation back to other missions:
![The mission overview breaks down complexity by construct](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/editor_mission_overview.png)

The **Nouns** section extracts runtime facts:
![The nouns section shows objectives](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/editor_nouns.png)

The **Status Badges** across all sections update in real time:
![The status badges show runtime state](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/editor_status_badges.png)

The **Reference Modules** section:
![The module reference: statements, conditions, effects, nouns, modes](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/modules.png)

Notice how these sections are entirely code-genned. They surface the [ubiquitous language](https://martinfowler.com/bliki/UbiquitousLanguage.html) of the domain in a way that QAs and developers can both understand, test, and iterate on atomically.

The UI also demonstrates how it can be chained; each "statement", "condition", "effect", "noun", and "mode" is self-documenting, semantically coherent and grouped in a way that demonstrates the form _understands_ the code it overlays.

### Editor Code Features

* Intellisense works great
![intellisense works great, shows hovering over condition: in a When statement](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/intellisense.png)
* nav-to-definition and f2 rename — the DSL is just typed Lua, so EmmyLua gives us these for free
* we can use the fact that our form has an enricher to also enhance the code, for example, UnitDef wrappers that warn you on a typo:

![an innaccurate unit def name errors](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/unitdef_name_error.png)

### The plugin ships the language server

You do not need BAR-Devtools to use any of this. If you want to hack on the server, run your own with `just bar::mission-serve` — the plugin adopts whatever is already answering and only starts its own when nothing is.

### The Code is a **subset** of Lua

Because this is a STRICT subset of Lua (the game's own verbs), it is unbelievably safe for us as maintainers. You can only call our own API at the moment and make it through a CI gate (or mod hub check) on your code. But we do probably want to loosen that gradually and at least permit like...math.

![math.floor is not in the mission vocabulary, and the editor says so](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/math_dot_floor_error.png)


### DSL Code Genned Forms Are God-Tier UIs

Because this is a parser, we get no-cost module expansion from a tooling PoV. If you add a new module vocabulary that doesn't have edit functionality for its own primitives baked yet, the form falls back to just rendering the DSL in the form inline -- which totally reads and works correctly from day 0 developing a new module.

![One statement at three levels of editor support: raw DSL, a sentence, typed slots](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/editor_fallback_ladder.png)

You can still navigate to your statements in Lua from the form and QA can still see your API shape without either of you adding or understanding any of the editor form functionality.

## Modules

Modules give developers a primitive to express boundaries to each other and the framework. They enable modules to expose new vocabulary through composition. If the mission team requires your module in the mission module -- boom! your module API/new vocabulary is now available in missions.

Modules publish **actions**, which are individual commands or queries that modify state (`Transfer.Units`) or answer questions (`Objective.IsComplete`, `Unit.IsDestroyed`), and rules are written over them in **policy language** (trigger or mode) - and within a mode chain there are three statement kinds.

* **Grants** - Allow/Deny actions.
* **Parameters** - Tax, Stun, Delay, Gate, Open, Defer
* **Modifiers** - Ranked, RetainValues, Desc, Hidden, Locked, Unlocked.

Modifiers provide global locks on inputs in the lobby or provide metadata for the global configuration (Desc, Ranked, RetainValues tells the mode to keep the last mode's selected values, when switching into that mode). Grants permit actions. Parameters modify policy.

### Modes

Modes are the _top-level_ configuration primitive for the global restrictions of behavior. They are each a self-contained closure. There can only be 1 mode per _category_. The demo has two categories: **game** — the axis a match is exactly one point on, where Standard, FFA, Scavengers, Raptors and Mission are all presets on one `game_mode` selector — and **transfer** — what may pass between allies. Each module binds its own vocabulary over the shared builder (`transfer/mode_dsl.lua`, `missions/lib/mode_dsl.lua`, `waves/mode_dsl.lua`, `scavengers/mode_dsl.lua`, `raptors/mode_dsl.lua`, ... are separate vocabularies that share the Mode() statement head). This means mission modes can't tax and Transfer can't own MatchFlow verdicts. In this way, each module can declare its own bespoke modes, and a flavor takes its seat on the game axis in its own PR.

Here is a multiplayer mode (that we're all familiar with) to show more:

`transfer/modes/easy_tax.lua`

```lua
local ModeDSL = VFS.Include("modules/transfer/mode_dsl.lua")
local Mode, Transfer, Construction, Take =
	ModeDSL.Mode, ModeDSL.Transfer, ModeDSL.Construction, ModeDSL.Take

return Mode("Easy Tax")
	.Desc(
		"Anti co-op sharing tax. 30% tax on shared resources; shared eco buildings are stunned and shared constructors cannot build, both for 30 seconds."
	)
	.Ranked()
	.Allow(Transfer.Units)
	.Stun(Transfer.Units.Resource, 30)
	.Delay(Construction.Build, 30)
	.Allow(Transfer.Resources)
	.Tax(Transfer.Resources, 0.30)
	.Allow(Construction.Assist)
	.Allow(Construction.Reclaim)
	.Allow(Construction.Resurrect)
	.Stun(Take)
	.Delay(Take.Resource, 30)
```

The module name is the vocabulary prefix, so a preset tells you which module owns
each line. `Construction.*` appears in a transfer mode because construction
declares what a builder may do for an ally and transfer requires it — the
grammar composes across the dependency edge, and a preset still reads as one
list.

Let's go over the modules contained in this demo.

### Demo Modules

- **context** — the factory every other module builds its decision context from, plus the shared policy vocabulary they enrich. No dependencies.
- **modes** — the mode machinery itself: how a preset is declared, aggregated, and exported to modoptions so the lobby can set it. No dependencies.
- **matchflow** — owns the verdict: match start, elimination, scripted win/loss, and the ceremony that follows. No dependencies.
- **combat** — scripted combat exceptions: protection (neutral to auto-targeting, damage ×0) and stun. No dependencies.
- **economy** — how a shared pool is distributed: the waterfill solver. It answers a question that is not about allies at all — given a pool, a set of claimants and their capacities, how much does each get — so it sits *under* the modules that have a reason to ask. No dependencies.
- **tech** — what a team may build at its tier: the gate, and the tech points UI. → context
- **construction** — what may be built and by whom: assist, reclaim, resurrect, ally mex upgrades, and the build delay. → context
- **transfer** — one pipeline for everything that changes hands between allies: units, resources, `/take`, and the tax on what flows. → context, tech, construction, economy
- **placement** — where a thing can legally stand, answered once and deterministically: the wave director asks it for burrows, the roster asks it for the opening world state, the move action asks it before it moves. → context
- **waves** — the PvE wave director as a library: anger clocks, wave composition, burrow and boss lifecycle, squad AI. Configured with plain data (a `WaveSpec`), so a multiplayer mode and a mission's scripted pressure are the same machinery at different intensities. → context, placement
- **scavengers** — the flavor pack over waves: the roster, the six difficulty rungs, beacons, behaviours, the boss — everything the director cannot know. The 2,971-line config monolith and the ~2,500-line spawner die in this PR. → context, waves, combat
- **raptors** — today only the lobby face of the flavor: the `raptor_*` options move into the module and the preset takes its seat on the game axis; the spawner migrates onto waves later, the same path scavengers took. → context, waves
- **missions** — the trigger runtime: the `When … Do` engine, the authoring DSL, and the loader that arms a mission as a single transaction. The requires list IS the vocabulary whitelist: what a mission file may say is exactly what these modules contribute. → matchflow, combat, transfer, waves, scavengers, placement

Two of those edges are worth pointing at, because they are the ones that moved
during review and they moved for reasons you can argue about — which is the
point of writing them down.

`transfer → construction`, not the other way round. Both directions have a
story: assisting an ally is arguably a kind of sharing, so it could hang off
transfer; but building is the more primitive idea, and construction has no need
to know that allies exist. It reads better at the base, so it went there and
transfer requires it.

`transfer → economy` exists because the waterfill solver isn't a sharing concept
that leaked downward — it's a pool-splitting algorithm that sharing happens to
be the first caller of. Making it its own module means the next thing that has
to split a pool asks the same solver instead of growing its own.

## Testing

### The specs run in the CI job we already have

63 spec files, 733 `it()` blocks, living next to the module they test —
`modules/transfer/spec/`, `modules/missions/spec/`, and so on. No new pipeline:
`.busted` discovers any `modules/*/spec/` directory generically, so the existing
`test_unit` workflow picks up a new module's specs the moment the directory
exists. A module ships its tests the same way it ships its gadgets.

The headless integration suite grew the same way, and it is scoped at the
machinery, never at a mission: hello_pawns played to victory, tech blocking,
resource and unit transfer run in the existing docker job; the claim, handover
and pressure paths run as a scenario (`startscript_missions_smoke.txt`) against
three fixture missions under `modules/missions/smoke_*`, hidden from the lobby
picker, and self-skip in the standard suite until the scenario is wired into CI.
A mission ships unit specs of its own input shapes — CM8's three `cm8_*_spec`
files — and nothing else: an author writing a mission is not testing waves.

This is a large part of why the boundaries are worth drawing. Most of what these
modules decide is now a pure function of a context table — "may this transfer
happen, and what does it cost" is answerable without a running engine — so it
gets tested as a policy rather than as a gameplay symptom.

### The in-game authoring loop

There are three verbs, all under `/mission`:

```
/mission load <name>
/mission reload
/mission restart
/mission editor
```

`load`, `reload` and `restart` are synced (one gadget chat action); `editor` is
unsynced (it opens the RmlUi panel). The panel and the chat command both come through the
same declared action, so the guard and the transaction happen once each rather
than once per caller.

**`reload` is a fresh run, not a hot patch.** It re-reads the trigger files,
replaces the armed set wholesale, clears objective progress, and despawns and
respawns the roster. That is deliberate — a completed objective must not survive
into the next run and re-fire victory on the following cadence — and in practice
it is what you want while iterating: nothing accumulates state worth preserving
between runs.

**Rosters are positioned in map fractions today, not coordinates.** `At(0.42, 0.42)`
means "42% across, 42% down", so a mission under development plays on any test
map. That is scaffolding for the current phase, where I am testing trigger
behaviour and the campaign maps do not exist yet; a finished mission pins real
coordinates and is map-bound like you would expect. Missions have historically
been script files and they still work the same way — they just live in a module
now.

### What guards it

`ChatGuard.IsAllowed(isSinglePlayer, cheatsEnabled)` — singleplayer always, or
cheats on. In multiplayer any player can send a synced chat action, so arming or
reloading a mission must not be an open verb. The guard is a pure function with
its own spec, and it sits on the command rather than inside the loader, because
*who may ask* is the channel's business and *is this a real mission* is the
action's.

On top of that, `missions/modes/mission.lua` is a mode like any other, so
"missions are on" is a lobby-visible setting and not an ambient runtime state:

```lua
return Mode("Mission")
	.Desc(
		"The mission decides when it is won or lost, so losing your units does not end the match. Every unit is loaded, because a mission can use anything."
	)
	.Own(MatchFlow.End)
	.Loads(Match.EveryUnitDef)
	.Ranked(false)
	.Locked()
	.Choose(Match.Mission)
	.Unlocked()
	.Bot("NullAI")
```

(`Bot("NullAI")` is the seat-filler: a mission needs an enemy TEAM to arm, not an enemy player — the waves are the pressure.)

## Opinions

###  "That's not how the game industry does it!"

@attean

Nonsense. This argument immediately breaks down under scrutiny. We have the same solutions already (caching, state machines, service layers through singletons) but they're just distributed throughout the code base instead of living in either the framework, or a module, and that is problematic because it's harder to generalize solutions. This factoring is easier for us because we can put **all** the foot guns in the framework box.

I don't know another way to decompose state in an incremental way into domain modules, other than to actually go and start to do that.

### Module dependency graphs seem too complex?

@attean

"Woh, woh, woh, slow down!", I hear you say. "Dependency graphs?! What is this madness?! I don't want to know this stuff!"

But you have to. These modules are our best-known expression of _our_ domain (RTS behavior) boundaries. They are exactly what we should all be discussing, all the time. Right now, in engineering anyway, we're discussing a lot of control flow, which is a smell. How can we make our domain more comprehensible and easy to read? If there are actual dependencies between modules, making that explicit and auto-documented at edit-time helps QA debug it better and helps developers to focus on specific, incremental verbs as they're building out features.

![Before: the answer is spread across the tree. After: one module, two declared edges](https://raw.githubusercontent.com/keithharvey/bar-design-docs/7c3efa5807b1054df472f38eb6d19b6afcdb1dee/campaign_api/handoff/who_owns_transfer.png)

## Conclusion

@attean

I think that, to some extent, maintainers _MUST_ do large parts of this state decoupling in order to move with any velocity and eventually support modding.

This is the dev story I wanted to tell after I looked at a random problem (transfer and, quixotically enough, how to move `/take` out of Recoil), and I am very priveliged to have been able to prototype it out over the last however many months. It's pretty cool to me that I can kind of go through high level discovery and prototype tooling in a week, and then maybe have the conversation about module boundaries that I want to be having with yall instead, and with a broader audience because we surfaced the Lua API in a self-documenting way.

Also shout out to @NortySpock and @Harkenn for challenging me, @Boneless for paying attention to BAR, and @sprunk for stopping my premature engine PRs -- in order to bring this into this form. This is better than the half measure that tried to dodge having the framework conversation (and I think we can all see why :sweat:), but it's a much better demonstration for having pushed it a little further.

This is also a handoff of sorts from me on these ideas. Not to imply that I'm done working on this, but more that this is that communication's final form. I believe this is a comprehensible shape so I will iterate on and validate that shape, but this is enough for the demo.

"What module owns our behavior?" is the right conversation that we as contributors should be having with maintainers -- and that question being laser focused within the organization as a transparent artifact, in code, will intrinsically reduce all manner of time spent on debugging and on drama between the various stakeholders vying to control the One True Runtime State Implementation that isn't intrinsically factored to be composable. In summary, we have to do something like this and this is _one version_ of it that satisfies the requirements and then some. Some of the most successful UIs (commercially and in terms of maintenance) that I have ever built have been this exact same approach, so my confidence in these refactoring and tooling approaches is extremely high.



