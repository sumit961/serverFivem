# CM-LAW Phase 4: routine convoy robbery

Phase 4 extends the Phase 3 routine Army supply order. It does not create a
second shipment or resupply system. The existing `in_transit` order and its
temporary `cm-vehicles` shipment are the only convoy.

## Authority and state

`cm-law` owns the additive `cm_legal_logistics_cargo` ledger. Each order line
becomes at most one persisted cargo crate after a successful breach. A crate
moves through `available`, `carried`, `dropped`, `extracted`, `delivered`,
`wrecked`, `recovered`, or `expired`. A character can have only one `carried`
crate at a time; this is checked server-side, not inferred from the client
visual.

Robbery handlers re-resolve the character's current membership through
`cm-gang:GetGangForCharacter` and require the configured
`gang.rob_items` permission. The temporary shipment plate, `cm-vehicles`
registry, routing bucket, vehicle speed, rear distance, player alive state,
and all extraction/recovery distances are checked on the server. No client
coordinate, vehicle state, gang ID, or quantity is trusted.

## Outcomes and recovery

The requester receives only `available` or `dropped` cargo at delivery after a
breach. Carried and extracted cargo is excluded, so partial delivery cannot
recreate stolen stock. Extracted cargo is credited through
`cm-gang:AddGangArmoryStock` with a deterministic operation ID. A failed or
interrupted cross-resource credit stays pending and is retried; the gang export
provides the idempotency boundary.

If the temporary vehicle is destroyed while in transit, the order becomes
`wrecked` and remaining vehicle cargo becomes recoverable wreck cargo with an
expiry. Army logistics can recover it at the saved wreck location using
`law.logistics.recover`; it is returned to Army stock through the existing
logistics ledger. Disconnects, dead carriers, resource restarts, and expired
crates reconcile to persisted dropped/expired states rather than silently
deleting cargo.

## Configuration and interaction

`Config.Logistics.Robbery.ExtractionPoints` must contain operator-approved
`{ id, x, y, z, bucket }` entries (or a gang-ID keyed list). It is empty by
default intentionally: extraction is fail-closed until safe locations are
configured. No gang HQ or law facility location is guessed.

The client adds only nearby world prompts and local crate/carry visuals:

1. Stop an active shipment and press **E** at its rear to breach it.
2. Press **E** at an available or dropped crate to carry it.
3. Press **E** away from an extraction point to drop it, or at a configured
   extraction point to extract it.

There are no gang notifications, dashboard robbery cards, blips, route
broadcasts, location broadcasts, or event scoreboard. Nearby physical visual
updates are sent only to players within the configured visual radius.

The additive cargo table is created/reconciled by `server/logistics.lua` beside
the Phase 3 tables. Existing Phase 3 order rows are upgraded with guarded
columns; no destructive migration is performed automatically.
