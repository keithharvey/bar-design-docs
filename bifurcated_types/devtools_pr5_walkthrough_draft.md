# Dev Workflow Walkthrough: Engine API Change -> Game-Side Validation

> This comment demonstrates the developer workflow that this PR enables. The goal is to show how changes in the engine propagate through the toolchain to the game-side, with type checking catching mismatches before runtime.
>
> For context on the architecture this supports, see [RecoilEngine PR #2664 (Game Economy)](https://github.com/beyond-all-reason/RecoilEngine/pull/2664).

## How the pieces fit together

```
RecoilEngine C++              BAR-Devtools              Beyond-All-Reason
(EmmyLua decorators)          (just recipes)            (game-side Lua)

rts/Lua/LuaSyncedCtrl.cpp     just lua::library         types/Spring.lua
     |                              |                        |
     |   lua-doc-extractor parses   |                        |
     +----->------->------->--------+                        |
                                    |                        |
                   recoil-lua-library/library/generated/     |
                   (Spring.AddMetal, Spring.AddEnergy, ...)   |
                                    |                        |
                                    +-->-- LuaLS reads -->---+
                                                             |
                                              SpringSynced class
                                              game_resource_transfer_controller.lua
                                                             |
                                              Linter: "Undefined field `AddMetal`"
```

LuaLS resolves types from `recoil-lua-library` and `types/` (configured in [`.luarc.json`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/.luarc.json)):

```json
"diagnostics": {
  "type": {
    "definition": [".lux/", "types/", "recoil-lua-library/library/"]
  }
},
"workspace": {
  "library": ["recoil-lua-library", "types", ...]
}
```

---

## (a) Engine-side: add `AddMetal` / `AddEnergy` to the API

Sprunk [requested](https://github.com/beyond-all-reason/RecoilEngine/pull/2664#issuecomment-3627813409) that the economy controller interface expose per-resource convenience functions and that it "Sure, as long as it actually doesn't entangle with the legacy logic. Have the modrule also affect the following legacy resourcing lines (just add if modrule -- prompt note: we could use our gameEconomy for this, around each), then demonstrate a gadget" and referenced specific code lines.

https://github.com/beyond-all-reason/RecoilEngine/blob/0ccd60a7dc48120629def049486b8f02f70880c5/rts/Sim/Units/UnitTypes/Factory.cpp#L319 
https://github.com/beyond-all-reason/RecoilEngine/blob/0ccd60a7dc48120629def049486b8f02f70880c5/rts/Sim/Units/Unit.cpp#L1050-L1078


We add EmmyLua decorators to the C++ source in RecoilEngine:

```cpp
// rts/Lua/LuaSyncedCtrl.cpp

/***
 * Adds metal to the specified team's current resources.
 * Counts as production in post-game graph statistics.
 *
 * @function Spring.AddMetal
 * @number teamID
 * @number amount
 * @treturn nil
 */

/***
 * Adds energy to the specified team's current resources.
 * Counts as production in post-game graph statistics.
 *
 * @function Spring.AddEnergy
 * @number teamID
 * @number amount
 * @treturn nil
 */
```

Then regenerate the Lua library:

```sh
just lua::library
```

This runs `lua-doc-extractor` against the RecoilEngine C++ source and copies the generated stubs into `Beyond-All-Reason/recoil-lua-library/library/generated/`.

<details>
<summary>Terminal output</summary>

<!-- paste `just lua::library` output here -->

</details>

The generated file now includes the new function signatures:

```diff
 -- recoil-lua-library/library/generated/rts/Lua/LuaSyncedCtrl.cpp.lua

+---Adds metal to the specified team's current resources.
+---Counts as production in post-game graph statistics.
+---
+---@param teamID integer
+---@param amount number
+---@return nil
+function Spring.AddMetal(teamID, amount) end
+
+---Adds energy to the specified team's current resources.
+---Counts as production in post-game graph statistics.
+---
+---@param teamID integer
+---@param amount number
+---@return nil
+function Spring.AddEnergy(teamID, amount) end
```

---

## (b) Linter catches type mismatch on `SpringSynced`

The `game_resource_transfer_controller` uses a `springRepo` parameter typed as `SpringSynced`. When we update the controller to call the new engine functions:

```lua
-- game_resource_transfer_controller.lua
springRepo.AddMetal(teamID, amount)
springRepo.AddEnergy(teamID, amount)
```

LuaLS immediately flags errors because the hand-written `SpringSynced` class in [`types/Spring.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/types/Spring.lua) doesn't include these fields:

```lua
-- types/Spring.lua (current)
---@class SpringSynced
---@field CMD table
---@field Log fun(section: string, level: number, ...: any)
---@field GetModOptions fun(): table
---@field GetGameFrame fun(): number
---@field IsCheatingEnabled fun(): boolean
---@field GetTeamRulesParam fun(teamID: number, key: string): any
---@field SetTeamRulesParam fun(teamID: number, key: string, value: any)
---@field GetUnitDefID fun(unitID: number): number?
---@field ValidUnitID fun(unitID: number): boolean
---@field GetTeamLuaAI fun(teamID: number): string
-- no AddMetal, no AddEnergy
```

<!-- paste screenshot of LuaLS diagnostics showing the errors here -->

The linter reports `undefined-field` diagnostics:

```
Undefined field `AddMetal`.  [undefined-field]
Undefined field `AddEnergy`.  [undefined-field]
```

This is the mechanism: the engine defines the API surface, `lua-doc-extractor` propagates it into the generated library, and LuaLS enforces conformance on the game-side types. When we add engine functions and start using them game-side, any type gap is caught statically.

---

## (c) Fix the types, errors clear

Add the missing fields to `SpringSynced`:

```diff
 -- types/Spring.lua
 ---@class SpringSynced
 ---@field CMD table
 ---@field Log fun(section: string, level: number, ...: any)
 ---@field GetModOptions fun(): table
 ---@field GetGameFrame fun(): number
 ---@field IsCheatingEnabled fun(): boolean
 ---@field GetTeamRulesParam fun(teamID: number, key: string): any
 ---@field SetTeamRulesParam fun(teamID: number, key: string, value: any)
 ---@field GetUnitDefID fun(unitID: number): number?
 ---@field ValidUnitID fun(unitID: number): boolean
 ---@field GetTeamLuaAI fun(teamID: number): string
+---@field AddMetal fun(teamID: number, amount: number)
+---@field AddEnergy fun(teamID: number, amount: number)
```

<!-- paste screenshot of clean diagnostics here -->

LuaLS is satisfied. The controller's usage of `springRepo.AddMetal(...)` resolves correctly because `SpringSynced` now declares those fields, and the generated library confirms the functions exist on `Spring`.

---

## (d) `just reset` clears the generated artifacts

Before committing, we need to clean up the generated output that `just lua::library` wrote into both repos. This is tracked in git today (it shouldn't be -- see the [TODO in lua.just](https://github.com/thvl3/BAR-Devtools/blob/just/just/lua.just#L57-L60)), so without resetting, `git status` would show hundreds of modified/untracked files from the regenerated library.

```sh
just reset
```

This runs two sub-recipes:

1. **`lua::reset`** -- reverts `rts/Lua/library/` in RecoilEngine and resets the `recoil-lua-library` submodule in BAR
2. **`docs::reset`** -- reverts `doc/site/data/` in RecoilEngine

<details>
<summary>Terminal output</summary>

<!-- paste `just reset` output here -->

</details>

After reset:

```sh
cd RecoilEngine && git status
# only the C++ changes remain (the EmmyLua decorators we added)

cd ../Beyond-All-Reason && git status
# only the game-side changes remain (types/Spring.lua, controller)
```

<details>
<summary>git status in both repos</summary>

<!-- paste git status output here -->

</details>

---

## (e) Clean commits

Now we commit only the *inputs* -- not the generated outputs.

**RecoilEngine** (engine-side):
```sh
cd RecoilEngine
git add rts/Lua/LuaSyncedCtrl.cpp
git commit -m "feat(Lua): add Spring.AddMetal and Spring.AddEnergy"
```

**Beyond-All-Reason** (game-side):
```sh
cd ../Beyond-All-Reason
git add types/Spring.lua
git add luarules/gadgets/game_resource_transfer_controller.lua
git commit -m "feat: use AddMetal/AddEnergy in economy controller"
```

<details>
<summary>git diff --stat</summary>

<!-- paste git diff --stat for both repos here -->

</details>

No generated artifacts in either commit. The generated library is a local build artifact consumed by the editor, not tracked in the PR.

---

## Why this matters

This loop -- **engine change -> regenerate library -> linter catches mismatch -> fix game-side -> reset -> clean commit** -- is the developer workflow that `just lua::library`, `just lua::library-reload`, and `just reset` enable.

Without the devtools recipes, this workflow requires manually running `lua-doc-extractor`, manually copying files, manually cleaning up generated output, and remembering which paths to `git checkout` before committing. The justfile recipes make the loop a single command at each stage.

The underlying architecture (engine defines the API surface, game-side conforms to it via typed interfaces) is the [inversion of control](https://github.com/beyond-all-reason/RecoilEngine/pull/2664) proposed for the economy subsystem. The tooling demonstrated here is how contributors will iterate on that interface across both repos without generated artifacts polluting their commits.
