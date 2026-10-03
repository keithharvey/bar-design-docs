# The mode is the configuration root

Plan for implementation. Written 2026-07-26 against the working checkout
(`sharing-v2` chain: missions → combat → cm8 → modes → sharing).

## The thesis

A mode is the only artifact that spans the whole configuration path — the lobby
client picks one, SPADS expands it, the engine receives modoptions, the runtime
reads them. Today it carries exactly one kind of fact: **which modoptions are
set and locked**.

Extend it to carry a second: **which modules are active**. Everything else
follows from those two, because a module already owns its gadgets, policies,
modoptions fragment, mode presets, and — since the DSL work — the vocabulary it
injects into the authoring sandbox.

    lobby pick
       ↓
    mode  ──declares──>  root modules
       ↓                      ↓ (manifest `requires` closure)
    modoptions            active module set
                              ↓
                   ┌──────────┼───────────────┐
              gadgets/     sandbox env      published fact
              policies    (mission_loader)   (editor, tooling)

One selection, one resolution, four consumers that never disagree because they
read the same answer.

## Is `When` a "mode verb"?

No — and keeping them distinct is what makes the rest work.

- `Mode(...)` chains are **standing tense**: configuration, resolved before the
  match, serialized to modoptions, chosen in a lobby.
- `When(...)` chains are **event tense**: they run during the match.

They are different tenses and must stay different verbs; collapsing them would
undo the discipline ratified in `mission_authoring_dsl.md`.

What is true — and is the real insight — is that **which event-tense verbs
exist is a consequence of the mode**. `When` is not a mode verb; `When` is
vocabulary published by the `missions` module, which is active because the mode
says so. The mode is the root of the configuration tree; the DSL surface is one
of its leaves.

So the aggregate you are describing is real, and its shape is:

    mode → modules → { modoptions, gadgets, policies, vocabulary }

## What changes

### 1. A mode declares its root modules

Add one verb to the base mode chain (owned by `modules/modes`):

```lua
return Mode("Mission")
    .Desc("Triggers own the verdict; engine elimination never ends the match.")
    .Uses(Module.missions)
    .Own(Match.End)
```

`.Uses` takes module nouns, not strings, so a typo is a load error and the
editor can offer the list. Roots only — the manifest `requires` graph resolves
the closure (`missions` pulls `combat`, `matchflow`, `modes`), so a mode names
what it is *about*, not everything it transitively needs.

A mode preset's location already implies its own module
(`modules/missions/modes/mission.lua`), so `.Uses` is for the root set, and a
preset that names nothing defaults to the module it lives in.

### 2. The game resolves and publishes the fact

- `ModuleHandler.Active(modeConfig)` → the transitive closure of the mode's
  roots over manifest `requires`, in dependency order. Pure, specs under busted.
- The runtime stamps it: `Spring.SetGameRulesParam("modules_active", …)` or a
  small synced table — savegame-durable and readable unsynced.
- `mission_bridge` publishes `modules.json` into the editor dir, exactly as it
  already publishes `domains.json` (things only the game knows).
- `export_game_modes` includes the module set per mode, so SPADS and the lobby
  expand a mode into *options plus modules*.

### 3. Consumers read the fact instead of deriving it

- **`mission_loader`** already composes its sandbox from the missions manifest's
  `requires`. Change it to compose from the **active set** instead: same
  mechanism, authoritative input. A module that is present on disk but not
  active must not inject vocabulary.
- **bar-mission-kit** stops resolving dependencies altogether. Delete the
  transitive walk in `TypeSurface::load_near`, `manifest_requires`, and the
  depth computation in `modules_graph`; read `modules.json` and consume the
  published order. Keep the static walk **only** as the headless fallback
  (`mission-check` in CI runs with no game), the same shape as
  `TypeSurface::builtin()` vs `load_near`.

This closes a live correctness gap: today the editor derives its own module set,
so a module that is present but disabled would still appear in the Reference and
still pass `check` — the editor offering vocabulary the runtime will not inject.

### 4. The Reference renders the published graph

The `Graph` section becomes a rendering of the fact (nodes, edges, resolution
order) rather than an inference. Nothing else in the view changes.

## Order of work

Each step is independently landable and gated.

1. **`Module` nouns + `.Uses`** in `modules/modes` (types + builder + specs).
   Gate: busted; `mission-check` over `modules/` stays OK.
2. **`ModuleHandler.Active(mode)`** — closure + ordering + cycle safety. Pure
   Lua, spec'd. Gate: busted.
3. **Stamp and publish** — rulesparam in the loader/gadget, `modules.json` in
   `mission_bridge`. Gate: arm a mission, confirm the file and the param.
4. **Loader composes from the active set.** Gate: `hello_pawns` and
   `cm8_ashfall` still arm; the headless `test_win` integration test passes.
5. **Kit reads the fact**, static walk demoted to fallback. Gate: kit tests;
   `mission-check` green both with and without `modules.json` present.
6. **Export carries modules.** Gate: the export CI job; SPADS expansion
   unchanged for existing modes.

## Prerequisite, and how it interacts

`sharing_split_v2.md` should land first if it is going to land at all — it
changes which modules exist (`tech` extracted, `sharing` renamed `allies`), and
every step here enumerates modules. Doing it second means redoing steps 1 and 2
and re-recording every mode's root set.

Note that plan's conclusion is *narrow*: sharing stays one module because every
attempted cut produced a dependency cycle. So the module set this plan resolves
over is close to today's — missions, matchflow, combat, allies, tech, modes —
which keeps `.Uses` short and the graph readable.

The related cleanup that falls out naturally: `Mode` is currently declared in
**both** `modules/missions/types/mode_dsl.lua` and
`modules/sharing/types/mode_dsl.lua`, so the Reference shows it under both. It
belongs to `modules/modes`, with each module declaring only what it *adds*.
No inheritance machinery is needed — the kit's type parser merges classes by
name across files, so two modules declaring `---@class ModeChain` contribute
fields to one class. Each module then adds `modes` to its manifest `requires`.

## Open questions

- **Do non-mode games have a mode?** Skirmish and multiplayer without an
  explicit pick still need an active set. Simplest answer: a default mode that
  names the base modules, so there is never an unconfigured path.
- **Where does the runtime read the active set from at load time?** The mode is
  known from modoptions; the closure could be computed at gadget init, or
  precomputed by the export and passed as a modoption. Prefer computing in-game
  (one implementation) unless SPADS needs it earlier.
- **Enablement vs presence for `ModuleHandler.Discover`.** Discovery stays
  presence-based (it must find modules to resolve them); *activation* is the new
  filter. Auto-loaded subdirectories (`gadgets/`, `widgets/`) currently load by
  presence — deciding whether activation gates those too is a behavioral change
  worth its own review, and it is the one step here that can break existing
  games.

## Out of scope

- Changing tense discipline or merging `When` into `Mode`.
- Runtime module state in the editor (the "what is this module doing right now"
  idea) — same publishing channel, separate feature.
- Any change to how modoptions serialize; byte-neutrality specs stay as they are.
