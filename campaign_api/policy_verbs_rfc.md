# RFC: naming the policy builder's verbs

Status: draft. Grew out of #dev-discussion, 2026-08-30.

## What we are naming

A module owns *pipelines*, one per decision it makes (`transport.load`,
`transport.unload`, `transfer.unit_transfer`, `matchflow.game_over`). A
pipeline is an ordered list of named *stages*. Evaluation is:

```
for each stage in order:
    result = stage.evaluate(ctx, ...)
    if result ~= nil then return result end
return nil
```

First non-nil result wins. The last stage is the *terminal*: it must produce a
result. Other modules *contribute* to a pipeline they do not own by inserting
stages before or after a named stage, replacing one, or removing one.

Today's surface (module-runtime, `modules/policy_builder.lua`):

```lua
-- owner
Policies.Pipeline(Stages)
	.Gate(Stages.Submerged, function(ctx) if Rules.Submerged(ctx.goalY, ctx.height) then return false end end)
	.Gate(Stages.OutOfReach, ...)
	.Compute(Stages.Allowed, function() return true end)

-- contributor
Policies.Contribute(Stages)
	.Gate("TanksStayOnTheGround", function(ctx) if isTank(ctx.passengerDef) then return false end end)
	.Before(Stages.Submerged)
```

Stage names are an enum in the owner's `policy_stages.lua`:

```lua
local Unload = { Submerged = "Submerged", OutOfReach = "OutOfReach", NanoOnSlope = "NanoOnSlope", Allowed = "Allowed" }
```

Three things are up for naming: the pipeline itself, the two stage verbs
(short-circuiting vs terminal), and the stage enum.


## Constraints the names must satisfy

- Stages are **named and addressable**: contributions say `.Before(Stages.Submerged)`.
  Whatever the verb, the name is the unit of extension.
- A stage's result is not always a boolean. `transport.loaded_speed` stages
  return a multiplier; `transfer.unit_transfer` returns terms; `matchflow.game_over`
  returns a verdict. Any vocabulary that reads as validation-only misnames
  half the pipelines. See `cm8-ashfall` for the mission-side pipelines.
- The terminal is a stage like the others (contributions can `Replace` it),
  so it has a name in the enum.
- One vocabulary, or at least one family, is wanted across the policy
  builder and the mission DSL (`When`/`Then`/`Do` today). Two unrelated
  vocabularies for "condition, then consequence" in one codebase is the
  outcome we most want to avoid.
- The verbs will be bikeshedded. Whatever we pick, we want to be able to say
  "we default to X's names" and point at X.

## Where the shape comes from

This is not a data-transformation pipeline and not a sequence library. It is
a **middleware chain**: ordered named handlers, each may short-circuit with a
response or pass to the next, one terminal handler, and extension by
inserting handlers around named ones. The ecosystem names for that shape:

| Ecosystem | Whole | Short-circuiting stage | Terminal | Notes |
|---|---|---|---|---|
| ASP.NET Core | request **pipeline** | `Use` | `Run` | literally called a pipeline; `Map` branches |
| Koa / Express | middleware stack | `use` (calls `next()` or not) | last handler | |
| Django | middleware | `process_request` returning a response short-circuits | view | ordering by list position |
| Rack (Ruby) | middleware | `call` returning a response | app | |
| Chain of responsibility (GoF) | chain | handler | default handler | |

So "pipeline" has direct precedent for exactly this shape, and the
transformation reading is one of two common meanings, not the only one.

For the *result* the pipeline produces, the closest functional reading is
`Result<T, Reason>`: the short-circuiting stages produce `Err(reason)`, the
terminal produces `Ok(value)`, and first non-nil wins is `?`. Under that
reading the stage enum looks like a list of `Err` variants plus the `Ok`.
The enum is neither: it is the pipeline's stage roster, and the terminal is
in it because the terminal is a stage — contributions can `Replace` it.

## Where "validation" already lives

Validation is the layer above this one: `actions/<command>.lua` registers
`Validate(request) -> boolean allowed, string? reason` and `Execute(request)`,
and that validate reads context the pipelines set up. Adjacent, not 1:1 —
pipeline results also cross to unsynced as view models. Naming the pipeline
layer "validation" too would put validation consulting validation side by
side, so validation-flavored vocabularies are out of the running.


## The approaches

The axes being traded:

1. **Transferability** — learn our verbs, gain knowledge that works in other
   languages; and we get the out of "we default to X's names", with X's
   ecosystem of ideas behind it.
2. **Familiarity for BAR developers** — imperative, engine-callin culture
   (`Allow*` callins, checks that return true/false).
3. **Per-scope readability** — the verb that says exactly what *this*
   pipeline does, at the cost of a vocabulary per scope and a bikeshed per
   verb.

| Approach | Whole | Stage | Terminal | transport.load reads as |
|---|---|---|---|---|
| Functional (X = LINQ) | `Pipeline` | `Where` | `Select` | `.Where(Submerged, fn).Select(Allowed, fn)` |
| BAR-imperative | `Policy` | `Check` | `Decide` | `.Check(Submerged, fn).Decide(Allowed, fn)` |
| Domain-specific per scope | per scope | per scope | per scope | `.Refuse(Submerged, fn).Grant()`; loaded_speed: `.Rate(CommanderDrag, fn)`; game_over: `.Verdict(...)` |
| Hybrid (one family with missions) | `Pipeline` | `When` | `Do` | `.When(Submerged, fn).Do(Allowed, fn)` |
| Today | `Pipeline` | `Gate` | `Compute` | `.Gate(Submerged, fn).Compute(Allowed, fn)` |

- **Functional** maximizes axis 1. The runner *is* functional — see the
  ecosystem table below — and the verbs come pre-argued. The known cost: a
  `Where` stage that answers with a value on rejection is not strictly a
  where; the Result reading (stage = `Err(reason)` producer) is the honest
  gloss. The mission DSL stays its own scope with its own verbs, which
  axis 3 legitimizes.
- **BAR-imperative** maximizes axis 2 for the current contributor base —
  `Check`/`Decide` need no explanation — and buys nothing transferable.
  It also weights what current BAR developers know, and for this layer they
  are learning something new regardless.
- **Domain-specific** maximizes axis 3: each pipeline is maximally readable
  in isolation. The costs are N vocabularies to design, teach, and defend,
  and nothing transfers between scopes, let alone out of the codebase.
- **Hybrid** trades a little of axis 3 for one condition/consequence family
  across the policy builder and the mission DSL: two DSLs, one set of
  concepts. The risk is `When` promising a boolean condition when a stage is
  a handler that may answer with a value.
- **Today** is hybrid-shaped with unshared verbs: `Gate` is a place, not an
  act, and `Compute` was already argued down to `Do` in mission-DSL review.

### Functional ecosystem comparison

If the pick is functional, the X to point at:

| Ecosystem | filter | transform | fold | first-hit (= our runner) |
|---|---|---|---|---|
| LINQ (C#) | `Where` | `Select` | `Aggregate` | `FirstOrDefault` |
| Rust `Iterator` | `filter` | `map` | `fold` | `find_map` |
| Kotlin sequences | `filter` | `map` | `fold` | `firstNotNullOf` |
| Ruby `Enumerable` | `select` | `map` | `reduce` | `detect` |
| Rx / observables | `filter` | `map` | `reduce` | `first` |
| luafun (Lua) | `filter` | `map` | `reduce`/`foldl` | none (`head` after `filter`) |

The runner column is the tell: our evaluation is exactly `find_map` /
`firstNotNullOf` — map each stage over the context, first non-nil wins.
LINQ is the strongest X: the largest audience, PascalCase matching the
builder surface Lua already has, and `Where`/`Select` being household names.
luafun is the only Lua-native X and loses on casing and audience.

None of these libraries can replace the builder — they are sequence
combinators with no named stages and no short-circuit-with-value — so
whichever X we point at, we are borrowing names, not code. The same goes for
the rest of functional Lua (Penlight `pl.seq`, Moses, lume).

## Do stages answer with values?

The design question beneath the verbs. On the branch, short-circuiting
stages do three jobs:

1. **Bare refusal** — transport's gates return `false`.
2. **Refusal with payload** — `unit_transfer`'s gates return the full terms
   record with the refusal folded in: callers need the delay terms to
   explain a no.
3. **Preemption** — `game_over.ScriptedVerdict` returns
   `{ winners = ctx.scriptedWinners }`: not a refusal, an early answer that
   outranks the standard computation.

The alternative design: the conditional stages only answer yes or no, and
the runner does the rest — the terminal still computes its value as today.
A conditional stage would return true/false, the runner would turn a no into
"refused: Submerged" using the stage's own name, and each pipeline would
declare once how a refusal gets dressed up into its result shape (the terms
record, say). That covers jobs 1 and 2, and it would make `Where` fully
honest — every `Where` stage really would be a filter.

Job 3 doesn't break it — `ScriptedVerdict` could be a conditional at the
top of the terminal — but the fold has a price. As a stage, preemption is
named and addressable: a contributor can insert before it, replace it, or
remove it, and the enum shows one name per decision. As a branch inside the
terminal it disappears from all of that; the only lever left for a module
that wants to outrank or drop scripted verdicts is replacing the whole
terminal, standard computation and all.

So stages are handlers not by necessity but because it keeps every decision
— preemption included — individually contributable. The naming consequence
stands either way: `Where` is a slight lie for preemption stages; `When`
and `Use` are not.

## Proposal

Keep `Pipeline` (precedent: ASP.NET, Koa, Rack, Polly). The verb decision is
between the two live finalists:

- **Functional, X = LINQ**: `.Where(...)` / `.Select(...)`. Transferable,
  pre-argued, and the runner is honestly LINQ. The mission DSL keeps its own
  domain verbs as its own scope.
- **Hybrid**: `.When(...)` / `.Do(...)`. One condition/consequence family
  shared with the mission DSL, at the cost of belonging to no outside
  ecosystem.

Decide with the full pipeline roster on the table — the non-boolean ones
(`loaded_speed`, `take`, `game_over`, `tech_core`) are where the verbs earn
or lose their names — not the transport booleans alone.