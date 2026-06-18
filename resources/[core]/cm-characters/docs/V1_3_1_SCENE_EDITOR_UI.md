# v1.3.1 Selector Scene Editor UI

This version replaces the command-heavy selector scene editor with a clickable NUI panel.

## Open editor

```text
/charselectedit
```

Alias:

```text
/charselecteditui
```

## What can be edited in UI

- Character finish position
- Walk-in start position
- Stream/player move position
- Camera position
- Camera FOV
- Weather
- Time
- Idle animation preset

## How to use

1. Open selector or stand near the location you want.
2. Run `/charselectedit`.
3. Use the editor panel buttons:
   - Use my current position as character finish
   - Use my current position as walk start
   - Use my current position as stream location
   - Use current camera view
4. Use nudge buttons to fine tune camera/player positions.
5. Click Preview.
6. Click Save Scene.

The saved config is written to:

```text
cm-characters/data/selector_scene.json
```

The old commands still exist as fallback, but normal use should be through the UI.
