# Teaching the architecture — the ladder

A framework for explaining the module/policy system and the PR stack that
builds it. Each rung is motivated by a failure the previous rung cannot
handle. Teach the failure first; the rule then explains itself.

## Rung 0 — the problem: layered effects

Gameplay rules live as gadget code, layered one after another, escaping the
layering through code reuse — an effect may call into another effect. Order
and state coupling are implicit; you cannot answer "what applied and why"
by reading any one piece.

## Rung 1 — policies: rules as data

A policy is a name, a `match`, and an `apply`. Policies are grouped in
ordered arrays; loading code determines order. All policies are evaluated
in order (matchAny) — there are no other array modes.

This buys the configuration axiom: *add or remove a policy from the set,
and this either breaks loudly at load or results in a well-formed runtime.*
matchAny is the only evaluation rule where an edit touches nothing but the
policy you edited — under first-match-wins, removing a policy silently
changes what applies for everything it used to shadow.

Two disciplines keep the rung standing:
- Effects are lazy **descriptors** (data); one applier executes them. Reuse
  lives in libraries called for *computation*, never for *application* —
  effect-calls-effect is Rung 0 growing back.
- Policies are stateless **rules**; state (a protection refcount, a latched
  sighting, objective progress) lives in a **named, owned ledger**, with a
  hard line on what closures may capture: *configuration, never progress.*
  This is the entire reload/savegame story.

## Rung 2 — the one-author substrate: the DSL statement

Failure Rung 1 can't handle: humans compose with order and precedence —
if/elif, match arms, "this AND that". Order-insensitive arrays have no
place for that.

It lives inside the statement — the unit with exactly one author. A trigger
chain, a roster entry, an objective declaration, a mode preset: sequencing
and conjunction are written at the statement, readable top-to-bottom in the
file that owns the decision. Repeated `.When` is AND. OR is two statements
(a second `.CompletedWhen` is another way, not another requirement).
Languages keep first-match single-author — no one adds match arms to
someone else's match statement — and so do we.

## Rung 3 — the array is the plural-author boundary

Failure Rung 2 can't handle: modules that have never seen each other must
contribute to one system.

Under matchAny, merging contributions is concatenation — the semantics of
the union is the union of the semantics. Under any richer mode, merging
changes what *existing* policies mean: load order starts deciding fights
nobody wrote down (CSS specificity is this failure, shipped). Where overlap
would be a bug, it is checked: a name collision between modules is a **load
error, not a silent shadow**.

## Rung 4 — the load step is the compiler

Failure Rung 3 can't handle: Lua has no static checker, so where does
"breaks loudly" happen? At load. Decision time is part of a policy's type,
in three tiers:

1. **Lobby-decidable** — decided before the game exists. Mode presets
   serialize to plain modoptions; lobby and server expand the same preset
   from the same data.
2. **Load-decidable** — parse-time discovery, definition sites, wiring.
   `units.lua` declares every unit name, `objectives.lua` every objective
   id; a typo is a load error, not a silently-never-true condition. The
   engine hooks only the callins some armed rule declared.
3. **Frame-decidable** — the residue: whether the projectile came from a
   ceasefired team. Fast because it is small.

The rule: every decision migrates to the earliest tier that can make it.

Corollary: **triggers attach to artifacts, not intentions.** Events are
facts (you cannot deny UnitDestroyed); requests are deniable and get a
validate/execute split whose refusal names its reason. "The build queue"
is an intention; the nanoframe is the artifact. Persistent intentions are
policies.

## Rung 5 — arbitration by orchestrator

Failure Rung 4 can't handle: contributions that genuinely conflict at
runtime — a room full of players wanting different modes.

Appoint an arbiter with an explicit protocol. `!mode <category> <mode>
[override=x]*` is a fold with a declared decision rule (the vote), and its
payload is grammar terms resolved by the same resolver both sides run — the
orchestrator can only *speak the grammar*, so a vote cannot produce an
ill-formed configuration.

## The three boundaries

> Composition in the grammar (one author).
> Accumulation at the array (many authors, no conflicts).
> Arbitration by orchestrator (many authors, real conflicts).

## Reading the stack as the ladder

| PRs | Rung |
|---|---|
| module-runtime, context | 1+4 — the substrate and the loud-break machinery: discovery, collision-as-load-error, spec'd libs |
| modes | 4+5 — grammar precompiled to lobby data; the orchestrator's vocabulary |
| matchflow | 2 — the first owned decision (the verdict), a noun other grammars import from its owner |
| missions, mission-editor, hello_pawns | 2+4 — the statement substrate: triggers, definition sites, facts-vs-requests; hello_pawns is the smallest complete climb |
| tech, construction, economy, transfer, combat, placement | 1+3 — domain modules as policy contributors; transfer is the request path (validate/execute), combat is the ledger (a refcount, not a set) |
| waves, scavengers, raptors | 3 — plural authorship for real: one module's verbs, another's packs, a third proving the seam as second consumer |
| cm8-ashfall | all — a mission authored entirely inside the substrate, including its own objective board |

## Phrases that carry weight

- *Add or remove a policy: loud break or well-formed runtime.*
- *Configuration, never progress.*
- *Collision is a load error, not a silent shadow.*
- *OR is two statements.*
- *Triggers attach to artifacts, not intentions.*
- *Every decision migrates to the earliest tier that can make it.*
- *A refcount, not a set.*
- *The orchestrator speaks the grammar.*
