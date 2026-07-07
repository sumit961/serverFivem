# v1.5.1 Duplicate Selector Load Fix

Fixes the issue where the character selector looked like it loaded twice while the player stayed on character selection.

## Cause

The selector could receive repeated open/ready messages from these places close together:

- cm-auth login handoff
- spawn fallback open event
- NUI `uiReady` safety pings
- delayed `showSlots` replay

Those repeated messages rebuilt the preview ped/camera or restarted the full-screen loader.

## Fixes

- Added client duplicate-open guard in `client/main.lua`.
- Added slot request debounce/in-flight guard.
- Added slot payload fingerprinting so the same slot list only refreshes UI, not the ped/camera.
- Changed NUI safety replay to `showApp` only, not repeated `showSlots`.
- Added UI duplicate slot handling so duplicate `showSlots` does not restart loader or auto-preview again.
- Added server-side selector open debounce in `server/bridge.lua`.

## Expected log

If duplicate events happen, you should now see messages like:

```txt
[CM-CHARACTERS] selector already open for this account; not rebuilding scene/loading again
[CM-CHARACTERS] duplicate showSlots ignored: refreshing UI only
[CM-CHARACTERS] getSlots skipped (...): debounce
```

These logs are normal and mean the duplicate load was blocked.
