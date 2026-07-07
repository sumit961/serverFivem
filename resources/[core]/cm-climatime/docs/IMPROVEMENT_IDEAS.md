# CM Climatime improvement ideas

## High priority

1. Add a proper server-side player bucket filter so climate sync is not sent to selector/creator routing buckets.
2. Add zone blending instead of hard switching at the border. Example: CLOUDS -> RAIN with a transition based on distance into the zone.
3. Add per-zone priority visual debug mode in-game, not only in the admin UI.
4. Add a forecast timeline with exact next-change timestamps for HUD integration.
5. Add weather event presets: heatwave, storm warning, Halloween night, Christmas snow, foggy morning.

## Admin/UI

1. Add live player count inside each zone.
2. Add test-player-position preview on the map.
3. Add copy/export/import per-zone presets.
4. Add undo history for admin actions.
5. Add confirmation modal for reset/import/delete.

## Server/professional polish

1. Add permission groups for view-only vs edit climate.
2. Add database version migrations instead of runtime ALTER-style changes.
3. Add admin audit details: old value, new value, character ID, account ID.
4. Add convars for emergency disable.
5. Add telemetry/debug command `/climatime status` showing active/paused/zone/weather/time.

## Gameplay/RP features

1. Forecast app/export for phone/HUD.
2. Storm impact events: slippery roads, lower traction, thunder ambience.
3. Fog visibility zones for mountains/forest.
4. Temperature system for clothing/needs resources.
5. Seasonal schedules for server events.
