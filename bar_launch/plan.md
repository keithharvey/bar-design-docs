# `just bar::launch` — unified BAR dev launch across Linux & Windows (WSL2)

## Context

Today, two tools live side-by-side and don't quite talk to each other:

- **BAR-Devtools** (`~/code/BAR-Devtools`) — `just`-based orchestrator. Clones repos, builds the engine, links live checkouts of `Beyond-All-Reason/`, `BYAR-Chobby/`, and the engine into the BAR data dir (`$XDG_STATE_HOME/Beyond All Reason` on Linux). No `just launch` recipe; user runs the AppImage by hand. Linux-first; Windows users are expected to be in WSL2.
- **bar_debug_launcher** (`~/code/bar_debug_launcher`) — Tk GUI that scans the BAR data dir's `cache/` and `engine/` folders, presents a dropdown of menu/game/replay choices, and shells out to either the AppImage launcher (for `modtype 0`, with a generated JSON config) or the engine binary directly (for `modtype 1` / `5`). Knows nothing about Devtools symlinks, repos, or hot-reload.

The gap: a developer who's checked out BAR-Devtools and wants to test their local Lua / engine changes has to (a) run the right `just link::create` recipes, (b) remember which menu/game name maps to their local checkout, (c) launch the AppImage or engine themselves. On WSL2 this is worse — the engine has to run as a native Windows process for usable perf (WSLg is unacceptable for Recoil), the BAR data dir lives on `\\wsl$\...` which is slow for runtime IO, and there's no agreed-upon sync target.

**Goal:** a single `just bar::launch` recipe that:
1. Ensures Devtools symlinks/syncs are in place for the **currently checked-out** BAR / Chobby / engine.
2. Hands off to bar_debug_launcher as the user-facing UI (or runs it headless with `--no-gui` for automation).
3. Works identically on Linux and on Windows-via-WSL2 — bridging the WSL↔Windows filesystem gap with rsync rather than symlinks for runtime data.

## Implementation phasing

The work splits into three phases:

- **Phase 1 — Perf probe.** A throwaway diagnostic script run on the user's own Windows/WSL2 box. Generates the data we need to commit to a sync architecture (or to delete the entire sync-daemon design if `\\wsl$\…` direct reads turn out to be fast enough). No production code; nothing to merge upstream. Output: a small results table the user pastes into this plan.
- **Phase 2 — Linux end-to-end.** `just bar::launch` works on Linux. All `bar_debug_launcher` refactor work — package reshape, CLI, `intents.py`, GUI nomenclature cleanup, AppImage env-var read — ships in this phase, **bundled together** with the BAR-Devtools recipe/setup work. The unification of the confusing dropdown labels is much easier to justify in a "here's the cross-tool refactor" framing than as a standalone launcher PR.
- **Phase 3 — Windows mirror.** Whatever architecture Phase 1's perf probe selects gets implemented: sync daemon (if needed), Windows-side Python, `.cmd` shim, `scripts/launch.sh` WSL2 branch. Purely additive on top of Phase 2; **does not require Phase 2 to be redesigned** — Phase 2's CLI, `intents.py`, and recipe are designed up front to be platform-portable.

This phasing tells a clearer PR story: Phase 1 is data-gathering, Phase 2 is reviewable against a Linux-native dev box with no Windows context, and Phase 3 is "do for WSL2 what Phase 2 already proved on Linux."

## Architecture

```
                       ┌──────────────────────────────────┐
   user runs           │       just bar::launch           │
   ───────────────►    │  (in BAR-Devtools, any platform) │
                       └─────────────┬────────────────────┘
                                     │
                  ┌──────────────────┴──────────────────┐
                  │  Linux                              │  WSL2 (Phase 3)
                  ▼                                     ▼
        ┌────────────────────┐               ┌──────────────────────┐
        │  bar-launch (py)   │               │   sync daemon        │
        │  on $XDG_STATE_HOME│               │   (rsync + watchexec)│
        │  → engine via      │               │   3 WSL repos ──►    │
        │  symlinks          │               │   Windows data dir   │
        └────────┬───────────┘               └──────────┬───────────┘
                 │                                      │
                 │                                      ▼
                 │                          ┌────────────────────────┐
                 │                          │ Windows-side python.exe│
                 │                          │  -m bar_launch         │
                 │                          │  --data-dir <synced>   │
                 │                          └──────────┬─────────────┘
                 │                                     │
                 ▼                                     ▼
              ┌──────────────────────────────────────────────┐
              │           Recoil engine                      │
              │           (--menu / start script)            │
              └──────────────────────────────────────────────┘
```

There is no PyInstaller binary, no `bar-launch.exe`, no Windows-side native shim beyond a tiny `.cmd` text file. Both platforms run the same Python source.

---

# Phase 1 — Perf probe (data first, decisions after)

Throwaway diagnostic. Run on the user's Windows/WSL2 box once. No production code, nothing merged. The numbers determine whether Phase 3 needs a sync daemon at all, or whether direct `\\wsl$\…` reads from Windows are fast enough that we delete the entire sync architecture.

## P1.1 — `scripts/probe_wsl_sync.py`

A standalone Python script with subcommands selectable per host (refuses to run a Windows-only mode from WSL or vice versa). Generates a synthetic tree on WSL ext4 mimicking BYAR-Chobby's shape (~3000 small Lua files, ~200KB each, ~50 dirs), then measures three architectures plus a no-WSL baseline:

- **(0) NTFS-local baseline.** Tree generated directly on Windows-local NTFS; Windows-side process reads it. No WSL, no Plan9, no sync. Anchors the floor: separates "Plan9 / sync overhead" from "this workload is just IO-heavy." Run with `--win-baseline` (Windows Python).
- **(i) `WSL ext4 → /mnt/c/...` via rsync.** From inside WSL: `rsync -a --delete --inplace src/ /mnt/c/Users/<u>/AppData/Local/BAR-DevSync-probe/`. Engine reads NTFS local. The "obvious" architecture.
- **(ii) Direct `\\wsl$\<distro>\...` reads from Windows.** Baseline only. We already know the game runs unacceptably under this setup; we measure it to anchor the other numbers, not as a candidate architecture.
- **(iii) Windows-side watch + copy from `\\wsl$\<distro>\...` → Windows-local NTFS.** Windows process polls the UNC tree for changes and copies them locally. Tests whether the plan9 server emits useful change-detection signals to Windows-side fsevents at all, and at what latency.

For each architecture, four scenarios:

- **a) Cold copy / cold read** of the full ~3000-file tree.
- **b) Incremental update**, 1 file changed.
- **c) Incremental update**, 50 files changed.
- **d) Sustained loop**: WSL side touches 5 random files every 1s for 60s; the measuring side records end-to-end latency from "file written WSL-side" to "new content readable on the target side." Reports median, p95, max.

The script is platform-aware (`platform.system()` + `/proc/version` check) and ships subcommands: `--setup` (WSL), `--rsync` (WSL), `--win-read` (Windows Python), `--win-watch` (Windows Python), `--win-baseline` (Windows Python, scenario (0)), and `--wsl-touch-loop` (WSL helper paired with the Windows-side measuring runs). A separate `--all` subcommand prints step-by-step run instructions so the user can copy/paste the right commands into the right shell on the right side.

For (ii) and (iii) there is also an `auto` subcommand (WSL): it launches the Windows-side measurer over WSL2 interop (`py.exe -3 \\wsl$\<distro>\...\probe_wsl_sync.py win-{read,watch}`) with `--non-interactive --ready-flag <flag>`, polls the flag to know when Windows has reached the (d) phase, drives the touch loop in-process, then collects the JSON. Designed to remove the hand-coordinated 3-second wait and the manual touches between (a)/(b)/(c) — the original sources of measurement noise. Runs `--iterations N` (default 3), pools the raw (d) latency samples across runs, drops the top 1% (`--trim-pct 0.01`) before reporting median/p95, and keeps the un-trimmed `max_ms_raw` so one-off Plan9 / Defender stalls remain visible without dominating the central tendency.

## Decision matrix the probe feeds

| Outcome of probe                                                          | Phase 3 architecture                                            |
|---------------------------------------------------------------------------|-----------------------------------------------------------------|
| (i) sustained loop median < ~500ms                                        | rsync from WSL side, Linux-side watchexec. Original P3.2 design.|
| (iii) detect+copy median < ~500ms and beats (i)                           | Windows-side watch process; no Linux-side watchexec, no rsync.  |
| Everything sucks                                                          | Stop and rethink — fall back to the architecture options already mapped out elsewhere. |

## Phase 1 deliverable

The user runs the script, pastes the result table into this plan as a "Probe results" section, and we pick the Phase 3 architecture based on the table — not folklore.

## Probe results

Run on a Windows 11 / Ubuntu-24.04 WSL2 host on 2026-05-01. Raw JSON in
`probes/` next to this plan. (i) is a single `rsync` run (no auto orchestrator
— the rsync architecture has no Windows side to coordinate with); (ii) and
(iii) are aggregated via `probe_wsl_sync.py auto --arch all --iterations 3`,
which pools sustained-loop samples across runs and trims the top 1% so a
single Plan9 / Defender stall doesn't dominate the central tendency.

| Scenario                         | (0) NTFS-local baseline   | (i) WSL rsync → /mnt/c     | (ii) Windows direct UNC reads | (iii) Windows watch+copy from UNC |
|----------------------------------|---------------------------|----------------------------|-------------------------------|-----------------------------------|
| (a) cold (3000 files)            | _todo_                    | 26.22 s                    | 31.6 s (read, mean of 3)      | 43.6 s (copy, mean of 3)          |
| (b) inc 1 file / warm reread     | _todo_                    | 8.108 s                    | 31.22 s (warm reread, mean)   | n/a (auto skips)                  |
| (c) inc 50 files                 | _todo_                    | 8.075 s                    | n/a                           | n/a (auto skips)                  |
| (d) sustained median             | _todo_                    | 7314 ms                    | **77.4 ms** ✅                | **109.5 ms** ✅                   |
| (d) sustained p95                | _todo_                    | 11090 ms                   | 127.4 ms                      | 179.3 ms                          |
| (d) sustained max (trimmed/raw)  | _todo_                    | — / 11870 ms               | 141.3 / 176.1 ms              | 197.6 / 215.1 ms                  |
| (d) samples                      | _todo_                    | 298 (poll-rsync @ 200 ms)  | 891 / 900 (3 auto iters)      | 891 / 900 (3 auto iters)          |

> **(0) NTFS-local baseline** is a no-WSL control: tree generated on `C:\` and
> read by the same Windows Python harness. Establishes the floor for the
> chosen-arch (iii) numbers — anything in (iii) above the baseline is sync /
> Plan9 overhead, not raw IO cost. Pending; run with `--win-baseline`.

### Reading the table

- **Both (ii) and (iii) clear the <500 ms decision-matrix threshold by
  ~5×.** The relative ranking flipped from the noisy single-shot hand runs:
  in the auto run (ii)'s median is 77.4 ms (vs. ~10 s hand-run) and (iii)'s
  is 109.5 ms (vs. ~100 ms hand-run, with a 58 s outlier). The hand-run
  noise was almost entirely hand-coordination overhead between the WSL
  touch loop and the Windows-side measurer; the auto orchestrator's
  ready-flag handshake removes it.
- **The hand-run (iii) 58754 ms max did not reproduce** in 900 auto-run
  samples (max_raw 215.1 ms). Treat the 58 s figure as a one-off Plan9 /
  Defender stall on a cold cache, not a structural concern. We retain the
  earlier "exclude `<chosen-dir>/` from Defender if it recurs in the real
  launcher flow" mitigation as a backstop.
- (i)'s 7.3 s sustained median still rules it out for the sustained edit
  loop. The poll-rsync@200 ms propagator can't keep up with 5 touches/sec —
  events queue up, then per-tree rsync scans dominate. The originally-
  planned WSL-side rsync + watchexec pipeline is dead.
- (i)'s incremental rsync (b)/(c) at ~8 s confirms that the bottleneck for
  (i) is the propagator, not rsync's own cost: a 1- or 50-file rsync
  finishes in seconds, but the 200 ms poll cadence multiplied by the
  rescan-everything cost makes the sustained-loop median 7 s.
- (ii) wins (iii) on raw probe latency by ~30 ms. (ii) is a single Plan9
  round-trip per file; (iii) does Plan9 read + local NTFS write on each
  event. **(iii) is still the chosen architecture** because the probe
  measures dev edit-loop latency, not engine runtime read patterns. See
  the Decision block below for why that distinction matters.

### Decision

**Phase 3 sync architecture: (iii) — Windows-side watch + copy.**

The probe's (d) measurement is a 64-byte marker read — a lightweight smoke
test for the propagation layer, not the actual engine workload. Real BAR
runtime IO is per-frame Lua reads totalling hundreds of MB across the
session, and the substrate that reads gets is what matters for game-load
and gameplay smoothness:

- **Architecture (ii)** leaves the engine reading `\\wsl$\…` directly at
  gameplay rate. Marek's independently-measured Test 1 in
  `bifurcated_types/dev_setup_restructured.md` (game source on WSL,
  symlinked to a Windows install) shows 7m30s cold loads and 4m10s warm
  loads with mid-game freezes — that's the same Plan9 read path the engine
  would walk under (ii). A 77 ms probe latency does not buy us out of that
  cost; it just confirms Plan9 is *fast enough* for sparse 5-touches/sec
  marker reads.
- **Architecture (iii)** isolates the engine from Plan9 entirely. The
  engine reads from Windows-local NTFS at native speed (≈24 s warm load
  per Test 1's all-Windows baseline). The only Plan9 crossing happens on
  the dev edit loop, which the probe shows tolerates the boundary at
  ~109 ms median.

So we trade ~30 ms median dev-loop latency for ~3.5 minutes of game-load
time per warm restart. (iii) wins decisively once the comparison is on
the right axis.

Concrete consequences for the Phase 3 sections below:

- P3.2 ("Sync daemon") flips from a WSL-side rsync + watchexec design to a
  **Windows-side process** that watches `\\wsl$\Ubuntu-24.04\home\<u>\code\BAR-Devtools\{Beyond-All-Reason,BYAR-Chobby,RecoilEngine/build/...}`
  and mirrors changes to `<BAR_DEVSYNC_DIR>/{games/Beyond-All-Reason,games/BYAR-Chobby,engine/local-build}`. Likely
  built on Python's `watchdog` package (cross-platform) running inside the
  same Windows venv created for `bar-launch`.
- P3.5 (`scripts/launch.sh` WSL2 branch) starts the watcher *via*
  `cmd.exe /c …` rather than starting `watchexec` in WSL.
- The `--inplace` rsync requirement still applies to the Windows-side
  copy step (engine has files mmaped; we don't want inode rotation).
- The probe script (`scripts/probe_wsl_sync.py`) and these JSONs can be
  deleted once Phase 3's watcher lands.

---

# Phase 2 — Linux end-to-end

Bundled launcher + Devtools work, all justified together as "make this dev tool less confusing and integrate it with Devtools." Everything in this phase is testable on a Linux-only dev box; nothing in this phase depends on having WSL2, a Windows host, or rsync.

## P2.1 — Promote bar_debug_launcher to a parameterized `bar-launch` tool

Today the launcher is a Tk-only script with implicit inputs (cwd is the BAR install dir, repos and engine are discovered by scanning the data dir). Make it driveable from a `just` recipe.

- **CLI flags**, all optional, all overriding the existing autodetect:
  - `--gui` (default) / `--no-gui` (headless: requires `--play` and at least `--source` or `--map`).
  - `--data-dir PATH` (overrides `find_linux_datadir`).
  - `--engine VERSION_OR_DIR` (skips engine dropdown; accepts a folder name like `recoil_2025.06.19` or the literal `local-build` for the Devtools-symlinked engine).
  - `--play {chobby,bar,replay}` — what to launch.
  - `--source {latest,local,pinned}` — `latest` resolves to `rapid://...:test` (today's only channel); `local` requires the Devtools symlink to be in place; `pinned` requires `--version`.
  - `--version VERSION` — only meaningful with `--source pinned`.
  - `--boot {launcher,engine}` — replaces the implicit modtype 0/1/5 selection. Defaults to `launcher` for `--play chobby`, `engine` for `bar` and `replay`.
  - `--map NAME` — only meaningful with `--play bar`.
  - `--launcher-binary PATH` (override AppImage discovery).
  - `--print-cmd` (resolve and print the engine command, don't execute — useful for the just recipe to debug).
  - `--config PATH` (load defaults from a JSON; lets Devtools pin sane defaults per checkout).
- **Refactor**: extract the current `gencmd` body into a pure `build_runcmd(intent, engine, map, …)` function so both the GUI's combobox handler and the new CLI path share one code path. Critical files: `BAR_Debug_Launcher.py:514-568` (genscript / gencmd / config-file blob).
- **Keep `refresh()` and `parsecache()` as-is** — the local-games scan from the open Linux PR (line 248–268) is exactly what the dev-mode flow needs to surface a Devtools-linked checkout.
- **No PyInstaller, no compiled binary.** `bar-launch` ships as Python source. On Linux it's invoked as `python -m bar_launch …` (via a venv created during setup, see P2.5).

## P2.2 — UI nomenclature: collapse `$VERSION` / folder-name / rapid-URI into intents

The dropdown today is genuinely cryptic. A representative slice of what `modinfos` produces:

| Current label                                            | What it actually does                                          |
|----------------------------------------------------------|----------------------------------------------------------------|
| `Spring-launcher with rapid://byar-chobby:test`          | Run AppImage launcher → downloads latest Chobby → starts menu  |
| `Latest BYAR Chobby Lobby: rapid://byar-chobby:test`     | Run engine directly with `--menu rapid://byar-chobby:test`     |
| `Latest BAR Game: rapid://byar:test`                     | Run engine directly with a generated start script for BAR      |
| `Beyond All Reason $VERSION`                             | Same as above but for a specific cached version                |
| `Spring-launcher with Beyond All Reason $VERSION`        | Same as the first row, but pinned to a cached menu version     |
| `[LOCAL] Beyond-All-Reason`                              | Run engine against the locally checked-out BAR repo            |

The reason these are confusing is that they leak three orthogonal axes into one string:

1. **What you want to play** — the menu/lobby (Chobby), the game (BAR), or a replay.
2. **Which version** — bleeding-edge from `rapid://...:test`, a specific cached release (`$VERSION` is a literal placeholder the engine substitutes from rapid metadata at runtime), or your local checkout.
3. **How it boots** — through the AppImage launcher (handles downloads, splash, auto-update) or straight into the engine (faster, no download retry logic, breaks if anything's missing).

Proposal: **invert the UI to be intent-first, with a "show technical details" affordance.**

- Primary GUI: two compact dropdowns instead of one mega-list.
  - **What to launch**: `Chobby (lobby/menu)` · `BAR (game directly)` · `Replay…`
  - **Source**: `Latest` (today resolves to `rapid://...:test`; if BAR ever introduces a stable channel it slots in here) · `Local checkout (RecoilEngine HEAD: a1b2c3d)` · `Pinned: <version>` (only enabled if cached versions exist).
- A **boot mode** toggle (advanced disclosure only) defaulting to `launcher` for Chobby and `engine` for BAR/Replay, with an info tooltip.
- An **ⓘ button** next to each selection that reveals the underlying technical identifier (`rapid://byar-chobby:test`, `Beyond All Reason 2024.05.1234`, etc.). For a "Local checkout" source, the tooltip shows the resolved source path on disk (`~/code/BAR-Devtools/Beyond-All-Reason`) rather than trying to render a `→` arrow from the target — `just link::create` may use hardlinks rather than symlinks (one of the open questions below), and hardlinks have no recoverable arrow-style representation.
- The `[LOCAL]` prefix goes away as a label decoration; "local checkout" becomes a first-class source choice that's only available when the corresponding `link::create` has been run.

Internally, `build_runcmd()` translates `(play, source, boot)` back into the existing `(modinfo, modtype, name)` shape so the engine command-construction code doesn't have to change. The translation table is the single place we encode what `$VERSION`, `rapid://...:test`, and `[LOCAL]` actually mean — and it doubles as the canonical reference doc for newcomers (including, per the user's note, the user themselves).

This translation layer lives in `bar_debug_launcher/intents.py` (new), is unit-testable without Tk, and is what `--print-cmd` exercises. Tests of `intents.py` are the regression net for the GUI: as long as `build_runcmd` produces the same engine command for a given intent, the GUI's behavior is preserved.

## P2.3 — Custom engine builds (when RecoilEngine is symlinked)

If the user has run `just link::create engine`, they have a local Recoil checkout, and we should treat the **docker-build-v2 output** (`RecoilEngine/build/.../spring`) as the *default* engine selection in `bar-launch` — not just one of N options.

- `bar-launch`'s engine dropdown labels this entry distinctly, e.g. `[DEV] local-build (RecoilEngine HEAD: a1b2c3d)`. CLI invocation that explicitly asks for it (`--engine local-build` or `--source local`) always selects this entry; that path is non-negotiable. For the GUI's cold-start default with no flags, we wrap the selection in a small policy function with two implementations: `dev build > newest stable > rest` (our preferred default) and the legacy `engine_cb.set(sorted(engines.keys())[-1])`. The policy is a one-line code switch so if Marek pushes back on the new default, reverting is a trivial diff rather than a structural change.
- The display shows the short git SHA of the checked-out RecoilEngine. `findengines()` already discovers the dir; extend it to optionally read a sibling `.git/HEAD` (or a `BUILD_INFO` file the docker-build-v2 step can drop) for the SHA.

Phase 2 only addresses the Linux engine binary. The Windows engine binary question is Phase 3.

## P2.4 — AppImage path: lazy, only when `--boot launcher` is asked for

The AppImage is BAR's spring-launcher binary; it handles splash, auto-update, and rapid downloads, then invokes the engine. **Every dev path that uses `--boot engine` ignores the AppImage entirely** — the engine binary in `<datafolder>/engine/<ver>/spring` is invoked directly. The only time we need the AppImage is when someone explicitly asks for `--boot launcher` (the default for `--play chobby --source latest`, where having the launcher manage the rapid pull mirrors the real-player experience).

So we don't prompt for it at setup. Instead:

- **`BAR_APPIMAGE_PATH` env var** (or `--launcher-binary` CLI flag) is read lazily, only when `--boot launcher` is the resolved boot mode.
- **Resolution order** when the launcher binary is needed:
  1. `--launcher-binary` CLI flag (explicit, wins).
  2. `BAR_APPIMAGE_PATH` env var.
  3. **Cwd-scan fallback, preserved for the standalone "drop next to the AppImage and double-click" workflow.** This is how `BAR_Debug_Launcher.py` is used today by people who aren't going through Devtools at all. We must not break that path. The cwd scan only fires if neither (1) nor (2) supplied a path, which is the only state a standalone-launched user would be in.
  4. Fail with `"set BAR_APPIMAGE_PATH or pass --launcher-binary to use --boot launcher"`.
- **README documents `~/Applications/Beyond-All-Reason.AppImage`** as the suggested location (AppImageLauncher's canonical path) and links to where to download it. No setup prompt; the Devtools-flow user sets the env var if they want `--boot launcher`, the standalone user keeps double-clicking next to the AppImage and the cwd scan finds it.
- **Keep the case-insensitive regex** so `BAR_APPIMAGE_PATH=~/Applications/` (a directory) still resolves to whichever AppImage is in there.

## P2.5 — Linux-side `just bar::launch` recipe

```
launch *FLAGS:
    @./scripts/launch.sh {{FLAGS}}
```

`scripts/launch.sh` (new) on Linux:

1. **Pre-flight**: confirm the link recipes have run (engine, bar, chobby symlinks exist in `$XDG_STATE_HOME/Beyond All Reason`). If not, prompt or auto-run `just link::create {engine,bar,chobby}` (re-uses existing `just/link.just`).
2. **Resolve interpreter**: ensure a `bar-launch` venv exists at `~/.local/share/bar-devtools/bar-launch-venv/`. If not, create it (`python3 -m venv …`, `pip install -e ~/code/bar_debug_launcher`). The venv is a one-time bootstrap; subsequent runs skip straight to step 3.
3. **Invoke**: `<venv>/bin/python -m bar_launch <FLAGS>`. Symlinks are zero-overhead; no sync daemon needed on Linux.

The script has a platform branch in it from day one, but in Phase 2 the WSL2 branch is a stub that prints "WSL2 path lands in Phase 3" and exits. That stub is deliberate — it makes the Phase 3 PR a focused diff instead of a structural rewrite.

## P2.6 — Register `bar_debug_launcher` in BAR-Devtools' repo set

Devtools manages its peer repos via `repos.conf` (default URLs/branches, committed) plus `repos.local.conf` (gitignored, per-user path overrides — see explore agent notes). `bar_debug_launcher` becomes one of those peers:

- **`repos.conf` entry** (committed): default upstream URL + branch for `bar_debug_launcher`. A contributor with no local checkout gets it via `just repos::clone` like every other Devtools peer.
- **`repos.local.conf` pattern** (per-user): a developer with `~/code/bar_debug_launcher` already checked out points Devtools at it via the existing path-override mechanism. This is the closest thing to a "symlinked submodule" without actually being a git submodule (which we explicitly don't want — submodules force a pinned SHA on every Devtools clone, and we want the launcher's main to track independently during this integration period).
- **`scripts/repos.sh` already handles** the clone-or-symlink behavior. We're adding a row to a config table, not new logic.

No filesystem symlink is required from the developer. If they prefer to symlink `~/code/BAR-Devtools/bar_debug_launcher → ~/code/bar_debug_launcher` manually, that also works and `repos.local.conf` documents both options.

## P2.7 — Distribution & first-run (Linux)

- Extend BAR-Devtools `setup.sh` to create the venv described in P2.5 and `pip install -e ./bar_debug_launcher` so user-side patches show up without re-installing.
- End-user contract on Linux: `just bar::launch` Just Works after `just setup && just link::create bar chobby engine`. No prompts, no manual Python install (Linux distros ship Python 3 by default; setup script verifies ≥ 3.10 in the existing distro-detection block).

## Phase 2 PR sequencing

Three PRs across two repos. The first goes out alone as a probe of maintainer responsiveness on uncontroversial bugfixes; the latter two are a coordinated pair sharing one justification ("integrate the launcher with Devtools and clean up the dropdown nomenclature in the same review").

1. **`random_fixes` PR** to `bar_debug_launcher` (branch: `random_fixes`, ready to push). Single commit. Three small Linux-side bugfixes only:
   - `parsecache` sort key was `lambda x:[1]` — sorts by a constant list, so "newest archivecache wins" silently did nothing. Fixed to `lambda x: x[1]`. Same loop now also picks up archivecache.lua files placed directly under the cache dir, not just one level deep.
   - `refresh()` menus loop had an early `break` preventing more than one `$VERSION` menu from being registered. Removed.
   - `find_linux_launcher_binary` regex tightened to be case-insensitive and tolerate separator variants (`Beyond_All_Reason-x.y.AppImage`, `beyond-all-reason*.appimage`).

   Strictly fixes — no new features, no refactor. Commit message doubles as PR description. ~12 lines net.
2. **`cli` PR** to `bar_debug_launcher` (branch: `cli`, based on `random_fixes`):
   - New `bar_launch/` package: `core.py` (discovery, platform constants, AppImage env-var lookup), `engine_cmd.py` (`build_runcmd`, start-script + dev-lobby-config writers), `intents.py` ((play, source, boot) → modinfo translation), `__main__.py` (argparse CLI).
   - `BAR_Debug_Launcher.py` keeps the GUI; delegates AppImage discovery to `bar_launch.core` and adds the [LOCAL] local-games scan to `refresh()` so `--source local` has entries to resolve against. GUI behavior otherwise unchanged.
   - `pyproject.toml` so `pip install -e .` works for the venv that Devtools' setup script will create.
   - `tests/test_intents.py` exercising the intent translation without Tk.
   - **GUI nomenclature changes (intent-first dropdowns, ⓘ tooltip) deferred to a follow-up commit on the same branch** — they're a user-visible UX change that benefits from real-game testing first.
3. **Devtools integration PR** to BAR-Devtools (branch: `launch`, paired with PR 2):
   - Adds `bar_debug_launcher` to `repos.conf`; documents the `repos.local.conf` path-override option in the Devtools README.
   - New `just/launch.just` recipe and `scripts/launch.sh` with Linux branch implemented, WSL2 branch as a stub.
   - Setup-script extension: create the venv at `~/.local/share/bar-devtools/bar-launch-venv/`; `pip install -e ./bar_debug_launcher`. No `BAR_APPIMAGE_PATH` prompt — that var is read lazily only when `--boot launcher` is requested (P2.4).
   - README adds the AppImage canonical-path guidance for users who want `--boot launcher`.

After PRs 2 and 3 land together, a Linux contributor running `just setup && just link::create bar chobby engine && just bar::launch` gets a working dev-mode game launch end-to-end. Phase 3 (Windows) rebases on top of `launch`.

---

# Phase 3 — Mirror the Linux flow on Windows (WSL2)

Phase 3 is purely additive: it does not modify the Phase 2 CLI, `intents.py`, GUI, or engine-command construction. It adds whatever sync architecture the Phase 1 probe selected, populates the WSL2 branch of `scripts/launch.sh`, and arranges for `python -m bar_launch` to run on the Windows side instead of the WSL side.

The exact shape of P3.3 ("Sync daemon") depends on Phase 1 results. If the probe finds direct `\\wsl$\…` reads are fast enough, P3.3 disappears entirely and the engine reads through the SMB shim with no rsync involvement.

## P3.1 — WSL2-aware `setup::init` and the sync target dir

Detecting WSL2 (`grep -qi microsoft /proc/version` or `[ -n "$WSL_DISTRO_NAME" ]`) happens during `just setup` / `setup::init`, **before** any `link::create` recipe runs. The reason: on WSL2 we are *not* symlinking the engine/games into `$XDG_STATE_HOME/Beyond All Reason` — we're (probably) rsyncing them to a Windows-side path, depending on Phase 1's result, and `link::create` needs to know that's where it should be wiring things (it becomes a no-op on WSL2 in favor of either the sync daemon or direct UNC reads).

What `setup::init` does on WSL2 detect:

1. **Prompt the user** with a short explainer the first time they run setup on WSL2:

   > "WSL2 detected. Linux↔Windows symlinks are too slow for runtime game files (the engine reads Lua per-frame). Instead, BAR-Devtools will keep your repos on the Linux side and continuously rsync them to a Windows folder that the game reads from. Where should that folder live?"

   Default suggestion: `%LOCALAPPDATA%\BAR-DevSync\` (i.e., `/mnt/c/Users/<user>/AppData/Local/BAR-DevSync/`). `%LOCALAPPDATA%` is Microsoft's canonical "per-user, never-roamed, never-OneDrive'd" directory — it's where BAR's Windows installer already puts the game (`%LOCALAPPDATA%\Programs\Beyond-All-Reason\`). Documents is the default OneDrive redirection target on consumer Windows setups and we explicitly avoid it. The prompt also advises against `%TEMP%` and `\\wsl$\…`.

2. **Persist the choice** to `BAR-Devtools/.env` as `BAR_DEVSYNC_DIR=…` — that's the existing user-config convention (see `scripts/setup.sh` writing `DEVTOOLS_DISTROBOX` to `.env`, and `scripts/doctor.sh` checking for it). Every `just` recipe and shell script picks it up via the standard env-loading path. Subsequent `just` invocations read it; no re-prompt.

3. **Create the directory tree** the sync daemon and `bar-launch` will use. The Windows-side path is a real, full BAR data dir that the engine reads and writes freely — `cache/`, `demos/`, `infolog.txt`, settings, replays etc. all get created by the engine on first run and live entirely Windows-side. The sync daemon only writes into **three specific subpaths** (the three things that come from the Devtools checkout), and leaves the rest alone:

   ```
   <chosen-dir>/                       # --data-dir target; engine owns everything except…
     engine/local-build/               # ← rsync target #1 (RecoilEngine build artifact)
     games/Beyond-All-Reason/          # ← rsync target #2 (BAR Lua repo)
     games/BYAR-Chobby/                # ← rsync target #3 (Chobby Lua repo)
     bin/bar-launch.cmd                # ← dropped by setup; user invokes from Windows
     # everything else (cache/, demos/, infolog.txt, settings, packages/, pool/, …)
     # is engine-managed runtime state; sync daemon never touches it
   ```

   Initial `setup::init` `mkdir -p`s these three target paths plus `bin/`; everything else materializes when the engine runs for the first time.

4. **Make `link::create` WSL-aware**: on WSL it skips symlink creation and instead registers the sync daemon's source/target pair. On Linux it behaves as it did in Phase 1.

User-facing flow: `just setup` → answers the WSL prompt once → `just link::create bar chobby engine` → `just bar::launch`.

## P3.2 — Sync daemon (only if Phase 1 says we need one)

If the Phase 1 probe shows direct `\\wsl$\…` reads are acceptable, this section is deleted in implementation. Otherwise:

- **Sources** (WSL ext4): the three Devtools checkout dirs — `~/code/BAR-Devtools/Beyond-All-Reason`, `~/code/BAR-Devtools/BYAR-Chobby`, `~/code/BAR-Devtools/RecoilEngine/build/...`.
- **Targets** (Windows NTFS): the three subpaths in `<chosen-dir>` from P2.2.
- **Mechanism**:
  - `rsync -a --delete --inplace` for the initial copy.
  - `watchexec -w <src> -- rsync -a --delete --inplace <src>/ <dst>/` for incremental updates. `--inplace` matters: the engine has files open and we don't want to rotate their inodes mid-frame.
  - One watchexec process per top-level dir (engine vs bar vs chobby) so a churny engine rebuild doesn't starve game-Lua updates.
- **Logging**: `~/.cache/bar-launch/sync.log` (game logs go to the engine's normal `infolog.txt` Windows-side). Expose via `just launch::logs sync` and `just launch::logs game`.

The exact rsync pattern — direct WSL→`/mnt/c/`, or Windows-host watchexec watching `\\wsl$\…`, or something else — is whichever option won the Phase 1 probe.

## P3.3 — Python on Windows: ask once, persist to `.env`

`bar-launch` runs as Python source on Windows too. Same pattern as `BAR_APPIMAGE_PATH` and `BAR_DEVSYNC_DIR`:

> "Path to a Python ≥ 3.10 on Windows? \[`py -3`]"

Default is `py -3` — the Python Launcher's canonical multi-version dispatch, which picks the highest installed registered interpreter (pyenv-win, conda, Microsoft Store, python.org all register). User accepts, supplies an explicit path, or types `install` to run `winget install Python.Python.3.12 --silent` (still UAC-prompted) and accept the default afterward. Result persists to `BAR-Devtools/.env` as `BAR_LAUNCH_PYTHON=…`. Setup uses it once to bootstrap a project-owned venv at `<chosen-dir>/.venv/`; from then on `bar-launch` only calls the venv's Python.

Why this avoids the binary-distribution rabbit hole entirely:

- `python.exe` is signed (Microsoft Store and python.org both ship signed builds), so SmartScreen doesn't fire.
- `.py` source isn't a packed PE, so Defender's heuristics don't fire.
- We never ship a binary, never sign anything, never build reputation.

## P3.4 — `bar-launch.cmd` Windows shim

`<chosen-dir>/bin/bar-launch.cmd` is a small text shim dropped by setup. Its job is unchanged from the abstract concept of a launcher: read `BAR_LAUNCH_PYTHON` and `BAR_DEVSYNC_DIR` from `BAR-Devtools/.env` (via WSL invocation), build the right argv, exec.

The shim is **generated by setup** with `BAR_LAUNCH_PYTHON` and `BAR_DEVSYNC_DIR` baked in as literals — no runtime re-discovery, no `wsl.exe` call to grep `.env` on every launch:

```bat
@echo off
"C:\path\to\python.exe" -m bar_launch --data-dir "C:\Users\<user>\Documents\BAR-DevSync" %*
```

If either `.env` value changes, `setup` (or a `just launch::regen-shim` recipe) rewrites the file. A `.cmd` is text, not a PE — no SmartScreen, no Defender heuristics, no signing. The shim is dumb on purpose; all interesting logic stays in the Python.

## P3.5 — `scripts/launch.sh` WSL2 branch

Replace the Phase 2 stub with the real WSL2 platform branch:

1. **Pre-flight**: confirm `BAR_DEVSYNC_DIR` is set in `.env`; if not, suggest `just setup` and exit.
2. **Start sync daemon** (only if P3.2 applies): `rsync` cold copy if needed, then start watchexec processes in the background. Trap exit to clean them up. Skipped entirely if Phase 1 selected the direct-UNC architecture.
3. **Hand off to Windows**: `cmd.exe /c "%BAR_DEVSYNC_DIR%\bin\bar-launch.cmd" <FLAGS>`. The Windows-side `python.exe` runs the GUI/CLI; the engine launches as a native Windows process.
4. **Tear down**: stop the sync daemon (if running), leave the runtime dir in place (it's a cache, not state).

## P3.6 — Custom engine builds on Windows

If the user has a local RecoilEngine checkout, the docker-build-v2 image must produce a Windows-targeted binary that lands in the `engine/local-build/` target. Confirm whether the existing image's `linux` / `amd64` targets cover this or whether we need a `windows` target added.

If a Windows engine target isn't readily available, the initial Phase 3 release uses the upstream-released Recoil. A Windows engine build is a fast-follow PR.

## Phase 3 PR sequencing

1. **WSL2 setup detection PR** to BAR-Devtools: detect WSL2 in `setup.sh`, prompt for `BAR_DEVSYNC_DIR`, persist to `.env`, create the target subpaths and `bin/`. `link::create` becomes a no-op on WSL2.
2. **Sync architecture PR** to BAR-Devtools: shape determined by Phase 1. Either `scripts/sync.sh` (rsync + watchexec) + `just launch::logs` recipes, or — if direct UNC reads won — a no-op stub plus README documenting the architecture choice.
3. **Windows Python provisioning PR** to BAR-Devtools: prompt for `BAR_LAUNCH_PYTHON`, optional `winget install` flow, venv bootstrap.
4. **`bar-launch.cmd` shim PR** to BAR-Devtools: setup generates the shim with literal paths baked in; document Windows-side invocation in README.
5. **`scripts/launch.sh` WSL2 branch PR** to BAR-Devtools: replace the Phase 2 stub with the real platform branch.
6. **Windows engine build PR** to BAR-Devtools (optional / fast-follow): add docker-build-v2 windows target if needed.

After PR 5 lands, a WSL2 contributor running the same `just setup && just link::create bar chobby engine && just bar::launch` flow gets the same working dev-mode game launch as a Linux contributor.

---

# Cross-cutting decisions

## Should `bar_debug_launcher` become a folder in BAR-Devtools?

**Decision for now: keep it as a separate repo.** Rationale:

- The Phase 2 PRs cross repo boundaries and are easier to review/revert independently than as commits in a megarepo.
- BAR-Devtools currently has no Python in its primary toolchain; pulling in a Tk app changes the reviewer pool and the CI matrix.
- Merging tools across stewardship boundaries is a fight that's easier *after* `just bar::launch` has demonstrated value end-to-end against the separate repo.
- Revisit absorption later once the API is stable.

What this means for the plan: BAR-Devtools' `setup.sh` clones `bar_debug_launcher` as a sibling under `~/code/BAR-Devtools/` via `repos.conf`. A small config change, not an architectural one.

## Remaining open questions

- **Hardlinks vs symlinks today**: the existing `just/link.just` description says "hardlinks" but typical Linux setups do symlinks; verify before claiming the Linux path needs no changes.

# Critical files

- `~/code/bar_debug_launcher/BAR_Debug_Launcher.py` — refactor `gencmd` (line 514) into `bar_launch/engine_cmd.py`; add CLI entry point at `bar_launch/__main__.py`; introduce `bar_launch/intents.py`.
- `~/code/bar_debug_launcher/bar_debug_launcher_config.json` — delete (accidental).
- `~/code/BAR-Devtools/Justfile` and `~/code/BAR-Devtools/just/` — add `launch.just`, register it.
- `~/code/BAR-Devtools/scripts/launch.sh` (new) — platform branch (Linux first in Phase 2, WSL2 stub becomes real in Phase 3).
- `~/code/BAR-Devtools/scripts/setup.sh` — extended in Phase 2 (P2.6, P2.7) and Phase 3 (P3.1, P3.3).
- `~/code/BAR-Devtools/scripts/probe_wsl_sync.py` (new, Phase 1) — perf probe; throwaway, not shipped in setup.
- `~/code/BAR-Devtools/scripts/sync.sh` (new, Phase 3, conditional) — sync daemon orchestration; only if Phase 1 says we need one.
- `~/code/BAR-Devtools/just/link.just` — verify symlink targets match what `bar-launch --data-dir` expects; make WSL-aware in P3.1.
- `~/code/BAR-Devtools/repos.conf` — add `bar_debug_launcher` as a managed sibling repo.
- `~/code/BAR-Devtools/README.md` — AppImage canonical-path guidance (P2.4 / P2.7); WSL2 setup section (P3.x).

# Verification

## Phase 1 (Perf probe)

- Run all four subcommands on the user's actual Windows/WSL2 box; copy the resulting numbers into a "Probe results" section of this plan.
- Decide which Phase 3 architecture to commit to using the decision matrix in P1.

## Phase 2 (Linux)

- From a clean `~/.local/state/Beyond All Reason/`, run `just setup && just link::create bar chobby engine && just bar::launch --no-gui --play chobby --source local`. Engine starts, Chobby loads, `infolog.txt` shows it loaded Lua from `~/code/BAR-Devtools/BYAR-Chobby/...`.
- **GUI regression**: launching with no flags opens the existing Tk window, dropdowns populate (intent-first), "Run" produces an engine command equivalent to what the old `gencmd` produced for the same selection.
- **`--print-cmd`** on a known-good combination returns a string that matches what the GUI's button-click would produce — this is a unit test of `intents.build_runcmd` and is gated in CI.

## Phase 3 (WSL2)

- Same flow as Phase 2, plus: verify the chosen sync architecture's cold copy completes (or that direct UNC reads work, depending on Phase 1's selection), edit a Chobby `.lua` file Linux-side, reload the menu in-game, confirm change visible (<2s latency target informed by Phase 1 results).
- Verify `bar-launch.cmd` invoked directly from a Windows shell (outside of `just`) produces the same engine command as the same flags via `just bar::launch`.
- Verify SmartScreen does not appear on first run (it shouldn't — we're only invoking signed `python.exe`).
