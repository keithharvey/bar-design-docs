Hey @rhys-vdw, @badosu -- so I went and built the whole thing. Rushing to get this out since I have some friends coming in from out of town tomorrow and I desperately want to get my PRs out of draft and surprisingly this is blocking for me on the goals I've set out for myself this spike. Fair warning: I vibe coded this with Opus but I've tested it thoroughly and it does what I need.  More importantly, it **doesn't touch the existing `Spring` interface at all** -- the per-file output, the docs, the helper classes, all exactly the same.

Here's what I did:

**lua-doc-extractor:** [PR #74](https://github.com/rhys-vdw/lua-doc-extractor/pull/74). Added `--table-mapping "Spring:SpringSynced"` which remaps the first segment of names in the output, and `--strip-helpers` which drops standalone classes/enums/aliases so they don't duplicate what's already in the per-file output. No changes to C++ annotations needed. 16 new tests, all passing, bumped to 3.4.0.

**RecoilEngine:** [new commit on #2799](https://github.com/beyond-all-reason/RecoilEngine/pull/2799/changes/8eb0f5aecd76bb5b7f82f1e940ced122a756ed47). Adds a `lua_library_bifurcated` mise task that runs after the existing generation. Three non-overlapping passes produce:

- `SpringShared.lua` (425 functions from LuaSyncedRead + LuaUnsyncedCtrl -- the functions available in both contexts)
- `SpringSynced.lua` (210 functions from LuaSyncedCtrl only, inherits SpringShared)
- `SpringUnsynced.lua` (172 functions from LuaUnsyncedRead only, inherits SpringShared)

`Spring.lua` declares `---@class Spring : SpringSynced, SpringUnsynced`, composing the full API from both contexts. Zero duplication across the generated files -- each source file is processed exactly once. The source file groupings match the actual table assembly in `LuaHandleSynced.cpp`.

**BAR:** [cleanup commit on #5704](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5704/changes/628e8dbc1917b294bc9bbc1771877a5a3151a671#diff-d95ea3877f21666889b6de43da3bf249012e5810dbfb16a1507e90a780248284R1). Killed the 39 hand-maintained `---@field` declarations in `types/spring.lua` -- all generated now. There's also a `simulate-bifurcated-types.sh` script in that commit so I can test locally before the pipeline is live (I'll clean this up later, this was just for a hot second)

The reason I care about this: I'm doing dependency injection on my synced gadget code. Spring gets passed as a `springRepo: SpringSynced` parameter to pure functions that I can then unit test with my mock. [Here's the commit where I renamed ISpring to SpringSynced](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/5704/changes/e5ef77249d7bb57ec7fdfac69e36ba9fe40a5fb6) -- you can see it flowing through the economy solver, resource transfers, unit transfers, context factory, and the gadget controllers. They're all decorators anyway, so I'm naturally bifurcating my code along synced/unsynced file naming conventions, and now the EmmyLua types reflect that.

**On "all the way through":** You're right that the constituent types should be the primary definitions. Right now the per-file output (`LuaSyncedRead.cpp.lua` etc.) still produces `function Spring.GetGameFrame()`, and the context-specific files produce `function SpringShared.GetGameFrame()` alongside it. Both resolve correctly via the class hierarchy, but it does mean the function exists in two places in the generated output. Going fully "all the way through" -- where the per-file output itself uses `SpringShared.*`/`SpringSynced.*`/`SpringUnsynced.*` instead of `Spring.*` -- would be cleaner, but it breaks the 1:1 mapping from input C++ files to docs site pages. We'd probably want to realign the docs site to also be organized by these categories rather than by source file, which is a bigger conversation. Happy to explore that on the `lua-language-types` branch when you have bandwidth.

End result: 807 unique functions across three generated files, zero duplication, LuaLS autocomplete works, F12 goes to the right place, and `missing-fields` fires when my mock falls behind the engine API. The existing `Spring.*` stuff is completely unchanged for everyone else.
