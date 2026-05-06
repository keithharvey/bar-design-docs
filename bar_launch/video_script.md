
# `just bar::launch` demo — recording script

* Show system settings

* The demo proves four things:

    1. Fresh WSL2 → running engine in one session.

    2. Editor integration

    3. Real dev loop: edit Lua, save, hot-reload, see it.

    4. `bar::launch` / `bar::stop` are symmetric and idempotent.

Target runtime: **12–16 min**. Container/engine builds will be cut later.

---

## Pre-flight (before recording)

- VS Code installed on **Windows** (not via WSL — Windows install ships the `code` CLI Remote-WSL bridges back).
- Remote-WSL extension removed (reinstall live from PowerShell: `code --install-extension ms-vscode-remote.remote-wsl`) — or just rely on `setup::init` to wire it.
- `wsl --shutdown` + `wsl --unregister Ubuntu-24.04` + reinstall fresh — only way to actually catch missing prereqs.
- **BAR installed via the official installer** to `C:\Program Files\Beyond-All-Reason\` and launched once. Two reasons: (a) confirms DirectX/VC++ runtimes are present, (b) `link::all` will drop NTFS junctions into `C:\Program Files\Beyond-All-Reason\data\` pointing back at the dev sync target — that dir has to exist. Co-installed with the per-user dev install we set up later; don't uninstall it.
- **Uninstall the Nerd Font** you installed last take (Settings → Personalization → Fonts → JetBrainsMono Nerd Font → Uninstall). Scene 1.5 demonstrates the install fresh.
- Close everything except a fresh Ubuntu terminal. No Discord, no notifications.
- Open System Settings
- Bind a global hotkey to start recording (CTRTL+f9) and pause recording (CTRL+F10)
- Decide split-pane layout (engine + sync logs) **before** recording.
- Pin the demo files in advance — don't hunt on camera:

| Purpose | Suggested path |
|---|---|
| Lua hover/completion | `Beyond-All-Reason/luaui/Widgets/cmd_attack_aoe.lua` |
| Widget reload demo | `Beyond-All-Reason/luaui/Widgets/gui_top_bar.lua` |
| Gadget reload demo | `Beyond-All-Reason/luarules/gadgets/gui_display_dps.lua` |
| C++ clangd | `RecoilEngine/rts/Game/Game.cpp` |
| C++ header hover | `RecoilEngine/rts/Sim/Units/Unit.h` |

The actual edit snippets to paste live in `recording_clipboard.md`.

---

## Scene 1 — Open (~30s)

```
wsl -l -v
```

- "Wiped WSL. Going to use the new dev tools to set my environment up like I would normally."
- Only the fresh Ubuntu should be listed. If anything else, **stop the take**.

## Scene 1.5 — Nerd Font (~45s)

In a Windows PowerShell pane:

```
winget install --id DEVCOM.JetBrainsMonoNerdFont
```

Windows Terminal → Settings → Ubuntu profile → Appearance → Font face → `JetBrainsMono Nerd Font`. Save.

- Starship and the dev container emit Unicode glyphs (git branch, status icons, lock symbols). Without a Nerd Font they render as tofu boxes.

## Scene 2 — Bootstrap `just` (~1m)

```
git clone https://github.com/keithharvey/BAR-Devtools.git
git remote add upstream https://github.com/beyond-all-reason/BAR-Devtools.git
cd BAR-Devtools
bash scripts/bootstrap.sh
exec "$SHELL" -l
just --version
```
- Ubuntu apt ships `just` 1.21; this repo needs ≥ 1.31 (module syntax).
- One-script bootstrap installs upstream `just` to `~/.local/bin`.
- Pitfall: `apt install just` → `just --list` parse error. Use bootstrap.

## Scene 3 — `just setup::init` (~3m, mostly dead air)

```
just setup::init
```
- Front-loads every interactive question at the top — features, SSH choice, springsettings, editor wiring, extension install — **then runs unattended**.
- During distrobox build: container is the toolchain habitat (emmylua_ls, emmylua_check, clangd, stylua, lx, watchman). Exported to host PATH via `distrobox-export` but actually run inside.
- During engine build: Recoil builds **for Windows natively**, which is why the sync target is Windows-side.
- One UAC prompt during the symlinks step — that's wiring our dev install into BAR's data dir. Click Yes.
- At end: read the summary block aloud — that's the value just delivered.

## Scene 4 — Lua + EmmyLua (~2m)

```
cd Beyond-All-Reason
code .
```
- Status bar should turn green: `[WSL: Ubuntu-24.04]`. >30s "Installing Server" = retake.
- Open the Lua widget. Hover a `Spring.*` call → real type signature.
- Type `Spring.GetUni|` → completion list.
- EmmyLua reads `.emmyrc.json` pointing at the Spring API stubs that ship with the engine.
- Stylua is the default formatter, but **format-on-save is off by default** — decoupled from the editor PR so it lands when bar-fmt rolls out.
- Demo: format-on-demand (Ctrl+Shift+I) → empty diff or tiny reformat.

## Scene 5 — C++ + clangd (~2m)

- Open the C++ demo file. LuaSyncedCtrl.cpp
- Hover a method → full type sig. Go-to-Definition → jumps cross-file. `unit->` → autocomplete.
- Clangd needs `compile_commands.json`; setup::editor ran cmake with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` and symlinked it into the repo root.
- If indexing, let it finish — first run takes a couple minutes.
- Pitfall: red squiggles everywhere = symlink missing → `just setup::editor` regenerates.

## Scene 6 — `bar::launch` + the dev loop (~3m)

```
just bar::launch
```
- WSL2 path: kicks the watchman daemon → cold-copies live repos into the Windows-side mirror, then watches inotify and propagates through `/mnt/c` at ~100ms median.
- Engine starts as a **native Windows process** → real GPU, not WSLg software.
- Engine window must appear. If not, no demo.
- Click into menu, start skirmish vs AI on a fast map.
- Talking point: no Steam install, no prod launcher — engine, games dir, Chobby all from live checkouts.

Second pane:
```
just bar::sync-logs
```
- Left = dev shell, right = sync log.
- **Widget edit:** in `gui_top_bar.lua`, inject the magenta banner snippet at the top of `widget:DrawScreen()` (line 1730). Snippet in `recording_clipboard.md`. Save.
- Sync-log line appears with a latency suffix: `mirrored luaui/Widgets/gui_top_bar.lua (87ms)`. Read it: "edit-to-Windows in 87 milliseconds — that's the architecture earning its keep." The 100ms floor is the coalesce window; below that is just the rsync delta.
- In engine: `Enter` → `/luaui reload gui_top_bar` → magenta band across the top.
- **Gadget edit:** in `gui_display_dps.lua`, add the `Spring.MarkerAddPoint(...)` snippet (clipboard). Save → another `mirrored ... (Nms)` log line → `/luarules reload gui_display_dps` → labeled marker drops at camera position, visible in 3D and on the minimap.
- "Edit, save, reload — sub-second sync, manual reload, no rebuild. Old SMB-over-WSL setup took ~1s per file. Probe data in `bar-design-docs/bar_launch/probes/`."

## Scene 7 — `bar::stop` (~30s)

```
just bar::stop
just bar::stop
```
- First run kills python (bar_launch) + spring.exe.
- Symmetric on Linux — same recipe, same shape.
- Scoped: only matches `spring` running out of our managed game dir → safe on shared boxes.
- Second run: `no BAR processes were running`, exit 0. Idempotent.
- Useful before `just engine::build` so the DLL rsync doesn't hit a Windows file lock.

## Scene 8 — Close (~30s)

- Recap: fresh WSL → `bootstrap.sh` → `setup::init` → `bar::launch`. Lua + C++ both wired.
- Link to the PR. Questions: issue or Discord.

---

## Failure modes (recognize fast, decide retake vs cut)

| Symptom | Likely cause | Action |
|---|---|---|
| `just --list` parse error | Used `apt install just` | Re-run bootstrap, new take |
| Prompt fires mid-build | Front-load regression | Stop, file bug |
| Distrobox build fails on a pkg | Containerfile drift / mirror burp | Cut, retry, narrate honestly |
| Distrobox emmylua download fails | Release-asset blip / deleted tag | Bump `EMMYLUA_VERSION`, retry |
| `code .` hangs at "Installing Server" | Remote-WSL pre-flight didn't take | New take |
| EmmyLua "no information available" | `.emmyrc.json` paths wrong or ext not installed | Output → EmmyLua, fix, retry |
| Clangd red squiggles everywhere | `compile_commands.json` symlink missing | `just setup::editor` |
| Clangd 60s+ hover delay | First-time index | Pre-warm before recording |
| Sync-log doesn't show saved file | Watchman not started / daemon died / path not watched | `cat $BAR_DEVSYNC_DIR/.bar-launch/sync.log` |
| UAC prompt times out / cancelled during setup::init | Distracted, missed the dialog | Re-run `just link::all` to retry the symlink step alone |
| First `bar::launch` does a 60-90s "cold copy" | Expected — it's the watchman clock seed | Subsequent launches go through the incremental branch (sub-second) |
| `/luaui reload` does nothing visible | Wrong widget name or non-visible edit | Different widget; rehearse |
| `bar::launch` exits, no engine window | Sync didn't finish or shim is stale | `just bar::regen-shim`, retry |
| `bar::stop` "killed" but PID survives | Different user / AV | Narrate as known caveat |

---

## After the take

- Watch back at 1.5x before editing — catches ums + "the thing".
- Cut distrobox build to ~30s with fast-forward caption.
- Cut engine build the same.
- Chapter markers at each scene boundary (most viewers jump to Scene 6).
- No background music.
- Upload unlisted first; send to one reviewer before publishing.
