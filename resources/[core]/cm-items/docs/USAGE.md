# CM-Items usage

## Check item

```lua
local item = exports['cm-items']:GetPhysicalItem('water')
```

## Inventory validation

```lua
if not exports['cm-items']:IsInventoryItem(itemName) then
    return false, 'This item cannot be stored in inventory'
end
```

## Get weight

```lua
local weight = exports['cm-items']:GetWeight('water', 3)
-- 1500 grams
```

## Virtual items

```lua
local phone = exports['cm-items']:GetVirtualItem('phone')
```

Virtual items are for labels/images/rules only. Do not insert them into inventory tables.

## Add more physical items

Edit:

```text
shared/items.lua
```

## Add more virtual system items

Edit:

```text
shared/virtual.lua
```
