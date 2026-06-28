ADMIN UI + NPC FIX
==================

What changed:
- Admin UI no longer uses tiny item cards for editing.
- Admin mode now renders one full-width row per catalog item.
- Price, label, image path, description, enabled checkbox, and Save button are easier to click/type.
- Added shop NPC support.
- Player store opens by walking near the NPC and pressing E.
- Ground marker is disabled by default for a cleaner clothing-store-like flow.

Config:
- Config.Ped controls the NPC model/scenario/invincible/freeze behavior.
- Each Config.Shops entry can use pedCoords = vec4(x, y, z, heading).
- Config.Interact.distance controls how close the player must be to press E.
