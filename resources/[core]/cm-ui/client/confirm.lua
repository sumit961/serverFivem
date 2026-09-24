-- Shared FiveM Lua confirmation bridge.
-- Routes confirmation requests to cm-ui's persistent NUI overlay so gameplay scripts
-- can present authoritative CM confirmations without implementing separate NUI modals.
--
-- Usage:
-- local confirmed = exports['cm-ui']:Confirm({
--     title = 'REMOVE VEHICLE?',
--     message = 'This will remove the vehicle from the parking slot.',
--     confirmText = 'REMOVE',
--     cancelText = 'CANCEL',
--     danger = true
-- })

local confirmPromise = nil

local function CMConfirm(options)
    if confirmPromise then
        -- Another confirmation is currently awaiting resolution
        return false
    end

    options = type(options) == 'table' and options or {}

    confirmPromise = promise.new()
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'cmConfirm:show',
        title = options.title or options.header or 'CONFIRM ACTION',
        message = options.message or options.content or 'Are you sure you want to proceed?',
        confirmText = options.confirmText or (options.labels and options.labels.confirm) or 'CONFIRM',
        cancelText = options.cancelText or (options.labels and options.labels.cancel) or 'CANCEL',
        danger = options.danger == true or options.destructive == true or (options.tone == 'danger')
    })

    local result = Citizen.Await(confirmPromise)
    confirmPromise = nil
    SetNuiFocus(false, false)
    return result
end

RegisterNUICallback('cmConfirm:result', function(data, cb)
    local result = data and data.result == true
    cb({ ok = true })
    if confirmPromise then
        confirmPromise:resolve(result)
    end
end)

exports('Confirm', CMConfirm)
_G.CMConfirm = CMConfirm
