# cm-inventory — Tier 1 changes

This pass covers the four low-risk changes plus a performance fix. The higher-risk
Tier 2 items (nearby-player give list + confirm, ammo-follows-gun on unequip,
death-drop of weapon+ammo) are intentionally NOT in this build and come next.

## 1. Same clothes now merge
`server/items.lua` — the clothing stack signature compared far too many fields
(gender/model, dlc/collection, arms/undershirt/torso linkage, and nested
appearance tables that carry capture-time / row-id / ordering noise). Two
identical-looking clothing items therefore refused to stack. The signature now
compares ONLY the fields that define the wearable: category + component/prop +
drawable + texture. Identical clothes merge; genuinely different ones still don't.

## 2. Drop = drop the whole stack, no amount prompt
`ui/app.js` — the DROP context action (and drag-to-drop) now call `dropAll()`,
which posts the full quantity immediately. The drop amount modal is bypassed.

## 3. Give nearby = give the whole stack, no amount prompt
`ui/app.js` — the GIVE context action (and drag-to-give-zone) now call
`giveAll()`, posting the full quantity. The give amount modal is bypassed.
NOTE: player selection/confirmation (when several players are nearby) is a Tier 2
change; this build keeps the existing server-side target resolution.

## 4. Double right-click moves item to the other open container
`ui/app.js` — two right-clicks on an item within 400ms send it straight to the
OTHER open container: main→external if a vehicle/stash is open, external→main if
the item is in the container. Rules honored:
  - Does NOTHING when no second container is open (as requested).
  - Never moves equipment-slot items via this shortcut.
  - Picks the first free slot in the destination; notifies if the destination is full.

## Performance
`client/main.lua` — two loops previously ran at `Wait(0)` during ALL normal
gameplay (inventory closed), i.e. a permanent per-frame cost for every player:
  - Weapon-wheel suppression: now spins per-frame only while the wheel key
    (control 37) is actually held; otherwise polls at 150ms. The wheel is still
    fully blocked.
  - Quick-access hotkeys (1–5): now spin per-frame only while a hotkey is held;
    otherwise poll at 100ms. Number keys remain instant.
These remove two constant full-speed loops from every client with no loss of
responsiveness. Other inventory loops were already correctly gated.

Also removed the dead `server/legacy_main_before_split.lua.disabled` and pruned
stale UI-iteration / debug docs.

## Validated
- All server Lua files pass syntax; client/main.lua validated (its backtick
  hash-literals are valid CfxLua and only trip offline checkers).
- ui/app.js passes `node --check`.
