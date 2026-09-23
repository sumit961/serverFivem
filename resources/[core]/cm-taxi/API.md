# CM Taxi Runtime Contracts

These events are owned by `cm-taxi`. Server handlers treat client arguments as untrusted and use the event source as the active session identity. Character IDs and player session IDs are not sent to the dispatch UI.

## Commands

| Command | Behavior |
|---|---|
| `/taxi`, `/texi` | Creates a real player passenger request at the caller's current location. |
| `/taxicancel` | Cancels a pending request, including an assigned pickup before boarding. It cannot cancel a ride after the passenger boards. |

## Client to server

| Event | Payload | Behavior |
|---|---|---|
| `cm-taxi:server:cancelTaxiRequest` | none | Cancels the source player's request before boarding. |
| `cm-taxi:server:boardPassenger` | `requestId`, `fareId` | Confirms the requester is in the assigned taxi and the assigned driver is driving it. Replies through `cm-taxi:client:boardPassengerResult`. |
| `cm-taxi:server:passengerAbandoned` | `fareId` | Cancels a boarded request only if the passenger died, left the assigned taxi, and is not at the destination. |
| `cm-taxi:server:boardJob` | `requestId`, `fareId` | Confirms an NPC passenger boarded the source driver's taxi. Replies through `cm-taxi:client:boardJobResult`. |
| `cm-taxi:server:finishJob` | `requestId`, `fareId` | Completes a ride after server-side driver, taxi, passenger, and destination checks. Payout is locked against duplicate completion. |

## Server to client

| Event | Payload | Recipient |
|---|---|---|
| `cm-taxi:client:playerFareOffers` | Offer list with pickup distance and nearby status | On-duty taxi drivers in the caller's routing bucket; pickup coordinates are scoped to these drivers. |
| `cm-taxi:client:taxiRequestStatus` | `status`, request data such as ETA, assigned taxi network ID, or destination | The player who called `/taxi` or `/texi`. |
| `cm-taxi:client:startJob` | `fareId`, optional private player-request route data | Assigned driver. Player-request coordinates are sent directly, not through global fare state. |
| `cm-taxi:client:playerFareBoarded` | `fareId`, destination | Assigned driver after server validation. |
| `cm-taxi:client:boardPassengerResult` | `requestId`, `{ success, finish? }` | Requesting passenger completing boarding. |
| `cm-taxi:client:boardJobResult` | `requestId`, `{ success }` | Driver completing NPC pickup validation. |
| `cm-taxi:client:shiftStats` | `{ completed, earnings, tips }` | Driver on the current shift. |
| `cm-taxi:client:jobCancelled` | message string | Driver whose assigned fare was cancelled or timed out. |

Request status values are `queued`, `accepted`, `searching`, `expired`, `cancelled`, and `completed`. Calls expire according to `FareExpiryMs`; assigned pickups and boarded rides also have separate time limits. Player-request pickup and destination coordinates are omitted from `GlobalState.cmTaxiFares`.

Shift totals remain in memory and reset when the driver starts a new shift. Tips are calculated by the server from pickup time and taxi body-health change; clients do not submit reward values.
