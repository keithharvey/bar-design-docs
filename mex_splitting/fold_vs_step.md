# The unit def fold, two ways

The same feature, end to end, in real code: every unit def passes through the base game's post-processing, then transport writes `transportbyenemy` onto it, then tech cheapens T2 labs and puts the Keystone in T1 constructor menus. Three modules, one chain, no module knowing the others exist.

Left column is the tree as it stands (`modules/defs/policies/unit_def.lua`, `modules/transport/policies/defs.lua`, `modules/tech/policies/defs.lua`, the hook in `gamedata/unitdefs_post.lua`, the fold branch of `ModuleHandler.Evaluate`). Right column is the same feature with one policy kind and one verb: `Step` returns from the chain when non-nil, `Return` is the owner's last step, `Before` places a step, data travels on `ctx`. Nothing on the right is pseudocode; it is what the files would be.

## The owner: defs

### Today, `Policy.Fold`

```lua
---@class DefContext
---@field name string
---@field def table
---@field modOptions table

---@class DefsUnitDefPolicy: PolicySteps<DefContext, DefContext>
---@field Base "Base"

---@type DefsUnitDefPolicy
local UnitDef = {
	Base = "Base",
}
Policy.Fold(UnitDef)

Policies.On(UnitDef).Apply(UnitDef.Base, function(ctx)
	require("modules/defs/lib/base").Base().UnitDef_Post(ctx.name, ctx.def)
end)

---@class (partial) DefsContract
local Contract = {}
Contract.UnitDef = UnitDef
return Contract
```

### One kind, `Step` and `Return`

```lua
---@class DefContext
---@field name string
---@field def table
---@field modOptions table
---@field result table the def, as the chain leaves it -- T, grafted onto C

---@class DefsUnitDefPolicy: PolicySteps<DefContext, table>
---@field Base "Base"
---@field ReturnResult "ReturnResult"

---@type DefsUnitDefPolicy
local UnitDef = {
	Base = "Base",
	ReturnResult = "ReturnResult",
}
Policy.Single(UnitDef)

Policies.On(UnitDef)
	.Step(UnitDef.Base, function(ctx)
		require("modules/defs/lib/base").Base().UnitDef_Post(ctx.name, ctx.def)
		ctx.result = ctx.def
		-- returns nothing: a return here would end the chain before anyone else ran
	end)
	.Return(UnitDef.ReturnResult, function(ctx)
		return ctx.result
	end)

---@class (partial) DefsContract
local Contract = {}
Contract.UnitDef = UnitDef
return Contract
```

What the owner now has to know: that it is the last step, that nothing before it may return, and that the result must be copied onto the context so the sentinel can hand it back. `ReturnResult` must be owner-only and last, which is a rule the loader has to hold either way.

## A contributor: transport

### Today

```lua
---@type DefsContract
local Defs = Policies.Contract(Modules.Defs)

---@class TransportUnitDefSteps: PolicySteps<DefContext, DefContext>
---@field EnemyTransport "EnemyTransport"

---@type TransportUnitDefSteps
local UnitDef = {
	EnemyTransport = "EnemyTransport",
}
Policy.Contributes(Defs.UnitDef, UnitDef)

local TransportEnemy = TransportEnums.TransportEnemy

Policies.On(UnitDef).Apply(UnitDef.EnemyTransport, function(ctx)
	local which = ctx.modOptions[TransportEnums.ModOptions.TransportEnemy]
	if which == TransportEnemy.None then
		ctx.def.transportbyenemy = false
	elseif which == TransportEnemy.NotCommanders and ctx.def.customparams.iscommander then
		ctx.def.transportbyenemy = false
	end
end)
```

### One kind

```lua
---@type DefsContract
local Defs = Policies.Contract(Modules.Defs)

---@class TransportUnitDefSteps: PolicySteps<DefContext, table>
---@field EnemyTransport "EnemyTransport"

---@type TransportUnitDefSteps
local UnitDef = {
	EnemyTransport = "EnemyTransport",
}
Policy.Contributes(Defs.UnitDef, UnitDef)

local TransportEnemy = TransportEnums.TransportEnemy

Policies.On(UnitDef)
	.Step(UnitDef.EnemyTransport, function(ctx)
		local which = ctx.modOptions[TransportEnums.ModOptions.TransportEnemy]
		if which == TransportEnemy.None then
			ctx.result.transportbyenemy = false
		elseif which == TransportEnemy.NotCommanders and ctx.result.customparams.iscommander then
			ctx.result.transportbyenemy = false
		end
		-- returns nothing, or tech never runs and the def is never returned
	end)
	.Before(Defs.UnitDef.ReturnResult)
```

What transport now has to know: the owner's sentinel by name, that its step must sit before it, that the def it edits is `ctx.result` rather than `ctx.def` (or that the two are the same table, which is a fact about the owner's `Base` step it has no way to see), and that it must not return.

## A contributor: tech

### Today

```lua
---@type DefsContract
local Defs = Policies.Contract(Modules.Defs)

---@class TechUnitDefSteps: PolicySteps<DefContext, DefContext>
---@field TechBlocking "TechBlocking"

---@type TechUnitDefSteps
local UnitDef = {
	TechBlocking = "TechBlocking",
}
Policy.Contributes(Defs.UnitDef, UnitDef)

Policies.On(UnitDef).Apply(UnitDef.TechBlocking, function(ctx)
	if ctx.modOptions[TechEnums.ModOptions.TechBlocking] then
		TechDefs.Apply(ctx.name, ctx.def)
	end
end)
```

### One kind

```lua
---@type DefsContract
local Defs = Policies.Contract(Modules.Defs)

---@class TechUnitDefSteps: PolicySteps<DefContext, table>
---@field TechBlocking "TechBlocking"

---@type TechUnitDefSteps
local UnitDef = {
	TechBlocking = "TechBlocking",
}
Policy.Contributes(Defs.UnitDef, UnitDef)

Policies.On(UnitDef)
	.Step(UnitDef.TechBlocking, function(ctx)
		if ctx.modOptions[TechEnums.ModOptions.TechBlocking] then
			TechDefs.Apply(ctx.name, ctx.result)
		end
	end)
	.Before(Defs.UnitDef.ReturnResult)
```

`TechDefs.Apply` is the function that cheapens the labs and injects the Keystone; it is the same in both columns. Note what `TechDefs.Apply(name, def)` would do if a future author wrote `return TechDefs.Apply(...)` out of habit, as Lua authors do: under the fold, the return is ignored. Under one kind, the chain ends there, the def is returned early, and whichever module sorts after tech never runs for any unit. No error. The lab is cheaper and the next module's feature is silently off.

## The hook, `gamedata/unitdefs_post.lua`

### Today

```lua
for name, unitDef in pairs(UnitDefs) do
	ModuleHandler.Evaluate(
		ModuleHandler.Contract(Modules.Defs).UnitDef,
		{ name = name, def = unitDef, modOptions = modOptions }
	)
end
```

### One kind

```lua
for name, unitDef in pairs(UnitDefs) do
	local result = ModuleHandler.Evaluate(
		ModuleHandler.Contract(Modules.Defs).UnitDef,
		{ name = name, def = unitDef, modOptions = modOptions }
	)
	-- result is unitDef by identity, or nil if some step returned early; nothing here can tell which
end
```

## The loader

### Today, the whole fold branch of `Evaluate`

```lua
if policies.result == "fold" then
	for _, policy in ipairs(policies) do
		policy.evaluate(ctx)
	end
	return ctx
end
```

Six lines. Plus the declaration check that `Apply` is the only verb a fold accepts and that it returns nothing, which is what makes mistake 1 below an error at load instead of a silent skip at runtime.

### One kind

Those six lines are gone. Nothing is added to the loader. Everything they did is now a convention held by every contributor, listed below.

## What the one-kind version asks of every contributor, forever

| the fold gives it | with one kind, every contributor must | if they forget |
|---|---|---|
| every step runs | return nothing from their step | the chain ends at their step, every module sorted after them is silently off for every unit |
| steps run in declared order, placement optional | write `.Before(Defs.UnitDef.ReturnResult)` on every step | their step lands after the return and never runs; no error |
| the context is the data | edit `ctx.result`, not `ctx.def`, or know the owner made them the same table | they edit the def and nothing is returned, or edit a copy and nothing changes; depends on the owner's `Base` |
| the result is the context | nothing | nothing |
| one `Return`, owner-only, last | the loader keeps a rule anyway | a contributor's `Return` becomes the answer |

The fold has none of these because it has no return, and a chain with no return has nothing to short-circuit on and no sentinel to miss.

## Count

Lines are the code blocks above, blank lines included, comments excluded from the second number.

| | today | one kind |
|---|---|---|
| owner file | 22 (10 code) | 31 (16 code) |
| transport's file | 22 (14 code) | 25 (16 code) |
| tech's file | 17 (10 code) | 19 (12 code) |
| the hook | 6 | 7 |
| the loader | 6 | 0 |
| conventions every future contributor keeps | 0 | 3 |

Six lines leave the loader. Fifteen arrive across four files that already exist, two or three more for every module that joins the chain later, plus the three rules its author has to know and the one failure mode that cannot be seen from any file.

## The reverse graft, for completeness

A `Single` written as a fold is the other direction: every step runs even after one refuses, so a refusal is a flag on the context every later step checks before doing anything, and the caller reads the answer off the context after `Evaluate`. The load rule in transport has five guards. Each would open with `if ctx.refused then return end`, the owner's `Allowed` step would write `ctx.answer = true`, and `MayLoad` would read `ctx.answer` and `ctx.refused` instead of a boolean. The context stops being immutable, which is the thing `Single` is for, and a step that forgets the opening line runs on a refused context.
