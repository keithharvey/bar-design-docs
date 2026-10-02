# Kickoff prompt for the Hello Pawns build session

Paste everything below the line into the new session, or just tell it: "read ~/code/bar-design-docs/campaign_api/hello_pawns_prompt.md and do it."

---

Build the Hello Pawns demo in /var/home/daniel/code/Beyond-All-Reason.

Branching: fetch upstream, then create branch `hello_pawns` off upstream/master. Do NOT base on the modules branch — it is regenerated (overlay commits) and anything based on it gets orphaned. Instead BORROW from it: checkout `modules/module_handler.lua`, `modules/policy_builder.lua`, and the minimal `modules/types/` files + emmylua config the loader needs, from the modules branch onto your branch. If the borrow drags in more than expected, report that as a finding — it is a live question in matchflow_module_plan.md ("loader bootstrap size"), not an obstacle to silently work around.

Read before writing any code, in this order:

1. ~/code/bar-design-docs/campaign_api/hello_pawns_plan.md — THE plan. Its scope rules are hard limits: three verbs only, demo-minimal matchflow (scripted-verdict path only), no objective UI if it threatens the win path.
2. ~/code/bar-design-docs/campaign_api/mission_authoring_dsl.md — the DSL grammar you are implementing a skeleton of: chain shapes, trigger identity = filename + declaration order, the source-vs-save state table.
3. ~/code/bar-design-docs/campaign_api/matchflow_module_plan.md — context only. The demo's `MatchFlow.Victory(...)` call shape must survive when the real module lands later. Build nothing from this plan beyond the scripted-verdict path.
4. Exemplars, on the modules branch (read there, borrow what the plan says): modules/module_handler.lua (especially includeRegistrationFile — your mission loader uses this idiom), modules/policy_builder.lua (the builder idiom your DSL follows), modules/sharing/ (what a finished module looks like — read-only reference, do not copy it over or modify it).

Order of work = the plan's "Order of work tonight" section. Milestone 4 (skirmish, `/luarules mission hello_pawns`, build 3 Pawns, victory) is the deliverable. STOP and report at milestone 4 before attempting the reload command or the RML form.

Testing, two layers, two frameworks — do not mix them up:

- UNIT tests: busted, in spec/, for the pure-Lua pieces (trigger engine, DSL builder, condition evaluation). Write these alongside the code, per the plan's order of work.
- INTEGRATION test at the first stop: the repo's own in-game framework in luaui/Tests/ (NOT busted — conversion to busted is a someday, not tonight). Tests are coroutine files run by the dbg_test_runner widget using the Test.* DSL — see types/IntegrationTests.lua for the API and luaui/Tests/sharing/ for a real exemplar to copy the shape from. Before reporting milestone 4, write luaui/Tests/hello_pawns/: load the mission via the chat command, cheat-spawn or build toward 3 Pawns, Test.waitUntil the count, and Test.expectCallin("GameOver") with the right winners. This test plays the actual mission — it fails if DSL registration breaks, the loader env is missing a verb, the condition never fires, or the verdict path is disconnected. tools/headless_testing/ is the harness for running it without a display; if you get it working, that procedure is a prime skill to capture.

Write skills as you go. Any time you figure out a repeatable procedure — running the busted specs, launching the game to test a gadget, the mission-load chat command, checking with emmylua — capture it immediately as a project skill in the BAR repo itself (/var/home/daniel/code/Beyond-All-Reason/.claude/skills/<name>/SKILL.md, imperative voice, the exact commands that worked). NOT in BAR-Devtools — Devtools owns cross-repo scripting and orchestration; skills that make sense with only the BAR repo cloned belong in BAR. If a skill already covers it, improve that skill instead of duplicating it. The demo is half the deliverable; the paved road for the next session is the other half.

Known repo facts — do not rediscover these the hard way:

- Synced Lua strips rawset. Plain assignment only in lazy __index contracts; the crash fires only when first resolved from synced code.
- _G can be nil in unsynced sandboxes. Use module_handler's CHUNK_ENV pattern; never roll your own.
- Fresh worktrees need the recoil-lua-library submodule initialized and the .lux symlink.
- emmylua baseline is 1 pre-existing error (gui_pip). Anything beyond that is yours.
- game_end.lua ends the game on elimination. Spawn no enemy, or pick a setup where nothing can die before the Pawns exist.
- Busted: specs live in spec/; the shim caches truthy returns only; the test sandbox has had getfenv/setmetatable deliberately exposed — if the sandbox is missing something your loader needs, extend the sandbox the same way rather than weakening the loader.

Boundaries:

- Commit locally as you go with clear messages. Do not push to any remote.
- Do not modify modules/sharing/ or game_end.lua. Do not add verbs beyond the three.
- Type-annotate everything (LuaCATS). The annotations are load-bearing for the editor design — they become the form schema — not decoration.
- State discipline from commit one: trigger fired-flags/counters live in the engine's plain tables, never in closures (the savegame rule).
- When you hit an in-game verification step you cannot perform, say exactly what needs manual testing and how, instead of claiming it works.
