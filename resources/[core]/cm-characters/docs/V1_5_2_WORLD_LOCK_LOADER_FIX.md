# v1.5.2 - Character Screen World Lock + One-Time Loader Fix

## Fixed

- HUD and radar are force-hidden while the player is in character selection, basic creator form, or appearance creator.
- Character selection and creation now use a local fixed night environment: `CLEAR`, `23:00`.
- `cm-climatime` is paused/ignored during character screens using best-effort statebags, events, and exports.
- Time/weather are continuously re-applied while character screens are active so other resources cannot visually override the scene.
- The selector loading overlay only appears once when first entering character selection.
- Repeated slot refreshes no longer restart `Loading character preview...`.
- Repeated slot refreshes no longer auto-preview/rebuild the first character again.
- UI slot refreshes preserve the selected card and do not call preview again unless the player clicks a character.

## Config

`config.lua` now includes:

```lua
Config.CharacterScreenWorld = {
    enabled = true,
    weather = 'CLEAR',
    hour = 23,
    minute = 0,
    second = 0,
    hideHud = true,
    hideRadar = true,
    suppressClimatime = true,
    hudPulseMs = 650,
    weatherPulseMs = 350
}
```

## Notes

This lock is local only. It does not change the global weather/time for players already spawned in the city. When the real character spawn finishes, the lock is released and `cm-climatime` is asked to sync again.
