# rn-vehicleshop production cleanup changelog

## Preserved capture setup
- Kept green screen position: `vector4(-1228.0586, -2271.1174, 16.1346, 117.3766)`
- Kept green screen scale: `2.00`
- Kept vehicle photo position: `vector4(-1227.8779, -2271.1907, 13.3395, 242.6514)`
- Kept camera: `vector3(-1219.7456, -2268.8145, 15.2026)` looking at `vector3(-1248.9626, -2277.5510, 12.9446)` with FOV `50.0`

## Main changes
- Removed temporary placement/debug commands from client scripts.
- Rebuilt capture code as a production-only capture flow.
- Added crop preview modal with proper focus and z-index behavior.
- Saves optimized WebP where supported, with PNG fallback.
- Updated store close position to `vector4(-2264.3823, 392.3130, 174.6739, 263.2466)`.
- Improved HUD hide/show flow for store, admin, capture, crop, and test drive.
- Added test-drive key/ownership bypass state markers and temporary key event attempts.
- Removed duplicate purchase notifications.
- Updated admin/store UI with glass panels and less blocked vehicle preview.

## Follow-up Fix Pass
- Removed remaining large black UI slabs by overriding store/category panels with transparent/glass layouts.
- Added hard `forceClose` NUI action from Lua close path to prevent stuck UI after leaving store/admin.
- Cleared queued jQuery animations and body state classes during close to avoid panels reappearing after exit.
- Fixed duplicate `openUI` server trigger from dealer interaction.
- Changed test-drive vehicle to a local mission vehicle to avoid cm_vehicle ownership cleanup/key validation conflicts.
- Added test-drive grace period so held/old F key state cannot cancel test drive immediately.
- Added timer cleanup so old test-drive timers do not continue after return/close.
- Added extra temporary key event call signatures for compatibility with different key systems.


## HUD / UI restore hotfix
- Removed all glass blur CSS CSS usage.
- Reworked HUD hide/show calls to avoid toggle HUD APIs that can flip cm-hud into a permanently hidden state.
- Added forced HUD restore after store/admin exit and resource stop.
