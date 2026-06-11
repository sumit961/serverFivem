local function log(message)
    print(('[CM-ITEMS] %s'):format(message))
end

local function normalizeExportArgs(...)
    local args = { ... }

    -- FiveM Lua exports can be called as either:
    -- exports['cm-items'].IsInventoryItem('water')
    -- exports['cm-items']:IsInventoryItem('water')
    -- In some runtimes, colon-style passes the exports table as arg #1.
    -- This removes that extra table so the real first argument is always the item name.
    if type(args[1]) == 'table' then
        table.remove(args, 1)
    end

    return args
end

local function exportSafe(fn)
    return function(...)
        local args = normalizeExportArgs(...)
        local ok, result, extra = pcall(function()
            return fn(table.unpack(args))
        end)

        if not ok then
            log(('Export error: %s'):format(tostring(result)))
            return nil
        end

        return result, extra
    end
end

CreateThread(function()
    Wait(500)
    local physicalCount = 0
    local virtualCount = 0

    for _ in pairs(CMItems.Items or {}) do physicalCount += 1 end
    for _ in pairs(CMItems.VirtualItems or {}) do virtualCount += 1 end

    log(('Started v1.1-export-fix | physical items: %s | virtual items: %s'):format(physicalCount, virtualCount))
end)

exports('GetItem', exportSafe(function(name, includeVirtual)
    return CMItems.GetItem(name, includeVirtual)
end))

exports('GetPhysicalItem', exportSafe(function(name)
    return CMItems.GetPhysicalItem(name)
end))

exports('GetVirtualItem', exportSafe(function(name)
    return CMItems.GetVirtualItem(name)
end))

exports('Exists', exportSafe(function(name, includeVirtual)
    return CMItems.Exists(name, includeVirtual)
end))

exports('IsInventoryItem', exportSafe(function(name)
    return CMItems.IsInventoryItem(name)
end))

exports('IsVirtualItem', exportSafe(function(name)
    return CMItems.IsVirtualItem(name)
end))

exports('GetAllItems', exportSafe(function()
    return CMItems.GetAllItems()
end))

exports('GetInventoryItems', exportSafe(function()
    return CMItems.GetInventoryItems()
end))

exports('GetVirtualItems', exportSafe(function()
    return CMItems.GetVirtualItems()
end))

exports('GetItemsByCategory', exportSafe(function(category, includeVirtual)
    return CMItems.GetItemsByCategory(category, includeVirtual)
end))

exports('GetWeight', exportSafe(function(name, amount)
    return CMItems.GetWeight(name, amount)
end))

exports('CanStack', exportSafe(function(name)
    return CMItems.CanStack(name)
end))

exports('ValidateMetadata', exportSafe(function(name, metadata)
    return CMItems.ValidateMetadata(name, metadata)
end))

exports('RegisterItem', exportSafe(function(name, data)
    return CMItems.RegisterItem(name, data)
end))

exports('RegisterVirtualItem', exportSafe(function(name, data)
    return CMItems.RegisterVirtualItem(name, data)
end))

RegisterCommand('cmitem', function(src, args)
    if src ~= 0 then return end

    local name = args[1]
    if not name then
        log('Usage: cmitem <item_name>')
        return
    end

    local item, kind = CMItems.GetItem(name, true)
    if not item then
        log(('Item not found: %s'):format(name))
        return
    end

    log(('Item %s [%s] label=%s inventory=%s virtual=%s weight=%s'):format(
        item.name,
        kind,
        item.label,
        tostring(item.inventory),
        tostring(item.virtual),
        tostring(item.weight)
    ))
end, true)
