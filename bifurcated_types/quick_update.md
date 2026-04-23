@WatchTheFort @[BONELESS]
Ok so quick update. I did address the globals. Check out the commit "env(llm): fmt-llm-source preparation for the LLM run" for the manual changes that made that possible (would link but it'd be stale pretty fast).

The 38 remaining errors broke into three neat buckets:

| Category | Count | Names | Fix |
|---|---|---|---|
| Test-DSL bare globals injected by the test runner | 33 | `assertThrowsMessage` (×15), `assertThrows` (×8), `assertSuccessBefore` (×7), `assertTablesEqual` (×2), `pack` (×1) | `@meta` stubs in `types/Test.lua` |
| Engine GL constant | 2 | `GL_TEXTURE_2D` | Added to `.emmyrc.json` `diagnostics.globals` |
| Real dead-code refs | 3 | `CommandNames` (×2 in `luaui/debug.lua`), `CALLIN_MAP` (×1 in `luarules/gadgets.lua`) | `---@diagnostic disable-next-line` + `-- TODO:` at each use site |

All addressed in the env commit so the LLM pass doesn't have to.

Added two separate "leaf" PRs so we can discuss them independently:

* [Integration Test Refactor PR](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7437) - had to refactor these a bit to get them out of ignoreDirs. No more magic singletons, return tables. @NortySpock

* [Busted Types PR](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/7438) - Watch said "no globals that mask real problems" and this one would qualify, imho. I would never type these myself without intellisense. Ended up just copying in LuaCATS again into types/ and ensuring correct licensing/provenance. I think this is the correct call for this moment in history (TLDR Lux wants lua-package-manager to do something before they can do something), but it is incredibly kludgey. So I removed one kludge and added one.