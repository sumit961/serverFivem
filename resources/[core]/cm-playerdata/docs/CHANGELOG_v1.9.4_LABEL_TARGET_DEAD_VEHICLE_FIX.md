# cm-playerdata v1.9.4 - Label Target / Dead / Vehicle Fix

## Changes
- Fixed normal ID colour: `ID: <characterId>` is white by default.
- ID turns CM cyan only while the player is actually targetable and the G prompt is visible.
- Blocked player G prompt/menu for targets inside vehicles.
- Kept overhead name/ID visible while target is inside a vehicle.
- Vehicle occupant label now anchors to the ped head bone instead of the car roof/entity origin.
- Dead player label now shows `unconscious | <name/stranger>` and keeps the same database character ID line.
- Improved in-vehicle detection using multiple natives to avoid one-frame vehicle target leaks.
- Increased G target hold default to reduce flicker when the camera ray misses for a frame.

## Security / rules
- Server ID is still never shown.
- Server-side interaction validation still rejects player interactions against targets inside vehicles.
- Admin replacement label behaviour from v1.9.2 is preserved.
