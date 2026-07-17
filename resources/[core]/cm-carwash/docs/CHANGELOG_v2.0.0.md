# v2.0.0

## Security

- Added one-time, expiring server wash sessions.
- Added open/purchase cooldowns and per-player processing locks.
- Added per-vehicle session locks.
- Added fail-closed entity, driver, distance, routing-bucket, plate, model and CM vehicle-ID validation.
- Added CM key/access validation.
- Removed client-authoritative price and completion persistence.
- Server persists the clean state immediately after successful cash payment.
- Payment is refunded if persistence fails.
- Deprecated legacy `requestWash` event can no longer buy or trigger a wash.

## UI and interaction

- Replaced default help text with custom CM cyan E prompt.
- Added compact right-side UI matching `cm-gasstations`.
- Added vehicle name, plate, cleanliness, dirt level, duration, price and cash balance.
- Added animated wash stages and progress.
- Added responsive 1366x768 layout.
- No `backdrop-filter` is used.

## Vehicle handling

- Vehicle stops immediately when the menu is opened.
- Velocity, handbrake, engine and exact position are controlled while secured.
- Exit, throttle, brake and steering controls are disabled during the session.
- Vehicle is released automatically after close/finish/resource stop.
