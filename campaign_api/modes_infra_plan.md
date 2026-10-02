# Chain reorder: combat first, modes-infra rides just ahead of sharing

Plan for review before execution. Nothing has moved yet — all SHAs below verified against the
working checkout on 2026-07-25. Supersedes the modes-at-#4 draft: combat swaps in at #4 because
it never needed the mode grammar, and the grammar landing one PR before its first full consumer
(sharing) is the tighter story anyway.

## The chain

```
#1 hello_pawns            module + mission foundation
#2 matchflow_extraction   first extracted module (cm8 Beat 6, already done)
#3 bar_editor             served editor, contract-as-review-surface (PR #8427)
#4 combat                 stun ownership + Combat.Protect (cm8 Beat 2 as acceptance)
#5 cm8 slice (optional)   playable trimmed Ashfall — Beats 2+6 only, pure dogfood content
#6 modes-infra            Mode() joins the DSL; the editor renders it
#7 sharing-modules        first full mode consumer, partitioned correctly from day one
```

Dependency check that makes the swap legal: combat's surface is capability declaration +
event-tense verbs (`Combat.Protect` inside `When` chains). Both exist since #1. `mode_builder`
only matters for standing-tense bundles, and nothing bundles until sharing.

CM8 "Ashfall" (`cm8_ashfall_comparison.md`) stays the standing acceptance spec — each chain entry
checks off a beat; it is the roadmap, not a chain slot. #5 is the one place it partially
materializes early, and it can stay "maybe" without blocking anything after it.

## Phase A — detach the mode grammar NOW (before combat branches)

This happens first regardless of the reorder. The two mode commits sit in `hello_pawns`' history
and contaminate everything stacked above — combat included if it branched today. Current state:

```
b67738b705  missions: the bus vocabulary is closed by type      ← origin/hello_pawns tip
6131f13a41  modules: mode_builder — the mode grammar is foundation
4173376d6e  missions: Scripted — triggers own the verdict        ← hello_pawns tip
    ├── matchflow_extraction (3 commits, tip 99762f4dc6)
    │       └── bar_editor (33 commits, tip 1d4d23b41d)
    └── sharing-modules (17 commits, tip f2397f37be)
```

Old-tip markers are mandatory — matchflow and bar_editor histories contain the mode commits, so
plain `rebase <newbase>` would replay them.

```bash
cd Beyond-All-Reason

# 0. safety net
for b in hello_pawns matchflow_extraction bar_editor sharing-modules; do
  git branch "backup-premodesinfra-$b" "$b"
done

# 1. rewind #1 (lands exactly on origin/hello_pawns — the push becomes a no-op)
old_hp=$(git rev-parse hello_pawns)                     # 4173376d6e
git branch -f hello_pawns b67738b705

# 2. slide #2 and #3 down
old_mf=$(git rev-parse matchflow_extraction)            # 99762f4dc6
git rebase --onto hello_pawns "$old_hp" matchflow_extraction
git rebase --onto matchflow_extraction "$old_mf" bar_editor
```

The mode commits wait in `backup-premodesinfra-hello_pawns` until Phase C mints modes-infra.

**sharing-modules parks.** It consumes `mode_builder`, so it cannot rebase onto any base that
lacks the grammar. It stays on its current old-history base through #4 and #5 and drops out of
restack.sh's rebase/push set until modes-infra exists.

Gates for Phase A:

1. `lx test` green on `matchflow_extraction` and `bar_editor` tips.
2. `git range-diff` old→new for both: content-identical, only reparented.
3. No pushes as a side effect; `restack.sh push` only after review.

restack.sh (devtools `bar_editor` branch — topology's single source) updates in the same breath:
`STACK=(hello_pawns matchflow_extraction bar_editor)` unchanged, but the `SHARING` sibling
variable is commented out with a pointer to this doc (parked until Phase C). `KNOWN_DELETE` and
the merge-base push guard stay.

## Phase B — combat (#4), branched off clean bar_editor

`git checkout -b combat bar_editor` after Phase A. Scope is consumed capabilities only:

- **Stun ownership.** The module owns paralysis behavior: `UnitPreDamaged` / `AllowWeaponTarget`
  callins with flat-lookup registrations (per the cm8 doc's system-B shape). Today stun lives as
  scattered gadget behavior + sharing-modules' unlanded StunDelay/Take machinery
  (`modules/sharing/modoptions.lua` "Stun Delay", ModeEnums.TakeMode.StunDelay). Combat introduces
  the capability fresh; sharing re-references it at #7 — it does NOT reach into the unlanded
  sharing branch.
- **Combat.Protect.** cm8 Beat 2 snippet verbatim as the acceptance test.
- **Byte-exact serialization specs** prove the modoptions output is neutral — same bytes before
  and after ownership moves, so the eventual sharing re-partition is provably behavior-free.

restack.sh grows the branch: `STACK=(hello_pawns matchflow_extraction bar_editor combat)`.

## Phase B½ — cm8 slice (#5, optional)

Expand combat's Beat 2 acceptance into a playable trimmed Ashfall mission exercising Beats 2+6
(combat + matchflow — the only modules in tree). Mission content only, no infra; skippable or
deferrable without touching anything downstream.

## Phase C — modes-infra (#6)

```bash
git checkout -b modes-infra <chain tip>        # combat, or cm8-slice if it became a branch
git cherry-pick 6131f13a41 4173376d6e          # mode_builder + Scripted, verbatim
```

Possible conflict in `types/modules.lua` if matchflow/combat grew it — take both; the cherry-pick
only appends the mode types.

**The exemplar: the campaign editor renders the mode layer.** Not loader/launch wiring (settled;
not relitigating), not an invented "Campaign" mode (no fake capabilities; Scavengers/Raptors/FFA
conversions go to the tracking issue). On modes-infra (BAR) + bar_editor (devtools/bar-mission-kit):

1. **Recognizer learns Mode chains.** Same span/CAS gate machinery as `When` chains; a mode file
   is a single closure-free `Mode("Name")...` chain, discovered under `modules/*/modes/*.lua`.
2. **The form grows a Modes section.** Standing-tense sentences ("Scripted **owns** Match.End"),
   one row per verb link, same flat-card language as Nouns. Standing rules render as statements,
   not events — the two-tense vocabulary stays separate.
3. **Vocabulary projection** from `mode_builder`'s verb grammar (Own/Deny/Allow/Gate…), served the
   same way trigger-file vocabulary already is. The only mode in tree is Scripted — correct, not
   thin: when sharing lands at #7, its five modes appear in the section with **zero editor
   changes**. That sentence is the PR's closer.

PR framing: grammar is foundation, Scripted is the proof a mission can be a mode, the editor is
the first consumer. Tracking issue filed alongside for the preset conversions.

## Phase D — sharing lands (#7)

```bash
git rebase --onto modes-infra 4173376d6e sharing-modules
```

The big one: 17 commits crossing matchflow + editor + combat (+ cm8) for the first time. Known
auto-resolve: `matchflow_verdict.lua` modify/delete → keep deletion. The stun conflicts against
combat are *intended* — resolving them in-place is exactly where sharing sheds its stun
implementation and re-references combat's, with the byte-exact specs proving output-neutrality.
Resolve in place, `git rebase --continue`, never abort-and-restart; afterward verify
`git log --oneline modes-infra..sharing-modules | wc -l` == 17 and
`spec/no_substrate_globals_spec.lua` still passes.

restack.sh final form: `STACK=(hello_pawns matchflow_extraction bar_editor combat modes-infra
sharing-modules)`, one chain, one loop.

Validation pass (from the earlier plan, unchanged): in-game — five DSL modes apply, dropdown
lists once (Chobby dedup `1b9ee24a`), Stun/Defer take behaviors observable, sharing tab UI,
export widget parity; editor — Modes section renders sharing's five modes, gated edits
round-trip. Then trials.lua sharing verbs (mission tense over PolicyEvents) become the follow-up,
informed by `dsl_env_proposed.lua` signatures.

## Explicitly out of scope

- No pushes anywhere until each phase's gates pass and the moves are reviewed.
- `fmt-llm` branches, the devtools bar-fmt re-slice, Chobby `1b9ee24a` — separate tracks.
- User scratch stays untouched: `modules/missions/sharing_trials/`, `types/dsl_env_proposed.lua`.
- `modules_iteration` deletion remains the user's call.
