@Watch @Boneless

Four things:

## 1. Editor plugin install — resolved

Watch raised whether `setup::editor` should force-install plugins without asking. Agreed — wrong tooling = unusable language server. Current solution: `setup::init` now includes editor setup as a step. It previews what it'll install/remove and asks once (y/N). If `code` isn't on PATH it skips gracefully (WSL instructions cover this). Open to making it more aggressive — or rolling it into a single "here's what we're about to do to your system" y/N for the entire `setup::init`.

## 2. Windows testing — need your help

I added first-draft Windows/WSL instructions to the [BAR-Devtools README](https://github.com/keithharvey/BAR-Devtools/blob/9235234f5babc46bf41da3f25ceff2f0da860d14/README.md) PR and gutted the [BAR README](https://github.com/keithharvey/bar/blob/dcc143b60cb1c2359b27d4f722450bfce38090f4/README.md) down to just a link to Devtools (kept only the Dev Lobby `.sdd` launch instructions — Devtools shouldn't own that). Please sanity-check my Windows instructions

Still needed:
- `just link::create` needs to handle Windows paths (symlinks in Program Files)
- Verify `setup::init` works end-to-end in WSL2

## 3. Stacked PRs — @Watch I need you to run one command

I set up GitHub stacked PRs so each layer is reviewable in isolation. Right now all PRs target `master` and show the cumulative diff of every layer below them — not great for review. Stacked PRs fix this: each PR shows only its own diff.

**@Watch** — once you've reviewed the changes and are confident the diffs are just formatting + the Spring split transforms (`Spring` → `SpringSynced`/`SpringUnsynced`/`SpringShared`), please push three branches to origin so I can retarget the PRs. Once we're confident a given file's diff is purely transform conflicts (formatting, renames, Spring split), contributors can safely resolve with `--theirs`:
```bash
git remote add keithharvey https://github.com/keithharvey/bar.git   # if not already
git fetch keithharvey fmt mig fmt-llm-source
git branch fmt keithharvey/fmt
git branch mig keithharvey/mig
git branch fmt-llm-source keithharvey/fmt-llm-source
git push origin fmt mig fmt-llm-source
```
My script handles the retargeting automatically after that. GitHub won't let me do this from a fork.

The stack:
- **`fmt`** → `master` — StyLua formatting only. Ready now.
- **`mig`** → `fmt` — all automated transforms (spring-split, i18n-kikito, bracket-to-dot, rename-aliases, etc.)
- **`fmt-llm-source`** → `mig` — human-curated env layer (`.emmyrc.json`, `types/*` stubs, type ignores, CI gate)
- **`fmt-llm`** → `fmt-llm-source` — LLM type-fix pass + blame-ignore-revs

When `fmt` merges, GitHub auto-retargets `mig` to `master`, and so on down.

## 4. Two announcements

Splitting this into two because `just bar::fmt-mig` (the migration command) will reformat the entire codebase if run before the formatting PR lands on master. We need to give people a heads-up first, then give them the migration instructions once it's safe to run. 

### Announcement 1 — post once Windows is confirmed working

This one needs a firm merge date. Without a deadline people will ignore the setup instructions and then panic when master changes under them. The date gives them a concrete window to get BAR-Devtools working before it matters.

---

# Heads up: auto-formatting + type checking landing on master Wednesday, April 23rd

We're rolling out auto-formatting, linting, and type checking for the BAR Lua codebase via [BAR-Devtools](https://github.com/beyond-all-reason/BAR-Devtools/pull/17). This will land on `master` in stages starting **Wednesday, April 23rd**.

**What's happening:**
- `stylua` auto-formatting merges first (large diff, but purely whitespace/style — no logic changes)
- Automated transforms (API renames, Spring split) follow
- Type errors will eventually block PRs via a CI gate

**What you need to do before April 23rd:**
1. **Clone [BAR-Devtools](https://github.com/beyond-all-reason/BAR-Devtools) and run `just setup::init`.** This sets up the formatter, type checker, linter, editor integration, and git hooks.
2. **Run `just bar::units`** and confirm tests pass on your machine.
3. **Do not run `just bar::fmt` on your branches yet** — stylua will reformat the entire codebase if master hasn't been formatted first. Migration instructions come with the merge.

**What you get from `setup::init`:**
- Format-on-save and pre-commit hooks configured automatically
- `just bar::test` — unit + integration tests
- `just bar::lint` — luacheck
- `just bar::fmt` — StyLua (also runs on pre-commit)
- `just bar::check` — EmmyLua type checking

Full docs: [BAR-Devtools README](https://github.com/beyond-all-reason/BAR-Devtools#readme)

---

### Announcement 2 — post after the PRs merge into master

---

# Developer Tooling Update — `master` has been reformatted

The formatting + transform PRs have landed. Everything runs through [**BAR-Devtools**](https://github.com/beyond-all-reason/BAR-Devtools).

### You must

1. **Clone [BAR-Devtools](https://github.com/beyond-all-reason/BAR-Devtools) and run `just setup::init`.**
   This installs the formatter, type checker, linter, editor integration, and git hooks. One command.

2. **Update your open branches:**
   ```bash
   just bar::fmt-mig                       # transform your branch first
   git commit -am "apply code transforms"  # squashed away when PR merges
   git merge origin/master                 # conflicts are now real conflicts only
   ```

### Going forward

- **EmmyLua type errors will block PRs.** If you see red underlines in your editor, fix them before opening a PR.
- **Use `SpringSynced`, `SpringUnsynced`, or `SpringShared` instead of `Spring`** for engine API calls. Check which context your code runs in — synced (sim), unsynced (UI), or shared (both).

Full docs: [BAR-Devtools README](https://github.com/beyond-all-reason/BAR-Devtools#readme)
