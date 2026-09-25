local open = false
-- Whether the dispatch notification carousel (html/app.js's
-- #dispatchNotifyStack) currently has a card up. It needs mouse-only NUI
-- focus (SetNuiFocus(true, false) + SetNuiFocusKeepInput) to be clickable
-- while F6 is closed, WITHOUT taking over full keyboard/movement focus the
-- way the F6 menu itself does -- closeMenu() below has to hand focus back to
-- that partial state instead of fully releasing it if a card is still up.
local notifyFocusActive = false

function CmLawMenuOpen()
    return open
end

local function applyNotifyFocus()
    if notifyFocusActive then
        SetNuiFocus(true, false)
        SetNuiFocusKeepInput(true)
    else
        SetNuiFocus(false, false)
    end
end

local function closeMenu()
    open = false
    if type(StopLawTablet) == 'function' then StopLawTablet() end
    SendNUIMessage({ cmInterface = "law", action = 'close' })
    -- The embedded Police backend can open this same shared surface. Clear
    -- its companion state whenever the shared Law close path wins ESC,
    -- refresh failure, or an explicit close callback.
    TriggerEvent('cm-law:client:sharedDashboardClosed')
    applyNotifyFocus()
end

CreateThread(function()
    while true do
        if open then
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 202, true)
            if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 202) then
                SendNUIMessage({ cmInterface = 'law', action = 'escape' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Bare global: client/vehicles.lua's "Set location" flow needs to close the
-- F9 menu itself before warping the player into the location dummy.
function CmLawCloseMenu()
    closeMenu()
end

local function fetchDashboardData()
    if type(LocalPlayer.state.cmPolice) == 'table' and type(NormalizePoliceDashboard) == 'function' then
        local policeData, reason = lib.callback.await('cm-police:server:dashboard', false, false, type(sex) == 'function' and sex() or 'male')
        if not policeData then
            return { ok = false, error = reason or 'Police organization access is no longer available.' }
        end
        return NormalizePoliceDashboard(policeData)
    end
    return lib.callback.await('cm-law:server:dashboard', false)
end

local function refresh()
    local data = fetchDashboardData()
    if not data or data.ok ~= true then
        closeMenu()
        TriggerEvent('cm-hud:client:notify', data and data.error or 'Organization access is no longer available.', 'error')
        return data or { ok = false, error = 'Organization access is no longer available.' }
    end
    SendNUIMessage({ cmInterface = "law", action = 'dashboard', data = data })
    return data
end

local function openMenu(initialTab)
    if open or IsPauseMenuActive() or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local data = fetchDashboardData()
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
    -- F6 is the single shared entry point. Close any legacy Police surface
    -- first so a stale command/key mapping cannot leave its iframe focused
    -- underneath the approved Organization Hub.
    TriggerEvent('cm-police:client:closeMenu')
    open = true
    SetNuiFocus(true, true)
    if (initialTab == 'mdt' or initialTab == 'dispatch') and type(StartLawTablet) == 'function' then
        StartLawTablet()
    end
    SendNUIMessage({ cmInterface = "law", action = 'open', data = data, initialTab = initialTab,
        standaloneMode = initialTab == 'dispatch',
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
    TriggerEvent('cm-law:client:openLawQuickMenu', state)
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
    openMenu('overview')
end, false)

RegisterNetEvent('cm-law:client:openDashboard', function() openMenu('overview') end)
RegisterNetEvent('cm-law:client:closeDashboard', function() closeMenu() end)

RegisterNetEvent('cm-law:client:openMdt', function()
    local legal, police = LocalPlayer.state.cmLegalOrg, LocalPlayer.state.cmPolice
    local onDuty = (type(legal) == 'table' and legal.onDuty == true and not legal.suspended and (not legal.capabilities or legal.capabilities.mdt ~= false))
        or (type(police) == 'table' and police.onDuty == true and not police.suspended)
    if not onDuty then return end
    openMenu('mdt')
end)

RegisterNetEvent('cm-law:client:openDispatch', function()
    local legal, police = LocalPlayer.state.cmLegalOrg, LocalPlayer.state.cmPolice
    local onDuty = (type(legal) == 'table' and legal.onDuty == true and not legal.suspended and (not legal.capabilities or legal.capabilities.dispatch ~= false))
        or (type(police) == 'table' and police.onDuty == true and not police.suspended)
    if not onDuty then return end
    openMenu('dispatch')
end)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('escape', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('bookingClose', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)
RegisterNUICallback('bookingSubmit', function(data, cb)
    local result = lib.callback.await('cm-law:server:bookSuspect', false, type(data) == 'table' and data or {})
    cb(result or { ok = false, error = 'No response from booking authority.' })
    if result and result.ok then
        SetNuiFocus(false, false)
        TriggerEvent('cm-hud:client:notify', result.message or 'Booking confirmed.', 'success')
    end
end)
RegisterNUICallback('refresh', function(_, cb)
    -- LSPD uses the shared Law renderer but keeps cm-police's authoritative
    -- membership tables. Refresh through that backend and normalize again so
    -- the dashboard never falls back to a stale organisation/session.
    if type(LocalPlayer.state.cmPolice) == 'table' and type(NormalizePoliceDashboard) == 'function' then
        local policeData, reason = lib.callback.await('cm-police:server:dashboard', false, false, type(sex) == 'function' and sex() or 'male')
        if not policeData then
            closeMenu()
            cb({ ok = false, error = reason or 'Police organization access is no longer available.' })
            return
        end
        local normalized = NormalizePoliceDashboard(policeData)
        SendNUIMessage({ cmInterface = 'law', action = 'dashboard', data = normalized })
        cb(normalized)
        return
    end
    cb(refresh() or { ok = false })
end)
RegisterNUICallback('endDuty', function(_, cb)
    local result = lib.callback.await('cm-law:server:setDuty', false, false)
    cb(result or { ok = false, error = 'No response from server.' })
end)
RegisterNUICallback('staffAction', function(data, cb)
    local result = lib.callback.await('cm-law:server:staffAction', false, data.action, data)
    cb(result or { ok = false, error = 'No response from server.' })
    if result and result.ok then refresh() end
end)
-- The F6 recruit form accepts character identity only. Each server backend
-- resolves the session and reuses its nearby invitation validation.
RegisterNUICallback('hubInvite', function(data, cb)
    local targetCid = type(data) == 'table' and tostring(data.characterId or '') or ''
    local callback = type(LocalPlayer.state.cmPolice) == 'table'
        and 'cm-police:server:inviteFromHub' or 'cm-law:server:inviteFromHub'
    cb(lib.callback.await(callback, false, targetCid) or { ok = false, error = 'The invitation service did not respond.' })
end)
-- Ranks & Access page (html/app.js).
RegisterNUICallback('saveRank', function(data, cb)
    local isPolice = type(LocalPlayer.state.cmPolice) == 'table'
    local result
    if isPolice then
        result = lib.callback.await('cm-police:server:action', false, 'save_rank', data)
    else
        result = lib.callback.await('cm-law:server:saveRank', false, data)
    end
    cb(result or { ok = false, error = 'No response from server.' })
    if result and result.ok then refresh() end
end)
RegisterNUICallback('deleteRank', function(data, cb)
    local isPolice = type(LocalPlayer.state.cmPolice) == 'table'
    local result
    if isPolice then
        result = lib.callback.await('cm-police:server:action', false, 'delete_rank', data)
    else
        result = lib.callback.await('cm-law:server:deleteRank', false, data and data.rankId)
    end
    cb(result or { ok = false, error = 'No response from server.' })
    if result and result.ok then refresh() end
end)

-- Activity Logs page (html/app.js) -- on-demand fetch, same shape as
-- fleetCatalog/dispatchActiveCalls.
RegisterNUICallback('toggleMemberMap', function(_, cb)
    local enabled = CMLawTrackingToggle and CMLawTrackingToggle()
    -- Tell the server whether to keep pushing positions to us, so an
    -- organization with nobody watching costs nothing to broadcast.
    if enabled ~= nil then TriggerServerEvent('cm-law:server:toggleMemberMap', enabled == true) end
    cb({ ok = enabled ~= nil, enabled = enabled == true })
end)

RegisterNUICallback('setMeetingPoint', function(data, cb)
    local payload = { clear = type(data) == 'table' and data.clear == true }
    if not payload.clear then
        local coords = GetEntityCoords(PlayerPedId())
        payload.x, payload.y, payload.z = coords.x, coords.y, coords.z
    end
    local ok, message = lib.callback.await('cm-law:server:setMeetingPoint', false, payload)
    cb({ ok = ok == true, message = message })
end)

RegisterNUICallback('activityLog', function(_, cb)
    cb({ list = lib.callback.await('cm-law:server:activityLog', false) or {} })
end)
RegisterNUICallback('custody', function(_, cb)
    cb(lib.callback.await('cm-law:server:custody', false) or { ok = false, error = 'Custody data unavailable.' })
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
RegisterNUICallback('lawMdtSetReportStatus', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtSetReportStatus', false, data and data.reportId, data and data.status) or { ok = false })
end)
RegisterNUICallback('lawMdtAddReportEvidence', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtAddReportEvidence', false, data and data.reportId, data and data.label, data and data.note) or { ok = false })
end)
RegisterNUICallback('lawMdtLinkReportOfficer', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtLinkReportOfficer', false, data and data.reportId, data and data.officerCid) or { ok = false })
end)
RegisterNUICallback('lawMdtCaptureReportPhoto', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtCaptureReportPhoto', false, data and data.reportId) or { ok = false })
end)
RegisterNUICallback('lawMdtCapturePhoto', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtCapturePhoto', false, data and data.characterId) or { ok = false })
end)
RegisterNUICallback('lawMdtSetLicenseStatus', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtSetLicenseStatus', false, data and data.characterId, data and data.licenseType, data and data.status, data and data.reason) or { ok = false })
end)
RegisterNUICallback('setMemberPhoto', function(_, cb)
    cb(lib.callback.await('cm-law:server:setMemberPhoto', false) or { ok = false })
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
RegisterNUICallback('lawMdtDashboard', function(_, cb)
    cb(lib.callback.await('cm-law:server:mdtDashboard', false) or { ok = false })
end)
RegisterNUICallback('lawMdtIssueBolo', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtIssueBolo', false, data and data.plate, data and data.description) or { ok = false })
end)
RegisterNUICallback('lawMdtClearBolo', function(data, cb)
    cb(lib.callback.await('cm-law:server:mdtClearBolo', false, data and data.boloId) or { ok = false })
end)
RegisterNUICallback('lawMdtActiveBolos', function(_, cb)
    cb({ list = lib.callback.await('cm-law:server:mdtActiveBolos', false) or {} })
end)
RegisterNUICallback('lawMdtBoloHistory', function(_, cb)
    cb({ list = lib.callback.await('cm-law:server:mdtBoloHistory', false) or {} })
end)

-- Criminal Code page (html/app.js).
RegisterNUICallback('lawListCharges', function(_, cb)
    cb(lib.callback.await('cm-law:server:listCharges', false) or { ok = false })
end)
RegisterNUICallback('lawCreateCharge', function(data, cb)
    cb(lib.callback.await('cm-law:server:createCharge', false, data) or { ok = false })
end)
RegisterNUICallback('lawUpdateCharge', function(data, cb)
    cb(lib.callback.await('cm-law:server:updateCharge', false, data) or { ok = false })
end)
RegisterNUICallback('lawDeleteCharge', function(data, cb)
    cb(lib.callback.await('cm-law:server:deleteCharge', false, data and data.id) or { ok = false })
end)

-- Fleet tab (html/app.js) NUI relays live in client/vehicles.lua now
-- (fleetCatalog/setFleetVehicleMinTier/setFleetVehicleLocation/
-- recallAllFleetVehicles) -- persistent vehicle management
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
    local ok, message, call = lib.callback.await('cm-law:server:acceptDispatchCall', false, data.callId)
    if ok and data.route ~= false and type(call) == 'table' and type(call.coords) == 'table'
        and tonumber(call.coords.x) and tonumber(call.coords.y) then
        SetNewWaypoint(tonumber(call.coords.x) + 0.0, tonumber(call.coords.y) + 0.0)
    end
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
RegisterNUICallback('dispatchLiveOperations', function(_, cb)
    cb(lib.callback.await('cm-law:server:liveOperations', false) or { ok = false, error = 'Live operations unavailable.' })
end)
RegisterNUICallback('setUnitStatus', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setUnitStatus', false, data and data.status)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('setUnitCallsign', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setUnitCallsign', false, data and data.callsign)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchAssignUnit', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:assignDispatchUnit', false, data and data.callId, data and data.characterId)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchReleaseUnit', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:releaseDispatchUnit', false, data and data.callId, data and data.characterId)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchSetPriority', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setDispatchPriority', false, data and data.callId, data and data.priority)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchRouteUnit', function(data, cb)
    local ok, message, coords = lib.callback.await('cm-law:server:routeToUnit', false, data and data.characterId)
    if ok and type(coords) == 'table' and tonumber(coords.x) and tonumber(coords.y) then
        SetNewWaypoint(tonumber(coords.x) + 0.0, tonumber(coords.y) + 0.0)
    end
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('dispatchOnScene', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setDispatchResponseStatus', false, data and data.callId, 'on_scene')
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)

-- Notification carousel (html/app.js's #dispatchNotifyStack). Quick GPS
-- reuses the same bare global the F7 Dispatch tab's own Accept button uses
-- (client/dispatch.lua). Focus toggling only touches the F6 menu's own
-- SetNuiFocus state when F6 isn't already open (see applyNotifyFocus above).
RegisterNUICallback('dispatchQuickRoute', function(data, cb)
    cb({ ok = type(LawSetDispatchRoute) == 'function' and LawSetDispatchRoute(tonumber(data and data.callId)) == true })
end)
RegisterNUICallback('dispatchNotifyFocus', function(data, cb)
    notifyFocusActive = data and data.active == true
    if not open then applyNotifyFocus() end
    cb({ ok = true })
end)

RegisterNetEvent('cm-law:client:membershipChanged', function()
    if open then refresh() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeMenu() end
end)
