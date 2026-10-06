# cm-vehicles service mutation API (authoritative)

Source of truth: `server/main.lua` (section "Trusted vehicle service mutation") and `shared/config.lua` (`Service.TrustedCallers`).
This replaces the older `ServiceVehicle(src, plate, kind)` (API.md) and `ServiceVehicle(source, vehicleIdOrPlate, patch, reason)` (API_PHASE2.md) descriptions, which never matched the shipped export.

## Signatures (server exports only; there is no client path)

```lua
ok, result = exports['cm-vehicles']:ServiceVehicleById(vehicleId, patch, targetSrc?)   -- preferred
ok, result = exports['cm-vehicles']:ServiceVehicle(plate, patch, targetSrc?)           -- legacy, plate-keyed
```

* `vehicleId` – persistent `cm_owned_vehicles.id` (authoritative identity). `plate` – normalised and resolved server-side to a row (`plate` is `UNIQUE`); it is a lookup key only, never a second authority. New callers should use `ServiceVehicleById`.
* `targetSrc` – optional online player used only to pick which client physically re-applies the condition. It never authorizes anything; an invalid/offline value falls back to a broadcast.
* Return: `true, { vehicleId, plate, applied = { field, ... } }` or `false, reason`. Existing callers that test only the first value (`== true`) keep working.

| reason | meaning |
|---|---|
| `forbidden_caller` | invoking resource is not in `Config.Service.TrustedCallers` (audited as `service_denied`) |
| `field_not_permitted` | caller is trusted but the patch contains a field outside its allowlist |
| `unsupported_field` | key is not a serviceable field at all (owner, model, registration, insurance, mods, metadata, keys, garage, money, ...) |
| `invalid_patch` | not a table / empty / non-finite number / wrong type |
| `invalid_vehicle` | no persistent vehicle for that id/plate |
| `vehicle_unavailable` | temporary admin vehicle (no persistent row) |
| `persistence_failed` | the database update failed (nothing was broadcast) |

## Trust

`GetInvokingResource()` is checked against `Config.Service.TrustedCallers` (resource → permitted fields). Same-resource (`cm-vehicles`) calls are allowed. Unknown resources (e.g. `cm-trade`, `cm-phone`, `cm-tuning`) are denied. Proven callers at the time of writing:

| Caller | Purpose | Fields |
|---|---|---|
| cm-mechanic | paid repair commit (absolute patch) | engineHealth, bodyHealth, tankHealth, conditionState, clearVisualDamage |
| cm-carwash | paid wash | dirtLevel |
| cm-gasstations | fuel can / refuel / repair-kit / wash-kit after item consumption | fuel, bodyHealth, dirtLevel |
| cm-law, cm-ems | organization fleet recall baseline | all serviceable fields |
| cm-gang | gang fleet recall baseline | fuel, engine/body/tank health, conditionState, clearVisualDamage |
| cm-vehicles (internal) | repair/wash/fuel items in the G-menu path | all, still validated |

`cm-tuning` is intentionally **not** trusted: its former "engine rebuild" was a plain repair and now belongs to cm-mechanic.

## Patch schema (all optional, at least one required)

`fuel` 0–100 (floored) · `dirtLevel` 0–15 · `engineHealth` / `bodyHealth` / `tankHealth` normalised by `U.NormalizeHealth` (0–1000) · `conditionState` table (sanitised by `U.SanitizeConditionState`) · `clearVisualDamage` boolean (shorthand for an empty `conditionState`). Values are clamped, never coerced from garbage: a non-numeric value is `invalid_patch`, not 0.

## Semantics

* Patches are **absolute target values**. Re-sending the same patch is idempotent; callers must not send increments.
* Persistence is by `id`, then the live entity statebag is updated and `cm-vehicles:client:applyTrustedCondition` is sent; the patch stays in `cmPendingServicePatch` until a controlling client applies and confirms it.
* Non-serviceable data (ownership, mods, registration, insurance) has its own owner exports.
