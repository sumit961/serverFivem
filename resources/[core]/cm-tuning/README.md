# CM Tuning v3.0.0

Secure performance and visual tuning for the CM vehicle system.

## Required order

```cfg
ensure oxmysql
ensure cm-playerdata
ensure cm-vehiclekeys
ensure cm-vehicles
ensure cm-tuning
```

This version is designed for `cm-vehicles` v3.1.0 or newer and uses:

- `GetVehicleByPlate`
- `HasVehicleAccess`
- `SaveVehicleModsAuthorized`
- `ServiceVehicle`
- `InstallRacingHarness`

## Main behaviour

- The player must be in the driver seat.
- The exact registered network vehicle is validated server-side.
- The vehicle is stopped, handbraked, switched off and frozen while the UI is open.
- Preview changes are local and are reverted when the player cancels.
- The client sends selected parts only; it never sends an authoritative price.
- Prices are recalculated from `shared/config.lua` on the server.
- Approved modifications are persisted only after successful payment.
- Failed persistence is refunded and rolled back.
- Cash and bank can be enabled or disabled separately.

## Configuration

The most important settings are:

```lua
CMTuning.Config.defaultAccount = 'cash'
CMTuning.Config.allowCash = true
CMTuning.Config.allowBank = true
CMTuning.Config.requireDriver = true
CMTuning.Config.requireOwnership = true
```

Change shop coordinates under `Config.Shops`.

## UI

The resource uses a custom cyan E prompt and a compact right-side interface. It does not use FiveM's default help menu and contains no `backdrop-filter`.
