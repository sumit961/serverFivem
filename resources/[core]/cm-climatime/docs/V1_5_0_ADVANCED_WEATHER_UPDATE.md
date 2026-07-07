# CM Climatime v1.5.0 - Advanced Weather Update

## Main fixes

- cm-climatime remains spawn-gated. It stores sync data during login/character selector but only applies weather/time after `cm-spawn:client:spawned`.
- Rain has been fixed with `SetRainLevel()` and `SetRainFxIntensity()`, not only weather type changes.
- Smooth weather transitions are configurable and rain starts visibly during transitions.

## New features

- Zone blending / soft edges to avoid hard weather snapping at zone borders.
- Live zone debug overlay: `/climatime debug` or `/climazone` if you bind it separately.
- `/climatime status` shows current mode, weather, time, active event and your zone.
- Forecast exports for HUD/phone.
- Weather event presets: storm warning, heatwave, foggy morning, Halloween, Christmas snow.
- Admin undo history: `/climatime undo` or the Undo button.
- View-only and edit permissions.
- Better schedule items: sequence, start after delay, start at time, repeat daily.
- Gameplay effects: wet roads/rain intensity, optional storm traction, optional fog timecycle, snow tracks/trails.

## Recommended ACE permissions

```cfg
add_ace group.admin cmclimatime.view allow
add_ace group.admin cmclimatime.edit allow
add_ace group.admin cmclimatime.admin allow
add_ace group.admin command.climatime allow
add_ace group.admin command.weatheradmin allow
```

## Useful commands

```txt
/climatime
/climatime status
/climatime debug
/climatime undo
/weatheradmin
/weatheradmin status
```

## HUD/phone exports

```lua
local forecast = exports['cm-climatime']:GetForecastTimeline()
local conditions = exports['cm-climatime']:GetCurrentConditions()
local weather = exports['cm-climatime']:GetCurrentWeather()
```
