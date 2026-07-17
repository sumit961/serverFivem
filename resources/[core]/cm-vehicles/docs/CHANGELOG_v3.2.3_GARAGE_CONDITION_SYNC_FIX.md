# cm-vehicles v3.2.3 – Garage condition sync fix

- Fixed the vehicle-information UI showing a destroyed `0` engine as `100%` because JavaScript used `value || 1000`.
- Added replicated engine/body/tank/dirt condition state for registered vehicles.
- Prevented transient server-native `0` readings from corrupting persisted vehicle health.
- Garage vehicles remain fully visible and targetable but are damage-proof while frozen in their slots.
- Starting a garage vehicle removes protection and restores the saved condition before enabling the engine.
- Promoting/calling a garage vehicle clears garage protection.
