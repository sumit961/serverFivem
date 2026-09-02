local function exportSafe(fn)
    return function(...)
        local ok, result, extra = pcall(fn, ...)
        if not ok then
            print(('[CM-ITEMS] Client export error: %s'):format(tostring(result)))
            return nil
        end
        return result, extra
    end
end

exports('GetItem', exportSafe(function(name, includeVirtual)
    return CMItems.GetItem(name, includeVirtual)
end))

exports('GetPhysicalItem', exportSafe(function(name)
    return CMItems.GetPhysicalItem(name)
end))

exports('GetVirtualItem', exportSafe(function(name)
    return CMItems.GetVirtualItem(name)
end))

exports('GetInventoryItems', exportSafe(function()
    return CMItems.GetInventoryItems()
end))

exports('GetVirtualItems', exportSafe(function()
    return CMItems.GetVirtualItems()
end))

exports('IsInventoryItem', exportSafe(function(name)
    return CMItems.IsInventoryItem(name)
end))

exports('IsVirtualItem', exportSafe(function(name)
    return CMItems.IsVirtualItem(name)
end))

exports('IsRobberyProtected', exportSafe(function(name)
    return CMItems.IsRobberyProtected(name)
end))

exports('GetWeight', exportSafe(function(name, amount)
    return CMItems.GetWeight(name, amount)
end))

exports('ValidateMetadata', exportSafe(function(name, metadata)
    return CMItems.ValidateMetadata(name, metadata)
end))

exports('GetItemWorldModel', exportSafe(function(name, metadata)
    return CMItems.GetItemWorldModel(name, metadata)
end))

exports('GetCategoryWorldModel', exportSafe(function(category)
    return CMItems.GetCategoryWorldModel(category)
end))

exports('ResolveTorsoFit', exportSafe(function(gender, torsoDrawable, torsoTexture, fallback)
    return CMItems.ResolveTorsoFit(gender, torsoDrawable, torsoTexture, fallback)
end))

exports('GetBestTorsoFit', exportSafe(function(gender, torsoDrawable, torsoTexture)
    return CMItems.GetBestTorsoFit(gender, torsoDrawable, torsoTexture)
end))

--========================================================
-- Clothing catalog client sync
--========================================================
local previewOpen = false
local buildPreviewPayload

RegisterNetEvent('cm-items:client:setClothingCatalog', function(catalog)
    CMItems.SetClothingCatalog(catalog or { male = {}, female = {} })
    if CMItems.Config and CMItems.Config.Debug then
        print('[CM-ITEMS] Clothing catalog synced to client')
    end
end)

RegisterNetEvent('cm-items:client:setItemsCatalog', function(catalogItems)
    CMItems.Items = CMItems.Items or {}
    for name in pairs(CMItems.CatalogItems or {}) do
        CMItems.Items[name] = nil
    end

    CMItems.CatalogItems = catalogItems or {}
    for name, def in pairs(CMItems.CatalogItems) do
        CMItems.Items[name] = def
    end
    if previewOpen then
        SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
    end
    if CMItems.Config and CMItems.Config.Debug then
        print('[CM-ITEMS] Item catalog synced to client')
    end
end)

-- Per-item drop-prop overrides, synced from the server for the preview UI.
CMItems.ItemProps = CMItems.ItemProps or {}

RegisterNetEvent('cm-items:client:setItemProps', function(props)
    CMItems.ItemProps = props or {}
    if previewOpen then
        SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
    end
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('cm-items:server:requestCatalogSync')
    TriggerServerEvent('cm-items:server:requestItemsCatalogSync')
    TriggerServerEvent('cm-items:server:requestItemPropsSync')
end)

exports('GetClothingCatalogEntry', exportSafe(function(gender, componentType, componentIndex, drawableId, textureId)
    return CMItems.GetClothingCatalogEntry(gender, componentType, componentIndex, drawableId, textureId)
end))

exports('GetClothingCatalog', exportSafe(function()
    return CMItems.Clothing.Catalog or { male = {}, female = {} }
end))


--========================================================
-- Admin Item Preview UI
-- /cmitempreview or /cmitemsui shows all cm-items definitions and clothing catalog rows with images.
--========================================================

local function imageUrlForItem(image)
    image = tostring(image or '')
    if image == '' then image = 'clothing.png' end
    if image:find('^nui://') then return image end
    return ('nui://cm-items/ui/images/%s'):format(image)
end

local function imageUrlForCatalog(image)
    image = tostring(image or '')
    if image == '' then return 'nui://cm-items/ui/images/clothing.png' end
    if image:find('^nui://') then return image end
    if image:find('^clothing/') then return ('nui://cm-items/ui/images/%s'):format(image) end
    return ('nui://cm-items/ui/images/clothing/%s'):format(image)
end

local function flattenCatalog()
    local rows = {}
    local catalog = CMItems.Clothing and CMItems.Clothing.Catalog or {}
    for gender, byComponent in pairs(catalog) do
        if type(byComponent) == 'table' then
            for componentIndex, byDrawable in pairs(byComponent) do
                if type(byDrawable) == 'table' then
                    for drawableId, entryWrap in pairs(byDrawable) do
                        if type(entryWrap) == 'table' then
                            local function addEntry(textureId, entry)
                                if type(entry) ~= 'table' then return end
                                rows[#rows + 1] = {
                                    kind = 'catalog',
                                    name = ('%s %s:%s:%s'):format(tostring(gender), tostring(componentIndex), tostring(drawableId), tostring(textureId)),
                                    label = entry.label or ('Clothing ' .. tostring(drawableId)),
                                    category = entry.category or 'clothing',
                                    gender = gender,
                                    componentType = entry.componentType or 'component',
                                    componentIndex = tonumber(componentIndex),
                                    drawableId = tonumber(drawableId),
                                    textureId = tonumber(textureId) or 0,
                                    price = tonumber(entry.price) or 0,
                                    enabled = entry.enabled ~= false,
                                    shop = entry.shop or 'clothes',
                                    image = imageUrlForCatalog(entry.image),
                                    description = entry.description or '',
                                    arms = entry.arms,
                                    armsTexture = entry.armsTexture or entry.arms_texture,
                                    undershirt = entry.undershirt,
                                    undershirtTexture = entry.undershirtTexture or entry.undershirt_texture,
                                    sleeveStyle = entry.sleeveStyle or entry.sleeve_style,
                                    bagLevel = entry.bagLevel or entry.bag_level,
                                    source = 'clothing_catalog',
                                    deletable = true,
                                }
                            end
                            if type(entryWrap.default) == 'table' then addEntry(-1, entryWrap.default) end
                            if type(entryWrap.textures) == 'table' then
                                for textureId, entry in pairs(entryWrap.textures) do addEntry(textureId, entry) end
                            else
                                for textureId, entry in pairs(entryWrap) do
                                    if type(textureId) == 'number' and type(entry) == 'table' then addEntry(textureId, entry) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        return (a.category .. a.name) < (b.category .. b.name)
    end)
    return rows
end

-- Resolve the effective drop prop for the UI (mirrors the server resolver, but
-- only needs override -> category default because the item's own worldModel is
-- passed in). Clothing intentionally shares one prop.
local function effectivePropForItem(name, category, itemWorldModel)
    local override = CMItems.ItemProps and CMItems.ItemProps[name]
    if override and override.model and override.model ~= '' then
        return { model = override.model, zOffset = tonumber(override.zOffset) or 0.0, heading = tonumber(override.heading) or 0.0, override = true }
    end
    if type(itemWorldModel) == 'string' and itemWorldModel ~= '' then
        return { model = itemWorldModel, zOffset = 0.0, heading = 0.0, override = false }
    end
    local models = (CMItems.Config and CMItems.Config.WorldModels) or {}
    category = tostring(category or 'misc'):lower()
    if tostring(name):find('clothing_', 1, true) == 1 then category = 'clothing' end
    if tostring(name):find('weapon_', 1, true) == 1 then category = 'weapon' end
    if tostring(name):find('ammo_', 1, true) == 1 then category = 'ammo' end
    return { model = models[category] or models.default or 'prop_cs_cardbox_01', zOffset = 0.0, heading = 0.0, override = false }
end

function buildPreviewPayload()
    local items = {}
    for name, item in pairs(CMItems.GetAllItems and CMItems.GetAllItems() or {}) do
        local category = item.category or item.type or 'misc'
        local itemWorldModel = (CMItems.GetItemWorldModel and CMItems.GetItemWorldModel(name)) or item.worldModel or ''
        local prop = effectivePropForItem(name, category, item.worldModel)
        items[#items + 1] = {
            kind = 'item',
            name = name,
            label = item.label or name,
            category = category,
            itemType = item.itemType or item.type or 'normal',
            weight = tonumber(item.weight) or 0,
            stack = item.stack ~= false,
            usable = item.usable == true,
            inventory = item.inventory ~= false,
            virtual = item.virtual == true,
            image = imageUrlForItem(item.image or item.icon),
            description = item.description or '',
            equipmentSlot = item.equipmentSlot or item.equipSlot or '',
            worldModel = itemWorldModel,
            propModel = prop.model,
            propZOffset = prop.zOffset,
            propHeading = prop.heading,
            propOverride = prop.override,
            source = (CMItems.CatalogItems and CMItems.CatalogItems[name]) and 'catalog' or 'static',
            deletable = (CMItems.CatalogItems and CMItems.CatalogItems[name]) ~= nil,
        }
    end
    table.sort(items, function(a, b) return (a.category .. a.name) < (b.category .. b.name) end)
    return { items = items, catalog = flattenCatalog() }
end

local function openItemPreview()
    previewOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
end

RegisterCommand('cmitempreview', function()
    openItemPreview()
end, false)

RegisterCommand('cmitemsui', function()
    openItemPreview()
end, false)

RegisterNUICallback('closeItemPreview', function(_, cb)
    previewOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closeItemPreview' })
    cb({ success = true })
end)

RegisterNUICallback('refreshItemPreview', function(_, cb)
    SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
    cb({ success = true })
end)



local previewCallbacks = {}
local previewRequestId = 0

local function nextPreviewRequest(cb)
    previewRequestId = previewRequestId + 1
    local requestId = tostring(previewRequestId)
    previewCallbacks[requestId] = cb
    return requestId
end

RegisterNUICallback('previewGiveItem', function(data, cb)
    TriggerServerEvent('cm-items:server:previewGiveItem', nextPreviewRequest(cb), data or {})
end)

RegisterNUICallback('previewDeleteItem', function(data, cb)
    TriggerServerEvent('cm-items:server:previewDeleteItem', nextPreviewRequest(cb), data or {})
end)

RegisterNUICallback('previewSetProp', function(data, cb)
    TriggerServerEvent('cm-items:server:previewSetProp', nextPreviewRequest(cb), data or {})
end)

RegisterNUICallback('previewClearProp', function(data, cb)
    TriggerServerEvent('cm-items:server:previewClearProp', nextPreviewRequest(cb), data or {})
end)

RegisterNUICallback('previewSetImage', function(data, cb)
    TriggerServerEvent('cm-items:server:previewSetImage', nextPreviewRequest(cb), data or {})
end)

RegisterNetEvent('cm-items:client:previewImageResult', function(requestId, success, message, itemName)
    local cb = previewCallbacks[tostring(requestId)]
    previewCallbacks[tostring(requestId)] = nil
    if cb then cb({ success = success == true, message = message, itemName = itemName }) end
    if success and previewOpen then
        SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
    end
    if lib and lib.notify then
        lib.notify({ title = 'CM Items', description = tostring(message or ''), type = success and 'success' or 'error' })
    end
end)

-- Local spawn test: preview the prop (with z-offset/heading) in front of the
-- player for a few seconds. Client-only, no persistence.
local testProp = nil
RegisterNUICallback('previewSpawnProp', function(data, cb)
    data = data or {}
    local model = tostring(data.model or '')
    if model == '' then cb({ success = false, message = 'No model' }); return end

    CreateThread(function()
        if testProp and DoesEntityExist(testProp) then DeleteEntity(testProp); testProp = nil end
        local hash = joaat(model)
        RequestModel(hash)
        local tries = 0
        while not HasModelLoaded(hash) and tries < 100 do Wait(20); tries = tries + 1 end
        if not HasModelLoaded(hash) then return end

        local ped = PlayerPedId()
        local fwd = GetEntityForwardVector(ped)
        local pos = GetEntityCoords(ped) + (fwd * 1.2)
        local z = pos.z - 0.9 + (tonumber(data.zOffset) or 0.0)
        testProp = CreateObject(hash, pos.x, pos.y, z, false, false, false)
        if testProp and testProp ~= 0 then
            SetEntityHeading(testProp, GetEntityHeading(ped) + (tonumber(data.heading) or 0.0))
            PlaceObjectOnGroundProperly(testProp)
            FreezeEntityPosition(testProp, true)
            SetEntityAlpha(testProp, 200, false)
        end
        SetModelAsNoLongerNeeded(hash)
        Wait(6000)
        if testProp and DoesEntityExist(testProp) then DeleteEntity(testProp); testProp = nil end
    end)
    cb({ success = true })
end)

RegisterNetEvent('cm-items:client:previewPropResult', function(requestId, success, message, itemName)
    local cb = previewCallbacks[tostring(requestId)]
    previewCallbacks[tostring(requestId)] = nil
    if cb then cb({ success = success == true, message = message, itemName = itemName }) end
    if success and previewOpen then
        SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
    end
    if lib and lib.notify then
        lib.notify({ title = 'CM Items', description = tostring(message or ''), type = success and 'success' or 'error' })
    end
end)

RegisterNetEvent('cm-items:client:previewGiveResult', function(requestId, success, message, itemName)
    local cb = previewCallbacks[tostring(requestId)]
    previewCallbacks[tostring(requestId)] = nil
    if cb then
        cb({ success = success == true, message = message, itemName = itemName })
    end

    local text
    if success and message == 'existing_item_reused' then
        text = ('Updated existing %s; no duplicate was added'):format(tostring(itemName or 'item'))
    elseif success then
        text = ('Added %s to inventory'):format(tostring(itemName or 'item'))
    else
        text = tostring(message or 'Could not add item')
    end
    if lib and lib.notify then
        lib.notify({ title = 'CM Items', description = text, type = success and 'success' or 'error' })
    else
        print(('[CM-ITEMS] %s'):format(text))
    end
end)

RegisterNetEvent('cm-items:client:previewDeleteResult', function(requestId, success, message, itemName)
    local cb = previewCallbacks[tostring(requestId)]
    previewCallbacks[tostring(requestId)] = nil
    if cb then
        cb({ success = success == true, message = message, itemName = itemName })
    end

    local text = success and ('Deleted %s from registry'):format(tostring(itemName or 'item')) or tostring(message or 'Could not delete item')
    if success then
        SendNUIMessage({ type = 'openItemPreview', payload = buildPreviewPayload() })
    end

    if lib and lib.notify then
        lib.notify({ title = 'CM Items', description = text, type = success and 'success' or 'error' })
    else
        print(('[CM-ITEMS] %s'):format(text))
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and previewOpen then
        SetNuiFocus(false, false)
    end
end)
