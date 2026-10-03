<!-- https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9474 — module: transport (widget move) — body as of 2026-09-29 -->

## Context

#9173 moved transport's nine gadgets into `modules/transport/`. The six widgets that drive transports on the player's side stayed in `luaui/Widgets/`, so #8965 had to move them along with its changes, and a move mixed with edits reads as a rewrite. This gives the widgets the same home first, so #8965 edits two of them in place and leaves the other four alone. (Opened again: the first PR, #9438, was marked merged by GitHub when a stack branch above it took in its commit.)

## What's It Do

A move and nothing else. Area unload, preserved commands after unload, the weight-limit indicator, the turret carry range, loading a moving unit of one's own, and guarding a factory with a transport go from `luaui/Widgets/` to `modules/transport/widgets/`, byte for byte. The module's manifest is already on master with its gadgets, and the loader lists a module's widgets beside the loose ones, so the game runs the same code from the new place.

## Overview

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 28, "rankSpacing": 44, "padding": 12}, "theme": "base", "themeVariables": {"lineColor": "#94a3b8", "fontFamily": "ui-sans-serif, system-ui", "clusterBkg": "#eef2f7", "clusterBorder": "#94a3b8", "titleColor": "#1f2937"}}}%%
graph BT
  subgraph s1["Stack 1 · the loader"]
    runtime("modules #8484 · merged")
    move("transport move #9173 · merged")
    widgets("transport widgets (this PR)")
  end
  subgraph s2["Stack 2 · the framework"]
    policies("policies #9170")
  end
  move --> runtime
  widgets --> move
  policies --> widgets
  click move "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9173"
  click runtime "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/8484"
  click widgets "https://github.com/beyond-all-reason/Beyond-All-Reason/tree/transport-widgets"
  click policies "https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9170"
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
  class move merged
  class runtime merged
  class widgets quietHere
  class policies quietFar
  style s1 fill:#e8edf3,stroke:#64748b,stroke-width:2.5px,rx:14,ry:14
  style s2 fill:#f1f6fd,stroke:#a9c0e0,stroke-width:1px,stroke-dasharray:6 4,rx:14,ry:14
```
🟩 no gameplay change  🟧 gameplay change  ⬜ merged  🟦 lobby (Chobby)  ⬛ dark outline: this PR  ┄ faded and dashed: the other stacks, for their direct ties: above, what this one is built on; below, what is built on it. Solid edges are `requires`; dotted edges are edits to a module the PR does not own. The whole stack is drawn on [#8534](https://github.com/beyond-all-reason/Beyond-All-Reason/issues/8534).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
