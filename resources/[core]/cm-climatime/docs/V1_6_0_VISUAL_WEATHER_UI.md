# CM Climatime v1.6.0 - Visual Weather UI

This update focuses on making climate administration easier and more visual.

## Added

- Dynamic weather profile selector in the Weather Manager.
- Visual mixed-weather builder for weather zones.
- Click weather chips to add weather into the zone mix pool.
- Drag weather chips into the drop zone to build mixed weather.
- Remove weather from the mix pool with the `x` button.
- Quick mix presets: Normal, Rain, Storm, Snow, Clear Pool.
- Better weather zone cards with pool preview.
- Hidden legacy `zonePool` input is kept only for compatibility; admins no longer need to type weather names manually.

## Rules

- Weather/time ownership stays inside `cm-climatime`.
- Admin access should come through `cm-admin` when available.
- The `/climatime` command still works with ACE permission fallback.
- `cm-spawn` should ask `cm-climatime` to prepare weather/time before visible spawn.
- `cm-hud` and phone resources can use forecast exports.

## Current exports

### Server

```lua
exports['cm-climatime']:GetState()
exports['cm-climatime']:SetGlobalWeather(weather)
exports['cm-climatime']:SetManualTime(hour, minute, freeze)
exports['cm-climatime']:ResetRealTime()
exports['cm-climatime']:GetCurrentWeather()
exports['cm-climatime']:GetForecast()
exports['cm-climatime']:GetTime()
exports['cm-climatime']:GetActiveProfile()
exports['cm-climatime']:GetForecastTimeline()
exports['cm-climatime']:GetCurrentConditions()
exports['cm-climatime']:ApplyPreset(key)
```

### Client

```lua
exports['cm-climatime']:GetState()
exports['cm-climatime']:GetCurrentWeather()
exports['cm-climatime']:GetCurrentTime()
exports['cm-climatime']:SetPaused(paused, reason)
exports['cm-climatime']:StartAfterSpawn(reason)
exports['cm-climatime']:PrepareBeforeSpawn(data)
exports['cm-climatime']:IsPreSpawnPrepared()
exports['cm-climatime']:RequestSync()
exports['cm-climatime']:ForceSync()
exports['cm-climatime']:IsActive()
exports['cm-climatime']:IsPaused()
exports['cm-climatime']:GetForecastTimeline()
exports['cm-climatime']:GetCurrentConditions()
exports['cm-climatime']:GetCurrentZone()
```

## Future ideas to add later

- Weather calendar view for full weekly schedule.
- More zone templates such as desert heat, mountain snow, city fog, airport storm.
- Admin drag-to-reorder schedule cards.
- HUD/phone weather app showing forecast and zone weather.
- Severe weather alerts with map blinking zones.
- Staff view-only mode inside `cm-admin` for moderators.
- Gameplay effects per zone: fog visibility, wet road traction, heatwave stamina, storm vehicle handling.
- Seasonal presets: Halloween, Christmas snow, summer heatwave, foggy morning.
- Organization/event weather override for RP events.
