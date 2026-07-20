# Mission Editor, Serialization, and Authoring

How mission designers get a real editor — forms, a trigger graph, a verb palette — without anyone building or maintaining a second file format. Companion to [module_breakdown.md](https://github.com/keithharvey/bar-design-docs/pull/1) (PR #1), which covers what the domain modules own; this doc covers how missions drive them, and how the editor the campaign team wants falls out of that.

## Start from what the editor needs

Any mission editor, whatever the file format underneath, needs four things:

1. **A schema** — what actions and triggers exist, what parameters they take, which are required, what the legal values are. This is what draws the forms and dropdowns.
2. **A validator** — is this mission well-formed? Same schema, second consumer.
3. **Round-tripping** — read a mission, show it, write it back without destroying anything a human did by hand.
4. **An escape hatch** — some mission logic is genuinely custom. SC2, FAF, and our own draft spec (the `Custom` action takes a function) all concede this. The editor has to coexist with real code.

Point 4 is where editors go to die. The moment the escape hatch is a *different format* from the triggers (code blobs embedded in data tables), every nontrivial mission becomes half forms, half opaque functions, and the two halves can't see each other — the validator can't check the code, the code can't be shown next to the triggers it cooperates with, and round-trips get lossy at every boundary.

## The move: one format, and it's the one we already have

Every layer of the modules framework already authors through small declarative builder files: policies (`Policies.Pipeline():Gate(...):Compute(...):Register()`), actions, modes. Each is Lua, loaded in an injected environment, checked by EmmyLua, readable by tooling. Missions use the same idiom. A trigger file:

```lua
-- missions/cm3_flameswept/triggers/second_wave.lua
local T = Mission.Trigger

T.When(Region("north_pass"):EnteredBy(Team.Player, { count = 5 }))
    :AndWhen(Objective("hold_the_line"):IsActive())
    :Debounce(seconds(10))
    :Once()
    :Then(function(ctx)
        Wave.Define("raptor_flank")
            :Composition({ raptor_land_swarmer_basic = 40, raptor_land_assault_basic = 8 })
            :Route(Path("east_ridge"))
            :Target(Region("player_base"))
            :Spawn()
        Intel.Grant(Team.Player, { layers = { "radar" } })
            :Over(Region("east_ridge"))
            :For(seconds(30))
        Presentation.Announce("wave_incoming_east")
    end)
    :Register()
```

(Vocabulary illustrative — the verbs come from the domain modules, so this assumes the breakdown doc's modules exist.)

Now walk the editor's four needs against this:

**Schema: already written.** Every verb carries LuaCATS annotations — parameter names, types, enums, which argument is a region name vs a number. That IS the form schema. Nobody writes a second schema file for the editor; nobody keeps two schemas in sync. When a module adds a verb, the editor learns it automatically, because the annotation is the only source of truth and it ships with the verb.

**Validator: same parser, two consumers.** The subset of Lua the editor understands (builder chains with literal arguments and named references) is defined once. The editor uses it to decide what's form-editable; CI uses it to decide what's a legal mission. They cannot drift, because they are the same code.

**Round-tripping: structural where possible, byte-exact where not.** Chains with literal arguments round-trip as structure — the editor can rewrite them freely. Anything else (a computed argument, a `:Then` body with real logic) is an *opaque block*: the editor shows it as a code node, does not decompose it, and writes it back byte-for-byte, comments and formatting included. A hand-written mission survives the GUI untouched; a GUI-built mission is hand-editable. Neither author is a second-class citizen.

**Escape hatch: it's the same file, same language, same checks.** The `:Then` body above isn't an embedded blob in a foreign format — it's Lua in a Lua file, type-checked with everything else, sandboxed by the injected environment (the same mechanism policies and tweaks already use: a mission physically can't call what the mission surface doesn't hand it). The cliff between "what forms can express" and "what missions need" becomes a gentle slope inside one file.

That's the pairing: the DSL isn't a rival to the GUI, it's the substrate that makes the GUI cheap. Everything the editor needs — schema, validation, round-trip, escape hatch — is a property the authoring format already has, because the authoring format is code with annotations rather than data with code holes.

There's a second payoff, and for this project it may be the bigger one: **the editor becomes an on-ramp to contributing, not a ceiling.** BAR's contributors are mostly players who drifted into modding. In this design, a designer working in forms has the code in front of them the whole time — same file, the `:Then` blocks sitting next to the triggers they cooperate with. Curiosity has a zero-cost first step, and graduating from forms to code means decomposing more of the same file, not abandoning your missions' format to start over in a language the editor hid from you. It runs the other way too: a mission built entirely in the GUI is still reviewable Lua in a pull request — same diffs, same review culture, no "open the editor to see what changed." One design grows modders; the other grows editor users who hit a wall.

## The editor ships in stages, each useful alone

Nothing waits on the editor. Mission authors start with a text editor and EmmyLua on day one — which is how the first missions get written regardless.

1. **Validate**: CI runs the subset parser + type checker on mission files. (Nearly free; the toolchain exists.)
2. **Visualize**: read-only trigger graph rendered from parsed chains. Cheap, and immediately valuable for *reviewing* missions — you can see the trigger flow of a mission in a PR.
3. **Edit forms**: annotation-driven forms writing back subset nodes; opaque blocks shown as code.
4. **Full editor**: verb palette, region painting on the map, difficulty-variant views.

Because the file format is source, every stage is optional and no stage can hold mission production hostage. Compare the alternative order of operations: design a data format, build the editor that is its only decent authoring tool, and only then find out what missions actually need.

## Migration from the draft trigger/action tables

Mechanical, not political: the existing declarative shapes map 1:1 onto chains — `{ type = 'UnitEntersArea', region = R, count = 5 }` becomes `Region(R):EnteredBy(team, { count = 5 })`. A converter is a few hundred lines, so adoption is a rename, not a rewrite. The draft shapes keep working during the transition; the chains are where the new capability (type checking, editor stages, savegame discipline) accrues.

## Who owns which words

Three layers in the example above, three owners:

1. **Chain mechanics and combinators** — `When/AndWhen/Debounce/Once/Then/ Register`, AND/OR/NOT grouping, random-pick, repeat. These are the draft spec's "trigger modifiers," and they are FRAMEWORK-owned: one grammar, defined once (PolicyBuilder grown up). If every module invented its own `When`, authors would learn seven dialects and the editor would need seven parsers. Same split as the shared command handler: plumbing in the framework, decisions in the domains.
2. **Domain verbs** — `Wave.Define`, `Intel.Grant`, `Build.Restrict`, `Region(...):EnteredBy`. MODULE-owned, shipped next to the module's policies, annotated. New module, new vocabulary, zero editor changes.
3. **Mission logic** — the `:Then` bodies. Author-owned, plain Lua, inside the sandbox.

## Savegames: the constraint no format escapes

The campaign spec requires Autosave / Set Checkpoint. Functions do not survive serialization — in ANY authoring format (the draft data format has `Function` parameters too; this constraint was never format-dependent). So everything a mission is gets split into two piles, and a checkpoint only ever saves the second:

| | Lives in source (reloaded on restore) | Lives in the save (serialized) |
|---|---|---|
| What | Trigger definitions: conditions, effects, wave defs, the chains themselves | Trigger progress: fired flags, debounce clocks, counters, random seeds, active timers |
| Owner | Mission files | The trigger engine, in plain tables |
| On restore | Re-run the mission files (they're just code) | Reapply the saved tables on top |

For the split to work, trigger definitions must be stateless: condition and effect functions read `ctx` and module state, and capture no mutable locals — a closure that counts in an upvalue has smuggled progress into the source pile, where the save can't see it. Enforce that from the first trigger-engine commit. It's the same split the modules already use: policies are code, verdicts are derived, only real state persists.

## Open questions

- Combinator set: chain methods vs condition-expression objects (`All(a, b)`, `Any(a, b)`)? Leaning expression objects for arbitrary nesting, chain methods for the common linear case.
- Named references: regions/paths/groups/objectives declared in a sibling file (`missions/<name>/map.lua`) so the editor and the parser resolve names without executing anything.
- Difficulty variants: chain-level (`:OnDifficulty("hard", ...)`) vs file-level overlays (`triggers/hard/*.lua`) — probably both; overlays for wholesale changes, chain-level for parameter tweaks.
- Hot-reload during authoring: re-running a registration file mid-game means unregister-by-identity first; trigger identity = filename + declaration order, same as policies. Design it in early — it's what makes iteration fast enough for mission designers to love.
- How much of the `Wave.*` vocabulary is authoring DSL vs runtime API — the spec's Wave verbs read like both; probably the DSL builds WaveDefs and the runtime API drives them.
