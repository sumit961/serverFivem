-- cm-characters/server/appearance.lua

-- ClockMate clothing inventory starter support
local CM_NAKED_BASE = {
    male = {
        arms = 15, arms_2 = 0,
        pants_1 = 21, pants_2 = 0,
        shoes_1 = 34, shoes_2 = 0,
        tshirt_1 = 15, tshirt_2 = 0,
        torso_1 = 15, torso_2 = 0,
    },
    female = {
        arms = 15, arms_2 = 0,
        pants_1 = 15, pants_2 = 0,
        shoes_1 = 35, shoes_2 = 0,
        tshirt_1 = 14, tshirt_2 = 0,
        torso_1 = 15, torso_2 = 0,
    }
}

local function cmIsFemaleAppearance(appearance)
    local sex = appearance and appearance.sex
    return sex == 'female' or sex == 'f' or sex == 1 or sex == '1'
end

local function cmCopyTable(value)
    if type(value) ~= 'table' then return {} end
    local out = {}
    for k, v in pairs(value) do
        if type(v) == 'table' then
            out[k] = cmCopyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function cmItemsCall(method, ...)
    if GetResourceState('cm-items') ~= 'started' then return nil end
    local args = { ... }

    local ok, result, extra = pcall(function()
        return exports['cm-items'][method](table.unpack(args))
    end)
    if ok and result ~= nil then return result, extra end

    ok, result, extra = pcall(function()
        return exports['cm-items'][method](exports['cm-items'], table.unpack(args))
    end)
    if ok and result ~= nil then return result, extra end

    return nil
end

local function cmFallbackClothingImage(gender, componentType, componentIndex, drawableId)
    gender = gender == 'female' and 'female' or 'male'
    local propPrefix = componentType == 'prop' and 'prop_' or ''
    local drawable = tonumber(drawableId)
    if not drawable or drawable < 0 then return 'nui://cm-items/ui/images/clothing.png' end
    return ('nui://cm-items/ui/images/clothing/%s_%s%s_%s.png'):format(gender, propPrefix, tostring(componentIndex), tostring(drawable))
end

local function cmBuildStarterClothingMeta(category, raw, opts)
    raw = type(raw) == 'table' and raw or {}
    opts = type(opts) == 'table' and opts or {}

    local built = cmItemsCall('BuildClothingMetadata', category, raw, opts)
    if type(built) == 'table' then
        built.equipped = true
        built.itemType = built.itemType or 'clothing'
        built.rarity = built.rarity or 'normal'
        built.label = built.label or opts.label
        return built
    end

    local component = category == 'torso' and 11 or category == 'shoes' and 6 or 4
    local meta = {
        categoryType = category,
        componentType = 'component',
        componentIndex = component,
        drawableId = tonumber(raw.drawableId) or 0,
        textureId = tonumber(raw.textureId) or 0,
        gender = opts.gender or 'male',
        label = opts.label or ('Starter ' .. category),
        description = opts.description or 'Starter clothing item',
        itemType = 'clothing',
        rarity = 'normal',
        equipped = true,
    }
    meta.image = cmFallbackClothingImage(meta.gender, meta.componentType, meta.componentIndex, meta.drawableId)
    meta.icon = meta.image

    if category == 'torso' then
        meta.arms = tonumber(raw.arms)
        meta.armsTexture = tonumber(raw.armsTexture) or 0
        meta.undershirt = tonumber(raw.undershirt)
        meta.undershirtTexture = tonumber(raw.undershirtTexture) or 0
    end

    return meta
end

local function cmGiveStarterClothes(src, appearance)
    if GetResourceState('cm-inventory') ~= 'started' then
        print('[CM-CHARACTERS] cm-inventory not started; starter clothes were not given.')
        return nil
    end

    appearance = type(appearance) == 'table' and appearance or {}
    local gender = cmIsFemaleAppearance(appearance) and 'female' or 'male'
    local naked = CM_NAKED_BASE[gender]

    -- Build starter clothing metadata through cm-items so image/metadata logic is shared
    -- by character creator, nv_cloth shop, and inventory.
    local torsoMeta = cmBuildStarterClothingMeta('torso', {
        drawableId = tonumber(appearance.torso_1) or naked.torso_1,
        textureId = tonumber(appearance.torso_2) or 0,
        gender = gender,
        arms = tonumber(appearance.arms) or naked.arms,
        armsTexture = tonumber(appearance.arms_2) or 0,
        undershirt = tonumber(appearance.tshirt_1) or naked.tshirt_1,
        undershirtTexture = tonumber(appearance.tshirt_2) or 0,
    }, {
        gender = gender,
        label = 'Starter Top',
        description = 'Clothing selected during character creation.',
    })

    local pantsMeta = cmBuildStarterClothingMeta('pants', {
        drawableId = tonumber(appearance.pants_1) or naked.pants_1,
        textureId = tonumber(appearance.pants_2) or 0,
        gender = gender,
    }, {
        gender = gender,
        label = 'Starter Pants',
        description = 'Clothing selected during character creation.',
    })

    local shoesMeta = cmBuildStarterClothingMeta('shoes', {
        drawableId = tonumber(appearance.shoes_1) or naked.shoes_1,
        textureId = tonumber(appearance.shoes_2) or 0,
        gender = gender,
    }, {
        gender = gender,
        label = 'Starter Shoes',
        description = 'Clothing selected during character creation.',
    })

    -- Sixth argument is the preferred inventory slot. This makes starter clothes appear equipped,
    -- not just sitting in the backpack/pocket. cm-inventory now preserves this 6th arg.
    local okTorso, torsoSlot = exports['cm-inventory']:AddItem(src, 'clothing_torso', 1, torsoMeta, 'starter_clothes_equipped', 'outerwear')
    local okPants, pantsSlot = exports['cm-inventory']:AddItem(src, 'clothing_pants', 1, pantsMeta, 'starter_clothes_equipped', 'pants')
    local okShoes, shoesSlot = exports['cm-inventory']:AddItem(src, 'clothing_shoes', 1, shoesMeta, 'starter_clothes_equipped', 'shoes')

    if not okTorso then print('[CM-CHARACTERS] Starter torso add failed: ' .. tostring(torsoSlot)) end
    if not okPants then print('[CM-CHARACTERS] Starter pants add failed: ' .. tostring(pantsSlot)) end
    if not okShoes then print('[CM-CHARACTERS] Starter shoes add failed: ' .. tostring(shoesSlot)) end

    local equipment = {}
    if okTorso and torsoSlot == 'outerwear' then
        equipment.outerwear = { item_name = 'clothing_torso', label = torsoMeta.label, metadata = torsoMeta }
    end
    if okPants and pantsSlot == 'pants' then
        equipment.pants = { item_name = 'clothing_pants', label = pantsMeta.label, metadata = pantsMeta }
    end
    if okShoes and shoesSlot == 'shoes' then
        equipment.shoes = { item_name = 'clothing_shoes', label = shoesMeta.label, metadata = shoesMeta }
    end

    return next(equipment) and equipment or nil
end

local function cmMakeNakedAppearance(appearance)
    appearance = type(appearance) == 'table' and appearance or {}
    local gender = cmIsFemaleAppearance(appearance) and 'female' or 'male'
    for key, value in pairs(CM_NAKED_BASE[gender]) do
        appearance[key] = value
    end
    return appearance
end

RegisterNetEvent('cm-characters:server:saveAppearance', function(charId, appearanceData)
    local src = source

    if type(appearanceData) ~= 'table' then
        TriggerClientEvent('cm-characters:client:error', src, 'Invalid appearance data')
        return
    end

    local char = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
    if not char or #char == 0 then
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end
    
    local charFull = char[1]

    -- Verify this character belongs to the requesting player's account.
    local playerAccountId = tostring(Player(src).state.accountId or '')
    if playerAccountId ~= '' and tostring(charFull.account_id) ~= playerAccountId then
        TriggerClientEvent('cm-characters:client:error', src, 'Character does not belong to your account')
        return
    end

    -- IMPORTANT:
    -- cm-inventory resolves owner from Player(src).state.charId.
    -- During first character creation this state may not exist yet, so set it BEFORE AddItem.
    Player(src).state:set('charId', charId, true)
    Player(src).state:set('characterId', charId, true)

    -- Give starter clothing items only the first time this character saves appearance.
    -- Otherwise every later SaveAppearance/equip would duplicate starter clothes.
    local alreadyHasAppearance = false
    if charFull.appearance_json and charFull.appearance_json ~= '' and charFull.appearance_json ~= '{}' and charFull.appearance_json ~= 'null' then
        alreadyHasAppearance = true
    end

    -- Keep the creator outfit for starter inventory items, but save only the naked/base
    -- body appearance to the character JSON. This prevents clothes coming back from JSON.
    local creatorOutfit = cmCopyTable(appearanceData)

    local starterEquipment = nil
    if not alreadyHasAppearance then
        starterEquipment = cmGiveStarterClothes(src, creatorOutfit)
    end

    local baseAppearance = cmMakeNakedAppearance(cmCopyTable(appearanceData))
    local appearanceJson = json.encode(baseAppearance)

    -- Use Query for UPDATE (cm-core doesn't have Execute)
    local ok, result = pcall(function()
        exports['cm-core']:Query(
            'UPDATE characters SET appearance_json = ? WHERE id = ?',
            {appearanceJson, charId}
        )
        return true
    end)

    if not ok then
        print('[CM-CHARACTERS] ERROR saving appearance: ' .. tostring(result))
        TriggerClientEvent('cm-characters:client:error', src, 'Failed to save appearance')
        return
    end

    print('[CM-CHARACTERS] Appearance saved for char ' .. tostring(charId))

    exports['cm-core']:CacheInvalidate('char:' .. charId)

    Player(src).state:set('charId', charId, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('cash', charFull.cash or 0, true)
    Player(src).state:set('bank', charFull.bank or 0, true)

    -- For first creation, do NOT apply the naked/base appearance immediately.
    -- The player is already wearing the chosen creator clothes client-side; applying base here
    -- caused the one-frame default/naked blink. cm-spawn may still apply the saved base after
    -- characterLoaded, so we re-apply inventory equipment several times on the client.
    if alreadyHasAppearance then
        TriggerClientEvent('cm-characters:client:applyAppearance', src, baseAppearance)
    end

    TriggerEvent('cm-core:characterLoaded', src, charId)

    -- Spawn is handled by cm-spawn / cm-core:characterLoaded. Do not trigger the old removed
    -- cm-characters:client:spawn event here; this resource no longer registers that client event.

    if starterEquipment then
        TriggerClientEvent('cm-characters:client:equipStarterClothingSlots', src, starterEquipment)
    end

    -- Always let inventory win after creation/spawn. This covers cm-spawn or any other
    -- appearance script that applies the naked/base JSON after our starter event.
    TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
    SetTimeout(1000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
    SetTimeout(3000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
end)

RegisterNetEvent('cm-characters:server:saveCurrentAppearance', function(appearanceData)
    local src = source
    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        TriggerClientEvent('cm-hud:client:notify', src, 'No active character to save appearance.', 'error')
        return
    end
    if type(appearanceData) ~= 'table' then return end

    -- Merge with existing appearance so a clothing-only save cannot wipe face/hair data.
    local merged = {}
    local rows = exports['cm-core']:Query('SELECT appearance_json FROM characters WHERE id = ?', { charId })
    local existingJson = rows and rows[1] and rows[1].appearance_json
    if existingJson and existingJson ~= '' and existingJson ~= 'null' then
        local ok, decoded = pcall(json.decode, existingJson)
        if ok and type(decoded) == 'table' then
            merged = decoded
        end
    end

    for key, value in pairs(appearanceData) do
        merged[key] = value
    end

    -- Clothing is inventory-owned. Even when SaveAppearance is triggered after equipping or
    -- removing clothes, never persist shirt/torso/pants/shoes into appearance_json.
    merged = cmMakeNakedAppearance(merged)

    exports['cm-core']:Query('UPDATE characters SET appearance_json = ? WHERE id = ?', { json.encode(merged), charId })
    exports['cm-core']:CacheInvalidate('char:' .. tostring(charId))
end)

exports('SaveAppearance', function(src)
    src = tonumber(src)
    if not src then return false end
    TriggerClientEvent('cm-characters:client:requestCurrentAppearanceSave', src)
    return true
end)


-- Development helper: /givestarterclothes from F8/server console event if starter clothes were missed during testing.
RegisterNetEvent('cm-characters:server:debugGiveStarterClothes', function(appearanceData)
    local src = source
    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        TriggerClientEvent('cm-hud:client:notify', src, 'No active character.', 'error')
        return
    end
    if type(appearanceData) ~= 'table' then return end
    cmGiveStarterClothes(src, appearanceData)
    TriggerClientEvent('cm-hud:client:notify', src, 'Starter clothing items added.', 'success')
end)
