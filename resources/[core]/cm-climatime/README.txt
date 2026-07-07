CM CLIMATIME - Weather / Time / Zones
====================================

Install:
1. Put the folder `cm-climatime` inside `resources/[core]/`.
2. In server.cfg, add it after cm-core and before/around cm-hud:

   ensure cm-climatime

3. Give admin permission:

   add_ace group.admin cmclimatime.admin allow

Your current server.cfg already has `add_ace group.admin command allow`, so your admin group should also be able to use /climatime.

Commands:
- /climatime
- /weatheradmin

Main features:
- Server-authoritative synced weather and time.
- 24-hour real-life time mode by default.
- Admin can override/freeze/reset time.
- Dynamic global weather rotation.
- Weather schedule presets with durations.
- Weather zones: local weather area using coords + radius.
- Zone modes: static, dynamic, or mix pool.
- Force snow footprints/vehicle trails.
- Blackout support.
- Persistent state saved to data/state.json.

Theme:
- Default accent is CM cyan/blue.
- To use lime color like the screenshot, open shared/config.lua and change:
  Config.UI.Accent = '#aaff00'

Important:
- Remove/stop any other weather/time sync resource. Only one resource should control GTA weather/time.
- Zone weather is client-side by design, so two players can see different weather when one is inside a zone and another is outside.

=== v1.3 High-End Update ===
- FIX: manual time drift (read no longer double-counts elapsed minutes)
- FIX: dev freeze action name (dev tab now only opens the panel, no stray actions)
- Zones: 2D distance + enter/exit hysteresis (no edge flicker, roofs/tunnels stay in-zone)
- Dynamic weather: profile-weighted + transition chains (forecast mode) - no random jumps
- Weather profiles: normal, hot_summer, rainy_week, storm, winter, foggy_morning, halloween, christmas
- Forecast queue: upcoming weather timeline (exports:GetForecast)
- Manual time speed multiplier (setTimeSpeed action)
- DB admin action logging (cm_climatime_admin_logs) + feeds cm-admin unified log
- Exports for cm-hud: GetCurrentWeather, GetForecast, GetTime, GetActiveProfile
- Dev tab: single "Open Climatime Panel" button (no typing /climatime)
=== v1.4 Interactive Zone Map Update ===
- Zones tab now uses the same Senor Airdrops-style GTA interactive map pattern.
- Click the GTA map to fill zone X/Y coordinates automatically.
- Existing saved zones are shown as markers with radius circles.
- Clicking a saved marker opens it for editing; the Map button recenters the map.
- Get Current Position now also recenters the map and previews the zone radius.
- Fixed the previous UI app.js duplicate `return` syntax issue in readZoneForm.
- Leaflet/GTA map vendor files are bundled locally from the uploaded airdrops resource; map tiles still load from gtamap.xyz like Senor Airdrops.

v1.4.1 local mapzones fix:
- Removed remote gtamap.xyz tile dependency that caused the Zones tab to stay on Loading map.
- Leaflet is now exposed correctly from the bundled Senor Airdrops map vendor.
- Zones tab now uses a local offline GTA-style map layer at ui/assets/gta-map-local.png.
- Optional: put an exact GTA default map image named ui/assets/gta-map.png and the UI will use it before the fallback map.
- Click the map to set X/Y, drag the selected marker to move the zone, and change Radius to update the circle live.


INTERACTIVE MAP TILES
---------------------
This version uses GTA-style map tiles instead of one merged PNG.
Tiles are stored here:
  ui/assets/map_tiles/minimap_sea_X_Y.png

Current grid in ui/app.js is 3 columns x 2 rows:
  minimap_sea_0_0.png  minimap_sea_1_0.png  minimap_sea_2_0.png
  minimap_sea_0_1.png  minimap_sea_1_1.png  minimap_sea_2_1.png

If your folder has only 4 tiles, use TILE_COLUMNS = 2, TILE_ROWS = 2 and list:
  0_0, 1_0, 0_1, 1_1

The map still supports click-to-place, drag center marker, drag radius handle, show all saved circles, and click a saved circle/marker to edit.
