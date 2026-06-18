# Walk-in Preview Visible Fix v1.1.3

This update fixes the issue where the selector details show but the GTA character preview does not appear in the center stage.

## Changes

- The preview stage now uses the player's currently loaded world position instead of a far rooftop coordinate.
- The script camera is forced active while the selector is open.
- HUD/radar is hidden while the selector is open.
- The center stage CSS is transparent so the GTA ped can be seen behind the UI.
- The first character auto-previews from Lua, not only from the NUI callback.
- Selecting any card spawns the character at the rear of the stage, walks it into the center, faces it to the camera, and plays idle animation.

## Test command

```text
/charwalktest
```

Run it while the selector is open to replay the first loaded character walk-in.
