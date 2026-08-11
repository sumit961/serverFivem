-- cm-admin/server/devtools.lua
-- v2.6 Developer tools plugin system.
--
-- THE POINT: cm-admin is never edited again for new tools. Any resource
-- self-registers at startup:
--
--   exports['cm-admin']:RegisterDevTool({
--       id = 'housing',
--       label = 'Housing Editor',
--       category = 'World',
--       permission = 'dev.housing',       -- optional, default 'dev.tools'
--       actions = {
--           { id = 'open', label = 'Open Editor', type = 'launcher',
--             realm = 'server', event = 'housing:dev:open' }
--       }
--   })
--
-- Tools are removed automatically when their owning resource stops.
-- Developer entries are launchers only. They may open a resource-owned panel
-- through a local server event or a client event, but cannot run commands,
-- submit forms, or perform business actions from cm-admin itself.

CMDevTools = {}

local tools = {}        -- [id] = tool
local toolOwner = {}    -- [id] = resource name

local function log(src, action, data)
    local name = src and src > 0 and GetPlayerName(src) or 'system'
    if Config.QuietConsoleLogs ~= true then
        print(('[CM-ADMIN:DEV] %s (%s) -> %s %s'):format(name, src or 0, action, data and json.encode(data) or ''))
    end
    data = type(data) == 'table' and data or {}
    data.category = data.category or 'dev'
    TriggerEvent('cm-admin:server:addLog', src or 0, action, data)
end

local function hasPerm(src, permission)
    local ok, allowed = pcall(function()
        return exports['cm-admin']:HasPermission(src, permission)
    end)
    return ok and allowed == true
end

local function validateTool(tool)
    if type(tool) ~= 'table' then return false, 'tool must be a table' end
    if type(tool.id) ~= 'string' or tool.id == '' then return false, 'tool.id required' end
    if type(tool.label) ~= 'string' or tool.label == '' then return false, 'tool.label required' end
    if type(tool.actions) ~= 'table' or #tool.actions == 0 then return false, 'tool.actions required' end
    for _, a in ipairs(tool.actions) do
        if type(a.id) ~= 'string' or type(a.label) ~= 'string' then return false, 'action id/label required' end
        local t = a.type
        if t ~= 'launcher' then return false, 'developer actions must be launchers' end
        if a.realm ~= 'client' and a.realm ~= 'server' then return false, 'launcher realm must be client or server' end
        if type(a.event) ~= 'string' or a.event == '' then return false, 'launcher actions need .event' end
    end
    return true
end

local function registerDevTool(tool)
    local ok, err = validateTool(tool)
    if not ok then
        if Config.QuietConsoleLogs ~= true then print(('[CM-ADMIN:DEV] Rejected tool registration: %s'):format(err)) end
        return false
    end

    tool.category = tool.category or 'Tools'
    tool.permission = tool.permission or 'dev.tools'
    tools[tool.id] = tool
    toolOwner[tool.id] = GetInvokingResource() or GetCurrentResourceName()
    if Config.QuietConsoleLogs ~= true then print(('[CM-ADMIN:DEV] Registered dev tool "%s" (%s) from %s'):format(tool.label, tool.id, toolOwner[tool.id])) end
    return true
end

local function unregisterDevTool(id)
    tools[id] = nil
    toolOwner[id] = nil
end

exports('RegisterDevTool', registerDevTool)
exports('UnregisterDevTool', unregisterDevTool)

-- Tools vanish with their resource: no stale buttons, no admin edits.
AddEventHandler('onResourceStop', function(resourceName)
    for id, owner in pairs(toolOwner) do
        if owner == resourceName then
            unregisterDevTool(id)
        end
    end
end)

-- Menu payload: only the tools/actions this admin is allowed to see.
function CMDevTools.forPlayer(src)
    if not hasPerm(src, 'dev.view') then return nil end

    local out = {}
    for _, tool in pairs(tools) do
        if hasPerm(src, tool.permission) then
            local actions = {}
            for _, a in ipairs(tool.actions) do
                actions[#actions + 1] = {
                    id = a.id, label = a.label, type = a.type, hint = a.hint
                }
            end
            out[#out + 1] = {
                id = tool.id, label = tool.label,
                category = tool.category, icon = tool.icon,
                actions = actions
            }
        end
    end

    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.label < b.label
    end)
    return out
end

function CMDevTools.invoke(src, data)
    if type(data) ~= 'table' then return end
    local tool = tools[tostring(data.tool or '')]
    if not tool then return end
    if not hasPerm(src, 'dev.view') or not hasPerm(src, tool.permission) then
        log(src, 'dev_denied', { tool = data.tool })
        return
    end

    local action = nil
    for _, a in ipairs(tool.actions) do
        if a.id == data.actionId then action = a break end
    end
    if not action then return end

    log(src, 'dev_launcher_open', { tool = tool.id, launcher = action.id })
    TriggerClientEvent('cm-admin:client:closeForDevTool', src)
    if action.realm == 'client' then
        TriggerClientEvent(action.event, src)
    else
        TriggerEvent(action.event, src)
    end
end

-- Optional built-in launchers. Current CM resources self-register their own
-- panels so authorization and lifecycle ownership stay with each resource.
CreateThread(function()
    Wait(1000)
    for _, tool in ipairs(Config.DevToolsBuiltin or {}) do
        registerDevTool(tool)
    end
end)
