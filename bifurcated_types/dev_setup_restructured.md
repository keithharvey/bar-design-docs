# Dev Setup (RFC)

*Authors:* Daniel/attean. *Contributors:* Marek, FlameInk.
*Last update:* Apr 26, 2026

This is an RFC, not a decision. It enumerates the problems we have today, the options for addressing each, and the recommendations. Each decision below is independently reviewable — adopting one does not require adopting the others.

See the overall coordinating issue for context: [Beyond-All-Reason/issues/7408](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7408)

## Review table

To be filled in manually by people that reviewed the document and the content looks correct to them. LGTM does not mean approval of the proposed solution, merely accuracy of the document.

| Reviewer | Date | Status | Notes |
|---|---|---|---|
| Marek | Apr 26, 2026 | Waiting | Waiting for confirmation there is no feedback / no-changes after I made changes to the doc |
| Thule | Apr 24, 2026 | Pending | |
| *(put your name here)* | | Pending | |

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
- **Marek/p2004a — A (Status quo) / unconvinced of B:** At the current number of dependencies we have, adding a package manager might be just not worth it. This is not Node.js/Rust world where it's required, a lot of issues with current way of dealing with dependencies might be a matter of better repo hygiene. I've played a bit with Lux, it's pre v1, and quite immature making some parts of the setup more annoying than they could be. But that's just opinion: if we decide to add a package manager, especially given how messy Lux is, having scripts in repo that set all up correctly is effectively a *requirement* and manual setup is not viable at all.
- **FlameInk (Nikita) — A or C (maintainer-only vendoring):** Not yet convinced making every contributor install `lx` is justified. Position: a single maintainer runs `lx`, commits the resulting `lib/` to the repo; other contributors `git pull` and have what they need without ever touching the package manager. The PR-review-noise cost can be mitigated via PR descriptions naming dependency directories; blame fidelity rarely matters for library code in practice. *Open question raised:* if Decision 3 mandates WSL anyway, the per-contributor `lx install` cost is moot — `lx` is already in the container.
- **Watch Fort — B is acceptable**, sequence packaging one-at-a-time after toolchain lands. "Rip 1 package at a time after this lands" — consistent with the deferred entries (`—`) in the Specific Deps table below.
- **Boneless** — against vendoring third-party code (per PR #5902 review, pending verification). Specific positions on package-manager-vs-vendoring need re-reading from the review thread before being characterized further.
- **Sprunk** — *"i don't think i've weighed in on any actual details, but on earlier discord discussions i have been supportive towards the general effort. keep in mind i am entirely unaffected by the changes though so am happy to take arbitrarily bad tradeoffs just to see what happens"* ([quote](https://discord.com/channels/549281623154229250/1494629570077266030/1496954973555134576)).

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
- **B. Windows-native game/engine + WSL for toolchain only.** Edit, build, and run the game on Windows native. Cross to WSL only to run lint/format/type-check/test commands. Source-of-truth for game Lua lives in WSL ext4; the engine, running natively on Windows, needs to read those files at gameplay rate. **How the live source crosses the boundary is a sub-decision** with three live answers — call them B.1, B.2, B.3 — measured in Tests 4–5 below:
  - **B.1 — Pure symlink.** Windows symlink: `<install>/data/BAR.sdd → \\wsl$\<distro>\home\<u>\code\Beyond-All-Reason`. Simplest possible mechanism; this is the path Marek's Test 1 measures, and the result (7m30s cold load, 4m10s warm, mid-game freezes) rules it out.
  - **B.2 — Direct UNC reads at runtime.** No symlink, no copy: configure the engine to read directly from `\\wsl$\<distro>\…`. Probe Test 5 says the dev edit loop is fast under this scheme (77 ms median), but Test 1 shows the engine itself can't read this way at gameplay rate — same Plan9 path, same 7m30s game-load problem.
  - **B.3 — Windows-side watch + copy.** A small watcher process on the Windows side observes `\\wsl$\…` source dirs and mirrors changes to a Windows-local NTFS sync target; the engine reads the local NTFS copy. Probe Test 5 shows the dev edit loop tolerates this at 109 ms median (≈30 ms slower than B.2), and the engine reads from native NTFS — i.e. ≈24 s warm load per Test 1's all-Windows baseline. **This is the recommended sub-option.** Implementation sketch in `bar_launch/plan.md` P3.2 / P3.5.
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

#### Sub-tradeoffs within Option B (live-source-crossing mechanism)

| Axis | B.1: Symlink | B.2: UNC reads | B.3: Watch + copy |
|---|---|---|---|
| Engine read substrate | `\\wsl$\…` Plan9 | `\\wsl$\…` Plan9 | Windows-local NTFS |
| Game cold load (per Test 1 substrate equivalence) | **7m30s** (measured) | ~7m30s (same Plan9 path) | ~24s (NTFS path) |
| Edit-loop median latency (per Test 5) | n/a — filesystem semantics, not a propagation step | 77 ms | 109 ms |
| Implementation cost | None (just `mklink /D`) | None (no sync layer) | Small Windows-side watcher process |
| Dev source-of-truth | WSL ext4 | WSL ext4 | WSL ext4 (Windows copy is read-only mirror) |
| Failure mode if Plan9 hiccups | Game freeze (Test 1) | Game freeze | Edit-loop latency spike; gameplay unaffected |

### Recommendation(s)

- **Daniel/attean — B (Windows-native game/engine + WSL for toolchain only), specifically B.3 (Windows-side watch + copy):** Game/engine stay Windows-native where the platform support and runtime characteristics are best; toolchain (lint, format, type-check, test, codemod, package install) runs in WSL where the tools' native habitat is. The live-source-crossing problem inside Option B is solved by sub-option B.3 — a small Windows-side watcher mirrors `\\wsl$\…` to local NTFS so the engine reads from native NTFS at gameplay rate, while the dev edit loop tolerates the Plan9 boundary at ~109 ms median (Tests 4–5 below; full numbers and implementation sketch in `bar_launch/plan.md` Probe results and P3.2 / P3.5). B.1 (pure symlink) and B.2 (direct UNC reads) are ruled out by Test 1's game-load measurement: both leave the engine reading source files through Plan9, which produces 7m30s cold loads. Option A remains a real fallback if WSL friction proves too high overall. Option D is technically viable but requires writing all recipes twice in practice (bash + PowerShell, since most of the underlying tools have bash-shaped entry points).
- **Marek/p2004a — D (PowerShell / dual native).** I don't like the idea of making the development not-accessible or less performant for the majority of our contributors, especially the less technical ones. I don't like WSL because it's not only system complexity and overhead (additional tens of GiB of disc, virtualization, containers and so on just to run a few tools) but also with high probability of constant performance impact (e.g. formatting potentially taking tens of seconds vs <1s).

  Even if more complex in implementation, "PowerShell"-only or "PowerShell for Windows + bash for Linux" is viable and provides the smoothest experience for Windows users: NONE additional setup — you fork the repo, you double-click `install.cmd` in Windows Explorer and you are 100% done.

  To not speak entirely out of my ass I've built a Proof-of-Concept that works like that for the package manager: [PR #7533](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7533). (Yeah, it's not pretty, but that's not what I'm optimizing for.)

  To be honest, the current description of option A is a little bit not-defined-enough for me to say whether it's viable or not.
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

**Test 4 — Architecture probe: cold tree copy and warm re-read across the live-source-crossing options.** Setup: `BAR-Devtools/scripts/probe_wsl_sync.py` generates a synthetic ~3000-file Lua tree (~600 MB, mimicking BYAR-Chobby's shape) on WSL ext4, then measures cold full-tree copy/read time across the three Option-B sub-mechanisms. Different Windows host than Marek's (Daniel's hardware, Windows 11 + Ubuntu-24.04 WSL2, 2026-05-01). 3 iterations per architecture for (ii) and (iii); (i) is a single hand run.

| Architecture | (a) Cold full-tree | (b) Warm re-read of same tree |
|---|---|---|
| (i) WSL ext4 → /mnt/c via rsync | 26.22s | 8.108s (rsync incremental, no changed files) |
| (ii) Direct `\\wsl$\…` reads from Windows (B.2) | ~31.6s (read-only, mean of 3) | ~31.2s (mean of 3) |
| (iii) Windows-side watch + copy from `\\wsl$\…` (B.3) | ~43.6s (copy, mean of 3) | n/a (auto-orchestrator skips) |

The decision-relevant figure is (ii)'s warm re-read: it stays at ~31s because *re-reading* through Plan9 still requires a per-file round-trip. Any architecture where the engine re-reads source files over `\\wsl$\…` per gameplay-frame multiplies that 31s read by however many frames touch fresh files. This isolates the cause of Test 1's 7m30s game load to per-file Plan9 read latency, not to one-time sync overhead.

**Test 5 — Architecture probe: sustained dev edit-loop latency.** Same probe script. WSL-side touches 5 random files per second for 60s; the measuring side records end-to-end latency from "file written WSL-side" to "fresh content readable on the Windows side." For (ii) and (iii), 3 iterations pooled, top 1% trimmed (the trim drops single-event Plan9/Defender stalls so they don't swamp the central tendency, but raw max is preserved for visibility). For (i), a single run — there's no Windows-side handshake to coordinate, so the auto orchestrator doesn't apply.

| Architecture | Median (ms) | p95 (ms) | Max trimmed (ms) | Max raw (ms) | n / propagator |
|---|---|---|---|---|---|
| (i) WSL → /mnt/c via rsync (poll-rsync @ 200ms) | 7314 | 11090 | — | 11870 | 298 (single hand run) |
| (ii) Direct `\\wsl$\…` reads (B.2) | **77.4** | 127.4 | 141.3 | 176.1 | 891 / 900 (3 auto iters) |
| (iii) Windows-side watch + copy (B.3) | **109.5** | 179.3 | 197.6 | 215.1 | 891 / 900 (3 auto iters) |

Reading:

- **B.2 and B.3 both clear a <500 ms dev-loop threshold** by ~5×. (i)'s rsync-poll architecture does not — at 5 touches/sec the 200 ms poll batches events and the per-tree rescan dominates. So *any* WSL-side-rsync design is dead for sustained edit loops, regardless of which Option-B sub-mechanism we pick.
- **B.2 wins B.3 on raw probe latency by ~30 ms.** B.2 is one Plan9 round-trip per file; B.3 is Plan9 read + local NTFS write per event. The probe shows the cost of the extra write step.
- **B.3 wins on what-the-engine-reads-from.** Pairing Test 5 with Test 1: B.2 leaves the engine on Plan9 at gameplay rate (Test 1: 7m30s cold load); B.3 puts the engine on Windows-local NTFS (Test 1: ~24s cold load). B.3's extra ~30 ms median dev-loop latency buys a ~3.5-minute reduction in warm restart time per session.
- **Methodology footnote.** The probe is a synthetic workload (sequenced touches, 64-byte marker payloads). Real BAR Lua reload involves more files at lower frequency, but is bursty in a way the probe approximates poorly. Read the medians as *floor* numbers the production sync daemon won't beat, not as wall-clock predictions of game-load time. Test 1 is the right reference for game-load wall-clock; Test 5 is the right reference for dev edit-loop responsiveness.

**Implications for Decision 3:**

- **Test 1** is decisive for the *runtime* path: any path that has the engine read source files across the WSL↔Windows boundary at game-load time is a non-starter. Inside Option B this rules out B.1 (pure symlink) and B.2 (direct UNC reads); B.3 (Windows-side watch + copy) is the only sub-option that puts the engine on Windows-local NTFS at gameplay rate.
- **Test 2** is not directly relevant to Option B as proposed — Option B runs the engine natively on Windows (cross-compiled via `docker-build-v2`), not inside WSL. The 1–2 fps figure applies to a "run the AppImage in WSL" path nobody is advocating; included here for completeness.
- **Test 3** is the cost driver for *developer* loop tools: anything inside WSL that walks the BAR tree (`bar::check-errors`, `bar::lint`, `bar::test`, the codemod) reads source files. If those files live on NTFS and the tool runs on ext4, every recipe is ~17× slower. Implication: BAR source repo should live inside WSL (`~/Beyond-All-Reason`, ext4), with sync-out to the Windows install dir for the runtime path.
- **Test 4** isolates the cost driver behind Test 1: per-file Plan9 read latency, not one-time sync overhead. (ii)'s warm re-read still costs ~31 s for the 3000-file tree, which is what makes B.2 a non-starter for the runtime path even though its dev edit loop tests fast.
- **Test 5** establishes that the dev edit loop is fine under B.2 *or* B.3 (both well under a 500 ms target); the choice between them is determined by Test 1 / Test 4 on the runtime side, not by edit-loop latency. (i) is also ruled out for the dev edit loop here, but that's already covered by Test 3.

**Action item carried by Daniel/attean:** Tests 4 and 5 above are the first instrumented-sync results on the second hardware profile this action item asked for; the comparison against Marek's measurements is now in. A `bar_launch/plan.md` Probe results section holds the full numbers, raw JSONs, and the implementation sketch under P3.2 / P3.5. Open follow-up: a (0) NTFS-local baseline (tree generated directly on `C:\`, no WSL involvement) is still pending — it would establish the floor for B.3's cold-copy and edit-loop numbers.

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
- **Marek/p2004a:** My opinions here are not strong, I do not care much. I do not see much benefit in `just` but that's just personal preference. Decision 3 is what matters; Decision 4 for me is more or less implementation details. If it requires additional installs it's just additional overhead. Moreover, I do not care what happens in BAR-Devtools — in this document I care only about impact on the main game repo.

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
- **Marek/p2004a — Both and Neither.** For the workflows *required* for development in the main game repo, that tooling in my opinion must be contained within the main game repo. For cross-repo orchestration, it's for me a separate tooling and separate repo makes sense. Cross-repo orchestration is fine and helpful but needs to be *optional*. Only after it's proven to be good enough and e.g. >90% of people organically use it, we can consider such cross-repo tooling mandatory.

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
2. What is the actual filesystem-perf cost of WSL ↔ Windows for BAR's build/test loop today? *(Marek measured a baseline on his hardware — see Tests 1–3. Daniel added Tests 4–5 on a second hardware profile, which give an instrumented comparison of B.1/B.2/B.3. Still open: a (0) NTFS-local control to anchor the floor, plus a third hardware profile if anyone has time.)*
3. Is `mingw/msys2` viable as a Windows-native alternative to WSL for `lx`, `emmylua_check`, and `clangd`? *(Daniel to investigate.)*
4. How many third-party Lua deps does BAR realistically grow to over the next 12 months? *(Stakeholders to estimate; affects cost-benefit of Decision 1.)*
5. If `recoil-lua-library` moves to Lux, what's the migration path for downstream consumers (CircuitAI, other Recoil-based games)? *(Recoil maintainers' input needed.)*

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

  Even with some hacky rsync workarounds to manage the WSL boundary cost (see Marek's measurements above), I read the trade as still favoring WSL — but the boundary-cost data shifts the implementation work the WSL path needs to do. The promised second-hardware-profile baseline is now in (Tests 4–5 above): the watch+copy workaround (B.3) lands the dev edit loop at 109 ms median while keeping the engine on Windows-local NTFS, so the runtime path stays close to the all-Windows baseline. That's the workaround-quality number the trade was waiting on.
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

- Pushed back on copying third-party code into the repo in the context of PR #5902 — pending verification of specific positions on package-manager-vs-vendoring before any are cited here.
- Otherwise generally supportive.

### Sprunk

- Chaotic neutral; generally supportive but points out he's free from any ramifications of this decision, so more eating popcorn.

### FlameInk (Nikita)

- **The "Why a cross-platform build script" framing was unnecessary** as a distinct section — it should be folded into the per-decision sections. *(Addressed in this restructure: Decision 3 absorbs it.)*
- **On Decision 1: not yet convinced making every contributor install `lx` is justified vs. having a single maintainer install it and commit the resulting `lib/` contents to the repo.** Position: contributors `git pull` and have what they need without ever touching the package manager; only the version-bumper interacts with `lx`. The two main arguments against vendoring (PR review noise, blame fidelity) FlameInk reads as overstated:
  - *On PR review noise:* a 3000-line dep-bump PR is workable if the PR description tells reviewers which directories are dependency content vs. authored changes — they can ignore the `lib/` portion. The "30 minutes hunting the 20 lines that matter" framing assumes reviewers don't get that signal.
  - *On blame fidelity:* library code rarely gets `git blame`d in practice. The one person who would (the version bumper) can blame the upstream source repo directly.
- **Open question raised, threading into Decision 3:** if Decision 3 mandates WSL anyway, the per-contributor `lx install` cost may be moot — `lx` is already inside the container that's already being installed. Which BAR-Devtools tools actually require WSL/distrobox vs. running natively on Windows? *(See Open Question #3 about msys2 viability — answer affects how much weight the "make everyone install lx" cost actually carries.)*
