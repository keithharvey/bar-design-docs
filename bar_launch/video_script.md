# `just bar::launch` demo — recording script

A follow-along checklist for the screencast. Read it like a teleprompter:
**[NARRATE]** lines are what you say, **[DO]** lines are what you do on
camera, **[EXPECT]** lines are what should appear on screen so you know to
stop the take if something else shows up.

The demo proves four things, in order:
1. A WSL2 contributor with nothing installed can get from `git clone` to a
   running engine in one session.
2. Editor integration is one recipe — Lua autocompletes via `emmylua_ls`,
   C++ autocompletes via `clangd`, both pointed at the dev container.
3. The dev loop is real: edit a Lua widget, save, hot-reload, see the
   change. The sync log proves the bytes actually crossed the WSL/Windows
   boundary.
4. `bar::launch` / `bar::stop` are symmetric and idempotent.

Total runtime target: **12–16 minutes**. Padding is fine; long silences
during container builds are fine — viewers expect them and you'll cut later.

---

## Pre-flight (do **before** hitting record)

### Host (Windows) prep
- [ ] Install **VS Code** on Windows: <https://code.visualstudio.com/>.
      Don't install via WSL — the Windows install ships the `code` CLI that
      Remote-WSL bridges back through.
- [ ] Open VS Code once on Windows, install the **Remote - WSL** extension
      (`ms-vscode-remote.remote-wsl`). Close it again. This makes the first
      `code .` inside the new WSL Just Work; without it, the first `code .`
      sits at "Installing VS Code Server" for ~60s and breaks pacing.
- [ ] `wsl --shutdown` then `wsl --unregister Ubuntu-24.04`, reinstall fresh.
      This is the only way to prove "first-time contributor" and *actually*
      catch missing prerequisites.
- [ ] (Optional) Pre-launch BAR from Steam at least once on this Windows
      install so prerequisites (DirectX runtime etc.) are present. The
      demo's engine never goes through Steam, but a missing system DLL
      will surface at engine launch and you'd rather find it now.

### Recording prep
- [ ] Close every window that isn't (a) a fresh Ubuntu terminal and
      (b) the Windows VS Code you'll open later. No Discord, no
      notifications, no half-eaten Slack.
- [ ] OBS / recording: 1080p, 30fps is enough — don't fight 60fps for a
      mostly-text demo. Mic check: speak the line "BAR-Devtools first-time
      setup, take one" and play it back. If it clips, drop input gain.
- [ ] If you'll show two terminal panes (engine + sync logs in Scene 6),
      decide now whether you'll use Windows Terminal split panes or two
      separate windows side-by-side. Set the layout *before* recording.
- [ ] Two takes minimum. The first one will run into something you forgot.

### Pick the demo files now (don't dither on camera)

These need to actually exist in the BAR repo on the branch you're cloning.
Pin specific file paths in advance so you're not hunting on camera. Pick
files where:
- the Lua one calls a Spring API EmmyLua has stubs for (so hover docs work)
- the C++ one is small enough to scroll without thrashing, but real enough
  that clangd has something to autocomplete

Suggested defaults (verify on your branch before recording):

| Purpose                       | Path                                                                 |
|-------------------------------|----------------------------------------------------------------------|
| Lua widget for EmmyLua hover  | `Beyond-All-Reason/luaui/Widgets/cmd_attack_aoe.lua` (or a small widget you actually wrote) |
| Lua widget for hot-reload     | A widget with a visible side-effect (text overlay, color change). Test it works with `/luaui reload <widget>` before recording. |
| C++ engine file for clangd    | `RecoilEngine/rts/Game/Game.cpp` or any small file under `rts/Sim/` |
| C++ header for clangd hover   | `RecoilEngine/rts/Sim/Units/Unit.h`                                  |

---

## Take 1 — Quickstart from a clean WSL

### Scene 1: open with the problem statement (~30s)

**[NARRATE]** "I just wiped my WSL2 install. I'm going to set up a complete
BAR development environment — engine builds, lobby server, autohost, the
game client, and a working Lua / C++ editor — using one repo and a small
number of `just` recipes. End to end."

**[DO]** Show `wsl -l -v` to prove only the freshly-installed Ubuntu is
there. If anything else lingers, **stop the take.**

**[EXPECT]**
```
  NAME            STATE   VERSION
* Ubuntu-24.04    Running 2
```

### Scene 2: bootstrap `just` (~1m)

**[NARRATE]** "Ubuntu's apt ships `just` 1.21, but this repo uses module
syntax that needs 1.31 or newer. We have a one-script bootstrap that
installs the right version to ~/.local/bin. After this it's all `just`
commands."

**[DO]** Clone the repo first (you need `bootstrap.sh` on disk), then run
the bootstrap:
```
git clone https://github.com/beyond-all-reason/BAR-Devtools.git
cd BAR-Devtools
bash scripts/bootstrap.sh
exec "$SHELL" -l    # or: source ~/.bashrc
just --version
```

**[EXPECT]** `just 1.40.x` (or whatever upstream is at recording time —
**must** be ≥ 1.31).

**[NARRATE PITFALL]** "If you `apt install just` instead of using this
script, you get 1.21 and `just --list` fails with a parse error before
anything runs. Use the bootstrap." *Pause here so the cut is clean.*

### Scene 3: `setup::init` — front-loaded prompts then walk away (~3m, mostly dead air during distrobox build)

**[DO]** `just setup::init`

**[NARRATE while the prompts come up]** "Setup front-loads every
interactive question at the top, then runs unattended. Watch — features,
SSH agent choice, springsettings opt-in, *and* whether to wire up VS Code
integration, all in one batch."

**[EXPECT prompt batch]** Whatever your front-loaded prompts look like — be
specific in narration about what each opt-in does. **If a prompt fires
mid-build instead of at the start, that's a bug. Stop and fix.**

**[DO]** Answer the prompts. Pick:
- All four features (bar, recoil, teiserver, chobby)
- SSH: `op` if you have 1Password running on Windows, otherwise `manual`
- Yes to symlinks
- Yes to wiring up editor integration
- Yes to installing missing VS Code extensions
- Yes to uninstalling sumneko (if asked — fresh WSL probably won't have it)

Then let the recipe run.

**[NARRATE while distrobox builds]** "This is the dev container — it's
where `emmylua_ls`, `emmylua_check`, `clangd`, `stylua`, and `lx` live. We
export them onto the host PATH so VS Code can find them, but they actually
run inside the container. Build is one-time; future setups skip it."
*(Cut this section short in post — viewers don't need to watch a full
container build.)*

**[NARRATE during engine build]** "RecoilEngine builds for Windows
natively — that's why the sync target is on the Windows side. Compiling
takes 5–10 minutes; I'll cut this down in post."

**[EXPECT at end]** `setup::init` exits 0 with a final summary block. The
last thing it should do is run the editor integration step (binary
exports, `compile_commands.json` for clangd, write the workspace
`settings.json`). Read the summary aloud — it's what the user *just got*.

### Scene 4: editor walkthrough — Lua + EmmyLua (~2m)

**[DO]** Open VS Code from inside WSL, pointed at the BAR repo (not the
Devtools repo):
```
cd Beyond-All-Reason
code .
```

**[EXPECT]** VS Code opens on Windows with a green "[WSL: Ubuntu-24.04]"
indicator in the bottom-left status bar. If it says "Installing VS Code
Server" for more than ~30s, your pre-flight Remote-WSL install didn't
take — stop and retry from a known-good state.

**[DO]** Open the Lua demo file (the one you picked in pre-flight, e.g.
`luaui/Widgets/cmd_attack_aoe.lua`).

**[NARRATE]** "EmmyLua is the language server. It reads a `.luarc.json` /
`.emmyrc.json` at the repo root that points at the Spring API type stubs
shipped with the engine. So I get autocomplete and hover docs for the
actual BAR runtime."

**[DO]** Hover over a Spring API call (`Spring.GetUnitDefID`,
`Spring.GetMyTeamID`, `widgetHandler:RegisterGlobal`, etc.). Show the
inline type signature in the hover popup.

**[DO]** Type a partial Spring call (`Spring.GetUni|`) and show the
completion list.

**[NARRATE]** "Stylua is set as the default Lua formatter, but
format-on-save is *not* turned on by default in this template. We
deliberately decoupled formatting from the editor PR so it lands when the
bar-fmt rollout does, not silently here. You can still format on demand."

**[DO]** "Format Document" via Cmd/Ctrl+Shift+I (or right-click → Format
Document). Show either an empty diff or a tiny visible reformat.

### Scene 5: editor walkthrough — C++ + clangd (~2m)

**[DO]** Open the C++ engine demo file you picked
(`RecoilEngine/rts/Game/Game.cpp` or similar).

**[NARRATE]** "Clangd needs `compile_commands.json` to know which flags
to compile each translation unit with. The editor setup recipe ran
`cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON` against RecoilEngine and
symlinked the result into the repo root, so clangd just works."

**[DO]** Hover over a method or class in the file. Show the full
type signature in the hover popup. Right-click → Go to Definition on a
symbol that lives in another file. Show clangd jumping correctly.

**[DO]** Type a partial method call on a known type (e.g., on a `CUnit*`,
type `unit->` and show the autocomplete list).

**[EXPECT]** Hover popups have the C++ type, not "no information
available". If clangd is grinding ("Indexing project... N/M"), let it
finish — first index after a fresh checkout takes a couple minutes.

**[NARRATE PITFALL]** "If clangd shows red squiggles on every line of
every file, `compile_commands.json` didn't make it into the repo root.
Check `RecoilEngine/compile_commands.json` is a symlink to
`build/compile_commands.json`. Re-run `just setup::editor` to regenerate."

### Scene 6: `bar::launch` + the dev loop (~3m)

**[DO]** Switch to terminal. Run `just bar::launch`.

**[NARRATE]** "On WSL2 this kicks off the watchman daemon — it cold-copies
our three live repos into the Windows-side mirror, then watches for
changes via inotify and propagates new bytes through `/mnt/c` at ~100ms
median. Then the engine starts as a native Windows process so we get real
GPU performance instead of WSLg's software path."

**[EXPECT]** Engine window opens on Windows. **Do not skip this.** If the
engine doesn't appear, you do not have a demo.

**[DO]** Click into the menu, start a skirmish vs an AI on a fast map.
Let the game world load (~30s).

**[NARRATE while it runs]** "I haven't installed Beyond All Reason from
Steam. I haven't run the prod launcher. The engine, the games dir, and
the Chobby menu are all running from my live checkouts."

#### The dev loop

**[DO]** Open a second terminal pane (or split horizontally). In the
second pane:
```
just bar::sync-logs
```

**[NARRATE]** "Left pane: my dev shell. Right pane: the sync daemon's log
— I'll watch this so we can see live edits cross the boundary."

**[DO]** Switch back to VS Code. Open the hot-reload-friendly Lua widget
you picked. Make a *visible* change — change a color, an opacity, a label
string, an offset. Save (Cmd/Ctrl+S).

**[EXPECT]** In the sync-logs pane, a line appears within ~100ms naming
the file path. Read it aloud: "There it is — the bytes I just saved are
already on the Windows side."

**[DO]** Switch to the engine window. Open the chat (Enter), type:
```
/luaui reload <widget_name>
```

**[EXPECT]** The visual change you made appears in the running engine.

**[NARRATE]** "Edit, save, reload — three seconds, no rebuild. This is
why the sync architecture matters; with the old SMB-over-WSL setup a
single-file edit could take a full second to traverse. The probe data is
in `bar-design-docs/bar_launch/probes/` if you want the numbers."

### Scene 7: `bar::stop` (~30s)

**[DO]** Switch back to terminal (don't close the engine window — let
`bar::stop` close it). Run `just bar::stop`.

**[EXPECT]**
```
[step]  Stopping BAR processes
[info]    killed: python.exe (PID …, bar_launch)
[info]    killed: spring.exe
[ok]    BAR processes stopped
```

**[NARRATE]** "Symmetric on Linux too — same recipe, same output shape,
matches `spring` only when it's running out of our managed game dir so a
shared dev box is safe."

**[DO]** Run `just bar::stop` *again* immediately.

**[EXPECT]** `[info]  no BAR processes were running` and exit 0.

**[NARRATE]** "Idempotent. Useful before `just engine::build` so the
rsync mirroring new DLLs doesn't hit a Windows file lock."

### Scene 8: close (~30s)

**[NARRATE]** "Recap: fresh WSL, two commands —
`bash scripts/bootstrap.sh` and `just setup::init` — and one
`just bar::launch` to run the engine with both Lua and C++ language
servers wired up. The full PR is on GitHub at [link]. Questions,
comments, suggestions: open an issue, or find me on Discord."

**[DO]** Stop recording.

---

## Things that will probably go wrong on take 1

These are the failure modes I expect — pre-mortem so you can recognize
them fast and either retake or cut.

| Symptom                                                  | Likely cause                                                                                          | Action mid-take                                          |
|-----                                                     |-----                                                                                                  |-----                                                     |
| `just --list` errors on `[confirm("…")]`                 | You re-installed `just` from apt, not the upstream installer / bootstrap.                             | Stop. Re-run `bash scripts/bootstrap.sh`. New take.      |
| `setup::init` asks a Y/n question 90s into a build       | A prompt regressed out of the front-load batch.                                                       | Stop. File the bug. Don't ship the demo with this.       |
| Distrobox build fails on a missing pkg                   | Containerfile drift since last successful build, or upstream package mirror burped.                   | Cut, retry, narrate the retry honestly in v2.            |
| Distrobox build fails fetching emmylua_ls/emmylua_check  | GitHub release-asset download blip or version pinned to a tag that was deleted.                       | Cut. Bump `EMMYLUA_VERSION` in `dev.Containerfile`, retry.|
| `code .` hangs at "Installing VS Code Server"            | Pre-flight Remote-WSL install didn't take in the new WSL.                                             | Stop. Install Remote-WSL on Windows side. New take.      |
| EmmyLua hover shows "no information available"           | `.luarc.json` / `.emmyrc.json` missing or paths wrong; or extension not actually installed.           | Open Output → EmmyLua. Cut, fix, retry.                  |
| clangd shows red squiggles on every line                 | `RecoilEngine/compile_commands.json` symlink missing.                                                 | `just setup::editor` to regenerate. Retry the scene.     |
| clangd hover delayed by 60s+                             | First-time index. Expected; either narrate it or pre-warm by opening VS Code once before recording.   | If pre-warmed and still slow: cut.                       |
| Sync-log pane doesn't show the saved file                | Watchman not started; or daemon died; or path doesn't fall under a watched root.                      | `cat $BAR_DEVSYNC_DIR/.bar-launch/sync.log` — check why. |
| `/luaui reload` does nothing visible                     | Wrong widget name, or your edit doesn't have a visible side-effect.                                   | Pick a different widget; rehearse this off-camera.       |
| `bar::launch` exits but no engine window appears         | Sync daemon didn't finish before launcher fired, or `bar-launch.cmd` shim is stale.                   | `just bar::regen-shim`, retry. If still broken, cut.     |
| `bar::stop` reports "killed" but PID survives            | Process running as different user, or AV is blocking taskkill.                                        | Narrate it as a known caveat; don't pretend it worked.   |

---

## After the take

- [ ] Watch the whole thing back **at 1.5x** before editing. You will catch
      ums, dead air, and one place where you said "the thing" instead of
      naming it.
- [ ] Cut the distrobox build dead air down to ~30s with a "fast-forward"
      caption — viewers don't need to watch 4 minutes of cargo compile.
- [ ] Cut the engine build dead air the same way (5–10 minutes → ~30s).
- [ ] Add a chapter marker at each scene boundary above. Most viewers
      will skip to "Scene 6: bar::launch + the dev loop".
- [ ] Don't add background music. Engineering demos don't need lofi.
- [ ] Upload unlisted first. Send to one reviewer (Norty, or whoever's
      been closest to the launch PR) before publishing.
