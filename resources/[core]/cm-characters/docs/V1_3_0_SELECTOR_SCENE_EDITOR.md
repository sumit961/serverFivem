# v1.3.0 Selector Scene Editor

This version adds an in-game editor for the character selection preview scene.

## Commands

```text
/charselectedit
```
Toggle editor mode. In edit mode the selector UI hides and your player becomes visible so you can move around normally.

```text
/cssetplayer
```
Save your current player position as the preview finish/player position.

```text
/cssetwalkstart
```
Save your current player position as the walk-in start position.

```text
/cssetstream
```
Save your current player position as the streaming location. During selector, the hidden real player is moved here so the map loads.

```text
/cscamfromview
```
Save your current gameplay camera position/rotation as the selector camera.

```text
/csfov 34
/cstime 12 0
/csweather EXTRASUNNY
/csanim amb@world_human_hang_out_street@male_c@idle_a idle_b
```
Adjust camera FOV, time, weather, and idle animation.

```text
/cspreview
```
Preview the current draft.

```text
/cssave
```
Save the draft to:

```text
data/selector_scene.json
```

The selector loads this file every time it opens.

## Suggested workflow

1. Go to the place where you want the character to stand.
2. Run `/charselectedit`.
3. Stand where the character should finish and run `/cssetplayer`.
4. Walk backwards to where the character should start and run `/cssetwalkstart`.
5. Stand/look where you want the selector camera, then run `/cscamfromview`.
6. Run `/cspreview`.
7. Adjust with `/csfov`, `/cstime`, `/csweather`, `/csanim`.
8. Run `/cssave`.
9. Restart or reopen character selector.
