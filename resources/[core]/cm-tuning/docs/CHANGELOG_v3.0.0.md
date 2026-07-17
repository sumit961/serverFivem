# CM Tuning v3.0.0

## Security

- Removed client-authoritative purchase prices.
- Added one-time server tuning sessions.
- Bound each session to source, plate, vehicle ID, model, network ID, routing bucket, shop type and shop location.
- Added request and purchase cooldowns.
- Added one active tuner per vehicle.
- Added server-side ownership/key validation.
- Added server-side modification allowlists and value limits.
- Added server-authoritative modification merging from the saved vehicle record.
- Added refund and rollback when persistence fails.
- Engine rebuild price now uses live server-side engine health.
- Engine repair is persisted with the secure CM Vehicles service export.
- Harness installation uses the secure CM Vehicles server export.

## Vehicle behaviour

- Vehicle stops immediately after E is pressed.
- Velocity is cleared and the handbrake is applied.
- Vehicle remains frozen in the exact bay position.
- Engine remains off after leaving tuning so the CM Vehicles start system remains authoritative.
- Exit, steering, acceleration and braking inputs are blocked while the vehicle is secured.

## Interface

- Replaced default FiveM help text with a custom cyan E interaction prompt.
- Rebuilt the UI as a compact right-side panel matching CM gas-station styling.
- Added vehicle/plate/secured information.
- Added category state and unsaved-change indicators.
- Added responsive layouts for 1366x768 and ultrawide screens.
- Added NUI ready/render acknowledgements and a visible failure timeout.
- Added processing overlay and error toast.
- Removed all backdrop filters.
- Removed optional chaining and nullish syntax for wider FiveM Chromium compatibility.

## Fixes

- Corrected `respayPrice` to `resprayPrice` while keeping backward compatibility.
- Free downgrades/removals can now be saved.
- Unpaid preview modifications always revert.
- Headlight colours automatically require and price xenon lights.
- Neon and extended visual settings persist in the vehicle mods JSON.
