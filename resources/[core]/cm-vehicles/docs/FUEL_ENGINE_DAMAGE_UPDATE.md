# Fuel + Engine Damage Update

This build fixes the issue where spawned vehicles keep showing around 60% fuel.

## What changed

- On spawn, `cm-vehicles` now applies the database fuel value to the GTA native fuel level and to entity state `cmFuel`.
- The vehicle information UI now reads live fuel from the spawned entity when possible.
- The save loop now saves `cmFuel` instead of the random native fallback.
- `cm-vehicles` includes simple standalone fuel consumption, so fuel no longer stays unchanged forever.
- Manual engine shutoff is blocked above 20 km/h.
- A hard crash/impact shuts the engine off.
- After a hard impact, pressing the engine key starts a 5-second restart sequence.

## Existing cars already saved as 60 fuel

If old testing saved every vehicle with 60 fuel, those rows will still show 60 because the database has 60. To reset existing cars to full fuel, run:

```sql
UPDATE cm_owned_vehicles SET fuel = 100 WHERE fuel = 60;
```

New spawned vehicles will no longer randomly fall back to 60 unless the database fuel value is actually 60.

## Config values

Edit `shared/config.lua`:

```lua
Engine = {
    manualStopMaxSpeedKmh = 20.0
},

Fuel = {
    defaultFuel = 100.0,
    consumeEnabled = true,
    consumeIntervalMs = 5000,
    idleDrainPerMinute = 0.04,
    speedDrainPerMinute = 0.16,
    rpmDrainPerMinute = 0.22
},

Damage = {
    hardImpactMinSpeedKmh = 35.0,
    hardImpactDeltaKmh = 28.0,
    restartDelayAfterImpactMs = 5000
}
```


## 2026-07-02 adjustment
- Severe crash engine shutoff now uses the same crash level as the seatbelt ejection check. Small bumps no longer shut the engine off.
- After a severe crash, restart delay remains 5 seconds.
- Fuel consumption now checks both cm-vehicles engine state and the native GTA engine-running state, so fuel still drains if another script turns the engine on.
- Fuel drain defaults were increased slightly and UI fuel can show decimals, making testing easier.
- Menu entity lookup now safely falls back to DB payload values if the network entity is not visible on the client.
