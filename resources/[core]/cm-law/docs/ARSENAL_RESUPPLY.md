# CM-LAW Phase 5 — Arsenal Resupply

Arsenal Resupply is a separate rare major event. It never uses or changes
`cm_legal_logistics_orders`, so routine Phase 3/4 deliveries remain silent to
gangs and retain their existing behaviour.

## Authority and flow

`cm-law` owns the state machine:

`IDLE -> WARMUP -> ARMY_PREPARATION -> CONVOY_ACTIVE ->
WAREHOUSE_UNLOADING -> ENDING -> COMPLETED`

An administrator can cancel, and a restart marks an active run
`INTERRUPTED`, preserves completed credits, and marks unresolved cargo lost.
A start requires the configured number of on-duty Army members. The configured
manifest is checked against `cm-weapons`/`cm-items` before the configured
normal-world lead escorts, cargo trucks, and rear escorts are spawned.
Manifest quantity is split into configured crate sizes across the actual cargo
trucks without changing the total incoming quantity.

The manifest is new incoming stock. Starting a run never removes or reserves
existing Army warehouse stock. Only cargo actually unloaded or recovered by
Army is credited to the warehouse.

Cargo is persisted per truck. Breach, carry, drop, extraction, death,
disconnect, expiry, wreck recovery, and pending gang credit are server
validated. Gang stock credit uses `cm-gang:AddGangArmoryStock` with a
deterministic operation ID. Army unloading and recovery use the separate
`cm_legal_arsenal_stock_ledger`; repeated requests cannot duplicate stock.
Weighted manifest value is conserved across Army-secured, gang-extracted, and
lost outcomes. Army and participating gangs compete by secured cargo value.

Gang notifications contain only the configured approximate route intelligence.
No route coordinates, gang GPS, route blips, or server-wide gang
notifications are emitted. Only a gang that breaches/claims/extracts becomes a
participant and receives the result quick-view notification through the
existing cm-gang event presentation path.

## Admin/config surface

All exported admin methods require `cm-admin` character-ID permission
`orgs.manage` through `cm-law:adminAllowed`; no client coordinates are trusted.

* `AdminGetArsenalResupply(source)`
* `AdminConfigureArsenalResupply(source, data)`
* `AdminSaveArsenalManifest(source, { item, quantity, crateSize, valueWeight })`
* `AdminDeleteArsenalManifest(source, item)`
* `AdminCaptureArsenalRoutePoint(source, routeId, 'start'|'waypoint_add'|'waypoint_remove'|'destination', data?)`
* `AdminDeleteArsenalRoute(source, routeId)`
* `AdminCaptureArsenalExtractionPoint(source, { gangId?, radius? })`
* `AdminDeleteArsenalExtractionPoint(source, extractionId)`
* `AdminStartArsenalResupply(source)` / `AdminCancelArsenalResupply(source)`

The existing Gang Dashboard shows the public event card and only the permanent
history of runs in which the current authoritative gang participated. The
existing Army Logistics dashboard exposes authoritative event history only to
on-duty Army members. The existing CM Admin Gangs/Events screen owns schedule,
convoy composition, manifest, route/waypoint, extraction, gameplay, and manual
start/cancel controls. Routine logistics remain private and separate.

Convenience commands are `/cm_arsenal_start`, `/cm_arsenal_cancel`,
`/cm_arsenal_capture_route <routeId> <start|destination>`, and
`/cm_arsenal_capture_extraction [gangId]`. The event is disabled until an
administrator enables it and configures a valid route, manifest, and
extraction point. The SQL migration is
`sql/012_cm_law_arsenal_resupply.sql`; it is additive and repeatable.

`/cm_arsenal_check [runId]` compares the immutable incoming manifest with every
persisted cargo terminal/non-terminal state and emits an error only when the
conservation invariant fails. Cargo transfer to getaway vehicles is deferred
and is not implemented in this pass.

## Development multiplayer test controls

Use the existing CM Admin Arsenal panel to start or cancel a run without
waiting for the daily schedule. Console or an authorized administrator may use
`/cm_arsenal_start`, `/cm_arsenal_cancel`, and `/cm_arsenal_check [runId]`.
Normal players cannot use these controls. Before starting, configure a valid
manifest, route, extraction point, and the required number of on-duty Army
members. Test with one, two, then three cargo trucks and run the invariant check
after creation, breach, extraction, recovery, unloading, and completion.

Use at least three player roles for recipient/security testing: on-duty Army,
an active gang member, and a civilian or non-Army law member. A second gang is
required to verify dropped-cargo reassignment and participant-only results.

### Existing control map

| Control | Location | Permission | Console | Authorized admin | Normal player |
| --- | --- | --- | --- | --- | --- |
| Start now | CM Admin Gangs/Events and `cm_arsenal_start` | `orgs.manage` | Yes | Yes | No |
| Cancel | CM Admin Gangs/Events and `cm_arsenal_cancel` | `orgs.manage` | Yes | Yes | No |
| Current status/run ID | CM Admin Gangs/Events and `cm_arsenal_status` | `orgs.manage` | Yes | Yes | No |
| Cargo invariant | `cm_arsenal_check [runId]` | `orgs.manage` | Yes | Yes | No |

Manual start does not bypass event enabled state, minimum on-duty Army count,
Supply War exclusivity, catalog validation, route validation, or duplicate-run
protection. A refused start prints the eligible and required Army counts.

### Recommended temporary configuration

Do not overwrite production settings automatically. For the first development
session, temporarily configure warmup 30 seconds, preparation 30 seconds,
maximum duration 10 minutes, one cargo truck, zero or one lead/rear escort,
breach and unload durations of 5-10 seconds, quick result 30 seconds, and intel
interval 30 seconds.

Create a short route with the existing Admin position picker: Army start, one
nearby waypoint, then a nearby Army warehouse destination. Add a nearby
extraction point. Do not hard-code these coordinates.

A manageable manifest using current valid IDs is:

* `ammo_556nato`: quantity 1000, crate size 250, value weight 2.
* `ammo_9x19_smg`: quantity 500, crate size 250, value weight 2.
* `armor`: quantity 5, crate size 1 or 5, value weight chosen for the test.

Confirm each ID through the Admin editor; authoritative catalog validation
still rejects an ID disabled or unavailable in the running server.

### First multiplayer test sequence

Players: Client 1 on-duty Army; Client 2 Gang A; Client 3 Gang B if available;
Client 4 civilian/non-Army observer if available. Army plus one gang is the
minimum useful starting group.

1. Complete a routine Police/FIB supply delivery first. Gang clients must see
   no Arsenal notification, active card, intel, blip, or result.
2. Run `cm_arsenal_status`, start through CM Admin or `cm_arsenal_start`, and
   inspect status through WARMUP, ARMY_PREPARATION, and CONVOY_ACTIVE. Record
   the single run ID and run `cm_arsenal_check <runId>` after cargo creation.
3. Confirm Gang A receives the announcement, the civilian does not, and Army
   receives only Army operational routing.
4. With one cargo truck, stop and breach it, extract one gang crate, drop and
   recover one crate as Army if possible, deliver the truck, time the unload,
   then verify completion, J result, Gang history, Army history, and invariant.
5. Only after the one-truck lifecycle passes, test Gang A dropping on death and
   Gang B claiming/extracting that crate.
6. Repeat with two and then three cargo trucks. Check the invariant after
   creation, breach, extraction, unload, and completion.
7. During a partial run, secure one Army unit, extract one gang unit, leave
   cargo unresolved, and restart `cm-law`. Verify INTERRUPTED, preserved
   completed credits, unresolved cargo lost, and no duplicate manifest.
8. Finally run Supply War and verify its card, notification, join, HUD, result,
   J quick view, and history remain independent.

## Compatibility/blockers

The current framework has no authoritative AI convoy-driver API. The
fail-closed implementation therefore spawns normal temporary vehicles but
does not invent NPC drivers or client-directed remote driving. Army players
must drive and unload the convoy. Exact in-game multiplayer validation remains
manual.
