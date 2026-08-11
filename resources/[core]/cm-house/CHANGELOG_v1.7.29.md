# cm-house v1.7.29

- House creation no longer accepts an admin-entered name or address.
- The server assigns the next numeric `house_number` while preserving the existing unique database constraint.
- Newly published properties use the fixed label `House`.
- The admin property selector displays and searches properties as `House #<number>`.
- Removed the obsolete address-availability NUI/server callback.
- House map blips now share the single `House` legend category; numbered selection remains in house/admin menus.
- Added a visible cyan helipad marker and an authorized helicopter call menu for owners and family ranks with `helipad.use`.
- Helipads use GTA `MarkerTypeHelicopterSymbol` (marker type 34) and gracefully report when the server callback has not loaded instead of raising an ox_lib client error.
- Helicopter calls retain cm-vehicles ownership, persistent `vehicle_id`, condition and duplicate prevention.

Existing custom labels remain stored for rollback compatibility, but cm-house normalizes them to `House` when loading its runtime cache. No database migration is required.
