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
--           { id = 'open', label = 'Open Editor', type = 'command', command = 'houseadmin' },
--           { id = 'reload', label = 'Reload Configs', type = 'server_event', event = 'housing:server:reload' },
--           { id = 'goto', label = 'Teleport To House', type = 'form', event = 'housing:server:gotoHouse',
--             fields = { { id = 'houseId', label = 'House ID', type = 'number', required = true } } }
--       }
--   })
--
-- Tools are removed automatically when their owning resource stops.
-- Action types:
--   command      -> runs a chat command AS the admin (works for client & server commands)
--   client_event -> TriggerEvent on the admin's client
--   server_event -> TriggerEvent on the server (src, values)
--   form         -> renders input fields, then fires `event` server-side with (src, values)

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
        if t ~= 'command' and t ~= 'client_event' and t ~= 'server_event' and t ~= 'form' then
            return false, ('unknown action type %s'):format(tostring(t))
        end
        if t == 'command' and type(a.command) ~= 'string' then return false, 'command actions need .command' end
        if (t == 'client_event' or t == 'server_event' or t == 'form') and type(a.event) ~= 'string' then
            return false, 'event actions need .event'
        end
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
                    id = a.id, label = a.label, type = a.type,
                    fields = a.fields, hint = a.hint
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

    local values = type(data.values) == 'table' and data.values or {}
    log(src, 'dev_tool', { tool = tool.id, action = action.id, values = values })

    if action.type == 'command' then
        -- Runs on the admin's client so server commands receive the real src.
        TriggerClientEvent('cm-admin:client:runCommand', src, action.command, values)
    elseif action.type == 'client_event' then
        TriggerClientEvent('cm-admin:client:devClientEvent', src, action.event, values)
    elseif action.type == 'server_event' or action.type == 'form' then
        -- Close the admin menu first so a tool that opens its own NUI panel
        -- (e.g. Climatime) gets a clean focus handoff.
        TriggerClientEvent('cm-admin:client:closeForDevTool', src)
        TriggerEvent(action.event, src, values)
    end
end

-- Built-in registrations for existing stores (configurable in config.lua).
CreateThread(function()
    Wait(1000)
    for _, tool in ipairs(Config.DevToolsBuiltin or {}) do
        registerDevTool(tool)
    end
end)
