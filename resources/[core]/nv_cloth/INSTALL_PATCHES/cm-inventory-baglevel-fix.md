# cm-inventory bagLevel fix

Your clothing/admin side now sends bag metadata as `metadata.bagLevel`.
Patch `cm-inventory/server/main.lua` so it also accepts older aliases and both BagLevels config shapes.

## 1) Replace getBagLevelFromItem(row) with this

```lua
local function getBagLevelFromItem(row)
    if not row then return 0 end
    local metadata = decode(row.metadata)
    local def = getItemDef(row.item_name) or {}

    local level = tonumber(
        metadata.bagLevel or metadata.bag_level or metadata.level or
        metadata.backpackLevel or metadata.backpack_level or
        def.bagLevel or def.bag_level or def.level
    )

    if level then return math.max(0, math.min(4, math.floor(level))) end

    local name = tostring(row.item_name or ''):lower()
    local fromName = name:match('bag_level(%d)') or name:match('backpack_level(%d)') or name:match('bag(%d)')
    if fromName then return math.max(0, math.min(4, tonumber(fromName) or 0)) end
    return 0
end
```

## 2) In rowToItem(row), use this output field

```lua
bagLevel = tonumber(metadata.bagLevel or metadata.bag_level or metadata.level or def.bagLevel or def.bag_level or def.level) or 0
```

## 3) Replace getBagInfo(ownerType, ownerId) with this

```lua
local function getBagInfo(ownerType, ownerId)
    local bagRow = getItemAt(ownerType, ownerId, 'bag')
    local level = getBagLevelFromItem(bagRow)
    local cfg = Config.BagLevels and Config.BagLevels[level] or nil
    if not cfg then
        cfg = Config.BagLevels and Config.BagLevels[0] or {
            label = 'No Bag',
            backpackSlots = 0,
            maxWeight = Config.Weight and Config.Weight.max or 25000
        }
    end

    return {
        level = level,
        label = cfg.label or ('Bag Level ' .. tostring(level)),
        backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
        maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000
    }
end
```

## 4) Replace getBagConfigByLevel(level) with this

```lua
local function getBagConfigByLevel(level)
    level = math.max(0, math.min(4, tonumber(level) or 0))
    local cfg = Config.BagLevels and Config.BagLevels[level] or nil
    if not cfg then
        cfg = Config.BagLevels and Config.BagLevels[0] or {
            label = 'No Bag',
            backpackSlots = 0,
            maxWeight = Config.Weight and Config.Weight.max or 25000
        }
    end

    return {
        level = level,
        label = cfg.label or ('Bag Level ' .. tostring(level)),
        backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
        maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000
    }
end
```

This makes inventory accept `bagLevel`, `bag_level`, or `level`, and it supports config values named either `backpackSlots/maxWeight` or `slots/weight`.
