That "expanding or contracting a subset of Lua" was doing a lot of work in the video, so I did iterate on the language server a bit to make that more true. It is just a tree walker validating what we hand it now.

In vscode, standard Lua will error in the vscode plugin at the moment:
[math.floor error screenshot]

I wanted to validate that the plugin would surface the subset edge for users (and serve actually enforces it), but that's basically the end of the plugin's job. Is this construct in the subset the game itself publishes?

The game side white list is just Lua. Here is `modules/missions/types/dsl_env.lua`
```lua
---@meta mission_dsl

---Start a trigger chain with its arming condition. Chain more conditions
---with .When(...), effects with .Do(...), behavior with .Once(...).
---@param condition MissionCondition
---@return TriggerChain
function When(condition) end

---Objective handle: .Complete() builds the effect side, .IsComplete() the
---condition side.
---@param name ObjectiveName
---@return MissionObjective
function Objective(name) end
...
```

Of interest here is the comment decorator `---@meta mission_dsl`. That decorator is a similar pattern to what lua-doc-extractor uses over in Recoil docs during CI generation. It's a code contract between BAR and our language server that "this file IS your DSL surface". Any `types/*.lua* declaring `---@meta mission_dsl` joins the surface - that's how modules publish their own vocabulary later without LS changes.

What we put in our own modules is the ONLY Lua that works in there right now. That fact is easy to change, and once we do our days of needing to change the language server are kind of over (for tolerance, not editability). But I wanted to make sure the tooling also made it clear to consumers where the edge was, so there wasn't confusion.