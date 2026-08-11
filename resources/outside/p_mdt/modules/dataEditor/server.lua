DataEditor = {}

function DataEditor.compareKeys(left, right)
    if type(left) == type(right) then
        return tostring(left) < tostring(right)
    end
    return type(left) < type(right)
end

function DataEditor.formatKey(key)
    if type(key) == "number" then
        return ("[%s]"):format(key)
    end

    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
        return key
    end

    return ('["%s"]'):format(tostring(key))
end

function DataEditor.formatValue(value, indent)
    if type(value) == "table" then
        return DataEditor:serializeTable(value, indent)
    end

    if type(value) == "string" then
        local escaped = value
            :gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\n", "\\n")
        return ('"%s"'):format(escaped)
    end

    if type(value) == "boolean" then
        return value and "true" or "false"
    end

    return tostring(value)
end

function DataEditor.serializeTable(self, tbl, indent)
    indent = indent or ""
    local nextIndent = indent .. "    "
    local lines = { "{\n" }
    local keys = {}

    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end

    table.sort(keys, DataEditor.compareKeys)

    for index, key in ipairs(keys) do
        local line = nextIndent
            .. DataEditor.formatKey(key)
            .. " = "
            .. DataEditor.formatValue(tbl[key], nextIndent)

        if index < #keys then
            line = line .. ","
        end

        lines[#lines + 1] = line .. "\n"
    end

    lines[#lines + 1] = indent .. "}"
    return table.concat(lines)
end

RegisterNetEvent("p_mdt/server/dataEditor/save", function(data)
    local source = source
    local job = Bridge.Framework.getPlayerJob(source)

    if data.Vehicles then
        local vehiclesData = lib.load("data.vehicles") or {}
        vehiclesData[job.name] = data.Vehicles

        SaveResourceFile(
            GetCurrentResourceName(),
            "data/vehicles.lua",
            "return " .. DataEditor:serializeTable(vehiclesData),
            -1
        )
    end

    if data.Garages then
        local garagesData = lib.load("data.garages") or {}
        garagesData[job.name] = data.Garages

        SaveResourceFile(
            GetCurrentResourceName(),
            "data/garages.lua",
            "return " .. DataEditor:serializeTable(garagesData),
            -1
        )
    end
end)
