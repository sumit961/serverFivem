# v1.2.4 Selector Layout + Inventory Clothing Preview

Changes:

- Character cards moved to the far left side of the screen.
- Character details moved to the far right side of the screen.
- Middle of screen stays open for the live GTA world preview ped.
- Selector music is off by default. Player can turn it on from the button.
- Preview camera/ped placement was raised and pulled back to avoid the ped looking like it is inside the ground.
- Character slot payload now includes equipped inventory items from `inventory_items` for equipment slots.
- Preview ped applies equipped clothing from inventory metadata:
  - shirt
  - outerwear
  - pants
  - shoes
  - accessory
  - bag
  - headwear
  - glasses
  - earrings
  - watch

Notes:

- The inventory query expects `inventory_items.owner_type = 'character'` and `owner_id = characters.id`.
- Clothing items must use metadata fields like `drawableId`/`drawable`, `textureId`/`texture`, plus torso fields like `arms`, `undershirt`, etc.
