# Hello Pawns: The Runnable Demo

WtF's ask, verbatim: "start with a bot lab and build three Pawns to win the mission." This plan gets that running in-game, with the mission logic authored in the trigger DSL, and — stretch — editable live from an in-game RML form. The demo's job is to make six lines of mission Lua kill the "only one person can maintain it" fear.

The whole mission:

```lua
-- modules/missions/hello_pawns/triggers/win.lua
T.When(Team.Player:Has(UnitDef("armpw"), 3))
    :Then(function()
        Objective("build_pawns"):Complete()
        MatchFlow.Victory(Team.Player.allyTeam)
    end)
    :Register()
```

## Where it's built

On a new branch **off master** (fetch upstream first — local master goes stale), **borrowing files from the modules branch** rather than basing on it: copy in `modules/module_handler.lua`, `modules/policy_builder.lua`, and the minimal `modules/types/` + emmylua config the loader needs. Two reasons over branching off modules: the demo stays standalone (checkoutable without the 1500-file stack), and the modules branch is regenerated (`just bar::sharing-module rebuild` — overlay commits), so anything based on it gets orphaned on regeneration. Side effect: this IS step 1 of matchflow_module_plan.md's sequencing (the master bootstrap) — the demo doubles as proof the bootstrap is small. If the borrowed files drag in more than expected, that's a finding worth reporting, not silently working around.

## Components, smallest that can work

### 1. matchflow (demo-minimal)

`modules/matchflow/` with just the scripted-verdict path — NOT the game_end extraction (that's the real plan, later):

- `api.lua` (synced provide): `Victory(allyTeamID)`, `Defeat(allyTeamIDs)` — sets a pending verdict.
- `gadgets/matchflow_verdict.lua`: on GameFrame, if a verdict is pending, `Spring.GameOver(winners)`. Coexists with game_end.lua exactly the way missions do today (scenariooptions path) — acceptable for the demo, called out as demo-only.

Half a page of code. The point is the *call shape* `MatchFlow.Victory(...)`, which survives unchanged when the real module lands underneath it.

### 2. Trigger engine skeleton

`modules/missions/` (the mission-runtime module — name it now, it becomes the CampaignAPI home):

- `lib/trigger_engine.lua`: holds registered triggers, evaluates conditions on a cadence (every 15 frames is fine for the demo), runs effects. **State discipline from commit one**: fired flags and counters live in the engine's own plain tables, never in closures — the savegame rule from mission_authoring_dsl.md, enforced from the start because retrofitting it is the expensive direction.
- `lib/dsl.lua`: the builder — `T.When(cond):Then(fn):Register()`, `:Once()` (default true for the demo), condition objects with an `evaluate(ctx)` method. Follow policy_builder.lua's idiom (chain → descriptor list → sink). Trigger identity = filename + declaration order, recorded at registration — this is what makes hot-reload possible.
- `gadgets/mission_loader.lua`: if a mission is selected (see §4), loads `modules/missions/<name>/triggers/*.lua` with the injected environment (the includeRegistrationFile idiom from module_handler.lua): env contains `T`, `Team`, `UnitDef`, `Objective`, `MatchFlow` — and nothing else. The sandbox IS the API surface.

### 3. Verbs (three, no more)

- `Team.Player:Has(unitDef, count)` — condition; counts via `Spring.GetTeamUnitDefCount` on the engine's cadence. Team.Player resolves to the first human team (demo rule, documented).
- `Objective(name)` — demo-minimal: `:Complete()` echoes/pings; if time permits, a tiny widget listing objectives from a synced rulesparam. Do not build objective UI tonight if it threatens the win path.
- `MatchFlow.Victory/Defeat` — from §1.

Resist adding verbs tonight. Every verb after these three dilutes the demo's point (smallness) and adds surface before the shape is proven.

### 4. Mission selection

Demo-grade: a modoption is overkill and needs lobby plumbing. Use a dev start: local skirmish + `/luarules mission hello_pawns` chat command (gadget RecvLuaMsg/chat action) that loads and arms the mission mid-game. This is also secretly the hot-reload demo: `/luarules mission reload` re-runs the trigger files through unregister-by-identity. Two commands, both demo gold.

### 5. Stretch: the RML form

`modules/missions/rml_widgets/mission_editor.lua`: one form showing the registered trigger — condition (unit type dropdown, count field), effect (readonly text is fine) — with an Apply button that rewrites the values and re-registers the trigger live. Cheat mode only. The demo line: change 3 → 5 mid-game, build two more Pawns, win.

**There is no editor model.** The model is the registered trigger descriptors — the same tables the engine runs. Loading the mission file IS parsing (parse-by-execution): the file runs in the injected env, the builders record descriptors, the form renders from them. Hand edits and form edits converge automatically because both flow through load-and-register. Do not build a separate form state that shadows the descriptors — that would be the second source of truth this whole architecture exists to prevent.

The stretch ladder, in order — stop wherever the evening ends:

1. **Live apply**: form mutates the descriptor values, re-registers, game obeys.
2. **Write-back + type check** (the proof of the "basically free" claim made publicly): serialize the descriptors back to canonical trigger-file text and run emmylua on the result, surfacing output in the form. Opaque `:Then` bodies round-trip byte-exact via `debug.getinfo` (source + linedefined/lastlinedefined -> extract the span from the file), comments inside them included. DSL value helpers (`seconds(...)`) and named refs must carry their source form (tagged values / self-describing objects) so regeneration writes `seconds(10)`, not `300` — build that into the primitives from the start, it's cheap now and painful later. Demo beat: enter a bad value, the annotation catches it before the game ever sees it.
3. Later, not tonight: the static subset parser — buys editing without a running game, CI validation without executing files, and comment-perfect file-level round-trips (prose BETWEEN triggers is lost on regeneration until then; say so if asked, it's the one honest degradation).

Do NOT attempt: source-patching (regenerate, never patch), arbitrary trigger creation, multiple triggers. One form, one trigger.

## Order of work tonight

1. Trigger engine + DSL + `Has` condition, specs in busted (spec/ alongside, engine is pure Lua — cheap to test).
2. matchflow verdict path.
3. mission_loader + injected env + the hello_pawns mission files.
4. In-game: skirmish, `/luarules mission hello_pawns`, build 3 Pawns, win screen. **This is the milestone; screenshot/clip it.**
5. Reload command (hot-reload by identity).
6. RML form if the evening survives.

## Demo script (for the Discord clip)

1. Start a skirmish. `/luarules mission hello_pawns`. Objective appears.
2. Build bot lab, 3 Pawns → victory. (One take, ~2 minutes.)
3. Show `win.lua` — the whole file fits on screen.
4. If stretch landed: reopen, change count to 5 live, win again.

Post the clip + the file contents, not prose. The six lines are the argument; everything this thread has asked for ("could I write that?") is answered by reading them.

## Traps

- Synced Lua strips `rawset` — plain assignment in any lazy contract (known repo lesson; crashes only when first resolved from synced code).
- `_G` may be absent in unsynced sandboxes — CHUNK_ENV/getfenv fallback if the RML widget needs the module api (module_handler already handles this; use ModuleHandler.Get, don't roll your own).
- game_end.lua also calls GameOver on its own conditions — in a skirmish vs an idle AI, don't let elimination win before the Pawns do (pick a map/AI where the base survives; or spawn no enemy at all — a mission with no opponent is fine for hello world).
- Determinism doesn't matter for the demo (local, no replay claims) — don't spend tonight on it, but don't post the clip claiming multiplayer-safe either.
