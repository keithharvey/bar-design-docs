# Execution handbook

Companion to the plan documents. They say what to build; this says how to build
it here without breaking things, and — more importantly — **how to verify a
claim rather than assert one**. Written 2026-07-26 for orchestrated work.

## State at handoff

BAR repo (`/var/home/daniel/code/Beyond-All-Reason`), stack bottom to top:

| branch | upstream | note |
|---|---|---|
| `hello_pawns` | synced | PR #8424 (1/5) — the foundation stage commit |
| `matchflow_extraction` | synced | #8464 (2/5) |
| `bar_editor` | synced | #8465 (3/5) |
| `combat` | synced | #8460 (4/5) |
| `cm8_ashfall` | synced | #8461 (5/5) |
| `modes` | **ahead** | #8462 — `Scripted` renamed `Mission`, unpushed |
| `gui_chat_state` | **ahead** | precursor commit inside #8463 |
| `sharing-v2` | **ahead** | #8463 — checked out |
| `gui_chat_locals` | synced | #8467, standalone vs master |

Devtools repo: branch `combat`, all committed. Its `bar-mission-kit` is the
editor tooling; its `just/bar.just` holds every recipe named below.

**`wip-orders-ac`** branches off `sharing-v2` and carries two commits that are
not yet on their stage commits. Each names its restack target in its message:
order C -> `bar_editor`, order A -> `hello_pawns`. Suite is 408/0 there
(397 baseline + 11 new specs). Nothing is pushed.

The stripped trailing newlines seen on `cm8_ashfall/{units.lua,
triggers/outpost.lua}` were **not** the kit — `apply_edit` was proved
byte-exact over a 213-operation sweep against the real CRLF tree. Suspect the
editor the panel hands files to (VS Code `files.trimFinalNewlines`).

## Environment

Nothing but `git`, `python3`, and `just` is on the host PATH. `cargo`, `node`,
and `lua` live in the `bar-dev` distrobox.

    just bar::units                     busted suite          expect 397/0 on sharing-v2
    just bar::mission-kit-test          kit tests + terminal JS syntax gate   expect 50/0
    just bar::mission-check <dir>       recognizer over a missions/modules tree
    just bar::integrations              headless engine suite  expect 7 pass / 0 fail
    emmylua_check -c .emmyrc.json .     type check (host has this one)

    # cargo, from the Devtools repo
    DEVTOOLS_DIR=$PWD bash scripts/mission-kit-cargo.sh {build,test,build --release}

    # anything needing node/lua
    distrobox enter bar-dev -- bash -lc '<cmd>'

Serve runs the **release** binary, so rebuild `--release` after kit changes or
the running editor keeps the old behavior.

### File hygiene

- **BAR working-tree files are CRLF.** Never `sed -i`. Edit via `python3` with
  `open(p,"rb")` / byte-preserving writes, or the Edit tool. A `$`-anchored
  regex will silently miss every line.
- Baselines differ per branch. `emmylua_check` on master lineage reports
  hundreds of pre-existing errors — the bar is **zero new errors in touched
  files**, measured by filtering the JSON output to those paths and comparing
  against the same filter on the unmodified tree.

## Gates that actually prove something

Pick the gate that can fail for the reason you care about.

**Pure moves / refactors → tree identity.** The strongest gate available:

    git rev-parse <branch>^{tree}     # must equal the pre-refactor tree hash

If content should not change, prove it did not. This caught nothing during the
module fold *because it was used*; it is the reason that refactor was safe.

**Behavior-preserving code edits → token equivalence, with a caveat.** Compare
lexed token streams, normalizing whitespace/quote-style/trailing commas. But:

> A token-collapse proof is **blind to missed conversions.** When mapping
> `state.X` back to `X` to compare, an unconverted `X` and a converted
> `state.X` collapse to the same token, so a half-finished refactor passes.

This shipped a real crash (`attempt to index global 'I18N'`). The correct
companion gate is a **bare-reference scan**: after an alias-removal refactor, no
name in the alias set may appear outside a field access or a table-constructor
key. Generalize the principle: *ask what the proof cannot see*, and add a second
check that sees exactly that.

**Lua that must load in-engine → parse it with stock Lua 5.1.** It enforces the
200-local `LUAI_MAXVARS` ceiling that cargo/busted cannot see:

    distrobox enter bar-dev -- bash -lc 'lua -e "assert(loadfile(\"<file>\"))"'

To measure headroom, append `local __p1..N` probes and bisect until it fails.

**Embedded scripts → syntax-check them separately.** `terminal.html`'s
`<script>` is invisible to cargo; a redeclaration there blanks the whole panel
while every test passes. `just bar::mission-kit-test` now extracts and
`node --check`s it. Anything else embedded needs the same treatment.

**Editor/tooling changes → render the real tree.** Run serve against
`modules/missions/cm8_ashfall` into a scratch editor dir and grep
`mission_view.json`. Tests pass on fixtures; the real tree finds the rest.

## Subagent discipline

Observed failure mode, worth designing against: **a subagent will report a
proof that does not hold.** The gui_chat agent reported a "byte-exact
reverse-map proof" for a refactor that had seven unconverted call sites, and its
proof genuinely could not see them.

So when delegating:

- Give the **exact command** for each gate and require its output verbatim.
- Require a gate that can fail for the specific hazard, not a general one.
- Ask what the proof does not cover; treat "nothing" as a wrong answer.
- Diffs should be **reviewed by category** ("every changed line is a comment
  line") and that claim independently spot-checked.
- Scope agents to **disjoint file sets**; concurrent agents in one repo make
  `git add -A` unsafe. Prefer explicit path staging over `-A` while any agent
  is running.

## Git discipline for this stack

- **Bottom to top, always.** Retarget PR bases first, then push the base-most
  branch, then each child in order.
- **Before any force-push, enumerate open PRs by head branch** (`gh pr list
  --head <branch>`). A batch force-push of three branches to one commit
  false-merged #8427 permanently (GitHub marks it MERGED; the badge cannot be
  removed) and auto-closed #8426. The remembered PR map is not authoritative.
- **The stack-widget trap:** a PR added to a GitHub *stack object* has its base
  locked ("part of a stack") and cannot be retargeted — #8408 had to be closed
  and re-minted. Chain by base branches only.
- **Backups before history edits:** `git branch backup-<what>-<branch> <branch>`
  for every branch touched. Existing families: `backup-preslice-*`,
  `backup-prevocabfold-*`, `backup-premodesinfra-*`.
- **`hello_pawns` is a presentation branch** — rebuild it from the stage tree,
  never cherry-pick into it:
  `git commit-tree <stage>^{tree} -p <merge-base> -m "<subject>"`.
- **No `Co-Authored-By` or AI attribution in commits.** The sharing-module
  generator script still injects one — strip it after running `transform`.

## Do not touch

    modules/missions/sharing_trials/          user scratch
    modules/missions/types/dsl_env_proposed.lua   user scratch (deliberately unmarked)
    modules_iteration branch                  derived; the user deletes it

## Decisions, as answered 2026-07-26

1. **Does #8463 land first?** No — ordering does not matter much. The split can
   follow the modules that require it, with the purely multiplayer module after
   that.
2. **Is the mode `category` string a wire value?** **Yes.** "sharing" is
   consumed by the BYAR-Chobby `sharing_tab` branch, which drives the mode
   dropdown. So renaming the module must not rename the category, or both ship
   together.
3. **The ahead branches** (`modes`, `gui_chat_state`, `sharing-v2`) get their
   PRs closed and renamed with proper scope — the branch names read badly if
   they stay open as-is. Not started; do it bottom to top.

## Where the work stands

`work_orders.md` holds the briefs. A, C and D are done (A and C on
`wip-orders-ac`, D committed in Devtools as the `EditJournal` rebase). **B — the
combat contract — is not started**, and was deliberately held because it shares
`mission_loader.lua` with order A.

One caveat order A surfaced that B inherits: the staging swap rolls back the
*trigger engine*, not other modules. A contribution that mutates module-level
state during a load (combat's ledger) still leaves that behind when a later file
fails. "A failed load changes nothing" is true of the mission, not the process.

## Known work not in any plan

- **In-game RCSS.** Every editor change from this session (summary tiles,
  chips, module rows, graph, `me-hidden`, jump rows) is styled in the web/VS
  Code terminal only. The in-game stylesheet is
  `modules/missions/rml_widgets/mission_editor.rcss` on the **`bar_editor`
  stage**, so styling it means amending that commit and restacking all seven
  branches. Parked pending approval.
- **Spawn add/edit.** The Units section has no "+ add spawn"; the palette is
  trigger-only. Needs `Spawn`/`.At`/`.Named`/`.Grouped` templates in
  `surfaces/missions.json` and a roster-aware add row.
- **Module runtime state.** The Reference shows what a module *publishes*, not
  what it is *doing*. The bridge already samples probes — a per-module probe
  manifest would light up combat's protected ledger, matchflow's pending
  verdict, allies' active mode.
- **Events in the Reference.** Conditions declare `inputs` (the closed
  `MissionEventName` bus), but nothing surfaces them. That is the third leg
  beside conditions and effects: what can happen.
