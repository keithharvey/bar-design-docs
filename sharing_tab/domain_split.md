# The domain split: units, resources, modes

> [!WARNING]
> **Superseded by `campaign_api/sharing_split_v2.md` (2026-07-26).**
> The units/resources assignment below was derived from what files are *about*.
> Deriving it from what they *include* produced a dependency cycle on every
> attempted seam — see that document. The conclusion there is narrower: extract
> `tech`, rename `sharing` to `allies`, and leave the rest whole. Kept here for
> the reasoning trail.

Decided 2026-07-26. Sequenced **after** the sharing PR (#8463) lands — it is a
pure-move refactor, and pure-move refactors verify against a landed baseline.

## The seam

"Sharing" was never a domain; it was a feature name covering two domains and
their configuration. The subdirectories inside `modules/sharing/` already cut
along the real seams, so the split is mostly `git mv` plus manifests.

| module | owns | publishes |
|---|---|---|
| **units** | unit ownership and the transfer runtime | `Units.Transfer` to the mission sandbox |
| **resources** | resource transfer, tax, and the economy data plane | resource verbs (later) |
| **modes** | how the game is configured to play, and the UI that surfaces it | the mode grammar (already there) |

`sharing` disappears as a concept. Nothing is left over: mechanism goes to the
two domains, configuration goes to modes.

### units

    unit/{shared,comms,synced,unsynced,categories}.lua
    gadgets/game_unit_transfer_controller.lua
    gadgets/game_allied_unit_reclaim_mode.lua
    gadgets/game_allied_assist_mode.lua
    gadgets/game_allow_partial_resurrection.lua

The transfer runtime the engine binds through `SetUnitTransferController`, plus
the gadgets that govern what may be done to units you do not own.

### resources (absorbs economy)

    resource/{shared,comms,synced}.lua
    economy/{waterfill_solver,manual_share_ledger,share_stats,shared_config}.lua
    team_resource_data.lua
    gadgets/game_resource_transfer_controller.lua
    gadgets/game_disable_ally_geo_mex_upgrades.lua

Economy is not a peer domain — waterfill is resource-excess redistribution, the
ledger and share stats are resource accounting, `team_resource_data` is a
resource snapshot. Merging removes the module that never sat right (an
`economy/` directory inside `sharing/`, called out in the squash audit as "the
first cross-module dependency").

### modes

    modes/*.lua                       the presets (disabled, enabled, easy_tax, tech_core, customize)
    mode_dsl.lua, mode_enums.lua, mode_helpers.lua, policy_bundle.lua
    policy_views/*                    the per-player policy UI in advplayerslist
    take/comms.lua, gadgets/cmd_take.lua, widgets/cmd_take.lua
    modoptions.lua

Presets span both domains by nature — `disabled.lua` is `.Deny(Share.Units)` +
`.Deny(Share.Resources)` + `.Tax(...)` — so they live above both. There is no
literal "sharing tab": the player-facing surface is the mode preset chosen in
the lobby plus the policy views rendered inside `gui_advplayerslist`. Take is
policy-configured cross-domain behavior (the mode grammar already has `Take.*`
nouns: `.Deny(Take)`, `.Defer(Take)`, `.Delay(Take.<Category>)`), so it belongs
with modes rather than with either domain.

### Undecided / on their own track

- `enums.lua`, `serialization.lua`, `policy_events.lua`, `context_factory.lua` —
  cross-cutting policy vocabulary. Default: keep with modes; promote to a thin
  shared lib only if both domains end up importing them.
- `tech/`, `gadgets/game_tech_blocking.lua`, `rml_widgets/gui_tech_points/`,
  and the TechCore unit content — arguably a **tech** module of its own. Tech
  Core is a distinct feature, not sharing configuration. Split it separately.

## Why this ordering matters

The mission DSL's `Units.Transfer` currently calls `Spring.TransferUnit`
directly from the loader — a second implementation of the transfer the units
domain owns. It should call the module's contract instead, the way missions
calls combat's.

(No live bug: `Spring.TransferUnit` does not consult `AllowUnitTransfer` —
verified in the engine source — so scripted mission transfers already bypass
policy, which is the correct semantics. Mission fiat is not taxable.)

The dependency that follows is on **units**, a small domain module that can sit
low in the stack, *not* on the whole sharing feature. That is the payoff of the
split: it dissolves the ordering problem instead of paying for it.

    missions  -> units, combat, matchflow
    modes     -> units, resources

Without the split, `cm8_ashfall` would have to sit above sharing and the PR
stack would need reordering. With it, nothing moves.

## Execution notes

- Mechanical: `git mv` per a move map, quote-anchored path rewrites, per-module
  manifests, `types/dsl.lua` for anything publishing sandbox vocabulary.
- Gate on **tree identity** where content should not change, plus `busted` green
  (397/0 at the time of writing) and `bar-mission-kit check` over the modules
  tree. The module fold (2026-07-26) is the worked example.
- Each module needs a `module.lua` manifest with `requires`; the kit derives the
  editor surface from the manifest graph, so the dependency list must be honest.
