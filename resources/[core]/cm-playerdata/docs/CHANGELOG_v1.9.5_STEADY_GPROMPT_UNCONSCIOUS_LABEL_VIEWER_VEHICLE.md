# cm-playerdata v1.9.5 — Steady G prompt, Unconscious label, viewer-in-vehicle block

Four fixes on top of v1.9.4.

## 1. G prompt no longer blinks
Root cause: the G prompt shared the NUI `labels` message channel and the
`labelsWereVisible` flag. With native overhead labels enabled, the render loop
clears the NUI `labels` channel every frame, which wiped the G prompt one frame
after each `PushLabels` push (only every ~50 ms). Result: a fast on/off blink.

Fix: the G prompt now has its own NUI channel (`action = 'gprompt'`) with its own
visibility state and change-detection (`PushGPrompt` / `renderGPrompt`). The
per-frame label clear can no longer touch it, so it stays perfectly steady while
you look at a player and disappears cleanly when you look away.

## 2. Name + ID always over the head (on foot, in a car, or downed)
Overhead labels already followed players on foot and in vehicles. The downed
case was broken because dead detection used `IsEntityDead(ped)`, which is always
false in this framework (a downed player is kept alive at
`Vitals.DamageThreshold`). So the dead Z-offset never applied and the label
floated at standing height above a lying body.

Fix: a single `IsPedDowned(ped, serverId)` helper reads the replicated `isDead`
state bag (with a real-death native fallback). It is now used for label height,
wording, and menu paging, so the label sits correctly above the body.

## 3. "Unconscious" status line (Grand-RP style)
Downed players now show a red **Unconscious** line on its own row above the name:

```
Unconscious
musa bhai
ID: 13
```

Previously this was an inline `unconscious | name` prefix that never triggered.
Text/colour are configurable: `Interactions.DownedLabelText` /
`Interactions.DownedLabelColour`. Works in both native and NUI label modes.

## 4. No G menu / prompt while the viewer is in a vehicle
`CanInteract()` now returns false when the local player is inside a vehicle
(`IsLocalPlayerInVehicle`), gated by `Interactions.BlockInteractionWhenViewerInVehicle`
(default true). Overhead name/ID labels still render from inside a car — only the
G target, prompt, and menu are suppressed.

## New config keys (Interactions)
- `DownedLabelText = 'Unconscious'`
- `DownedLabelColour = { r = 235, g = 45, b = 45, a = 250 }`
- `BlockInteractionWhenViewerInVehicle = true`

## Files touched
- `client/interactions.lua` — helpers, downed detection, decoupled G channel, viewer-vehicle gate
- `ui/main.js` — `gprompt` channel + status line
- `ui/style.css` — `.pstatus` red line
- `config.lua` — new keys
