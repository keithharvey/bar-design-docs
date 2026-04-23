# Dev Setup

We will be transitioning to using the BAR Devtools repository to automate installation and setup of all your tools used to work on the game, engine, Teiserver, and services. We are looking for devs to test migrating to BAR Devtools, especially those on Windows, to make the transition for everyone as painless as possible.

See the overall coordinating issue for full details: Beyond-All-Reason/issues/7408

---

## 1. What we're proposing

Three tools are added to a contributor's environment:

- **`just`** — a task runner (like Make, npm scripts, or Rake). Runs the recipes that wrap our tools so contributors don't have to remember invocations.
- **`lx`** (Lux) — a Lua package manager. Manages third-party Lua dependencies declaratively from a `lux.toml` + lockfile.
- **`distrobox`** (Linux) / **WSL** (Windows) — a container/sandbox where the above run, so the toolchain is identical across hosts.

### Game code changes

- **Style.** A single formatter (`stylua`) and linter (`luacheck`) replace per-contributor preferences. CI rejects unformatted code.
- **Spring split.** The `Spring` table is split into `SpringShared`, `SpringSynced`, `SpringUnsynced`. The IDE can now flag context-mismatched calls without having to run the game.
- **Strong typing.** EmmyLua's checker can detect calls with wrong argument types in-editor without having to run the game.

### New developer commands

`just <recipe>` invokes a task. The recipes contributors will use:

| Recipe | What it does |
|---|---|
| `just setup::init` | One-shot setup: installs the container, tools, editor extensions, settings |
| `just setup::editor` | Editor integration only (LSPs, extensions, settings) |
| `just bar::test` | Unit + integration tests |
| `just bar::check` | Type-check (EmmyLua) |
| `just bar::fmt` | Format (StyLua) |
| `just bar::lint` | Lint (luacheck) |
| `just bar::fmt-mig` | Replay codemod transforms onto your branch (catch-up after `mig` lands) |
| `just lua::library` | Recoil → BAR types pipeline for live API iteration |

CI runs `bar::check`, `bar::fmt`, `bar::lint`, and `bar::test` and rejects PRs that fail any. With editor setup completed, `bar::fmt` and `bar::check` happen automatically on save; the others contributors run before pushing.

### Dependencies to migrate

| Dep | Current state | Proposed state |
|---|---|---|
| `kikito/i18n.lua` | Vendored in `modules/i18n/i18nlib/`, drifted from upstream | Lux dependency (already done on `lux-i18n` branch) |
| `recoil-lua-library` | Git submodule | Lux git dependency |
| `common/luaUtilities/json.lua`, `utf8.lua`, etc. | Vendored, drift status unknown | Each replaced with a published rock (e.g., dkjson) or removed; out of scope for this PR stack |

Future deps go through normal review.

---

## 2. What it costs

### Contributor cost

- One-time: install WSL (Windows only) and run `just setup::init`. The container holds all the tools; nothing installed directly on the host.
- Per-task: learn `just bar::*` commands. Equivalent in scope to learning `npm run *` or `make *`.
- Per-PR: run the four CI commands locally before pushing (or rely on editor-on-save for two of them).

### WSL costs (Windows specifically)

WSL is not free. Concretely:

- Filesystem performance is poor when crossing the Windows ↔ WSL boundary (`/mnt/c/...`); BAR work needs to live inside the WSL filesystem to avoid 10×+ slowdowns.
- WSL2 uses Hyper-V, which can conflict with VirtualBox, VMware Workstation, and some Android emulators.
- GPU passthrough for game-client testing has historical quirks (better in 2024+ but still a gotcha for some hardware).
- Initial learning curve for Windows contributors who've never used a Linux shell.

### Maintenance cost

- **BAR-Devtools repo** must be maintained alongside BAR. Currently a small set of just recipes + setup scripts.
- **External dep on Lux** (lumen-oss). If Lux disappears, we'd need to migrate to LuaRocks or vendor differently.
- **Lockfile churn**: dep updates land as small PRs (lockfile bump + adaptation), more frequent than today's "rare bulk update" cadence.

### CI cost

- New CI step: `lx install` to populate `.lux/` before lint/check/test runs.
- One-time: extend `.luarc.json` generation to track resolved Lux paths (currently hardcoded SHAs).

---

## 3. What it replaces

- **Per-host hand-installation** of stylua, luacheck, EmmyLua, lx, clangd → one container.
- **Vendored copies of third-party Lua** (`kikito-i18n`, `common/luaUtilities/*`) → declarative deps.
- **Git submodule** for `recoil-lua-library` → Lux git dependency.
- **Per-contributor editor configuration** (which LSP, which formatter, which extensions) → `just setup::editor` writes a working `.vscode/settings.json` and installs the right extensions.
- **Per-PR formatting nag rounds** → CI gate.

---

## 4. Open questions

These are factual questions someone needs to answer before the doc can settle.

1. Does `lx` require MSVC unconditionally on Windows, or only when installing rocks with native code? If unconditional, can it be filed upstream as an issue? *(Daniel to verify.)*
2. Was a "PowerShell Core everywhere" alternative seriously considered? Pwsh runs on Linux and would avoid WSL for Windows contributors. What ruled it out? *(Open.)*
3. How many third-party Lua deps does BAR realistically grow to over the next 12 months? *(Currently 1. Stakeholders to estimate.)*
4. Where does the line sit between "BAR-Devtools is fine to exist" and "BAR-the-game-repo can take a hard dep on it"? *(Marek's framing — needs a position from each maintainer.)*
5. What is the actual filesystem-perf impact of WSL on the BAR build/test loop today? Is the Chobby filesystem layout affected? *(Empirical — someone with a Windows host runs the numbers.)*
6. If recoil-lua-library moves to Lux, what's the migration path for downstream consumers (CircuitAI, other Recoil-based games)? *(Recoil maintainers' input needed.)*
7. On PR #5902, did `@sprunk` actually weigh in on vendor-vs-package-manager specifically, or only on PR mechanics? *(Daniel to verify before citing.)*

---

## 5. Opinions

Tagged by holder. Body sections above are intended to be agreement substrate; this is where positions live.

### Daniel (attean)

- **Vendoring at scale produces drift**, not in the abstract but in this org specifically. The kikito-i18n case (vendored → drifted → accidental fork) is the existence proof. lx adoption is partly about preventing the next one.
- **Single-submodule consumption is fine today; the concern is future-state.** Adding more submodules over time produces what Recoil currently has (cross-org cross-fork-branch submodule trees). Want to break the pattern before recoil-lua-library is followed by similar deps.
- **The shared toolchain layer is load-bearing**, not the codemod capability. The codemods are independently reviewable proposals.
- **`bar-stdlib` (or similar) should be where pure-Lua `common/` content lands**, not recoil-lua-library — that library is types-only today and expanding its scope is a separate negotiation.

### Marek (p2004a)

- **At current dep count (1 library, no bitrot), lx is extremely costly with very little benefit.** The case for lx has to rest on future state, not present.
- **Submodule drift complaints are handwavy.** Single-submodule consumption isn't broken; the doc conflates vendoring drift with submodule complexity.
- **WSL costs aren't acknowledged in the original framing.** A balanced doc needs to name them.
- **MSVC requirement is a Lux issue, not a contributor-cost argument** if BAR will only consume pure-Lua deps.
- **The cross-repo scripting layer is fine; the dispute is only about whether BAR-the-game-repo takes a hard dep.**
- **PowerShell-on-Linux is a real alternative** that would avoid WSL for Windows contributors.

### WatchTheFort

- **Primary objective is shrinking `common/luaUtilities` and `common/`** by moving content to packages. Holds-off on parallel package extraction until the toolchain layer lands; "rip 1 package at a time" after merge.

### Boneless / sprunk (per PR #5902 review)

- **Pushed back on copying third-party code into the repo.** Detailed positions need to be re-read from the review thread before being characterized further; current doc citations are placeholders pending verification.

---

## Appendix: what `just setup::editor` actually does

Skip unless you want the per-tool detail.

**Binaries exported from distrobox to `~/.local/bin`** (so editors find them on PATH):

- `emmylua_ls` — Lua language server
- `emmylua_check` — Rust EmmyLua analyzer (also what CI runs via `bar::check`)
- `clangd` — C/C++ for engine work
- `stylua` — Lua formatter
- `lx` — Lux

**VS Code / Cursor extensions installed (with a y/N prompt):**

- `tangzx.emmylua` — EmmyLua LSP
- `JohnnyMorganz.stylua` — formatter
- `llvm-vs-code-extensions.vscode-clangd` — clangd
- `bmalehorn.test-switcher` — Ctrl+Shift+Y test ↔ source jump

**Removed if present** (conflicts with EmmyLua, duplicate diagnostics, slower):

- `sumneko.lua` (LuaLS) — most common new-contributor trap

**Workspace `.vscode/settings.json` written into BAR:**

- `search.exclude` for `.lux/`, `.devtools/`, `common/luaUtilities/**`
- `[lua]` formatter = stylua, format-on-save
- `test-switcher.rules` — `spec/<area>/<x>_spec.lua ↔ <area>/<x>.lua`, plus the builder-spec convention

**Engine work**: `compile_commands.json` generated for clangd against RecoilEngine if it's cloned.
