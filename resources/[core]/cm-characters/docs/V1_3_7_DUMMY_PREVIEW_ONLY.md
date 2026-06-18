# v1.3.7 Dummy Preview Only

Fixes duplicate preview peds and removes use of the real player ped for preview.

## Behavior

- Selecting a character always deletes the old preview ped first.
- Preview uses a local dummy freemode ped created with `CreatePed(..., false, false)`.
- The real player ped is only hidden and used for streaming the world.
- Before each preview, old untracked dummy freemode peds near the selector scene are cleaned up.
- Enter City deletes the preview dummy before loading the real character.
- `/charpreviewclear` deletes tracked and nearby untracked preview dummies.

## Flow

```text
select card
↓
delete old dummy preview
↓
spawn one local dummy ped
↓
apply appearance + inventory clothing
↓
idle animation
```
