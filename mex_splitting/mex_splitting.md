
## Mex Splitting User Story

### "None" Mex Splitting

As a **player**, I want nothing to ever change. I will use Chobby with Standard mode, playing Glitters until I die.

### "Map Assigned" Mex Splitting

```md
As a **player**, I want
  to play in lobbies with a set of mexes that are "mine", depending on my start position and the prevailing meta for a given map.
    In game,
      at pre-game start,
        each start's own mex regions are dealt round the players seated at that start, nearest first; regions of a start nobody sits at are dealt round everyone the same way
          if there are too many regions,
            players will receive multiples from the unclaimed pool
          if there are too few regions or invalid regions,
            An error is displayed, "Mex Splitting: Map Assigned is set but mex regions are not configured by the map maker. Please set the 'mex_regions_layout' mod option."
            The game is allowed to proceed with "Mex Splitting: None" behavior.
        I should receive a message informing me that mex building is restricted.
        I should be able to see the mexes that are mine highlighted.
      during the game,
        when building a mex in my own team's territory,
          building a mex in enemy team's regions should be allowed
          if a mex spot is contained any friend region claimed by me,
            that is a valid build target
          for an invalid mex spot,
            I should see
              which mexes I can build (or not) highlighted on the map
              tooltips describing an invalid mex spot
            errors when an existing mex exists (unchanged)
        when a player leaves the game,
          their mex regions should be assigned to their nearest-neighbor, who has been gifted the fewest total number of mex regions
        for allied interactions (like upgrading mexes in my mex regions),
          there is already an orthogonal mod option in transfer that decides that behavior (`unit_sharing_mode`):
            when it lets utility buildings change hands, an ally may build onto my mex on my spot
            otherwise, a spot an ally holds is closed to me

As a **map maker**, I want add mex regions that enclose specific mexes on my map.
  On each mex region, I need to add
    a required team (example: "north", "south"), from a list of teams
    a required group (example: "tech", "anti_canyon")
    an optional name (example: "tech", "anti_canyon_1", "anti_canyon_2")
  On all regions, I need
    to validate that every mex is circled by a region at least once
  I need a save button in Terraformer, so that I can persist my own changes to my bar data directory and see them in my next session.
  I need a publish/Open PR button in Terraformer, so that I can publish my map metadata to other people. (not built: COPY gives the blob, a host `!bset`s it)

As a **BAR Lobby Host**,
  I want to select an option for Mex Splitting: [None, MapAssigned, Shared]
    with tooltips
  (nice to have) if a map doesn't have the metadata to support MapAssigned, warn the lobby
  (nice to have) add a filter to Change Map for only maps with mex regions defined.

As a **BAR AI**,
  I am out of scope for this feature and haven't been considered in depth.
```

### "Shared" Mex Splitting

```md
As a **player**, I want
  to play in lobbies where my team shares all metal income.
    In game,
      at pre-game start,
        I should receive a message informing me that all mex income is shared across the team evenly.
      during the game,
        I should receive mex income equal to my team's total metal extraction income / number of team players.
          (income, not a count of mexes: mexes differ by spot and by tier)
```
