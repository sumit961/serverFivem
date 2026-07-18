# Validation matrix

Maps change type to what to check. Pick the row(s) matching the change;
combine rows for changes that span categories (e.g. a database + NUI
change uses both rows).

**Static and contract-map checks establish that code is syntactically
sound and that known contracts still resolve. Neither proves runtime
behavior in FiveM.** Manual FiveM tests are required for anything that
actually runs in-game; never report a change as verified based on static
checks alone.

| Change type | Static checks | Contract-map checks | Security checks | Required manual FiveM tests |
|---|---|---|---|---|
| Lua-only (server or client) | Lua syntax valid; no accidental global leakage | Re-run CM scan; confirm no event/export/command contract the file defines was accidentally renamed/removed | Server authority if the file handles client input | Load the resource, exercise the changed code path in-game, watch server console for errors |
| Network event change (add/rename/remove) | Syntax valid | CM scan: confirm the event's producer/consumer relationship still resolves on both sides; check for now-`unresolved_no_handler` or `untriggered_handler` entries | Full security-review.md pass on the handler | Trigger the event from both realms where applicable; confirm the handler fires exactly once and behaves correctly for an unauthorized/invalid case |
| Export change (add/rename/remove signature) | Syntax valid | CM scan: check every consumer resolves; grep source for the old export name across resources if renamed | Realm (client/server) match between definition and every consumer | Start a resource that consumes the export; confirm no `attempt to call a nil value` or resolution failure in console |
| Database query/schema change | Query syntax review; migration script reviewed | CM scan: confirm affected tables' read/write/schema entries match intent; check no other resource silently depends on a column/table being removed | Dynamic SQL, parameterisation, transaction/idempotency | Run the migration against a non-production copy; exercise the read/write paths; confirm no other resource errors on the new schema |
| NUI JS/HTML/CSS change | JS syntax valid; no console errors on load | CM scan: confirm `fetch()`→`RegisterNUICallback` relationships still resolve; check `nui_relationships` for new mismatches | NUI trust: validate payload shape server-side | Open the NUI in-game, exercise every interactive element, confirm callbacks round-trip and the UI closes/opens cleanly |
| `cm-ui` (shared UI primitives) change | JS/CSS syntax valid | CM scan + source grep: identify every resource consuming the changed primitive (shared components fan out widely) | N/A unless the primitive itself handles input | Exercise the primitive in at least the two or three most prominent consumer resources, not just one |
| Vehicle-state change (spawn/condition/ownership/persistence) | Syntax valid | CM scan: confirm `MySQL.*` operations on vehicle tables and any related events/exports still resolve | Vehicle spawning/duplication, ownership, persistent ID handling (security-review.md) | Spawn, store, and recall a vehicle; confirm condition/fuel/mods persist correctly and no duplicate vehicle record is created |
| House/garage change | Syntax valid | CM scan: confirm house/garage-related tables and cross-resource events (e.g. to `cm-family`/`cm-vehicles`) still resolve | House/family access, ownership | Buy/sell or access a house as owner and as a non-owner (expect denial); test garage store/recall |
| Family/rank/permission change | Syntax valid | CM scan: confirm ACE/permission entries and rank-check call sites still match intended strings | Full permission/rank/ownership section of security-review.md | Test the changed permission as an authorized and an unauthorized member; confirm rank-gated UI/actions match server-side enforcement |
| Performance change (no behavior change intended) | Syntax valid; confirm no behavior actually changed by diff review | CM scan: confirm no contract accidentally changed as a side effect | N/A unless the optimization touches a security-relevant check | Profile/observe the specific hot path in-game or via server console timing; confirm no regression in the exercised feature |
| Resource manifest/start-order change | `fxmanifest.lua`/`__resource.lua` syntax valid | CM scan: resource discovery still finds the resource correctly; re-check nested-manifest flags if paths moved | Confirm no dependency resource loses its declared start-order relationship | Restart the server (or `refresh`/`ensure` the resource) and confirm it starts without dependency errors |
| Release preparation | Full diff review across all changed resources | Full CM scan + `--check`; refresh Graphify if call graphs changed materially | Full security-review.md pass on every privileged change in the release | Smoke-test every changed feature end-to-end on a non-production server before any deployment approval |
