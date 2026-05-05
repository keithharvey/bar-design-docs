# Recording clipboard

Snippets to paste into the demo machine *off-camera*. Open this file in
its own window on the recording PC; the script lives in `video_script.md`
and stays closed so you can't accidentally glance at it on a take.

## `repos.local.conf` (paste in BEFORE the recorded `just setup::init`)

The video clones from `beyond-all-reason/BAR-Devtools` to stay timeless,
but for now the launch + editor work lives on a fork branch. After
`git clone … && cd BAR-Devtools` and *before* the recorded
`just setup::init`, drop this in:

```
# Per-user overrides of repos.conf (gitignored).

@local_root ~/code
@protocol ssh
bar_debug_launcher   git@github.com:keithharvey/bar_debug_launcher.git cli
RecoilEngine         git@github.com:keithharvey/RecoilEngine.git         fix/archivescanner-empty-pool-roots-crash
```

Save as `repos.local.conf` in the BAR-Devtools repo root.

Cut the take here so the recording resumes from `just setup::init` and
the viewer never sees the override file.
