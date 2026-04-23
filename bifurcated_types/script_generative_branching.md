# Generative Branch Rebuild

Deterministic script to reconstruct the `fmt`, leaf (`mig-*`), and linear `mig` branches from `origin/master`. Runs codemod transforms, captures output, and optionally updates leaf PRs via `gh`.

## Branch Topology

```
origin/master
  └─ fmt (stylua + luacheck + .git-blame-ignore-revs)
      ├─ mig-bracket              (leaf: bracket-to-dot)
      ├─ mig-rename-aliases      (leaf: rename-aliases)
      ├─ mig-detach-bar-modules  (leaf: detach-bar-modules)
      ├─ mig-spring-split        (leaf: spring-split)
      └─ mig                     (linear: all four transforms, one commit each)
```

**Leaf branches** show one transform in isolation. Each has its own draft PR for review.

**Linear `mig` branch** applies all transforms sequentially (one commit per transform). This is what eventually merges.

Both topologies are reconstructed from scratch every run -- no cherry-picks, no rebases, no conflicts.

## Usage

```bash
# Rebuild all branches locally (does not push)
just bar::fmt-mig-generate

# Rebuild + force-push to upstream
just bar::fmt-mig-generate --push

# Rebuild + push + update leaf PR descriptions with captured stats
just bar::fmt-mig-generate --push --update-prs
```

## What the script does

1. `git fetch origin` and `git checkout -B fmt stylua` (the `stylua` branch has config/CI fixes)
2. Run stylua across the repo (the "fmt" pass)
4. Commit, create `.git-blame-ignore-revs`, commit again
5. For each leaf transform: checkout from `fmt`, run codemod commands, run stylua, commit
6. Build `mig` branch: checkout from `fmt`, apply all transforms in order (commit after each)
7. If `--push`: force-push all branches to `$PUSH_REMOTE` (default: `upstream`)
8. If `--update-prs`: update each leaf's PR body via `gh pr edit` with a generated description + captured codemod output

## Config format

Transforms are defined in `BAR-Devtools/scripts/generate-branches.sh` as bash functions. Each transform has:

- `<name>_branch` -- git branch name (e.g. `mig-bracket`)
- `<name>_commit` -- commit message
- `<name>_pr` -- GitHub PR URL for `gh pr edit` (optional)
- `<name>_description` -- extra markdown for the PR body (optional)
- `run_<name>()` -- function that runs the codemod commands
- `describe_<name>()` -- function that echoes the commands with comments (for PR body)

The `TRANSFORMS` array controls ordering (matters for the linear `mig` branch).

### Adding a new transform

```bash
TRANSFORMS=("bracket_to_dot" "rename_aliases" "detach_bar_modules" "spring_split" "my_new_thing")

my_new_thing_branch="mig-my-new-thing"
my_new_thing_commit="refactor: my new thing"
my_new_thing_pr=""
my_new_thing_description=""

run_my_new_thing() {
    "$CODEMOD" my-new-thing --path "$BAR" --exclude common/luaUtilities
}

describe_my_new_thing() {
    cat <<'EOF'
# my-new-thing - description here
bar-lua-codemod my-new-thing --path "$BAR_DIR" --exclude common/luaUtilities
EOF
}
```

## PR body template

Each leaf PR gets an auto-generated body:

```markdown
## Commands

Demonstrates running bar-lua-codemod with:

    ```sh
    # bracket-to-dot - convert x["y"] to x.y and ["y"] = to y =
    bar-lua-codemod bracket-to-dot --path "$BAR_DIR" --exclude common/luaUtilities
    ```

{description, if any}

## Output Summary

    ```
    {captured stdout from codemod commands}
    ```
```

## Notes

### `.stylua.toml` column_width

The script patches `column_width = 120` to `column_width = 2000` during the fmt build. This effectively disables line-width wrapping as requested by WatchTheFort and Boneless. The change is committed into the `fmt` branch, not applied as a local-only hack.

### Orphan commit

The `mig` branch previously had a manual "Spring orphaned nested tables" commit (`ced7f66d0b`) that isn't produced by any codemod. This was a one-time manual edit. If it needs to be reproduced, either:
- Add it as a new codemod transform in `bar-lua-codemod`
- Apply it manually after running `fmt-mig-generate`

### Remote

The script pushes to `$PUSH_REMOTE` (default: `upstream`, which is `keithharvey/bar`). Override with `PUSH_REMOTE=origin just bar::fmt-mig-generate --push` if needed.

## Implementation

- Script: `BAR-Devtools/scripts/generate-branches.sh`
- Recipe: `just bar::fmt-mig-generate` in `BAR-Devtools/just/bar.just`
