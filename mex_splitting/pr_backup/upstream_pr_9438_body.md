<!-- https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9438 — module: transport (widget move) — body as of 2026-09-29 -->

## Context

#9173 moved transport's nine gadgets into `modules/transport/`. The six widgets that drive transports on the player's side stayed in `luaui/Widgets/`, so #8965 had to move them along with its changes, and a move mixed with edits reads as a rewrite. This gives the widgets the same home first, so #8965 edits two of them in place and leaves the other four alone.

## What's It Do

A move and nothing else. Area unload, preserved commands after unload, the weight-limit indicator, the turret carry range, loading a moving unit of one's own, and guarding a factory with a transport go from `luaui/Widgets/` to `modules/transport/widgets/`, byte for byte. The module's manifest is already on master with its gadgets, and the loader lists a module's widgets beside the loose ones, so the game runs the same code from the new place.

## Overview

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 28, "rankSpacing": 44, "padding": 12}, "theme": "base", "themeVariables": {"lineColor": "#94a3b8", "fontFamily": "ui-sans-serif, system-ui", "clusterBkg": "#eef2f7", "clusterBorder": "#94a3b8", "titleColor": "#1f2937"}}}%%
graph BT
  subgraph s1["Stack 1 · the loader"]
    move("transport move #9173 · merged")
  end
  subgraph s2["Stack 2 · the framework"]
    policies("policies #9170")
    widgets("transport widgets (this PR)")
    modes("modes #9301")
    providers("providers #9302")
    docs("docs #9178")
  end
  subgraph s3["Stack 3 · transport"]
    defs("defs #9110")
  end
  subgraph s4["Stack 4 · transfer"]
    construction("construction #8520")
  end
  subgraph s5["Stack 5 · regions"]
    regions("regions + start #37")
  end
  policies --> move
  widgets --> policies
  modes --> widgets
  providers --> modes
  docs --> providers
  defs --> policies
  construction --> providers
  regions --> policies
  click policies "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9170"
  click move "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9173"
  click widgets "https://github.com/beyond-all-reason/Beyond-All-Reason/tree/transport-widgets"
  click modes "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9301"
  click providers "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9302"
  click docs "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9178"
  click defs "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9110"
  click construction "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8520"
  click regions "https://github.com/keithharvey/bar/pull/37"
  classDef quiet fill:#77b255,stroke:#4f7d33,stroke-width:1.5px,color:#14260a,rx:8,ry:8
  classDef seen fill:#f4900c,stroke:#b35f00,stroke-width:1.5px,color:#2a1600,rx:8,ry:8
  classDef quietHere fill:#77b255,stroke:#0f172a,stroke-width:4px,color:#14260a,rx:8,ry:8
  classDef seenHere fill:#f4900c,stroke:#0f172a,stroke-width:4px,color:#2a1600,rx:8,ry:8
  classDef quietFar fill:#dcebd5,stroke:#a9c79a,stroke-width:1px,color:#4b5f42,rx:8,ry:8
  classDef seenFar fill:#fbe3c3,stroke:#e0b37c,stroke-width:1px,color:#6b5230,rx:8,ry:8
  classDef merged fill:#cbd5e1,stroke:#64748b,stroke-width:1.5px,color:#334155,rx:8,ry:8
  classDef mergedFar fill:#e5eaf0,stroke:#aab4c0,stroke-width:1px,color:#64748b,rx:8,ry:8
  classDef mergedHere fill:#cbd5e1,stroke:#0f172a,stroke-width:4px,color:#334155,rx:8,ry:8
  classDef lobbyQuiet fill:#5eb5c4,stroke:#2f7f8d,stroke-width:1.5px,color:#08262b,rx:8,ry:8
  class policies quiet
  class move mergedFar
  class widgets quietHere
  class modes quiet
  class providers quiet
  class docs quiet
  class defs quietFar
  class construction quietFar
  class regions quietFar
  style s1 fill:#f4f6f9,stroke:#b6c0cc,stroke-width:1px,stroke-dasharray:6 4,rx:14,ry:14
  style s2 fill:#e3eefb,stroke:#5b8ac7,stroke-width:2.5px,rx:14,ry:14
  style s3 fill:#f3f9f0,stroke:#b5cfa8,stroke-width:1px,stroke-dasharray:6 4,rx:14,ry:14
  style s4 fill:#fef8ee,stroke:#e3c79e,stroke-width:1px,stroke-dasharray:6 4,rx:14,ry:14
  style s5 fill:#f7f2fd,stroke:#c4b0e4,stroke-width:1px,stroke-dasharray:6 4,rx:14,ry:14
```
🟩 no gameplay change  🟧 gameplay change  ⬜ merged  🟦 lobby (Chobby)  ⬛ dark outline: this PR  ┄ faded and dashed: the other stacks, for their direct ties: above, what this one is built on; below, what is built on it. Solid edges are `requires`; dotted edges are edits to a module the PR does not own. The whole stack is drawn on [#8534](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/8534).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
