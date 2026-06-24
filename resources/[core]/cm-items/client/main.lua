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

RegisterNetEvent('cm-items:client:setClothingCatalog', function(catalog)
    CMItems.SetClothingCatalog(catalog or { male = {}, female = {} })
    if CMItems.Config and CMItems.Config.Debug then
        print('[CM-ITEMS] Clothing catalog synced to client')
    end
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('cm-items:server:requestCatalogSync')
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
local previewOpen = false

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

local function buildPreviewPayload()
    local items = {}
    for name, item in pairs(CMItems.GetAllItems and CMItems.GetAllItems() or {}) do
        items[#items + 1] = {
            kind = 'item',
            name = name,
            label = item.label or name,
            category = item.category or item.type or 'misc',
            weight = tonumber(item.weight) or 0,
            stack = item.stack ~= false,
            usable = item.usable == true,
            inventory = item.inventory ~= false,
            virtual = item.virtual == true,
            image = imageUrlForItem(item.image or item.icon),
            description = item.description or '',
            equipmentSlot = item.equipmentSlot or item.equipSlot or '',
            worldModel = CMItems.GetItemWorldModel and CMItems.GetItemWorldModel(name) or item.worldModel or '',
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

RegisterNUICallback('previewGiveItem', function(data, cb)
    previewRequestId = previewRequestId + 1
    local requestId = tostring(previewRequestId)
    previewCallbacks[requestId] = cb
    TriggerServerEvent('cm-items:server:previewGiveItem', requestId, data or {})
end)

RegisterNetEvent('cm-items:client:previewGiveResult', function(requestId, success, message, itemName)
    local cb = previewCallbacks[tostring(requestId)]
    previewCallbacks[tostring(requestId)] = nil
    if cb then
        cb({ success = success == true, message = message, itemName = itemName })
    end

    local text = success and ('Added %s to inventory'):format(tostring(itemName or 'item')) or tostring(message or 'Could not add item')
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
