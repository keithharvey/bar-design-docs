@Marek -- the breakdown I promised.

## What's load-bearing vs what's a proposal

You said you suspect my implementation looks the way it does because I have goals beyond linting/typechecking, and the org isn't aligned on those. Fair concern, let me decouple it explicitly:

* **The shared scripting layer is load-bearing.** Stylua/EmmyLua/lx running consistently across hosts, and codemod-based migrations, both require the same thing. That's the only commitment I'm asking the org to actually make here.
* **The codemod capability is a tool, not a commitment.** Having `bar-lua-codemod` available doesn't obligate the org to *use* it for anything specific. The migration PRs in [#7408](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/7408) (spring-split, bracket-to-dot, rename-aliases, etc.) are *proposals* -- intentionally split into isolated PRs so each one is independently reviewable and rejectable. If the org doesn't want a given transform, we don't merge it. The capability stays; the application is per-PR.

## The DX rubric

This is the shape I'd expect. Status quo vs this change:

| Deliverable | Status quo | Proposed |
|---|---|---|
| One-command setup | 🔴 Windows wiki, different per repo, silent WSL/msys2 choice | 🟢 `just setup::init` |
| Windows install cost for forced deps | 🔴 unsigned exe + PATH + **VS + C++ workload + x64 MSVC toolset** just for `lx` ([docs](https://lux.lumen-labs.org/tutorial/getting-started/#windows)) | 🟢 runs inside distrobox/WSL, contributor never sees MSVC |
| Reproducible toolchain | 🔴 whatever stylua/LLS each person installed | 🟢 pinned, matches CI |
| Cross-repo ops | 🔴 manual; recoil-lua-library as a git submodule, recoil itself as submodules-across-orgs-across-branches-of-a-fork | 🟢 `just lua::library`, shared pipeline |
| Branch catch-up | 🔴 doesn't exist | 🟢 `just bar::fmt-mig` -- only exists *because* there's a shared layer |
| IDE integration | 🟡 works if you know the plugins (Sumneko trap) | 🟢 `just setup::editor` copies settings |
| Local CI parity | 🔴 different versions, missing steps | 🟢 same binaries, same configs |
| Package management | 🔴 copies rot; org already said no to copying in ([#5902](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5902#pullrequestreview-3380058963)) | 🟢 `lx install` + lockfile |
| Bumpers for new devs | 🔴 skill gap widens as tooling matures | 🟢 scripts encapsulate toolchain |

Your "90% pay for the 10%" concern inverts without the shared layer: each of the 90% pays the setup cost individually. The shared layer is how they stop paying it.

## Package list you asked for

Two:

* `kikito/i18n.lua`
* `recoil-lua-library` -- currently consumed via git submodule. Recoil itself already shows where that strategy leads at scale: submodules across the BAR org boundary tracking divergent branches of a fork. Lux is the clean exit before recoil-lua-library ends up in the same spot.

No grand expansion beyond those. Any future dep goes through normal review.

On recoil: the direction I'd go is move recoil-lua-library toward standard Lua conventions, not bend Lux to recoil's. There's [pressure](https://github.com/lumen-oss/lux/issues/953) to upstream "exception" PRs carving out its non-`src/` layout -- that's backwards. Adopt the standard `src/` layout, publish recoil-lua-library as a standard lua rock, consume it from BAR via `lx install` like any other dep, delete the submodule, stop being the org that needs special-cased package-manager features.

## Why Lux at all (instead of no package manager)

The vendoring counter is "just store the source in a folder and update it manually" -- but that's not a free alternative. Concretely:

* **A vendor-update flow is a package manager you write yourself.** Detect new upstream versions, pull, diff, patch local modifications, run tests, commit. Either we maintain that script on every host (back to the shared-layer problem) or each contributor does it by hand (back to the skill-gap problem).
* **It doesn't generalize past one library, and we've watched the pattern decay in this org.** I'm not saying vendoring doesn't work in the abstract -- I'm saying in this org it has produced entropy, and has. Concretely:
    * **kikito-i18n was vendored in BAR.** Copied in, drifted from upstream, started accepting contributions *not present in upstream* via direct commits to BAR. The "manual update workflow" turned into an accidental fork. We already tried this.
    * **Recoil itself shows where the submodule variant of the same pattern leads.** Recoil pulls submodules across an org boundary, on two different branches of a fork, for code it clearly owns (thinking of CurcuitAI here). The question isn't "does Recoil's setup work for them today," it's "do we want BAR to keep doubling down on the same pattern that produced that?"
    * **recoil-lua-library is currently a git submodule in BAR.** Same pattern, earlier in its lifecycle. Simplest form: one repo, one published version, one consumer-side `lx install`. Get out before it accretes the same complexity.
    * Vendoring is also consume-only -- it doesn't address the publish side that recoil-lua-library needs at all.
* **No lockfile, no transitive resolution, no standard ecosystem entry point.** When something breaks on a contributor's machine, "did you re-run `lx install`?" is one diagnostic. "Did you copy the right version of the right files?" is N.
* **The org has already pushed back on copying third-party code in.** [PR #5902 review](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5902#pullrequestreview-3380058963) -- @Watch The Fort (Quality Lead), @[BONELESS], @sprunk all weighed in. Reopening that's possible but worth flagging the standing position.

Cost of the alternative: `lx install` once per contributor (hidden behind `setup::init`) plus one lockfile entry per dep. We don't write or maintain a homemade updater.

## Why a shared layer (assuming we keep Lux)

If vendoring's off the table, the next question is whether we can require Lux without requiring the shared scripting layer -- i.e. just have contributors install `lx` themselves. Per [Lux install docs](https://lux.lumen-labs.org/tutorial/getting-started/#windows), a Windows contributor's real steps are:

1. Download unsigned `lx_*.msi` from GitHub releases, dismiss "Windows protected your PC"
2. Run installer
3. Manually add to PATH
4. **Install Visual Studio (or VS Build Tools) with the C++ workload; enable an x64 hosted MSVC toolset**
5. `lx help` to verify
6. *Then* `lx install`

That's a Visual Studio Code install for someone who wanted to fix a widget. `just setup::init` does the whole thing inside WSL/distrobox and the contributor never sees MSVC. On Linux it's `cargo binstall lx` and done, but as you pointed out, the BAR base is majority Windows.

Re your fallback of "powershell script you can double-click" -- that *is* a shared scripting layer, just in a worse environment. We'd write every recipe twice (powershell + bash), debug all of them, and reinvent things like `just`, `lx`, and distrobox manually because none of that ecosystem lives natively on powershell. Linux-via-WSL/distrobox lets us write once, run on every host, and lean on the existing tooling instead of reimplementing it. The cost of that is "WSL is installed" -- a first-class Microsoft-supported Windows feature.

## What the script actually does

So the layer isn't a black box. `just setup::editor` (one of the steps in `setup::init`) does specifically this:

**Binaries exported from distrobox to `~/.local/bin`** (so editors find them on PATH):

* `emmylua_ls` -- Lua language server
* `emmylua_check` -- Rust EmmyLua analyzer (also what CI runs via `bar::check`)
* `clangd` -- C/C++ for engine work
* `stylua` -- Lua formatter
* `lx` -- Lux

**VS Code / Cursor extensions installed (with a y/N prompt before applying)**:

* [tangzx.emmylua](https://marketplace.visualstudio.com/items?itemName=tangzx.emmylua) -- EmmyLua LSP
* [JohnnyMorganz.stylua](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.stylua) -- formatter
* [llvm-vs-code-extensions.vscode-clangd](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.vscode-clangd) -- clangd
* [bmalehorn.test-switcher](https://marketplace.visualstudio.com/items?itemName=bmalehorn.test-switcher) -- Ctrl+Shift+Y to jump test ↔ source

**Removed if present** (conflicts with EmmyLua, duplicate diagnostics, slower):

* `sumneko.lua` (LuaLS) -- this is the trap I see new contributors fall into constantly

**Workspace `.vscode/settings.json` written into BAR**:

* `search.exclude` for `.lux/`, `.devtools/`, `common/luaUtilities/**` (the test-switcher, type noise removal from "Problems" for what are essentially vendored lua utilities + lux internals)
* `[lua]` formatter = stylua, format-on-save
* `test-switcher.rules` -- maps `spec/<area>/<x>_spec.lua ↔ <area>/<x>.lua`, plus the builder-spec convention

**Engine work**: `compile_commands.json` generated for clangd against RecoilEngine if it's cloned.

That's the bumper. Without the script, every contributor wires that by hand, gets the Sumneko/EmmyLua choice wrong, doesn't know about test-switcher, and so on.

## What gets enforced where

Agree: enforcement lives in CI.

**CI gates** (these can fail your PR):

* EmmyLua, locally `bar::check-errors` -- resolved by fixing your own type errors
* luacheck, locally `bar::lint` -- noise gets cleared by running stylua first

**Host-side scripts** (productivity, *not* enforcement -- here so contributors avoid the CI failures above and don't grind through manual cross-repo work):

* `bar::fmt-mig` -- catch up open branches across the codebase transforms
* `lua::library` -- recoil→bar pipeline, lets you iterate on API changes live locally
* `setup::init` -- one-command onboarding instead of per-host setup

"BAR-Devtools required" isn't a new burden on top of the existing toolchain -- it replaces N individual host installs with one shared one.

## Open

* Given the Windows install path and the #5902 prior pushback on copying code in, does any of this change what you're asking for? Happy to keep digging.
* Want to do a screen-share where I run this end to end on a fresh setup and talk through the decisions made and why?
* If BAR-Devtools-the-repo is the real sticking point (vs the shared-scripting-layer idea), we can move the recipes into BAR itself. Same layer, different home. I'm kind of conflicted on this one, because I think packaging these in just recipes gives us dependencies, and splitting that scripting layer up and distributing it would have some real downsides in factoring. Totally doable though, but are also forgoing the 1-host simplification and maintaining powershell scripts there too now?

## Update: on `common/` packaging

After posting, it surfaced that what Marek may actually be after is going after `common/luaUtilities/` and packaging up the rest of `common/`. My response, then attean's call:

> Marek, I think maybe you're looking for something I haven't done yet: go after `common/luaUtilities` and `common/` packages. That should probably happen but I was more putting the tools in place to allow that to happen, I hadn't taken that on yet. I'll take a look at that now and see, but I do think that rests behind the same toolchain discussion.

> **attean (Contributors):** I think we're going to hold off on that, we should rip 1 package at a time out after this lands.

So: out of scope for this PR stack, in scope for follow-up work once the toolchain layer is merged. The shared scripting layer is exactly the thing that makes "rip 1 package at a time" cheap to do.
