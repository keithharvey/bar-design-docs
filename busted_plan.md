# Busted Commit Extraction Plan

## Problem

The staged sharing tab commit contains test infrastructure changes that logically belong in the Busted commit (`6a96904cfc`). Specifically the Synced/Unsynced type split and the `spring_builder.lua` → `spring_synced_builder.lua` rename.

## Current Commit Stack

```
master (6713192b30)
  └─ af1e9aa0b6  Lux package manager              (fork/lux)
      └─ 6a96904cfc  Busted Unit Tests             (fork/specs)
          └─ 60971a5e91  CUSTOM_ENGINE_URL          (fork/int — not yet on origin)
              └─ a055d8f1bd  i18n.interpolate fix   (fork/sharing_tab HEAD)
                  └─ [staged]  sharing tab mega-commit
```

## What Needs to Move

### Clean (no sharing deps)
| File | Why it belongs in Busted |
|------|--------------------------|
| `common/luaUtilities/resource_type.lua` | **New.** `ResourceType`/`ResourceTypes` extracted here from `transfer_enums.lua`. A universal primitive with no sharing logic. `transfer_enums.lua` re-exports it for full backward compat. |
| `types/simulate-bifurcated-types.sh` | Generates `SpringSynced`/`SpringUnsynced`/`SpringShared` from Recoil source via `lua-doc-extractor` |
| `types/spring.lua` (partial) | Replaces hand-written `ISpring` with `SpringSyncedMock : SpringSynced`, which derives from the generated types |

### Contaminated (sharing-specific code mixed in)
| File | Busted part | Sharing part |
|------|------------|--------------|
| `spec/builders/spring_synced_builder.lua` | Class rename `SpringBuilder` → `SpringSyncedBuilder`, type annotations `ISpring` → `SpringSyncedMock` | `game_economy = "1"` default mod option, `setDataCalls`/`__resourceSetCalls`/`__clearResourceDataCalls` economy stubs |
| `spec/builders/index.lua` | `SpringBuilder` → `SpringSyncedBuilder` reference | Adds `ResourceDataBuilder`, `ModeTestHelpers` |
| `spec/builders/team_builder.lua` | `WithID()`, `WithAllyTeam()` helpers, player ID separation | `ResourceDataBuilder` usage, `WithPlayer()` |
| `spec/spec_helper.lua` | `Spring.Echo`, `_G.GG` | Economy audit stubs (`IsEconomyAuditEnabled`, etc.) |
| `.luarc.json` | Lux paths `5.1` → `jit` fix | `common/luaUtilities` added to library |
| `types/spring.lua` (partial) | `SpringSyncedMock : SpringSynced` + `UnitWrapper`/`TeamData`/`ResourceData` | `GameEconomyController`, `GameUnitTransferController`, `EconomyTeamResult`, `TeamResourceData` |

## Options

### Option A: New Commit, Clean Files Only (safe, partial)

Extract only the purely clean files into a new commit between HEAD and the sharing commit. Mixed files stay in sharing.

```bash
# 1. Unstage everything
git reset HEAD

# 2. Stage ONLY the clean busted-infra files
git add types/simulate-bifurcated-types.sh

# 3. For types/spring.lua — need manual edit to commit only the busted part
#    (SpringSyncedMock class def + UnitWrapper/TeamData/ResourceData refactors)
#    Then add the sharing-specific types back before the sharing commit
git add types/spring.lua  # after manual split

# 4. Commit
git commit -m "Busted: add bifurcated type generation script and SpringSynced types"

# 5. Stage everything else
git add -A
# 6. Commit sharing tab
```

**Problem**: `types/spring.lua` still has mixed content. Would need manual edit-commit-edit cycle. And the sharing tab commit still references `spring_synced_builder` which doesn't exist until this commit, but `index.lua` is in the sharing commit… circular.

### Option B: Interactive Rebase to Amend Busted Commit (thorough, risky)

```bash
git rebase -i af1e9aa0b6  # rebase onto lux
# mark 6a96904cfc as "edit"
# at the edit point, apply the clean type changes + rename
# continue rebase
```

**Problem**: You just did a painful rebase and force-pushed multiple branches. Another interactive rebase risks having to redo conflict resolution and re-force-push `fork/specs`, `fork/int`, and `fork/sharing_tab`.

### Option C: Dedicated Follow-Up Commit (pragmatic, recommended)

Don't amend the old Busted commit. Instead, create a **new commit** in the stack specifically for the type infrastructure upgrade. The sharing tab commit remains as-is but smaller.

```
master
  └─ Lux package manager
      └─ Busted Unit Tests (original, unchanged)
          └─ CUSTOM_ENGINE_URL
              └─ i18n.interpolate fix
                  └─ [NEW] Busted: bifurcated types + spring_synced_builder ← extract this
                      └─ Sharing Tab (everything else)
```

#### Steps

```bash
# 1. Unstage everything
git reset HEAD

# 2. Stage the busted-infra files (new + renamed)
git add common/luaUtilities/resource_types.lua
git add types/simulate-bifurcated-types.sh
git add spec/builders/spring_synced_builder.lua
git add spec/builder_specs/spring_synced_builder_spec.lua

# 3. Partially stage mixed files (interactive hunk selection)
git add -p types/spring.lua        # take SpringSyncedMock + UnitWrapper/TeamData/ResourceData, skip GameEconomyController etc.
git add -p spec/spec_helper.lua    # take Spring.Echo + _G.GG, skip economy audit stubs
git add -p spec/builders/index.lua # take SpringBuilder→SpringSyncedBuilder rename, skip ResourceDataBuilder/ModeTestHelpers
git add -p .luarc.json             # take 5.1→jit path fix, skip common/luaUtilities

# 4. For team_builder.lua, the WithID/WithAllyTeam helpers are useful generically
#    but ResourceDataBuilder usage ties it to sharing. Skip for now—leave in sharing commit.

# 5. Commit
git commit -m "$(cat <<'EOF'
Busted: bifurcated types and spring_synced_builder rename

Adapt the test framework to use generated SpringSynced/SpringShared/SpringUnsynced
types from lua-doc-extractor instead of hand-written ISpring. Renames SpringBuilder
to SpringSyncedBuilder to match.

Includes simulate-bifurcated-types.sh for local type generation from RecoilEngine
source until the CI pipeline publishes them.
EOF
)"

# 6. Stage everything remaining
git add -A

# 7. Commit sharing tab
git commit -m "sharing tab commit message here"
```

**The `git add -p` steps are the fiddly part** — you'll be accepting/rejecting individual hunks in 3 files (one fewer than before, since `spring_synced_builder.lua` is now fully stageable as-is). But it's safe (no rebase, no force push) and produces a clean history.

#### Hunk Guide for `git add -p`

**`types/spring.lua`**: Accept the `SpringSyncedMock : SpringSynced` class def and the `UnitWrapper`/`TeamData`/`ResourceData` refactors. Reject `GameEconomyController`, `GameUnitTransferController`, `EconomyTeamResult`, `TeamResourceData`, `ResourceName` additions.

**`spec/spec_helper.lua`**: Accept the `Spring.Echo` and `_G.GG = {}` additions. Reject `IsEconomyAuditEnabled`, `EconomyAuditLog*`, `EconomyAuditBreakpoint`, `GetGameFrame`, `GetAuditTimer`.

**`spec/builders/index.lua`**: Accept `SpringBuilder` → `SpringSyncedBuilder` rename. Reject `ResourceDataBuilder` and `ModeTestHelpers` additions. (May need to split the hunk with `s`.)

**`spec/builders/spring_synced_builder.lua`**: No longer needs hunk selection — the `TransferEnums` import is gone. The remaining sharing-specific parts (`game_economy = "1"` default, economy audit stubs) are in the sharing commit where they belong. Stage the whole file.

**`.luarc.json`**: Accept the `.lux/5.1/` → `.lux/jit/` path changes + the new `luafilesystem` entry. Reject the `common/luaUtilities` addition. (Also may need hunk splitting.)

### Option D: Don't Split, Document Instead

Keep everything in the sharing tab commit. In the PR description, note that it includes test framework improvements (type bifurcation, builder rename) that were developed alongside the sharing modes. This is the simplest approach if the Busted PR (#5902) is going to be reviewed with the understanding that the sharing tab builds on it.

## Recommendation

**Option C** if you want clean history for review. The `git add -p` takes ~10 minutes but is safe.

**Option D** if the PRs will be reviewed together anyway and the separation is purely aesthetic.

Either way, the `types/simulate-bifurcated-types.sh` script and the generated `recoil-lua-library/library/generated/` output are independently valuable and could live in either commit.
