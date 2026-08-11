# RN Vehicleshop — CM Update Notes

## Kept intentionally

- `this_is_a_map 'yes'` remains in `fxmanifest.lua` because the resource streams/uses the capture prop.

## Payment

- Purchases and paid public test drives use combined `cm-playerdata` cash + bank.
- Default order is cash first, then bank for any remainder.
- Partial debit failures are rolled back.
- Purchase registration failures and test-drive start failures refund the original account split.
- Configure the debit order in `Config.Payment.Priority`.

## Vehicle validation and appearance

- Client model loading validates both `IsModelInCdimage` and `IsModelAVehicle`.
- RGB is clamped to 0–255 and GTA colour indexes to 0–160.
- Vehicle price is server-clamped by `Config.Security.MaxVehiclePrice`.
- Extras are no longer globally disabled.
- Configure per-model livery/extras in `Config.VehicleDefaults`.

Example:

```lua
Config.VehicleDefaults = {
    ['yourmodel'] = {
        livery = 0,
        extras = {
            [1] = true,
            [2] = false
        }
    }
}
```

## Admin

- Rebuilt the admin UI as a compact dark/cyan catalog manager with readable typography, one scrolling vehicle list, status chips, grouped settings, and sticky actions.
- The centre remains transparent and unobstructed for the live vehicle.
- The admin camera now points directly at the vehicle with a closer 42° framing.
- The neutral midday admin environment is continuously reapplied while admin is open so `cm-climatime` cannot make the preview nearly black.
- Selecting a vehicle previews it in the admin studio.
- **Test Vehicle** starts a free admin test drive and returns to the admin studio afterward.
- Runtime tuning commands `/gstune`, `/gsscale`, `/gsaxis`, `/gsz`, `/gsveh`, `/gsshot`, and `/gsdump` were removed.

## Logging

Purchase, test-drive, catalog-edit, and image-capture actions use the structured adapter in `Config.Logging`.

The adapter tries these `cm-admin` exports by default:

- `AddLog`
- `CreateLog`
- `Log`

It then emits `cm-admin:server:addLog` as a compatibility fallback and writes a console audit line when no adapter confirms delivery. Update `Config.Logging` if your `cm-admin` uses a different export or event name.

## Validation performed

- JavaScript syntax check passed with Node.
- Changed Lua blocks were reviewed structurally; a Lua compiler was not available in the packaging environment.
- Duplicate HTML IDs: none.
- CSS brace validation passed.
- No removed `/gs*` command registrations remain.
- No `backdrop-filter` declaration remains.


## V3 admin stability and auto-discovery
- Removed the accidental full-screen admin background caused by a legacy high-specificity CSS rule.
- Reduced both admin panels to compact centered drawers and kept the world/vehicle viewport fully transparent.
- Prevented duplicate preview respawns and slowed weather reassertion to remove visual blinking.
- Added automatic scanning of started resources for nested `vehicles.meta` files.
- Added a manual rescan button; newly discovered vehicles appear hidden until saved/enabled by an admin.
- Added resource provenance and client model validation to the catalog list.

## Runtime catalog manager

- `/managevehicle` opens the same secured catalog manager as `/vehicleadmin`.
- The first authorized manager open per client session enumerates FiveM's live registered vehicle models and seeds missing civilian land vehicles into the store without overwriting existing rows.
- Emergency, military, aircraft, watercraft, and rail models remain visible but disabled by default.
- Catalog top speed is editable in km/h. New store purchases persist the limit in owned-vehicle metadata; Police/EMS fleet appearance payloads carry the same limit.
