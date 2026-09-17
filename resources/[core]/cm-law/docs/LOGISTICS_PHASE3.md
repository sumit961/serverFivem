# CM-LAW Phase 3: routine military logistics

## Ownership and architecture

`cm-law` owns the order state machine and the additive
`cm_legal_logistics_orders`, `cm_legal_logistics_order_lines`, and
`cm_legal_logistics_ledger` tables. Army inventory is the existing
`cm_legal_armory_stock` ledger. No player/container inventory is created for a
shipment.

The requestable list is `Config.Logistics.RequestableItems` in
`shared/config.lua`. Each name is checked at runtime against the enabled
`cm-weapons` weapon/ammunition catalog, a physical `cm-items` item, or the
authoritative `cm-gunstore` armor catalog (which syncs armor into
`cm-items`). Labels and descriptions are resolved from those resources; item
names are never accepted from the client unless they are in this allowlist.

`cm-vehicles` supplies one temporary, owner-restricted `barracks` shipment
vehicle per order. It is not a persistent vehicle and has no `vehicle_id`.
`cm-law` was added to the existing trusted temporary-placement allowlist.

## State machine

`requested -> accepted -> prepared -> loaded -> in_transit -> delivered`

An order may be cancelled while open. Army acceptance atomically reserves
the requested quantities from Army armory stock and writes a reservation
ledger row for every line. Cancellation releases those rows once. Delivery
uses per-line transfer ledger rows and one stock-lock/SQL transaction, so a
retry cannot duplicate destination stock. A delivered order is idempotently
reported as already delivered.

If the temporary vehicle is missing during startup or after a
`cm-vehicles` restart, a prepared/loaded/in-transit order is safely returned to
`accepted` with its Army reservation intact. Army quartermasters can also use
**Recover** at the Army armory. The vehicle is deleted after a successful
delivery or cancellation.

## Permissions and limits

The additive permissions are:

* `law.logistics.request` — submit a request from the requesting org armory.
* `law.logistics.accept` — Army acceptance and stock reservation.
* `law.logistics.prepare` — create the temporary shipment vehicle.
* `law.logistics.load` — load and depart the shipment.
* `law.logistics.deliver` — deliver at the saved receiving point.
* `law.logistics.cancel` — cancel/release an order.
* `law.logistics.recover` — reset an interrupted shipment to `accepted`.

The default rank ladder grants request access to members and the operational
actions to supervisors and leaders. Leaders retain the existing bypass
behaviour. Existing installations keep their database rank permissions
authoritative; an organization leader can grant the new permissions from the
existing Ranks & Access page. All operations additionally require on-duty membership; source
organization and requester organization are derived server-side.

Limits are configurable in `Config.Logistics`: three open orders per
organization, eight lines per order, 1,000 per line, and 5,000 total units.
`DeliveryRadius`, shipment model, and `DefaultReceivingMaxStock` are also
configuration values. Optional
`ReceivingPoints[organizationId]` entries use `{ x, y, z, heading, bucket }`;
when absent, the organization's configured armory facility is snapshotted as
the receiving point.

## Interaction

The existing `cm-law` dashboard has a Logistics tab. A requester submits an
item and quantity there while standing at their armory. Army quartermasters
accept, prepare, load, depart, deliver, cancel, or recover from the same tab.
The server, not the tab, validates every action. Delivery requires the driver
to be in the exact temporary shipment vehicle and at the saved receiving
point.

Trusted integrations may use the read-only exports
`GetLogisticsRequestableItems()` and `GetLogisticsOrder(orderId)`. The
namespaced callbacks are `cm-law:server:logistics`,
`cm-law:server:logisticsCreate`, and
`cm-law:server:logisticsAction`.

## Future robbery extension

A later robbery feature should add a separate, audited transition and
physical-world interaction around an in-transit shipment. It must not mutate
the current delivery path from the client or bypass the reservation/transfer
ledger. Any robbery outcome should be represented as new `cm_legal_*` ledger
actions and retain idempotency, recovery, and Army/requester authorization.
This v1 intentionally adds no gang resource or notification integration.
