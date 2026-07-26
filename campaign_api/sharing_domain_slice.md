# Slicing by RTS domain

Written 2026-07-26 against `wip-orders-ac`. **Supersedes `sharing_split_v2.md`**,
which concluded "don't split." That conclusion came from a real observation and
a categorization error, and the error is the instructive part.

## Why v2 said no, and why it was wrong

v2 tried three cuts, hit a cycle each time, and concluded sharing is one system.
I extracted every `VFS.Include` edge inside `modules/sharing/`. **There is no
cycle anywhere.** The three it cites do not survive checking:

- *"Both transfer controllers include `context_factory`, so units depends on
  modes depends on units."* Two domains sharing a base is a **shared
  dependency, not a cycle** — unless `context_factory` is filed under `modes`,
  which it should not be. It builds policy contexts.
- *"`game_disable_ally_geo_mex_upgrades` -> `enums`."* `enums.lua` is 44 lines
  of `PolicyType`/`ResourceType`. Filing vocabulary inside a domain manufactures
  the edge.
- *"`game_resource_transfer_controller` -> `tech/blocking`."* One-directional
  and a leaf; `tech/blocking.lua` includes nothing from sharing.

**Every "cycle" came from putting shared vocabulary inside a domain.** The
second objection — that the substrate is "most of the module" — measures at
**9%** (14% counting the mode grammar), off by about six times.

And the fact v2 missed: **`unit/` and `resource/` have zero edges between
them**, in either direction.

## The finding that sets the shape

Of the five gadgets that look like the unit domain, one is about transfer:

| gadget | imports |
|---|---|
| `game_allied_assist_mode` | `mode_enums` only |
| `game_allied_unit_reclaim_mode` | `mode_enums` only |
| `game_allow_partial_resurrection` | `mode_enums` only |
| `game_disable_ally_geo_mex_upgrades` | `unit/synced`, `enums` |
| `game_unit_transfer_controller` | the transfer machinery |

**Four of five are construction policy.** Sharing felt like it spanned
everything because it was holding them. Strip them and what remains is one
system — units, resources and take, all moving **ownership** between teams.
`transfer` is the honest name. **"Allied" is a modifier on other domains'
policies, not a domain**, which is the same reason `units`/`resources` failed
v2's durability test — diagnosed correctly there, then applied to the wrong
conclusion.

## One transfer, authorized by the mode

v2 argued missions should keep its own `Spring.TransferUnit` call because
"mission fiat is a different operation." **That is wrong**, and the correction
matters more than the module boundaries.

It conflates *mechanism* with *authorization*. Transferring a unit is one
operation; whether it is permitted is a policy question. A separate code path
means missions silently escapes everything the pipeline provides — no policy
events, no ledger entry, no share stats, no notification. The engine permitting
it (`Spring.TransferUnit` does not consult `AllowUnitTransfer`) is not a reason
to build a second implementation.

**One implementation owns unit transfer; the mode enables the transfer type.**
A `Mission` mode enabling scripted transfer is the configuration root doing
exactly its job, per `mode_as_configuration_root.md`. Authority becomes a policy
input, not a bypass.

**`Spawn` names its target team.** `Spring.CreateUnit` already takes a
`teamID`. cm8 currently spawns the outpost to gaia and immediately runs
`When(MatchFlow.Started()).Do(Units.Transfer("outpost_auto", Player))` — which
is spawning to the player with extra steps. Name the team at creation and that
transfer disappears.

What remains is genuine mid-mission handover, and **spawn may call transfer's
capability for that** — reuse, not duplication, which is the point of having one
implementation. So `construction -> transfer` is an expected edge, and it stays
acyclic: transfer needs context and tech, neither needs construction.

## Why the substrate is called `context`

It is not a leftovers bucket, and the proof is that it breaks a real cycle:

    tech      game_tech_blocking      -> context_factory
    transfer  resource_transfer_ctrl  -> tech/blocking
              economy/shared_config   -> tech/blocking
              resource/comms          -> tech/blocking_comms
              unit/comms              -> tech/blocking_comms

Transfer needs tech for the tax rate; tech needs `context_factory`. Put the
context inside transfer and that is `transfer -> tech -> transfer`. v2's
instinct that something here resists cutting was right — it misidentified what.

**`policy` names the consumer, not the thing.** The rules that read this live in
`modes` (presets) and in the domains (controllers). What this module provides is
*the facts of a proposed action, assembled once and enriched by whoever knows
something relevant.* That is a context, and the reuse mechanism already exists:
`registerPolicyContextEnricher`, with the registry on `GG` because `VFS.Include`
re-runs per call and a module-local list would split registrar from consumer.

**Every module should reuse it** for one shape of question — *may this action
happen, and what does it cost?* Transfer, build restriction, tech gating and
combat exceptions are all that question; the engine's own vocabulary agrees
(`AllowUnitTransfer`, `AllowUnitBuildStep`, `AllowWeaponTarget`).

**But not the mission `ctx`.** That is services available to a trigger
(`ctx.frame`, `ctx.IsObjectiveComplete`), not the subject of a decision. Merging
environment-for-a-callback with facts-of-a-decision is the same category error
that produced v2's phantom cycles.

**`cache` was considered and rejected**: the caching lives in the domains
(`factor_cache` has specs under both `unit/` and `resource/`) and
`serialization.lua`'s pooled buffer is one file's implementation detail. Naming
the substrate after an optimisation that mostly is not in it would age badly.

## The slice

    modes           grammar, presets, modoptions, policy views
      |
      +-- transfer      units, resources, take, tax, economy
      +-- construction  assist, reclaim, resurrect, mex, roster + Spawn
      +-- combat        protection, stun
      +-- tech          tier gating, tech points
            |
            +---------> context  the facts of a proposed action

Domains import `mode_enums` — vocabulary — never `modes` itself, so
configuration sits above without inverting. The one cross-domain edge is
transfer -> tech for the tax rate; `tech/blocking.lua` already splits along the
tier/rate line.

**Runtime agrees.** The only `GG` surface sharing *defines* is
`GG.policyContextEnrichers` (`context_factory.lua:17`), an extension point
domains register *into* — dependency runs domain -> substrate. Every other
`GG.*` is engine surface. Caveat: several come from the pending RecoilEngine PR
and are not in the local checkout, so this was read, not executed.

**The roster is in the wrong commit today.** `spawnRoster`, `CreateUnit`,
`TransferUnit` and `lib/roster.lua` first appear in the **combat** stage —
because combat's demo needed units to protect, not because they belong to
combat. The slice gives them homes: roster + `Spawn` to construction,
`Units.Transfer` to transfer, and combat keeps protection and stun.

## Stage order

`gui_chat` goes first for a measured reason. Main-chunk local headroom in
`gui_chat.lua`, probed against stock Lua 5.1:

| variant | headroom |
|---|---:|
| upstream/master | **0 locals** |
| after the state-table refactor | 30 locals |

Master sits **exactly on** the 200-local `LUAI_MAXVARS` ceiling. One added
main-chunk local and it stops compiling — which in this engine means the widget
silently fails to load. That is how the `I18N` crash hid: seven broken call
sites produced no error because the widget never loaded. Anything touching that
file before the refactor is a silent breakage.

| # | stage | requires | why here |
|---|---|---|---|
| 1 | gui_chat | — | master has **zero** headroom |
| 2 | hello_pawns | — | trigger runtime + DSL; ships no roster |
| 3 | matchflow | — | one owner of the verdict |
| 4 | bar_editor | missions | the served editor |
| 5 | context | — | breaks the real transfer <-> tech cycle; nothing cuts cleanly without it |
| 6 | modes | context | only consumer of the grammar; `mode_dsl` moves here |
| 7 | combat | — | protection + stun only; the roster leaves |
| 8 | tech | context | before transfer — the tax rate reads the tier |
| 9 | transfer | context, tech | biggest; everything else has left by then |
| 10 | construction | context, transfer | 3 of 4 gadgets need only `mode_enums`; gains roster + `Spawn`, which calls transfer for event-time handover |
| 11 | cm8_ashfall | missions, combat, construction | a mission consumes modules, so it sits above them |

`missions.requires` grows as each module lands — the pattern already in use
(`{matchflow}` at stage 2, gaining `combat` when combat arrives).

## Gates

- `just bar::units` — 425/0 on `wip-orders-ac`.
- Tree identity for pure moves: content byte-identical, paths only.
- `just bar::mission-check modules/missions/cm8_ashfall` — a wrong `requires`
  surfaces as missing vocabulary.
- `git grep 'modules/sharing'` clean, including `.github/` and `luaui/Tests/`.
- Per step, re-extract the include graph and confirm it is still acyclic.
- Per step, probe `gui_chat.lua` headroom if the stage touches it.

## Open questions

- **The mode `category` string is a wire value** — confirmed: BYAR-Chobby's
  `sharing_tab` branch drives its mode dropdown off it. Renaming the module must
  not rename the category, or both ship together.
- **What does a scripted transfer look like in the mode grammar?**
  `.Allow(Transfer.Scripted)`, or an authority field on the policy context. The
  grammar exists; the vocabulary for authority does not yet.
- **Does `construction` own build restriction too?** cm8 Beat 1 wants it, mostly
  new code. Probably, but it does not gate the moves here.
- **`economy` stays inside transfer** until a non-transfer consumer appears.

## Not yet reconciled

`upstream/modes` is `077df5f491`, "…**Scripted** as the surrogate mode" — the
pre-rename commit, so **PR #8462 shows stale content**. The local `modes` branch
was missing entirely and was recreated at `c429b431dc` (parent verified as
`cm8_ashfall`).
