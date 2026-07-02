# HUD State Lock Fix - 2026-06-30

`cm-hud` now respects explicit state locks from UI resources before running its automatic HUD recovery logic.

Recognised locks:
- `LocalPlayer.state.cmHudHiddenByVehicleShop`
- `LocalPlayer.state.cmVehicleShop == 'store' | 'admin' | 'capture'`
- `LocalPlayer.state.cmHudHiddenByClothing`
- `LocalPlayer.state.inClothingStore`

This prevents vehicle/clothing store HUD blinking when NUI focus changes temporarily.
