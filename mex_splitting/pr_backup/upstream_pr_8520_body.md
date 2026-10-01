<!-- https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8520 — module: construction — body as of 2026-09-29 -->

## Context
Four gadgets that were filed under sharing because they are written for allies: assist, reclaim, resurrect, and ally mex upgrades (plus the build delay they lean on). None of them transfers anything. They are policies over building, so this PR gives construction a contract like every other module's.

## User story

```md
As a **player**, I want
  to help an ally's build, reclaim their unit, or guard their reclaimer, only when the lobby lets allies do that;
  a wreck I reclaimed halfway to resurrect only when the lobby allows partial resurrection;
  a builder under a build delay to build nothing until it lifts;
  to build a mex or a geo on a spot an ally holds only when the lobby lets utility buildings change hands, and then only onto their extractor.
As a **BAR Developer**, I want
  each of those to be a decision I can add a step to,
  and two facts I can answer for construction: who holds a spot, and whether utility buildings change hands.
```

## What's It Do
- `contract.lua` declares five policies with typed contexts: `assist`, `reclaim`, `resurrect`, `build`, `placement`, matching the module's own action domains.
- `policies/construction.lua` holds the rules the gadgets used to hardcode: an ally may not help an unfinished unit or a builder when assist is off, may not reclaim an ally or guard a reclaimer when reclaim is off, a partly reclaimed wreck resurrects only when the mode allows, a delayed builder builds nothing, and an ally's extractor spot is taken unless utility buildings may change hands.
- The gadgets build a context from engine state and ask. None of them disables itself at load anymore, so a mod can add a rule to any of these policies even when the base modoption is permissive.

Construction sits below transfer because transfer's Customize preset uses its verbs.

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
  class move,policies,modes,providers,docs,defs,game,transport,economy quiet
  class transfer,tech,techcore seen
  class runtime merged
  class chobbymodes lobbyQuiet
  class construction quietHere
```
🟩 no gameplay change  🟧 gameplay change  ⬜ merged  🟦 lobby (Chobby)  ⬛ dark outline: this PR. Boxes are the stacks, in merge order.

## Conclusion
Merging it moves assist, reclaim, resurrect, build delay and the geo and mex rule into a module as they are. Nothing players see changes.

## LLMs
Yes. Used for the broad refactors; every name and boundary was chosen by hand and is up for review above.



