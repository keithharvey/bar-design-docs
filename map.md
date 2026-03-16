# Sharing Tab — PR Map

Everything below exists to make the **Sharing Tab** technically sound. Unit tests were a hard requirement to do something like waterfill economy in-game, and the type system improvements keep the test mocks from drifting.

`|_` = "required by the PR above it" (dependency flows upward)

---

## Status Key

| Symbol | Meaning |
|--------|---------|
| :white_check_mark: | Merged |
| :large_blue_circle: | Open, unblocked |
| :yellow_circle: | Open, blocked |
| :red_circle: | Blocked by external decision |

---

## Dependency Tree

```
The Sharing Tab (BAR #5704)                          🟡 blocked by engine PR
├── Add Modes (Chobby #1041)                         🟡 blocked by Sharing Tab
├── Game Economy (Recoil #2664)                       🔴 blocked by Sprung comparison
│   └── OR: Game Economy RE (Recoil #2828)            🔴 same blocker
├── Unit Test Bootstrapping (BAR #5902)               🔵 unblocked
│   └── Lux Package Manager (BAR #6005)               🔵 unblocked
│       └── EmmyLua Synced/Unsynced Types (Recoil #2799)  🔵 unblocked
│           └── lua-doc-extractor --table-mapping (LDE #74)  🔵 unblocked
└── Integration Tests: CUSTOM_ENGINE_URL (BAR #7087)  🔵 unblocked
```

---

## All PRs

### Unblocked — Ready for Review

| # | PR | Repo | Branch | Description |
|---|-----|------|--------|-------------|
| 1 | [Lux Package Manager](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/6005) | BAR | `lux` | Adds Lux as the Lua package manager. Base for test dependencies. |
| 2 | [Unit Test Bootstrapping](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5902) | BAR | `specs` | Busted framework + builder pattern for Spring mocks, team config, and global isolation. |
| 3 | [EmmyLua Synced-Unsynced-Shared Types](https://github.com/beyond-all-reason/RecoilEngine/pull/2799) | Recoil | — | Generates `SpringSynced`, `SpringUnsynced`, `SpringShared` classes from engine source so LuaLS types don't drift. |
| 4 | [Add `--table-mapping` and `--strip-helpers`](https://github.com/rhys-vdw/lua-doc-extractor/pull/74) | lua-doc-extractor | — | CLI options that enable #3. Upstream dependency. |
| 5 | [Integration Tests: CUSTOM_ENGINE_URL](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7087) | BAR | `int` | Optional engine URL override for docker-compose CI. Zero-code engine swaps. |

### Blocked — Pending Engine or External Decision

| # | PR | Repo | Blocker | Description |
|---|-----|------|---------|-------------|
| 6 | [The Sharing Tab](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5704) | BAR | Engine PR (#7 or #8) | Sharing modes: Enabled, Disabled, Easy Tax, Tech Blocking. Waterfill economy, advplayerlist overhaul, unit and resource transfer policies. |
| 7 | [Game Economy](https://github.com/beyond-all-reason/RecoilEngine/pull/2664) | Recoil | Sprung comparison | Inversion-of-control for resource and unit transfer. Game-side controllers replace hardcoded engine behavior. |
| 8 | [Game Economy RE](https://github.com/beyond-all-reason/RecoilEngine/pull/2828) | Recoil | Sprung comparison | Copy of Sprung's branch for side-by-side API comparison with #7. One of these two will be chosen. |
| 9 | [Add Modes](https://github.com/beyond-all-reason/BYAR-Chobby/pull/1041) | Chobby | Sharing Tab (#6) | Dynamic mode tabs in lobby. Reads `modes/**/*.lua` from game archive. Data-driven mod option whitelisting. |

### Documentation

| Doc | Repo | Link |
|-----|------|------|
| Game Controllers & Policies | Recoil | [Issue #2781](https://github.com/beyond-all-reason/RecoilEngine/issues/2781) |
| Mode First, Details Second | Chobby | [Issue #1040](https://github.com/beyond-all-reason/BYAR-Chobby/issues/1040) |

---

## Merge Order

Ideal landing order assuming blockers resolve:

```
1. lua-doc-extractor #74     (upstream, independent)
2. Lux Package Manager #6005 (BAR, independent)
3. Busted Unit Tests #5902   (BAR, depends on #2)
4. EmmyLua Types #2799       (Recoil, depends on #1)
5. CUSTOM_ENGINE_URL #7087   (BAR, independent)
6. Game Economy #2664 or #2828 (Recoil, pending decision)
7. The Sharing Tab #5704     (BAR, depends on #3, #6)
8. Add Modes #1041           (Chobby, depends on #7)
```

---

## BAR Branch Stack (on `sharing_tab`)

The BAR commits stack linearly. Each branch tracks a separate `fork/` remote for its own PR:

```
master
  └─ af1e9aa0b6  Lux package manager              fork/lux     → PR #6005
      └─ 6a96904cfc  Busted Unit Tests             fork/specs   → PR #5902
          └─ 60971a5e91  CUSTOM_ENGINE_URL          fork/int     → PR #7087
              └─ a055d8f1bd  i18n.interpolate fix   fork/sharing_tab
                  └─ [staged]  sharing tab          → PR #5704
```

**Known issue**: The staged sharing tab commit contains test infrastructure changes (SpringBuilder → SpringSyncedBuilder rename, bifurcated type generation script, type annotation refactors) that logically belong in the Busted commit. See `busted_plan.md` for extraction options.
