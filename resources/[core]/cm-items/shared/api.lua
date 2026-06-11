CMItems = CMItems or {}

local function normalizeName(name)
    if type(name) ~= 'string' then return nil end
    name = name:lower():gsub('%s+', '_')
    name = name:gsub('[^a-z0-9_%-%.]', '')
    return name ~= '' and name or nil
end

local function copyTable(value)
    if type(value) ~= 'table' then return value end
    local copied = {}
    for k, v in pairs(value) do
        copied[k] = copyTable(v)
    end
    return copied
end

local function applyDefaults(name, item, virtual)
    if type(item) ~= 'table' then return nil end
    local defaults = CMItems.Config and CMItems.Config.Defaults or {}
    local output = copyTable(defaults)

    for k, v in pairs(item) do
        output[k] = v
    end

    output.name = name
    output.label = output.label or name
    output.category = output.category or 'misc'
    output.image = output.image or 'default.png'
    output.weight = tonumber(output.weight) or 0
    output.stack = output.stack == true
    output.unique = output.unique == true
    output.usable = output.usable == true
    output.close = output.close ~= false
    output.virtual = virtual == true or output.virtual == true
    output.inventory = output.virtual and false or output.inventory ~= false

    if output.unique then
        output.stack = false
    end

    return output
end

function CMItems.NormalizeName(name)
    return normalizeName(name)
end

function CMItems.GetItem(name, includeVirtual)
    name = normalizeName(name)
    if not name then return nil end

    local item = CMItems.Items and CMItems.Items[name]
    if item then return applyDefaults(name, item, false), 'physical' end

    if includeVirtual ~= false then
        local virtual = CMItems.VirtualItems and CMItems.VirtualItems[name]
        if virtual then return applyDefaults(name, virtual, true), 'virtual' end
    end

    return nil
end

function CMItems.GetPhysicalItem(name)
    name = normalizeName(name)
    if not name or not CMItems.Items then return nil end
    local item = CMItems.Items[name]
    if not item then return nil end
    return applyDefaults(name, item, false)
end

function CMItems.GetVirtualItem(name)
    name = normalizeName(name)
    if not name or not CMItems.VirtualItems then return nil end
    local item = CMItems.VirtualItems[name]
    if not item then return nil end
    return applyDefaults(name, item, true)
end

function CMItems.Exists(name, includeVirtual)
    return CMItems.GetItem(name, includeVirtual) ~= nil
end

function CMItems.IsInventoryItem(name)
    local item = CMItems.GetPhysicalItem(name)
    return item ~= nil and item.inventory ~= false and item.virtual ~= true
end

function CMItems.IsVirtualItem(name)
    return CMItems.GetVirtualItem(name) ~= nil
end

function CMItems.GetAllItems()
    local out = {}
    for name, data in pairs(CMItems.Items or {}) do
        out[name] = applyDefaults(name, data, false)
    end
    return out
end

function CMItems.GetInventoryItems()
    local out = {}
    for name, data in pairs(CMItems.Items or {}) do
        local item = applyDefaults(name, data, false)
        if item.inventory ~= false and item.virtual ~= true then
            out[name] = item
        end
    end
    return out
end

function CMItems.GetVirtualItems()
    local out = {}
    for name, data in pairs(CMItems.VirtualItems or {}) do
        out[name] = applyDefaults(name, data, true)
    end
    return out
end

function CMItems.GetItemsByCategory(category, includeVirtual)
    local out = {}
    if type(category) ~= 'string' then return out end
    category = category:lower()

    for name, data in pairs(CMItems.Items or {}) do
        local item = applyDefaults(name, data, false)
        if item.category == category then out[name] = item end
    end

    if includeVirtual then
        for name, data in pairs(CMItems.VirtualItems or {}) do
            local item = applyDefaults(name, data, true)
            if item.category == category then out[name] = item end
        end
    end

    return out
end

function CMItems.GetWeight(name, amount)
    local item = CMItems.GetPhysicalItem(name)
    if not item then return 0 end
    amount = tonumber(amount) or 1
    if amount < 1 then amount = 1 end
    return item.weight * amount
end

function CMItems.CanStack(name)
    local item = CMItems.GetPhysicalItem(name)
    return item ~= nil and item.stack == true and item.unique ~= true
end

function CMItems.RequiresMetadata(name)
    local item = CMItems.GetItem(name, true)
    if not item or type(item.metadataRequired) ~= 'table' then return false, {} end
    return #item.metadataRequired > 0, item.metadataRequired
end

function CMItems.ValidateMetadata(name, metadata)
    local required, fields = CMItems.RequiresMetadata(name)
    if not required then return true end
    if type(metadata) ~= 'table' then return false, ('Missing metadata for %s'):format(name) end

    for _, field in ipairs(fields) do
        if metadata[field] == nil or metadata[field] == '' then
            return false, ('Missing metadata field: %s'):format(field)
        end
    end

    return true
end

function CMItems.RegisterItem(name, data)
    name = normalizeName(name)
    if not name or type(data) ~= 'table' then return false, 'Invalid item data' end
    if CMItems.VirtualItems and CMItems.VirtualItems[name] then return false, 'Name already used by virtual item' end
    CMItems.Items = CMItems.Items or {}
    CMItems.Items[name] = data
    return true, name
end

function CMItems.RegisterVirtualItem(name, data)
    name = normalizeName(name)
    if not name or type(data) ~= 'table' then return false, 'Invalid virtual item data' end
    if CMItems.Items and CMItems.Items[name] then return false, 'Name already used by physical item' end
    CMItems.VirtualItems = CMItems.VirtualItems or {}
    data.inventory = false
    data.virtual = true
    CMItems.VirtualItems[name] = data
    return true, name
end
