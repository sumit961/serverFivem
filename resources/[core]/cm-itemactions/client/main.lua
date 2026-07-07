local function requestAnimDictSafe(dict, timeoutMs)
    dict = tostring(dict or '')
    if dict == '' then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + (tonumber(timeoutMs) or 1200)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function playActionAnim(kind, duration)
    local ped = PlayerPedId()
    if not ped or ped == 0 or IsPedInAnyVehicle(ped, false) then return end

    kind = tostring(kind or 'use'):lower()
    local dict, anim, flag
    if kind == 'clothes' or kind == 'armor' then
        dict, anim, flag, duration = 'clothingshirt', 'try_shirt_positive_d', 49, tonumber(duration) or 1200
    elseif kind == 'pickup' then
        dict, anim, flag, duration = 'pickup_object', 'pickup_low', 48, tonumber(duration) or 850
    else
        dict, anim, flag, duration = 'mp_common', 'givetake1_a', 48, tonumber(duration) or 900
    end

    CreateThread(function()
        if requestAnimDictSafe(dict, 1400) then
            TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration, flag, 0.0, false, false, false)
            Wait(duration)
            StopAnimTask(ped, dict, anim, 1.0)
            RemoveAnimDict(dict)
        end
    end)
end

RegisterNetEvent('cm-itemactions:client:playActionAnim', function(kind, duration)
    playActionAnim(kind, duration)
end)

RegisterNetEvent('cm-itemactions:client:heal', function(amount)
    playActionAnim('use')
    amount = tonumber(amount) or 0
    local ped = PlayerPedId()
    local current = GetEntityHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.min(maxHealth, current + amount))
end)

RegisterNetEvent('cm-itemactions:client:armor', function(amount)
    playActionAnim('armor')
    amount = tonumber(amount) or 0
    local ped = PlayerPedId()
    local current = GetPedArmour(ped)
    SetPedArmour(ped, math.min(100, current + amount))
end)

RegisterNetEvent('cm-itemactions:client:repairVehicle', function()
    playActionAnim('use', 1400)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        local coords = GetEntityCoords(ped)
        veh = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end
    if veh ~= 0 then
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, 900.0)
        SetVehicleBodyHealth(veh, 900.0)
    end
end)

RegisterNetEvent('cm-itemactions:client:lockpickStart', function()
    playActionAnim('use', 1200)
    -- Placeholder. Later this should open your lockpick minigame.
    print('[CM-ITEMACTIONS] Lockpick placeholder triggered')
end)

RegisterNetEvent('cm-itemactions:client:showIdCard', function(item)
    playActionAnim('use', 900)
    -- Placeholder. Later this should show the ID card to nearby players.
    print(('[CM-ITEMACTIONS] ID card metadata: %s'):format(json.encode(item and item.metadata or {})))
end)


local CLOTHING_CATEGORIES = {
    tshirt   = { type = 'component', index = 8 },
    torso    = { type = 'component', index = 11 },
    pants    = { type = 'component', index = 4 },
    legs     = { type = 'component', index = 4 },
    shoes    = { type = 'component', index = 6 },
    chains   = { type = 'component', index = 7 },
    bags     = { type = 'component', index = 5 },
    hat      = { type = 'prop',      index = 0 },
    glasses  = { type = 'prop',      index = 1 },
    earrings = { type = 'prop',      index = 2 },
    watches  = { type = 'prop',      index = 6 },
}

local function notify(msg, typ)
    TriggerEvent('cm-hud:client:notify', tostring(msg or ''), typ or 'info')
end

local function getCategory(itemName, metadata)
    local category = tostring((metadata and (metadata.categoryType or metadata.category)) or ''):lower()
    if category == '' then
        category = tostring(itemName or ''):lower():gsub('^clothing_', '')
    end
    return category
end

local function readCurrentClothing(ped, def)
    if def.type == 'prop' then
        return {
            drawableId = GetPedPropIndex(ped, def.index),
            textureId = GetPedPropTextureIndex(ped, def.index)
        }
    end

    local data = {
        drawableId = GetPedDrawableVariation(ped, def.index),
        textureId = GetPedTextureVariation(ped, def.index)
    }

    if def.index == 11 then
        data.arms = GetPedDrawableVariation(ped, 3)
        data.armsTexture = GetPedTextureVariation(ped, 3)
        data.undershirt = GetPedDrawableVariation(ped, 8)
        data.undershirtTexture = GetPedTextureVariation(ped, 8)
    end

    return data
end

local function equipClothing(ped, def, drawable, texture)
    drawable = tonumber(drawable)
    texture = tonumber(texture) or 0
    if drawable == nil then return false end

    if def.type == 'prop' then
        if drawable < 0 then
            ClearPedProp(ped, def.index)
        else
            SetPedPropIndex(ped, def.index, drawable, texture, true)
        end
    else
        SetPedComponentVariation(ped, def.index, drawable, texture, 0)
    end

    return true
end


local function applyTorso(metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local ped = PlayerPedId()

    local torso = tonumber(metadata.drawableId or metadata.drawable)
    local torsoTexture = tonumber(metadata.textureId or metadata.texture) or 0
    if not torso then
        TriggerEvent('cm-hud:client:notify', 'Invalid shirt metadata.', 'error')
        return false
    end

    local arms = tonumber(metadata.arms)
    local armsTexture = tonumber(metadata.armsTexture) or 0
    local undershirt = tonumber(metadata.undershirt)
    local undershirtTexture = tonumber(metadata.undershirtTexture) or 0

    if arms then
        SetPedComponentVariation(ped, 3, arms, armsTexture, 0)
    end

    if undershirt then
        SetPedComponentVariation(ped, 8, undershirt, undershirtTexture, 0)
    end

    SetPedComponentVariation(ped, 11, torso, torsoTexture, 0)
    TriggerEvent('nvCloth:client:equipClothingItem', 'torso', torso, torsoTexture)
    return true
end

RegisterNetEvent('cm-itemactions:client:equipTorso', function(metadata)
    applyTorso(metadata)
end)

RegisterNetEvent('cm-itemactions:client:swapClothing', function(requestId, itemName, metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local category = getCategory(itemName, metadata)
    local def = CLOTHING_CATEGORIES[category]

    if not def then
        TriggerServerEvent('cm-itemactions:server:clothingSwapComplete', requestId, {
            success = false,
            message = 'Unsupported clothing category.'
        })
        return
    end

    local ped = PlayerPedId()
    playActionAnim('clothes', 1200)
    local old = readCurrentClothing(ped, def)
    local ok

    if category == 'torso' then
        ok = applyTorso(metadata)
    else
        ok = equipClothing(ped, def, metadata.drawableId or metadata.drawable, metadata.textureId or metadata.texture)
    end

    if not ok then
        TriggerServerEvent('cm-itemactions:server:clothingSwapComplete', requestId, {
            success = false,
            message = 'Invalid clothing metadata.'
        })
        return
    end

    if category ~= 'torso' then
        TriggerEvent('nvCloth:client:equipClothingItem', category, metadata.drawableId or metadata.drawable, metadata.textureId or metadata.texture)
    end
    notify('Clothing equipped.', 'success')
    TriggerServerEvent('cm-itemactions:server:clothingSwapComplete', requestId, {
        success = true,
        old = old
    })
end)
