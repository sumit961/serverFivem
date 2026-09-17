local Config = CMFishing.Config

local function dbg(...)
    if Config.Debug then print('[CM-FISHING]', ...) end
end

local ITEM_DEFS = {}

for name, rod in pairs(Config.Rods) do
    ITEM_DEFS[name] = {
        name = name,
        label = rod.label,
        image = 'nui://cm-fishing/ui/images/' .. rod.image,
        category = 'tool',
        itemType = 'normal',
        weight = 1800,
        stack = false,
        unique = false,
        usable = false,
        description = rod.description or ('A fishing rod (%s).'):format(rod.label),
    }
end

for name, bait in pairs(Config.Bait) do
    ITEM_DEFS[name] = {
        name = name,
        label = bait.label,
        image = 'nui://cm-fishing/ui/images/' .. bait.image,
        category = 'tool',
        itemType = 'normal',
        weight = 60,
        stack = true,
        unique = false,
        usable = false,
        description = bait.description or 'Bait for fishing.',
    }
end

for name, fish in pairs(Config.Fish) do
    ITEM_DEFS[name] = {
        name = name,
        label = fish.label,
        image = 'nui://cm-fishing/ui/images/' .. name .. '.png',
        category = 'misc',
        itemType = 'normal',
        weight = 900,
        stack = true,
        unique = false,
        usable = false,
        description = fish.description or ('A %s catch (%s rarity).'):format(fish.label, fish.rarity),
    }
end

local function getCatalogResource()
    if GetResourceState('cm-items') == 'started' then return 'cm-items' end
    return nil
end

local function registerCatalogItem(resourceName, definition)
    local ok, result = pcall(function()
        return exports[resourceName]:RegisterItem(definition.name, definition)
    end)
    return ok and result ~= false
end

CreateThread(function()
    local attempts = 0
    local resourceName = getCatalogResource()
    while not resourceName and attempts < 40 do
        Wait(500)
        attempts = attempts + 1
        resourceName = getCatalogResource()
    end

    if not resourceName then
        print('[CM-FISHING] cm-items is not running. Add the fishing items manually.')
        return
    end

    -- Always (re)registers, overwriting whatever cm-items already has for
    -- these names. This catalog is fully owned by shared/config.lua, not
    -- meant for manual edits via cm-items' own tooling, so a config change
    -- (a new description, price, etc.) should take effect on every restart
    -- instead of silently staying stale because the name was already known.
    for itemName, definition in pairs(ITEM_DEFS) do
        if registerCatalogItem(resourceName, definition) then
            dbg('registered catalog item:', itemName)
        else
            print(('[CM-FISHING] Could not auto-register %s. Add it manually to cm-items.'):format(itemName))
        end
    end
end)
