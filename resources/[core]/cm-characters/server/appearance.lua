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

CMCharacters.GiveStarterClothes = cmGiveStarterClothes

local function cmMakeNakedAppearance(appearance)
    appearance = type(appearance) == 'table' and appearance or {}
    local gender = cmIsFemaleAppearance(appearance) and 'female' or 'male'
    for key, value in pairs(CM_NAKED_BASE[gender]) do
        appearance[key] = value
    end
    return appearance
end


local function failAppearanceSave(src, message)
    message = tostring(message or 'Failed to save appearance')
    TriggerClientEvent('cm-characters:client:error', src, message)
    TriggerClientEvent('cm-characters:client:appearanceSaved', src, false, { message = message })
end

RegisterNetEvent('cm-characters:server:saveAppearance', function(charId, appearanceData)
    local src = source

    if type(appearanceData) ~= 'table' then
        failAppearanceSave(src, 'Invalid appearance data')
        return
    end

    local char, accountId, err = CMCharacters.GetOwnedCharacter(src, charId)
    if not char then
        failAppearanceSave(src, err or 'Character not found')
        return
    end

    -- IMPORTANT:
    -- cm-inventory resolves owner from Player(src).state.charId.
    -- During first character creation this state may not exist yet, so set it BEFORE AddItem.
    CMCharacters.SetCharacterState(src, char)

    -- Give starter clothing items only the first time this character saves appearance.
    -- Otherwise every later SaveAppearance/equip would duplicate starter clothes.
    local alreadyHasAppearance = false
    if char.appearance_json and char.appearance_json ~= '' and char.appearance_json ~= '{}' and char.appearance_json ~= 'null' then
        alreadyHasAppearance = true
    end

    local creatorOutfit = cmCopyTable(appearanceData)
    local starterEquipment = nil
    if not alreadyHasAppearance then
        starterEquipment = cmGiveStarterClothes(src, creatorOutfit)
    end

    local baseAppearance = cmMakeNakedAppearance(cmCopyTable(appearanceData))
    local appearanceJson = json.encode(baseAppearance)

    local ok, result = pcall(function()
        CMCharacters.Query(
            'UPDATE characters SET appearance_json = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ?',
            { appearanceJson, tostring(char.id), accountId }
        )
    end)

    if not ok then
        print('[CM-CHARACTERS] ERROR saving appearance: ' .. tostring(result))
        failAppearanceSave(src, 'Failed to save appearance')
        return
    end

    print('[CM-CHARACTERS] Appearance saved for char ' .. tostring(char.id))
    exports['cm-core']:CacheInvalidate('char:' .. tostring(char.id))

    -- Refresh state with saved character details.
    CMCharacters.SetCharacterState(src, char)

    if alreadyHasAppearance then
        TriggerClientEvent('cm-characters:client:applyAppearance', src, baseAppearance)
    end

    TriggerEvent('cm-core:characterLoaded', src, tostring(char.id))

    if starterEquipment then
        TriggerClientEvent('cm-characters:client:equipStarterClothingSlots', src, starterEquipment)
    end

    TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
    SetTimeout(1000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
    SetTimeout(3000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)

    -- Acknowledgement used by the client to close the creator only after the DB/inventory work finished.
    TriggerClientEvent('cm-characters:client:appearanceSaved', src, true, {
        charId = tostring(char.id),
        alreadyHadAppearance = alreadyHasAppearance,
        starterEquipment = starterEquipment ~= nil
    })
end)

RegisterNetEvent('cm-characters:server:saveCurrentAppearance', function(appearanceData)
    local src = source
    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        CMCharacters.Notify(src, 'No active character to save appearance.', 'error')
        return
    end
    if type(appearanceData) ~= 'table' then return end

    local char, accountId, err = CMCharacters.GetOwnedCharacter(src, charId)
    if not char then
        CMCharacters.Notify(src, err or 'Character not found.', 'error')
        return
    end

    local merged = {}
    local existingJson = char.appearance_json
    if existingJson and existingJson ~= '' and existingJson ~= 'null' then
        local ok, decoded = pcall(json.decode, existingJson)
        if ok and type(decoded) == 'table' then merged = decoded end
    end

    for key, value in pairs(appearanceData) do merged[key] = value end
    merged = cmMakeNakedAppearance(merged)

    CMCharacters.Query(
        'UPDATE characters SET appearance_json = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ?',
        { json.encode(merged), tostring(char.id), accountId }
    )
    exports['cm-core']:CacheInvalidate('char:' .. tostring(char.id))
end)

exports('SaveAppearance', function(src)
    src = tonumber(src)
    if not src then return false end
    TriggerClientEvent('cm-characters:client:requestCurrentAppearanceSave', src)
    return true
end)

RegisterNetEvent('cm-characters:server:debugGiveStarterClothes', function(appearanceData)
    local src = source
    if not CMCharacters.IsAdmin(src) then
        CMCharacters.Notify(src, 'No permission to use starter clothing debug tools.', 'error')
        return
    end

    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        CMCharacters.Notify(src, 'No active character.', 'error')
        return
    end
    if type(appearanceData) ~= 'table' then return end

    local char = CMCharacters.GetOwnedCharacter(src, charId)
    if not char then
        CMCharacters.Notify(src, 'Character ownership check failed.', 'error')
        return
    end

    cmGiveStarterClothes(src, appearanceData)
    CMCharacters.LogAdmin(src, 'debug_give_starter_clothes', { char_id = tostring(charId) })
    CMCharacters.Notify(src, 'Starter clothing items added.', 'success')
end)
