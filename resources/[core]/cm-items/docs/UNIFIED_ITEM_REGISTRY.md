# Unified Item Registry (cm-items as single source of truth)

## The model

- **Item definitions** (what an item *is*: name, label, image, weight, usable,
  armor value, component/drawable/texture, weapon hash, etc.) live in **cm-items**
  in the `cm_items_catalog` table. This is the single source of truth.
- **Images** are saved into **cm-items** (`ui/images/catalog/<name>.png`), so an
  item is fully independent of the resource that created it.
- **Shop data** (price, stock, enabled-in-this-shop) stays in each store
  (e.g. cm-gunstore's `cm_gun_catalog`). A shop row only references an item by
  name and adds its price.

This means: **make the item once → it exists on the server → use it anywhere**
(any store, any event, admin give).

## Creating items

Any resource creates an item by calling:

```lua
exports['cm-items']:SaveCatalogItem({
    name        = 'armor_heavy_tactical',
    label       = 'Heavy Tactical Vest',
    category    = 'armor',
    itemType    = 'rare',
    equipmentSlot = 'bodyarmor',
    armorValue  = 100,
    weight      = 2500,
    stack       = false,
    usable      = true,
    description = 'Heavy protective vest.',
    metadata    = { componentIndex = 9, drawableId = 12, textureId = 0, gender = 'male' },
    imageData   = '<base64 png data url>', -- cm-items saves this to its own folder
    -- OR: image = 'nui://some-resource/path.png' (explicit path, skips base64 save)
    enabled     = true,
    createdBy   = 'player:1',
})
```

The gun store now does this automatically when you create armor/weapon/ammo:
the **definition + PNG** go to cm-items; the **price/stock** go to
`cm_gun_catalog`.

## Using items anywhere

Give an item to a player from any script/event:

```lua
exports['cm-items']:GiveCatalogItem(playerSrc, 'armor_heavy_tactical', 1)
```

Or in-game (admin): `/giveitem <playerId> <itemName> [amount]`

## Reading the registry

```lua
local def  = exports['cm-items']:GetCatalogItem('armor_heavy_tactical')
local list = exports['cm-items']:GetCatalogByCategory('armor')
```

Because catalog items are merged into `CMItems.Items` on load, the standard
`cm-items:GetItem(name)` and `cm-items:IsInventoryItem(name)` also resolve them —
so **cm-inventory accepts them automatically** (no per-item registration, no
name-pattern workaround needed).

## Exports added to cm-items

- `SaveCatalogItem(def)` -> ok, { name, image }
- `GetCatalogItem(name)` -> def | nil
- `GetCatalogByCategory(category)` -> def[]
- `DeleteCatalogItem(name)` -> ok
- `SaveCatalogImage(name, dataUri)` -> nui path
- `ReloadItemsCatalog()` -> reloads from DB
- `GiveCatalogItem(src, name, amount, metaOverride)` -> ok

## Install

1. Run `cm-items/sql/items_catalog.sql` once.
2. Replace `cm-items`, `cm-gunstore`, and `nv_cloth` with these updated builds.
3. Load order (cm-items must start before stores that use it):
   ```
   ensure oxmysql
   ensure cm-items
   ensure cm-inventory
   ensure screenshot-basic
   ensure nv_cloth
   ensure cm-gunstore
   ```
4. Ensure `cm-items/ui/images/catalog/` exists (a `.keep` file is included).

## Flow recap (armor vest)

1. `/gunadmin` -> Type = Armor -> Capture Vest (Clothing Studio).
2. nv_cloth photographs the vest, chroma-keys a transparent PNG, and forwards the
   **base64 image + component/drawable/texture** to the gun admin form.
3. Admin sets name/price/armor and clicks Create.
4. cm-gunstore:
   - calls `cm-items:SaveCatalogItem` (definition + PNG saved in cm-items),
   - writes price/stock to `cm_gun_catalog`.
5. Buying adds the item (cm-inventory resolves it from cm-items).
6. Using it equips component 9 + armor (handled in cm-inventory's bodyarmor slot).

## Notes

- cm-inventory's `DynamicItemPatterns` safety net is harmless to keep, but is no
  longer required now that items are registered in cm-items.
- Clothing still uses its existing `clothing_catalog` flow (unchanged, already
  worked). It can be migrated into the generic catalog later if desired; both can
  coexist.
