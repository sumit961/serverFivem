local function isAllowed(src)
    -- v7 dev mode: all players are admins until you enable ACE later.
    if src == 0 then return CMClothingAdmin.Config.AllowConsole == true end
    if CMClothingAdmin.Config.RequireAce == true then
        return IsPlayerAceAllowed(src, CMClothingAdmin.Config.AcePermission or 'cm.clothingadmin')
    end
    return true
end

local function notify(src, msg)
    if src == 0 then
        print('[CM-CLOTHINGADMIN] ' .. tostring(msg))
        return
    end
    TriggerClientEvent('cm-clothingadmin:client:notify', src, msg)
end

local function respond(src, requestId, data)
    if not requestId then return end
    TriggerClientEvent('cm-clothingadmin:client:serverResponse', src, requestId, data or { ok = false, error = 'empty response' })
end

local function normaliseEntry(src, entry)
    if type(entry) ~= 'table' then return nil end
    entry.gender = tostring(entry.gender or 'male'):lower() == 'female' and 'female' or 'male'
    entry.componentType = tostring(entry.componentType or 'component'):lower()
    entry.componentIndex = tonumber(entry.componentIndex)
    entry.drawableId = tonumber(entry.drawableId)
    entry.textureId = tonumber(entry.textureId)
    if entry.textureId == nil then entry.textureId = -1 end
    entry.price = tonumber(entry.price) or 0
    entry.enabled = entry.enabled ~= false
    entry.arms = entry.arms ~= nil and tonumber(entry.arms) or nil
    entry.armsTexture = tonumber(entry.armsTexture) or 0
    entry.undershirt = entry.undershirt ~= nil and tonumber(entry.undershirt) or nil
    entry.undershirtTexture = tonumber(entry.undershirtTexture) or 0
    entry.createdBy = src == 0 and 'console' or GetPlayerName(src)
    entry.updatedBy = entry.createdBy

    if entry.sleeveStyle == '' then entry.sleeveStyle = nil end
    if entry.image == '' then entry.image = nil end
    if entry.job == '' then entry.job = nil end
    if entry.gang == '' then entry.gang = nil end
    if entry.category == '' or entry.category == nil then entry.category = CMClothingAdmin.Config.DefaultCategory or 'uncategorized' end
    if entry.shop == '' or entry.shop == nil then entry.shop = CMClothingAdmin.Config.DefaultShop or 'city' end

    if entry.sleeveStyle == 'full' then
        entry.arms = entry.arms or 6
        entry.armsTexture = entry.armsTexture or 0
    elseif entry.sleeveStyle == 'half' then
        entry.arms = entry.arms or 5
        entry.armsTexture = entry.armsTexture or 0
    end

    if not entry.componentIndex or not entry.drawableId then return nil end
    if entry.label == nil or tostring(entry.label) == '' then
        entry.label = ('Clothing %s/%s'):format(entry.drawableId, entry.textureId)
    end
    return entry
end

local function cmItemsExport(method, ...)
    if GetResourceState('cm-items') ~= 'started' then
        return false, 'cm-items is not started'
    end

    local ok, result, extra = pcall(function(...)
        return exports['cm-items'][method](...)
    end, ...)
    if ok then return result, extra end

    ok, result, extra = pcall(function(...)
        return exports['cm-items'][method](exports['cm-items'], ...)
    end, ...)
    if ok then return result, extra end

    return false, tostring(result)
end

local function saveEntry(src, entry)
    entry = normaliseEntry(src, entry)
    if not entry then return false, 'Invalid clothing catalog entry.' end

    local result, err = cmItemsExport('SaveClothingCatalogEntry', entry)
    if result ~= true then
        return false, tostring(err or result)
    end
    return true, entry
end

local function deleteEntry(entryOrGender, componentType, componentIndex, drawableId, textureId)
    local gender
    if type(entryOrGender) == 'table' then
        gender = entryOrGender.gender
        componentType = entryOrGender.componentType or 'component'
        componentIndex = entryOrGender.componentIndex
        drawableId = entryOrGender.drawableId
        textureId = entryOrGender.textureId
    else
        gender = entryOrGender
    end

    local result, err = cmItemsExport('DeleteClothingCatalogEntry', gender, componentType or 'component', componentIndex, drawableId, textureId or -1)
    if result ~= true then
        return false, tostring(err or result)
    end
    return true
end

--========================================================
-- NUI request handlers
--========================================================

RegisterNetEvent('cm-clothingadmin:server:nuiGetCatalogItems', function(requestId)
    local src = source
    if not isAllowed(src) then respond(src, requestId, { ok = false, error = 'not allowed' }) return end
    local rows, err = cmItemsExport('GetClothingCatalogRows')
    if type(rows) ~= 'table' then
        respond(src, requestId, { ok = false, error = tostring(err or 'could not load catalog rows') })
        return
    end
    respond(src, requestId, { ok = true, items = rows })
end)

RegisterNetEvent('cm-clothingadmin:server:nuiSaveEntry', function(requestId, payload)
    local src = source
    if not isAllowed(src) then respond(src, requestId, { ok = false, error = 'not allowed' }) return end
    local ok, entryOrErr = saveEntry(src, payload and payload.entry)
    if not ok then respond(src, requestId, { ok = false, error = entryOrErr }) return end
    notify(src, ('Saved %s drawable %s texture %s as "%s".'):format(entryOrErr.gender, entryOrErr.drawableId, entryOrErr.textureId, entryOrErr.label))
    respond(src, requestId, { ok = true, entry = entryOrErr })
end)

RegisterNetEvent('cm-clothingadmin:server:nuiDeleteEntry', function(requestId, payload)
    local src = source
    if not isAllowed(src) then respond(src, requestId, { ok = false, error = 'not allowed' }) return end
    local ok, err = deleteEntry(payload and payload.entry)
    if not ok then respond(src, requestId, { ok = false, error = err }) return end
    notify(src, 'Deleted clothing catalog entry.')
    respond(src, requestId, { ok = true })
end)

RegisterNetEvent('cm-clothingadmin:server:nuiReloadCatalog', function(requestId)
    local src = source
    if not isAllowed(src) then respond(src, requestId, { ok = false, error = 'not allowed' }) return end
    local result, count = cmItemsExport('ReloadClothingCatalog')
    if result ~= true then respond(src, requestId, { ok = false, error = tostring(count or result) }) return end
    notify(src, ('Reloaded clothing catalog. Rows: %s'):format(tostring(count or '?')))
    respond(src, requestId, { ok = true, count = count })
end)

--========================================================
-- Legacy command handlers
--========================================================

RegisterNetEvent('cm-clothingadmin:server:saveEntry', function(entry)
    local src = source
    if not isAllowed(src) then notify(src, 'You are not allowed to use clothing admin.') return end
    local ok, savedOrErr = saveEntry(src, entry)
    if not ok then notify(src, 'Save failed: ' .. tostring(savedOrErr)) return end
    notify(src, ('Saved %s drawable %s texture %s as "%s".'):format(savedOrErr.gender, savedOrErr.drawableId, savedOrErr.textureId, savedOrErr.label))
end)

RegisterNetEvent('cm-clothingadmin:server:deleteEntry', function(gender, componentType, componentIndex, drawableId, textureId)
    local src = source
    if not isAllowed(src) then notify(src, 'You are not allowed to use clothing admin.') return end
    local ok, err = deleteEntry(gender, componentType or 'component', componentIndex, drawableId, textureId or -1)
    if not ok then notify(src, 'Delete failed: ' .. tostring(err)) return end
    notify(src, 'Deleted clothing catalog entry.')
end)

RegisterNetEvent('cm-clothingadmin:server:reloadCatalog', function()
    local src = source
    if not isAllowed(src) then notify(src, 'You are not allowed to use clothing admin.') return end
    local result, count = cmItemsExport('ReloadClothingCatalog')
    if result ~= true then notify(src, 'Reload failed: ' .. tostring(count or result)) return end
    notify(src, ('Reloaded clothing catalog. Rows: %s'):format(tostring(count or '?')))
end)

RegisterCommand('cmclothreloadserver', function(src)
    if not isAllowed(src) then notify(src, 'Not allowed.') return end
    local result, count = cmItemsExport('ReloadClothingCatalog')
    notify(src, result == true and ('Reloaded clothing catalog. Rows: ' .. tostring(count or '?')) or ('Reload failed: ' .. tostring(count or result)))
end, true)
