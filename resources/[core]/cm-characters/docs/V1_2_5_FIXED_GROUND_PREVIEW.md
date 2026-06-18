# v1.2.5 Fixed Ground Preview

This update stops building the selector camera from the player current reconnect location.

The selector now:

- Moves the hidden real player to a known outdoor ground location near Legion Square.
- Loads collision at that preview area before spawning the preview ped.
- Spawns the selected character preview ped at ground height.
- Makes the preview ped walk into the scene and face the camera.
- Restores the player back to the original location only if the selector is closed/cancelled.

F8 test command:

```text
/charwalktest
```

Look for this log:

```text
[CM-CHARACTERS] Fixed ground preview scene:
```
