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
