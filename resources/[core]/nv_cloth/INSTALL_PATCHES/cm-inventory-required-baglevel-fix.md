# Required cm-inventory bag metadata fix

Your clothing resources now always send bag metadata like this:

```lua
metadata.bagLevel = 1 -- 1 to 4
metadata.bag_level = 1 -- compatibility alias
metadata.level = 1 -- compatibility alias
```

If `cm-inventory/server/main.lua` errors with:

```text
attempt to index a nil value (global 'metadata')
```

then inside that function you are reading a global `metadata` variable. Replace that code with a local safe metadata reader.

Use this helper near the top of `server/main.lua`:

```lua
local function decodeMetadata(meta)
    if type(meta) == 'string' then
        local ok, decoded = pcall(json.decode, meta)
        meta = ok and decoded or {}
    end
    return type(meta) == 'table' and meta or {}
end

local function getBagLevelFromItem(item)
    item = type(item) == 'table' and item or {}
    local meta = decodeMetadata(item.metadata or item.info or item.meta)
    local def = {}

    if GetResourceState('cm-items') == 'started' then
        local ok, itemDef = pcall(function()
            return exports['cm-items']:GetItem(item.name or item.item_name or item.item)
        end)
        if ok and type(itemDef) == 'table' then def = itemDef end
    end

    local level = tonumber(
        meta.bagLevel or meta.bag_level or meta.level or
        meta.backpackLevel or meta.backpack_level or
        item.bagLevel or item.bag_level or item.level or
        def.bagLevel or def.bag_level or def.level
    )

    if not level then
        local name = tostring(item.name or item.item_name or item.item or ''):lower()
        level = tonumber(name:match('bag_level(%d)') or name:match('backpack_level(%d)') or name:match('bag(%d)'))
    end

    level = tonumber(level) or 0
    return math.max(0, math.min(4, math.floor(level)))
end
```

At the old failing line, do **not** use:

```lua
metadata.bagLevel
```

Use:

```lua
local bagLevel = getBagLevelFromItem(item)
```

Then resolve capacity from your inventory config:

```lua
local cfg = Config.BagLevels and Config.BagLevels[bagLevel]
local backpackSlots = cfg and tonumber(cfg.backpackSlots or cfg.slots) or 0
local maxWeight = cfg and tonumber(cfg.maxWeight or cfg.weight) or 0
```

This keeps inventory as the authority for slots/weight while clothing only sends the bag level.
