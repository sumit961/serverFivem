# Walk-in Character Preview Update

This version changes the selector preview behavior:

- The NUI selector now has a transparent center stage so the GTA world camera is visible behind the UI.
- Character cards stay on the left and the details panel stays on the right.
- When a character card is selected, the old preview ped is removed and the selected character spawns behind the stage, walks into the center, then idles facing the camera.
- `/charwalktest` can replay the walk-in preview after the selector is open.
- `/chartestui` still reopens the selector for testing.

If the details show but no character is visible, check F8 for `[CM-CHARACTERS] preview failed` messages.
