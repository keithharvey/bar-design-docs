# Sharing squash audit — 2026-07-26

The 14-commit sharing tail (4173376d6e..sharing-modules) replayed onto the rebuilt modes
chain and squashed to one commit on `sharing-v2`:

    b6a59ba45d sharing: expressed through the mode grammar — lib, policies, economy, gadgets, tech, the tab

Diff vs `modes`: **149 files, 12,778+ / 2,049−** (raw squash was 22,717+ / 11,247−; ~44% of
insertions and ~82% of deletions were noise). Busted: 400/0 throughout.

## Noise removed (mechanical, token-gated)

The sharing commits ran stylua over every game file they touched; master is not
stylua-formatted, so touched files carried thousands of lines of reformat. Removed by
token-level splice (modes' formatting for token-equal runs, sharing's tokens for real edits),
treating as neutral: whitespace, `'`↔`"`, trailing comma before `}`, `['x']`↔`x` keys.
Gates: lexer token-stream equality vs the sharing tree, `loadfile` parse check on all 45
Lua files in bar-dev, full busted suite.

Worst offenders: gridmenu_layouts 4,298→255 diff lines (real change: keystone entries in
18 con grids + 3 voussoir tables), buildmenu_sorting 1,384→~10, gui_advplayerslist
5,905→974, gui_chat 1,388→267, cmd_dev_helpers 947→98.

## Bugs found and fixed in the squash

- **gui_chat.lua failed to load in-game**: sharing's additions put the main chunk at 201
  locals; engine `LUAI_MAXVARS` is 200 (verified in RecoilEngine luaconf.h). Dropped the
  single-use `spGetMyTeamID` alias. Now 200 exactly — zero headroom, see refactors below.
- **modoptions spec invariant was obsolete**: rewritten from "modules contribute zero
  options" to "module fragments are the list's tail, exactly once" and modoptions.lua now
  pulls fragments via `ModuleHandler.ModOptions()` instead of the inline sharing include.
- **spec output noise**: spec_helper's `VFS.SubDirs` shim leaked `find:` stderr for
  optional module dirs; silenced.

## Refactors applied (direction: the module owns its vocabulary)

- `modes/sharing_mode_enums.lua`, `modes/sharing_mode_helpers.lua` →
  `modules/sharing/mode_{enums,helpers}.lua` (29 references). Repo-root `modes/` is gone.
- `export_game_modes.lua` dropped its transitional `modeDirs()` shim (root scan + comment
  "ModeDirs takes over when the module loader lands" — it landed) and now uses
  `ModuleHandler.ModeDirs()`.

## Kept, with reasoning

- `types/engine.lua` — vendored Engine.Synced/Shared annotations, TODO tied to
  RecoilEngine discussion #2953. Not cruft until upstream ships the context split.
- `spec/no_substrate_globals_spec.lua` — the guard from the residue commit; keeps
  detach-bar-modules namespaces from leaking back into carried files. Drop after merge.
- `.github/workflows/export_game_modes.yml`, `luaui/Tests/sharing/*` — the export feature
  and headless tests, part of the story.

## Refactor opportunities (not done — flagged)

1. **gui_chat is at the 200-local ceiling.** Sharing's half-finished `state`-table refactor
   moves ~20 fields into `state` then unpacks them all back into locals. Finish it (drop
   the unpack aliases, reference `state.*`) or revert it; either buys real headroom.
2. **Carried files vs module.** The sharing lib still lives in
   `common/luaUtilities/sharing/` ("carried files speak Spring again") while the module
   shell is `modules/sharing/`. When the module loader story allows, fold the lib into the
   module and the substrate-globals guard retires with it.
3. **advplayerslist module extraction** (`gui_advplayerslist_modules.lua`) is the right
   pattern — the m_* block as a factory. Candidate to go further: the sharing-tab widget
   consumes `ApiExtensions`/`Helpers` from `common/.../gui_advplayerlist/`; same fold as (2).
4. **restack.sh topology is stale**: `STACK=(hello_pawns matchflow_extraction bar_editor)`
   + `SHARING=sharing-modules` predate the fold; chain is now
   matchflow_extraction → bar_editor → combat → cm8_ashfall → modes → sharing-v2, and
   hello_pawns is the separate fat-fold presentation. Needs a deliberate topology decision
   before editing.

## Branches

- `sharing-v2` — the squashed sharing commit on the rebuilt chain.
- `ashfall` — QA tracking branch, currently = cm8_ashfall; moves to sharing-v2 when QA
  should pick up sharing. Push: `git push -f upstream ashfall`.
- `sharing-modules`, old `modes` etc. survive as `backup-precommentsfold-modes` + originals
  until deliberately deleted.
