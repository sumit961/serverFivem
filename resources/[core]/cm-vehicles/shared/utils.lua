CMVehicles = CMVehicles or {}
CMVehicles.Utils = CMVehicles.Utils or {}
local U = CMVehicles.Utils

function U.Debug(...)
    if CMVehicles.Config and CMVehicles.Config.Debug then print('[CM-VEHICLES]', ...) end
end

function U.NormalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

function U.Truthy(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local s = tostring(value):lower()
    return s == 'true' or s == 'yes' or s == 'on'
end

function U.Encode(v)
    local ok, out = pcall(json.encode, v or {})
    return ok and out or '{}'
end

function U.Decode(v)
    if type(v) == 'table' then return v end
    if not v or v == '' then return {} end
    local ok, out = pcall(json.decode, v)
    return ok and type(out) == 'table' and out or {}
end

function U.ClampHealth(v)
    v = tonumber(v) or 0.0
    if v < 0.0 then return 0.0 end
    if v > 1000.0 then return 1000.0 end
    return v
end

function U.Notify(src, msg, typeName)
    TriggerClientEvent('cm-vehicles:client:notify', src, msg or '', typeName or 'info')
end

function U.CallExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    print(('[CM-VEHICLES] Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end
