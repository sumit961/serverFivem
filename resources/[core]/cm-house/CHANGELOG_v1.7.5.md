# cm-house v1.7.5 — cm-family per-vehicle access hook

## Added
- `checkSeatAccess` (server/sv_garage.lua) now consults cm-family's
  `CanUseFamilyVehicle(cid, vehicleId, 'spawn')` export when a member spawns a
  **family** vehicle. This enforces the per-vehicle minimum rank tier that
  cm-family stores for each shared car — property-level family access alone is
  no longer sufficient to drive any family car regardless of rank.
- Fails closed only when cm-family is running and explicitly returns false, so
  servers without cm-family (or with it stopped) are completely unaffected.

This is the single integration point cm-family needs on the cm-house side; the
rest of the family system talks to cm-house through the pre-existing exports
(`GetHousesForCharacter`, `SetFamilyHouseLink`, `GetFamilyVehicles`,
`RefreshFamilyMembers`, `RefreshFamilyAccess`) and the `HasHousePermission`
seam that cm-house already calls.
