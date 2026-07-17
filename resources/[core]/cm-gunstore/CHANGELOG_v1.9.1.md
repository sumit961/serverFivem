# cm-gunstore v1.9.1 — store UX follow-up

## Ammo is buyable on its own again
- Ammunition is back as standalone items in the player store (its own
  "Ammunition" dropdown). Selecting an ammo item shows a detail panel with a
  rounds stepper (−10 / − / value / + / +10) and a live total, then Buy Cash /
  Buy Bank.
- The weapon "Add ammunition" convenience panel is kept, so players can buy ammo
  by itself OR bundled with a gun. No server changes were needed — standalone
  ammo uses the existing quantity buy path.
- The Ammo tab is visible to players again.

## Collapsible catalog dropdowns per weapon type
- Each catalog group (Pistols, SMGs, Assault Rifles, Shotguns, Sniper Rifles,
  Machine Guns, Ammunition, Armor) is now a collapsible dropdown with an item
  count badge and a rotating chevron. Click a header to expand/collapse it.
- The group holding the currently selected item always stays open.
