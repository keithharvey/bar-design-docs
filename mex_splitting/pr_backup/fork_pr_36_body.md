<!-- https://github.com/keithharvey/bar/pull/36 — module: region, start; feature: mex splitting — body as of 2026-09-29 -->

## Mex Splitting User Story

### "None" Mex Splitting

As a **player**, I want nothing to ever change. I will use Chobby with Standard mode, playing Glitters until I die.

### "Map Assigned" Mex Splitting

```md
As a **player**, I want
  to play in lobbies with a set of mexes that are "mine", depending on my start position and the prevailing meta for a given map.
    In game,
      at pre-game start,
        I should receive a message informing me that mex building is restricted.
      when building a mex, I should see:
        which mexes I can build (or not) highlighted on the map
        tooltips describing why that is if I mouse over a particular mex
As a **map maker**, I want add regions enclosing specific mexes to on my map.
  On each region, I need to add
    a required team ("north", "south"), from a list of teams
    a required group ("tech", "anti_canyon").
    an optional name (e.g. "tech", "anti_canyon_1", "anti_canyon_2")
  On all regions, I need
    to validate that every mex is circled by a region at least once.

As a **Terraformer maintainer**, I want region logic and runtime code out of terraform.
As a **BAR developer**,
  I want the ability to add a feature that talks about a region, which is an enclosed area on a map.
  I want to be able to extend regions with my own region types, which have: required fields and custom behavior
  I also want to be able to extend existing region types (such as start positions, or mission objective regions) with new behaviors
As a **BAR maintainer**,
  I would like type checking so any mistakes I make are caught at edit-time and not run-time
```

### "Shared" Mex Splitting

As a **player**, I want
  to play in lobbies where my team shares all metal income is shared.
    In game,
      at pre-game start,
        I should receive a message informing me that all mex income is shared across the team evenly.
      during the game,
        I should receive mex income equal to the cumulative number of team mexes / number of team players.

## Context

Regions are sort of in terraformer today in the form of start boxes. Regions would also be useful for circling other things on a map, like mexes that you want to be grouped for 1 player -- assuming you want to restrict who can build where. But then you have the problem of how you compose _game behavior_ on top of those regions, so you need [policies](https://github.com/beyond-all-reason/Beyond-All-Reason/pull/9170).

## Regions module

Adds a Regions module. Regions are a closed area on a map; they also carry data from the map maker to the runtime.

## Start module
Adds a Start module, which is the home for all of the pre-game start logic. Move startbox logic behind the start module api, expressed as rules around regions of type "start".

## Terraformer regions
Terraformer then interacts with the region module api alone to get lists of regions, edit regions, everything. The module enforces its rules at runtime. It also knows how to draws regions grouped however you want.

It writes data to the data dir on save
<TODO Detail>

Note: and eventually, this data dir file(s) would need to be synced over to a specific map key in rowy.

## Mex Income

Adds the Mex Splitting Dropdown to the Transfer Resources section with three options:
* None  -- first come, first serve
* Shared  -- split a teams metal evenly across players
* Map Assigned -- requires the map maker to define regions  of type "mex_region", grouping the mexes on the map. Falls back to None if preconditions aren't met.

In mex_income, we get a region that looks like this:

```lua
{ regions = {
   start = { -- regions of type startbox
       ...
    } , 
    mex_regions = {
       { team=1, name="anti1", group="anti", poly = { { x = 0, y = 0 }, { x = 60, y = 200 } } },  -- two points: a rect
       { team=1, name="carry", group="carry", poly = { { x = 60, y = 40 }, { x = 140, y = 40 }, { x = 100, y = 160 } } },
       { team=1, name="anti_tech_1", group="anti_tech", poly = ... },
       { team=1, name="anti_tech_2", group="anti_tech", poly = ... },
    }
} }
```

So for **Shareable** Mex Income, **Economy** module controls income distribution, so it defines its own type of Region, using region's own enum as the key:

```lua
local Enums = VFS.Include("modules/regions/enums.lua")

return {
	[Enums.Types.MexRegion] = {
		key = Enums.Types.MexRegion,
		label = "Mex region",
		geometries = { Enums.Geometry.Polygon },
		layoutKey = "regions",
		disjoint = true,
		order = 20,
		fields = {
			{ key = "name", label = "Name", kind = "string", unique = true },
			{ key = "group", label = "Group", kind = "string" },
		},
	},
}
```

## Branch Topology

Two stacks.
1) `regions` and `start` need only the runtime and the policies, and are useful without transfer; with the terraformer tool they are a stack of their own off `policies`.
2) `mex restrictions` is enhancements to modules that already exist in the transfer stack. That can move independently.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 28, "rankSpacing": 44, "padding": 12}, "theme": "base", "themeVariables": {"lineColor": "#94a3b8", "fontFamily": "ui-sans-serif, system-ui", "clusterBkg": "#eef2f7", "clusterBorder": "#94a3b8", "titleColor": "#1f2937"}}}%%
graph BT
  subgraph s1["Stack 1 · the loader"]
    runtime("modules #8484")
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
  subgraph s5["Stack 5 · mex splitting (this PR)"]
    regions("regions + start")
    terraformer("terraformer regions tool")
    mexsplit("mex splitting")
  end
  subgraph lobby["Chobby · the lobby side"]
    chobbymodes("Chobby: modes #1041")
    chobbymex("Chobby: mex region layout (branch, no PR yet)")
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
  regions --> policies
  terraformer --> regions
  mexsplit --> regions
  mexsplit -.-> transfer
  mexsplit -.-> tech
  chobbymodes --> game
  chobbymex --> mexsplit
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
  classDef lobbyQuiet fill:#5eb5c4,stroke:#2f7f8d,stroke-width:1.5px,color:#08262b,rx:8,ry:8
  classDef lobbyPending fill:#d7eef2,stroke:#2f7f8d,stroke-width:1.5px,stroke-dasharray:5 4,color:#08262b,rx:8,ry:8
  class runtime,move,policies,modes,providers,docs,defs,game,transport,construction,economy quiet
  class transfer,tech,techcore seen
  class regions,terraformer quietHere
  class mexsplit seenHere
  class chobbymodes lobbyQuiet
  class chobbymex lobbyPending
  style s1 fill:#e8edf3,stroke:#64748b,stroke-width:1.5px,rx:14,ry:14
  style s2 fill:#e3eefb,stroke:#5b8ac7,stroke-width:1.5px,rx:14,ry:14
  style s3 fill:#e6f4e1,stroke:#6a9f52,stroke-width:1.5px,rx:14,ry:14
  style s4 fill:#fdf0dc,stroke:#c9944a,stroke-width:1.5px,rx:14,ry:14
  style s5 fill:#efe6fb,stroke:#8a63c9,stroke-width:2.5px,rx:14,ry:14
  style lobby fill:#e2f4f1,stroke:#3f9c8f,stroke-width:1.5px,stroke-dasharray:6 4,rx:14,ry:14
```
🟩 no gameplay change  🟧 gameplay change  🟦 lobby (Chobby)  ⬛ dark outline: this PR  ┄ dashed node: not opened yet. Boxes are the stacks, in merge order. Solid edges are `requires`; dotted edges are edits to a module this PR does not own.

## LLMs
Mostly fable 5.1 for this one. I've validated every line, description is mine, design is mine.


