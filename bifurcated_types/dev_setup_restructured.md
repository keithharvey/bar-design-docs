# BAR Repo Dev Setup (RFC)

*Authors:* attean. *Contributors:* Marek, FlameInk.
*Last update:* May 27, 2026

This is an RFC, not a decision. It enumerates the problems we have today, the options for addressing each, and the recommendations. Each decision below is independently reviewable — adopting one does not require adopting the others, with one coupling called out explicitly: adopting Lux (Decision 1=B) effectively forces a setup scripting layer (Decision 2) into existence (see Decision 1 → *Coupling with Decision 2*).

See the overall coordinating issue for context: [Beyond-All-Reason/issues/7408](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7408)

## Review table

To be filled in manually by people that reviewed the document and the content looks correct to them. **LGTM does not mean approval** of the proposed solution, merely accuracy of the document that feedback is represented.

| Reviewer | Date | Status | Notes |
|---|---|---|---|
| Marek | May 9, 2026 | Waiting | Waiting for last few comments resolution. |
| Thule | Apr 24, 2026 | Pending | |
| *(put your name here)* | | Pending | |

---

## What's broken today

Four concrete problems contributors hit right now:

1. **Lua type errors accumulate uncaught.** There's no enforced static type checking. Errors don't surface until the relevant code path runs and crashes (or silently misbehaves). A real backlog of latent type errors has accumulated in the codebase as a result.
2. **Vendored Lua deps drift.** `kikito-i18n` was vendored, then accepted patches not present in upstream, and is now an accidental fork no one fully understands. Other vendored content in `common/luaUtilities/` (json, utf8, base64, serpent) has unknown drift status — verifying would require git archeology.
3. **Per-host setup is undocumented and inconsistent.** Windows contributors hit a wiki, Mac/Linux contributors hit a different one. Tool versions, install methods, and editor settings are per-contributor folklore.
4. **No mechanism for cross-branch transforms.** When a codebase-wide transform lands (e.g., the Spring API split), contributors with open branches must merge in the change manually with no automation.

A fifth concern is *prospective*, not current: once we adopt static analysis and formatting tools with CI gates (per the decisions below), contributor machines need to run them at the same versions CI does. Without that mechanism, CI failures will be hard to reproduce locally. Decision 2 addresses this — it's not a present pain, it's a prerequisite for the rest of the proposal not creating new ones.

---

## Decisions to make

This proposal bundles five separable decisions. Each can be adopted, rejected, or deferred independently.

| # | Decision | Lead recommendation | Status | Default if rejected |
|---|---|---|---|---|
| 1 | Lua package manager (Lux) | **B — adopt Lux** (attean) | Contested (Marek/FlameInk lean A/C) | Continue vendoring + submodules |
| 2 | Cross-host toolchain consistency mechanism | **B — shared scripts** (attean) | Framing-disputed (the "hard dep" question) | Continue per-host install |
| 3 | Where contributors run the toolchain on Windows | **B.2 — WSL toolchain, engine on local NTFS** (attean) | Contested — load-bearing (Marek: D, PowerShell) | WSL implicit; msys2/native alternatives |
| 4 | Task runner (`just`) | **A — `just`** (attean) | Near-settled / low-stakes (Marek neutral) | Currently in BAR-Devtools |
| 5 | Where the shared scripts/recipes live | **A — separate repo** (attean) | Partially contested (Marek: optional until proven) | Currently in BAR-Devtools (vs in-tree) |

**Decision dependencies.** Mostly independent, but three couplings are real and flagged where they bite: **1→2** — adopting Lux forces a setup scripting layer into existence (Decision 1 → *Coupling with Decision 2*); **3↔4** — where the toolchain runs and what language the recipes are written in are separable in principle but coupled through contributor workflow (Decision 3 → Recommendation); **1↔3** — if Decision 3 mandates the container, the per-contributor `lx`-install cost in Decision 1 is largely moot (FlameInk's open question).

**Non-goals.** This proposal does *not* change game runtime, the asset pipeline, or gameplay code (only dev tooling and the CI gates in *Game code changes*); does *not* mandate a specific editor (VS Code/Cursor are auto-wired, but any editor works); does *not* rewrite the engine build (`docker-build-v2` is wrapped, not replaced); and does *not* force existing contributors off their current setup overnight (see *Sequencing*).

**Costs being accepted.** Implementation effort is treated as negligible — the costs that matter are ongoing: (a) *contributor friction* for the Windows majority (WSL2 is a real ask in disk and virtualization for the least-experienced cohort; the bet is Microsoft-supported WSL + one shell beats the alternatives — Goal 4); (b) *a bet on immature tooling* (Lux is pre-1.0 and needs a bootstrap shim); (c) *maintenance surface* (a shared Linux substrate to keep working — the counter-bet is it's *less* surface than N per-platform implementations); (d) *organizational* (an opinionated solution that asks the org to commit, mitigated by keeping everything but the CI gates opt-in).

**Sequencing & what's actually mandatory.** *Hard-mandatory:* the CI gate **outcomes** (`bar::fmt`/`check`/`lint`/`test` — they fail your PR) and, once a Lux *runtime* dep lands (`i18n` first), Lux itself (the game won't load without the rock; see Decision 1's coupling). *De-facto mandatory:* the pinned toolchain that makes those gates pass — and therefore `setup::init`, which installs it. The only way to skip `setup::init` is to hand-install matching tool versions per host, which is exactly the "works on my machine" failure Decision 2 exists to kill — so in practice it's required, not optional. Lux migrations proceed one package at a time ("rip 1 at a time"), each reviewable in isolation. *Genuinely optional* (until proven — Marek's >90%-organic bar): only the **cross-repo orchestration** layer (`services::up`, multi-repo clone management) and the productivity helpers (`fmt-mig`, `lua::library`). The honest read: once you accept CI gates + runtime Lux deps, the optional surface shrinks to that last bucket — which is why "BAR-Devtools stays optional" (Marek's Decision 5 position) can't fully hold, and `setup::init` is best framed as *the* supported setup path, not one option among several.

**Success criteria.** #1 — the latent type-error backlog burns down and CI blocks new ones. #2 — a CI failure reproduces locally with the same command. #3 — a new Windows contributor reaches a working env via one command, no wiki-spelunking. #4 — a landed `mig` is replayed onto an open branch in one command instead of hand-merged.

---

## Terms

Quick definitions for reviewers who live in one decision but not all of them.

- **distrobox** — runs a containerized Linux environment tightly integrated with the host (shared PATH, home dir). Hosts the pinned toolchain. Two are used: `bar-dev` (toolchain, all contributors) and, on WSL2 only, `bar-sync` (the file-sync daemon).
- **Lux / `lx`** — a Rust-based Lua package manager (pre-1.0). Declares deps in `lux.toml`, installs into a gitignored `.lux/`.
- **Plan 9 / 9P (`\\wsl$\…`)** — the protocol WSL2 uses to expose Linux files to Windows. Per-file round-trips make it slow for the engine's read pattern, and it does **not** forward Linux inotify events.
- **drvfs (`/mnt/c`)** — how WSL2 mounts Windows drives inside Linux; adds per-stat round-trips.
- **Watchman** — Facebook's filesystem-watching service; used WSL-side for cheap change deltas (`since <clock>`). Not the same as the Python **watchdog** library (a measured-and-rejected probe arm).
- **EmmyLua / stylua / luacheck** — Lua type-checker (LSP + Rust CLI), formatter, and linter; these are the CI gates (`bar::check` / `bar::fmt` / `bar::lint`).
- **codemod / `mig`** — an automated repo-wide source transform (e.g. the Spring API split); `bar::fmt-mig` replays one onto an in-flight branch.
- **mmap** — memory-mapping a file into a process's address space. The engine mmaps Lua sources, which constrains how the sync may rewrite files (Decision 3, constraint #1).
- **ABI** — the binary-level contract (symbol and shared-library versions) a compiled binary expects at load time; why Watchman pins a Fedora release (Decision 3, constraint #4).
- **Recoil / Chobby / SPADS / Teiserver** — the engine, lobby UI, autohost, and lobby server that BAR-Devtools can clone and orchestrate.

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
| Supported by deployment infra | Yes | No — deployment computes version changes by inspecting git-tracked files; non-git-tracked `.lux/` requires infra work to support. Hard blocker until resolved. | Yes |

### Verified concerns

- **MSVC on Windows: not unconditional.** Lux requires MSVC only when (a) a rock declares C source files in its rockspec, or (b) no Lua installation is detectable via pkg-config and Lux must build Lua from source. BAR's deps are all pure-Lua, so (a) never fires. (b) only fires if the Windows host has no Lua 5.1 install — both msys2 (`mingw-w64-x86_64-lua51`) and chocolatey (`lua51`) ship Lua 5.1 directly, and the WSL path doesn't hit this either. The Lux install docs list MSVC + Visual Studio Build Tools as mandatory, which is over-cautious for our usage; worth filing upstream as a docs improvement and/or a "ship a prebuilt Lua binary path" feature request. Verified against [`lux-lib/src/build/builtin.rs`](https://github.com/lumen-oss/lux/blob/main/lux-lib/src/build/builtin.rs) and [`lux-lib/src/operations/build_lua.rs`](https://github.com/lumen-oss/lux/blob/main/lux-lib/src/operations/build_lua.rs).

### Coupling with Decision 2 (not fully independent)

Adopting Lux isn't cleanly separable from Decision 2. Lux is immature enough that bootstrapping it correctly across platforms isn't viable by hand — Marek concurs (his recommendation below: with a package manager, "having scripts in repo that set all up correctly is effectively a *requirement* and manual setup is not viable at all"). And once `i18n` is a Lux *runtime* dep, the game won't load without the rock, so the bootstrap is required to *run* BAR, not just to develop it. So **Decision 1=B forces a setup scripting layer (Decision 2) into existence**; the only open question is whether that layer is *unified* (one substrate, closed under tool addition — a new tool is `apt install X`) or *Cartesian* (per-platform bootstrap — `lx` alone was the hardest tool in Marek's PoC at ~333 lines; see the closure-under-addition discussion under Opinions → attean). This is the first *measured* instance of the unified-vs-Cartesian tradeoff, not a hypothetical.

### Recommendation(s)

- **attean — B (Adopt Lux):** Already partially adopted on master (test deps); the `i18n` runtime migration is the first runtime use, in the PR attached to the tracking issue. The other options leave us exposed to repeating the kikito-style accidental-fork failure.
- **Marek/p2004a — A (Status quo) / unconvinced of B:** At the current number of dependencies we have, adding a package manager might be just not worth it. This is not Node.js/Rust world where it's required, a lot of issues with current way of dealing with dependencies might be a matter of better repo hygiene. I've played a bit with Lux, it's pre v1, and quite immature making some parts of the setup more annoying than they could be. But that's just opinion: if we decide to add a package manager, especially given how messy Lux is, having scripts in repo that set all up correctly is effectively a *requirement* and manual setup is not viable at all.
- **FlameInk (Nikita) — A or C (maintainer-only vendoring):** Not yet convinced making every contributor install `lx` is justified. Position: a single maintainer runs `lx`, commits the resulting `lib/` to the repo; other contributors `git pull` and have what they need without ever touching the package manager. The PR-review-noise cost can be mitigated via PR descriptions naming dependency directories; blame fidelity rarely matters for library code in practice. *Open question raised:* if Decision 3 mandates WSL anyway, the per-contributor `lx install` cost is moot — `lx` is already in the container.
- **Watch Fort — B is acceptable**, sequence packaging one-at-a-time after toolchain lands. "Rip 1 package at a time after this lands" — consistent with the deferred entries (`—`) in the Specific Deps table below.
- **Boneless** — against vendoring third-party code (per PR #5902 review, pending verification). Specific positions on package-manager-vs-vendoring need re-reading from the review thread before being characterized further. *(See Open Question #5.)*
- **Sprunk** — *"i don't think i've weighed in on any actual details, but on earlier discord discussions i have been supportive towards the general effort. keep in mind i am entirely unaffected by the changes though so am happy to take arbitrarily bad tradeoffs just to see what happens"* ([quote](https://discord.com/channels/549281623154229250/1494629570077266030/1496954973555134576)).

### Specific deps

Candidates for Lux migration. The **"In this PR stack?"** column tracks what's delivered by the current proposal — entries marked `—` are deferred to follow-up PRs ("rip 1 package at a time after this lands," per Watch Fort's framing). Deferred ≠ rejected; they're targets for future work, sequenced one-at-a-time so each migration can be reviewed in isolation.

| Dep | Current state | Proposed | In this PR stack? |
|---|---|---|---|
| `kikito/i18n.lua` | Vendored, drifted from upstream | Lux dep (consume existing rock; on `lux-i18n` branch in PR attached to tracking issue) | ✓ |
| `recoil-lua-library` | Git submodule | Lux git dep. Later possibly a lua rock published by Recoil | — |
| `common/luaUtilities/json.lua` | Vendored, drift status unknown | `dkjson` rock (already a test dep). Out of scope. | — |
| `common/luaUtilities/serpent.lua` | Vendored | Upstream `serpent` rock | — |
| `common/luaUtilities/base64.lua`, `utf8.lua` | Vendored | TBD per package | — |


Future deps go through normal review.

---

## Decision 2: Cross-host toolchain consistency

**Prerequisite for the rest of the proposal.** Doesn't address a current pain — addresses the problem that would be *created* by adopting CI gates without a way for contributors to reproduce them locally.

### Options

- **A. Status quo (no shared mechanism).** When tools are adopted, each contributor installs stylua/luacheck/EmmyLua/`lx` at whatever version their extension manager has.
- **B. Shared scripts setting up toolchain.** Some scripting layer (Decision 3) automatically installs and sets up core project dependencies and tools. Most basic-users don't need to care much about details.
- **C. Pinned versions per-host with thorough docs.** Each contributor installs the exact pinned version themselves.

### Tradeoffs

| Axis | A: Per-host | B: Shared scripts | C: Pinned per-host |
|---|---|---|---|
| Reproducibility of CI failures locally | Variable | Reliable | Possible (relies on contributor diligence) |
| Initial install complexity | Variable | Running provided scripting layer | High — N tools at specific versions |
| Per-tool update cost | Per-contributor | Re-running scripting | Per-contributor |
| Works without any new infra | Yes | No | Yes |

### Recommendation(s)

- **attean — B:** Per-host has worked historically because there was nothing to be consistent with; once CI gates exist, per-host produces "works on my machine" failures. **Stance update from the launch-branch implementation (commit `1cd8819`):** the implementation makes distrobox *mandatory* — no host-side toolchain fallback. `require_host` checks hard-error if a docker recipe runs inside the dev container, and `setup::init` always rebuilds the container rather than warning-and-keeping a stale one. This sharpens Marek's framing of Decision 2: the question is no longer "do contributors *also* get a shared mechanism" but "is the shared mechanism the *only* path". On launch, it is. If we want to preserve a per-host escape hatch, that's a deliberate decision to add back, not a status-quo carry-over. The cost calculus here is betting that distrobox and all of these opinionated selections, combined with upstreamability of code, makes the shared tooling worth it from a maintenance and organizational point of view.
- **Marek/p2004a — cross-cutting framing:** The shared scripting layer (BAR-Devtools) is fine to exist; the actual dispute is whether BAR-the-game-repo takes a hard dep on it. That makes Decision 2 a question of "do contributors *need* the container at all", which is bound up with Decision 3's answer. *(No specific A/B/C position stated.)*

---

## Decision 3: Where contributors run the toolchain on Windows

**Addresses problem #3** (Windows setup friction). This is the load-bearing decision for Windows contributors.

**Orientation.** This is the largest decision and the only one backed by original measurement, so it carries its evidence inline. Skim path: **Options A–D** plus the **Recommendation** *are* the decision; the sub-options **B.1/B.2**, the four **implementation-forcing constraints**, and **Tests 1–6** are supporting evidence — go as deep as you need. Two naming schemes appear in the probe data: **roman numerals (i)–(vi)** are the historical probe arms, and **stateless ids** like `wsl-watchman-mntc` follow `<watcher-host>-<event-source>-<destination>`; the table under Test 5 maps between them.

**Status badges used below:** ✅ production / recommended · ❌ ruled out (measured & rejected) · 📐 reference / ceiling (kept for comparison, not a live option) · ⚠️ low replication (single hardware, single 60-s run — see the (0)-baseline caveat in the action item).

### Options

- **A. Windows-native + msys2.** All tools installed natively on Windows, possibly via msys2 for the bash-flavored ones. No virtualization.
- **B. Windows-native game/engine + WSL for toolchain only.** Edit, build, and run the game on Windows native. Cross to WSL only to run lint/format/type-check/test commands. Source-of-truth for game Lua lives in WSL ext4; the engine, running natively on Windows, needs to read those files at gameplay rate. **How the live source crosses the boundary is a sub-decision** with two substrate-level answers — call them B.1 and B.2 — measured in Tests 5–6 below:
  - ❌ **B.1 — Engine reads from `\\wsl$\…` (Plan9/9P).** Any setup where the runtime read path crosses into WSL ext4 via the 9P server: Windows symlink to `\\wsl$\<distro>\…`, direct UNC reads configured in the engine, or any "native WSL driver" mount that's still 9P under the hood. Marek's Test 1 measures the symlink variant (7m30s cold, 4m10s warm, freezes mid-load); Test 5's (ii) measures the direct-UNC variant (~31s warm re-read of a 3000-file tree). Both bottom out in per-file Plan9 round-trips at gameplay rate. ❌ **Ruled out by Test 1.**
  - ✅ **B.2 — Engine reads from Windows-local NTFS (mirror of WSL source).** Engine reads native NTFS; a propagation layer keeps a Windows-local copy in sync with the WSL ext4 source-of-truth. Propagation mechanism is an implementation detail with its own measurements: Test 5's (iii) measures Windows-side watch+copy at ~43.6 s cold full-tree copy, Test 6's (iii) measures it at 109 ms median sustained edit-loop latency. (Test 6's (i) WSL-side rsync also lands engine on local NTFS, but its 7.3 s sustained-loop median rules it out for the sustained-edit case.) Engine-side cold load matches Test 1's all-Windows baseline (~24 s warm). **This is the recommended sub-option.** Within B.2, the propagation question has further sub-detail — see Sub-tradeoffs and Test 6 below for the (iii)/(iv)/(v)/(vi) comparison. *Open sub-axis (added 2026-05-04): which side runs the watcher.* `win-watchdog-unc` (watcher on Windows) **is ruled out as a live propagation candidate** — Plan 9 doesn't deliver inotify across the boundary, so any watcher library on Windows degrades to polling regardless of how it advertises itself. Its 109 ms number stays in the tables as the *ceiling* for the watcher-on-Windows class, not as a live option. `win-watchdog-unc` (watcher on Windows) is therefore ❌ 📐 (ruled out / kept as ceiling). The actual viable candidates are the watcher-on-WSL designs: ✅ `wsl-watchdog-mntc` / `wsl-inotifywait-mntc` (single-process, copy through /mnt/c — production-pick lineage) and 📐 `wsl-detect-win-copy` (split-brain reference; WSL detects, Windows copies). The (iv)-vs-(v) comparison decides whether B.2 ships single-process or split-brain.
- ❌ **C. Everything in WSL.** Edit, build, and run inside WSL. *(Rejected: 16 GiB-RAM machines crash, GPU passthrough is fragile, and it forces a Linux shell on contributors who don't want one.)*
- **D. PowerShell-everywhere.** Write all recipes in PowerShell Core, which runs on Linux too. Avoids WSL entirely. *(Version caveat: PowerShell 5.1 ships by default on Windows 10/11, but Linux/macOS need PowerShell 7+ — recipes must target the 5.1∩7 subset or non-Windows contributors install PS7. Marek's PoC was authored for 5.1 and runs as-is on 7, so this is tractable, not a blocker.)*

### Tradeoffs

| Axis | A: Windows native | B: WSL toolchain only | D: PowerShell |
|---|---|---|---|
| Contributor in their preferred environment | Yes | Yes (game+engine) | Yes |
| Filesystem-perf cost | None | Build artifacts cross once | None |
| Tool ecosystem fit | Some Lua tools (`lx`, `emmylua_check`) lack Windows-first support | Toolchain matches CI's substrate bit-for-bit — same binaries, same versions, no Linux↔Windows patch-version drift in `bar::fmt`/`check`/`lint` output; `lx` (pre-1.0) and `emmylua_check` have measurable Windows-side friction today, `stylua` is cross-platform but still version-pinning-sensitive | PowerShell-on-Linux less common; tools still need to be installed natively |
| Compiler requirement | Only if no system Lua 5.1 (msys2 ships one, so usually avoided) | Avoided (Lua in container) | Same as A |
| Maintenance burden | Recipes work cross-platform out of the box | Recipes are bash, run inside WSL | Recipes are PowerShell, run on both |
| Match between contributor and CI environment | Mismatch (CI is Linux) | Match (CI is Linux) | Mismatch (CI is bash on Linux) |

*Note on the CI-match row (responding to Marek, comment 3).* Windows CI runners do exist, and a PS-on-Windows-runners pipeline could in principle turn D's cell into a match. The row reads as written because (a) CI today is Linux for the rest of the toolchain (`lx`, `emmylua_check`, the integration stack), so flipping D would require flipping CI alongside it, and (b) under the soft-launch position below the goal isn't to force a particular contributor substrate — it's to make a green local `bar::check` reproduce whatever CI runs, bit-for-bit. PS-on-Windows-runners stays available as a future-flip if we ever choose to take it.

#### Sub-tradeoffs within Option B (live-source-crossing mechanism)

| Axis | B.1: Engine on Plan9 | B.2: Engine on Windows-local NTFS |
|---|---|---|
| Propagation mechanisms that land here | ❌ Windows symlink to `\\wsl$\…`, direct UNC reads, "native WSL driver" mounts (all 9P under the hood) | ✅ watcher-on-WSL → /mnt/c (production pick, arms iv/vi); ❌ 📐 watcher-on-Windows (iii) and 📐 split-brain WSL-detect/Win-copy (v) both measured-and-rejected; ❌ WSL-side rsync (i) ruled out for the edit loop |
| Game cold load (per Test 1 substrate equivalence) | **7m30s** (symlink, measured); ~7m30s expected for any Plan9 variant | ~24s (matches all-Windows NTFS baseline) |
| Engine read cost per file at runtime | One or more Plan9 round-trips per read (Test 5 (ii): ~31s warm re-read of 3000-file tree) | Native NTFS read |
| Edit-loop median latency (per Test 6) | 77 ms (Test 6 (ii) — direct UNC variant) | 76–115 ms across (iii)/(iv)/(v)/(vi); 7.3 s for (i) rsync-poll (ruled out) |
| Implementation cost | None (just `mklink /D`) | Small watcher process (WSL-side; watcher-on-Windows ruled out) |
| Dev source-of-truth | WSL ext4 | WSL ext4 (Windows copy is read-only mirror) |
| Failure mode if Plan9 hiccups | Game freeze mid-frame (Test 1's repeated freezes) | Delay before /luarules or /luaui reload effects appear in-game; live gameplay unaffected (engine isn't on Plan9) |

#### Implementation-forcing constraints inside B.2

These four facts are not free parameters of the design — they're *forcing* the shape the production sync daemon (`wsl-watchman-mntc`) ends up with, and any future "obvious simplification" will run into them. Surfacing them up front so reviewers can map "why this shape" without reading the daemon source. Codified in `BAR-Devtools/.claude/skills/wsl2-sync-architecture/SKILL.md`.

1. **mmap inode stability.** The engine `mmap`s Lua sources. If a sync replaces a file via temp-file + rename, the inode flips under the live mmap and the engine reads garbage mid-frame. **Forces** `rsync --inplace` for both cold copies *and* per-event mirrors — the daemon batches Watchman events and re-runs `rsync -a --inplace --files-from=-` (`sync.py:_apply_files`), never a tempfile-and-rename or `shutil.move`/`shutil.copyfile`+rename. This rules out a whole class of "obvious" propagator implementations.
2. **`fs.inotify.max_user_watches` default of 8192 is below BAR's directory count.** Without a bump the watcher silently drops events (failure is in the inotify backend, not at the watchdog layer, so it's invisible from Python). **Forces** `setup::init` to install a sysctl drop-in (`/etc/sysctl.d/99-bar-devtools.conf`) raising the limit to 524288.
3. **drvfs EACCES on locked DLLs.** When `spring.exe` or `Beyond-All-Reason.exe` is running, rsync from Linux through drvfs to engine DLLs hits `EACCES` (rsync exit 23). **Forces** two design choices: (a) `bar::stop` (taskkill /F /T) is mandatory before `engine::build`, and (b) the engine pair is *excluded* from the live watcher and mirrored synchronously from the build recipe instead, because a live watcher would race the build's writes.
4. **Watchman ↔ Fedora ABI lockstep — quarantined to a WSL2-only sidecar.** The cold-copy path uses Watchman's `since <clock>` query to skip the rsync stat-walk on unchanged subtrees (without it, /mnt/c stat round-trips dominate). Meta publishes the Watchman RPM built against a specific Fedora release (currently fc42 — boost 1.83 / libglog.so.0 / libdwarf.so.0, the last of which fc43 dropped). Rather than pin the whole toolchain to that release, the implementation **isolates Watchman in a dedicated WSL2-only container** (`docker/sync.Containerfile`, the `bar-sync` distrobox) while the main toolchain container (`dev.Containerfile`, `bar-dev`) tracks current Fedora (fedora:43). **Forces** `sync.Containerfile`'s `FROM` line and the pinned `WATCHMAN_VERSION` to bump in lockstep — `fedora:latest` there breaks with "nothing provides libboost_context.so.1.83.0" — but only WSL2 contributors build `bar-sync`, so Linux/macOS contributors never pay the constraint.

### Recommendation(s)

- **attean — B (Windows-native game/engine + WSL for toolchain only), specifically B.2 (engine on Windows-local NTFS):** Game/engine stay Windows-native where the platform support and runtime characteristics are best; toolchain (lint, format, type-check, test, codemod, package install) runs in WSL so a green local `bar::check` reproduces CI's verdict for the same structural reasons (same container, same toolchain versions), instead of relying on best-effort cross-OS version parity. The live-source-crossing problem inside Option B is solved by sub-option B.2 — a small watcher mirrors `\\wsl$\…` to local NTFS so the engine reads from native NTFS at gameplay rate, while the dev edit loop tolerates the boundary at ~76–115 ms median (Tests 5–6 below give the full numbers; the production daemon at `BAR-Devtools/scripts/sync.py` is the implementation). B.1 (any "engine on Plan9" mechanism — symlink, direct UNC reads, native-driver mounts) is ruled out by Test 1's game-load measurement: leaving the engine reading source files through Plan9 produces 7m30s cold loads. Option A remains a real fallback if WSL friction proves too high overall.

  - **On Option D specifically.** Mechanically viable, per Marek's [PR #7533](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7533). Decisions 3 and 4 are separable in principle but coupled in practice via contributor workflow. Lint, format, type-check, integration tests, and codemod are operations a BAR contributor uses every day — they're *BAR contributor concerns*. They happen to be hosted in BAR-Devtools because that's where shared tooling lives, but where the implementation files sit is an organizational question; what substrate they require is a runtime question, and that's what drives the Decision 3 analysis.

    The load-bearing example today is **codemod**, which uses cargo + Rust because that was the best substrate for the tooling it needed (full-moon parser). But codemod is just the first instance of a pattern I expect to recur: every future dev tool will face the same "what substrate fits this best?" question, and the answers will be heterogeneous — Rust for one, Python for another, Go for a third. *(For the GUI / Windows-native edge case Marek raised in comment 11 — a hypothetical future tool that runs poorly under WSL — `setup::deps` is the explicit escape hatch: a per-platform install step that `winget`-installs on Windows and `apt`-installs in the dev container on Linux, the same pattern the current `bar_debug_launcher` venv setup uses.)* A unified bash + Linux substrate makes the BAR ↔ BAR-Devtools edge blurry in the helpful direction for all of them: new tools land wherever they fit best, contributors invoke them through the same shell regardless of what's underneath, and the line between "this lives in BAR" and "this lives in BAR-Devtools" stops being a contributor-facing distinction. Less maintenance per new tool (a reliable dev container acting as "host", no twin-implementation tax for a PowerShell half-measure), less contributor friction (one shell to learn, one set of conventions), tighter feedback when adding tooling. Integration tests are the firm-substrate case — they need Docker, BAR-Devtools provides that today, BAR doesn't host it or handle setting up that tooling (bit of a strawman because we **could** do that independent of BAR-Devtools, but I'm not certain anyone wants to maintain that) — but the substrate need is BAR's regardless of repo location.

    Going PowerShell-native on Decision 3 while keeping cross-repo tooling Linux-substrate-shaped means contributors live in two shells (PowerShell for edit/build/run, Linux for everything else), and adding new tooling has to pick a side or be implemented twice. The consistent alternative is going PowerShell-native on the cross-repo tooling too — rewriting the integration pipeline, the CI, Lux, and codemod orchestration in PowerShell. That's consistent by construction (no parallel implementations), but the downside is *what* it's consistent on; that lands in the contributor-pool note below.

    One additional contributor-pool note: bash literacy is broader than PowerShell literacy in the OSS contributor pool. Most active contributors have bash on hand (Linux native, Git Bash or WSL2 on Windows); PowerShell is Windows-default but typically not installed on Linux/macOS, even though PowerShell Core is technically cross-platform. Picking PowerShell for shared tooling raises the entry bar for contributors generally; WSL2 raises it for Windows contributors only, in a path Microsoft ships and supports natively.

    Admittedly, this recommendation is predicting (and conflating) an outcome for Decision 4 (even though Decision 4 is narrow, focusing on `just`) — that cross-repo tooling stays Linux-substrate-shaped. Flipping that — committing to PowerShell-native cross-repo tooling — would change the Decision 3 analysis, but it's that flip, not Decision 3 in isolation, that's the load-bearing question. Most of this conflation comes from reaching for a comprehensive, unified tooling story — one dispatch interface, heterogeneous recipes underneath. I think that makes sense for BAR's needs today — but when we include the entire project's scripting and maintenance needs it becomes a landslide. Removing seams for contributors has real benefits, and the unified-tooling pull is what keeps merging Decisions 3 and 4 in my head, even though they're separable in principle.

- **Marek/p2004a — D (PowerShell / dual native).** I don't like the idea of making the development not-accessible or less performant for the majority of our contributors, especially the less technical ones. I don't like WSL because it's not only system complexity and overhead (additional tens of GiB of disc, virtualization, containers and so on just to run a few tools) but also with high probability of constant performance impact (e.g. formatting potentially taking tens of seconds vs <1s).

  Even if more complex in implementation, "PowerShell"-only or "PowerShell for Windows + bash for Linux" is viable and provides the smoothest experience for Windows users: NONE additional setup — you fork the repo, you double-click `install.cmd` in Windows Explorer and you are 100% done.

  To not speak entirely out of my ass I've built a Proof-of-Concept that works like that for the package manager: [PR #7533](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7533). (Yeah, it's not pretty, but that's not what I'm optimizing for.)

  To be honest, the current description of option A is a little bit not-defined-enough for me to say whether it's viable or not.
- **FlameInk (Nikita) — open question:** Which BAR-Devtools tools actually require WSL/distrobox vs. running natively on Windows? The answer determines how much of the per-contributor cost calculus in Decision 1 still holds. *(Threads into Open Question below about msys2 viability.)*

### Open questions

- What's the actual filesystem-perf cost of WSL ↔ Windows for BAR's build/test loop today? *(Marek measured a baseline on his hardware — see [Cost of crossing the WSL boundary](#cost-of-crossing-the-wsl-boundary). attean to add an option-B baseline + workaround attempts on his hardware as a jumping-off point for performance improvements.)*
- Is msys2 viable for `lx`, `emmylua_check`, and `clangd` natively on Windows without WSL? *(attean to investigate.)*

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

**Test 4 — Sync game files from WSL to Windows drive via rsync.** Marek's hardware. Optimized for the Windows target — excluding `.git` metadata, dropping permission/timestamp comparison, syncing on modification timestamp + size:

```
rsync -rltv --omit-dir-times --whole-file --inplace \
    --exclude='/.git' --filter=':- .gitignore' --delete-after \
    /home/p2004a/Workspace/BAR/Beyond-All-Reason/ \
    /mnt/c/Users/marek/Workspace/Beyond-All-Reason-copied/
```

| Run | Runtime |
|---|---|
| Initial file copy | ~9m10s |
| Repeated runs, no files modified (sync-status check) | ~2m0s |

**Note on scale (Test 4 vs. Tests 5–6).** Test 4 runs against the *real* BAR tree; Tests 5–6 run against a synthetic ~3,000-`.lua` tree mimicking BYAR-Chobby. The two aren't linearly comparable by file count. `fd | wc -l` on real BAR returns ~18,603 entries — but `fd` counts directories as well as files and honors `.gitignore`, whereas the synthetic tree is exactly 3,000 uniform 200 KB `.lua` files in 50 dirs (`probe_wsl_sync.py:78`, `:240`). Extrapolating the synthetic warm-rsync figure linearly (8.1 s × 18603 / 3000 ≈ 50 s) lands ~2.4× below Marek's measured ~2 m repeated-run, with the residual split between file-type/size heterogeneity (real BAR's large binary assets stat-walk differently than uniform Lua) and hardware. Treat the synthetic numbers as *floor* indicators for the architecture comparison, not wall-clock predictions for real BAR — Test 4 remains the reference for real-repo rsync cost.

**Tests 5-6 were run by Attean** on a PC (AMD Ryzen 5600X, 16GiB, Nvidia 7060Ti) to measure the best architecture to sync to NTFS for within B.2

**Test 5 — Architecture probe: cold tree copy and warm re-read across the live-source-crossing options.** Setup: `BAR-Devtools/scripts/probe_wsl_sync.py` generates a synthetic ~3000-file Lua tree (~600 MB, mimicking BYAR-Chobby's shape) on WSL ext4, then measures cold full-tree copy/read time across the candidate sync architectures. 3 iterations per architecture for `win-unc-read`/`win-watchdog-unc`; `wsl-rsync-mntc` is a single hand run; `wsl-watchdog-mntc`, `wsl-inotifywait-mntc`, and `wsl-detect-win-copy` are single-iteration runs from 2026-05-04, n=300 events each (the auto-orchestrator only cross-iterates arms that need `\\wsl$\…` Windows-side coordination).

Each row is named by a stateless architecture id `<watcher-host>-<event-source>-<destination>`; the parenthetical roman numeral is the historical probe-arm number, kept for cross-reference.

| Architecture | Roman | Sub-option | (a) Cold full-tree | (b) Warm re-read |
|---|---|---|---|---|
| ❌ `wsl-rsync-mntc` — WSL ext4 → /mnt/c via rsync | (i) | B.2, WSL-side rsync | 26.22s | 8.108s (rsync incremental, no changed files) |
| ❌ `win-unc-read` — direct `\\wsl$\…` reads from Windows | (ii) | B.1 (Plan9 substrate) | ~31.6s (read-only, 3-iter mean) | ~31.2s (3-iter mean) |
| ❌ 📐 `win-watchdog-unc` — watcher on Windows, copy from `\\wsl$\…` *(ruled out as a live propagation candidate; retained as ceiling data point — see caveat)* | (iii) | B.2, watcher-on-Windows | ~43.6s (3-iter mean) | n/a (auto-orchestrator skips) |
| ✅ `wsl-watchdog-mntc` — watcher on WSL (python-watchdog), copy → /mnt/c | (iv) | B.2, watcher-on-WSL | 28.5s | n/a (single-process; no warm re-read step) |
| 📐 `wsl-detect-win-copy` — WSL inotifywait → UNC-visible event log → Windows python tails + copies UNC→local NTFS | (v) | B.2, split-brain reference | 28.4s | n/a (split-brain; no warm re-read step) |
| ✅ `wsl-inotifywait-mntc` — watcher on WSL (inotifywait), copy → /mnt/c | (vi) | B.2, watcher-on-WSL | 28.4s | n/a (single-process; no warm re-read step) |

The decision-relevant figure is (ii)'s warm re-read: it stays at ~31s because *re-reading* through Plan9 still requires a per-file round-trip. Any architecture where the engine re-reads source files over `\\wsl$\…` per gameplay-frame multiplies that 31s read by however many frames touch fresh files. This isolates the cause of Test 1's 7m30s game load to per-file Plan9 read latency, not to one-time sync overhead.

**Test 6 — Architecture probe: sustained dev edit-loop latency.** Same probe script. WSL-side touches 5 random files per second for 60s; the measuring side records end-to-end latency from "file written WSL-side" to "fresh content readable on the Windows side." For (ii) and (iii), 3 iterations pooled, top 1% trimmed (the trim drops single-event Plan9/Defender stalls so they don't swamp the central tendency, but raw max is preserved for visibility). For (i), a single run — there's no Windows-side handshake to coordinate, so the auto orchestrator doesn't apply.

| Architecture | Roman | Median (ms) | p95 (ms) | Max trimmed (ms) | Max raw (ms) | n / propagator |
|---|---|---|---|---|---|---|
| ❌ `wsl-rsync-mntc` (poll-rsync @ 200ms) | (i) | 7314 | 11090 | — | 11870 | 298 (single hand run) |
| ❌ `win-unc-read` (B.1) | (ii) | **77.4** | 127.4 | 141.3 | 176.1 | 891 / 900 (3 auto iters) |
| ❌ 📐 `win-watchdog-unc` (B.2, watcher-on-Windows; log-driven poll baseline — *ruled out as candidate, kept as ceiling*) | (iii) | **109.5** | 179.3 | 197.6 | 215.1 | 891 / 900 (3 auto iters) |
| ✅ ⚠️ `wsl-watchdog-mntc` (B.2, watcher-on-WSL; python-watchdog) | (iv) | **97.6** | 160.0 | 175.0 | 181.0 | 297 / 300 |
| ✅ ⚠️ `wsl-inotifywait-mntc` (B.2, watcher-on-WSL; inotifywait \| python copy) | (vi) | **76.0** | 117.9 | 134.5 | 143.1 | 297 / 300 |
| 📐 ⚠️ `wsl-detect-win-copy` (B.2, split-brain reference; inotifywait → UNC log → Win copier) | (v) | **114.9** | 172.5 | 191.1 | 205.2 | 297 / 300 |

Reading:

- **(ii) and the watch+copy arms (iii)/(iv)/(v)/(vi) all clear a <500 ms dev-loop threshold** by ~5×. (i)'s rsync-poll architecture does not — at 5 touches/sec the 200 ms poll batches events and the per-tree rescan dominates. So *any* WSL-side-rsync design is dead for sustained edit loops, regardless of which Option-B substrate we pick.
- **B.1 (UNC-read) wins watch+copy on raw probe latency by ~30 ms.** (ii) is one Plan9 round-trip per file; the watch+copy arms are Plan9 read + local NTFS write per event (or inotify + /mnt/c write for the WSL-side variants). The probe shows the cost of the extra write step.
- **The dev-loop ranking inverts under runtime substrate.** Pairing Test 6 with Test 1: B.1 leaves the engine on Plan9 at gameplay rate (Test 1: 7m30s cold load); B.2 puts the engine on Windows-local NTFS (Test 1: ~24s cold load). The extra ~30 ms median dev-loop latency buys a ~3.5-minute reduction in warm restart time per session, which is why B.2 (watch+copy) is the recommended sub-option even though B.1 is faster on the dev loop in isolation.
- **Caveat on `win-watchdog-unc`'s detection layer (added 2026-05-04).** The (iii) auto-orchestrator drives the Windows-side copier from a WSL-written touch log — explicit log-driven polling, *not* native filesystem events. The intended production design assumed a watcher-on-Windows variant could do better via `watchdog.observers.Observer`, but Plan 9 does not deliver inotify events to Windows, so that path silently degrades to `PollingObserver` semantics regardless. `win-watchdog-unc`'s 109 ms median therefore reflects the real ceiling for any watcher-on-Windows design — it cannot be improved by "adding fsevents," because the OS layer doesn't have any to give. The watcher-on-WSL arms (iv) and (vi) confirm this: with native inotify on ext4 and writes through /mnt/c, `wsl-watchdog-mntc` lands at 97.6 ms and `wsl-inotifywait-mntc` lands at 76.0 ms — *faster* than (iii) on every percentile despite the extra /mnt/c hop, because they're event-driven instead of poll-driven.
- 📐 **`wsl-detect-win-copy` (split-brain) as reference, not winner.** Detection on WSL (inotifywait), copy on Windows (`shutil.copyfile` from `\\wsl$\…` to local NTFS), with a UNC-visible event-log file as the IPC channel. Median 114.9 ms — *slower* than both single-process WSL-side arms. UNC reads + local-NTFS writes cost more than direct /mnt/c writes, and the IPC complexity (event log + Windows-side python tail) buys nothing. The comparison hardens the recommendation around the single-process `wsl-watchdog-mntc` / `wsl-inotifywait-mntc` family; the split-brain design is documented as a measured-and-rejected alternative, not deferred.
- ✅ **Production pick: `wsl-watchman-mntc` (refinement of probe arm iv).** Among the *probed* arms, (iv) `wsl-watchdog-mntc` (python-`watchdog`) won the watcher-on-WSL, single-process comparison (~76 vs ~98 ms vs (vi) `wsl-inotifywait-mntc`, both well under the <500 ms target; the `inotifywait` pipeline saves ~22 ms but forces a bash+python coprocess split). The **shipped daemon refines that rather than copying it**: since Watchman was already required for the cold-restart `since <clock>` delta queries, `scripts/sync.py` **unifies on Watchman for the live event source too** (subscriptions) instead of also running the python-`watchdog` library, and tracks all file state through it — a single-process Python daemon that still integrates naturally with `pair_state` (atomic-rename JSON). So the watcher-on-WSL/single-process *shape* was measured; the Watchman-vs-watchdog event source was an implementation refinement for dependency unification, not a measured one. (Don't conflate Facebook **Watchman**, which we ship, with the python **watchdog** library, the probe arm — the historical arm name keeps `watchdog`.) ⚠️ **Confidence:** arms iv/v/vi are a single 60-s run on one machine (n≈300 propagation events each), vs 3 pooled runs for ii/iii; the (0) NTFS baseline is still open (see the action item). The within-run ranking is solid; cross-run and cross-hardware replication is the missing piece.
- **Methodology footnote.** The probe is a synthetic workload (sequenced touches, 64-byte marker payloads). Real BAR Lua reload involves more files at lower frequency, but is bursty in a way the probe approximates poorly. Read the medians as *floor* numbers the production sync daemon won't beat, not as wall-clock predictions of game-load time. Test 1 is the right reference for game-load wall-clock; Test 6 is the right reference for dev edit-loop responsiveness.

**Key finding (load-bearing for the whole sub-decision):** *Plan 9 does not forward Linux-side inotify events across the WSL/Windows boundary.* A "native" file-system watcher (e.g. `watchdog.observers.Observer`) running on Windows over `\\wsl$\…` silently degrades to `PollingObserver` semantics regardless of how it advertises itself. This is what makes `win-watchdog-unc` (iii) a measurement ceiling rather than a viable production design, and it's why arm (iv) — *watcher on the WSL side*, native inotify on ext4, writes through `/mnt/c` — is the production pick. Every "could we just run the watcher on Windows?" question collapses to this fact; treat it as the headline of the sub-decision rather than as a Test 6 footnote.

**Implications for Decision 3:**

- **Test 1** is decisive for the *runtime* path: any path that has the engine read source files across the WSL↔Windows boundary at game-load time is a non-starter. Inside Option B this rules out B.1 (any "engine on Plan9" mechanism — symlink, direct UNC reads, native-driver mounts); B.2 (engine on Windows-local NTFS via watch+copy) is the only sub-option that puts the engine on Windows-local NTFS at gameplay rate.
- **Test 2** is not directly relevant to Option B as proposed — Option B runs the engine natively on Windows (cross-compiled via `docker-build-v2`), not inside WSL. The 1–2 fps figure applies to a "run the AppImage in WSL" path nobody is advocating; included here for completeness.
- **Test 3** is the cost driver for *developer* loop tools: anything inside WSL that walks the BAR tree (`bar::check-errors`, `bar::lint`, `bar::test`, the codemod) reads source files. If those files live on NTFS and the tool runs on ext4, every recipe is ~17× slower. Implication: BAR source repo should live inside WSL (`~/Beyond-All-Reason`, ext4), with sync-out to the Windows install dir for the runtime path.
- **Test 4** establishes the WSL→Windows rsync sync-cost ceiling on Marek's hardware: 9m10s initial copy, ~2m for repeated no-change runs. Together with Test 6's (i) sustained-loop result this rules out WSL-side rsync as a live propagation mechanism for B.2.
- **Test 5** isolates the cost driver behind Test 1: per-file Plan9 read latency, not one-time sync overhead. (ii)'s warm re-read still costs ~31 s for the 3000-file tree, which is what makes B.1 a non-starter for the runtime path even though its dev edit loop tests fast.
- **Test 6** establishes that the dev edit loop is fine under B.1 *or* B.2 (both well under a 500 ms target); the choice between them is determined by Test 1 / Test 5 on the runtime side, not by edit-loop latency. (i) is also ruled out for the dev edit loop here, but that's already covered by Test 4.

**Action item carried by attean:** Tests 5 and 6 above are the instrumented-sync results on the second hardware profile this action item asked for; the comparison against Marek's measurements is now in. The numbers above are collated medians/percentiles from the probe runs; raw JSONs for arms (i)/(ii)/(iii) are checked in at `bar-design-docs/bar_launch/probes/`, and a secondary confirmation run for (iv)/(v)/(vi) is on the to-do list to commit alongside the other arms. The production sync daemon (`BAR-Devtools/scripts/sync.py`) is the watcher-on-WSL, single-process design that probe arm (iv) `wsl-watchdog-mntc` validated, refined to use Watchman (not the python-`watchdog` library) as the event source — see the production-pick note above. Remaining open follow-up:
  - A (0) NTFS-local baseline (tree generated directly on `C:\`, no WSL involvement) — would establish the floor for B.2's cold-copy and edit-loop numbers. Not load-bearing for the architecture pick — every B.2 watch+copy arm is already <200 ms p95 and the production daemon also leans on Watchman for incremental cold copies, which the synthetic probe doesn't model.

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

> **Note on "supports project-level config":** This is listed as a *neutral* dimension, but attean's recommendation treats it as a downside — see Opinions. The argument is that config support tempts the runner to accumulate state that should live in source repos or docker, eroding the "pure runner" boundary.

### Recommendation(s)

- **attean — A (`just`):** Adds welcome conveniences (recipe dependencies, recipe arguments, namespacing like `bar::fmt`) without bringing project-level config. Cost: one binary install. Already used in BAR-Devtools.

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

- **attean — A (Separate repo / BAR-Devtools):** The setup script and codemod tooling are not BAR-specific; sibling Lua-on-Recoil projects can use them. Splitting this layer also keeps BAR's repo focused on game content, and we seem to be splitting everything up, so...
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
| `just bar::test` | Unit + integration tests | Before PR (also runs in CI) |
| `just bar::check` | Type-check (EmmyLua) | Before PR (also runs in CI) |
| `just bar::fmt` | Format (stylua) | Before PR (also runs in CI) |
| `just bar::lint` | Lint (luacheck) | Before PR (also runs in CI) |
| `just bar::fmt-mig` *(planned, not yet on launch branch)* | Replay codemod transforms onto your branch | Optional; the announced replay path after a `mig` PR lands (manual conflict-resolution remains the fallback). Addresses problem #4 |
| `just bar::launch` | Launch the game (cold-copies WSL→Windows on Win, `mintty`/native on Linux) | Every dev session; on Windows this is the trigger for the WSL2 sync described in Decision 3 |
| `just bar::stop` | Kill running spring/launcher/python processes | Required before `engine::build` on Windows (drvfs EACCES on locked DLLs) |
| `just lua::library` | Recoil → BAR types pipeline for live API iteration | Engine-side dev |
| `just engine::build <platform>` | Build RecoilEngine via docker-build-v2; on WSL2 mirrors `install/` to the Windows-NTFS data dir | Engine-side dev |

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

`bar::fmt-mig` *(planned, not yet on launch branch — see open question below)* — replay codemod transforms onto your branch when a `mig` PR lands. **Opt-in, not required:** when a transform PR lands it is *announced* as the recommended way to carry an in-flight branch across the change, but skipping it just means you do the same conflict resolution by hand, exactly as today. Nothing in BAR's CI or build depends on it. The reason it doesn't need to be mandated is the convenience delta — one command versus hand-resolving every rewritten call site on your branch — which makes adoption self-driving for anyone who actually has an open branch when a transform lands. Addresses problem #4. The `bar-lua-codemod` runner CLI is the substrate; the `bar::fmt-mig` recipe that wires it into a contributor-facing replay command is the missing piece.
`lua::library` — recoil → BAR types pipeline for live API iteration during engine work. Skip it if you're not touching the engine.
`setup::init` — one-command onboarding (the Decision 5 vehicle). Skip it and you set up tools by hand. Addresses problem #3.

Skipping any of these doesn't fail anything; you just do the underlying work manually instead.

---

## What BAR-Devtools actually does

BAR-Devtools is a shared scripting layer for cross-repo dev tasks. It exists to serve the goals below; the implementation is what `just setup::init` (and the other recipes already covered) concretely does.

**Wider scope on the launch branch (worth surfacing for Decision 5).** Beyond the dev-toolchain story this document focuses on, BAR-Devtools also hosts: (a) Teiserver + PostgreSQL + SPADS local-services orchestration via `just services::up`, (b) `repos.conf`-driven multi-repo clone management with feature-tag classification, (c) 1Password SSH agent bootstrap (`just ssh::*`), and (d) the WSL2 sync daemon discussed in Decision 3. This sharpens Marek's "hard dep on it" framing: the dep is broader than just "shared scripting", which is part of why the cross-repo-vs-main-repo scope distinction matters for the decision.

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

The **`bar-dev`** distrobox container holds the pinned versions of these binaries (on Linux, distrobox runs natively; on Windows, it runs inside WSL). On WSL2 a *second* container, **`bar-sync`**, is also built — it hosts only the filesystem-mirror daemon (Watchman + rsync) and is pinned to its own Fedora release for ABI reasons (see Decision 3, constraint #4). All contributors get `bar-dev`; `bar-sync` exists only on Windows/WSL2:

- `emmylua_ls` — Lua language server
- `emmylua_check` — Rust EmmyLua analyzer (also what CI runs via `bar::check`)
- `clangd` — C/C++ for engine work *(only relevant for engine contributors)*
- `stylua` — Lua formatter
- `lx` — Lux

On Linux, `distrobox-export` makes these visible on the host's PATH (`~/.local/bin`), so editors running on the host find them automatically.

On Windows, the binaries live inside WSL. The editor reaches them by running inside WSL itself — the standard pattern is the [VS Code Remote-WSL extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl), which lets you "Open Folder in WSL" so the LSP and tools execute server-side in WSL while the UI stays on Windows. Cursor has the same pattern. *(This is what Marek's review comment was pointing at — yes, the Windows-side editor still needs to know the WSL binaries exist; the Remote-WSL extension is how.)*

#### 2. Editor extensions get installed

VS Code / Cursor extensions (Phase 4: all interactive y/N prompts are batched into a Step 0 Configuration block at the *start* of `setup::init`; long-running steps then roll non-interactively):

`tangzx.emmylua` — EmmyLua LSP
`JohnnyMorganz.stylua` — formatter
`llvm-vs-code-extensions.vscode-clangd` — clangd
`bmalehorn.test-switcher` — Ctrl+Shift+Y test ↔ source jump

Removed if present (conflicts):

- `sumneko.lua` (LuaLS) — too slow to parse BAR's bindings effectively; takes minutes where EmmyLua takes seconds. Mutually exclusive with EmmyLua so we remove it to avoid duplicate diagnostics.

#### 3. Workspace settings get written into BAR

`.vscode/settings.json` is written per-checkout (gitignored) into both the BAR and RecoilEngine repos, from `templates/bar-vscode-settings.json` / `templates/recoil-vscode-settings.json` via `_write_vscode_settings`. The shipped BAR template is deliberately minimal:

- `[lua]` formatter = `JohnnyMorganz.stylua`.
- `files.exclude` entries for `.devtools` and `.lux` (pinned to `false`, i.e. kept visible).

Earlier drafts described `search.exclude` covering `common/luaUtilities/**` and an auto-written `test-switcher.rules` block; **neither is in the shipped template.** `bmalehorn.test-switcher` is installed as an extension, but its rules are left to the contributor's User Settings (per the README), not written by `setup::editor`. The engine template bakes in `$HOME` for `clangd.path`.

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
2. What is the actual filesystem-perf cost of WSL ↔ Windows for BAR's build/test loop today? *(Marek measured a baseline on his hardware — see Tests 1–4. attean added Tests 5–6 on a second hardware profile, which give an instrumented comparison of B.1 vs B.2. Still open: a (0) NTFS-local control to anchor the floor, plus a third hardware profile if anyone has time.)*
3. Is msys2 viable as a Windows-native alternative to WSL for `lx`, `emmylua_check`, and `clangd`?
4. How many third-party Lua deps does BAR realistically grow to over the next 12 months? *(Stakeholders to estimate; affects cost-benefit of Decision 1.)*
5. If `recoil-lua-library` moves to Lux, what's the migration path for downstream consumers (CircuitAI, other Recoil-based games)? *(Recoil maintainers' input needed.)*

---

## Opinions (tagged by holder)

The body sections above are intended as agreement substrate. This is where positions live.

### attean

Per-decision recommendations are inline under each Decision's Recommendation(s) section. These are cross-cutting positions that inform multiple decisions or sit outside any one of them.

- **Vendoring at scale produces drift in this org specifically.** Kikito-i18n is the existence proof; assume the next vendored dep follows the same path absent a mechanism that prevents it.
- **Single-submodule consumption is fine today; the concern is the future-state pattern, not the technical separation.** What I push back on is the *consumption mechanism*. The Recoil → CircuitAI relationship makes the failure mode concrete: Recoil pulls submodules from a CircuitAI fork on two specific branches, which obligates whoever owns that fork to maintain those exact branches indefinitely or break Recoil. Marek is correct that the AI interface was *designed* to be implementable separately from engine source — that separation is intentional and good. The structural critique is orthogonal: cross-org submodules pinned to specific branch SHAs invert who owns the maintenance burden — the upstream repo becomes the load-bearing party for our consumption shape, not theirs. Add that submodule SHAs carry no version semantics (your master changes SHA regularly with no release-interpretation; `git submodule update` produces meaningless rebase churn), and the pattern accumulates entropy with each new dep. Want to break it before recoil-lua-library is followed by similar deps and we end up where Recoil is.
- **The shared toolchain is load-bearing for problem #1** (the EmmyLua type-check is a CI gate — enforced, not optional). For **problem #4** the *requirement* lives in CI like any other outcome — a branch that skipped a transform fails `bar::check` — so the toolchain provides the ergonomic replay path (`bar::fmt-mig`), not the enforcement. The codemod capability is independently reviewable.
- **`common/luaUtilities` should become packages** because the game owns its own utility domain — it shouldn't wait for the engine to provide json/utf8/string helpers it doesn't care about.

#### Response to Marek's PowerShell PoC ([PR #7533](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7533))

The PR itself is good work: SHA pinning, no-admin repo-local install, the `_run.cmd`/`.sh` symmetry — all clean. Lux is a relatively friendly tool to package this way and it's been shown doable. Below is what I'm weighing as I think about whether to extend this pattern to the rest of the toolchain, with corrections from Marek's inline review folded in.

- **Reproducibility.** The dev environment lives in an immutable distrobox container that `setup::init` builds from a Containerfile manifest. The load-bearing value is **system-level immutability** — every contributor's environment is rebuilt from the manifest, so drift never accumulates in the first place; new contributors get a known-good environment regardless of whether they understand how it works. That's distinct from *recoverability* (`distrobox rm` + rebuild in two minutes, host untouched), which does require knowing what distrobox is — Marek's "they can recover, if they have a clue" applies there, not to the immutability property. The PoC's native path is cleanly removable today (it installs into `.tools/`), but going native still means install steps that touch the host, and future native tools may not all be as clean.
- **Scope — narrowed to the disagreement that actually exists.** Marek's clarification is important here: he is *not* arguing that BAR-Devtools cross-repo orchestration should be Windows-native, and he agrees that the PoC's pattern is not the right shape for cross-repo. The disagreement is narrower — *day-to-day main-repo dev workflow* (lint, format, type-check, test, codemod, package install). My earlier listing ("the rest of the toolchain") was too loose and didn't separate cross-repo concerns from main-repo concerns; Marek was right to flag that. Locking down which tools are actually in-scope for the slope-cost argument:

  | Tool | Cross-repo orchestration? | Main-repo day-to-day? |
  |---|---|---|
  | `stylua` | No | Yes (`bar::fmt`, CI gate) |
  | `emmylua_check` | No | Yes (`bar::check`, CI gate) |
  | `bar-lua-codemod` runner CLI | No | Yes (`bar::fmt-mig`, after migs land) |
  | Language-server CLIs | No | Yes (CI, pre-commit hooks, scripting) |
  | `mingw-w64` cross-compile | Yes | No (engine devs only) |
  | `lx` | No | Yes (test deps today, runtime deps incoming) |

  The five non-`mingw-w64` rows are the main-repo day-to-day surface; the slope-cost argument applies to that narrowed set specifically, not to the full toolchain. The PoC's ~333 lines went toward `lx` — the **hardest** of the candidates, not a soft baseline (it required installer manipulation and pre-provisioned Lua prebuilds + headers from awkward hosting). So the slope genuinely cuts both ways: the painful cases may be front-loaded, or they may compound. I'm explicitly *not* asking the PoC to grow further to find out — the intent is to first see how good the WSL path gets with workarounds before extending the bifurcation experiment. Granted, several language servers (e.g. EmmyLua) ship as IDE plugins now and don't need a separate CLI install on contributor machines; but the CLI matters for CI, scripting, and pre-commit hooks regardless. Whether the slope stays sublinear is the empirical question to answer, not a settled one.
- **Container comparison.** Adding a tool to the container today is roughly `apt install -y X` in `dev.Containerfile` — every tool gets added the same way, no per-platform bootstrap code. That's a property of having a real package manager inside an image we throw away; Windows doesn't quite have an equivalent today (`winget`/`scoop` are close-but-not-quite, especially on the throwaway property).
- **Honest read.** The PoC is a great existence proof that *one* tool can be done native, and Marek's point that I shouldn't have used "not possible" stands — I should have said "not possible *maintainably* at the cross-repo orchestration scope." For the *narrowed* scope (main-repo day-to-day workflow), the answer is genuinely less clear, and Marek's point about optimizing for the Windows-majority contributor is real.

  WSL2 + container has two properties worth naming precisely:

  - **Closure under tool addition.** The PoC achieves *reproducibility* of an already-pinned set of tools via SHA + lockfile — that's real and it's what the PowerShell PoC already gives us today. What the container path adds is that the property carries automatically for any new tool: `apt install -y X` extends the set without writing a new bootstrap module per tool. The PoC pattern requires roughly N × per-tool-bootstrap as the toolchain grows; the container is closed under addition.
  - **Single-implementation contribution surface.** Not a licensing point (both paths are open source by construction) — a practical contribution-friction one: a single implementation means a fix lands once, in one place, in the language the existing contributor pool is already comfortable with (bash). A bifurcated scripting layer (bash *and* PowerShell as parallel trees) means writing fixes twice, testing twice, and triaging which side a bug lives in. The "half of the codebase" framing assumed that bifurcation case — bash on Linux + PowerShell on Windows. If the proposal were instead PowerShell-only as the *single* implementation across both platforms, then "half" is wrong; it'd be the whole. But that's a much larger commitment (rewriting the existing bash recipes in PowerShell) that should be costed separately.

  Even with some hacky rsync workarounds to manage the WSL boundary cost (see Marek's measurements above), I read the trade as still favoring WSL — but the boundary-cost data shifts the implementation work the WSL path needs to do. The promised second-hardware-profile baseline is now in (Tests 5–6 above): the watch+copy workaround (B.2) lands the dev edit loop at 109 ms median while keeping the engine on Windows-local NTFS, so the runtime path stays close to the all-Windows baseline. That's the workaround-quality number the trade was waiting on.
- **Where this leaves the disagreement.** Decoupled from "should cross-repo orchestration be native" (we agree it shouldn't) and from "is mandatory adoption acceptable" (we agree organic adoption is preferable; the question is whether BAR-the-game-repo's CI gates create de-facto mandatory adoption). The remaining live question is: *for the main-repo day-to-day surface, can a Windows-native path stay maintainable as the toolchain grows past one tool?* That's an empirical question better answered by the msys2-viability investigation (Open Question #3) than by re-arguing principles.

*Corrections folded in from Marek's inline review: the PoC installs into a removable `.tools/` (not an MSI installer, as an earlier draft stated); `lx` was the hardest candidate, not the "easy one"; and "WSL is reproducible, the PoC is not" was a false framing — the PoC is reproducible, and the container's added property is closure under tool addition.*

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
