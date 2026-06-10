Hey man, here is my "cheat sheet" from the video, that should get you started:

## Scene 1 — Open

```pwsh
code --install-extension ms-vscode-remote.remote-wsl

winget install --id DEVCOM.JetBrainsMonoNerdFont

Get-ComputerInfo

# modify this to fit your computer, you want ~5-6Gb for Windows
@"
[wsl2]
memory=12GB
swap=8GB
processors=4
"@ | Set-Content $env:USERPROFILE\.wslconfig;

wsl -l -v
wsl --install -d Ubuntu-24.04
```
**Set Ubuntu to be the default terminal and set the font under your profile**
**Start a new terminal**

### Starship

```sh
curl -sS https://starship.rs/install.sh | sh
echo 'eval "$(starship init bash)"' >> ~/.bashrc && exec bash

mkdir -p ~/.config && cat > ~/.config/starship.toml <<'EOF'
right_format = '$time'

[time]
disabled = false
format = '[$time]($style)'
time_format = '%T'
style = 'bold yellow'
EOF

exec "$SHELL" -l
```

## Scene 2 — Bootstrap `just`

```sh
mkdir code
cd code
git clone https://github.com/keithharvey/BAR-Devtools.git
cd BAR-Devtools

git fetch origin
git checkout launch
git remote remove origin
git remote add origin git@github.com:keithharvey/BAR-Devtools.git

cat > repos.local.conf <<'EOF'
@local_root ~/code
@protocol ssh
bar_debug_launcher   git@github.com:keithharvey/bar_debug_launcher.git  cli
RecoilEngine         git@github.com:keithharvey/RecoilEngine.git        fix/archivescanner-empty-pool-roots-crash
Beyond-All-Reason    git@github.com:keithharvey/bar.git                 fix/lux-29-deps
EOF

bash scripts/bootstrap.sh
source ~/.bashrc
just --version
```


## Scene 3 — `just setup::init`

```sh
just setup::init
```

## Scene 5 — Lua + EmmyLua + clangd

```sh
cd ~/code
code RecoilEngine/ Beyond-All-Reason/ BAR-Devtools/
```

Open "gui_top_bar.lua", show Problems/EmmyLua working
Open "LuaSyncedCtrl.cpp"
Open `Beyond-All-Reason/luarules/gadgets/gui_display_dps.lua` (unsynced).

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
```

## Scene 8 - Nice to haves

### Claude code and git config
```sh
git config --global user.email "keithdanielharvey@gmail.com"
git config --global user.name "Daniel Harvey"
curl -fsSL https://claude.ai/install.sh | bash
```