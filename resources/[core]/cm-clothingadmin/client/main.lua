local pending = nil
local nuiOpen = false
local requestId = 0
local requests = {}

local COMPONENTS = {
    tshirt   = { type = 'component', index = 8,  label = 'T-Shirt', itemName = 'clothing_tshirt' },
    shirt    = { type = 'component', index = 8,  label = 'T-Shirt', itemName = 'clothing_tshirt' },
    torso    = { type = 'component', index = 11, label = 'Top', itemName = 'clothing_torso' },
    top      = { type = 'component', index = 11, label = 'Top', itemName = 'clothing_torso' },
    jacket   = { type = 'component', index = 11, label = 'Top', itemName = 'clothing_torso' },
    pants    = { type = 'component', index = 4,  label = 'Pants', itemName = 'clothing_pants' },
    legs     = { type = 'component', index = 4,  label = 'Pants', itemName = 'clothing_pants' },
    shoes    = { type = 'component', index = 6,  label = 'Shoes', itemName = 'clothing_shoes' },
    chains   = { type = 'component', index = 7,  label = 'Chain', itemName = 'clothing_chains' },
    chain    = { type = 'component', index = 7,  label = 'Chain', itemName = 'clothing_chains' },
    bags     = { type = 'component', index = 5,  label = 'Bag', itemName = 'clothing_bags' },
    bag      = { type = 'component', index = 5,  label = 'Bag', itemName = 'clothing_bags' },
    hat      = { type = 'prop',      index = 0,  label = 'Hat', itemName = 'clothing_hat' },
    glasses  = { type = 'prop',      index = 1,  label = 'Glasses', itemName = 'clothing_glasses' },
    earrings = { type = 'prop',      index = 2,  label = 'Earrings', itemName = 'clothing_earrings' },
    ears     = { type = 'prop',      index = 2,  label = 'Earrings', itemName = 'clothing_earrings' },
    watches  = { type = 'prop',      index = 6,  label = 'Watch', itemName = 'clothing_watches' },
    watch    = { type = 'prop',      index = 6,  label = 'Watch', itemName = 'clothing_watches' },
}

local function say(msg)
    print(('[CM-CLOTHINGADMIN] %s'):format(msg))
    TriggerEvent('chat:addMessage', {
        color = { 120, 200, 255 },
        multiline = true,
        args = { 'CM Clothing', tostring(msg or '') }
    })
end

local function getGender(ped)
    local model = GetEntityModel(ped or PlayerPedId())
    return model == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
end

local function getCurrent(category)
    local def = COMPONENTS[tostring(category or ''):lower()]
    if not def then return nil, 'Unknown category.' end

    local ped = PlayerPedId()
    local drawable, texture

    if def.type == 'prop' then
        drawable = GetPedPropIndex(ped, def.index)
        texture = drawable ~= -1 and GetPedPropTextureIndex(ped, def.index) or 0
    else
        drawable = GetPedDrawableVariation(ped, def.index)
        texture = GetPedTextureVariation(ped, def.index)
    end

    local entry = {
        gender = getGender(ped),
        componentType = def.type,
        componentIndex = def.index,
        drawableId = drawable,
        textureId = texture,
        label = ('%s %s/%s'):format(def.label, drawable, texture),
        price = 0,
        category = category,
        shop = (CMClothingAdmin.Config and CMClothingAdmin.Config.DefaultShop) or 'city',
        enabled = true,
        itemName = def.itemName,
    }

    if def.index == 11 and def.type == 'component' then
        entry.arms = GetPedDrawableVariation(ped, 3)
        entry.armsTexture = GetPedTextureVariation(ped, 3)
        entry.undershirt = GetPedDrawableVariation(ped, 8)
        entry.undershirtTexture = GetPedTextureVariation(ped, 8)
    end

    return entry
end

local function getCurrentFit()
    local ped = PlayerPedId()
    return {
        arms = GetPedDrawableVariation(ped, 3),
        armsTexture = GetPedTextureVariation(ped, 3),
        undershirt = GetPedDrawableVariation(ped, 8),
        undershirtTexture = GetPedTextureVariation(ped, 8),
    }
end

local function pendingSummary()
    if not pending then return 'No pending clothing captured. Use /cmclothcapture torso first.' end
    return ('%s %s comp=%s drawable=%s texture=%s label="%s" price=%s category=%s shop=%s arms=%s:%s undershirt=%s:%s enabled=%s'):format(
        pending.gender or '?',
        pending.componentType or '?',
        tostring(pending.componentIndex),
        tostring(pending.drawableId),
        tostring(pending.textureId),
        tostring(pending.label or ''),
        tostring(pending.price or 0),
        tostring(pending.category or ''),
        tostring(pending.shop or ''),
        tostring(pending.arms or ''),
        tostring(pending.armsTexture or 0),
        tostring(pending.undershirt or ''),
        tostring(pending.undershirtTexture or 0),
        tostring(pending.enabled ~= false)
    )
end

local function serverRequest(eventName, payload, timeoutMs)
    requestId = requestId + 1
    local id = requestId
    local p = promise.new()
    requests[id] = p
    TriggerServerEvent(eventName, id, payload or {})
    SetTimeout(timeoutMs or 6000, function()
        if requests[id] then
            requests[id] = nil
            p:resolve({ ok = false, error = 'server timeout' })
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('cm-clothingadmin:client:serverResponse', function(id, data)
    local p = requests[id]
    if not p then return end
    requests[id] = nil
    p:resolve(data or { ok = false, error = 'empty response' })
end)

local function openAdminUi()
    local current = getCurrent('torso')
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        current = current,
        config = {
            categories = (CMClothingAdmin.Config and CMClothingAdmin.Config.Categories) or {},
            shops = (CMClothingAdmin.Config and CMClothingAdmin.Config.Shops) or {},
            defaultShop = (CMClothingAdmin.Config and CMClothingAdmin.Config.DefaultShop) or 'city',
            defaultCategory = (CMClothingAdmin.Config and CMClothingAdmin.Config.DefaultCategory) or 'uncategorized'
        }
    })
end

local function closeAdminUi()
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function applyPreview(entry)
    if type(entry) ~= 'table' then return false, 'invalid entry' end
    local ped = PlayerPedId()
    local componentType = tostring(entry.componentType or 'component')
    local index = tonumber(entry.componentIndex)
    local drawable = tonumber(entry.drawableId)
    local texture = tonumber(entry.textureId) or 0
    if not index or not drawable then return false, 'missing component/drawable' end

    if componentType == 'prop' then
        if drawable < 0 then
            ClearPedProp(ped, index)
        else
            SetPedPropIndex(ped, index, drawable, texture, true)
        end
    else
        if texture < 0 then texture = 0 end
        SetPedComponentVariation(ped, index, drawable, texture, 0)
        if index == 11 then
            if entry.arms ~= nil then SetPedComponentVariation(ped, 3, tonumber(entry.arms) or 0, tonumber(entry.armsTexture) or 0, 0) end
            if entry.undershirt ~= nil then SetPedComponentVariation(ped, 8, tonumber(entry.undershirt) or 0, tonumber(entry.undershirtTexture) or 0, 0) end
        end
    end
    return true
end

-- NUI callbacks
RegisterNUICallback('close', function(_, cb)
    closeAdminUi()
    cb({ ok = true })
end)

RegisterNUICallback('getCurrentClothing', function(data, cb)
    local entry, err = getCurrent(data and data.category or 'torso')
    cb(entry and { ok = true, entry = entry } or { ok = false, error = err or 'capture failed' })
end)

RegisterNUICallback('getCurrentFit', function(_, cb)
    cb({ ok = true, fit = getCurrentFit() })
end)

RegisterNUICallback('previewClothing', function(data, cb)
    local ok, err = applyPreview(data and data.entry)
    cb({ ok = ok, error = err })
end)

RegisterNUICallback('getCatalogItems', function(_, cb)
    cb(serverRequest('cm-clothingadmin:server:nuiGetCatalogItems', {}))
end)

RegisterNUICallback('saveCatalogItem', function(data, cb)
    cb(serverRequest('cm-clothingadmin:server:nuiSaveEntry', data or {}))
end)

RegisterNUICallback('deleteCatalogItem', function(data, cb)
    cb(serverRequest('cm-clothingadmin:server:nuiDeleteEntry', data or {}))
end)

RegisterNUICallback('reloadCatalog', function(_, cb)
    cb(serverRequest('cm-clothingadmin:server:nuiReloadCatalog', {}))
end)

RegisterCommand('clothingadmin', function()
    openAdminUi()
end, false)

RegisterCommand('cmclothingadmin', function()
    openAdminUi()
end, false)

-- Legacy command workflow kept for fast testing/dev use.
RegisterCommand('cmclothcapture', function(_, args)
    local entry, err = getCurrent(args[1] or 'torso')
    if not entry then say(err or 'Capture failed.') return end
    pending = entry
    say('Captured: ' .. pendingSummary())
end, false)

RegisterCommand('cmclothpreview', function()
    say(pendingSummary())
end, false)

RegisterCommand('cmclothset', function(_, args)
    if not pending then say('No pending clothing. Use /cmclothcapture torso first.') return end
    local key = tostring(args[1] or ''):lower()
    table.remove(args, 1)
    local value = table.concat(args, ' ')

    if key == 'name' or key == 'label' then
        pending.label = value
    elseif key == 'price' then
        pending.price = tonumber(value) or 0
    elseif key == 'category' then
        pending.category = value
    elseif key == 'shop' then
        pending.shop = value
    elseif key == 'sleeve' then
        pending.sleeveStyle = value
        if value == 'full' then
            pending.arms = 6
            pending.armsTexture = 0
        elseif value == 'half' then
            pending.arms = 5
            pending.armsTexture = 0
        elseif value == 'custom' then
            local fit = getCurrentFit()
            pending.arms = fit.arms
            pending.armsTexture = fit.armsTexture
        elseif value == 'none' then
            pending.sleeveStyle = nil
        end
    elseif key == 'enabled' then
        local v = tostring(value):lower()
        pending.enabled = not (v == '0' or v == 'false' or v == 'no' or v == 'disabled')
    elseif key == 'image' then
        pending.image = value
    elseif key == 'job' then
        pending.job = value ~= '' and value or nil
    elseif key == 'gang' then
        pending.gang = value ~= '' and value or nil
    elseif key == 'notes' then
        pending.notes = value
    elseif key == 'texture' then
        pending.textureId = tonumber(value) or pending.textureId
    else
        say('Unknown field. Use name, price, category, shop, sleeve, enabled, image, job, gang, notes, texture.')
        return
    end

    say('Updated: ' .. pendingSummary())
end, false)

RegisterCommand('cmclothfit', function()
    if not pending then say('No pending clothing. Use /cmclothcapture torso first.') return end
    if tonumber(pending.componentIndex) ~= 11 then say('Fit is only for torso/top component 11.') return end
    local fit = getCurrentFit()
    pending.arms = fit.arms
    pending.armsTexture = fit.armsTexture
    pending.undershirt = fit.undershirt
    pending.undershirtTexture = fit.undershirtTexture
    say('Fit captured: ' .. pendingSummary())
end, false)

RegisterCommand('cmclothsave', function()
    if not pending then say('No pending clothing. Use /cmclothcapture torso first.') return end
    TriggerServerEvent('cm-clothingadmin:server:saveEntry', pending)
end, false)

RegisterCommand('cmclothdelete', function(_, args)
    local gender = args[1]
    local componentIndex = tonumber(args[2])
    local drawableId = tonumber(args[3])
    local textureId = tonumber(args[4])
    if not gender or not componentIndex or not drawableId then
        say('Usage: /cmclothdelete <male|female> <componentIndex> <drawableId> [textureId|-1]')
        return
    end
    TriggerServerEvent('cm-clothingadmin:server:deleteEntry', gender, 'component', componentIndex, drawableId, textureId or -1)
end, false)

RegisterCommand('cmclothreload', function()
    TriggerServerEvent('cm-clothingadmin:server:reloadCatalog')
end, false)

RegisterNetEvent('cm-clothingadmin:client:notify', function(message)
    say(tostring(message or ''))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and nuiOpen then
        SetNuiFocus(false, false)
    end
end)
