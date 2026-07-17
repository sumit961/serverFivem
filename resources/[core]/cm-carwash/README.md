# CM Car Wash v2.0.0

Secure cash-only automatic vehicle washing for the CM framework.

## Main behaviour

- Uses a custom NUI `E` interaction prompt; no default FiveM help menu.
- Uses the same compact cyan/right-side visual language as `cm-gasstations`.
- Stops, handbrakes, switches off and freezes the vehicle in its exact position.
- Keeps the vehicle secured until the menu closes or the paid wash completes.
- Accepts cash only through `cm-playerdata`.
- Server creates a one-time session tied to the exact vehicle, plate, CM vehicle ID, model, driver, routing bucket and wash location.
- Server calculates the configured price and persists dirt through the secure `cm-vehicles:ServiceVehicle` export.
- The client only handles visuals and gradually removes visible dirt.

## Required resources

```cfg
ensure cm-playerdata
ensure cm-vehiclekeys
ensure cm-vehicles
ensure cm-carwash
```

`cm-hud` is optional and is used for notifications when available.

## Configuration

Edit `shared/config.lua` to change:

- cash price;
- wash duration;
- interaction distance;
- clean/dirt thresholds;
- vehicle access requirements;
- wash locations and blips.

The coordinates should be the centre of the position where the car must remain during the wash.

## Security notes

Do not restore the old direct `requestWash` payment flow. It is retained only as a harmless compatibility notice and cannot start a wash. All purchases must use the server-created NUI session.


## v2.0.2 interaction fix

- The custom E prompt and wash panel are available only from the driver seat.
- Wash-zone detection now uses the vehicle position rather than the ped position.
- Added an NUI readiness handshake and automatic message replay so the first prompt/open message is not lost on resource start or slow clients.
