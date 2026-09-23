local Config = CMFarming.Config

local function dbg(...)
    if Config.Debug then print('[CM-FARMING]', ...) end
end

local ITEM_DEFS = {}

for cropName, crop in pairs(Config.Crops) do
    ITEM_DEFS[crop.seedItem] = {
        name = crop.seedItem,
        label = crop.seedLabel or (crop.label .. ' Seeds'),
        image = 'nui://cm-farming/ui/images/' .. crop.seedItem .. '.png',
        category = 'tool',
        itemType = 'normal',
        weight = 100,
        stack = true,
        unique = false,
        usable = false,
        description = ('Seeds for growing %s.'):format(crop.label),
    }

    ITEM_DEFS[crop.cropItem] = {
        name = crop.cropItem,
        label = crop.label,
        image = 'nui://cm-farming/ui/images/' .. crop.cropItem .. '.png',
        category = 'misc',
        itemType = 'normal',
        weight = 400,
        stack = true,
        unique = false,
        usable = false,
        description = crop.description or ('A harvested %s crop.'):format(crop.label),
    }
end

for name, tool in pairs(Config.Tools) do
    ITEM_DEFS[name] = {
        name = name,
        label = tool.label,
        image = 'nui://cm-farming/ui/images/' .. (tool.image or (name .. '.png')),
        category = 'tool',
        itemType = 'normal',
        weight = name == 'watering_can' and 1200 or 300,
        stack = false,
        unique = false,
        usable = tool.usable == true,
        description = tool.description or '',
    }
end

ITEM_DEFS[Config.Livestock.feedItem] = {
    name = Config.Livestock.feedItem,
    label = Config.Livestock.feedLabel,
    image = 'nui://cm-farming/ui/images/default.png',
    category = 'tool',
    itemType = 'normal',
    weight = 200,
    stack = true,
    unique = false,
    usable = false,
    description = 'Feed for cows. Consumed when feeding.',
}

ITEM_DEFS[Config.Livestock.milkItem] = {
    name = Config.Livestock.milkItem,
    label = Config.Livestock.milkLabel,
    image = 'nui://cm-farming/ui/images/default.png',
    category = 'misc',
    itemType = 'normal',
    weight = 500,
    stack = true,
    unique = false,
    usable = false,
    description = 'Fresh milk from the dairy farm.',
}

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
        print('[CM-FARMING] cm-items is not running. Add the farming items manually.')
        return
    end

    -- Always (re)registers, overwriting whatever cm-items already has for
    -- these names -- this catalog is fully owned by shared/config.lua.
    for itemName, definition in pairs(ITEM_DEFS) do
        if registerCatalogItem(resourceName, definition) then
            dbg('registered catalog item:', itemName)
        else
            print(('[CM-FARMING] Could not auto-register %s. Add it manually to cm-items.'):format(itemName))
        end
    end
end)
