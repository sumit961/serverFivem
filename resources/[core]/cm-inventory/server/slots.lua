-- cm-inventory/slots.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

local function getRows(ownerType, ownerId)
    return MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY slot ASC', { ownerType, tostring(ownerId) }) or {}
end

local function getItemAt(ownerType, ownerId, slot)
    return MySQL.single.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND slot = ? LIMIT 1', {
        ownerType, tostring(ownerId), slot
    })
end

local function getUsedWeight(ownerType, ownerId)
    local rows = getRows(ownerType, ownerId)
    local weight = 0
    for _, row in ipairs(rows) do
        local def = getItemDef(row.item_name)
        weight = weight + ((def and tonumber(def.weight) or 0) * (tonumber(row.quantity) or 1))
    end
    return weight
end

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

local function getBagInfo(ownerType, ownerId)
    local bagRow = getItemAt(ownerType, ownerId, 'bag')
    local level = getBagLevelFromItem(bagRow)
    local cfg = Config.BagLevels and Config.BagLevels[level] or nil
    if not cfg then cfg = Config.BagLevels and Config.BagLevels[0] or { label = 'No Bag', backpackSlots = 0, maxWeight = Config.Weight.max } end
    return {
        level = level,
        label = cfg.label or ('Bag Level ' .. tostring(level)),
        backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
        maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000
    }
end

local function isBackpackSlot(slot)
    return type(slot) == 'string' and slot:find(Config.Slots.backpack.prefix, 1, true) == 1
end

local function backpackSlotIndex(slot)
    if not isBackpackSlot(slot) then return nil end
    return tonumber(slot:sub(#Config.Slots.backpack.prefix + 1))
end

local function isSlotUnlocked(ownerType, ownerId, slot)
    if not isBackpackSlot(slot) then return true end
    local idx = backpackSlotIndex(slot)
    if not idx then return false end
    local bag = getBagInfo(ownerType, ownerId)
    return idx <= (bag.backpackSlots or 0)
end

local function getMaxWeight(ownerType, ownerId)
    return getBagInfo(ownerType, ownerId).maxWeight
end


-- Bag transition safety:
-- Changing/removing a bag can reduce unlocked backpack slots and max weight.
-- We block the action unless every backpack slot that would become locked is empty
-- after the move/swap, and the current inventory weight fits the new capacity.
local function getBagConfigByLevel(level)
    level = math.max(0, math.min(4, tonumber(level) or 0))
    local cfg = Config.BagLevels and Config.BagLevels[level] or nil
    if not cfg then cfg = Config.BagLevels and Config.BagLevels[0] or { label = 'No Bag', backpackSlots = 0, maxWeight = Config.Weight.max } end
    return {
        level = level,
        label = cfg.label or ('Bag Level ' .. tostring(level)),
        backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
        maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000
    }
end

local function rowCanActAsBag(row)
    if not row then return false end
    local name = tostring(row.item_name or ''):lower()
    -- clothing_bags carries bagLevel in its metadata and acts as a real bag.
    -- All other clothing_* items are not bags.
    if name:find('clothing_', 1, true) == 1 then
        return name == 'clothing_bags' and getBagLevelFromItem(row) > 0
    end
    if getBagLevelFromItem(row) > 0 then return true end
    local ok = false
    pcall(function()
        ok = canPlaceInSlot(row.item_name, 'bag') == true
    end)
    return ok == true
end

local function validatePostBagState(ownerType, ownerId, newLevel, sourceRow, destRow, fromSlot, toSlot)
    local cfg = getBagConfigByLevel(newLevel)
    local allowedBackpackSlots = cfg.backpackSlots or 0

    local rows = getRows(ownerType, ownerId)
    for _, row in ipairs(rows) do
        local finalSlot = row.slot

        if sourceRow and tonumber(row.id) == tonumber(sourceRow.id) then
            finalSlot = toSlot
        elseif destRow and tonumber(row.id) == tonumber(destRow.id) then
            finalSlot = fromSlot
        end

        local idx = backpackSlotIndex(finalSlot)
        if idx and idx > allowedBackpackSlots then
            local label = row.item_name or 'item'
            return false, ('Cannot change/remove bag. Empty backpack slot %s first. It contains %s and would become locked.'):format(finalSlot, label)
        end
    end

    local currentWeight = getUsedWeight(ownerType, ownerId)
    if currentWeight > (cfg.maxWeight or 25000) then
        return false, ('Cannot change/remove bag. Inventory weight %.1fkg exceeds %s capacity %.1fkg.'):format(currentWeight / 1000.0, cfg.label, (cfg.maxWeight or 0) / 1000.0)
    end

    return true
end

local function validateBagTransition(ownerType, ownerId, fromSlot, toSlot, sourceRow, destRow)
    -- Only the bag slot changes backpack limits. Normal inventory moves are unaffected.
    if fromSlot ~= 'bag' and toSlot ~= 'bag' then return true end
    if not sourceRow then return true end

    local currentBag = getBagInfo(ownerType, ownerId)
    local newLevel = currentBag.level or 0

    if toSlot == 'bag' then
        -- Equipping/replacing bag: the source item becomes the active bag.
        if not rowCanActAsBag(sourceRow) then return true end
        newLevel = getBagLevelFromItem(sourceRow)
    elseif fromSlot == 'bag' then
        -- Removing current bag, or swapping with another bag from destination.
        if destRow and rowCanActAsBag(destRow) then
            newLevel = getBagLevelFromItem(destRow)
        else
            newLevel = 0
        end
    end

    return validatePostBagState(ownerType, ownerId, newLevel, sourceRow, destRow, fromSlot, toSlot)
end

local function validateBagRemovalFromSlot(ownerType, ownerId, slot, row)
    if slot ~= 'bag' or not rowCanActAsBag(row) then return true end
    -- Dropping/giving/consuming the active bag means new level 0.
    return validatePostBagState(ownerType, ownerId, 0, row, nil, slot, nil)
end

local function isPlayerDeadState(src)
    src = tonumber(src)
    if not src or src <= 0 then return true end
    local player = Player(src)
    return player and player.state and player.state.isDead == true or false
end

local function isPlayerInVehicleState(src)
    local ped = GetPlayerPed(tonumber(src) or -1)
    if not ped or ped == 0 then return false end
    local ok, vehicle = pcall(GetVehiclePedIsIn, ped, false)
    return ok and vehicle and vehicle ~= 0 or false
end

local function buildInventoryPayload(src)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return nil, 'No character owner found.' end

    local rows = getRows(ownerType, ownerId)
    local items = {}
    for _, row in ipairs(rows) do items[#items + 1] = rowToItem(row) end

    return {
        ownerType = ownerType,
        ownerId = tostring(ownerId),
        items = items,
        weight = {
            current = getUsedWeight(ownerType, ownerId),
            max = getMaxWeight(ownerType, ownerId)
        },
        bag = getBagInfo(ownerType, ownerId),
        slots = Config.Slots
    }
end

local function sendInventory(src, forceOpen)
    if forceOpen == true and isPlayerDeadState(src) then return false end
    local payload, err = buildInventoryPayload(src)
    if not payload then
        TriggerClientEvent('cm-inventory:client:notify', src, err or 'Could not load inventory.', 'error')
        return false
    end

    -- forceOpen=true is only used when the player explicitly opens inventory.
    -- Item add/pickup/use/drop should refresh the UI only if it is already open,
    -- not pop the inventory open by itself.
    if forceOpen == true then
        TriggerClientEvent('cm-inventory:client:open', src, payload)
    else
        TriggerClientEvent('cm-inventory:client:update', src, payload)
    end

    return true
end

local function findEmptySlot(ownerType, ownerId)
    for i = 1, Config.Slots.pockets.count do
        local slot = Config.Slots.pockets.prefix .. i
        if not getItemAt(ownerType, ownerId, slot) then return slot end
    end

    local bag = getBagInfo(ownerType, ownerId)
    for i = 1, math.min(Config.Slots.backpack.count, bag.backpackSlots or 0) do
        local slot = Config.Slots.backpack.prefix .. i
        if not getItemAt(ownerType, ownerId, slot) then return slot end
    end
    return nil
end

local function canCarry(ownerType, ownerId, itemName, amount)
    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end
    local addWeight = (tonumber(def.weight) or 0) * (tonumber(amount) or 1)
    if getUsedWeight(ownerType, ownerId) + addWeight > getMaxWeight(ownerType, ownerId) then
        return false, 'Inventory is too heavy. Upgrade/equip a better bag.'
    end
    return true
end

