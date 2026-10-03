# Savegame: what actually survives

Settled 2026-07-26 by reading the engine, after five stage reviews disagreed
about it. The working rule up to now — *mission progress must live in engine
state tables, never in closures* — is **not an engine constraint on BAR's save
path**. It is a project convention, and a weaker one than we thought.

## The chain

BAR writes **creg** saves. Every link verified, not inferred:

    luaui/Widgets/gui_savegame.lua:26     SAVE_TYPE = "save "        -- not "luasave "
    UnsyncedGameCommands.cpp:3755-3762    SaveActionExecutor(usecreg)
                                          "Save" -> ".ssf" | "LuaSave" -> ".slsf"
    LoadSaveHandler.cpp:13-24             CreateHandler dispatches on the extension
                                          "ssf" -> CCregLoadSaveHandler
    CregLoadSaveHandler.cpp:280-281       SaveLuaState(luaGaia); SaveLuaState(luaRules)
    CregLoadSaveHandler.cpp:189-193       creg::SerializeLuaState(s, &L)
                                          creg::SerializeLuaThread(s, &L_GC)
    CregLoadSaveHandler.cpp:176-188       Write() -> handle->SwapSyncedHandle(L, L_GC)

The last line is the one that matters: on load the **entire synced `lua_State`
is replaced** by the deserialized one. Gadget chunks are not re-executed.
Locals, upvalues, closure-captured tables, and the gadget handler's own callin
lists all come back as they were.

Corroborating: **no BAR gadget implements `Save` or `Load`** (`grep -rln
"function gadget:Save\|function gadget:Load" luarules/ modules/` is empty),
even though `gadgets.lua:2752-2761` forwards both. Those callins belong to the
`.slsf` path (`CLuaHandle::Save` at `LuaHandle.cpp:2503`, `Load` at `:666`),
reachable only via `/luasave`, which nothing in BAR issues.

`gui_savegame.lua:60-63` will *load* a `.slsf` if it finds one, but only ever
*writes* `.ssf`. And BAR autosaves in singleplayer — which is exactly where
missions run, so this path is not hypothetical.

## What this invalidates

Three review findings assumed Lua locals are lost across a save. On the `.ssf`
path they are not:

- **combat's closure-held ledger.** `guard` survives. The absent `Initialize`
  reconciliation is moot too — `Initialize` does not re-run on a creg load.
- **`mission_active` surviving while `activeMission` does not.** Both survive.
  The armed-form-over-a-dead-mission scenario does not occur on this path.
- **`trigger_engine.GetState`/`SetState` being unwired.** Correct as observed,
  harmless as diagnosed: they are only needed for the `.slsf` path. Either wire
  them for that path or delete them, but do not add a `gadget:Save` on their
  account.

## The rule, restated

Progress in rulesparams is still **preferable**, for reasons that survive:

- Rulesparams are readable unsynced, so the editor bridge and any widget can
  see them. A closure upvalue is invisible to LuaUI. This is the actual reason
  the mission loader publishes `objective_*`, and it is a good one.
- They are inspectable in a running game, which makes missions debuggable.
- They do not depend on creg Lua serialization being correct (see below).

What is *not* true: that a closure loses progress on save. Comments asserting
that should be corrected rather than propagated.

## The real hazards, which are different

- **State the engine holds C-side that Lua registered.** `watchUnitDefs`,
  `watchAllowTargetDefs` and friends are explicitly collected and restored
  (`CregLoadSaveHandler.cpp:155-175`) — so `Script.SetWatchAllowTarget`
  registrations do round-trip. Anything *not* in that struct does not.
- **Anything derived from files at load time.** The state is restored, not
  recomputed, so a mission whose triggers were included from disk keeps the
  triggers it had — including ones since edited on disk.
- **Creg Lua serialization being wrong.** This is the honest open risk. The
  code intends to save the state; that is not the same as it round-tripping
  correctly, and Spring's creg Lua save has a rough history.

## Still unproven

Nothing here was executed. The proof that closes it: arm a mission, complete an
objective, `/save`, quit, load, and confirm the trigger set, `state.fired`, the
combat ledger, and the objective rulesparams all come back. Until someone runs
that, this document establishes *which mechanism is on the path*, not that the
mechanism works.

## The inline form

For code comments that need to state this, one sentence is enough — do not
paste the chain:

    -- BAR saves via creg (.ssf): the whole synced Lua state is swapped back in
    -- on load, so this survives. Rulesparams are still preferred where LuaUI
    -- needs to read the value.
