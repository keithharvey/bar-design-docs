<!-- https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9110 — module: defs — body as of 2026-09-29 -->

## Context
The first module, and the smallest one that could be: def post-processing as a fold.

## User story

```md
As a **player**, I want nothing to change: every def reads as it did.
As a **BAR Developer**, I want
  to change what a unit def or a weapon def says, once, after the engine has read it,
    without editing alldefs_post,
    as a named step every other module can put its own before or after.
```

## What's It Do
`gamedata/unitdefs_post.lua` and `weapondefs_post.lua` evaluate the defs module's `UnitDef` and `WeaponDef` folds once per def. The base game's own pass, `gamedata/alldefs_post.lua`, is the `Base` step of each: included once per Lua state through the module's `state.lua`, so the two post files no longer include it twice. The module is the first to carry its policy inline in `contract.lua`, the form for a module whose whole policy is a few lines. A module that edits defs adds a named step before or after `Base` with `Contributes`; transport's enemy-transport step is the first, up the chain.

What this adds: `modules/defs/` (manifest, a contract with its policy inline, `state.lua`, `api.lua`, a spec) and the two gamedata hooks. What it changes about how defs load: nothing observable. Every def goes through the same pass in the same order; the only difference is that the pass has a name. Merging it should do nothing.

The guide is [`modules/README.md`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/module-docs/modules/README.md) in the runtime PR; [`modules/REFERENCE.md`](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/module-docs/modules/REFERENCE.md) beside it shows this module's contract whole as its example of a Fold and of a policy carried inline.

## Overview
```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 28, "rankSpacing": 44, "padding": 12}, "theme": "base", "themeVariables": {"lineColor": "#94a3b8", "fontFamily": "ui-sans-serif, system-ui", "clusterBkg": "#eef2f7", "clusterBorder": "#94a3b8", "titleColor": "#1f2937"}}}%%
graph BT
  subgraph s1["Stack 1 · the loader"]
    runtime("modules #8484 · merged")
    move("transport move #9173")
  end
  subgraph s2["Stack 2 · the framework"]
    policies("policies #9170")
    modes("modes #9301")
    providers("providers #9302")
    docs("docs #9178")
  end
  subgraph s3["Stack 3 · transport"]
    defs("defs #9110")
    game("game #9113")
    transport("transport #8965")
  end
  subgraph s4["Stack 4 · transfer"]
    construction("construction #8520")
    economy("economy #8524")
    transfer("transfer #8521")
    tech("tech #8490")
    techcore("tech core #9038")
  end
  subgraph lobby["Chobby · the lobby side"]
    chobbymodes("Chobby: modes #1041")
  end
  move --> runtime
  policies --> move
  modes --> policies
  providers --> modes
  docs --> providers
  defs --> policies
  game --> modes
  transport --> defs
  transport --> game
  construction --> providers
  economy --> providers
  transfer --> construction
  transfer --> economy
  tech --> transfer
  tech --> construction
  techcore --> tech
  chobbymodes --> game
  click runtime "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8484"
  click move "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9173"
  click policies "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9170"
  click modes "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9301"
  click providers "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9302"
  click docs "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9178"
  click defs "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9110"
  click game "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9113"
  click transport "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8965"
  click construction "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8520"
  click economy "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8524"
  click transfer "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8521"
  click tech "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8490"
  click techcore "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9038"
  click chobbymodes "https://github.com/beyond-all-reason/BYAR-Chobby/pull/1041"
  classDef quiet fill:#77b255,stroke:#4f7d33,stroke-width:1.5px,color:#14260a,rx:8,ry:8
  classDef seen fill:#f4900c,stroke:#b35f00,stroke-width:1.5px,color:#2a1600,rx:8,ry:8
  classDef quietHere fill:#77b255,stroke:#0f172a,stroke-width:4px,color:#14260a,rx:8,ry:8
  classDef seenHere fill:#f4900c,stroke:#0f172a,stroke-width:4px,color:#2a1600,rx:8,ry:8
  classDef merged fill:#cbd5e1,stroke:#64748b,stroke-width:1.5px,color:#334155,rx:8,ry:8
  classDef lobbyQuiet fill:#5eb5c4,stroke:#2f7f8d,stroke-width:1.5px,color:#08262b,rx:8,ry:8
  style s1 fill:#e8edf3,stroke:#64748b,stroke-width:1.5px,rx:14,ry:14
  style s2 fill:#e3eefb,stroke:#5b8ac7,stroke-width:1.5px,rx:14,ry:14
  style s3 fill:#e6f4e1,stroke:#6a9f52,stroke-width:1.5px,rx:14,ry:14
  style s4 fill:#fdf0dc,stroke:#c9944a,stroke-width:1.5px,rx:14,ry:14
  style lobby fill:#e2f4f1,stroke:#3f9c8f,stroke-width:1.5px,stroke-dasharray:6 4,rx:14,ry:14
  class move,policies,modes,providers,docs,game,transport,construction,economy quiet
  class transfer,tech,techcore seen
  class runtime merged
  class chobbymodes lobbyQuiet
  class defs quietHere
```
🟩 no gameplay change  🟧 gameplay change  ⬜ merged  🟦 lobby (Chobby)  ⬛ dark outline: this PR. Boxes are the stacks, in merge order.

## Conclusion
Merging it does nothing observable: every def goes through the same pass in the same order, and the pass has a name.

## LLMs
Yes. Used for the broad refactors; every name and boundary was chosen by hand and is up for review above.



