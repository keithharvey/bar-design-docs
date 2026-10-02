# Terraform Brush (devtools setup)

The end-user zip (`run-terraform-brush.bat` + a bundled engine + assets) exists because
campaign creators have no build environment. Out of BAR-Devtools nothing is copied:
the engine is a build, and everything game-side rides in the BAR checkout.

| Zip payload | Devtools equivalent |
| --- | --- |
| `data\engine\recoil-terraform-test\` | `just engine::build` + `just link::create engine` (`engine/local-build`) |
| terraform suite / Map Project widgets | already in `Beyond-All-Reason/luaui/`, linked as `Beyond-All-Reason.sdd` |
| `run-terraform-brush.bat` | `just bar::launch` |
| DNTS splat sets, SkyBoxes, tileset widget + layer textures | the BAR PR — same checkout, nothing installed by hand |

Everything below assumes `just setup::init` has run with the `bar` and `recoil` features.
`just doctor` first if anything looks off.

## 1. Custom engine

Everything the zip's engine carried is merged to upstream master (#3086 blank-map DNTS,
#3088 InitBlank skybox, #3127 `Spring.SetMapShader`) — it just isn't in a released engine
yet. So: build master, no fork, no branch pin.

```bash
just repos::clone recoil
just bar::stop                 # engine::build refuses while local-build is running
just engine::build linux       # `windows` on WSL2
just link::create engine       # -> <data>/engine/local-build
just link::status              # confirm
```

`bar::launch` injects `--engine local-build` whenever that symlink exists, so there is no
per-run flag and no `.bat`. Nothing else in `<data>/engine/` is touched — the published
`recoil_*` versions stay intact for normal play. Once a release contains #3086, this whole
section reduces to "use the released engine".

## 2. Game-side tools and assets

One BAR PR carries all of it: the suite already merged
(`luaui/Widgets/cmd_terraform_brush*.lua`, `cmd_terraform_suite.lua`, `cmd_map_project.lua`,
`cmd_splat_painter.lua`, `luaui/RmlWidgets/gui_terraform_brush/`) plus, from the zip, the
DNTS splat-set library + catalog, the SkyBoxes library, and the tileset prototype widget
with its layer textures. Until that PR merges, it's a published branch:

```
# repos.local.conf
Beyond-All-Reason   git@github.com:<author>/Beyond-All-Reason   <branch>
```

```bash
just repos::sync --force       # onto the branch
just link::create bar chobby   # <data>/games/*.sdd
just bar::dev-mode             # Chobby channel -> byar-dev so the local .sdd loads
```

Widget and asset edits are live on the next `/luaui reload` — nothing installed into the
data dir, nothing to drift out of sync.

The only remaining copied payload is the optional ~4.4 GB Poly Haven diffuse-painter
library — too big for git, extract it into `<data>/Terraform Brush/` and the Diffuse
painter picks it up automatically.

## 3. Running

```bash
just bar::launch                                              # GUI, chobby
just bar::launch --no-gui --play bar --source local --map "Quicksilver"
```

Engine-direct (`--play bar`) needs a real `--map` or it silently no-ops. Then in game:

1. Settings > Widgets — enable the terraformer suite widgets and Map Project.
2. `FILE > New Map` for a blank map; the Splat Set picker reads the DNTS library.
3. `FILE > Save Project` writes the editable state to `<data>/MapProjects/<name>/`.
4. `FILE > Open Project` restarts into a blank map of the saved size and replays it back.
   If a load stalls, `/luaui reload` resumes from the last completed phase.

`just bar::log` tails the infolog when a phase misbehaves.

### Tileset terrain prototype (optional)

Enable "Tileset Terrain Prototype" in Settings > Widgets, or `/tileset` for its panel. It
shades terrain with the placeholder layer set (sand flats, gravel, cliff walls, plateau tops)
plus a chunky cliff normal and stagger mask. All knobs are live sliders. It requires
`local-build`; it will not work on a published engine.

## 4. Licenses — IMPORTANT

These are PLACEHOLDER assets for prototyping only; final distributed maps use proper artist
tilesets.

- Tileset layer textures (diff/nor/arm): CC0 from Poly Haven — see `tileset_dev/SOURCES.md`.
- `quarry_cliff_chunky_nor_gl_2k.png` (MrBob's chunky normal) is textures.com-derived and
  NOT redistributable — it cannot enter the repo. The PR needs a CC0 replacement (or a
  procedural stagger mask) before the tileset widget lands.
- DNTS splat textures are harvested from existing BAR maps and stay inside the BAR ecosystem.

Keep prototypes as map projects (`MapProjects/`); textures get replaced with licensed final
assets when a map heads to release.

## 5. Back to normal play

```bash
just chobby::dev-mode off      # Chobby channel back to byar
just link::unlink engine       # or `all`
```
