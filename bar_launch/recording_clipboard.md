## Scene 1 — Open

```pwsh
code --install-extension ms-vscode-remote.remote-wsl

winget install --id DEVCOM.JetBrainsMonoNerdFont

Get-ComputerInfo

@"
[wsl2]
memory=8GB
processors=4                                                                                                       
swap=12GB                
"@ | Set-Content $env:USERPROFILE\.wslconfig; wsl --shutdown

wsl -l -v
wsl --install -d Ubuntu-24.04
```
**Set Ubuntu to be the default and set the font**

**Start a new terminal**

### Starship (in Ubuntu, after bootstrap)


In Ubuntu:
```sh
curl -sS https://starship.rs/install.sh | sh
echo 'eval "$(starship init bash)"' >> ~/.bashrc && exec bash
echo 'eval "$(starship init bash)"' >> ~/.bashrc
exec "$SHELL" -l
```

## Scene 2 — Bootstrap `just`

```sh
mkdir code
cd code
git clone https://github.com/keithharvey/BAR-Devtools.git
cd BAR-Devtools
git remote add upstream git@github.com:beyond-all-reason/BAR-Devtools.git

cat > repos.local.conf <<'EOF'
@local_root ~/code
@protocol ssh

bar_debug_launcher   git@github.com:keithharvey/bar_debug_launcher.git  cli
RecoilEngine         git@github.com:keithharvey/RecoilEngine.git         fix/archivescanner-empty-pool-roots-crash
EOF

git checkout launch
bash scripts/bootstrap.sh
exec "$SHELL" -l
just --version
```

## `repos.local.conf` (paste in BEFORE the recorded `just setup::init`)

## Scene 3 — `just setup::init`

```sh
just setup::init
```

## Scene 4 — `bar::launch`

```sh
just bar::launch
```

Second pane:

```sh
just bar::sync-logs
```
## Scene 5 — Lua + EmmyLua

```sh
cd Beyond-All-Reason
code .
```

## Scene 6 - the dev loop
---

**Widget edit — magenta banner overlay.** Open
`Beyond-All-Reason/luaui/Widgets/gui_top_bar.lua`. (line 1730)

```lua
	gl.Color(1, 0, 1, 1)
	gl.Rect(0, vsy - 50, vsx, vsy)   -- magenta band across the top
	gl.Color(1, 1, 1, 1)
```

In game: `Enter` → `/luaui reload gui_top_bar`

**Gadget edit — drop a labeled marker.** Open
`Beyond-All-Reason/luarules/gadgets/gui_display_dps.lua` (unsynced).
Find `function gadget:GameStart()` or `function gadget:Initialize()`,

```lua
local cx, cy, cz = Spring.GetCameraPosition()
Spring.MarkerAddPoint(cx, cy, cz, "HELLO FROM GADGET RELOAD", true)
```

In game: `Enter` → `/luarules reload gui_display_dps`

## Scene 7 — `bar::stop`

```sh
just bar::stop
just bar::stop
```

## Scene 8 - Nice to haves

### Claude code and git config
```sh
curl -fsSL https://claude.ai/install.sh | bash

git config --global user.email "keithdanielharvey@gmail.com"
git config --global user.name "Daniel Harvey"
```