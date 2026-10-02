hey man — I think we should kill the zip and switch it over to BAR-Devtools. Happy to do
that side of it for you; here's what to do on yours.

## The engine build doesn't need to exist

I traced everything the zip's engine carries, and it's all yours and all already in master:

- #3127 Make `Spring.SetMapShader` work reliably (merged 07-22) — the "Lua map shader fixes"
- #3088 Fix InitBlank skybox creation and runtime swapping (merged 07-13)
- #3086 InitBlank DNTS propagation + blank-map splat mapoptions, SMF DNTS gating/fallbacks (merged 07-23)

None of them are in `2026.06.12` (released 07-14), which is the only reason the zip ships
`spring.exe` at all. So there's nothing private to distribute — the custom build *is* master.

For anyone on Devtools that means no fork, no branch pin, no `recoil-terraform-test` folder:

```bash
just repos::clone recoil
just engine::build linux        # windows on WSL2
just link::create engine        # -> <data>/engine/local-build
```

`bar::launch` injects `--engine local-build` on its own, so the `.bat` has no job either. And
the moment an engine release contains #3086, even this goes away — testers just play.

## Publish branches instead of zips

Anything not yet merged, put on a branch on your fork and tell people the row to drop in their
`repos.local.conf` (gitignored, per-user, so nobody edits Devtools):

```
Beyond-All-Reason   git@github.com:<you>/Beyond-All-Reason   <branch>
```

then `just repos::sync --force` and they're on your work. That's the whole distribution story —
no zip, no extract-into-your-install, no SmartScreen dance.

## The textures

Put these in the BAR PR alongside the widgets — don't ship them as a hand-installed folder:

- **DNTS splat sets + SkyBoxes** — harvested from BAR maps, so already BAR-licensed. They go
  in the PR next to the widgets that read them; nobody hand-installs, nothing drifts.
- **Poly Haven layers (`tileset_dev`)** — CC0, license is a non-issue. The placeholder set
  goes in the PR next to `dev_tileset_terrain.lua`. Only the 4.4 GB diffuse library stays an
  optional download — too big for git.
- **`quarry_cliff_chunky_nor_gl_2k.png`** — textures.com, prototype-only, can't be
  redistributed, so it cannot enter the repo. Swap it for a CC0 equivalent (Poly Haven has
  quarry/cliff normals) or generate the stagger mask procedurally — it's one file, and it's
  the only thing blocking the tileset widget from landing like the rest of the suite already
  did (`cmd_terraform_brush*`, `cmd_terraform_suite`, `cmd_map_project`, `cmd_splat_painter`,
  `RmlWidgets/gui_terraform_brush` are all in there).

Until the PR merges, publish it as a branch on your fork — the `repos.local.conf` row above
covers distribution. That's the whole story: no zip, no data-dir installs, and the zip's
engine build dies at the next engine release.
