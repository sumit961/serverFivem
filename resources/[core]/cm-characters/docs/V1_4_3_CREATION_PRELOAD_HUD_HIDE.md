# v1.4.3 Creation preload + HUD hide

- Adds a small loading overlay when opening first-time character creation.
- Preloads male/female freemode models and creator collision before showing the ped.
- Hides radar and attempts to hide cm-hud during selector and creation.
- Keeps `skipPositionSave=true` while the player is in selector/creation, only disabling it after full spawn.
