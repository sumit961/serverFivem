# v1.3.9 Selected Dummy Appearance Fix

Fixes selector preview showing GTA default freemode character before/without selected character data.

Changes:
- Preview ped is always a local dummy ped.
- Dummy ped starts hidden with alpha 0.
- Selected character model/gender/appearance is applied before showing the dummy.
- Inventory equipment clothing is applied before showing and again shortly after spawn.
- Supports optional appearance model fields: `model`, `pedModel`, `ped`.
- Logs `dummy preview spawned with selected appearance` for debugging.
