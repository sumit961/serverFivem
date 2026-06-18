# v1.2.5 Fixed Ground Selector

This update stops the selector camera from using the player's current/login position, because that position can be under the map during auth handoff.

Changes:
- Uses a fixed safe outdoor selector scene at Legion Square parking.
- Moves the real player to that location while selector is open so the map streams correctly.
- Keeps the real player hidden/frozen during selection.
- Spawns the selected preview ped on the same ground scene.
- Camera points at the ped above ground instead of from below the world.
- Stops the GTA character-change audio scene so city/selector sound stays off.

Debug:
- `/charwalktest` replays the selected character walk-in.
- Look for `[CM-CHARACTERS] AfterLife preview walk-in:` in F8.
