## Scene 1 — Open

```
wsl -l -v
```

## Scene 1.5 — Nerd Font + Remote-WSL (PowerShell)

```
winget install --id DEVCOM.JetBrainsMonoNerdFont
code --install-extension ms-vscode-remote.remote-wsl
```

Windows Terminal → Settings → Ubuntu profile → Appearance → Font face → `JetBrainsMono Nerd Font`. Save.

## Starship (in Ubuntu, after bootstrap)

```
curl -sS https://starship.rs/install/sh | sh
echo 'eval "$(starship init bash)"' >> ~/.bashrc
exec "$SHELL" -l
```

## Scene 2 — Bootstrap `just`

```
git clone https://github.com/keithharvey/BAR-Devtools.git
git remote add upstream https://github.com/beyond-all-reason/BAR-Devtools.git
cd BAR-Devtools
bash scripts/bootstrap.sh
exec "$SHELL" -l
just --version
```

## `repos.local.conf` (paste in BEFORE the recorded `just setup::init`)

```
# Per-user overrides of repos.conf (gitignored).

@local_root ~/code
@protocol ssh
bar_debug_launcher   git@github.com:keithharvey/bar_debug_launcher.git cli
RecoilEngine         git@github.com:keithharvey/RecoilEngine.git         fix/archivescanner-empty-pool-roots-crash
```

## Scene 3 — `just setup::init`

```
just setup::init
```

## Scene 4 — Lua + EmmyLua

```
cd Beyond-All-Reason
code .
```

---

## Scene 6 — `bar::launch` + the dev loop

```
just bar::launch
```

Second pane:

```
just bar::sync-logs
```

**Widget edit — magenta banner overlay.** Open
`Beyond-All-Reason/luaui/Widgets/gui_top_bar.lua`. (line 1730)

```lua
	gl.Color(1, 0, 1, 1)
	gl.Rect(0, vsy - 50, vsx, vsy)   -- magenta band across the top
	gl.Color(1, 1, 1, 1)
```

In engine: `Enter` → `/luaui reload gui_top_bar`

**Gadget edit — drop a labeled marker.** Open
`Beyond-All-Reason/luarules/gadgets/gui_display_dps.lua` (unsynced).
Find `function gadget:GameStart()` or `function gadget:Initialize()`,

```lua
local cx, cy, cz = Spring.GetCameraPosition()
Spring.MarkerAddPoint(cx, cy, cz, "HELLO FROM GADGET RELOAD", true)
```

In engine: `Enter` → `/luarules reload gui_display_dps`

## Scene 7 — `bar::stop`

```
just bar::stop
just bar::stop
```
