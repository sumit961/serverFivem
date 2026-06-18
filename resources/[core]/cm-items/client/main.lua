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
    print('[CM-ITEMS] Clothing catalog synced to client')
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
