-- ============================================================
--  cm-family | cl_menu.lua
--  Bridges the full-screen NUI to the server. Opens the menu, forwards every
--  action to cm-family:server:action, and refreshes the snapshot after a
--  successful mutation.
-- ============================================================

local menuOpen = false

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

local function pushMenu(snapshot)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    snapshot.clientTracking = {
        memberBlipsEnabled = CMFamilyTracking and CMFamilyTracking.IsMemberBlipsEnabled
            and CMFamilyTracking.IsMemberBlipsEnabled() or false,
    }
    SendNUIMessage({ action = 'family:open', data = snapshot })
end

RegisterNetEvent('cm-family:client:openMenu', function(snapshot)
    if not snapshot or not snapshot.ok then return end
    menuOpen = true
    setFocus(true)
    pushMenu(snapshot)
end)

RegisterNetEvent('cm-family:client:openCreate', function()
    local res = lib.callback.await('cm-family:server:getCreationHouses', false)
    menuOpen = true
    setFocus(true)
    SendNUIMessage({ action = 'family:create', data = res })
end)

RegisterNetEvent('cm-family:client:openInvitePrompt', function(invite)
    menuOpen = true
    setFocus(true)
    SendNUIMessage({ action = 'family:invite', data = invite })
end)

local function refresh()
    local menu = lib.callback.await('cm-family:server:getMenu', false)
    if menu and menu.ok then
        pushMenu(menu)
    else
        -- No longer in a family (e.g. left/disbanded): show create screen.
        local res = lib.callback.await('cm-family:server:getCreationHouses', false)
        SendNUIMessage({ action = 'family:create', data = res })
    end
end

-- NUI -> forward an action, return result, then refresh the snapshot.
RegisterNUICallback('action', function(payload, cb)
    payload = payload or {}
    payload.data = type(payload.data) == 'table' and payload.data or {}
    if payload.action == 'setMeetingPoint' then
        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then
            cb({ ok = false, result = 'player_not_ready' })
            return
        end
        local coords = GetEntityCoords(ped)
        payload.data.x = coords.x
        payload.data.y = coords.y
        payload.data.z = coords.z
    end
    local ok, result = lib.callback.await('cm-family:server:action', false, payload.action, payload.data)
    if ok == true and payload.action == 'trackVehicle' and type(result) == 'table' then
        TriggerEvent('cm-family:client:trackVehicleResult', result)
    end
    cb({ ok = ok == true, result = result })
    if ok == true then refresh() end
end)

RegisterNUICallback('createFamily', function(payload, cb)
    local ok, result = lib.callback.await('cm-family:server:createFamily', false, payload or {})
    cb({ ok = ok == true, result = result })
    if ok == true then refresh() end
end)

RegisterNUICallback('setMemberTracking', function(payload, cb)
    local enabled = type(payload) == 'table' and payload.enabled == true
    local applied = CMFamilyTracking and CMFamilyTracking.SetMemberBlipsEnabled
        and CMFamilyTracking.SetMemberBlipsEnabled(enabled) or false
    cb({ ok = true, enabled = applied == true })
end)

RegisterNUICallback('refresh', function(_, cb)
    refresh()
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    menuOpen = false
    setFocus(false)
    SendNUIMessage({ action = 'family:close' })
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if menuOpen then setFocus(false) end
end)
