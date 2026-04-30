# Dev Setup (RFC)

This is an RFC, not a decision. It enumerates the problems we have today, the options for addressing each, and the recommendations. Each decision below is independently reviewable — adopting one does not require adopting the others.

See the overall coordinating issue for context: [Beyond-All-Reason/issues/7408](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7408)

---

## What's broken today

Four concrete problems contributors hit right now:

1. **Lua type errors accumulate uncaught.** There's no enforced static type checking. Errors don't surface until the relevant code path runs and crashes (or silently misbehaves). A real backlog of latent type errors has accumulated in the codebase as a result. Editor-side detection doesn't help much either — the current best-available LSP, Sumneko/LuaLS, is too slow to parse BAR's bindings effectively, so most contributors don't get useful in-editor checking.
2. **Vendored Lua deps drift.** `kikito-i18n` was vendored, then accepted patches not present in upstream, and is now an accidental fork no one fully understands. Other vendored content in `common/luaUtilities/` (json, utf8, base64, serpent) has unknown drift status — verifying would require git archeology.
3. **Per-host setup is undocumented and inconsistent.** Windows contributors hit a wiki, Mac/Linux contributors hit a different one. Tool versions, install methods, and editor settings are per-contributor folklore.
4. **No mechanism for cross-branch transforms.** When a codebase-wide transform lands (e.g., the Spring API split), contributors with open branches must merge in the change manually with no automation.

A fifth concern is *prospective*, not current: once we adopt static analysis and formatting tools with CI gates (per the decisions below), contributor machines need to run them at the same versions CI does. Without that mechanism, CI failures will be hard to reproduce locally. Decision 2 addresses this — it's not a present pain, it's a prerequisite for the rest of the proposal not creating new ones.

---

## Decisions to make

This proposal bundles five separable decisions. Each can be adopted, rejected, or deferred independently.

| # | Decision | Default if rejected |
|---|---|---|
| 1 | Lua package manager (Lux) | Continue vendoring + submodules |
| 2 | Cross-host toolchain consistency mechanism | Continue per-host install |
| 3 | Where contributors run the toolchain on Windows | WSL is currently implicit; alternatives are mingw/native |
| 4 | Task runner (`just`) | Currently in BAR-Devtools |
| 5 | Where the shared scripts/recipes live (BAR-Devtools repo vs in-tree) | Currently in BAR-Devtools |

---

## Decision 1: Lua package manager

**Addresses problem #2** (vendored deps drift).

### Options

- **A. Status quo.** Vendor third-party Lua source into the repo, update by hand. Submodule for `recoil-lua-library`.
- **B. Adopt Lux (`lx`).** Declare deps in `lux.toml`, lockfile-pinned. `lx install` populates `.lux/` (gitignored). Already in the repo on master for test deps (busted/luassert/inspect/dkjson); the `i18n` migration to a runtime dep is in the PR attached to the tracking issue.
- **C. Vendor + periodic-update script.** Keep vendored layout, write a script that pulls upstream + diffs + commits. Maintainer-driven update flow.

### Tradeoffs

| Axis | A: Vendor | B: Lux | C: Vendor + script |
|---|---|---|---|
| Drift prevention | None — kikito case is the existence proof | Contributors manually bump versions with `lx install <package>`. Lockfile is source of truth; `lx install` blows away local edits. | Script must actually be maintained, run. |
| Repo size | Grows with every dep update | Stable (deps in `.lux/`, gitignored) | Grows with every dep update |
| PR review of dep bumps | Reviewer parses 100s–1000s of lines of upstream code | 1-line lockfile bump + adaptation | Reviewer parses upstream code |
| Branch merge conflicts | Conflicts in vendored files contributors didn't write | Lockfile conflicts trivially resolvable | Same as A |
| Publish side (recoil-lua-library) | Doesn't address | Native | Doesn't address |
| Contributor install cost | None | One-time `lx install` (hidden behind setup); `lx sync` when packages drift | None |

### Verified concerns

- **MSVC on Windows: not unconditional.** Lux requires MSVC only when (a) a rock declares C source files in its rockspec, or (b) no Lua installation is detectable via pkg-config and Lux must build Lua from source. BAR's deps are all pure-Lua, so (a) never fires. (b) only fires if the Windows host has no Lua 5.1 install — both msys2 (`mingw-w64-x86_64-lua51`) and chocolatey (`lua51`) ship Lua 5.1 directly, and the WSL path doesn't hit this either. The Lux install docs list MSVC + Visual Studio Build Tools as mandatory, which is over-cautious for our usage; worth filing upstream as a docs improvement and/or a "ship a prebuilt Lua binary path" feature request. Verified against [`lux-lib/src/build/builtin.rs`](https://github.com/lumen-oss/lux/blob/main/lux-lib/src/build/builtin.rs) and [`lux-lib/src/operations/build_lua.rs`](https://github.com/lumen-oss/lux/blob/main/lux-lib/src/operations/build_lua.rs).

### Recommendation(s)

- **Daniel/attean — B (Adopt Lux):** Already partially adopted on master (test deps); the `i18n` runtime migration is the first runtime use, in the PR attached to the tracking issue. The other options leave us exposed to repeating the kikito-style accidental-fork failure.
Marek/p2004a — A (Status quo) / unconvinced of B: At current dep count (1 library, no bitrot), Lux is extremely costly with very little benefit. The case for Lux must rest on future state, not present. Vendoring doesn't need to scale — BAR is not the npm/cargo world with deep transitive dep trees. Single-submodule consumption isn't broken; the cross-org-branches-of-fork pattern in Recoil's CircuitAI relationship was an intentional design choice, not a submodule failure mode.
FlameInk (Nikita) — A or C (maintainer-only vendoring): Not yet convinced making every contributor install `lx` is justified. Position: a single maintainer runs `lx`, commits the resulting `lib/` to the repo; other contributors `git pull` and have what they need without ever touching the package manager. The PR-review-noise cost can be mitigated via PR descriptions naming dependency directories; blame fidelity rarely matters for library code in practice. *Open question raised:* if Decision 3 mandates WSL anyway, the per-contributor `lx install` cost is moot — `lx` is already in the container.
Watch Fort — B is acceptable, sequence packaging one-at-a-time after toolchain lands. "Rip 1 package at a time after this lands" — consistent with the deferred entries (`—`) in the Specific Deps table below.
Boneless / sprunk — against vendoring third-party code (per PR #5902 review, pending verification). Specific positions on package-manager-vs-vendoring need re-reading from the review thread before being characterized further. *(See Open Question #5.)*

### Specific deps

Candidates for Lux migration. The **"In this PR stack?"** column tracks what's delivered by the current proposal — entries marked `—` are deferred to follow-up PRs ("rip 1 package at a time after this lands," per Watch Fort's framing). Deferred ≠ rejected; they're targets for future work, sequenced one-at-a-time so each migration can be reviewed in isolation.

| Dep | Current state | Proposed | In this PR stack? |
|---|---|---|---|
| `kikito/i18n.lua` | Vendored, drifted from upstream | Lux dep (consume existing rock; on `lux-i18n` branch in PR attached to tracking issue) | ✓ |
| `recoil-lua-library` | Git submodule | Lux git dep. Later possibly a lua rock published by Recoil | — |
| `common/luaUtilities/json.lua` | Vendored, drift status unknown | `dkjson` rock (already a test dep) | — |
| `common/luaUtilities/serpent.lua` | Vendored | Upstream `serpent` rock | — |
| `common/luaUtilities/base64.lua`, `utf8.lua` | Vendored | TBD per package | — |


Future deps go through normal review.

---

## Decision 2: Cross-host toolchain consistency

**Prerequisite for the rest of the proposal.** Doesn't address a current pain — addresses the problem that would be *created* by adopting CI gates without a way for contributors to reproduce them locally.

### Options

- **A. Status quo (no shared mechanism).** When tools are adopted, each contributor installs stylua/luacheck/EmmyLua/`lx` at whatever version their extension manager has.
- **B. Containerized toolchain (distrobox in both cases — running natively on Linux, inside WSL on Windows).** Tools live inside a container at versions pinned to match CI. Editor on the host calls into the container.
- **C. Pinned versions per-host with thorough docs.** Each contributor installs the exact pinned version themselves.

### Tradeoffs

| Axis | A: Per-host | B: Container | C: Pinned per-host |
|---|---|---|---|
| Reproducibility of CI failures locally | Variable | Reliable | Possible (relies on contributor diligence) |
| Initial install complexity | Variable | One container install | High — N tools at specific versions |
| Per-tool update cost | Per-contributor | One container rebuild | Per-contributor |
| Works without any new infra | Yes | No (needs distrobox/WSL) | Yes |

### Recommendation(s)

- **Daniel/attean — B (Containerized toolchain):** Per-host has worked historically because there was nothing to be consistent with; once CI gates exist, per-host produces "works on my machine" failures.
- **Marek/p2004a — cross-cutting framing:** The shared scripting layer (BAR-Devtools) is fine to exist; the actual dispute is whether BAR-the-game-repo takes a hard dep on it. That makes Decision 2 a question of "do contributors *need* the container at all", which is bound up with Decision 3's answer. *(No specific A/B/C position stated.)*

---

## Decision 3: Where contributors run the toolchain on Windows

**Addresses problem #3** (Windows setup friction). This is the load-bearing decision for Windows contributors.

### Options

- **A. Windows-native + mingw/msys2.** All tools installed natively on Windows, possibly via msys2 for the bash-flavored ones. No virtualization.
- **B. Windows-native game/engine + WSL for toolchain only.** Edit, build, and run the game on Windows native. Cross to WSL only to run lint/format/type-check/test commands. Build artifacts cross the filesystem boundary one-way.
- **C. Everything in WSL.** Edit, build, and run inside WSL. *(Rejected: 16 GiB-RAM machines crash, GPU passthrough is fragile, and it forces a Linux shell on contributors who don't want one.)*
- **D. PowerShell-everywhere.** Write all recipes in PowerShell Core, which runs on Linux too. Avoids WSL entirely.

### Tradeoffs

| Axis | A: Windows native | B: WSL toolchain only | D: PowerShell |
|---|---|---|---|
| Contributor in their preferred environment | Yes | Yes (game+engine) | Yes |
| Filesystem-perf cost | None | Build artifacts cross once | None |
| Tool ecosystem fit | Some Lua tools (`lx`, `emmylua_check`) lack Windows-first support | Tools run in their native habitat | PowerShell-on-Linux less common; tools still need to be installed natively |
| Compiler requirement | Only if no system Lua 5.1 (msys2 ships one, so usually avoided) | Avoided (Lua in container) | Same as A |
| Maintenance burden | Recipes work cross-platform out of the box | Recipes are bash, run inside WSL | Recipes are PowerShell, run on both |
| Match between contributor and CI environment | Mismatch (CI is Linux) | Match (CI is Linux) | Mismatch (CI is bash on Linux) |

### Recommendation(s)

- **Daniel/attean — B (Windows-native game/engine + WSL for toolchain only):** Game/engine stay Windows-native where the platform support and runtime characteristics are best; toolchain (lint, format, type-check, test, codemod, package install) runs in WSL where the tools' native habitat is. Build artifacts cross the boundary; live source files stay on whichever side the editor is on. This addresses the bulk of WSL-cost concerns. Option A is a real fallback if WSL friction proves too high. Option D is technically viable but requires writing all recipes twice in practice (bash + PowerShell, since most of the underlying tools have bash-shaped entry points).
- **Marek/p2004a — D (PowerShell-everywhere) is a real alternative; or A; framing: optimize for the Windows majority.** Most BAR contributors are on Windows and least experienced; simplicity for them outweighs elegance for Linux/Mac contributors. WSL is heavyweight; PowerShell-on-Linux would let us avoid mandating WSL while keeping cross-platform reach. Also: the "shell exposure" cost is broader than Linux-shell — many contributors aren't comfortable with *any* shell.
- **FlameInk (Nikita) — open question:** Which BAR-Devtools tools actually require WSL/distrobox vs. running natively on Windows? The answer determines how much of the per-contributor cost calculus in Decision 1 still holds. *(Threads into Open Question below about mingw/msys2 viability.)*

### Open questions

- What's the actual filesystem-perf cost of WSL ↔ Windows for BAR's build/test loop today? *(Marek measured a baseline on his hardware — see [Cost of crossing the WSL boundary](#cost-of-crossing-the-wsl-boundary). Daniel to add an option-B baseline + workaround attempts on his hardware as a jumping-off point for performance improvements.)*
- Is `mingw/msys2` viable for `lx`, `emmylua_check`, and `clangd` natively on Windows without WSL? *(Daniel to investigate.)*

### Cost of crossing the WSL boundary

Marek measured WSL↔Windows boundary-crossing costs on his hardware (laptop, AMD Ryzen 7 PRO 6860Z, 32 GiB) to inform Decision 3.

**Test 1 — game load time, source on WSL vs Windows.** Engine + lobby + data folder all on Windows native; only the game source location varies, pointed at via Windows symlink.

| Setup | Cold start | Warm start | Notes |
|---|---|---|---|
| Source on Windows native | ~40s | ~24s | — |
| Source on WSL (cross via symlink) | 7m30s | 4m10s | Repeated freezes mid-load |

**Test 2 — engine FPS, native vs WSL.** Engine running natively on Windows vs running inside WSL via the launcher AppImage.

| Setup | FPS @ resolution |
|---|---|
| Windows native | 60 fps @ 1080p |
| WSL (AppImage) | 1–2 fps @ 900p |

**Test 3 — Python script walking the game repo, recursively reading `.lua` files.** ([Script](https://gist.github.com/p2004a/0998d3f6a0e14af44d40cb9d12296da8).)

| Setup | Runtime |
|---|---|
| Native Windows, files on Windows | ~0.9s |
| WSL, files on Windows (cross) | ~16s |

**Implications for Decision 3:**

- **Test 1** is decisive for the *runtime* path: any path that has the engine read source files across the WSL↔Windows boundary at game-load time is a non-starter. The Option B (WSL toolchain, Windows-native engine) implementation must therefore *copy* (rsync) build artifacts to the Windows side rather than symlinking — symlink-into-WSL is what produced the 7m30s number.
- **Test 2** is not directly relevant to Option B as proposed — Option B runs the engine natively on Windows (cross-compiled via `docker-build-v2`), not inside WSL. The 1–2 fps figure applies to a "run the AppImage in WSL" path nobody is advocating; included here for completeness.
- **Test 3** is the cost driver for *developer* loop tools: anything inside WSL that walks the BAR tree (`bar::check-errors`, `bar::lint`, `bar::test`, the codemod) reads source files. If those files live on NTFS and the tool runs on ext4, every recipe is ~17× slower. Implication: BAR source repo should live inside WSL (`~/Beyond-All-Reason`, ext4), with sync-out to the Windows install dir for the runtime path.

**Action item carried by Daniel/attean:** add a baseline measurement on a second hardware profile, plus instrumented results from `rsync -a --delete`-based artifact handoff (vs symlink) to quantify how close the workaround gets to the all-native baseline. Will be added inline as it becomes available.

---

## Decision 4: Task runner

**Small QoL question. Independent of all other decisions.**

**Current state:** BAR-Devtools already uses `just` (Option A below). This isn't an unsettled choice — surfaced here as a decision because Marek questioned the tool selection in review. Switching to an alternative means migrating the existing recipes; that's a bounded but non-zero cost.

### Options

- **A. `just`** — minimal recipe runner, no config, recipes in a `justfile`. Adds one binary on PATH.
- **B. `make`** — universal recipe/build runner. Makefile syntax is awkward for non-build tasks.
- **C. `mise`** — manages tool versions, environment variables, and tasks via `mise.toml`. Used by Recoil.
- **D. Plain shell scripts** — no abstraction layer.

### Tradeoffs

| Axis | A: just | B: make | C: mise | D: shell scripts |
|---|---|---|---|---|
| Recipe namespacing (`bar::fmt`, etc.) | ✓ | — | ✓ | — |
| Recipe dependencies / prereqs | ✓ | ✓ | ✓ | — |
| Supports project-level config | — | — | ✓ | — |
| Manages tool versions | — | — | ✓ | — |
| Recipe args / parameters | ✓ | partial (vars only) | ✓ | ✓ |
| Universal availability | — | ✓ | — | ✓ |
| Adopted within the BAR ecosystem | BAR-Devtools | various | Recoil | various |

> **Note on "supports project-level config":** This is listed as a *neutral* dimension, but Daniel's recommendation treats it as a downside — see Opinions. The argument is that config support tempts the runner to accumulate state that should live in source repos or docker, eroding the "pure runner" boundary.

### Recommendation(s)

- **Daniel/attean — A (`just`):** Adds welcome conveniences (recipe dependencies, recipe arguments, namespacing like `bar::fmt`) without bringing project-level config. Cost: one binary install. Already used in BAR-Devtools.

  Specifically against `mise` (C): `mise` is more capable, but its config support is the wrong shape for this layer. The whole point of the shared scripting layer is that it's a pure recipe runner — config (tool versions, env vars, tasks-as-data) should live in the source repos or docker, not in the runner. Adopting a config-driven runner like `mise` invites that config to creep into BAR-Devtools over time, eroding the boundary. Recoil uses `mise` and that works for them; for BAR-Devtools the no-config property is a feature.

  This decision is otherwise genuinely opinion-driven; if the org prefers `make` or shell scripts the substantive proposal works the same.
- **Marek/p2004a — B (`make`) or D (shell scripts):** "Never understood why I would use [`just`] vs makefile/bash script, why I would want to have this tool installed." `just` is one more binary to install; `make` is universal and shell scripts are zero-dependency. Surfacing this question is what made Decision 4 a decision in the first place.

---

## Decision 5: Where the shared scripts live

**Addresses problem #3** (per-host setup) and enables addressing problem #4 (cross-branch transforms).

### Options

- **A. Separate repo (BAR-Devtools).** Recipes, setup scripts, and codemod tooling live in a sibling repo. BAR consumes them.
- **B. In-tree.** Same recipes, same scripts, but committed inside BAR.

### Tradeoffs

| Axis | A: Separate repo | B: In-tree |
|---|---|---|
| Reusability for sibling projects (Recoil, BYAR-Chobby) | Yes | No |
| Independent versioning | Yes | Tied to BAR's lifecycle |
| Setup complexity for BAR contributors | Two repos to clone | One repo |
| Coordinating cross-cutting changes | Two PRs | One PR |

### Recommendation(s)

- **Daniel/attean — A (Separate repo / BAR-Devtools):** The setup script and codemod tooling are not BAR-specific; sibling Lua-on-Recoil projects can use them. Splitting this layer also keeps BAR's repo focused on game content, and we seem to be splitting everything up, so...
- **Marek/p2004a — A is acceptable.** Marek's stated position is that the cross-repo scripting layer is fine to exist; his pushback is on Decisions 2/3 (whether contributors need it), not on where it lives. So Decision 5 is not where his disagreement sits.

---

## Game code changes (separate from the toolchain decisions above)

These are CI-side decisions about the BAR codebase itself, not about contributor environment. Listed for completeness.

- **Style.** Single formatter (`stylua`) and linter (`luacheck`). CI rejects unformatted/lint-failing code. Replaces per-contributor preferences.
- **Spring API split.** `Spring` table split into `SpringShared`, `SpringSynced`, `SpringUnsynced`. Static analysis can flag context-mismatched calls without running the game. Addresses problem #1.
- **Strong typing via EmmyLua.** Adds enforced static type checking — surfaces the backlog of latent type errors and prevents new ones from accumulating. Also replaces Sumneko/LuaLS as the editor LSP, which had been too slow to parse BAR's bindings effectively. Addresses problem #1.

---

## New developer commands

`just <recipe>` invokes a task. The recipes contributors will use:

| Recipe | What it does | When |
|---|---|---|
| `just setup::init` | One-shot: container, tools, editor extensions, settings | First-time setup |
| `just setup::editor` | Editor integration only (LSPs, extensions, settings) | Editor reinstall |
| `just bar::test` | Unit + integration tests | Before PR |
| `just bar::check` | Type-check (EmmyLua) | Before PR (also runs in CI) |
| `just bar::fmt` | Format (stylua) | Before PR (also runs in CI) |
| `just bar::lint` | Lint (luacheck) | Before PR (also runs in CI) |
| `just bar::fmt-mig` | Replay codemod transforms onto your branch | After a `mig` PR lands; addresses problem #4 |
| `just lua::library` | Recoil → BAR types pipeline for live API iteration | Engine-side dev |

CI runs `bar::check`, `bar::fmt`, `bar::lint`, `bar::test` and rejects PRs that fail any. With editor setup completed, `bar::fmt` and `bar::check` happen automatically on save.

---

## What gets enforced where

Two distinct tiers land with this proposal. Knowing which is which matters because the stakes differ.

### CI gates (these can fail your PR)

- **`bar::check`** — EmmyLua type-check. Fix the type errors in your code.
- **`bar::fmt`** — stylua. Code must be formatted; editor-on-save handles it for VS Code/Cursor users.
- **`bar::lint`** — luacheck. Most noise clears once `bar::fmt` runs first.
- **`bar::test`** — unit + integration tests must pass.

These are the actual commitment the proposal asks the org to make. Adopting Decisions 1–3 without these gates leaves the proposal's value on the table.

### Host-side helpers (productivity, not enforcement)

`bar::fmt-mig` — replay codemod transforms onto your branch when a `mig` PR lands. Skip it and you do the conflict resolution by hand. Addresses problem #4.
`lua::library` — recoil → BAR types pipeline for live API iteration during engine work. Skip it if you're not touching the engine.
`setup::init` — one-command onboarding (the Decision 5 vehicle). Skip it and you set up tools by hand. Addresses problem #3.

Skipping any of these doesn't fail anything; you just do the underlying work manually instead.

---

## What BAR-Devtools actually does

BAR-Devtools is a shared scripting layer for cross-repo dev tasks. It exists to serve the goals below; the implementation is what `just setup::init` (and the other recipes already covered) concretely does.

### Goals it serves

The decisions above are evaluated against these. Naming them explicitly lets reviewers flag the cases where a decision-level argument is actually a goal-level disagreement — much easier to resolve at the goal level than per-decision.

1. **Onboarding cost is bounded.** A new contributor gets a working dev environment without per-host research or per-tool installer hunting. *(Inverse of problem #3.)*
2. **Local reproduces CI.** A failure on the build server can be reproduced and fixed locally with the same commands. *(Inverse of the prospective concern under "What's broken today".)*
3. **Reviewer attention focuses on logic changes.** Dependency updates and vendored content don't dilute PR diffs. *(Inverse of problem #2.)*
4. **Optimize for the majority contributor demographic.** Most BAR contributors are on Windows and least experienced; simplicity for them outweighs elegance for Linux/Mac contributors. *(Per Marek's framing.)*
5. **Minimize what BAR-the-game-repo has to host or maintain.** Shared toolchain lives outside the game repo so the game repo stays focused on game content. *(Informs Decision 5.)*
6. **Capacity for future package adoption without re-litigating each time.** Establish the mechanism now; evaluate each new dep on its own merits when the time comes. *(Informs Decision 1.)*
7. **Enforcement at the CI gate; everything else opt-in.** Contributors don't have to use BAR-Devtools' productivity helpers; they have to pass CI. *(Reflected in "What gets enforced where" above.)*
### What `just setup::init` does

When a contributor runs `just setup::init`, four concrete things happen. This unpacks the script so it's not a black box.

#### 1. Toolchain binaries land somewhere editors can find them

The distrobox container holds the pinned versions of these binaries (on Linux, distrobox runs natively; on Windows, it runs inside WSL):

- `emmylua_ls` — Lua language server
- `emmylua_check` — Rust EmmyLua analyzer (also what CI runs via `bar::check`)
- `clangd` — C/C++ for engine work *(only relevant for engine contributors)*
- `stylua` — Lua formatter
- `lx` — Lux

On Linux, `distrobox-export` makes these visible on the host's PATH (`~/.local/bin`), so editors running on the host find them automatically.

On Windows, the binaries live inside WSL. The editor reaches them by running inside WSL itself — the standard pattern is the [VS Code Remote-WSL extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl), which lets you "Open Folder in WSL" so the LSP and tools execute server-side in WSL while the UI stays on Windows. Cursor has the same pattern. *(This is what Marek's review comment was pointing at — yes, the Windows-side editor still needs to know the WSL binaries exist; the Remote-WSL extension is how.)*

#### 2. Editor extensions get installed

VS Code / Cursor extensions (with a y/N prompt before applying):

`tangzx.emmylua` — EmmyLua LSP
`JohnnyMorganz.stylua` — formatter
`llvm-vs-code-extensions.vscode-clangd` — clangd
`bmalehorn.test-switcher` — Ctrl+Shift+Y test ↔ source jump

Removed if present (conflicts):

- `sumneko.lua` (LuaLS) — too slow to parse BAR's bindings effectively; takes minutes where EmmyLua takes seconds. Mutually exclusive with EmmyLua so we remove it to avoid duplicate diagnostics.

#### 3. Workspace settings get written into BAR

`.vscode/settings.json` in the BAR repo gets:

- `search.exclude` for `.lux/`, `.devtools/`, `common/luaUtilities/**` — keeps `.lux/` internals and vendored utility noise out of search and the Problems panel.
- `[lua]` formatter = stylua, format-on-save.
- `test-switcher.rules` — maps `spec/<area>/<x>_spec.lua ↔ <area>/<x>.lua`, plus the builder-spec convention.

#### 4. Engine work gets a `compile_commands.json`

*(Skip if you don't work on RecoilEngine.)* If RecoilEngine is cloned, `compile_commands.json` is generated against it so clangd can index the engine code.

---

The bumper for new contributors is the combination of (2) and (3): without the script, every contributor wires the editor by hand, lands on the wrong LSP (Sumneko is the default everyone reaches for), doesn't know about test-switcher, and so on. The script encodes the answer once.

---

## Why Rust appears in this proposal

Two pieces of tooling are Rust binaries:
- `bar-lua-codemod` (the codemod runner used by `just bar::fmt-mig`) is written in Rust.
- `lx` itself is Rust.

BAR-Devtools installs both via `cargo binstall` (which fetches prebuilt binaries — equivalent to `brew install` but for Rust-published tools) inside whichever environment hosts the toolchain — distrobox on Linux, WSL on Windows. For a Windows-native path (Decision 3 Option A), upstream installers would be used instead. No Rust appears in game code.

---

## Open questions

Consolidated from the per-decision sections:

1. ~~Does `lx` require MSVC unconditionally on Windows?~~ **Verified: no.** See Decision 1 → Verified concerns. Only fires for rocks with C sources or when Lua isn't already installed; BAR's deps are pure-Lua and msys2/WSL provide Lua 5.1.
2. What is the actual filesystem-perf cost of WSL ↔ Windows for BAR's build/test loop today? *(Empirical — Windows-host measurement needed.)*
3. Is `mingw/msys2` viable as a Windows-native alternative to WSL for `lx`, `emmylua_check`, and `clangd`? *(Daniel to investigate.)*
4. How many third-party Lua deps does BAR realistically grow to over the next 12 months? *(Stakeholders to estimate; affects cost-benefit of Decision 1.)*
5. On PR #5902, did `@sprunk` weigh in on vendor-vs-package-manager specifically, or only on PR mechanics? Same question for `@[BONELESS]`. *(Daniel to verify before citing.)*
6. If `recoil-lua-library` moves to Lux, what's the migration path for downstream consumers (CircuitAI, other Recoil-based games)? *(Recoil maintainers' input needed.)*

---

## Opinions (tagged by holder)

The body sections above are intended as agreement substrate. This is where positions live.

### Daniel (attean)

Per-decision recommendations are inline under each Decision's Recommendation(s) section. These are cross-cutting positions that inform multiple decisions or sit outside any one of them.

- **Vendoring at scale produces drift in this org specifically.** Kikito-i18n is the existence proof; assume the next vendored dep follows the same path absent a mechanism that prevents it.
- **Single-submodule consumption is fine today; the concern is the future-state pattern, not the technical separation.** What I push back on is the *consumption mechanism*. The Recoil → CircuitAI relationship makes the failure mode concrete: Recoil pulls submodules from a CircuitAI fork on two specific branches, which obligates whoever owns that fork to maintain those exact branches indefinitely or break Recoil. Marek is correct that the AI interface was *designed* to be implementable separately from engine source — that separation is intentional and good. The structural critique is orthogonal: cross-org submodules pinned to specific branch SHAs invert who owns the maintenance burden — the upstream repo becomes the load-bearing party for our consumption shape, not theirs. Add that submodule SHAs carry no version semantics (your master changes SHA regularly with no release-interpretation; `git submodule update` produces meaningless rebase churn), and the pattern accumulates entropy with each new dep. Want to break it before recoil-lua-library is followed by similar deps and we end up where Recoil is.
- **The shared toolchain is load-bearing** for solving problems #1 and #4; the codemod capability is independently reviewable.
- **`common/luaUtilities` should become packages** because the game owns its own utility domain — it shouldn't wait for the engine to provide json/utf8/string helpers it doesn't care about.

#### Response to Marek's PowerShell PoC ([PR #7533](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7533))

The PR itself is good work: SHA pinning, no-admin repo-local install, the `_run.cmd`/`.sh` symmetry — all clean. Lux is a relatively friendly tool to package this way and it's been shown doable. Below is what I'm weighing as I think about whether to extend this pattern to the rest of the toolchain, with corrections from Marek's inline review folded in.

- **Reproducibility.** The dev environment lives in an immutable distrobox container — `setup::init` builds it from a Containerfile manifest, and if anything drifts a contributor with the inclination can `distrobox rm` and rebuild in two minutes with their host untouched. *(Important distinction: the value here is the **system-level** property — every contributor's environment is rebuilt from a manifest, so drift never accumulates in the first place. That's valuable to the project regardless of whether any individual contributor knows or cares how it works; new contributors run `setup::init`, get a known-good environment, and never have to debug drift. Marek's pushback ["they can recover, if they have a clue"] applies to the recoverability case — `distrobox rm`-and-rebuild does require knowing what distrobox is. It doesn't apply to the immutability case, which is the load-bearing one and is upstream of any contributor's knowledge.)* Going native still means install steps that touch the host. *(Original draft of this section claimed the PoC runs an MSI installer; that was wrong — Marek's PR installs into `.tools/` and is fully removable by deleting that directory. Correction noted; the broader concern is about the future-state where additional native tools may not have that property.)*
- **Scope — narrowed to the disagreement that actually exists.** Marek's clarification is important here: he is *not* arguing that BAR-Devtools cross-repo orchestration should be Windows-native, and he agrees that the PoC's pattern is not the right shape for cross-repo. The disagreement is narrower — *day-to-day main-repo dev workflow* (lint, format, type-check, test, codemod, package install). My earlier listing ("the rest of the toolchain") was too loose and didn't separate cross-repo concerns from main-repo concerns; Marek was right to flag that. Locking down which tools are actually in-scope for the slope-cost argument:

  | Tool | Cross-repo orchestration? | Main-repo day-to-day? |
  |---|---|---|
  | `stylua` | No | Yes (`bar::fmt`, CI gate) |
  | `emmylua_check` | No | Yes (`bar::check`, CI gate) |
  | `bar-lua-codemod` runner CLI | No | Yes (`bar::fmt-mig`, after migs land) |
  | Language-server CLIs | No | Yes (CI, pre-commit hooks, scripting) |
  | `mingw-w64` cross-compile | Yes | No (engine devs only) |
  | `lx` | No | Yes (test deps today, runtime deps incoming) |

  The five non-`mingw-w64` rows are the main-repo day-to-day surface; the slope-cost argument applies to that narrowed set specifically, not to the full toolchain. The PoC's ~333 lines went toward `lx`. *(Earlier draft of this section called `lx` "the easy one" — Marek correctly pushed back: lx was actually the hardest of the candidates, requiring installer manipulation and pre-provisioned Lua pre-builds + headers from awkward hosting. So "easy baseline" was wrong, and the slope question genuinely cuts both ways: the painful cases may be front-loaded, or they may compound. I'm not asking the PoC to grow further to find out — explicitly the opposite. The intent is to first see how performant we can get the WSL path with workarounds before extending the bifurcation experiment.)* Granted, several language servers (e.g. EmmyLua) ship as IDE plugins now and don't need a separate CLI install on contributor machines; but the CLI matters for CI, scripting, and pre-commit hooks regardless. Whether the slope stays sublinear is the empirical question to answer, not a settled one.
- **Container comparison.** Adding a tool to the container today is roughly `apt install -y X` in `dev.Containerfile` — every tool gets added the same way, no per-platform bootstrap code. That's a property of having a real package manager inside an image we throw away; Windows doesn't quite have an equivalent today (`winget`/`scoop` are close-but-not-quite, especially on the throwaway property).
- **Honest read.** The PoC is a great existence proof that *one* tool can be done native, and Marek's point that I shouldn't have used "not possible" stands — I should have said "not possible *maintainably* at the cross-repo orchestration scope." For the *narrowed* scope (main-repo day-to-day workflow), the answer is genuinely less clear, and Marek's point about optimizing for the Windows-majority contributor is real.

  WSL2 + container has two properties worth naming precisely (the original draft of this paragraph blurred them, fairly flagged by Marek):

  - **Closure under tool addition.** The PoC achieves *reproducibility* of an already-pinned set of tools via SHA + lockfile — that's real and it's what the PowerShell PoC already gives us today. What the container path adds is that the property carries automatically for any new tool: `apt install -y X` extends the set without writing a new bootstrap module per tool. The PoC pattern requires roughly N × per-tool-bootstrap as the toolchain grows; the container is closed under addition. That's the property comparison; "WSL is reproducible, PoC is not" was a false framing on my part.
  - **Single-implementation contribution surface.** When I said "anyone can extend rather than just consume," I didn't mean licensing — both paths are open source by construction. I meant practical contribution friction: a single implementation means a fix lands once, in one place, in the language the existing contributor pool is already comfortable with (bash). A bifurcated scripting layer (bash *and* PowerShell as parallel trees) means writing fixes twice, testing twice, and triaging which side a bug lives in. The "half of the codebase" framing assumed that bifurcation case — bash on Linux + PowerShell on Windows. If the proposal were instead PowerShell-only as the *single* implementation across both platforms, then "half" is wrong; it'd be the whole. But that's a much larger commitment (rewriting the existing bash recipes in PowerShell) that should be costed separately.

  Even with some hacky rsync workarounds to manage the WSL boundary cost (see Marek's measurements above), I read the trade as still favoring WSL — but the boundary-cost data shifts the implementation work the WSL path needs to do, and I owe a follow-up baseline on my own hardware to put numbers on the workaround quality.
- **Where this leaves the disagreement.** Decoupled from "should cross-repo orchestration be native" (we agree it shouldn't) and from "is mandatory adoption acceptable" (we agree organic adoption is preferable; the question is whether BAR-the-game-repo's CI gates create de-facto mandatory adoption). The remaining live question is: *for the main-repo day-to-day surface, can a Windows-native path stay maintainable as the toolchain grows past one tool?* That's an empirical question better answered by the msys2-viability investigation (Open Question #3) than by re-arguing principles.

### Marek (p2004a)

Per-decision positions are inline under each Decision's Recommendation(s) section. These are cross-cutting positions that span multiple decisions.

- **The cross-repo scripting layer (BAR-Devtools) is fine to exist; the dispute is whether BAR-the-game-repo takes a hard dep on it.** Frames Decisions 2, 3, and 5 collectively.
- **Distinct scopes: cross-repo orchestration vs. main-repo day-to-day workflow.** Marek explicitly does *not* care whether BAR-Devtools' cross-repo orchestration is Windows-native — that surface affects 90%+ of main-repo contributors not at all. The position is about main-repo dev tooling specifically: lint, format, type-check, test, codemod, package install. Argues against making *that* surface require WSL/distrobox; supports organic adoption of cross-repo tooling for those who want it.
- **PowerShell-cross-repo is not the proposal.** Marek concurs that the pattern in [PR #7533](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7533) is not the right shape for cross-repo tooling and is not maintainable at that scale. The PoC is scoped to demonstrating that the *main-repo* surface can install a single tool (`lx`) without mandating WSL.
- **Mandatory vs. organic adoption.** Cross-repo orchestration tooling should not be a requirement of contributing to the main game repo; organic adoption by contributors who find it valuable is the right shape. The question this raises for the proposal: do the proposed CI gates create *de-facto* mandatory adoption of BAR-Devtools, even if it isn't formally required?
- **Optimize for the majority Windows contributor base** — they're also the least experienced; simplicity for them outweighs elegance for Linux contributors. Frames evaluation criteria across all decisions involving contributor-facing tooling.
- **`common/luaUtilities` repackaging needs a stronger motivation.** If something is genuinely useful, it should end up provided by the engine. Affects the Specific Deps table direction in Decision 1.

### WatchTheFort

- **Primary objective is shrinking `common/luaUtilities` and `common/`** by moving content to packages. (Per-decision sequencing position is inline under Decision 1.)

### Boneless

- Pushed back on copying third-party code into the repo in the context of PR #5902 — pending verification of specific positions on package-manager-vs-vendoring (see Open Question #5).
- Otherwise generally supportive.

### Sprunk

- Chaotic neutral; generally supportive but points out he's free from any ramifications of this decision, so more eating popcorn.

### FlameInk (Nikita)

- **The "Why a cross-platform build script" framing was unnecessary** as a distinct section — it should be folded into the per-decision sections. *(Addressed in this restructure: Decision 3 absorbs it.)*
