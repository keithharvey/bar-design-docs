> there is a claim of potential benefit, where if I install your tools I would be able to have autocomplete tell me that I can't use synced setters from LuaUI or vice versa.

You're framing this as if the proposal forces tooling. It doesn't — the namespacing lives in the engine-generated stubs whether anyone uses an LSP or not. If you're working in notepad, `Spring.SetUnitHealth` and `SpringSynced.SetUnitHealth` both call the same function at runtime; you see a longer name at the call site, that's it. If you're working with an LSP, you get the static-catch property on top.

I want to push back on the constraint that Recoil's API surface should optimize for contributors who are explicitly opting out of any modern type tooling. That's a real but small population — most active Lua devs in the Recoil ecosystem use EmmyLua, VS Code, or at minimum some form of completion/checking. Designing the engine API around the no-tooling case is an unusual posture for a 2026 codebase, especially when the proposal is strictly additive for that population (you lose nothing).

> Can you tell me which Lua env is `effects/mary_sue.lua` tied to?

Not without looking, but the general answer cleanly covers this:

- **Most files have an unambiguous context.** Widgets in `LuaUI/` run unsynced; gadgets in `LuaRules/` run synced. The current runtime already binds them — that's why `Spring.SetUnitHealth` from a widget fails today. The proposal makes that existing binding visible to the type system.
- **Files genuinely loaded in multiple contexts** (utility includes, shared data) get `@context shared` and call `SpringShared.X`. Functions that exist in both runtimes are exactly what `SpringShared` is for.
- **Gadgets are a related-but-different case.** The file is loaded in both contexts, but each callin runs in exactly one — `gadget:GameFrame` is synced and gets `SpringSynced` access, `gadget:DrawWorld` is unsynced and gets `SpringUnsynced`. The codemod and `@function` stubs handle this per-callin discipline correctly; it's not "the whole file is shared."
- **Config files** (`effects/`, `weapondefs/`, `unitdefs/` — where `mary_sue.lua` lives) are returned tables of definitions. They don't call Spring functions directly; the engine reads the table. No context binding to declare. Ideally these stay declarative (data, not embedded code), so the question doesn't really arise.
- **Files with embedded callbacks** that run in whatever env reads them — those are the legitimate edge case. They get `@context shared` and limit themselves to `SpringShared` calls, OR the callback signature carries the context. Either pattern is expressible.

If a specific file genuinely doesn't fit any of these — and `mary_sue` might be the test case — that's worth investigating, because either the file has a real context-binding bug today (calls a synced function from an unsynced load path) that the proposal would surface, or the type system needs an additional context (which is cheap to add since the mechanism generalizes).

The strawman framing here is "what about my file that doesn't fit the model?" The answer is "every file we have already fits one of these buckets in _runtime_ whether the type system reflects it or not — the proposal just makes the existing reality legible."

> The downside is that this splits the Recoil ecosystem into two groups using different aliases for the same things... BAR can still do this unilaterally without the engine (via `SpringUnsynced = { Foo = Spring.Foo, ... }; Spring = nil`)

The split argument is inverted. The split scenario you're worried about — BAR using one form, other Recoil games using another — only arises if **Recoil declines to ship the option**. If Recoil ships the namespacing canonically (Decision 1: B), every game has both forms available against the same engine API: Zero-K keeps using `Spring.X` (it's still there as the alias under Decision 2: C), BAR uses `SpringSynced.X`, both work, both compile against identical engine type stubs. There is no fork.

The "BAR shims it locally" path is the _bad_ outcome and it's exactly what your concern would create. And it's not even really viable unilaterally — without engine-published authoritative type stubs, BAR loses the ability to verify that its shim is correct. The information "which context is each function in" lives in engine source (the registration sites: `LuaSyncedCtrl::PushEntries` vs `LuaUnsyncedCtrl::PushEntries` vs `LuaParser::AddEntries`). The engine is the only source of truth for which-context-is-which. A BAR-side shim has to mirror that mapping by hand and re-check it every time Recoil adds or moves a function. That mapping rots silently — hard to detect because the runtime still works (the functions exist, just maybe in a wrong-context shim), and the type system can't help because it's downstream of the shim.

So the choice isn't "Recoil ships this OR BAR forks cleanly." It's "Recoil ships this OR BAR maintains a permanently-stale, undetectable manual shim and other games who want this benefit also each maintain their own permanently-stale manual shim, with no shared source of truth." The decision to ship the namespaced form upstream is what _prevents_ the fragmentation, not what causes it.

Decision 2: C closes the loop on the migration-pressure concern. With `Spring` kept as a permanent typed alias, **never deprecated**, both forms remain blessed Recoil API. Zero-K can ignore the namespaced tables and keep writing `Spring.X` indefinitely. There's no deprecation timer, no LSP nag in legacy code, no upstream pressure to migrate. The static-catch property becomes purely opt-in for projects/contributors who want it.

(Note on implementation alignment: the current draft has `@deprecated` on `Spring`, which is closer to a Decision 2: A or B posture. Honoring the C path I'm advocating means that annotation comes off when this ships — one-line change, not structural.)

Given the very real restrictions to BAR-only definitions of these types, what am I missing? Genuinely asking — under B + C, where is the downside that justifies the engine declining to ship this?
