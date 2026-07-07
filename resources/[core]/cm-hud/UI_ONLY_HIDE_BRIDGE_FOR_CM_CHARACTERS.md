# UI-only hide bridge for cm-characters

This HUD build adds UI-only hide/show events so character creation can hide the CM HUD without touching GTA native HUD/radar/minimap.

Events:
- `cm-hud:client:hideUiOnly`
- `cm-hud:client:showUiOnly`
- `cm-hud:client:setUiVisible`

Exports:
- `SetUiVisible(visible, reason)`
- `HideUiOnly(reason)`
- `ShowUiOnly(reason)`

The existing `cm-hud:client:setHudVisible` behaviour is unchanged for resources that intentionally want to hide the full native HUD/radar.
