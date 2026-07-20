# Stacked PR #3: Encapsulated `/modules` — the sharing module

Chain: **#1** type migration (fmt, #8235) → **#2** `sharing_tab` (the purely functional refactor) → **#3** this: the same code, given its final form and directory.

PR #2's own description already said the quiet part ([stacked_pr_1_description.md](stacked_pr_1_description.md)):

> a lot of the boilerplate orchestrator functions here are truly framework code, even if they're probably not in their final form or directory.

This PR is that final form: an **encapsulated module format** at root-level `modules/`, where the module name is the namespace and everything inside is organized by **domain, not technical category** — plus auto-loaded subdirectories, a manifest + contract per module, module-owned **modoptions**, and module-contributed **mode presets**.

## Why now, and why this shape

Three codebases converged on the same answer independently:

| Source | What it proved |
|---|---|
| **PR #8226** (Mission API: Refactor Actions, sorenmarkert) | One file per action; a declarative descriptor `{name, parameters, execute}`; `VFS.DirList` discovery + deterministic sort; schema prevalidation with named log errors; shared modules should load once |
| **The policy-engine spike** (`policies` branch, 2023) | Policies want to live one-per-file, registered by category, evaluated in order with first-result-wins; a fluent builder is nice ergonomics for modders |
| **`sharing_tab` (PR #2)** | The whole thing works best as pure typed functions: Context (cached) → Policy → PolicyResult → Action, controllers as the service layer, specs + emmylua as the safety net |

The module format is the synthesis: **PR #2's semantics, PR #8226's packaging, the spike's registration model.**

## The format

The module root **is** the library — no `lib/`. Auto-loaded subdirectories are the only "technical" folders; everything else is domain-scoped, and the module name makes flat names self-explanatory (`sharing/helpers.lua`, `sharing/enums.lua`).

```
modules/
  module_handler.lua            ← framework: discovery, contracts, include-once,
  policy_builder.lua              registries, modoptions/modes aggregation
  types/modules.lua             ← ModuleManifest, ActionDescriptor, PolicyDescriptor
  economy/
    module.lua  api.lua         ← waterfill solver, share stats, manual share ledger
    waterfill_solver.lua  share_stats.lua  manual_share_ledger.lua  team_resource_data.lua
  sharing/
    module.lua                  ← manifest: name, version, requires = { "economy" }, provides
    api.lua                     ← the contract: the ONLY surface outsiders may consume
    modoptions.lua              ← module-owned mod options (section + 25 entries)
    modes/                      ← surrogate mode presets (see below)
    widgets/  rml_widgets/  gadgets/   ← auto-loaded
    actions/                    ← {name, parameters, execute}: the only effectful layer
    policies/
      resource.lua              ← one Pipeline per category: gates in declaration order
      unit.lua
    types/  spec/               ← LuaCATS contracts; co-located busted specs
    enums.lua                   ← (ex transfer_enums)
    helpers.lua                 ← (ex policy_helpers)
    serialization.lua  policy_events.lua  policy_evaluation.lua
    context_factory.lua  unsynced.lua
    config.lua                  ← (ex shared_config: sharing's modoption/tech reader)
    resource/   shared.lua  comms.lua  factor_cache.lua
    unit/       shared.lua  comms.lua  factor_cache.lua  unsynced.lua  categories.lua
    take/       comms.lua
    tech/       blocking.lua  blocking_comms.lua
    policy_views/               ← per-player PolicyResult projections for list UIs
```

**What stays at repo root:** `modes/` (the mode *system* — enums, helpers, the shared vocabulary `modoptions.lua` and many consumers speak), `units/`, `gamedata/`, `language/`, and all modified-in-place core widgets/gadgets. Root `modules/` also still holds the legacy loose shared libs (`i18n/`, `graphics/`, `commands.lua`, …) — tolerated for now; a directory only counts as a module if it has auto-loaded subdirectories or a `module.lua`.

### Policies: pure functions, pipeline per category

Each category is one file — `policies/resource.lua`, `policies/unit.lua` — authored with the Pipeline builder and read top to bottom; order is declaration order, not filename numbering:

```lua
return Policies.Pipeline("resource")
	-- Sharing disabled by mod option denies everything, even when cheating.
	:Gate("SharingEnabled", function(ctx, resourceType)
		if not Config.isResourceSharingEnabled(ctx.springRepo) then
			return deny(ctx, resourceType)
		end
		return nil        -- nil = pass to the next gate
	end)
	:Gate("AlliedOrNonPlayerSender", …)
	:Gate("ReceiverActive", …)
	:Compute("ComputeResourceTransfer", function(ctx, resourceType)
		… -- terminal: always returns the pair's ResourcePolicyResult
	end)
	:Build()
```

Gates return a result to stop evaluation (first result wins) or nil to pass; `Compute` is the enforced-single terminal. This is exactly PR #2's `TryDenyPolicy` → `CalcResourcePolicy` control flow — the spec suite's ordering assertions pass unchanged. The old `*_transfer_synced.lua` delegate shells are **gone**, dissolved into `policy_evaluation.lua` (pipeline entry points) and `resource|unit/factor_cache.lua` (the per-team factor caches).

This is where the DSL earns its keep — it replaces filesystem-as-control-flow, not the semantics: every function inside a gate stays a pure typed function, and the pipeline emits plain `PolicyDescriptor[]` — the descriptor remains the interchange format the framework consumes. (A single-descriptor builder existed briefly as modder sugar; registration-style pipelines made its output unregisterable, so it's gone — dead API doesn't ride along.) No policy engine object; the manifest + descriptors are the automated interface, Lua is the scripting interface.

### Actions: the only effectful layer — registration style

Action files don't return descriptors; they **register**, and identity is the filename:

```lua
-- modules/sharing/actions/unit_transfer.lua   ← action name = filename
local Actions = Actions  -- injected by the loader (the `local widget = widget` idiom)

Actions.RegisterValidate(function(policyResult, unitIds, ...)  -- optional pure precondition, first
	...
end)

Actions.RegisterExecute(function(ctx)  -- exactly one, required; the only effectful code
	...
end)
```

The loader brackets each include, injects the registrar into the file's environment, and assembles the runtime descriptor — never hand-authored. Rails are loud at load: single Execute, Validate-before-Execute, error if a file returns anything. This is the native Recoil idiom — widgets/gadgets themselves (callins defined on an injected object), `actionHandler.AddAction`, `GG.*` publication, LUS unit scripts, busted's `describe/it` — *writing a module action feels like writing a widget*. The counter-current worth naming: `dbg_test_runner` migrated the opposite way (ambient hooks → returned tables) because **anonymous globals under setfenv** are fragile; explicit named `Register*` calls on an explicit local are the widget-handler family, not that one. Policy pipelines use the same idiom (`:Register()` terminal) so the framework has one registration story, like the spike. There are no hand-written parameter schemas — call sites are statically typed, and a *derived* schema (generated from the LuaCATS annotations) returns if a data-driven dispatcher (mission_api migration, CampaignAPI) ever creates a runtime boundary. Controllers consume the registry (`SharingActions.byName.resource_transfer.execute(ctx)`); consumers never include action files directly. mission_api is the obvious second tenant of this format.

### Contracts between modules — explicit partition, implicit resolution

The manifest declares the state partition **explicitly**: `provides` is a plain path (state-agnostic) or `{ shared, synced, unsynced }`. `ModuleHandler.Get("sharing")` resolves **implicitly**, merging shared + the current Lua state into one flat api — a consumer never picks a state (it has one), so a widget holds `Sharing.Resources`/`Sharing.Units` (with the `ShareUnits` graft) while a synced gadget holds only the shared surface, and wrong-state access is nil at the first index instead of a crash three calls deep. This mirrors the engine's own behavior (state-appropriate API exists or doesn't; nobody writes `Spring.Unsynced.X`), and the OG spike shipped exactly this pair (`api_team_transfer.lua` + the synced service). Per-state contract files are plain eager tables — the lazy metatable existed only to keep one file safe in both states, so it's gone. Deep includes of `modules/sharing/**` from outside are a boundary violation. `modoptions.lua` and mode enums stay direct data includes (lobby context, shared vocabulary). The manifest partition is also precisely the metadata the engine RFC would enforce (checksum exemption, per-state loading guarantees).

The dependency direction is real, not decorative: **`modules/economy/`** is its own module (waterfill solver, share stats, manual share ledger) and sharing declares `requires = { "economy" }`, consuming it via `ModuleHandler.Get("economy")` — `Discover()`'s dependency validation exercises an actual edge. The boundary forced one honest inversion: the waterfill solver is tax-agnostic (`Solve` takes an optional `getTeamTaxRate` resolver); sharing's config reader (`modules/sharing/config.lua`, ex `shared_config`) stays in sharing because it reads sharing's modoptions and tech state. `gui_top_bar`/`gui_teamstats` consume `ShareStats` from economy's contract, so sharing's api only exports things that are actually sharing.

**Synced-state gotcha:** the synced Lua environment strips `rawset`, so lazy `__index` contracts must use plain assignment (`api[key] = value`) — equivalent here since only `__index` is defined. Discovered when the resource controller first resolved a contract entry from synced code.

### Module-owned modoptions

A module ships `modoptions.lua` — same entry format as the root file, including its own section entry. `ModuleHandler.ModOptions()` merges fragments in module-name order and the game's `modoptions.lua` appends them; all 25 sharing options moved out of the root file, which now contains **zero** sharing references. `module_handler` logs via `print` fallback when `Spring` is absent, so lobby/unitsync LuaParser contexts can parse modoptions. *(Downstream note: Chobby/SPADS integrations that read mode presets from `modes/sharing/` must learn the module path — we control that branch.)*

### Surrogate modes

Mode presets travel with the module that owns the modoptions they lock: the five sharing presets live at `modules/sharing/modes/`. Root `modes/` remains the system — enums, helpers, category vocabulary — and aggregation uses `ModuleHandler.ModeDirs()` (the game-modes export scans root `modes/<category>/` plus module dirs; presets self-describe via `mode.category`).

## Engine loading (the Recoil RFC)

Game-side shims until the engine learns the layout: `luarules/gadgets.lua` and `luaui/barwidgets.lua` scan `modules/*/gadgets|widgets|rml_widgets` through `ModuleHandler`. The RFC (referencing RecoilEngine#2781) should be precise about *which half* of `module_handler` the engine absorbs — it isn't all of it.

**The engine's half** (boring and universal):

1. **Discovery + manifests** — `modules/<name>/module.lua` is a mini-modinfo; `Discover()` + `requires` validation is the engine's archive scanner wearing a fake mustache. The manifest format becomes engine API at that point (the `version` field starts mattering; BAR extensions stay explicitly outside the engine-spec surface).
2. **Load-once includes** — an engine-blessed, VFS-backed `require` with per-state caching (deterministic in synced). This kills the game-side cache *and* the class of sandbox bug we hit with `rawset` — sandbox constraints are the engine's to own. It is also literally #8226's "shared modules load only once" complaint, solved generally.
3. **Subdir auto-loading** — basecontent widget/gadget handlers scan `modules/*/widgets|gadgets|rml_widgets` natively (`widgets/` guaranteed unsynced), replacing our two shim hooks.
4. **`Get()` as service resolution** — `provides` → contract table; just `require("sharing")` once the above exists.
5. **The real prize: mounting** — modules as separate (rapid-distributed) archives layered onto a game. This one *cannot* be done game-side and is the actual modder story: drop in an archive; its manifest declares `requires`; its subdirs, modoptions, and modes self-register.

**The game's half, regardless:** the opinionated conventions — `actions/`/`policies/` semantics, descriptor schemas, `Pipeline`/first-result-wins, the LuaCATS contracts. The engine should never know what a PolicyDescriptor is; `module_handler` doesn't vanish, it sheds discovery/caching/loading and shrinks to the conventions layer. That's a feature of the pitch, not a concession: the engine spec stays tiny and games extend it.

**Why engine-side at all — composition, not perf.** Same VM either way: engine loading buys zero FPS; once files are loaded, engine-native and game-side hooks produce indistinguishable runtime states. Every real benefit lives *before* the VM boots or *across* boots — territory Lua can't reach: the VFS mount set is fixed at startup, so only the engine can make a module shippable as its own archive ("a rapid tag a game composes" vs. "a folder convention inside BAR.sdd"); **sync-boundary granularity** (a pure-UI module exempt from the synced checksum so UI mods don't gate lobbies, and "this module's gadgets are never scanned synced" as an engine *guarantee* rather than a convention a buggy module can violate); **cross-boot caching** (compiled chunks keyed by archive checksum — cold boot wins only the VM's owner can deliver); **one module identity across the four VMs** (synced, unsynced, LuaUI, LuaMenu each re-derive discovery today); lifecycle correctness (`/luarules reload`, synced/unsynced pairing handled uniformly instead of by shims); and modules contributing **unitdefs through the defs pipeline** — the piece this PR explicitly punts on (`units/` stays at root) becomes reachable exactly here. Note Recoil already has archive-level `depends` in modinfo; manifest `requires` is that idea one level down, which is the tell it belongs engine-side.

**The staged pitch:** (1) engine loads module subdirs + include-once semantics — this alone deletes the shim; (2) modules as mountable archives with manifest-level `requires`; (3) someday, per-module runtimes. Only stage 1 is needed to land; nothing built here is stranded by the later stages. The long-game framing: the format is **language-agnostic at the layout level** — manifests, opinionated subdirs, descriptors, typed contracts survive a runtime change; only the file extensions do not. The realistic endgame isn't "delete Lua" but *stratification*: something typed and deterministic for module internals — Teal/Luau are the cheap rungs (the LuaCATS annotations are most of a Luau port already), a deterministic WASM runtime the far one — with Lua kept as the thin modder-facing skin. Lua-the-VM is load-bearing for Recoil's determinism model and Lua-the-language for the modder ecosystem, which is the same split as "the module DSL is the automated interface; Lua is the scripting interface." Types come the honest way meanwhile (emmylua in CI); perf comes from promoting hot paths behind engine APIs, as Recoil already does. The RFC framing that future-proofs against the Lua question instead of being mooted by it: *embrace the layout and archive semantics; the contract layer stays ours; the runtime under it is swappable later.*

The shim **is** the RFC — reference implementation plus semantics, which is how Recoil proposals actually land. The pitch has teeth now: two real modules with a validated cross-module dependency, headless-engine-proven, mission_api as the obvious second migration, and #8226 as independent demand. And nothing blocks on it: Recoil PRs move slowly (#2642 is still open), the shim works today, and every `ModuleHandler.Get()` call site is a one-line mechanical swap when the engine call exists.

## Maintenance: `just bar::sharing-module`

The branch is `sharing_tab` + 7 commits, fully regenerable (BAR-Devtools `scripts/sharing-module/`):

1. `modules: module framework + loader hooks` *(cherry-picked)*
2. `modules: relocate sharing stack into modules/sharing` *(GENERATED from move_map.tsv — the whole domain tree is data)*
3. `modules: sharing module contract (manifest + api)`
4. `sharing: policies/ and actions/ in descriptor form`
5. `sharing: dissolve synced delegate libraries`
6. `modules: module-owned modoptions`
7. `modules: surrogate modes (module-contributed mode presets)`
8. `modules: extract economy module (first cross-module dependency)`
9. `sharing: policy pipelines — one file per category, no filename ordering`
10. `sharing: de-redundant contract keys`

The module is **`sharing`** — the same word players configure (mode category, modoption section, tab UI), the ubiquitous-language argument that won after trying `team_transfer` on for size. The vocabulary is then banished from the lineage entirely: sharing_tab itself carries `sharing: banish team_transfer vocabulary` (`common/luaUtilities/team_transfer/` → `common/luaUtilities/sharing/`, `types/sharing.lua`, `luaui/Tests/sharing/`, the unsynced facade renamed `SharingUnsynced`), and zero tokens remain in either tree. What survives untouched is *mechanism* naming — `unit_transfer`/`metal_transfer` policy types and engine callins like `AllowUnitTransfer` — because those name what the code does, not the module. The namespace stutter was the real complaint and it was in the contract *keys*: the api is domain-shaped and state-resolved: shared surface `Enums`/`Units`/`Take`, unsynced overlay `Resources`/`Units.ShareUnits`/`AdvPlayerList.{Helpers,ApiExtensions}` — organized by domain, never by file layout (we're in sharing or we're not).

`rebuild` replays everything on the current sharing_tab tip (verified byte-identical); `verify` = stale-path grep + emmylua vs baseline (1/1 pre-existing `gui_pip.lua`) + busted (292/292; sharing_tab baseline 269 intact). Headless engine smoke: all module gadgets/widgets load from module paths, modoptions parse with the aggregation, widget-failure set identical to the sharing_tab baseline.

## Out of scope (deliberately)

- The Recoil PR itself — RFC sketch above.
- Migrating mission_api / i18n / graphics into the format.
- Builder surface beyond `policy_builder.lua`; descriptors stay canonical.
- `units/` + `gamedata/` encapsulation (TechCore unitdefs stay at root until the def pipeline can load from modules).
