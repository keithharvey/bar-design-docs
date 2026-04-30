# Spring API split (RFC)

**Authors:** Daniel/attean. **Last update:** 2026-04-28.

This is an RFC, not a decision. It enumerates the problem, the options for addressing it, and the tradeoffs. Each game/engine project can adopt, reject, or defer independently — the engine-side work needed to *enable* the split is itself a precondition that's currently in flight in [RecoilEngine PR #2799](https://github.com/beyond-all-reason/RecoilEngine/pull/2799).

This RFC is shared with Recoil engine maintainers and Recoil-based-game maintainers (BAR, Zero-K, others) because the decision affects the engine's public Lua API surface and therefore every game built on it. Each game has a separate adoption decision; the engine has a "do we ship the split namespace at all" decision.

## Decisions to make

This RFC bundles two separable decisions. Each can be adopted, rejected, or deferred independently.

| # | Decision | Default if rejected |
|---|---|---|
| 1 | Spring API split (three-table namespacing) | Single `Spring` table; runtime-only context errors |
| 2 | Deprecate `Spring` immediately, or later | Currently kept as a typed runtime alias |

---

## Reviewer table

To be filled in by reviewers; LGTM = "the document accurately describes my position and the tradeoffs," not approval of any particular option.

| Reviewer | Date | Status | Notes |
|---|---|---|---|
| | | Pending | |
| | | Pending | |

---

## Background

Recoil-derived engines expose a large Lua API on the `Spring` table. Each function falls into one of three contexts:

- **Synced** — callable from gadgets only. Mutates game state, must be deterministic, replay-stable, and identical across all clients.
- **Unsynced** — callable from widgets only. Reads visual/UI state, free to be non-deterministic per-client.
- **Shared** — callable from both. Read-only utilities (`Echo`, `GetGameFrame`, math helpers, etc.) and a handful of pure functions.

At runtime, the per-context environments expose the wrong-context functions as `nil`. So a widget calling `Spring.SetUnitTeam(...)` (synced) crashes with "attempt to call a nil value" the moment that code path runs — not at load, not at edit time, not in CI.

The type system today reflects none of this. Static analysis (LuaLS / EmmyLua) sees `Spring` as a single table where every function is callable from everywhere. Editor autocomplete suggests synced functions inside widgets and vice versa. Documentation is split across wiki pages by convention, not by mechanism.

## What's broken today

Three concrete problems:

1. **Context-mismatched calls only fail at runtime.** A widget that calls `Spring.GiveOrderToUnit` (synced) gets `nil` and crashes when that code is exercised. The bug doesn't surface in editor warnings, in CI type-checks, or in unit tests that don't hit the offending branch. We see this category of bug recurring in BAR.

2. **Editor tools can't help.** Autocomplete inside a widget includes synced functions (which will crash). Autocomplete inside a gadget includes unsynced functions (which will crash). Hover-docs don't tell the developer the function's context unless the wiki happens to say so.

3. **Documentation discipline is implicit.** Every contributor needs to internalize "this function is gadget-only" as a remembered fact. New contributors don't have that memory. The wiki is not always current, especially for newer functions.

---

## Decision 1: Spring API split

**Addresses the three problems above.**

Split `Spring` into three tables: `SpringSynced`, `SpringUnsynced`, `SpringShared`. Each Lua-exposed engine function is registered into exactly one of them, corresponding to its context. The per-context Lua environments expose the relevant tables — widgets cannot see synced functions (the runtime gates that direction); synced code (gadgets) *can* call unsynced functions (the runtime doesn't gate that direction — see e.g. `Spring.PlaySound` in `LuaUnitScript.cpp`'s comments). The static-catch property therefore protects only the widget→synced direction; the gadget→unsynced direction remains a runtime-discipline question.

The engine side of this work — namespacing the `@function` annotations directly (`@function SpringSynced.X`, `@function SpringUnsynced.X`, `@function SpringShared.X`) so the lua-doc-extractor buckets output files accordingly, plus the missing type decorators — is in [RecoilEngine PR #2799](https://github.com/beyond-all-reason/RecoilEngine/pull/2799). No separate context tag is added; the namespace lives in the `@function` line itself.

The codemod that mass-rewrites call sites for an existing codebase (BAR's case) is open-sourced as part of [BAR-Devtools](https://github.com/beyond-all-reason/BAR-Devtools); other Recoil games can reuse it.

### Options

- **A. Status quo.** Single `Spring` table. Context errors fail at runtime.
- **B. Three-table split (this proposal).** `SpringSynced` / `SpringUnsynced` / `SpringShared`. Per-context envs expose the relevant pair. Legacy `Spring` retired or aliased — *aliasing decision is Decision 2 below.*
- **C. Annotation-only.** Keep `Spring`; add a per-function context tag and a custom checker. *(Hypothetical; not Recoil's pattern today.)*

### Tradeoffs

| Axis | A: Status quo | B: Three-table split | C: Annotation-only |
|---|---|---|---|
| Catches context errors statically | No | Yes (any LSP that reads the stubs) | Yes (requires custom checker) |
| Migration cost — engine | None | Moderate (`@function` annotations namespaced + extractor bucketing + per-context env registration) | Moderate (new per-function tag annotation + custom checker tooling) |
| Migration cost — each game's Lua codebase | None | High (every call site renamed; codemod-able) | Low (annotations consumed automatically) |
| Migration cost — third-party games | None | High; codemod-able if shared | Low |
| Editor autocomplete | All-in-one (incorrect inside one context) | Context-aware out-of-the-box | Possible only with custom plugin |
| Discoverability for existing devs | Familiar | Three namespaces (must know bucket) | Familiar |
| Discoverability for new devs | Implicit (have to remember context) | Explicit in the namespace | Explicit in tooltips |
| Documentation shape | One table | Three tables, possibly cross-referenced | One table + tags |
| Engine surface clarity at the call site | None | High (`SpringSynced.X` reads the context aloud) | Low (still `Spring.X`; tag is metadata) |
| Backwards-compat surface | N/A | `Spring` as deprecation alias (timing in Decision 2) | None needed |

### Upsides of B

1. **Context-mismatched calls fail at edit time, not runtime.** This is the load-bearing property. Today's failure mode — "widget calls SyncedRead, gets nil, crashes when invoked" — is only discovered by running the relevant code path. Post-split, it's a type error caught by `emmylua_check` (or any LSP that reads the generated stubs) at edit time and in CI. For BAR specifically, this drops one of the most common gadget/widget bugs from runtime to type-check time, even before tests cover the path.

2. **Editor experience becomes context-aware out-of-the-box.** Inside a gadget, the LSP hides unsynced functions; inside a widget, it hides synced ones. Any standard Lua LSP that reads the stubs gets this for free — no custom tooling. Hover-docs and goto-definition land on the right table.

3. **Namespace itself reads aloud the context.** A reader sees `SpringSynced.SetUnitTeam` and immediately knows the function is gadget-only. Today the same information lives in the wiki and in contributor memory. This also forces engine-source discipline going forward: adding a new Lua-exposed function requires authoring it under the right `@function SpringSynced/SpringUnsynced/SpringShared.X` namespace, which is information the engine *should* be tracking anyway.

4. **Codemod-able mass migration.** The split is mechanical: each function has a deterministic correct destination based on its engine-side namespace. BAR has done this on its own codebase via the [`mig-spring-split`](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7290) leaf in the BAR-Devtools migration tooling — the migration ships as a single reviewable PR rather than a hand-edited rolling refactor. Any game with a similar shape can reuse the codemod.

### Downsides of B

These are real costs, and the "three starting points" framing in particular is the one that gets cited as the muscle-memory tax.

1. **Three namespaces means three "starting points" for type lookup.** Today: "what's the function for X?" → look at `Spring.X` and grep. Post-split: "is X synced, unsynced, or shared?" → know the right table first, *then* find the function. For developers familiar with the existing API, this is muscle-memory friction (a contributor who reaches for `Spring.Echo` will land on the wrong namespace until the codemod or LSP corrects them). For new developers it's actually clearer because the context is explicit — so the cost falls disproportionately on existing contributors. Cross-namespace search tooling (the LSP, project-wide grep) mitigates but doesn't eliminate this.

2. **Type-stub generation gets more complex.** The lua-doc-extractor tooling has to bucket output files by `@function` namespace. PR #2799 wires this up. For Recoil maintainers, the ongoing cost is that every new Lua-exposed function has to be authored under the correct `SpringSynced` / `SpringUnsynced` / `SpringShared` namespace in its `@function` line — discipline, not a one-time cost.

3. **Fork compatibility surface.** Recoil-based games that have their own widget/gadget code (Zero-K, BYAR-Chobby, MetalFactionTA, etc.) need to either migrate (codemod-able, but the surface is large) or rely on the deprecation `Spring` alias. The shim approach is straightforward technically but adds a deprecation lifecycle for the engine to manage.

4. **Documentation has to be re-shaped.** Existing wiki pages, tutorials, third-party blog posts, and forum answers say "see `Spring.X`" everywhere. The search-and-replace surface is wide, and historical material can't easily be retroactively fixed. During the deprecation alias window, old `Spring.X` calls still work; after the alias is removed, anyone reading old docs sees calls that don't compile.

5. **API stability across versions becomes coarser.** A function that was added as unsynced and later becomes safe to call synced today is an internal engine detail. Post-split, it's a namespace move — a more visible API change. This makes some classes of evolution slightly more disruptive.

6. **"Which context is this function?" disagreements.** For functions whose context is ambiguous or has changed, putting them in a single canonical table forces a decision. Some functions might end up in `SpringShared` defensively when really they should be `SpringUnsynced`. The split surfaces these debates instead of letting them stay implicit.

### Scope: why just `Spring`?

`Spring` isn't the only table whose surface varies by context. `gl` and `RmlUi` are unsynced-only (a gadget calling `gl.X` blows up at runtime). `os`, `io`, and `debug` are partially restricted in synced for determinism reasons (no `os.time`, no `os.execute`, etc.). `math.random` is technically callable in synced but using it breaks replay determinism — convention is to reach for sync-safe sources instead. None of these context restrictions are reflected in the type stubs today.

The underlying mechanism (per-context type stubs registered into per-context environments) generalizes to all of these. This RFC scopes to `Spring` for cost/benefit reasons:

- **`Spring`** is by far the largest surface (~hundreds of functions) and where the bug class shows up most. Migration ROI is highest there.
- **Standard libraries** (`os`, `io`, `debug`) are upstream Lua APIs that BAR/Recoil contributors already know from outside the engine context. Reshaping `os` into `osSynced`/`osUnsynced` would diverge from every Lua reference, tutorial, and AI completion in the world. The cost ratio is dramatically worse than for the Recoil-specific `Spring` table.
- **`gl` / `RmlUi`** fit the same conceptual bucket as `Spring` — Recoil-specific modules with runtime context restrictions the type system doesn't express today. They're smaller (one-context-only), so the fix is just a one-shot annotation rather than a namespace split. Reasonable candidates to ride along with this RFC; can also land independently if scope creep is a concern.

### Migration considerations

#### For the engine

- Namespace every Lua-exposed `@function` annotation directly (`@function SpringSynced.X` / `@function SpringUnsynced.X` / `@function SpringShared.X`) — no separate context tag, just the `@function` line itself. PR #2799 lays groundwork.
- Update lua-doc-extractor / recoil-lua-library to emit three tables instead of one.
- Register each function into the right per-context environment. This may already be the case at the C++ level — what's changing is the Lua-side surface.
- *(Already done as part of PR #2799: Recoil's own docs were updated to reflect the three-table layout. The legacy `Spring` table's status — alias-with-deprecation, or kept indefinitely — is Decision 2 below.)*

#### For each Recoil-based game

- Run a codemod (BAR's is open-sourced; others can reuse or roll their own — the rule is mechanical). Mass-PR the rename across the codebase.
- Update game-side polyfills/overrides that staple things onto the `Spring` table to staple onto the appropriate `SpringX` table instead.
- Update game-side type stubs and wiki/docs.

#### For third-party tooling

- Custom Lua LSPs and editor extensions need to point at the new stub layout.
- AI assistants (Copilot, etc.) that have been trained on `Spring.X` patterns will surface stale completions for some time.

### Recommendation

**Daniel/attean — B (three-table split).** The static-catch property is genuinely valuable and not achievable cleanly under A or C. C requires custom tooling that no out-of-the-box LSP supports, which means each game maintaining the checker; B leverages the standard Lua LSP infrastructure that already exists. The migration cost is real but bounded (codemod-able, one-time per codebase), whereas the cost of A is unbounded over the long run as the context-mismatch bug class keeps recurring.

The "three starting points" cost is the most cited downside. My counter is that the cost falls on existing contributors during the migration window, and is offset within months by the editor-tooling improvement (autocomplete becomes correct, not noisy) and within the first year by the bugs-not-shipped delta.

This is a recommendation, not a position taken on behalf of the projects involved. Each game's maintainers and the Recoil engine maintainers have their own constraints I don't see fully.

---

## Decision 2: `Spring` deprecation timing

**Conditional on Decision 1 = B.** If the three-table split lands, what happens to the legacy `Spring` table? It exists today; the split adds three namespaced tables; `Spring` can either be deprecated immediately, deprecated later, or kept indefinitely as a permanent typed alias.

This decision is independent in principle (you could split tables without ever touching `Spring`'s status) but only meaningful if Decision 1 = B is adopted.

### Options

- **A. Deprecate immediately.** When Decision 1 lands, `Spring` is marked `---@deprecated` in the type stubs. LSPs (lua-language-server, EmmyLua) surface a soft warning at every `Spring.X` call site. Runtime behavior unchanged — the alias still works — but every editor open of legacy code shows yellow squiggles encouraging migration. Engine docs explicitly say "use the namespaced form."
- **B. Deprecate later.** `Spring` ships as a typed alias without `@deprecated`. At some future point — after BAR's migration lands cleanly, after Zero-K signs on, after some specific engine version, etc. — the `@deprecated` tag is added. The "later" specifics are intentionally left to opinion-holders to flesh out.
- **C. Maintain forever.** `Spring` is a permanent typed alias. Never deprecated. Both forms (`Spring.X` and `SpringSynced.X`) are blessed and expected to coexist long-term. The static-catch property of the namespaced form is opt-in for those who want it; existing code stays type-clean indefinitely.

### Tradeoffs

| Axis | A: Deprecate now | B: Deprecate later | C: Forever |
|---|---|---|---|
| Migration pressure on game maintainers | High (LSP nag is constant) | Low until the timer fires | None |
| Time-to-clean-codebase | Short — pressure produces motion | Variable | Indefinite |
| Friction for contributors during transition | Yellow squiggles in legacy files until migrated | None initially; spike when timer fires | None ever |
| Risk of premature pressure on under-resourced forks | Real — small games may not have bandwidth to migrate quickly | Mitigates by waiting | Eliminates |
| Signal clarity to ecosystem | Strong: "the `Spring` table is the old way" | Mixed: "you can use either, we'll tell you when to switch" | "Both forms are fine, pick what you like" |
| Risk of two equally-blessed APIs becoming a permanent split | None (deprecated form is going away) | Low (deprecation eventually arrives) | High — there's no forcing function |
| Effort cost to the engine | One-line `@deprecated` annotation, one-time | Same one-line annotation, deferred | None |

### Recommendation

**Daniel/attean — A (deprecate immediately).** Soft LSP warnings are the gentlest possible nudge — they don't break anyone's code, don't change runtime behavior, and don't gate any merge. They just put the migration story in front of contributors at the point where the migration is cheapest (when they're already editing the file). C concerns me because "two equally-blessed APIs" tends to ossify into "everyone uses the old one because that's what the docs/wiki/AI-completions still show," which is exactly the state that motivated this whole RFC. B is reasonable but I'd want a concrete trigger ("when X happens, we add the tag") rather than indefinite deferral.

The one objection I take seriously: under-resourced games with small maintainer teams might find the constant LSP warning demoralizing if they have no bandwidth to migrate. The mitigations are (a) `Spring` still works at runtime, so there's no actual breakage, and (b) most LSPs let users disable specific deprecation warnings per-workspace. But the concern is real.

This is a personal recommendation; opinion-holders below have weight here, especially anyone speaking for a smaller Recoil-based game.

### Open questions specific to Decision 2

- **For B (deprecate later): what's the trigger?** "After BAR migrates"? "After Zero-K opts in"? "At engine version X.Y"? "After 12 months"? Each opinion-holder choosing B should specify.
- **For A: which LSPs actually surface `@deprecated`?** lua-language-server does; EmmyLua does. Custom in-house tooling may not. Are there contributor populations who'd never see the warning?
- **For C: what's the eventual story for AI-assistant completions and external docs?** If both forms are permanent, do we expect contributors to learn "the right one" by convention?

---

## Open questions (cross-cutting)

1. **Codemod portability across games.** BAR's codemod is in [BAR-Devtools](https://github.com/beyond-all-reason/BAR-Devtools). Other Recoil-based games could reuse it, or write their own. Is there appetite for a shared "spring-split codemod" maintained at the engine repo level for any game's use?
2. **Functions that change context across engine versions.** A function might be added as unsynced and later become safe to call synced. Post-split, this becomes an API-visible namespace change rather than a release-note item. Is this acceptable, or do we want a "promote/demote" mechanism that preserves the old name as an alias?
3. **What's truly "shared"?** Some functions work in both contexts today by accident or by convention. The split forces a decision per-function. Who owns the categorization, and what's the appeal mechanism if a game disagrees with the engine's choice?
4. **Coordination with related work.** RmlUI, the new lobby/client overlays, and any in-flight Lua refactors will be affected. Is this RFC the right vehicle to coordinate timing, or should that conversation happen separately?

---

## Audience and stakes

Each stakeholder group has a different shape of cost/benefit:

- **Recoil engine maintainers.** One-time cost: namespace existing `@function` annotations into the three tables; wire the extractor to bucket output files; decide on the legacy `Spring` table. Ongoing cost: discipline on new function additions to author them under the right namespace. Benefit: cleaner public API, fewer "why does this crash?" issues filed against the engine.
- **BAR maintainers.** Already done internally on a branch; just need the engine-side work to land to consume it cleanly. Benefit: drops a recurring class of bugs from runtime to CI.
- **Zero-K maintainers.** Migration cost falls on the project; benefit is the same as BAR's. Whether they migrate is a per-project decision, but the engine carrying the deprecation alias keeps the option open.
- **Other Recoil-based games (smaller projects).** Same migration tradeoff as Zero-K; smaller surfaces mean migration is cheaper but the maintainer pool is also thinner. The deprecation-alias path is most important for these.
- **Third-party tooling authors and AI assistants.** Indirect impact; longer tail of stale completions and out-of-date examples.

---

## References

- [RecoilEngine PR #2799](https://github.com/beyond-all-reason/RecoilEngine/pull/2799) — engine-side enabling work (lua-doc-extractor wiring + missing type decorators).
- [BAR's `mig-spring-split` PR (#7290)](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7290) — concrete codemod-driven migration on the BAR codebase.
- [BAR's spring-split triage doc](spring_split_triage.md) — covers the long-tail of `Spring.X` references that needed manual attention beyond the codemod, useful for any game running the same migration.
- [BAR-Devtools codemod runner](https://github.com/beyond-all-reason/BAR-Devtools) — `bar-lua-codemod spring-split` is open-source and reusable.
