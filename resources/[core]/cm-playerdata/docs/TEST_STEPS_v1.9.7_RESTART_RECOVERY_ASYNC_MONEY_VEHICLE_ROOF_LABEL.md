# Test steps — v1.9.7

## 1. Dead-on-restart recovery
1. Get downed (bleed-out screen showing).
2. `restart cm-playerdata` (or restart the whole server) while still down.
3. Within ~1.5 s the death screen + timer should come back up on its own and NUI
   focus/controls should work again. No stuck half-dead state.
4. Also test: fully quit and rejoin while dead → death screen restores.

## 2. Async money (no hitch)
1. Fire many transactions quickly (buy/sell, `/giveitem` loops, paychecks) with
   several players online.
2. No per-transaction stall/micro-hitch.
3. Confirm persistence: make a balance change, wait past `FullSaveInterval`
   (default 3 min) OR disconnect cleanly, then rejoin — balance is correct.

## 3. Vitals loop config safety
1. Temporarily remove `HealthSyncInterval` and `PositionSyncInterval` from the
   config and restart.
2. No client error; the loop still runs on the 4000/6000 ms fallbacks.
3. Put the keys back.

## 4. Vehicle-roof labels
1. Sit in a car (driver and passenger): the ID floats above the roof, over your
   seat — not on the windshield/glass.
2. Drive around and swing the camera: the label stays glued above the roof and
   only moves as the car/player moves, no drift/wobble from your camera.
3. Passenger in different seats: label tracks the correct seat.
4. On foot: label is unchanged (above the head).
5. (If you have a trunk-stuff mechanic) a player attached in the trunk shows the
   ID above that car's roof.
