<!-- https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8965 — module: transport — body as of 2026-09-29 -->

## Context
The transport rules as one module. It pulls a long list of existing gadgets and every transport widget in behind it.

## User story

```md
As a **player**, I want
  my transport to pick up what it can, and refuse the rest for a reason I could name:
    not under water, not out of reach,
    not an enemy on the move,
    not an ally's nano unless it is my own.
  it to set a passenger down only where it can stand: dry ground, in reach, and no nano on a slope.
  a loaded transport to fly at its own speed, slowed by a commander aboard when the lobby says so.
As a **BAR Lobby Host**, I want
  to say whether enemies may carry units: everyone, nobody, or everyone but commanders.
As a **BAR Developer**, I want
  to add a rule to load, unload or loaded speed by name, without touching transport's files.
```

## What's It Do
- The decisions are three policies in one file, `policies/transport.lua`. The guards read inline; `lib/rules.lua` keeps only the physics the gadget needs.
- The api publishes `CanCarry`, `CanEverCarry`, `CanLoad`, `MayLoad` and `DefFacts` with no gadget behind them, so a widget can ask the module before it issues an order, and any gate a mod contributes is respected automatically. The factory guard and the load indicators had each grown their own private copy of carry eligibility; both now ask the api.
- The two modoptions that were these rules' dials, `transportenemy` and `comm_trans_slow`, move into the module's own section. Keys and defaults are unchanged, and the game presets claim them so the lobby shows what the active preset governs.
- The `transportenemy` rule that wrote `transportByEnemy` onto every def from inside `alldefs_post` is now transport's `EnemyTransport` step on the defs module's unit def fold, with a spec over both settings; the module requires `defs`.
- Ordering a transport to pick up an ally's nano goes through the load policy too (an `AlliedNano` gate), instead of a rule hidden in `AllowCommand`.
- Step names and typed contexts are published in `contract.lua`, so nothing names a step by string and a contributor's mod predicate references are typed.

One deliberate behavior change: the unload-momentum exception now keys off the `paratrooper` customparam instead of the unit name `cormando`.

**Before this rebases onto modes:** `modules/transport/lib/defs.lua` keeps its unit-fact cache in a file-level `local`, and `api.lua` is included by five files, so five copies fill. It moves into `modules/transport/state.lua` under the state convention the runtime PR sets (one `state.lua` per module, typed, anchored once per Lua state). The parked replay with `State` already exists locally; the cache move is the one change still to make there.

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
  class move,policies,modes,providers,docs,defs,game,construction,economy quiet
  class transfer,tech,techcore seen
  class runtime merged
  class chobbymodes lobbyQuiet
  class transport quietHere
```
🟩 no gameplay change  🟧 gameplay change  ⬜ merged  🟦 lobby (Chobby)  ⬛ dark outline: this PR. Boxes are the stacks, in merge order.

## Conclusion
Merging it moves the transport rules into a module as they are. Nothing players see changes.

## LLMs
Yes. Used for the broad refactors; every name and boundary was chosen by hand and is up for review above.



