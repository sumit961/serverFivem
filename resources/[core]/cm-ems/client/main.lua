local open = false
local adminMode = false

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS', description = message, type = kind or 'inform' }) end
end

local function captureOutfit()
    local ped = PlayerPedId()
    local outfit = { components = {}, props = {} }
    for index = 0, 11 do outfit.components[tostring(index)] = { drawable = GetPedDrawableVariation(ped, index), texture = GetPedTextureVariation(ped, index), palette = GetPedPaletteVariation(ped, index) } end
    for index = 0, 7 do outfit.props[tostring(index)] = { drawable = GetPedPropIndex(ped, index), texture = GetPedPropTextureIndex(ped, index) } end
    return outfit
end

-- Bare global: client/wardrobe.lua's wardrobe-NPC menu also needs this,
-- to apply a favorite outfit the moment it's worn there.
function applyOutfit(outfit)
    if type(outfit) ~= 'table' then return end
    local ped = PlayerPedId()
    for key, value in pairs(outfit.components or {}) do
        local index = tonumber(key)
        if index and type(value) == 'table' then SetPedComponentVariation(ped, index, tonumber(value.drawable) or 0, tonumber(value.texture) or 0, tonumber(value.palette) or 0) end
    end
    for key, value in pairs(outfit.props or {}) do
        local index = tonumber(key)
        if index and type(value) == 'table' then
            local drawable = tonumber(value.drawable) or -1
            if drawable < 0 then ClearPedProp(ped, index) else SetPedPropIndex(ped, index, drawable, tonumber(value.texture) or 0, true) end
        end
    end
end

local function sex()
    return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male'
end

local function closeMenu()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

AddEventHandler('cm-ems:client:closeMenu', closeMenu)

local function loadDashboard(initialPage, options)
    local data, reason = lib.callback.await('cm-ems:server:dashboard', false, adminMode, sex())
    if not data then notify(reason or 'Unable to open EMS.', 'error'); return false end
    SendNUIMessage({ action = 'open', data = data, initialPage = initialPage,
        fleetStandalone = options and options.fleetStandalone == true })
    return true
end

RegisterNetEvent('cm-ems:client:open', function(asAdmin)
    adminMode = asAdmin == true
    if not loadDashboard() then return end
    open = true
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cm-ems:client:openFleet', function()
    adminMode = false
    if not loadDashboard('fleet', { fleetStandalone = true }) then return end
    open = true
    SetNuiFocus(true, true)
end)

RegisterCommand(Config.MenuCommand, function()
    TriggerEvent('cm-ems:client:openQuickMenu')
end, false)

RegisterNetEvent('cm-ems:client:openDashboard', function()
    if open then return closeMenu() end
    TriggerEvent('cm-ems:client:open', false)
end)

RegisterNetEvent('cm-ems:client:openMedicalRecords', function()
    if type(LocalPlayer.state.cmEms) ~= 'table' then return end
    adminMode = false
    if not loadDashboard('medical') then return end
    open = true
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cm-ems:client:openQuickMenu', function()
    local state = LocalPlayer.state.cmEms
    if type(state) ~= 'table' then return end
    local options = {}
    if state.onDuty == true then
        options[#options + 1] = { title = 'Dispatch', description = 'Open active medical calls', icon = 'tower-broadcast',
            onSelect = function() ExecuteCommand('emsdispatchmenu') end }
        options[#options + 1] = { title = 'Deploy or Store Stretcher', description = 'Manage your EMS stretcher', icon = 'bed-pulse',
            onSelect = function() ExecuteCommand('cm_ems_stretcher_deploy') end }
        options[#options + 1] = { title = 'Request Backup', description = 'Request another on-duty EMS unit', icon = 'people-group',
            onSelect = function() ExecuteCommand('emsdispatchbackup') end }
        options[#options + 1] = { title = 'Panic Button', description = 'Send an urgent responder alert', icon = 'triangle-exclamation',
            onSelect = function() ExecuteCommand('emspanicbutton') end }
        options[#options + 1] = { title = 'Go Off Duty', description = 'End your shift and restore personal clothing', icon = 'right-from-bracket',
            onSelect = function()
                local ok, message = lib.callback.await('cm-ems:server:action', false, 'toggle_duty', {})
                TriggerEvent('cm-hud:client:notify', message or (ok and 'You are now off duty.' or 'Could not end duty.'), ok and 'success' or 'error')
            end }
    end
    if #options == 0 then
        TriggerEvent('cm-hud:client:notify', 'Wear an approved EMS outfit to start duty and use quick actions.', 'inform')
        return
    end
    lib.registerContext({ id = 'cm_ems_shared_quick_menu', title = 'EMS Quick Actions', options = options })
    lib.showContext('cm_ems_shared_quick_menu')
end)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb) cb({ ok = loadDashboard() }) end)
RegisterNUICallback('action', function(data, cb)
    local action = tostring(data.action or '')
    local payload = type(data.payload) == 'table' and data.payload or {}
    if action == 'set_meeting' then
        local coords = GetEntityCoords(PlayerPedId())
        payload.x, payload.y, payload.z = coords.x, coords.y, coords.z
    elseif action == 'set_daily_mission_npc' or action == 'set_clothing_npc' then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        payload.x, payload.y, payload.z, payload.heading = coords.x, coords.y, coords.z, GetEntityHeading(ped)
    elseif action == 'toggle_member_map' then
        local enabled = CMEMSTracking and CMEMSTracking.ToggleMemberBlips and CMEMSTracking.ToggleMemberBlips()
        cb({ ok = enabled ~= nil })
        return
    elseif action == 'toggle_duty' then
        payload.sex = sex()
        -- Server only verifies this against the resolved duty outfit --
        -- it never applies anything back. Wearing the right clothes
        -- happens at the wardrobe NPC beforehand (client/wardrobe.lua).
        if type(LocalPlayer.state.cmEms) ~= 'table' or LocalPlayer.state.cmEms.onDuty ~= true then
            payload.currentOutfit = captureOutfit()
        end
    elseif action == 'save_outfit_preset' or action == 'save_favorite_outfit' then
        payload.sex = sex()
        payload.outfit = captureOutfit()
    end
    local ok, message, result = lib.callback.await('cm-ems:server:action', false, action, payload)
    notify(message or (ok and 'Done.' or 'EMS action failed.'), ok and 'success' or 'error')
    if ok then
        loadDashboard()
    end
    cb({ ok = ok == true })
end)
RegisterNUICallback('assignLeader', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:adminAssignLeader', false, data.characterId)
    notify(message, ok and 'success' or 'error')
    if ok then loadDashboard() end
    cb({ ok = ok == true })
end)
RegisterNUICallback('adminStaffAction', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:adminStaffAction', false, data.action, data)
    notify(message, ok and 'success' or 'error')
    if ok then loadDashboard('admin') end
    cb({ ok = ok == true })
end)
RegisterNUICallback('adminSaveSettings', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:adminSaveSettings', false, data)
    notify(message, ok and 'success' or 'error')
    if ok then loadDashboard('admin') end
    cb({ ok = ok == true })
end)
RegisterNUICallback('medicalHistory', function(data, cb)
    local rows, reason = lib.callback.await('cm-ems:server:medicalHistory', false, data.patientCid, 50)
    if not rows then notify(reason or 'Unable to load medical history.', 'error') end
    cb({ ok = rows ~= nil, rows = rows or {} })
end)
RegisterNUICallback('createMedicalReport', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:createMedicalReport', false, data)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('employeeTasks', function(_, cb)
    local tasks, reason = lib.callback.await('cm-ems:server:employeeTasks', false)
    if not tasks then notify(reason or 'Unable to load EMS tasks.', 'error') end
    cb({ ok = tasks ~= nil, tasks = tasks })
end)
RegisterNUICallback('claimEmployeeTask', function(data, cb)
    local ok, message, tasks = lib.callback.await('cm-ems:server:claimEmployeeTask', false, data.period, data.taskId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, tasks = tasks })
end)
RegisterNUICallback('emsCallHistory', function(_, cb)
    local rows, reason = lib.callback.await('cm-ems:server:emsCallHistory', false)
    if not rows then notify(reason or 'Unable to load EMS call history.', 'error') end
    cb({ ok = rows ~= nil, rows = rows or {} })
end)

RegisterNUICallback('openEmsClothingAdmin', function(_, cb)
    closeMenu()
    TriggerEvent('nvCloth:client:openEmsWardrobe', true)
    cb({ ok = true })
end)

RegisterNUICallback('previewWardrobeItem', function(data, cb)
    local ped = PlayerPedId()
    local componentIndex = tonumber(data.componentIndex) or 0
    local drawableId = tonumber(data.drawableId) or 0
    local textureId = math.max(0, tonumber(data.textureId) or 0)
    if tostring(data.componentType) == 'prop' then
        SetPedPropIndex(ped, componentIndex, drawableId, textureId, true)
    else
        SetPedComponentVariation(ped, componentIndex, drawableId, textureId, 0)
    end
    cb({ ok = true })
end)

RegisterNetEvent('cm-ems:client:invite', function(data)
    CreateThread(function()
        local result = lib.alertDialog({ header = 'EMS Invitation', content = ('%s invited you to join Emergency Medical Services.'):format(tostring(data.inviter or 'EMS')), centered = true, cancel = true, labels = { confirm = 'Join EMS', cancel = 'Decline' } })
        local ok, message = lib.callback.await('cm-ems:server:respondInvite', false, result == 'confirm')
        notify(message, ok and 'success' or 'error')
    end)
end)

RegisterNetEvent('cm-ems:client:medicineOffer', function(data)
    data = type(data) == 'table' and data or {}
    local result = lib.alertDialog({
        header = 'Buy Medicine',
        content = ('%s offers **%s** for **$%d**.'):format(
            tostring(data.sellerName or 'An EMS medic'),
            tostring(data.itemLabel or 'medicine'),
            math.max(0, math.floor(tonumber(data.price) or 0))
        ),
        centered = true,
        cancel = true,
        labels = { confirm = 'Buy', cancel = 'Refuse' },
    })
    TriggerServerEvent('cm-ems:server:medicineOfferResponse', result == 'confirm')
end)

RegisterNetEvent('cm-ems:client:forceDutyCleanup', function()
    closeMenu()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if lib.progressActive and lib.progressActive() then lib.cancelProgress() end
end)

AddStateBagChangeHandler('cmEms', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    if (value == false or type(value) ~= 'table' or value.onDuty ~= true) and civilianOutfit then
        applyOutfit(civilianOutfit)
        civilianOutfit = nil
    end
end)

RegisterNUICallback('escape', function(_, cb) closeMenu(); cb({ ok = true }) end)
