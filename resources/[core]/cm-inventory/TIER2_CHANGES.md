# cm-inventory — Tier 2 changes

The three higher-risk features, built additively. New file `server/tier2.lua` is
concatenated into the existing server chunk (via the bootloader in
server/main.lua), so it shares scope with all the internal functions and reuses
them rather than duplicating logic. The whole combined chunk was compiled as one
unit to confirm no scope/upvalue errors.

## #4 Give with player name + list + confirmation
Flow (all target selection re-validated server-side):
1. Player picks GIVE on an item -> client sends `requestGive` (slot only).
2. Server finds nearby players (within Config.Give.distance), resolves each
   name via cm-playerdata, and replies with `giveTargets`.
3. UI shows a confirmation with the player's name (one nearby) or a picker list
   (several). Player chooses -> `confirmGive` with the chosen server id.
4. Server re-checks: the offer exists and hasn't expired (20s TTL), the chosen
   target was in the offered set AND is still in range now, the item is still in
   that slot, and the receiver can carry it. Then it moves the FULL stack with
   rollback on failure.

Anti-abuse: the offer is bound to the exact slot/item/amount and is single-use,
so a client can't confirm a different item or replay the confirm. Verified in a
standalone test (valid confirm passes; spoofed target, expired offer, and replay
all reject).

## #6 Unequip gun -> ammo follows to inventory
Hooked into the existing `moveItem` success path: when the WEAPON slot is emptied
into a normal (non-equipment, non-ammo) slot, the server pulls the matching ammo
out of the ammo slot into the first free pocket/backpack slot — but only if the
receiver has carry space. If there's no room, the ammo stays put and the player
is told. Uses the existing MoveItemInternal, so all its validation applies.

## #7 Death drops equipped gun + ammo to the ground
cm-inventory previously had no death handling. It now listens for
`cm-playerdata:server:playerDied` (source = the dying player) and drops the
equipped weapon and its ammo as separate world pickups any nearby player can
loot. Reuses the existing DropItemInternal / createWorldDrop path, so drops
behave exactly like normal dropped items. Configurable via Config.Death.dropWeapons.
An explicit export `DropEquippedWeaponsOnDeath(src)` is also provided if you want
cm-playerdata to trigger it at the precise moment of death (most reliable hook).

## Config added (config.lua)
    Give  = { enabled = true, distance = 3.0 }
    Death = { dropWeapons = true }

## Validation
- The full concatenated server chunk (all 10 files incl. tier2) compiles as one
  unit — no scope/upvalue/local-limit errors.
- All tier2 dependencies (MoveItemInternal, DropItemInternal, canCarry, etc.)
  are defined in files that load before tier2 in the chunk, so upvalue scope is
  satisfied.
- ui/app.js passes `node --check`; client/main.lua parses clean.
- Give offer/confirm logic unit-tested for the spoof/expiry/replay cases.

## Test in-game
- Give with exactly one player nearby (name confirm) and with 2+ (picker).
- Unequip a loaded gun; confirm ammo lands in a pocket (and stays if full).
- Die with a gun+ammo equipped; confirm both drop and another player can pick up.
