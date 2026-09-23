--[[ Load the required file based to the framework ]]

local version = IsDuplicityVersion() and "server" or "client"

local success, result = pcall(lib.load, ("modules.bridge.%s.%s"):format(shared.framework, version))

if not success then
    lib.print.error(result)
end
