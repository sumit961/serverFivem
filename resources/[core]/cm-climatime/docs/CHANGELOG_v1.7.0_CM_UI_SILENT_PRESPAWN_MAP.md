# cm-climatime v1.7.0 - CM UI, Silent Pre-Spawn Climate, Bigger Map UI

## Main fixes

- Added `cm-ui` dependency and loaded shared CM theme/component CSS and JS in the Climatime admin UI.
- Kept weather/time ownership inside `cm-climatime`; no economy, admin permission, or unrelated framework logic was moved.
- Weather/time now applies silently during the hidden pre-spawn phase so the sky/time is already prepared while the `cm-spawn` page is open, before the player clicks Last Location, Hotel, or any future spawn card.
- Added compatibility server nudge for `cm-climatime:server:requestPreSpawnClimate`, so older/newer spawn resources that only request the server can still make the client prepare before reveal.
- Added fresh-state reapply during pre-spawn sync: when the server sync arrives while pre-spawn is active/recently prepared, the client immediately reapplies the authoritative weather/time.
- Added final spawn-coordinate zone support for pre-spawn prepare. If `cm-spawn` sends spawn coordinates, zone weather can be resolved for that final location before reveal.

## Notification changes

- Set `Config.Weather.NotifyPlayers = false` by default.
- Added `Config.Notifications` defaults:
  - `UseGtaFeed = false`
  - `UiToasts = true`
  - `WeatherChangeToasts = false`
  - `AdminActionToasts = true`
- Weather changes no longer show GTA feed notifications to normal gameplay.
- Admin action feedback is still shown as an in-panel toast when the Climatime UI is open.

## Performance changes

- Added LocalPlayer statebag cache so unchanged climatime state values are not repeatedly written.
- Removed duplicate activation sync request.
- Fixed duplicate NUI callback response in `requestState`.
- Increased zone check interval from 1000ms to 1200ms to reduce background work while still feeling responsive.
- Admin UI time/next-change intervals now update only while the panel is visible.
- Zone map input updates are requestAnimationFrame-throttled instead of rebuilding immediately on every input event.

## UI/map improvements

- Admin panel is now larger and more fullscreen-friendly.
- Weather grid is larger and easier to click.
- Zone tab uses a bigger GTA map area.
- Added map controls:
  - `＋ Zoom`
  - `－ Zoom`
  - `⌖ Focus Zone`
  - `Use My Position`
- Map interactions improved:
  - click map to set center
  - drag center marker
  - drag radius handle
  - scroll wheel zoom
  - live coordinate hint while moving on map

## Files changed

- `fxmanifest.lua`
- `shared/config.lua`
- `client/main.lua`
- `server/main.lua`
- `ui/index.html`
- `ui/style.css`
- `ui/app.js`
