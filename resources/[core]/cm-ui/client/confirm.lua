-- Shared FiveM Lua confirmation bridge (v2.0.1).
--
-- SCOPE: WORLD-SCRIPT CONFIRMATION ONLY
-- This export is designed for gameplay scripts (such as world interactions,
-- G-menus, or job prompts) where NO parent NUI interface is currently open.
--
-- For existing in-NUI interfaces (e.g. House, Family, Bank, or any resource
-- with an open NUI window):
-- DO NOT call this Lua bridge. Use the in-page JavaScript helper:
--     const confirmed = await CMUI.confirm({ ... });
-- Calling the Lua bridge while another NUI is focused can conflict with parent
-- focus ownership.

local confirmPromise = nil
local focusOwnedByConfirm = false
local invokingResource = nil

local function ReleaseConfirmFocus()
    if focusOwnedByConfirm then
        focusOwnedByConfirm = false
        SetNuiFocus(false, false)
    end
end

local function CMConfirm(options)
    if confirmPromise then
        -- Fail-safe: do not allow concurrent world confirmations to fight for focus
        return false
    end

    options = type(options) == 'table' and options or {}

    -- Track focus ownership: only acquire and release focus if NUI was not already focused
    local hadFocus = false
    if IsNuiFocused and type(IsNuiFocused) == 'function' then
        pcall(function()
            hadFocus = IsNuiFocused() == 1 or IsNuiFocused() == true
        end)
    end

    invokingResource = GetInvokingResource()
    confirmPromise = promise.new()

    if not hadFocus then
        focusOwnedByConfirm = true
        SetNuiFocus(true, true)
    else
        focusOwnedByConfirm = false
    end

    SendNUIMessage({
        action = 'cmConfirm:show',
        title = options.title or options.header or 'CONFIRM ACTION',
        message = options.message or options.content or 'Are you sure you want to proceed?',
        confirmText = options.confirmText or (options.labels and options.labels.confirm) or 'CONFIRM',
        cancelText = options.cancelText or (options.labels and options.labels.cancel) or 'CANCEL',
        danger = options.danger == true or options.destructive == true or (options.tone == 'danger'),
        dismissOnBackdrop = options.dismissOnBackdrop ~= false
    })

    local result = Citizen.Await(confirmPromise)
    confirmPromise = nil
    invokingResource = nil
    ReleaseConfirmFocus()
    return result
end

RegisterNUICallback('cmConfirm:result', function(data, cb)
    local result = data and data.result == true
    cb({ ok = true })
    if confirmPromise then
        local p = confirmPromise
        confirmPromise = nil
        invokingResource = nil
        p:resolve(result)
    end
    ReleaseConfirmFocus()
end)

-- Safe cleanup on resource stop: never leave hanging promise, stuck focus, or active cursor
AddEventHandler('onResourceStop', function(resourceName)
    local currentRes = GetCurrentResourceName()
    if resourceName == currentRes or (invokingResource and resourceName == invokingResource) then
        if confirmPromise then
            SendNUIMessage({ action = 'cmConfirm:cancel' })
            local p = confirmPromise
            confirmPromise = nil
            invokingResource = nil
            p:resolve(false)
        end
        ReleaseConfirmFocus()
    end
end)

exports('Confirm', CMConfirm)
_G.CMConfirm = CMConfirm
