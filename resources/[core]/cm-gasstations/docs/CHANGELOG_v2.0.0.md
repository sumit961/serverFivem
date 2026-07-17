# v2.0.0 security and UI update

## Security

- Removed client-authoritative fuel amount and final fuel state.
- Added server-side vehicle entity resolution.
- Added fail-closed plate, model, routing-bucket, pump-distance and access checks.
- Added exact pump/vehicle session tokens with expiry.
- Added open/order cooldowns and one active order lock per player.
- Added server-side item quantity clamping.
- Added inventory capacity checks before payment.
- Added component refunds when delivery fails.
- Converted usable vehicle items to server-authorised service patches.
- Added minimum action duration checks for usable items.

## Vehicle behaviour

- Vehicle velocity is cleared when the station opens.
- Handbrake, brake lights and position freeze hold it in place.
- Engine is switched off.
- Closing the UI releases the position and handbrake without auto-starting the engine.

## UI

- Removed native FiveM help text.
- Added custom interaction prompt.
- Rebuilt the station as a compact right-side interface.
- Added vehicle name, plate, secured status, current/target fuel ring, slider and quick-fill controls.
- Added inventory product rows, cash display, calculated total and order result toast.
- Removed all backdrop-filter usage.
