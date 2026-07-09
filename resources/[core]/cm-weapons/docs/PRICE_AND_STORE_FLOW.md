# Price and store flow

`cm-weapons` is only the central weapon/ammo registry. It stores:

- ammo item name, label, ammo type, GTA ammo pickup hash, pack size, weight, image
- weapon item name, label, GTA weapon hash, allowed ammo item, damage, magazine size, weight, image
- sync into `cm-items`

It does not decide shop price.

Use `/gunadmin` in `cm-gunstore` to list every weapon/ammo from `cm-weapons`, then set:

- sale price
- stock
- In Store / Hidden
- optional store override image/description
