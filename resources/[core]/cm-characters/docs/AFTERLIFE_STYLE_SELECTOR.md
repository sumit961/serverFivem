# AfterLife-style selector update

This version keeps the existing `cm-auth`, `cm-core`, and `cm-characters` database flow, but changes the selector preview style to use real GTA world scenes.

## What changed

- Uses scene/camera locations inspired by AfterLife `CharacterSelection` config.
- Selecting a character now spawns a local preview ped in a real map scene.
- The selected ped walks into frame, stops, faces the camera, then idles.
- The NUI center area is transparent so the GTA ped/world is visible.
- Character cards/details remain on the sides.
- Background music/mute button stays.

## Test commands

```text
/chartestui
/charwalktest
```

## F8 debug lines

Look for:

```text
[CM-CHARACTERS] AfterLife scene loaded:
[CM-CHARACTERS] AfterLife preview walk-in:
```

If the ped does not appear, send the full F8 line to debug the exact scene/model problem.
