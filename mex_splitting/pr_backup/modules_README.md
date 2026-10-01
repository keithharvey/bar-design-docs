# Modules

**A module** is a directory that answers questions for one concern, like "may this team hand that unit to this one."

**It decides with policies.**

* A **[policy](#why-this-is-easier-for-every-layer)** is one named decision: a pure function of its context, written as named steps, each of which can refuse, pass, or answer. Policy in the middleware sense: a request passes through handlers in order, and any handler may stop it.
* A **[policy file](#how-a-decision-flows)** is a file under `policies/` declaring policies and their rules, each opened with `Policies.On(...)`.
* A **[context](#what-flows-through-it)** is the plain table of facts the gadget hands the policy when it asks: who, where, what the engine and the modoptions say.
* A **[contract](REFERENCE.md#declaring-a-policy)** names every step and every fact, and the shape going in and coming out, so another module or a mod can say "put my step after this one" or "replace that one."

**It acts through [actions](#what-flows-through-it).** An action is the only effectful code in a module: a pure validate over a request, then one execute.

**It ships modes.** A mode is a preset of modoptions: which dials are set, locked, or hidden.

**It keeps what it must remember in [`state.lua`](REFERENCE.md#in-a-gadget-widget-or-lib)**, once per Lua state, and nowhere else.

**[REFERENCE.md](REFERENCE.md)** is the vocabulary: one entry per term, why it exists, and the smallest real example.

## If you have written a gadget

You already do all of this. Here is what each thing is called now.

| You do this today | In a module |
|---|---|
| An `Allow*` callin with a stack of `if`s | A policy. The api gathers the context and asks it. |
| An `if` that returns false | A guard: `Unless` refuses on true, `If` refuses on false. |
| The branch that returns true | An Answer. The first one that returns wins. |
| `return false` | The Refusal, one shape declared once by the owner. |
| A modoption read inside the rule | A fact with a Default. |
| Another gadget reaching into yours through `GG` | A fact it provides, or a step it contributes, from its own directory. |
| A copy of the rule in a widget, for the tooltip | The same result, read back. One rule. |
| `GG.Foo = function` cross calls | `api.lua`, typed at the call site. |
| Upvalue tables in a gadget | `state.lua`, one table per module. |
| `Spring.TransferUnit` inside the callin | An action: validate, then execute. |
| `if modOptions.x == ...` scattered across gadgets | A mode preset. |
| An edit in `alldefs_post.lua` | A step on defs' unit def fold. |

## The modules

Each module owns one concern:

| Module | Owns | Requires |
|---|---|---|
| `regions` | Contained space on the map, drawn as a point or a polygon: the shape, the rules every region type shares on one region and on the set, the name a region gets when it carries none, what is said about a region, and the layout codec, one table keyed by type. Regions knows shapes and nothing else: types are contributed by the modules that own them through a `region_types.lua`, each with its own record extending `Region` and its own steps on the set check, the naming and the description, reading what it needs off an `env` the asker passes through. The terraformer draws them through this api alone. | the runtime |
| `start` | A team's start as a region: its positions and the area they sit in, with its rule that no two areas share ground. Its facts default to the match's own startboxes and start positions, so an editor opens on what the map plays with. | regions |
| `defs` | Def post-processing as a policy every unit and weapon def pass, and where a module adds its own step. | the runtime |
| `game` | Which game this is: the game axis, one selector, the presets, the export the lobby reads. | the runtime |
| `transport` | Who may load and unload what, and how fast a loaded transport flies. The first module with real rules; the air transport rework builds on it. | defs |
| `construction` | What may be built, and by whom: assist, reclaim, resurrect, build delay, geo and mex upgrades. | the runtime |
| `economy` | How a shared pool is distributed. | the runtime |
| `transfer` | What may pass between allied teams: units, resources, take, and the tax on what flows. Mex Splitting: the mex region type with its rule that every metal spot is covered, and Map Assigned's deal of those regions and the spots in them to the teams seated at each start, which no ally may build on. | construction, economy, regions, start |
| `tech` | The keystones that raise a team's tier, and the tier as a fact construction and transfer read. Tech Core is its preset. | transfer, construction |
| `combat` | Damage, targeting and protection as a lifetime. | proposed |
| `placement` | Where a thing may legally stand, answered once. | proposed |
| `matchflow` | How and when a game ends. | proposed |

Modules land one at a time, each with its own contract, policies and specs; a proposed module is a concern with a name and no code yet.

## How a decision flows

A module answers questions. "May this team hand that unit to this one?" is one. The rule that answers it is a policy: a list of steps, run in order, where each step can refuse, pass the question on, or answer it. No step is the rule. The list is.

The contract is the module saying that out loud. It names each question the module answers, names every step in the order they run, and says what goes in and what comes out. It is not the rules; it is the table of contents for them. That is what lets another module, or a mod, say "put my step after that one" or "replace this one" without reading or touching the file the rules live in, and it is what lets the loader [refuse a wiring mistake at load](#what-the-loader-refuses), by name, rather than let it become a silent no in game.

So a policy file is two halves: the declaration that names the question, and the rules that answer it. Together, a module's declarations are its contract. We'll walk the rules first, because they are the part you read as a rule, and then the declaration above them that makes it explicit.

The module's api gathers facts and asks. The policy decides. The module's actions act. Here is transfer asking whether one team may hand a unit to another, trimmed from `context_factory.lua`:

```lua
local ctx = {
	senderTeamId = senderTeamID,
	receiverTeamId = receiverTeamID,
	springRepo = springRepo,
	areAlliedTeams = springRepo.AreTeamsAllied(senderTeamID, receiverTeamID) == true,
	isCheatingEnabled = springRepo.IsCheatingEnabled(),
}
return ModuleHandler.Evaluate(ModuleHandler.Contract(Modules.Transfer).UnitTransfer, ctx)
```

### The policy

The real file, trimmed to one policy and three steps.

```lua
-- modules/transfer/policies/unit_transfer.lua, the rules
---@param ctx TransferContext
---@param canShare boolean
---@return UnitTransferTerms
local function terms(ctx, canShare)
	return {
		canShare = canShare,
		stunSeconds = tonumber(ctx.springRepo.GetModOptions().unit_share_stun_seconds) or 0,
	}
end

Policies.On(UnitTransfer)
	.Refusal(function(ctx)
		return terms(ctx, false)
	end)
	.If(UnitTransfer.Allied, function(ctx)
		return ctx.areAlliedTeams
	end)
	.Unless(UnitTransfer.ReceiverHasNoPlayers, function(ctx)
		if ctx.isCheatingEnabled then
			return false
		end
		local numActivePlayers = ctx.springRepo.GetTeamRulesParam(ctx.receiverTeamId, "numActivePlayers")
		return tonumber(numActivePlayers) == 0
	end)
	.Answer(UnitTransfer.TransferTerms, function(ctx)
		return terms(ctx, true)
	end)

return { UnitTransfer = UnitTransfer }
```

Line by line.

```lua
local function terms(ctx, canShare)
```

A plain local function. Both the yes and the no below are built by it, so a refusal is the same shape as a grant with `canShare` flipped.

```lua
Policies.On(UnitTransfer)
```

Open the policy. Explicitly name what that's about: transferring a unit. That lets other modules add their own rules to this decision if they want to. `Policies` is not included from anywhere: the loader sets it for the duration of this file, then takes it away.

```lua
	.Refusal(function(ctx)
		return terms(ctx, false)
	end)
```

What a no looks like. Declared once, by the owner. Every guard below that refuses hands back this, and so does falling off the end with nobody having said yes. Without it a no is `false`, which is fine for a boolean policy and useless for a table one.

```lua
	.If(UnitTransfer.Allied, function(ctx)
		return ctx.areAlliedTeams
	end)
```

A **guard**. It reads the context and returns a boolean. `If` refuses on false, so if our teams are allied, this one moves on to the next step. Guards cannot say "yes" for our policy.

`UnitTransfer.Allied` is our step name: `Allied`, in this case. Remember that is done so that someone else can contribute their own step `.Before` it, `.Replace` it.

```lua
	.Unless(UnitTransfer.ReceiverHasNoPlayers, function(ctx)
		if ctx.isCheatingEnabled then
			return false
		end
		local numActivePlayers = ctx.springRepo.GetTeamRulesParam(ctx.receiverTeamId, "numActivePlayers")
		return tonumber(numActivePlayers) == 0
	end)
```

Same shape, a few more lines. Order is precedence: this only runs if `Allied` passed.

```lua
	.Answer(UnitTransfer.TransferTerms, function(ctx)
		return terms(ctx, true)
	end)
```

**Answer** is the only kind of step that can say yes. It returns the result, the same shape the Refusal returns. Return nil instead and it passes, and the next Answer gets a go. Run out of Answers and nothing said yes, which is a no.

```lua
return { UnitTransfer = UnitTransfer }
```

The file hands its steps to the loader, which files them under the module: this is how `ModuleHandler.Contract(Modules.Transfer).UnitTransfer` names this policy from a gadget, a widget, a spec or a mod, and reaching it that way runs no rules.

### Why this is easier for every layer

A Single policy is a function from a context to a result, `C → T`, built out of steps that are each a smaller function. What makes it a policy and not a list of functions is the rule for what happens *between* the steps: a guard that refuses stops everything and hands back the Refusal; an Answer that returns nil hands on; an Answer that returns a value stops everything and hands that back. That rule lives in `Evaluate`, once. No step checks what the previous step said. No step knows whether it is first, last, or the only one.

That is the whole of what a monad is, TLDR: a type, plus one rule for chaining functions over it, so the functions themselves never do the chaining. Here the type is "maybe a `T`" and the rule is "first value wins, a refusal on the way stops it". You do not need the word. You need what it buys:

- The gadget asks and gets a `T`. Never nil, never "check if it's false and then go find out why". The Refusal gave the no a shape.
- The action reads its grant as a `T`. Same table, no second ask.
- The widget draws a `T`. Same table, so the tooltip and the rule cannot disagree.
- The spec passes a context literal and asserts on a `T`. No engine, no gadget, no globals.
- A mod adds one step and never touches control flow, because there is no control flow in the steps to touch.

Every layer sees one shape going in and one shape coming out, and the only place the "what if it refused" question is answered is the one line that declares what a refusal is.

### The declaration

Everything the rules just used by name, declared above them in the same file.

```lua
-- modules/transfer/policies/unit_transfer.lua, the declaration
local Policy = require("modules/policy")

-- May this team give that one a unit, and on what terms
--
---@class TransferContext
---@field senderTeamId integer
---@field receiverTeamId integer
---@field springRepo Spring
---@field areAlliedTeams boolean
---@field isCheatingEnabled boolean

---@class UnitTransferTerms
---@field canShare boolean
---@field stunSeconds number

---@class TransferUnitTransferPolicy: PolicySteps<TransferContext, UnitTransferTerms>
---@field Allied "Allied"
---@field ReceiverHasNoPlayers "ReceiverHasNoPlayers"
---@field TransferTerms "TransferTerms"

---@class (partial) TransferContract
---@field UnitTransfer TransferUnitTransferPolicy

---@type TransferUnitTransferPolicy
local UnitTransfer = {
	Allied = "Allied",
	ReceiverHasNoPlayers = "ReceiverHasNoPlayers",
	TransferTerms = "TransferTerms",
}
Policy.Single(UnitTransfer)
```

Same again, line by line.

```lua
-- May this team give that one a unit, and on what terms
--
```

The question, in one line, as the player would ask it. The empty `--` under it is the seam: a file with two policies in it puts a header like this over each, so the eye finds where one ends.

```lua
---@class TransferContext
---@class UnitTransferTerms
```

The two types every policy has, written `<C, T>` everywhere else in this doc. `C` is what the gadget gathered up top. `T` is what `terms` built. `T` is a table here, not a boolean, because the gadget that stuns the unit and the widget that explains the stun in a tooltip both need the seconds, and they need them on a refusal too.

```lua
---@class TransferUnitTransferPolicy: PolicySteps<TransferContext, UnitTransferTerms>
---@field Allied "Allied"
---@field ReceiverHasNoPlayers "ReceiverHasNoPlayers"
---@field TransferTerms "TransferTerms"

---@type TransferUnitTransferPolicy
local UnitTransfer = {
	Allied = "Allied",
	ReceiverHasNoPlayers = "ReceiverHasNoPlayers",
	TransferTerms = "TransferTerms",
}
```

The three names the rules hung their steps on, twice: once as a type, once as the table. Lua has no reflection, so the table is what runs and the class is what the checker reads, and the class types each field as its own value so the checker holds the two together: a step left out of the table is a missing field, a misspelled value is a type error. The literal has to sit on the typed local directly; a table handed through `Policy.Single(...)` on the same line is never checked. At load the loader checks the other direction: a step added under a name not in this table is refused, and a name in this table that never lands on the policy is refused too. The declaration is a promise in both directions, and it is the only thing a mod needs to read to put its own step `.Before` yours.

```lua
---@class (partial) TransferContract
---@field UnitTransfer TransferUnitTransferPolicy
```

The module's contract, as a type, is the union of what its policy files declare; each file adds its members with `(partial)`, so `---@type TransferContract` on the table the loader hands back reads every policy the module has.

```lua
Policy.Single(UnitTransfer)
```

Single means one question, one answer: the first step that answers ends it. `Product` and `Fold` are the other two shapes, and `Facts` declares the facts a decision reads instead of a decision. The stamp goes on the table after the literal, on its own line, so the checker still sees the literal on the typed local.

The loader includes every file under `policies/`, stamps what each returns with the module's name, and the module's contract is the sum: one file per policy, its question, its context, its steps and its rules read top to bottom, and a module that fits in one file is one file. Another module reaches the sum with `Policies.Contract(Modules.Transfer)`; api and gadget code with `ModuleHandler.Contract(Modules.Transfer)`.

### What flows through it

**The context** is the `C` the declaration named: the one table the api gathers for this ask, read from the engine or cached on a cadence. It is the policy's only input, which is the purity the section above leans on: a spec hands in a table literal, and a widget reads the same fields the gadget acted on.

**Order is precedence.** A guard can only refuse, so "yes, regardless of the rest" is a matter of placement, not a verb. An Answer above `Allied` that grants when cheating is enabled reads: cheaters share with anyone; everyone else must be allied and sharing with a live team. As boolean logic, `cheating or (allied and receiverHasPlayers)`.

**The result** is the `T`: the seam between deciding and doing, and always a plain table, because the gadget that acts, the event it sends and the widget that draws all read the same one. Time rides on it too: the stun is seconds on the result, and the gadget counts the frames.

**The action.** An action executes a request: the command's parameters plus the result it was granted. `api.lua` gathers, runs validate, then execute, and an action never resolves its own grant. Transfer's unit action, trimmed:

```lua
Actions.RegisterValidate(function(request)
	if request.from == request.to then
		return false, "a team cannot share with itself"
	end
	if not request.grant.canShare then
		return false, "the active mode does not allow unit transfer between these teams"
	end
	return true
end)

Actions.RegisterExecute(function(request)
	for _, unitID in ipairs(request.validation.validUnitIds) do
		Spring.TransferUnit(unitID, request.to, true)
		applyStun(unitID, Spring.GetUnitDefID(unitID), request.grant)
	end
	return { success = true, validationResult = request.validation, policyResult = request.grant }
end)
```

If you have built this before as blockers, modifiers and listeners around an `AllowX` call, the mapping is exact. Blockers are `Unless` and `If`. Modifiers are facts, filled once, up front, with no "modify and re-query" loop. Listeners are not in the policy at all: they are whoever consumes the result.

### A mod

A mod, or another module, changes a decision by aiming the same builder at the owner's policy. This is the whole of a mod that stops tanks being transported. Transport's own file is untouched:

```lua
-- modules/notanks/policies/load.lua
local Modules = require("modules/enums").Modules
local Policy = require("modules/policy")

---@type TransportContract
local Transport = Policies.Contract(Modules.Transport)

-- A tank stays on the ground
--
---@class NoTanksTransportLoadSteps: PolicySteps<TransportLoadContext, boolean>
---@field TanksStayOnTheGround "TanksStayOnTheGround"

---@type NoTanksTransportLoadSteps
local Load = {
	TanksStayOnTheGround = "TanksStayOnTheGround",
}
Policy.Contributes(Transport.Load, Load)

Policies.On(Load).Unless(Load.TanksStayOnTheGround, function(ctx)
	local moveDef = ctx.passengerDef and ctx.passengerDef.moveDef
	return moveDef ~= nil and moveDef.name:lower():find("^tank") ~= nil
end)

return { Load = Load }
```

The step this mod adds is declared with `Contributes`, named where others can find it, and the chain opens on the mod's own steps; the loader files them under the policy they contribute to.

The owner's steps run first, other modules' follow in module-name order, and a new step joins just before the answer unless `.Before` or `.After` says otherwise. Guards compose with AND: anyone can add one, and adding can only tighten. Loosening a rule you do not own touches that rule, by name: `Remove` it, `Replace` it, or exempt from all of them with an Answer above. That asymmetry is deliberate. Tightening is safe to let anyone do blind; loosening is not.

### A fact

Where an owner expects loosening, it puts the knob on the context as a fact, so nobody has to `Replace` anything. Transfer declares the facts others may fill, and Tech Core, a module up the chain, fills one:

```lua
-- transfer/policies/team_pairing.lua: the facts, declared
---@type TransferTeamPairingFacts
local TeamPairing = { TechBlocking = "techBlocking", TaxRate = "taxRate" }
Policy.Facts(TeamPairing)

-- and transfer's own default: what the fact means when no live module fills it
Policies.On(TeamPairing).Default(TeamPairing.TaxRate, function(_, springRepo)
	return Tax.ModOption(springRepo.GetModOptions())
end)
```

```lua
-- tech/policies/tech_blocking.lua
local Transfer = Policies.Contract(Modules.Transfer)

Policies.On(Transfer.TeamPairing).Provide(Transfer.TeamPairing.TaxRate, function(ctx, springRepo, senderTeamID)
	return tieredRate(ctx, springRepo, senderTeamID)
end)
```

Two modules may both provide the same fact. The owner declares the fact and its type. When nobody provides, the fact is the context's field of its name, which the api gathered from the engine; a `Default` is only for a fact that has to be computed. Either way a mod _may_ provide one and never has to.

Modes say which module's provider is live. The loader refuses a preset combination that would leave two live for one fact; that is in the list below.

| React nerds | Everyone else |
|---|---|
| A fact is a derived value with a default, and the mode picks the selector. | Facts are _computed_. They are not variables, not storage, and not configuration, though a Default often reads one. Each ask hands them a context and gets back a value of the type the owner declared. |

### What the loader refuses

Everything that can go wrong in wiring is a load error that names the file:

- a directory under `modules/` with no `manifest.lua`, or a manifest whose name does not match its directory
- a step added under a name no policy declares
- a declared name that never lands on the policy, the owner's or a contributor's
- two modules adding the same step name
- a Single policy that does not end in an Answer
- a preset combination that leaves two providers live for one fact
- a policy or action file that returns a value, which the include shim would cache and the registration would be lost

There is no registry to add yourself to and no global to poke. Policies, defaults and presets are all read from files, so the lobby, the synced game and the widgets see the same set.

### How a gadget asks

A gadget does not ask a policy. It calls the module's `api.lua`, which gathers the context, asks, and runs the action. The policy runs once, in synced. Transfer's unit controller, the two places it touches the module:

```lua
-- modules/transfer/gadgets/game_unit_transfer_controller.lua
local TransferApi = require("modules/transfer/api")

function gadget:AllowUnitTransfer(unitID, unitDefID, fromTeamID, toTeamID, capture)
	return TransferApi.MayTransfer(unitID, fromTeamID, toTeamID, capture)
end

function gadget:RecvLuaMsg(msg, playerID)
	local params = LuaRulesMsg.ParseUnitTransfer(msg)
	local _, _, _, senderTeamID = Spring.GetPlayerInfo(playerID, false)
	TransferApi.Units(params.unitIDs, params.targetTeamID, senderTeamID)
end
```

The api is where the gathering lives. `Units` builds the request, and one `perform` runs validate then execute for every action the module has:

```lua
-- modules/transfer/api.lua
local function perform(name, request)
	local action = ModuleHandler.LoadActions(Modules.Transfer).byName[name]
	local allowed, reason = action.validate(request)
	if not allowed then
		Spring.Log("transfer", LOG.WARNING, "transfer." .. name .. " refused: " .. reason)
		return nil
	end
	return action.execute(request)
end

Units = function(unitIDs, toTeamID, fromTeamID)
	-- the api gathers; the action only reads its request
	local grant = UnitShared.GetCachedTerms(fromTeamID, toTeamID, Spring)
	return perform("units", {
		from = fromTeamID,
		to = toTeamID,
		unitIDs = unitIDs,
		grant = grant,
		validation = UnitShared.ValidateUnits(grant, unitIDs, Spring),
	})
end
```
<sub>Example: [`modules/transfer/api.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transfer/modules/transfer/api.lua) · [`modules/transfer/gadgets/game_unit_transfer_controller.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transfer/modules/transfer/gadgets/game_unit_transfer_controller.lua)</sub>

A widget never asks either. It has no synced state to gather from, so the synced side publishes the result and the widget reads it back. The runtime's `Published.PerTeam` is that hop: declare the record's fields once, `Write` it from synced and it lands on a team rules param with one change event, `Read` it back typed on either side. Transfer ships a second door, `unsynced.lua`, that reads its records back and sends requests as a `LuaRulesMsg` for the synced controller to re-validate.

```lua
-- what a widget includes
local Transfer = require("modules/transfer/unsynced")

local terms = Transfer.Units.GetCachedTerms(myTeamID, theirTeamID) -- read back, same UnitTransferTerms shape
Transfer.Units.ShareUnits(theirTeamID) -- the player's selection, as a message
```

`ShareUnits` is the whole request path, in three hops:

1. The widget side reads `Spring.GetSelectedUnits()`, packs the IDs with the target team, and sends them as a `LuaRulesMsg`.
2. The synced controller's `RecvLuaMsg` unpacks them, resolves the sender's team from the player, and calls `TransferApi.Units`.
3. The api gathers the grant and the validation, runs the action's validate, then execute. Nothing the widget sent is trusted before that.

<sub>Example: [`modules/transfer/unsynced.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transfer/modules/transfer/unsynced.lua) · [`modules/published.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/module-policies/modules/published.lua) · [`modules/transfer/gadgets/game_share_policy_forwarding.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transfer/modules/transfer/gadgets/game_share_policy_forwarding.lua)</sub>

## The layout

A module is one directory under `modules/`. The loader knows these files and folders and nothing else. Every entry is optional except the manifest.

**`manifest.lua`**

The manifest. Names the module (it must match the directory) and lists what it requires. No manifest, no module: any other directory under `modules/` is ignored. A `requires` entry that names no discovered module refuses the module, and whatever required it, with an error naming both.
```lua
return { name = "transport", description = "What a carrier may pick up, and how it flies loaded", requires = { "defs" } } -- [1]
```
<sub>[1] [`modules/transport/manifest.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/transport/manifest.lua)</sub>

**`policies/`**

The rules, and what they are about. One file per policy: the question as a comment, its context, its steps as a typed enum, the rules built with `Policies.On(...)`, and `return { Name = Steps }` so the loader files the steps under the module. A module's contract is the sum of what its policy files return, and `ModuleHandler.Contract(Modules.X)` is that sum. A file may instead build against another module's policy, reached with `Policies.Contract(Modules.Y)`, adding steps it declared with `Policy.Contributes`. Any file here is found; there is nothing to register. See [Declaring a policy](REFERENCE.md#declaring-a-policy).
<sub>Examples: [`modules/transport/policies/transport.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/transport/policies/transport.lua) against its contract; [`modules/regions/policies/check.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/mex-splitting/modules/regions/policies/check.lua) declaring its own</sub>

**`actions/`**

The only effectful code. One file per action, registering a pure `validate` and one `execute`. A policy decides, an action does.
<sub>Example: [`modules/transfer/actions/units.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transfer/modules/transfer/actions/units.lua)</sub>

**`state.lua`**

What the module keeps in memory, declared once as a class and anchored once per Lua state. A file-level table that is written after load lives here, never in a `local`: `VFS.Include` is uncached, so a local is one copy per includer. See [In a gadget, widget or lib](REFERENCE.md#in-a-gadget-widget-or-lib).
<sub>Example: [`modules/defs/state.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/defs/modules/defs/state.lua)</sub>

**`api.lua`**

What other modules and the game's own files call. Included directly, `require("modules/defs/api")`, so it is typed at the call site.
```lua
local Defs = require("modules/defs/api")
Defs.PrebakeUnitDefs() -- [1], called from [2]
```
<sub>[1] [`modules/defs/api.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/defs/modules/defs/api.lua) · [2] [`gamedata/unitdefs_post.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/defs/gamedata/unitdefs_post.lua)</sub>

**`lib/`**

The module's own helpers. Ordinary include paths, no loader involvement.

<sub>Example: [`modules/defs/lib/base.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/defs/modules/defs/lib/base.lua)</sub>

**`enums.lua`**

The module's names as values, so nothing refers to them by string. [`modules/enums.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/enums.lua) at the root is the enum of modules themselves.
```lua
Modules.Defs -- [1]
TransportEnums.ModOptions.CommanderTransportSlow -- [2]
```
<sub>[1] [`modules/enums.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/enums.lua) · [2] [`modules/transport/enums.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/transport/enums.lua)</sub>

**`modes/`**

Presets, one file each, written in the mode grammar. A preset makes the module that ships it live.
<sub>Example: [`modules/game/modes/ffa.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/game/modules/game/modes/ffa.lua)</sub>

**`mode_verbs.lua`**

The verbs this module adds to another module's mode grammar, each a `ModeBuilder.Verb(parse, write)`: how a preset writes the claim, and the modoptions it becomes. The loader hands them to the axis's grammar, so a preset claims this module's options in this module's words.
<sub>Example: [`modules/transport/mode_verbs.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/transport/mode_verbs.lua)</sub>

**`modoptions.lua`**

The module's fragment of the game's options. The root `modoptions.lua` appends every module's fragment, so a module that ships options needs no change to the root file.
<sub>Example: [`modules/game/modoptions.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/game/modules/game/modoptions.lua)</sub>

**`gadgets/`, `widgets/`, `rml_widgets/`, `scripts/`**

The game's own kinds of file, loaded the way the game already loads their loose equivalents. Gadgets and widgets are added to the handler's list; unit scripts join the script loader's registry under their `modules/` path.
<sub>Example: [`modules/transport/gadgets/transport_rules.lua`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/transport/modules/transport/gadgets/transport_rules.lua)</sub>

Every file under `modules/` is loaded by the game's own handlers, in the same Lua state as the loose file it stands beside, with the same VFS mode. Synced code sees the archive only.

## What to keep

- A module is an opinionated directory that encapsulates game behavior.
- A policy file declares decisions, each one a policy.
- A policy is one chain of named steps, each a guard or an Answer, with one Refusal saying what a no looks like. On a Product the steps are Factors; on a Fold, Applies.
- Read a policy top to bottom, and place your step where the precedence says. No step is the rule; the chain is.
- A guard can only refuse, and only an Answer can answer. Loosening touches the rule by name; tightening never does.
- Facts inform a decision and are filled before it runs; an Answer makes the decision. The mode decides whose fact is live.
- The contract is the map: every step and every fact is a name there, and every wiring mistake is a load error that points at it.
- A gadget is the engine's callin and nothing more: it hands the ids to the api, which gathers, asks and acts. State a module must keep lives in `state.lua`, once per Lua state.

## Game

`mode_builder` turns a preset file into a ModeConfig. It has no runtime of its own; each module binds its own vocabulary over it, and preset files read as a dot-only chain. A preset is a whitelist: it claims the options it needs and says which are shown, hidden or locked, and the lobby shows exactly what it claims.

### In a preset

Every verb is documented where the editor shows it, `modules/game/types/mode_policy.lua`, with the option it writes. The ones every module shares:

| Thing | Why | Example |
|---|---|---|
| `Mode(name)` | Starts a preset. The category is not a parameter: the grammar binds every chain from a module to that module's axis, and the name only names it. | `return Mode("FFA")` |
| `.Desc(text)` | The sentence the lobby shows under the mode's name. | `.Desc("Free for all: every player for themselves.")` |
| `.Ranked()` | Whether the mode may count for rating. Never saying it means unranked, and the pin is written either way, so the lobby never has to pin it itself. | `.Ranked()` |
| a claim verb | Writes one option. Verbs that pick from a list take an enum, not a string. A bare claim is a suggestion and leaves its option open. | `.End(DeathMode.OwnCommander)`, `.MaxUnits(2000)` |
| `.Locked()` | Pins the last claim's noun; its dials stay editable. | `.Wreckage(true).Locked()` |
| `.Sealed()` | Pins the last claim outright, dials included. | `.UnitRestrictions().Sealed()` |
| `.Hidden()` | Keeps the last claim out of the lobby UI; its pin still applies. | `.FogOfWar(true).Hidden()` |
| `.Unlocked()` | The last claim is fully editable. Rule verbs come back pinned, so this is how a preset opens one. | `.Allow(Transfer.Units).Unlocked()` |
| `.Uses(Modules.X)` | A module whose fact providers this preset makes live, besides the one that ships it. | `.Uses(Modules.Tech)` |
| `.RetainValues()` | A non-sticky preset: picking it exposes and unlocks its claims but keeps the current values as the starting point. | `.RetainValues()` |

The FFA preset, whole:

```lua
local ModeDSL = require("modules/game/mode_dsl")
local Mode = ModeDSL.Mode
local DeathMode, DraftMode, AnonymousMode = ModeDSL.DeathMode, ModeDSL.DraftMode, ModeDSL.AnonymousMode

return Mode("FFA")
	.Desc("Free for all: every player for themselves. Losing your commander resigns you, and the fallen leave wreckage behind.")
	.Ranked()
	.End(DeathMode.OwnCommander)
	.Wreckage(true).Locked()
	.MaxUnits(2000)
	.Draft(DraftMode.Random)
	.Anonymous(AnonymousMode.Disabled)
	.EnemyTransporting(TransportEnemy.NotCommanders)
	.UnitRestrictions()
```

### The game axis

A match is exactly one way of being played, so there is one selector, `game_mode`, owned by the mode infrastructure rather than any flavor. The presets are Standard, FFA, Team FFA and Territorial Domination.

- Section entries in a module's `modoptions.lua` can declare `mode_category` (which axis governs their options) and `mode_key` (which preset reveals them).
- A module adds verbs to an axis's grammar by shipping `mode_verbs.lua`: `{ category = "game", verbs = { Name = ModeBuilder.Verb(parse, write) } }`. The loader hands them to the axis's grammar, so a preset claims the module's options in the module's own words and the grammar never names the module.
- The root `modoptions.lua` appends every module's fragment through `ModuleHandler.ModOptions()`, so a module that ships options needs no change to the root file.
- `modules/game/lib/values.lua` is the one formatter for a mode value on the wire (booleans as `1`/`0`, numbers at float32 precision). The export widget bakes `modes.json` with it and the lobby includes it out of the game archive, so neither side carries a copy. `tools/headless_testing/startscript_modes_export.txt` runs that export headless.
- A preset says what it makes live. The runtime walks every combination of presets at load and refuses one that leaves two providers live for one fact.
