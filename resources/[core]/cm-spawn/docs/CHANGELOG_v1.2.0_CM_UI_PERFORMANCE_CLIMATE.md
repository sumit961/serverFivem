# cm-spawn v1.2.0 - CM UI + performance-safe climate preload

## UI
- Added `cm-ui` dependency in `fxmanifest.lua`.
- Spawn selector now loads shared CM UI files:
  - `nui://cm-ui/web/cm-theme.css`
  - `nui://cm-ui/web/cm-components.css`
  - `nui://cm-ui/web/cm-icons.css`
  - `nui://cm-ui/web/cm-ui.js`
- Removed external Font Awesome CDN dependency.
- Reworked local CSS so it only owns spawn-specific layout and uses CM UI variables for theme/colors/panels/buttons/badges/scrollbars.
- Kept modern blue/cyan Grand RP style.
- Kept full-screen spawn selector.
- Kept tutorial UI, but restyled with CM UI variables.
- No `backdrop-filter` or `-webkit-backdrop-filter` is used.

## Climate / spawn handoff
- Spawn page now asks `cm-climatime` to prepare current synced weather/time before sending the NUI open message.
- Final selected spawn still prepares climate again before player reveal using selected server-resolved coordinates.
- Added preload config:
  - `Config.SpawnPageClimateWait = 120`
  - `Config.SpawnPageClimatePrepareMs = 900`
  - `Config.SpawnPageClimateValidMs = 30000`
- Added a client-side climate preload throttle so repeated selector openings do not spam climatime events.

## Performance / production safety
- Added HUD state cache to avoid duplicate HUD state/event spam during spawn transitions.
- Added local state setter guard to avoid repeating identical LocalPlayer statebag writes.
- Reworked NUI spawn card rendering to use a `DocumentFragment` instead of repeated direct DOM reflow.
- Reduced animation duration/delay slightly for lighter Chromium rendering.
- Kept logs quiet by default with `Config.Debug = false` and `Config.VerboseLogs = false`.
- Replaced spawn-select appearance lookup with the already-selected row data, reducing one DB query per spawn selection.
- Added `Config.AutoEnsureHasSpawnedColumn` so production servers can disable startup schema checking after running the SQL migration once.

## Security / framework rules preserved
- Browser still sends only `spawnKey`.
- Server still resolves the final spawn coordinates.
- Dead players are still forced back to dead/body location server-side no matter what card they click.
- No server ID is sent to NUI.
- No money/prices/rewards/admin logic added.
- Debug commands remain disabled by default.
