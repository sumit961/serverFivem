# cm-house v1.3.2.6

## Glass snapshot and recall visibility hotfix

- Replaced ambiguous legacy `windows[index] = intact` snapshots with schema-2 `brokenWindows[index] = true`.
- Window damage is captured only when the matching vehicle model bone exists.
- Legacy window maps are ignored to stop already-corrupted rows from smashing every pane.
- Door, tyre, engine and undriveable snapshots remain preserved.
- Works without a SQL migration; the next normal storage writes the clean schema-2 snapshot.
