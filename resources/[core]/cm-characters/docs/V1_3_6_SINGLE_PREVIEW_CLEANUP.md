# v1.3.6 Single Preview Cleanup

This version fixes duplicate preview peds in character selection.

## Behavior

- Only one selector preview ped is allowed at a time.
- Selecting another character deletes the previous preview ped first.
- Clicking Enter City deletes the selector preview ped before the real playable character is selected/spawned.
- Opening creator also deletes the preview ped first.

## Test command

```text
/charpreviewclear
```

This clears tracked selector preview peds.
