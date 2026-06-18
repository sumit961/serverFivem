# cm-characters v1.3.5 Simple Preview

This version removes the complicated walk-in/editor/freecam preview behavior from normal character selection.

When a character card is selected:

1. One preview ped is created.
2. The character's saved appearance is applied.
3. Equipped inventory clothing is applied from equipment slots.
4. The ped is placed at the preview position.
5. The ped plays an idle animation.
6. The details panel stays visible.

Test command:

```text
/charpreviewtest
```

The old `/charwalktest` behavior has been replaced with simple preview spawning.
