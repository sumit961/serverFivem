# cm-gunstore integration plan

Next, `cm-gunstore` should stop saving gun/ammo rules itself.

It should read from `cm-weapons`:

```lua
local catalog = exports['cm-weapons']:GetCatalog(false)
local ammo = catalog.ammo
local weapons = catalog.weapons
```

For store admin, `cm-gunstore` should only manage:

- /gunadmin controls shop price/stock/store visibility
- shown in this store yes/no
- NPC/store location
- preview camera
- buy button

Do not duplicate weapon damage, ammo pickup hash, or weapon hash in `cm-gunstore` anymore. Those should stay in `cm-weapons`.
