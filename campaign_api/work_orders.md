# Work orders from the stage reviews

Written 2026-07-26 after reviewing all five stack commits. Each order is
self-contained: a subagent should be able to work from one of these plus
`execution_handbook.md` without reading the reviews.

Read `savegame_and_state.md` first — it invalidates several findings that the
reviews reported in good faith.

## Rules that apply to every order

- **Do not run git.** No commit, no branch, no checkout, no stash. Make the
  edits, leave them in the working tree, report the diff. Placing changes on the
  right stage commit is a restack (`just bar::mission-restack`) and is not the
  agent's job.
- **Disjoint file sets.** Orders A and B both touch `mission_loader.lua`; they
  must not run concurrently. C is disjoint from both.
- **BAR files are CRLF.** Never `sed -i`, never a `$`-anchored regex. Use the
  Edit tool or byte-preserving python.
- **Terse comments.** Rationale goes in review discussion, not in the code. No
  `Co-Authored-By`, no AI attribution.
- **Every claim needs a gate that can fail for the specific hazard.** Report the
  command and its verbatim output. State what the gate cannot see.

## Order A — reload semantics

The highest-value work in the stack. Reload is the primary authoring workflow
and it is broken four independent ways. Files: `modules/missions/gadgets/
mission_loader.lua`, `modules/missions/lib/trigger_engine.lua`.

1. **Stale triggers are never unregistered** (`mission_loader.lua:190-192`).
   `loadMission` unregisters only files in the *incoming* listing, so a renamed
   or deleted trigger file stays armed and every effect runs twice; switching
   missions leaves the previous mission evaluating and able to end the new one.
   Needs an `UnregisterAll`-style API on the engine (it has only
   `UnregisterFile`), or unregistration driven by what is *registered* rather
   than by what is being loaded.
2. **Objective rulesparams survive a reload** (`:93` vs `:192`).
   `UnregisterFile` clears `state.fired`; the `objective_*` rulesparams the
   loader's own comment calls part of the same progress pile are never reset, so
   reloading a mission whose objective completed fires victory on the next
   cadence. Clear them with the triggers.
3. **A failed load leaves the mission half-armed** (`:327-332` before `:363`).
   Trigger includes are unprotected, unlike `parseRoster` which is pcall'd. The
   unregister happens *first*, so a typo'd trigger file destroys the running
   mission's state and arms a partial one. Load into a staging set and commit it
   only once every file has parsed.
4. **`spawnRoster` is unprotected** (`:404`) and `Spring.CreateUnit` **raises**
   on an unknown def name — verified in engine source, it returns nil only on
   unit limit. So the guard at `:263-268` cannot produce the graceful failure it
   advertises. Check `UnitDefNames[entry.def]` before the call.

Gate: a busted spec per item, each red before the fix. The reload cases are
pure-Lua state transitions, so they spec cleanly without a game.

Do **not** add `gadget:Save`/`Load` — see `savegame_and_state.md`.

## Order B — the combat contract

Files: `modules/combat/**`, plus `.Until` registration at
`mission_loader.lua:379-388` and `modules/missions/lib/verbs.lua:132-137`.

1. **`Protect` is not untargetable.** `AllowWeaponTarget` fires only for
   weaponDefIDs registered via `Script.SetWatchAllowTarget`/`SetWatchWeapon`,
   and combat registers neither. Either register (noting the toggle is global
   per-weaponDefID and shared with `unit_defend_firestate`, which un-watches
   unconditionally) or **correct the contract** in `api.lua:15` and the gadget
   desc. Do not leave the annotation claiming behavior the code does not have.
2. **The non-protected return clobbers other gadgets** (`combat_rules.lua:44`).
   `gadgetHandler:AllowWeaponTarget` is unconditional last-writer-wins with no
   nil filter, and combat is inserted last at layer 100 — so while anything is
   protected, AA target weighting and defend-firestate vetoes are discarded.
   Returning nothing is worse, not better. This needs a real answer, and it may
   be an engine/handler-level one.
3. **`.Until` is a standing trigger, not a lifetime.** It registers at file load,
   armed immediately, with nothing tying it to the `Protect` having fired — so a
   companion that fires first retires permanently and leaves the unit protected
   forever. Bind the companion's arming to the effect's execution. This is the
   tense violation the design forbids; treat it as a design fix, not a patch.
4. **Refcounting.** `.Until` makes overlapping protections expressible over a
   set-not-refcount primitive. Either refcount, or reject two lifetimes on one
   unit at load.
5. **The modoption spec proves nothing** (`spec/modules/combat/
   modoptions_spec.lua:57-65`) — it asserts merging is byte-neutral in a state
   where the merged list is empty. A later stack commit already rewrote it;
   carry that rewrite down to this commit rather than inventing a third form.

Skip the ledger serialization finding — the creg save restores it.

## Order C — editor cost and correctness

Files: `modules/missions/widgets/mission_bridge.lua`,
`modules/missions/rml_widgets/mission_editor.lua`. Disjoint from A and B.

1. **Gate both widgets on dev mode.** Today `enabled = true` plus the module
   widget autoload means every player writes a >100 KB `domains.json`, plants
   `modules/missions/.editor/` in their data dir, parses an RmlUi document they
   never see, and polls a nonexistent file at 2 Hz forever. Use the
   `Spring.Utilities.IsDevMode()` early return that `dbg_ceg_auto_reloader.lua`
   and friends use. This also closes the unattended synced-reload path.
2. **Do not republish a constant.** `domains.json` is the same bytes every run —
   derived only from `UnitDefs`. Write it when missing or stale, not on every
   Initialize.
3. **Validate before consuming the generation** (`:132-147`). `lastGeneration`
   is assigned before the payload is decoded, so a torn read is never re-read,
   and the reload fires on a payload that failed to decode.
4. **Armed-state coherence** is *not* a bug — see `savegame_and_state.md`.

## Order D — the whole-file CAS hash (kit repo)

`BAR-Devtools/bar-mission-kit`. `EditIntent.base_hash` is a hash of the entire
file (`model.rs:26-29`, checked in `serve.rs`), so two edits from one view
generation collide: the first applies, the second is rejected as "file changed
on disk", deleted, and never retried — the user's second edit silently reverts.
Needs either a span-scoped hash or rebase-and-retry on rejection. The write path
itself is byte-exact and now line-ending-preserving; do not re-litigate that.

## Not yet ordered

- **CM8 has no headless test.** Nothing in BAR's CI reads its trigger files. The
  static checker that would catch name errors lives in the kit repo and is not
  wired into this repo's CI. Worth its own order once A lands.
- **`UnitDef` and `Objective` names are unvalidated** — the two holes in "names
  declared once". `UnitDef` is checkable at load (`UnitDefNames` is available in
  synced code); `Objective` needs a declaration site that does not exist yet.
- **`resolveEnemyTeam`** (`mission_loader.lua:200-209`) picks the first non-gaia
  team that is not the player's, so in co-op the enclave may spawn onto a human
  ally.
- **Prove the save actually round-trips.** Arm a mission, complete an objective,
  save, load, confirm the trigger set and ledger return.
