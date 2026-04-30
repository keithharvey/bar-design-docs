#!/usr/bin/env bash
# devtools_split_pr.sh — open PRs for the focused branches split out of
# bar-fmt. Companion to devtools_split_pr.md, which has the rationale.
#
# Branches are assumed to already be pushed to the fork remote (default
# `upstream`, e.g. keithharvey/BAR-Devtools). PRs target the canonical
# `origin` (beyond-all-reason/BAR-Devtools) cross-repo.
#
# Usage:
#   cd /path/to/BAR-Devtools
#   bash /path/to/bar-design-docs/bifurcated_types/devtools_split_pr.sh        # dry run
#   DO_IT=1 bash /path/to/bar-design-docs/bifurcated_types/devtools_split_pr.sh
#
# Skips PR creation if a PR already exists for the branch.

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────

DEVTOOLS_DIR="${DEVTOOLS_DIR:-$PWD}"
REPO="${REPO:-beyond-all-reason/BAR-Devtools}"
BASE="${BASE:-master}"
REMOTE="${REMOTE:-upstream}"
DO_IT="${DO_IT:-0}"

# ─── Helpers ───────────────────────────────────────────────────────────────

c_blue='\033[0;34m'; c_green='\033[0;32m'; c_yellow='\033[1;33m'
c_red='\033[0;31m'; c_dim='\033[2m'; c_bold='\033[1m'; c_reset='\033[0m'

info() { echo -e "${c_blue}[info]${c_reset}  $*"; }
ok()   { echo -e "${c_green}[ok]${c_reset}    $*"; }
warn() { echo -e "${c_yellow}[warn]${c_reset}  $*"; }
err()  { echo -e "${c_red}[error]${c_reset} $*"; }
step() { echo -e "${c_bold}>>${c_reset} $*"; }

run() {
    if [[ "$DO_IT" == "1" ]]; then
        "$@"
    else
        echo -e "${c_dim}    $*${c_reset}"
    fi
}

git_in_devtools() { git -C "$DEVTOOLS_DIR" "$@"; }

remote_has_branch() {
    git_in_devtools ls-remote --exit-code --heads "$REMOTE" "$1" >/dev/null 2>&1
}

# `gh pr create --head` accepts bare `branch` for same-repo or `owner:branch`
# for cross-repo. If $REMOTE points at a different GitHub repo than $REPO,
# we need the owner prefix so GitHub knows where the head branch lives.
head_ref() {
    local branch="$1"
    if [[ -n "${HEAD_OWNER:-}" && "${HEAD_OWNER}/${REPO##*/}" != "$REPO" ]]; then
        echo "$HEAD_OWNER:$branch"
    else
        echo "$branch"
    fi
}
pr_exists() {
    gh pr list --repo "$REPO" --head "$(head_ref "$1")" --state open --json number --jq '.[0].number' 2>/dev/null | grep -q .
}

# Open PR for an already-pushed branch.
do_branch() {
    local branch="$1" title="$2" body="$3"

    step "${c_bold}${branch}${c_reset}"
    if [[ "$DO_IT" == "1" ]] && ! remote_has_branch "$branch"; then
        warn "  $REMOTE/$branch not found — push it first, then re-run"
        echo ""
        return 0
    fi

    if [[ "$DO_IT" == "1" ]] && pr_exists "$branch"; then
        local existing
        existing="$(gh pr list --repo "$REPO" --head "$(head_ref "$branch")" --state open --json number,url --jq '.[0]')"
        info "  PR already open for $branch: $(echo "$existing" | jq -r .url)"
    else
        run gh pr create \
            --repo "$REPO" \
            --base "$BASE" \
            --head "$(head_ref "$branch")" \
            --title "$title" \
            --body "$body"
    fi
    echo ""
}

# ─── Pre-flight ────────────────────────────────────────────────────────────

if [[ ! -d "$DEVTOOLS_DIR/.git" ]]; then
    err "Not a git repo: $DEVTOOLS_DIR"
    err "cd into BAR-Devtools, or set DEVTOOLS_DIR=/path/to/BAR-Devtools"
    exit 1
fi

if ! command -v gh >/dev/null; then
    err "gh CLI not found — install from https://cli.github.com/"
    exit 1
fi

# Validate that $REMOTE exists and infer the fork owner from its URL. This
# is what gh pr create needs as `--head owner:branch` for cross-repo PRs.
remote_url="$(git_in_devtools remote get-url "$REMOTE" 2>/dev/null || true)"
if [[ -z "$remote_url" ]]; then
    err "Remote '$REMOTE' not found in $DEVTOOLS_DIR."
    err "Set REMOTE=<your-fork-remote-name> or push branches to '$REMOTE' first."
    exit 1
fi
HEAD_OWNER="$(sed -nE 's|.*[:/]([^/]+)/[^/]+(\.git)?$|\1|p' <<<"$remote_url")"

# Sanity-check: a same-repo run (REMOTE points at $REPO) is valid; a
# cross-repo run (REMOTE points at a fork) is the common case. Anything
# else (REMOTE points at someone else's fork by mistake) we want to flag.
if [[ -z "$HEAD_OWNER" ]]; then
    err "Couldn't parse owner from remote URL '$remote_url'."
    exit 1
fi

if [[ "$DO_IT" == "1" ]]; then
    info "Fetching $REMOTE..."
    git_in_devtools fetch "$REMOTE" --quiet
    echo ""
else
    warn "DRY RUN — no PRs created. Re-run with DO_IT=1 to apply."
    echo ""
fi

info "Repo:   $REPO   (PR base)"
info "Base:   $BASE"
info "Remote: $REMOTE → $remote_url"
info "Head:   $HEAD_OWNER:<branch>"
info "Source: $DEVTOOLS_DIR"
echo ""

# ─── lua-check (3 commits: feat + lux revert + path fix) ───────────────────

do_branch \
    "lua-check" \
    "feat(lua): just lua::check + lux-shape revert" \
    "$(cat <<'EOF'
## Summary
- Adds \`just lua::check\` — runs the same \`lua-language-server --check\` that CI runs (\`recoil-docs\` mise task), via the \`recoil-docs\` compose service so no host install is required.
- Aliases \`just lua::build\` to \`just lua::library\` (more discoverable name).
- Scopes \`just lua::reset\` to the auto-generated subtree (\`rts/Lua/library/generated/\` + \`rts/Lua/library/RecoilEngine/\`) instead of \`git checkout -- rts/Lua/library/\`, which previously wiped in-progress edits to hand-authored files like \`Spring.lua\`/\`Types.lua\`.
- Reverts the lux-shape coupling that PR #16 introduced into \`just/lua.just\`: \`recoil-lua-library\` is not committed to the lux/rock build shape, so \`lua::library\` and \`lua::reset\` shouldn't expect a lux tree, an \`lx sync\`, or a \`src/\` package layout. Now \`lua::library\` always copies into BAR's \`recoil-lua-library/library/\` (matching what \`.luarc.json\` already lists in \`workspace.library\` and what the engine-side path is named).

The dev container's lux install (used by \`bar::lint\` and \`bar::fmt\`) is unchanged — that's BAR's lint/fmt toolchain and unrelated to library shape.

## Test plan
- [ ] \`just lua::library\` populates \`Beyond-All-Reason/recoil-lua-library/library/\` (no \`.lux/5.1/...\` resolution, no \`src/\` directory)
- [ ] \`just lua::reset\` cleans only the generated subtree; hand-authored files in \`rts/Lua/library/\` remain
- [ ] \`just lua::check\` runs \`lua-language-server --check\` via \`recoil-docs\` and reports the same problem count as CI
EOF
)"

# ─── Tier A — 4 ungated improvements ───────────────────────────────────────

do_branch \
    "dev-image-install-gawk" \
    "dev image: install gawk in dev.Containerfile" \
    "$(cat <<'EOF'
## Summary
Adds gawk to the dev container so scripts that require GNU awk extensions (versus busybox awk) work inside the distrobox without surprise. Containerfile-only change.

## Test plan
- [ ] \`just setup::distrobox\` rebuilds the image without errors
- [ ] \`distrobox enter \$DEVTOOLS_DISTROBOX -- gawk --version\` works
EOF
)"

do_branch \
    "doctor-teiserver-local" \
    "doctor: handle local teiserver checkout in scripts/doctor.sh" \
    "$(cat <<'EOF'
## Summary
Small \`scripts/doctor.sh\` tweak so the doctor recipe works correctly when teiserver is configured as a local checkout via \`repos.local.conf\` rather than cloned. Doctor-script-only change.

## Test plan
- [ ] \`just doctor\` reports the teiserver image as built when it actually is, regardless of clone-vs-symlink
EOF
)"

do_branch \
    "integrations-local-volume-mounts" \
    "compose: integrations get local volume mounts" \
    "$(cat <<'EOF'
## Summary
Adds \`docker-compose.integrations.local.{sh,yml}\` so contributors can mount their working trees into the integrations stack instead of relying on the in-image copies. Useful for anyone iterating on integration-test code locally. Wires the recipe into \`just/bar.just\`.

## Test plan
- [ ] \`just bar::test-integration-local\` (or whatever the wired recipe name is) starts the stack with the local mounts and tests pick up working-tree edits without rebuilding the image
EOF
)"

# ─── Tier B — editor setup ─────────────────────────────────────────────────

do_branch \
    "editor-setup-emmylua" \
    "feat(setup): editor integration via EmmyLua + extension install" \
    "$(cat <<'EOF'
## Summary
Four commits ship a coherent editor-setup story:
- improve \`setup::editor\` for emmylua (initial wiring)
- VS Code extension install in \`just::editor\` + workspace settings template
- ramp up the anti-sumneko prompt (make it harder to land on the wrong LSP)
- drop force-formatOnSave from the BAR workspace template — re-enabled by the bar-fmt PR

Not strictly RFC-gated — EmmyLua is the de-facto LSP for BAR's bindings today (LuaLS/sumneko is too slow to parse them effectively). This PR just configures the editor to use what already works.

Format-on-save is intentionally **not** turned on by this PR: forcing it before the bar-fmt rollout lands would silently rewrite formatting on save in any region a contributor touches. Manual formatting still works (\`just bar::fmt\`, or "Format Document" since stylua is set as the default Lua formatter). The \`formatOnSave\` flag rejoins the template as part of the bar-fmt PR.

## Test plan
- [ ] \`just setup::editor\` exports \`emmylua_ls\`, \`emmylua_check\`, \`clangd\`, \`stylua\`, \`lx\` to \`~/.local/bin\`
- [ ] On a host with \`code\` on PATH, the recipe offers to install the recommended extensions and remove sumneko.lua
- [ ] If \`Beyond-All-Reason/.vscode/settings.json\` is absent, the template gets written; if present, the recipe diffs against the template and leaves it alone
- [ ] The written \`settings.json\` does **not** contain \`editor.formatOnSave\`
EOF
)"

# ─── Summary ───────────────────────────────────────────────────────────────

if [[ "$DO_IT" == "1" ]]; then
    ok "Done."
else
    info "Plan above. Re-run with DO_IT=1 to push and open PRs."
fi
