--[[ All helper functions and variables are defined here ]]

---@alias FrameworkType "esx"|"qb"|"qbx"

---Loads the ox_lib locale module
lib.locale()

shared = {}
shared.resource = GetCurrentResourceName()

---Checks if the given resource is started.
---@param resourceName string
---@return boolean
function shared.isResourceStart(resourceName)
    return GetResourceState(resourceName) == "started"
end

---Returns the name of the active framework ("qb", "esx", "qbx").
---@return FrameworkType|nil
function shared.getFrameworkName()
    if shared.isResourceStart("es_extended") then
        return "esx"
    elseif shared.isResourceStart("qbx_core") then
        return "qbx"
    elseif shared.isResourceStart("qb-core") then
        return "qb"
    end
    return nil
end

---Retrieves the core object of the active framework.
---@return table|nil
function shared.getFrameworkObject()
    local frameworkName = shared.getFrameworkName()
    if not frameworkName then return nil end
    if frameworkName == "esx" then
        return exports["es_extended"]:getSharedObject()
    elseif frameworkName == "qbx" then
        return nil
    elseif frameworkName == "qb" then
        return exports["qb-core"]:GetCoreObject()
    end
end

---Formats and returns a string combining the script name and event.
---Created for the convenience of the developer.
---@param event string
---@return string
function _e(event)
    return ("%s:%s"):format(shared.resource, event)
end

function shared.debug(title, ...)
    if not Config.debug then return end
    local date = IsDuplicityVersion() and os.date("%Y-%m-%d %H:%M:%S") or GetGameTimer()

    local args = { ... }
    local printType = "info" -- default print type
    local content = args

    -- Check if last argument is a valid print type
    if #args > 0 then
        local lastArg = args[#args]
        if type(lastArg) == "string" and (lastArg == "info" or lastArg == "warn" or lastArg == "error") then
            printType = lastArg
            content = { table.unpack(args, 1, #args - 1) } -- Remove last argument from content
        end
    end

    lib.print[printType](("^2-----[DEBUG - %s ]-----"):format(date))
    lib.print[printType](("^2-----[%s]-----"):format(title))
    if #content > 0 then
        lib.print[printType](content)
    end
    lib.print[printType]("^2-----[ END DEBUG ]-----\n")
end

shared.framework = shared.getFrameworkName()

-- 0r_lib

if IsDuplicityVersion() then
    Resmon = exports["0r_lib"]:GetCoreObject()
end
