# Modules: reference

Every word the builder gives you, grouped by the file you write it in. [README.md](README.md) is the walkthrough; this is the lookup.

## Declaring a policy

A policy file declares what it builds, above the rules: the context, the result, the policy's steps as a typed enum, and the shape the steps combine in. The declaration is a lexical scope that reads top to bottom, each member typed and named explicitly. [The declaration](README.md#the-declaration) in the README walks a complete one line by line. The step enum is the promise: a name in it is a step on the policy, or load fails. That holds for the owner's own steps and for anything declared with `Contributes`.

A module's contract is what its policy files return, stamped by the loader with the module's name; the type `XContract` is built up the same way, one `---@class (partial) XContract` per file. There is no contract file.
```lua
---@class (partial) DefsContract
---@field UnitDef DefsUnitDefPolicy

---@type DefsUnitDefPolicy
local UnitDef = { Base = "Base" }
Policy.Fold(UnitDef)
…
return { UnitDef = UnitDef }
```

**`Single(steps)`**

<sub>Type: `steps → PolicySteps<C, T>`</sub>

A single policy answers one question once. Most policies are this.
* Guards (If/Unless) come first and can only refuse.
* Then Answers, in order; the first one that returns a value is the result, and one that returns nil passes to the next. 
* A guard refusal, or every Answer declining to provide a value, returns the Refusal if the owner declared one and `false` if not.

```lua
Policy.Single(Load) -- under the typed local

Policies.On(Load) -- the rules
	.Refusal(function() return false end)
	.Unless(Load.Submerged, isUnderwater) -- true refuses
	.If(Load.WithinReach, isClose) -- false refuses
	.Answer(Load.Allowed, function() return true end) -- the first non-nil Answer is the result
```

**`Product(steps)`**

<sub>Type: `steps → PolicySteps<C, number>`</sub>

A product policy multiplies each Factor's return value together and that is the result. Any module can add a step, and they stack. A Factor can return nil to contribute nothing. Only Factors are allowed; the loader refuses a guard or an Answer by name. If no step returns a number at all, the policy has nothing to return and throws at runtime.
```lua
Speed = Policy.Product(Speed) -- in the contract

Policies.On(Speed) -- in a policy: 0.5 × 0.75 × 1.25
	.Factor(Speed.Base, function() return 0.5 end)
	.Factor(Speed.Cargo, function() return 0.75 end)
	.Factor(Speed.Boost, function() return 1.25 end)
```

**`Fold(steps)`**

<sub>Type: `steps → PolicySteps<C, C>`</sub>

A fold policy runs every Apply, in order, on the same context, and returns that context. An Apply edits it in place and returns nothing. Only Applies are allowed; the loader refuses a guard or an Answer by name. Nothing refuses and nothing ends early. Use it for post-processing, where every unit def goes through every step.
```lua
UnitDef = Policy.Fold(UnitDef) -- in the contract

Policies.On(UnitDef) -- in a policy: both run, on the same def, in this order
	.Apply(UnitDef.Base, function(ctx) ctx.def.health = ctx.def.health * 1.1 end)
	.Apply(UnitDef.Scavenger, function(ctx) ctx.def.name = "scav_" .. ctx.def.name end)
```

**`Facts(names)`**

<sub>Type: `names → PolicyFacts<C>`</sub>

Not a policy. The facts a decision reads, which other modules may fill before the policy is asked. A fact informs a decision; it is not the decision. One fact, three files:
```lua
-- transfer/policies/team_terms.lua: the fact, declared and typed by its owner
---@class TransferTeamTermsFacts: PolicyFacts<TransferTeamContext>
---@field TaxRate "taxRate"
---@type TransferTeamTermsFacts
local TeamTerms = { TaxRate = "taxRate" }
Policy.Facts(TeamTerms)

-- the same file: what it means when nobody else answers
Policies.On(TeamTerms).Default(TeamTerms.TaxRate, function(ctx)
	return Tax.ModOption(ctx.modOptions)
end)

-- tech/policies/tech_blocking.lua: live under Tech Core, and the rate follows the team's tier
local Transfer = Policies.Contract(Modules.Transfer)
Policies.On(Transfer.TeamTerms).Provide(Transfer.TeamTerms.TaxRate, function(ctx)
	local level = tonumber(ctx.springRepo.GetTeamRulesParam(ctx.teamId, "tech_level")) or 1
	return TechTier.resolveByTechLevel(ctx.opts, "tax_resource_sharing_amount", level)
end)
```
Transfer never learns that tech exists. The mode says whose answer is live.

**`Contributes(target, names)`**

<sub>Type: `(PolicySteps, names) → names`</sub>

The steps this module adds to another module's policy, named here so a third module can place a rule against them by reference. A declared name that never lands is a load error.
```lua
---@type DefsContract
local Defs = Policies.Contract(Modules.Defs)

---@type TransportDefsUnitDefSteps
local UnitDef = { EnemyTransport = "EnemyTransport" }
Policy.Contributes(Defs.UnitDef, UnitDef)
```

**`---@class XContext`**

<sub>Type: `C`</sub>

The [context](README.md#what-flows-through-it) as a type, declared beside the steps, so `ctx` is typed inside every predicate without an annotation on the predicate.
```lua
---@class DefContext
---@field def table
```

## In a policy file

A policy file runs with one extra name in scope, `Policies`, bound to a registrar for that load. It builds policies, and returns the steps it declared (`return { Check = Check }`), which the loader stamps with the module and adds to the module's contract; a file that only contributes to other modules' policies still returns what it declared with `Contributes`. Two files of one module declaring the same member is a load error.

**`Policies.On(steps)`**

<sub>Type: `PolicySteps<C, T> → PolicyChain<C, T>` · `PolicyFacts<C> → PolicyEnrichment<C>`</sub>

Opens a chain against a policy's steps: the owner's own, or the steps this module declared with `Contributes`, which the loader files under the policy they contribute to. Open on your own steps when their context is typed more narrowly than the owner's.
```lua
Policies.On(Load) -- transport's own
Policies.On(RegionsNames) -- start's steps on regions' Names, typed over StartRegion
```

**`Policies.Contract(Modules.X)`**

<sub>Type: `Modules → Contract`</sub>

Another module's contract: what its policy files return, one table, loaded on demand. Two modules whose policy files ask for each other is a load error naming both. Annotate the local with the module's contract class, which the declaring files build up with `---@class (partial)`.
```lua
---@type RegionsContract
local Regions = Policies.Contract(Modules.Regions)
Policies.On(Regions.CheckSet).Apply(RegionsSet.AreasDisjoint, function(ctx) ... end)
```

**`.Unless(step, fn)`**

<sub>Type: `(step, C → bool) → Step<C, T>`</sub>

A guard that can only refuse. True refuses, false passes. It never says yes, so a mod adding one can only tighten. The predicate answers the step's name: unless submerged.
```lua
.Unless(load.Submerged, function(ctx) return ctx.goalY + ctx.height < 0 end)
```

**`.If(step, fn)`**

<sub>Type: `(step, C → bool) → Step<C, T>`</sub>

The same guard inverted: false refuses, true passes. If within reach.
```lua
.If(load.WithinReach, function(ctx) return ctx.distance <= ctx.reach end)
```

**`.Answer(step, fn)`**

<sub>Type: `(step, C → T?) → Step<C, T>`</sub>

Single only. The only step that can answer: returns the policy's result, or nil to pass to the next step. If every Answer declines, the policy refuses: nothing said yes is a no. A Single policy always ends in one.
```lua
.Answer(load.Allowed, function() return true end)

local function terms(ctx, canShare)
	return { canShare = canShare, stunSeconds = ctx.stunSeconds }
end

-- above the guards, an Answer is an exemption: nil is "not my case, keep going"
.Answer(unitTransfer.Cheating, function(ctx)
	if ctx.isCheatingEnabled then
		return terms(ctx, true)
	end
end)
```

**`.Factor(step, fn)`**

<sub>Type: `(step, C → number?) → Step<C, number>`</sub>

Product only. Returns a multiplier, or nil to contribute nothing. The loader refuses it on any other kind of policy, by step name.
```lua
.Factor(loadedSpeed.CommanderDrag, function(ctx) return ctx.carriesCommander and 0.5 or nil end)
```

**`.Apply(step, fn)`**

<sub>Type: `(step, C → ()) → Step<C, C>`</sub>

Fold only. Runs on the context, edits it in place, returns nothing. The loader refuses it on any other kind of policy, by step name.
```lua
.Apply(UnitDef.Base, function(ctx) base().UnitDef_Post(ctx.name, ctx.def) end)
```

**`.Refusal(fn)`**

<sub>Type: `C → T`</sub>

What a no looks like, declared once by the owner, wherever the no happens: a guard refusing, or every Answer declining. Instead of a bare `false`, a shape a widget can draw and a caller can act on.
```lua
.Refusal(function(ctx) return terms(ctx, false) end) -- the record a grant gets, with canShare flipped
```

**`.Before(step)`, `.After(step)`**

<sub>Type: `Step → Step`</sub>

Where the step just added goes. Without either, a new step joins the end of the checks, just before the answer.
```lua
-- the mod from above: tanks are refused before transport even looks at the water
.Unless(Load.TanksStayOnTheGround, isTank).Before(Transport.Load.Submerged)
```

**`.When(fn)`**

<sub>Type: `(C → bool) → Step`</sub>

A precondition on the step just added: it runs only when this holds. Otherwise the step steps aside rather than deciding: an Apply does nothing, an Answer or a Factor passes to the next, a guard holds. This is how a step that belongs to one region type sits on a policy that runs for every type, and it is why a contributor opens the chain on its *own* steps: they are typed over the contributor's region, and the loader files the chain under the policy they contribute to.
```lua
-- modules/start/policies/regions.lua: typed over StartRegion, run for starts only
Policies.On(RegionsNames)
	.Apply(RegionsNames.FromTeam, function(ctx)
		for i, region in ipairs(ctx.regions) do -- StartRegion[], no cast
			ctx.proposed[i] = tostring(region.team)
		end
	end)
	.When(RegionsApi.OfType(RegionsApi.Enums.Types.Start))
```

**`.Replace(step, fn)`**

<sub>Type: `(step, C → T?) → Step<C, T>`</sub>

Swap the closure under an existing name, keeping its position.
```lua
.Replace(load.MovingEnemy, function() return false end) -- a mod that lets you nap a moving enemy
```

**`.Remove(step)`**

<sub>Type: `Step → ∅`</sub>

Drop an existing step.
```lua
.Remove(load.AlliedNano) -- allied nano turrets may be carried after all
```

Every step is a name in a contract: the owner's from its own steps, anyone else's from what its contract declares with `Contributes`. A string typed inline is refused at load, naming the file and the contract it should have gone in.

## On a facts chain

Facts are filled before a policy is asked, not decided inside it. Anyone may provide one; the owner must default every one it declares.

**`Policies.On(facts)`**

<sub>Type: `PolicyFacts<C> → PolicyEnrichment<C>`</sub>

Opens a provider chain against a contract's facts.
```lua
Policies.On(Transfer.TeamPairing) -- another module's facts; or the owner's own, Policies.On(TeamPairing)
```

**`.Provide(fact, fn)`**

<sub>Type: `(fact, C → V?) → Provision<C>`</sub>

Answers a fact, per ask, from the context. Nil declines and the next live provider or the Default answers.
```lua
.Provide(Transfer.TeamPairing.TaxRate, function(ctx) return tieredRate(ctx) end)
```

**`.Default(fact, fn)`**

<sub>Type: `(fact, C → V) → Provision<C>`</sub>

The owner's answer when no live module provides, for a fact that has to be computed. A fact with no Default is the context's field of its name: the api gathered the engine's answer under that name, and nobody knowing better, that is the fact. Most facts are that; a Default is for the rest.
```lua
.Default(TeamTerms.TaxRate, function(ctx) return Tax.ModOption(ctx.modOptions) end)
```

## In a gadget, widget or lib

What a module's `api.lua` is written with. You call these when you are writing an api or a lib, not a gadget; [How a gadget asks](README.md#how-a-gadget-asks) is the path a gadget takes.

**`Modules.X`**

<sub>Type: `string`</sub>

A module by name, from [`modules/enums.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/enums.lua). Code never names a module by string.
```lua
local Modules = require("modules/enums").Modules
```

**`ModuleHandler.Contract(Modules.X)`**

<sub>Type: `Modules → Contract`</sub>

The module's contract as the loader assembled it: what its policy files return. For api, gadget and spec code that needs a facts table or a step enum; a policy file uses `Policies.Contract` instead.
```lua
---@type StartContract
local Start = ModuleHandler.Contract(Modules.Start)
```

**`ModuleHandler.Evaluate(steps, ctx, ...)`**

<sub>Type: `(PolicySteps<C, T>, C) → T | false`</sub>

Asks. The step enum from the contract names the policy; the loader finds what it assembled for that identity, every contributor's steps placed, and runs it under the contract's strategy. Returns the result, or the refusal. The result is the `T` the enum declared: a boolean for transport's load, the `UnitTransferTerms` record for transfer's unit transfer. A refusal has the same shape, so the caller reads one set of fields either way. `ctx` and the return are typed from the enum; no annotation at the call.
```lua
-- modules/transfer/unit/synced.lua
local grant = ModuleHandler.Evaluate(ModuleHandler.Contract(Modules.Transfer).UnitTransfer, ctx)
if grant.canShare then
	applyStun(unitID, grant.stunSeconds)
end
```

**`ModuleHandler.Steps(steps)`**

<sub>Type: `PolicySteps<C, T> → AssembledPolicy<C, T>`</sub>

The assembled policy itself, for a caller that reads its steps rather than running it: a spec asserting the order, a tool listing them. `Evaluate` takes this too.
```lua
for _, step in ipairs(ModuleHandler.Steps(ModuleHandler.Contract(Modules.Construction).Build)) do
	names[#names + 1] = step.name
end
```

**`ModuleHandler.Enrich(facts, ctx, ...)`**

<sub>Type: `(PolicyFacts<C>, C) → { [fact]: V }`</sub>

Fills a module's facts for one ask: the live providers answer, nil declines, the Default fills the rest. Every facts context is a `PolicyContext`: it carries the match's `modOptions`, read once by whoever builds it, and the live set is read off them.
```lua
-- modules/transfer/resource/tax.lua: whose rate this is, tech's or the modoption's, is the mode's business
local ctx = { teamId = teamId, modOptions = opts, springRepo = springRepo }
local TeamTerms = ModuleHandler.Contract(Modules.Transfer).TeamTerms
local terms = ModuleHandler.Enrich(TeamTerms, ctx)
local rate = tonumber(terms[TeamTerms.TaxRate])
```

**`ModuleHandler.LoadActions(Modules.X)`**

<sub>Type: `Modules → { byName, list }`</sub>

The module's actions by name. `api.lua` fronts this: validate, then execute, and nothing reaches execute around it.
```lua
ModuleHandler.LoadActions(Modules.Transfer).byName.units
```

**`ModuleHandler.State(Modules.X)`**

<sub>Type: `Modules → table`</sub>

The module's one in-memory table per Lua state. Called only from the module's `state.lua`, which declares its class and returns it. see below.

**`Published.PerTeam(key, fields)`**

<sub>Type: `(string, { [field]: wireType }) → PublishedRecord`</sub>

A per-team record synced writes and either side reads: one team rules param, the fields declared once with their wire types (`String`, `Number`, `Boolean`, `List`). `Write` from synced serializes it onto the param and fires `Published.EVENT` when it changed since the last write, so a widget hears about a change instead of polling; an optional list of field names narrows what counts as a change. `Read` on either side gives the record back typed, or nil where nothing was published.
```lua
-- modules/transfer/unit/shared.lua
Shared.UnitFactor = Published.PerTeam("unit_transfer_factor", {
	sharingModes = Published.List,
	active = Published.Boolean,
})

-- synced, per team, on each refresh
Shared.UnitFactor.Write(Spring, teamID, { sharingModes = modes, active = active })

-- either side
local factor = Shared.UnitFactor.Read(Spring, teamID) -- { sharingModes = {...}, active = true } or nil
```

**`Actions.RegisterValidate(fn)`, `Actions.RegisterExecute(fn)`**

<sub>Type: `(request → bool, string?)` · `(request → result)`</sub>

In an action file: the pure precondition over the request, and the one effectful function. Validate must come first; execute is required.
```lua
Actions.RegisterValidate(function(request)
	if not request.grant.canShare then
		return false, "the active mode does not allow unit transfer between these teams"
	end
	return true
end)

Actions.RegisterExecute(function(request)
	for _, unitID in ipairs(request.validation.validUnitIds) do
		Spring.TransferUnit(unitID, request.to, true)
	end
	return { success = true }
end)
```
<sub>Example: [`modules/transfer/actions/units.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transfer/modules/transfer/actions/units.lua)</sub>

```lua
-- modules/defs/state.lua, whole
local ModuleHandler = require("modules/module_handler")
local Modules = require("modules/enums").Modules

---@class DefsState
---@field alldefs table|nil gamedata/alldefs_post.lua, included on first use
local state = ModuleHandler.State(Modules.Defs) ---@type DefsState

return state
```

Readers include `state.lua`, never call `State` themselves, and get the class:

```lua
local state = require("modules/defs/state")
if state.alldefs == nil then
	state.alldefs = require("gamedata/alldefs_post")
end
```

