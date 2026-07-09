# CM Playerdata v1.9.2 - Native Head Label + Single Admin Replacement

## Changes
- Reworked overhead player labels to draw natively every render frame by default.
- Labels now anchor to the player ped/entity position plus a fixed Z offset, not animated head bones.
- This makes the label stay fixed above the player and move only with the player, with no NUI trailing when the camera moves.
- Normal label format now matches the requested simple style:
  - `Character Name`
  - `(Character ID)`
- Admin mode now replaces the normal player label instead of drawing a second admin label:
  - `Administrator`
  - `Character Name (Character ID)`
- Admin labels are all red.
- Local player still never sees their own overhead label.
- Admin noclip still hides the overhead label and disables G-menu targeting.
- Added fallback NUI admin class styling if native labels are disabled.

## Performance
- Native drawing only runs when streamed players are nearby.
- Nearby-player scanning remains throttled.
- Identity batch requests remain throttled.
- NUI label updates are no longer used for normal overhead labels by default, reducing browser update traffic.
