# Test steps — v1.9.5

Restart: `ensure cm-playerdata` (or `restart cm-playerdata`). Two players needed.

## G prompt is steady (no blink)
1. On foot, look at another player within ~4.5 m.
2. The cyan **G** on their body should appear once and hold rock-steady — no
   flicker while you keep the crosshair on them.
3. Look away: G disappears cleanly after a short hold.

## Labels always over the head
1. On foot: `Name / ID` sits above the head. ✔
2. Have the other player drive past / sit in a car: label stays above their
   head through the windshield. ✔
3. Down the other player (or get downed and watch a third): label sits right
   above the lying body, not floating high. ✔

## Unconscious wording
1. Down a player. Their label reads, top to bottom:
   `Unconscious` (red) / `Name` / `ID: xx`.
2. Revive/respawn: the red line disappears, normal label returns.

## No G in a vehicle (viewer side)
1. Get in any car as the driver or passenger.
2. Look at a nearby player on foot: **no G prompt, no target ring, G opens
   nothing.** The overhead name/ID label on that player still shows.
3. Exit the car: G targeting works again on foot.

## Regression checks
- Admin tag label still red and unchanged.
- Admin noclip still hides all labels/targets.
- Looking at a downed player and pressing G opens the treatment/dead page
  (not the handshake/main page).
