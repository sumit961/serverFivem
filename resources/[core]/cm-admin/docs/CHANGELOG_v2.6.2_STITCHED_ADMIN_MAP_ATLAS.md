# CM Admin v2.6.2 - Stitched Admin Map Atlas

## Changes
- Rebuilt the admin live map background from the six supplied GTA minimap sea tiles.
- Stitched the six tiles into a single `ui/assets/gta-map-local.png` atlas for the admin live map.
- Added the original six map tiles under `ui/assets/map_tiles/` for future reuse and debugging.
- Kept the same world bounds used by `cm-climatime` so staff/player/vehicle positions stay aligned.
- Kept existing admin logic, permissions, logs, GPS teleport, dev launchers, and head-tag behaviour unchanged.
- No heavy runtime changes were introduced; this update is asset/UI only.

## Tile layout used
- top-left: `minimap_sea_0_0.png`
- top-right: `minimap_sea_0_1.png`
- middle-left: `minimap_sea_1_0.png`
- middle-right: `minimap_sea_1_1.png`
- bottom-left: `minimap_sea_2_0.png`
- bottom-right: `minimap_sea_2_1.png`
