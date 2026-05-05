## Scene 1.5 — Nerd Font

```
winget install --id DEVCOM.JetBrainsMonoNerdFont
```

Windows Terminal → Settings → Ubuntu profile → Appearance → Font face → `JetBrainsMono Nerd Font`. Save.

Verify in Ubuntu: `echo -e "    "` shows solid glyphs, not tofu boxes.

## `repos.local.conf` (paste in BEFORE the recorded `just setup::init`)

```
# Per-user overrides of repos.conf (gitignored).

@local_root ~/code
@protocol ssh
bar_debug_launcher   git@github.com:keithharvey/bar_debug_launcher.git cli
RecoilEngine         git@github.com:keithharvey/RecoilEngine.git         fix/archivescanner-empty-pool-roots-crash
```

---

## Scene 6 — paste-able demo edits

**Widget edit — magenta banner overlay.** Open
`Beyond-All-Reason/luaui/Widgets/gui_top_bar.lua`. (line 1730)

```lua
	gl.Color(1, 0, 1, 1)
	gl.Rect(0, vsy - 50, vsx, vsy)   -- magenta band across the top
	gl.Color(1, 1, 1, 1)
```

**Gadget edit — drop a labeled marker.** Open
`Beyond-All-Reason/luarules/gadgets/gui_display_dps.lua` (unsynced).
Find `function gadget:GameStart()` or `function gadget:Initialize()`,

```lua
local cx, cy, cz = Spring.GetCameraPosition()
Spring.MarkerAddPoint(cx, cy, cz, "HELLO FROM GADGET RELOAD", true)
```

---

## Visuals to flash on screen while narrating

Open these in a side window (or as overlay PNGs in OBS) and switch to them
when the matching scene is hitting dead air. Each one is small enough to
read at 1080p without zooming.

### Scene 3 — `setup::init` step map

Use this while distrobox / engine builds are chugging.

```
┌────────────────────── just setup::init ──────────────────────┐
│ 0/8  Front-loaded prompts  (features, SSH, editor, sumneko) │
│ 1/8  System packages       (apt: distrobox, podman, …)      │
│ 2/8  Distrobox image       (dev.Containerfile build)        │
│ 3/8  Distrobox container   (bar-dev created + entered)      │
│ 4/8  Repo clones           (bar, recoil, teiserver, chobby) │
│ 5/8  Symlinks              (Devtools <-> BAR data dir)      │
│ 6/8  Engine build          (docker-build-v2, Windows tgt)   │
│ 7/8  bar-launch venv       (+ WSL sync deps + watchman)     │
│ 8/8  Editor integration    (binaries + compile_commands)    │
│      SSH setup             (1Password / manual / skip)      │
└──────────────────────────────────────────────────────────────┘
```

### Scene 4–5 — Editor integration topology

Use while VS Code opens / clangd indexes.

```
   Windows VS Code  ──Remote-WSL──▶  WSL2 (host PATH)
                                        │
                                        ▼
                         ~/.local/bin/{emmylua_ls,
                          emmylua_check, clangd, stylua, lx}
                                        │
                                  distrobox-export
                                        ▼
                          ┌─── bar-dev container ───┐
                          │  toolchain RPMs/binaries│
                          └─────────────────────────┘
                                        ▲
                                        │
                            .emmyrc.json points at
                          Spring API stubs (in repo)
                                  +
                       compile_commands.json symlink
                          (RecoilEngine build dir)
```

### Scene 6 — WSL2 ↔ Windows sync architecture

The big one. Flash this while reading the sync-log line aloud.

```
   WSL2 (Linux ext4)                       Windows (NTFS)
 ┌──────────────────────┐               ┌───────────────────────┐
 │ ~/code/BAR-Devtools/ │               │ %LOCALAPPDATA%/       │
 │  ├─ Beyond-All-      │               │  Beyond-All-Reason/   │
 │  │   Reason/         │   watchman    │   data/               │
 │  ├─ BYAR-Chobby/     │ ─since clock▶ │   ├─ games/*.sdd      │
 │  └─ RecoilEngine/    │  + rsync      │   └─ engine/          │
 │      build/install/  │  --inplace    │       local-build/    │
 └──────────┬───────────┘               └─────────┬─────────────┘
            │                                     │
       inotify (native)                  spring.exe (native Win)
                                                  │
                                                  ▼
                                           GPU / DirectX
```

Talking points:
- Source of truth lives on **Linux ext4** (fast inotify, fast git).
- Engine reads from **Windows NTFS** (native Win process, real GPU).
- Watchman provides "what changed since clock T" → rsync `--inplace`
  ships only deltas → ~100ms median per save.
- `--inplace` preserves the engine's mmap inode contract (Lua sources
  the engine has mmap'd don't change inode under it).

### Scene 6 — Dev-loop timing

```
  edit + Ctrl-S  ──▶  inotify  ──▶  rsync delta  ──▶  Windows file
       0ms              <10ms           ~50ms              ~80ms
                                                              │
                                          /luaui reload <w>   ▼
                                            (manual, ~1s)   engine
                                                            sees it
```

### Scene 7 — `bar::stop` scope

Reassures the "is this safe on a shared box?" question.

```
       just bar::stop
              │
              ▼
   match by /proc/<pid>/exe ─── only kills if the binary lives under
                                  the managed game dir
              │
   ┌──────────┼──────────┐
   ▼          ▼          ▼
 python    spring.exe  BAR launcher
 (bar_     (engine)    (.exe)
  launch)
```

---

## Production notes for the visuals

- Render each block to its own PNG (monospace font, dark bg, ~800×400) and
  load them as OBS sources you can hotkey-toggle.
- Or: keep this file open at 200% zoom on a second monitor and use OBS's
  window-capture as a picture-in-picture for the relevant 20s.
- Don't leave a diagram up for more than ~30s — viewers stop reading.
