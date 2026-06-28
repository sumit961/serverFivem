-- cm-inventory server bootloader
-- Keeps all split files inside one Lua chunk so existing local functions/variables
-- keep the same scope as the old single server/main.lua.

local resourceName = GetCurrentResourceName()
local serverFiles = {
    'server/db.lua',
    'server/items.lua',
    'server/slots.lua',
    'server/bags.lua',
    'server/equipment.lua',
    'server/drops.lua',
    'server/events.lua',
    'server/exports.lua'
}

local combined = {}
for _, fileName in ipairs(serverFiles) do
    local content = LoadResourceFile(resourceName, fileName)
    if not content then
        error(('[CM-INVENTORY] Missing server module: %s'):format(fileName))
    end
    combined[#combined + 1] = ('\n-- >>> %s\n'):format(fileName)
    combined[#combined + 1] = content
    combined[#combined + 1] = ('\n-- <<< %s\n'):format(fileName)
end

local chunk, err = load(table.concat(combined), '@cm-inventory/server/combined.lua', 't', _ENV)
if not chunk then
    error(('[CM-INVENTORY] Failed to compile split server modules: %s'):format(err))
end

chunk()
