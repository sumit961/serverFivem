local open = false

function CmLawMenuOpen()
    return open
end

local function closeMenu()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- Bare global: client/vehicles.lua's "Set location" flow needs to close the
-- F9 menu itself before warping the player into the location dummy.
function CmLawCloseMenu()
    closeMenu()
end

local function refresh()
    local data = lib.callback.await('cm-law:server:dashboard', false)
    SendNUIMessage({ action = 'dashboard', data = data })
    return data
end

local function openMenu(initialTab)
    if open or IsPauseMenuActive() or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local data = lib.callback.await('cm-law:server:dashboard', false)
    if not data or data.ok ~= true then
        return
    end
    if initialTab == 'mdt' and (type(data.member) ~= 'table'
        or data.member.onDuty ~= true or data.canMdt ~= true) then
        return
    end
    if initialTab == 'dispatch' and (type(data.member) ~= 'table'
        or data.member.onDuty ~= true or data.canDispatch ~= true) then
        return
    end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data, initialTab = initialTab,
        standaloneMode = initialTab == 'dispatch' or initialTab == 'mdt',
        facilityOnly = initialTab == 'fleet' })
end

local function legalState()
    local state = LocalPlayer.state.cmLegalOrg
    return type(state) == 'table' and state or nil
end

-- Shared J-key entry point. cm-police owns the physical J mapping and
-- forwards here when the player belongs to one of cm-law's organizations.
-- Civilians are deliberately silent: no menu and no warning notification.
function OpenLawQuickMenu()
    local state = legalState()
    if not state then
        local data = lib.callback.await('cm-law:server:dashboard', false)
        if not data or data.ok ~= true or type(data.member) ~= 'table' then return false end
        state = data.member
        state.label = data.organization and data.organization.label or state.label
        state.shortLabel = data.organization and data.organization.shortLabel or state.shortLabel
    end
    if state.onDuty ~= true then
        TriggerEvent('cm-hud:client:notify', 'Go on duty through your organization wardrobe to use quick actions.', 'inform')
        return false
    end
    TriggerEvent('cm-police:client:openLawQuickMenu', state)
    return true
end

RegisterNetEvent('cm-law:client:openQuickMenu', function() OpenLawQuickMenu() end)

RegisterNetEvent('cm-law:client:quickMenuOffDuty', function()
    local result = lib.callback.await('cm-law:server:setDuty', false, false)
    if result and result.ok then TriggerEvent('cm-law:client:restorePersonalOutfit') end
    TriggerEvent('cm-hud:client:notify', result and (result.message or result.error) or 'Could not end duty.', result and result.ok and 'success' or 'error')
end)

RegisterNetEvent('cm-law:client:quickMenuAlert', function(kind)
    if kind == 'backup' or kind == 'panic' then LawRequestOfficerAlert(kind) end
end)

RegisterNetEvent('cm-law:client:forceDutyCleanup', function()
    closeMenu()
    if lib.progressActive and lib.progressActive() then lib.cancelProgress() end
    TriggerEvent('cm-law:client:restorePersonalOutfit')
    TriggerEvent('cm-inventory:client:requestEquipmentRefresh')
end)

-- Bare global: the Fleet facility NPC (client/facilities.lua) opens this
-- same menu straight to the Fleet tab instead of a separate context menu,
-- so there is only one fleet UI to keep in sync.
function OpenLawMenu(initialTab)
    openMenu(initialTab)
end

RegisterCommand(Config.MenuCommand, function()
    OpenLawQuickMenu()
end, false)

RegisterNetEvent('cm-law:client:openDashboard', function() openMenu('overview') end)

RegisterNetEvent('cm-law:client:openMdt', function()
    local state = LocalPlayer.state.cmLegalOrg
    if type(state) ~= 'table' or state.onDuty ~= true or state.suspended or (state.capabilities and state.capabilities.mdt == false) then return end
    -- openMenu performs the authoritative dashboard/member check. Failed
    -- membership, duty and permission checks are intentionally silent for the
    -- shared Tab key.
    openMenu('mdt')
end)

RegisterNetEvent('cm-law:client:openDispatch', function()
    local state = LocalPlayer.state.cmLegalOrg
    if type(state) ~= 'table' or state.onDuty ~= true or state.suspended or (state.capabilities and state.capabilities.dispatch == false) then return end
    openMenu('dispatch')
end)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb) cb(refresh() or { ok = false }) end)
RegisterNUICallback('staffAction', function(data, cb)
    local result = lib.callback.await('cm-law:server:staffAction', false, data.action, data)
    cb(result or { ok = false, error = 'No response from server.' })
    if result and result.ok then refresh() end
end)
-- Ranks & Access page (html/app.js).
RegisterNUICallback('saveRank', function(data, cb)
    local result = lib.callback.await('cm-law:server:saveRank', false, data)
    cb(result or { ok = false, error = 'No response from server.' })
    if result and result.ok then refresh() end
end)
RegisterNUICallback('deleteRank', function(data, cb)
    local result = lib.callback.await('cm-law:server:deleteRank', false, data and data.rankId)
    cb(result or { ok = false, error = 'No response from server.' })
    if result and result.ok then refresh() end
end)

-- Activity Logs page (html/app.js) -- on-demand fetch, same shape as
-- fleetCatalog/dispatchActiveCalls.
RegisterNUICallback('activityLog', function(_, cb)
    cb({ list = lib.callback.await('cm-law:server:activityLog', false) or {} })
end)

RegisterNUICallback('lawMdtSearchCitizens', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtSearchCitizens', false, data and data.query) or { ok = false })
end)
RegisterNUICallback('lawMdtCitizenProfile', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtCitizenProfile', false, data and data.characterId) or { ok = false })
end)
RegisterNUICallback('lawMdtVehicleSearch', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtVehicleSearch', false, data and data.plate) or { ok = false })
end)
RegisterNUICallback('lawMdtAddNote', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtAddNote', false, data and data.characterId, data and data.note) or { ok = false })
end)
RegisterNUICallback('lawMdtCreateReport', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtCreateReport', false, data) or { ok = false })
end)
RegisterNUICallback('lawMdtSetWanted', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtSetWanted', false, data and data.characterId, data and data.stars, data and data.reason) or { ok = false })
end)
RegisterNUICallback('lawMdtCreateWarrant', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtCreateWarrant', false, data) or { ok = false })
end)
RegisterNUICallback('lawMdtCloseWarrant', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtCloseWarrant', false, data and data.warrantId) or { ok = false })
end)

-- Fleet tab (html/app.js) NUI relays live in client/vehicles.lua now
-- (fleetCatalog/setFleetVehicleMinTier/spawnFleetVehicle/
-- setFleetVehicleLocation/recallAllFleetVehicles) -- persistent recall/spawn
-- needs more client-side plumbing (warping into the location dummy, the H
-- keybind) than fits alongside this file's other NUI relays.

-- Dispatch tab (html/app.js) -- named to match cm-police's own F7 dispatch
-- NUI callbacks 1:1 (dispatchActiveCalls/dispatchAccept/dispatchEnRoute/
-- dispatchResolve/dispatchHistory), since the shape of the feature (and its
-- eventual MDT-terminal reuse) is identical.
RegisterNUICallback('dispatchActiveCalls', function(_, cb)
    cb({ list = lib.callback.await('cm-law:server:dispatchActiveCalls', false) or {} })
end)
RegisterNUICallback('dispatchHistory', function(_, cb)
    cb({ list = lib.callback.await('cm-law:server:dispatchHistory', false) or {} })
end)
RegisterNUICallback('dispatchAccept', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:acceptDispatchCall', false, data.callId)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchEnRoute', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setDispatchResponseStatus', false, data.callId, 'en_route')
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchResolve', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:resolveDispatchCall', false, data.callId, data.resolution)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchOfficerAlert', function(data, cb)
    if not data or data.confirmed ~= true then return cb({ ok = false, error = 'Confirmation required.' }) end
    local ok, message = lib.callback.await('cm-law:server:createOfficerAlert', false, data.alertType)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)

RegisterNetEvent('cm-law:client:membershipChanged', function()
    if open then refresh() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeMenu() end
end)
