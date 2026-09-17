-- Family-side CM UI bridge. ox_lib remains available only for callbacks.
local pending = {}
local contexts = {}
local sequence = 0

function CMFamilyNotify(payload, kind)
    local message = payload
    if type(payload) == 'table' then
        message = payload.description or payload.title or ''
        kind = payload.type or kind
    end
    message = tostring(message or '')
    kind = kind or 'inform'
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', message, kind)
    else
        TriggerEvent('chat:addMessage', { args = { 'Family', message } })
    end
end

local function awaitUi(mode, title, content)
    sequence = sequence + 1
    local id = ('family:%d'):format(sequence)
    local wait = promise.new()
    pending[id] = wait
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'uiBridge:open', mode = mode, id = id, title = title, content = content })
    return Citizen.Await(wait)
end

function CMFamilyAlert(options)
    options = options or {}
    return awaitUi('alert', options.header or 'Please confirm', {
        message = options.content or '',
        confirm = options.labels and options.labels.confirm or 'Confirm',
        cancel = options.labels and options.labels.cancel or 'Cancel',
        danger = options.danger == true,
    })
end

function CMFamilyRegisterContext(context)
    if type(context) == 'table' and context.id then contexts[context.id] = context end
end

function CMFamilyShowContext(id)
    local context = contexts[id]
    if not context then return end
    local rows = {}
    for index, option in ipairs(context.options or {}) do
        rows[index] = {
            index = index,
            title = option.title or option.label or 'Option',
            description = option.description,
            disabled = option.disabled == true,
            iconColor = option.iconColor,
        }
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'uiBridge:open', mode = 'context', id = tostring(id), title = context.title or 'Family', content = rows })
end

RegisterNUICallback('uiBridge:result', function(data, cb)
    data = data or {}
    local wait = pending[data.id]
    if wait then
        pending[data.id] = nil
        wait:resolve(data.cancelled == true and nil or data.value)
    end
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('uiBridge:contextSelect', function(data, cb)
    local context = contexts[data and data.id]
    local option = context and context.options and context.options[tonumber(data.index)]
    SendNUIMessage({ action = 'uiBridge:close' })
    SetNuiFocus(false, false)
    if option and option.disabled ~= true and type(option.onSelect) == 'function' then
        CreateThread(function() option.onSelect(option.args) end)
    end
    cb({ ok = option ~= nil })
end)

RegisterNUICallback('uiBridge:closed', function(data, cb)
    data = data or {}
    local wait = pending[data.id]
    if wait then pending[data.id] = nil; wait:resolve(nil) end
    SetNuiFocus(false, false)
    cb({ ok = true })
end)
