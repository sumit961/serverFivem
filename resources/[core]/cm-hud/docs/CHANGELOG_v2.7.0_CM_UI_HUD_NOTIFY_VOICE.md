# cm-hud v2.7.0 - CM UI HUD notification and voice/radio layout

## Changed
- Added cm-ui dependency and shared stylesheet/script references.
- Updated default HUD settings for this display: `uiScale = 1.35`, `locationOffsetX = -7`, `locationOffsetY = -112`.
- Switched HUD KVP settings to `cm_hud_settings_v17` so the new defaults apply cleanly after update.
- Reworked notifications into a larger screenshot-style banner with type colors:
  - success = green
  - error = red
  - warning = yellow
  - info = cyan blue
- Added right-middle voice/radio indicators:
  - `N` = mic
  - `O` = family radio
  - `U` = organization radio
- `N`, `O`, and `U` glow while held.
- Optimized key-state updates so NUI messages are only sent when a key state changes instead of every poll tick.
- Added short duplicate-notification protection in the Lua bridge.
- Removed forbidden blur CSS property from active HUD styles.

## Kept
- Existing HUD admin command and speedometer system.
- Existing money/location/player ID logic.
- No server ID is intentionally exposed by this update.
- No gameplay money/permission logic was moved into HUD.
