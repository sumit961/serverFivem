# CM Items 1.5.1

- Added packaged CM cyan icons for bandage, medical kits, body armor,
  painkillers, antibiotics, and adrenaline shots.
- Medical image URLs are authoritative across static definitions, SQL catalog
  rows, saved image overrides, inventory, and `/cmitempreview`.
- Inventory fallbacks now resolve bandage, medkit, medikit, and armor directly
  from the `cm-items` image owner.
