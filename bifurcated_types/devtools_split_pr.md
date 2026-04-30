# Splitting bar-fmt into focused PR branches

`bar-fmt` is the integration branch (~30 commits ahead of master). Most of those
commits are gated by an open RFC (spring-split, dev_setup) and should ride
together as that work lands. But a handful are useful right now and aren't
gated by any RFC outcome — those have been extracted into focused branches off
`origin/master` and are ready to push as separate PRs.

`bar-fmt` itself is left alone and continues to be the integration branch for
the gated work. After each focused PR merges, `git rebase origin/master` on
`bar-fmt` cleanly drops the merged commits.

## Already-split branches (not covered here)

| Branch                | Notes                                                                       |
|-----------------------|-----------------------------------------------------------------------------|
| `windows`             | Windows + WSL2 setup. Gated by Decision 3 of dev_setup RFC, but self-contained. |
| `lua-check`           | `just lua::check` recipe + scoped reset + `build` alias + lux-shape revert. |
| `lua-library-types`   | RecoilEngine — spring-split (lives in RecoilEngine, not BAR-Devtools).      |
| `minor_types`         | RecoilEngine — type fixes only (lives in RecoilEngine).                     |

## Tier A — 4 ungated improvements, one branch each

### ~~`fix/lua-library-cleaning`~~ — subsumed by `lua-check`

The `clean_dir` step it added is preserved in the surviving `library` recipe
after the lux revert lands on `lua-check`. Branch can be deleted; do not
open a PR for it.

### `dev-image-install-gawk`

- **Branch SHAs:** `679a2bd`  *(cherry-pick of bar-fmt `9961c69`)*
- **Title:** `dev image: install gawk in dev.Containerfile`
- **Description:**
  > Adds gawk to the dev container so scripts that require GNU awk extensions
  > (versus busybox awk) work inside the distrobox without surprise.
  > Containerfile-only change.

### `doctor-teiserver-local`

- **Branch SHAs:** `881d8af`  *(cherry-pick of bar-fmt `f46fed1`, conflict-resolved against master's reworked `scripts/doctor.sh`)*
- **Title:** `doctor: handle local teiserver checkout in scripts/doctor.sh`
- **Description:**
  > Small `scripts/doctor.sh` tweak so the doctor recipe works correctly when
  > teiserver is configured as a local checkout via `repos.local.conf` rather
  > than cloned. Doctor-script-only change.

### `integrations-local-volume-mounts`

- **Branch SHAs:** `c97758b`  *(cherry-pick of bar-fmt `21d2183`)*
- **Title:** `compose: integrations get local volume mounts`
- **Description:**
  > Adds `docker-compose.integrations.local.{sh,yml}` so contributors can mount
  > their working trees into the integrations stack instead of relying on the
  > in-image copies. Useful for anyone iterating on integration-test code
  > locally. Wires the recipe into `just/bar.just`.

## Tier B — editor setup as a single branch

### `editor-setup-emmylua`

- **Branch SHAs (oldest first):** `7972f75`, `2245e2a`, `6f673f5`, `476eed1`
  *(cherry-picks of bar-fmt `d51501c`, `2ba8084`, `4ba8465`, plus a fresh
  follow-up commit. `d51501c` had a conflict against master's
  `just/bar.just` because the bar-fmt-side `CODEMOD_*` vars belong to the
  gated codemod work; resolution drops them here and keeps just the
  EmmyLua wiring.)*
- **Title:** `feat(setup): editor integration via EmmyLua + extension install`
- **Description:**
  > Four commits ship a coherent editor-setup story:
  > - `7972f75` improve setup::editor for emmylua (initial wiring)
  > - `2245e2a` VS Code extension install in `just::editor` + workspace settings template
  > - `6f673f5` ramp up the anti-sumneko prompt (make it harder to land on the wrong LSP)
  > - `476eed1` drop force-formatOnSave from the BAR workspace template — re-enabled by the bar-fmt PR
  >
  > Not strictly RFC-gated — EmmyLua is the de-facto LSP for BAR's bindings
  > today (LuaLS/sumneko is too slow to parse them effectively). This PR just
  > configures the editor to use what already works.
  >
  > Format-on-save is intentionally **not** turned on by this PR: forcing it
  > before the bar-fmt rollout lands would silently rewrite formatting on
  > save in any region a contributor touches. Manual formatting still works
  > (`just bar::fmt`, or "Format Document" in the editor since stylua is set
  > as the default formatter). The `formatOnSave` flag rejoins the template
  > as part of the bar-fmt PR — bar-fmt's existing commits (2ba8084 and
  > 9235234) already carry it, so once this PR merges and bar-fmt rebases,
  > those commits become the canonical source of the re-enable.

## Tier C — stays on bar-fmt (RFC-gated, not split)

Everything in `bar-lua-codemod/`, `scripts/codemod/`, `claude/skills/`,
`claude/prompts/`, the spring-split-related README/tracking-issue work, etc.
These ride `bar-fmt` and ship together once the RFCs settle.

## Pushing the focused branches

None of the new branches have remote tracking yet. To push them all:

```bash
cd /var/home/daniel/code/BAR-Devtools
for b in \
    dev-image-install-gawk \
    doctor-teiserver-local \
    integrations-local-volume-mounts \
    editor-setup-emmylua; do
    git push -u upstream "$b"
done
```
