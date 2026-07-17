# cm-vehicles v3.3.5

## Model-aware glass state and instant world reveal

- Added the official eWindowId-to-bone mapping for window indexes 0-7.
- Applies broken glass only from schema-2 snapshots and only for windows present on the model.
- Ignores corrupted legacy window maps that treated unsupported indexes as broken.
- Added a direct recall reveal event for the requesting client.
- Recall handoff polls every frame during the initial stream window and uses `NetworkFadeInEntity`.
- Persistent release state still repairs late-streaming clients.

- Added an idempotent startup cleanup for legacy window maps and a runtime repair for already-spawned legacy entities.
