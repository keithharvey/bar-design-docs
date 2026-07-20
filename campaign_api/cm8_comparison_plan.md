# Handoff: CM8 "Ashfall" End-to-End Mission Comparison

Plan for building the single-mission comparison doc requested in the BAR
Discord modules discussion. Read this whole file before starting; the
audience and style constraints matter as much as the content.

## Scope

Two staged deliverables; THIS PLAN COVERS ONLY THE FIRST.

1. **The comparison doc** (this plan): paper, all beats, both columns. Write
   the column-B Lua *as if it will be executed* — deliverable 2 uses it as
   its spec, so no hand-waving pseudocode: real verb names, real chain
   shapes, plausible arguments.
2. **A playable vertical slice** (separate plan, later): the subset of CM8
   that can run on an existing map with existing units — automated base,
   unit naming/tracking, raptor waves, kill-commander victory, objectives,
   scripted mission end. Requires building matchflow, a minimal trigger
   engine + DSL skeleton, and stub verbs. The lava tiers and cloaked
   enclave stay paper-only (engine-dependent) even in the slice.

Full CM8 cannot run today under ANY architecture — the mission's map
(Teizer V), tileset, and lava-level engine control are all pre-production.
Say this in the comparison doc's intro; it heads off "so where's the
playable mission" before it's asked.

## What you are building

One document: `campaign_api/cm8_ashfall_comparison.md` in this repo
(bar-design-docs). It takes one real mission from the campaign team's spec —
CM8 "Ashfall" — and writes it out **twice, beat by beat**:

- **Column/section A — today**: how each mission beat would be implemented
  under the current draft Mission API (PR #8226's one-file-per-action format
  plus the draft trigger/action tables) and the current base-game gadget
  landscape. Include what is *not possible* or requires forking base-game
  gadgets, and say so flatly without editorializing.
- **Column/section B — modules**: the same beat under the domain-module +
  authoring-DSL design. Real-looking Lua using the trigger DSL from
  mission_authoring_dsl.md and the module verbs from module_breakdown.md.

The goal was set by Harkenn in the Discord thread: "take a single mission
design, lay out all the things that aren't possible or are difficult right
now, in the current systems available; and then do the same thing with the
modules approach." The comparison exists so non-architects can evaluate the
design by reading mission code, not architecture prose.

## Why CM8

Median campaign shape (a standard fight plus one signature mechanic), one of
the best-specified missions in the spec, and its beats touch most modules
without cherry-picking: automated pilotless base (unit tracking/orders),
lava tiers regulated by destroyable geothermals (environment + the one
honest engine-dependency case), a cloaked+jammed Armada enclave (intel),
raptor pressure (waves/ai_director), commander-kill victory (matchflow), T2
Veh Lab unlock (construction). Fallback if CM8 proves awkward: CM3 "The
Flameswept Face That Turns The World" (escort haulers on 2-minute timers,
bombing objectives, side-objective Bardex unlocks — safer, less module
coverage). Note: the mission choice may be overridden by Jaedrik (campaign
team) — check with Daniel whether a different mission was picked on Discord
before writing.

## The mission, from the spec

CM8 "Ashfall" — Teizer V, volcanic Line World, stepped volcanic shelves.
Beats extracted from the campaign doc (full text committed at
campaign_api/refs/campaign_reqs_extraction.txt in this repo — CM8 is around
lines 1145-1156):

1. Player arrives; intercepts a failing Cortex outpost pinned down by Armada
   armor. The base's automated systems are intact but pilots are dead/
   evacuated — dozens of automated units the player inherits/commands.
2. Map is tiered volcanic shelves. Each tier anchored by T2 geothermals that
   act as regulators for the lava level: destroying a geo raises the lava.
   A character (Gideon) repeatedly cautions the player each time one is
   triggered.
3. Near the Cortex base: a concealed Armada enclave with jammers and cloaked
   buildings; at its center a Tenebrium-fused device (broadcast/amplifier —
   the raptor lure, narratively).
4. Raptors attack throughout (this arc is the raptor war).
5. Win condition: kill the Armada Commander. Mission end: T2 Vehicle Lab
   unlocked for future missions; campaign flag that Tenebrium attracts
   Raptors.

Where the spec is silent (difficulty scaling, exact wave cadence, objective
UI beats), invent modestly and mark inventions with "(assumed)" — the
campaign team reads this and should be able to correct assumptions cheaply.

## Beat-by-beat structure to write

For each beat: 2-4 sentences of what the mission needs, then A (today), then
B (modules). Suggested beats — merge/split as the writing demands:

1. **Mission setup**: spawn bases, the automated unit group, restrict tech
   to T1+prior unlocks (construction verdicts vs today's static modoption/
   def preprocessing — under A, note mid-mission unlock requires custom
   gadget work).
2. **The automated base**: naming/tracking the pilotless units, handing them
   to the player, story-protecting key structures (combat targetability +
   damage x0 vs today: no invulnerability mechanism exists — custom gadget).
3. **Lava tiers**: geo destroyed -> lava rises one tier -> Gideon warning ->
   units in the flood zone. A: raise/lower water exists in engine? verify
   Spring.SetWaterLevel / terraform APIs before claiming; lava-as-water
   damage hacks are how maps do it today (check springboard/lava.lua in the
   BAR repo — modules/lava.lua exists on the modules branch). B: environment
   module event + trigger chain; be explicit this is the beat that needs
   engine triage either way — the comparison must NOT pretend modules make
   engine gaps vanish. That honesty is load-bearing for the doc's
   credibility.
4. **The cloaked enclave**: jammer field + cloaked buildings + reveal on
   proximity/scan (intel grants/deltas vs today's per-gadget cloak
   handling).
5. **Raptor waves**: scripted pressure that scales with difficulty
   (ai_director WaveOrder vs today: raptor spawner gadget is a 2500-line
   monolith driven by modoptions — a mission cannot call it; you'd fork it).
6. **Objectives & victory**: kill-commander objective, staged objectives UI,
   mission end -> matchflow scripted verdict; campaign flags (T2 unlock,
   lore flag) persisting to the next mission.
7. **Difficulty variants** (short): where each knob lives in A vs B.
8. **Savegame/checkpoint** (short): what state each approach must persist;
   reference the source-vs-save table in mission_authoring_dsl.md.

End with a half-page summary table: per beat, "possible today?" /
"who owns the code today" / "module surface used" — no adjectives, let the
table argue.

## Sources you need

- This repo: campaign_api/module_breakdown.md (module list, PolicyResult
  shapes, performance model), campaign_api/mission_authoring_dsl.md (trigger
  DSL, subset rules, savegame table), campaign_api/matchflow_module_plan.md
  (untracked file in working tree — first-module detail).
- BAR repo at /var/home/daniel/code/Beyond-All-Reason (branch: modules).
  Current Mission API: luarules/mission_api/ and luarules/gadgets/
  api_missions*.lua on master; the refactored actions are PR #8226
  (fetch refs/pull/8226/head from the beyond-all-reason upstream repo).
  Existing gadgets worth citing in column A: game_end.lua (victory),
  raptor_spawner_defense.lua (waves), unit_attributes.lua (stat changes),
  ruins/ (map features), modules/sharing/ (the shipped module exemplar,
  including policy_builder.lua for real DSL syntax).
- The campaign spec extraction (see above for path/re-extraction).

## Style constraints (these were hard-won; do not skip)

- Plain language. No architecture vocabulary: no "orchestrator",
  "decomposition", "encapsulation", "surface", "registrant". Technical terms
  allowed in parentheses after the plain phrase. The audience explicitly
  rejected architect-register prose — this doc exists to fix that.
- Code speaks first: lead each beat with the Lua, explain after.
- Column A must be written *fairly* — as the best honest implementation a
  competent contributor would write today, not a strawman. Where today's
  approach is fine, say it's fine (SendMessage, markers, one-shot spawns are
  fine today — say so). The doc's credibility rests on A being defensible.
- Where B needs something that doesn't exist yet (module X, engine callin
  Y), mark it plainly: "(needs: environment module, engine support for Z)".
  No pretending the design is built.
- Keep total length readable in one sitting — aim well under the size of
  module_breakdown.md. Cut beats before compressing prose into jargon.

## Process

1. Verify mission choice with Daniel (Jaedrik may have picked a different
   one on Discord).
2. Read the two design docs + skim the current mission_api code and PR
   #8226 actions so column A cites real files.
3. Verify engine claims before making them (water/terrain APIs, cloak/
   jammer Lua control, SetGlobalLos) — grep the BAR repo and Recoil docs;
   the lava beat especially. Wrong engine claims in column A are the
   fastest way to lose the audience this doc is for.
4. Draft, then do a jargon pass (the style constraints above), then a
   fairness pass on column A specifically.
5. Deliverable goes on a new branch off editor_lua (stack order: master ->
   campaign_api -> editor_lua -> this), PR into the bar-design-docs repo.
   Do NOT push to any beyond-all-reason remote. Daniel writes his own
   Discord/PR messages — provide a 3-sentence summary he can adapt, don't
   post anything.

## Context on the audience (why this doc exists)

The modules design is contested not on technical merit but on
evaluability: reviewers (WtF, Rasoul, Harkenn) can't judge architecture
prose and fear a system only its author can maintain. This comparison is
the grounding artifact they asked for. It succeeds if a non-architect reads
one beat and thinks "I could write that B code" — and it fails if it reads
as a sales document. Understate, show, and keep column A honest.
