# Lua 5.4 Migration: Initial Thoughts

Brain dump from an exploration session analyzing the feasibility of moving BAR from Lua 5.1 to 5.4. This is not a plan -- it's a record of what we found looking at the RecoilEngine source.

**Status: Parked.** No engine-side owner. The strategic direction is C# replacement, not Lua version upgrades. This document exists so the analysis doesn't have to be repeated if the conversation comes back.

## The engine side: how hard is the VM swap?

Recoil embeds Lua 5.1.5 as vendored source in `rts/lib/lua/` (~13,518 lines). The binding layer is 56 C++ files in `rts/Lua/` with ~4,487 Lua C API calls.

### Blockers by severity

**Hard: `setfenv`/`getfenv` (sandboxing) -- 9 call sites**

This is the only part that requires thought. The engine uses `lua_setfenv` to sandbox gadget/widget code into isolated environments:

- `LuaHandle.cpp` (2) -- loading gadget/widget chunks
- `LuaParser.cpp` (2) -- VFS.Include sandboxing
- `LuaVFS.cpp` (2) -- file loading sandbox
- `LuaUtils.cpp` (1) -- `PushFunctionEnv` helper
- `LuaHandleSynced.cpp` (2) -- commented-out lines

In 5.2+, `setfenv`/`getfenv` are replaced by `_ENV` upvalue manipulation. The pattern is well-documented: after `lua_load`, set the first upvalue of the loaded chunk to the desired environment table. The engine uses sandboxing in a contained, consistent way (always "load chunk, give it this env"), which maps cleanly to the 5.4 pattern.

**Mechanical: `LUA_GLOBALSINDEX` -- ~14 call sites**

Removed in 5.2. Replace with `lua_pushglobaltable(L)` + index operations. Straightforward find-and-replace in:

- `LuaParser.cpp` (3)
- `LuaHandle.cpp` (3)
- `LuaHandleSynced.cpp` (3)
- `LuaUI.cpp`, `LuaMenu.cpp`, `LuaIntro.cpp`, `LuaSyncedTable.cpp`, `LuaHashString.h` (1 each)

**Free: sol2 bindings**

7 files use sol2 (VBO, VAO, Shaders, Rml UI). sol2 already supports Lua 5.4. Rebuild against 5.4 headers, done.

**Needs review: `SerializeLuaState.cpp`**

1 call site with `LUA_GLOBALSINDEX`. This handles save/load of Lua state (game saves). The Lua 5.4 serialization format differs from 5.1. Needs careful analysis for save compatibility.

### Scorecard

| Change | Sites | Difficulty |
|--------|-------|-----------|
| Swap `rts/lib/lua/src/` for Lua 5.4 source | 1 directory | Copy-paste |
| `lua_setfenv`/`lua_getfenv` -> upvalue pattern | 5 call sites | Medium |
| `LUA_GLOBALSINDEX` -> `lua_pushglobaltable` | ~14 sites | Mechanical |
| sol2 rebuild | 0 code changes | Recompile |
| `SerializeLuaState.cpp` | 1 site | Needs review |

**Honest estimate:** A competent C++ dev who understands both Lua 5.1 and 5.4's C APIs could do the engine side in a week. The sandboxing migration (~5 real call sites) is the only part that requires understanding the design intent.

## The game code side

If the engine moves to 5.4, the game Lua code needs migration. A [full-moon](https://crates.io/crates/full_moon) based tool (see [../bifurcated_types/fmt_migrated_full_moon.md](../bifurcated_types/fmt_migrated_full_moon.md)) could automate most of this.

### Automatable transforms

| Category | 5.1 Pattern | 5.4 Equivalent |
|----------|------------|-----------------|
| Global `unpack` | `unpack(t)` | `table.unpack(t)` |
| `loadstring` | `loadstring(s)` | `load(s)` |
| `table.getn` | `table.getn(t)` | `#t` |
| `math.mod` | `math.mod(a, b)` | `a % b` |
| `string.gfind` | `string.gfind(...)` | `string.gmatch(...)` |
| Bitwise ops | `bit.band(a, b)` | `a & b` |
| Integer division | `math.floor(a/b)` | `a // b` (contextual) |
| `table.foreach` | `table.foreach(t, f)` | `for k,v in pairs(t) do f(k,v) end` |

### Requires human judgment

- **`setfenv` / `getfenv` -> `_ENV`**: Fundamental design change. Each use in game Lua needs analysis of what environment is being manipulated and why. The engine side is contained; the game side could be more scattered.
- **`module()` calls**: Structural redesign from module-function to return-table pattern.
- **Length operator `#` on tables with holes**: Behavior changed in 5.2+. Needs runtime analysis to determine if any code depends on 5.1's `#` behavior with sparse tables.

### full-moon for this

The pipeline is the same as bracket-to-dot -- parse, transform, write:

```rust
let ast = full_moon::parse(&code)?;       // parse 5.1 input
let ast = migrator.visit_ast(ast);         // transform: rewrite 5.1 patterns to 5.4 equivalents
fs::write(&path, full_moon::print(&ast));  // write result (now valid 5.4)
```

The transforms themselves are what convert the code. `bit.band(a, b)` becomes a `BinOp` node with `&`, `unpack(t)` becomes `table.unpack(t)`, etc. The output is valid Lua 5.4 because the visitor rewrote the AST nodes -- no second parse needed.

The `lua54` cargo feature flag on full-moon is only needed if you wanted to *parse* 5.4-specific syntax (like `<const>` attributes). For this migration, we're generating 5.4 code from 5.1 input, so the default 5.1 parser is sufficient.

## Why this is parked

1. **No engine-side owner.** Nobody on the Recoil team has expressed interest in swapping the Lua VM.
2. **Strategic direction is C# replacement.** Investing in Lua 5.4 migration competes with the longer-term goal of moving game logic to C#.
3. **The game code works fine on 5.1.** There's no pressing feature or performance need that 5.4 solves.
4. **LuaJIT compatibility.** Spring historically supported LuaJIT (5.1 API). Moving to 5.4 would break that path permanently.

If any of these change, this analysis is the starting point.
