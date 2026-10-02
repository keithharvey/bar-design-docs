# Sharing split v2: the graph says don't

> [!WARNING]
> **Superseded by `sharing_domain_slice.md` (2026-07-26).**
> The three cycles below do not exist. Each was produced by filing shared
> vocabulary (`enums`, `context_factory`) inside one of the domains; once the
> substrate is named, the include graph is acyclic and `unit/` and `resource/`
> have zero edges between them. The substrate measures 9% of the module, not
> "most" of it. The conclusion that missions should keep its own
> `Spring.TransferUnit` call is also wrong — it conflates mechanism with
> authorization and leaves missions outside the policy pipeline's events,
> ledger and stats. Kept for the reasoning trail.

Implementation plan. Written 2026-07-26 against `sharing-v2`, derived from the
include graph rather than from what files are *about*.

**Supersedes `../sharing_tab/domain_split.md`.** That draft proposed
units + resources + modes. This one concludes: **extract `tech`, leave the rest
of sharing whole, and rename it.** The reasoning below is the deliverable — the
moves are small once the categories are right.

## Three cuts, three cycles

I tried the split three ways. Each one produced a dependency cycle, and the
cycles were not accidents of layout.

**Cut 1 — units / resources.** Both transfer controllers include
`context_factory`, which includes `team_resource_data`; mode presets span both
domains. Put the context in `modes` and `units` depends on `modes` depends on
`units`.

**Cut 2 — add a `transfers` substrate below both.** Fixes cut 1, but the
substrate turns out to be most of the module: enums, context, events,
serialization, the resource snapshot. Splitting a system in half and calling the
shared half a substrate is not a split.

**Cut 3 — by system (transfers / economy / construction).** The best of the
three, and still cyclic:

    game_disable_ally_geo_mex_upgrades  ->  enums (UnitType.Utility)   construction -> transfers
    game_resource_transfer_controller   ->  tech/blocking (GetTaxRate)  transfers -> construction

When every proposed seam creates a cycle, the code is telling you it is one
system. The include graph inside `modules/sharing/` is dense; the edges leaving
it are few.

## What sharing actually is

Not "unit sharing plus resource sharing." It is **allied interaction**: what
teammates may do to, and receive from, each other.

    transfer units      transfer resources     take an empty team's assets
    assist their builds reclaim their units    resurrect their wrecks
    upgrade their mexes  tax on what flows

One policy pipeline (`context -> policy -> policy_result -> action`) evaluates
all of it. One set of mode presets governs all of it. One vocabulary
(`enums`, `unit/categories`, `policy_events`, `serialization`) describes all of
it. That is a coherent module, and it has a membership test a stranger can
apply: *does this govern what allies may do to or for each other?*

Contrast the names that failed the durability test. `units` and `resources` are
**nouns**, and nouns do not partition an RTS codebase — combat, construction,
intel, and orders all touch units too, so a module named `units` can only ever
mean "unit code we happened to write here." Systems partition; nouns do not.

**Rename it `allies`.** "Sharing" undersells it (assist and reclaim are not
sharing) and collides with the `Share.*` mode nouns. `allies` states the
membership test in one word. Keeping the name `sharing` is an acceptable
no-op alternative; renaming to `units`/`resources` is not.

Two corrections to file assignment that fell out of reading the code, both
staying inside the module:

- `economy/shared_config.lua` is not economy — it is `isResourceSharingEnabled`,
  `getTaxConfig`, `getTeamTaxRate`. Tax is transfer policy. Move it to
  `resource/tax_config.lua`.
- `economy/` therefore holds only allied-sharing accounting (`waterfill_solver`
  redistributes excess *to allies*, `manual_share_ledger` and `share_stats`
  record what was shared). It is sharing's accounting, not a separate economy
  domain. Keep it; rename the directory `ledger/` if the word keeps misleading.

## What does extract: tech

Tech Core is a build/tech feature that happens to expose a tax hook. It passes
the membership test for its own module (*does this govern what a team may build
at its tech tier?*) and fails sharing's.

    modules/tech/
      tier.lua                    from tech/blocking.lua: resolveByTechLevel
      gadgets/game_tech_blocking.lua
      rml_widgets/gui_tech_points/
      units/**/TechCore/*, scripts/Units/…, unitbasedefs/tech_blocking_defs.lua

The one edge that remains is honest and one-directional: **allies → tech**, to
read a team's tier when deriving the tax rate. `tech/blocking.lua` splits along
that line — `resolveByTechLevel` is tech's, `GetTaxRate` and `AnyTaxConfigured`
are the tax rate and move to `allies/resource/tax.lua`.

Extracting tech also removes ~1,140 lines of unit content from #8463, which is
the second-largest bloc in that PR's diff accounting.

## The missions question, resolved

The original motivation for splitting was that `Units.Transfer` (used by
`cm8_ashfall`) is implemented in `mission_loader` as a raw `Spring.TransferUnit`
call, duplicating what sharing owns — and that fixing it would make missions
depend on sharing, inverting the PR stack.

It is not duplication. **Mission fiat and player sharing are different
operations:**

- Sharing's transfer runs the policy pipeline: validate, tax, notify, respect
  the active mode. A player asked; the rules answer.
- A mission's transfer is authoritative. The script said so. It must succeed
  under `disabled` as much as under `enabled`.

Verified in the engine source: `Spring.TransferUnit` does not consult
`AllowUnitTransfer`, so the mission path already bypasses policy — which is the
correct semantics, not an oversight. Missions keeps its own transfer, missions
does not depend on allies, and the stack does not move.

The thing worth fixing is smaller: the loader should transfer through a named
capability rather than an inline engine call, so the *intent* (authoritative,
policy-exempt) is stated where a reader will find it.

## Order of work

Land after #8463. Steps 1–2 are the whole plan; 3 is optional cleanup.

1. **Extract `tech`.** Moves + `module.lua`; split `tech/blocking.lua` at the
   tier/rate line; `allies` gains `requires = { "tech" }`.
   Gate: busted 397/0, tree identity on moved files, no stale
   `modules/sharing/tech` paths.
2. **Rename `sharing` -> `allies`.** Directory, manifest, ~40 include paths,
   the ten external consumers below, `.github/`, `luaui/Tests/`. Mechanical and
   verifiable by grep; the mode category string stays `sharing` unless the lobby
   is updated in lockstep (it is a wire value — see open questions).
3. **Internal tidy** (optional, no module boundary changes):
   `economy/shared_config.lua` -> `resource/tax_config.lua`;
   `economy/` -> `ledger/`.

## Gates (every step)

- `just bar::units` — 397/0 at the time of writing.
- Tree identity for pure moves: content byte-identical, only paths change.
- `just bar::mission-check <modules root>` — the kit reads manifests, so a wrong
  `requires` surfaces as a missing-vocabulary finding.
- `git grep 'modules/sharing'` clean, including `.github/` and `luaui/Tests/`.

## External consumers (same commit as the rename)

    luarules/gadgets/cmd_idle_players.lua
    luaui/Widgets/{cmd_share_unit,gui_teamstats,gui_chat,gui_advplayerslist,
                   gui_top_bar,gui_tax_buildspeed_debuff}.lua
    luaui/Tests/sharing/*.lua

## Open questions

- **Is the mode category a wire value?** Presets carry `category = "sharing"`,
  and SPADS/Chobby consume the exported JSON. If the string crosses the wire,
  renaming the module must not rename the category — or both must ship together.
  Check before step 2.
- **Does `economy` ever leave?** Only when a non-allied consumer appears (a real
  production/storage system). Until then, extracting it invents an edge for no
  reader's benefit.
- **Construction.** cm8 Beat 1 wants a construction module for build
  restriction. It is mostly *new* code; the assist/reclaim/resurrect gadgets are
  allied-interaction policy and should stay with `allies`. Build the module when
  the beat is built, and let it own restriction, not sharing rules.
