local open = false
local adminMode = false
local sharedDashboardOpen = false
local civilianOutfit
local impoundPhotoMode = false
local impoundPhotoPreviousView = 1

CreateThread(function()
    while true do
        if impoundPhotoMode then
            HideHudAndRadarThisFrame()
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 75, true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not impoundPhotoMode then return end
    impoundPhotoMode = false
    SendNUIMessage({ cmInterface = "police", action = 'impoundCamera:hide' })
    SetFollowPedCamViewMode(impoundPhotoPreviousView ~= 4 and impoundPhotoPreviousView or 1)
end)

-- Global getter so client/ui.lua's confirm/quick-menu components know
-- whether to restore NUI focus to the F7 dashboard (still open underneath)
-- or drop it entirely once they close.
function IsPoliceMenuOpen()
    return open or sharedDashboardOpen
end

local function notify(message, kind)
    PoliceNotify(message, kind)
end

-- Bare global (not local) because the wardrobe UI captures favorites and
-- manager-created Police presets from the current ped appearance.
function captureOutfit()
    local ped = PlayerPedId()
    local outfit = { components = {}, props = {} }
    for index = 0, 11 do outfit.components[tostring(index)] = { drawable = GetPedDrawableVariation(ped, index), texture = GetPedTextureVariation(ped, index), palette = GetPedPaletteVariation(ped, index) } end
    for index = 0, 7 do outfit.props[tostring(index)] = { drawable = GetPedPropIndex(ped, index), texture = GetPedPropTextureIndex(ped, index) } end
    return outfit
end

-- Bare global (not local) -- client/wardrobe.lua's wardrobe-NPC "Wear"
-- confirmation needs this too, same cross-file-global convention as
-- captureOutfit/sex above.
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

-- Bare global (not local) -- wardrobe and duty reconciliation both need it.
function sex()
    return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male'
end

local function closeMenu()
    open = false
    sharedDashboardOpen = false
    adminMode = false
    if type(StopLawTablet) == 'function' then StopLawTablet() end
    SetNuiFocus(false, false)
    SendNUIMessage({ cmInterface = "police", action = 'close' })
end

RegisterNetEvent('cm-law:client:sharedDashboardClosed', function()
    sharedDashboardOpen = false
end)

CreateThread(function()
    while true do
        if open then
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 202, true)
            if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 202) then closeMenu() end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('cm-police:client:closeMenu', closeMenu)

-- Police owns a mature database and gameplay surface, while cm-law owns the
-- shared organisation dashboard. Keep that backend contract intact and
-- translate the Police result once at the UI boundary.
function NormalizePoliceDashboard(data)
    data = type(data) == 'table' and data or {}
    local source = type(data.self) == 'table' and data.self or {}
    local capabilities = type(data.capabilities) == 'table' and data.capabilities or {}
    local member = {
        characterId = tostring(source.characterId or ''),
        rankName = tostring(source.rankName or 'Police Member'),
        tier = tonumber(source.tier) or 0,
        isLeader = source.isLeader == true,
        onDuty = source.onDuty == true,
        suspended = source.suspended == true,
        permissions = type(source.permissions) == 'table' and source.permissions or {},
        capabilities = {
            dispatch = capabilities.receiveDispatch == true,
            mdt = capabilities.useMdt == true,
            fleet = capabilities.spawnVehicles == true or capabilities.manageVehicles == true,
            armory = capabilities.useArmory == true,
            citations = true,
            impound = capabilities.manageImpound == true,
            radar = true,
            spikes = true,
            barricades = capabilities.manageBarricades == true,
            clamp = true,
            k9 = true,
            alpr = capabilities.manageAlpr == true,
            prisonIntake = true,
        },
    }
    local roster = {}
    for _, row in ipairs(type(data.members) == 'table' and data.members or {}) do
        roster[#roster + 1] = {
            character_id = tostring(row.characterId or ''),
            name = tostring(row.name or row.characterId or 'Police member'),
            rank_id = tonumber(row.rankId),
            rank_name = tostring(row.rankName or 'Police Member'),
            tier = tonumber(row.tier) or 0,
            on_duty = row.onDuty == true,
            online = row.online == true,
            callsign = row.callsign,
            suspended = row.suspended == true,
            is_leader = row.isLeader == true,
            photo_url = row.photoUrl,
        }
    end
    local ranks = {}
    for _, row in ipairs(type(data.ranks) == 'table' and data.ranks or {}) do
        ranks[#ranks + 1] = {
            id = tonumber(row.id), name = tostring(row.name or 'Rank'),
            tier = tonumber(row.tier) or 0, is_leader = row.isLeader == true,
            permissions = row.permissions or {},
        }
    end
    local summary = type(data.summary) == 'table' and data.summary or {}
    local feature = type(data.featureCapabilities) == 'table' and data.featureCapabilities or {}
    local function allowed(permission)
        return not member.suspended and (member.isLeader or member.permissions[permission] == true)
    end
    local inspectPermissions = capabilities.manageRanks == true or capabilities.managePermissions == true
    if not inspectPermissions then
        for _, rank in ipairs(ranks) do rank.permissions = {} end
    end
    local normalized = {
        ok = true,
        source = 'cm-police',
        organization = {
            id = 'lspd', label = 'Los Santos Police Department', shortLabel = 'LSPD',
            color = '#2D7FF9', jurisdiction = 'Los Santos and state law enforcement coverage',
            leaderCid = data.organization and data.organization.leaderCid or nil,
            leaderName = data.organization and data.organization.leaderName or 'Not assigned',
        },
        member = member, characterId = member.characterId, roster = roster, ranks = ranks,
        summary = {
            memberCount = tonumber(summary.memberCount) or #roster,
            onDutyCount = tonumber(summary.onDutyCount) or 0,
            fleetConfigured = tonumber(summary.fleetConfigured) or 0,
            fleetAvailable = tonumber(summary.fleetAvailable) or 0,
            activeCalls = tonumber(summary.activeCalls) or 0,
            assignedCalls = tonumber(summary.assignedCalls) or 0,
            balance = capabilities.viewFund == true and type(data.fund) == 'table' and tonumber(data.fund.balance) or nil,
        },
        canViewMembers = allowed('police.view_members'),
        -- The Hub submits Police mutations only through police_action and
        -- inviteFromHub; cm-law staffing callbacks never touch Police tables.
        canInvite = allowed('police.invite'),
        canManage = allowed('police.promote') or allowed('police.demote') or allowed('police.kick'),
        canManageRanks = capabilities.manageRanks == true,
        canManagePermissions = capabilities.managePermissions == true,
        canInspectRankPermissions = inspectPermissions,
        permissions = inspectPermissions and data.permissions or {},
        canDispatch = allowed('police.receive_dispatch'),
        canMdt = allowed('police.mdt'),
        canCustody = allowed('police.book'),
        canViewMemberMap = allowed('police.view_member_map'),
        canSetMeeting = allowed('police.set_meeting'),
        canFleetManage = capabilities.manageVehicles == true,
        canFleetSpawn = allowed('police.spawn_vehicles'),
        logisticsVisible = false,
        canManageCharges = false,
        prison = { ready = false, configured = false, intakeConfigured = false, releaseConfigured = false, spawnCount = 0, capacity = 0, activeCount = 0 },
        facilities = {}, facilityTypes = {}, featureCapabilities = feature,
        canViewActivity = data.canViewLogs == true, recentActivity = data.logs or {},
    }
    return normalized
end

local function loadDashboard(initialPage, options)
    local data, reason = lib.callback.await('cm-police:server:dashboard', false, adminMode, sex())
    if not data then notify(reason or 'Unable to open Police.', 'error'); return false end
    if not adminMode and not (options and options.utility == true) then
        sharedDashboardOpen = true
        if (initialPage == 'mdt' or initialPage == 'dispatch') and type(StartLawTablet) == 'function' then
            StartLawTablet()
        end
        SendNUIMessage({ cmInterface = "law", action = 'open', data = NormalizePoliceDashboard(data), initialTab = initialPage,
            standaloneMode = initialPage == 'dispatch' })
        return true
    end
    if (initialPage == 'mdt' or initialPage == 'dispatch') and type(StartLawTablet) == 'function' then
        StartLawTablet()
    end
    SendNUIMessage({ cmInterface = "police", action = 'open', data = data, initialPage = initialPage,
        armoryStandalone = options and options.armoryStandalone == true,
        fleetStandalone = options and options.fleetStandalone == true,
        dispatchStandalone = options and options.dispatchStandalone == true })
    return true
end

RegisterNetEvent('cm-police:client:open', function(asAdmin)
    adminMode = asAdmin == true
    if not loadDashboard(adminMode and 'admin' or nil) then return end
    if not adminMode then SetNuiFocus(true, true); return end
    open = true
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cm-police:client:openFleet', function()
    adminMode = false
    if not loadDashboard('fleet', { fleetStandalone = true, utility = true }) then return end
    open = true
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cm-police:client:openArmory', function()
    adminMode = false
    if not loadDashboard('armory', { armoryStandalone = true, utility = true }) then return end
    open = true
    SetNuiFocus(true, true)
end)

RegisterCommand(PoliceConfig.MenuCommand, function()
    adminMode = false
    TriggerEvent('cm-law:client:openDashboard')
end, false)

RegisterNetEvent('cm-police:client:openDashboard', function()
    if open then return closeMenu() end
    if sharedDashboardOpen then
        TriggerEvent('cm-law:client:closeDashboard')
        return
    end
    adminMode = false
    TriggerEvent('cm-law:client:openDashboard')
end)

RegisterNetEvent('cm-police:client:openDispatch', function()
    if open then return end
    adminMode = false
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' or state.onDuty ~= true then return end
    local permissions = type(state.permissions) == 'table' and state.permissions or {}
    if state.isLeader ~= true and permissions['police.receive_dispatch'] ~= true then return end
    if not loadDashboard('dispatch', { dispatchStandalone = true, utility = true }) then return end
    open = true
    SetNuiFocus(true, true)
end)

-- Death always ends the current shift. The server event can affect only the
-- caller's own membership; civilian clothing is restored immediately and once
-- more after respawn because character appearance may be reapplied during spawn.
CreateThread(function()
    local wasDead = LocalPlayer.state.isDead == true
    while true do
        Wait(250)
        local dead = LocalPlayer.state.isDead == true
        if dead and not wasDead then
            local police = LocalPlayer.state.cmPolice
            if type(police) == 'table' and police.onDuty == true then
                TriggerServerEvent('cm-police:server:endDutyOnDeath')
                TriggerEvent('cm-inventory:client:restoreEquippedClothing')
            end
        elseif wasDead and not dead then
            Wait(500)
            TriggerEvent('cm-inventory:client:restoreEquippedClothing')
        end
        wasDead = dead
    end
end)

RegisterNUICallback('police_close', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('police_refresh', function(_, cb) cb({ ok = loadDashboard() }) end)
RegisterNUICallback('police_action', function(data, cb)
    local action = tostring(data.action or '')
    local payload = type(data.payload) == 'table' and data.payload or {}
    if action == 'set_meeting' then
        local coords = GetEntityCoords(PlayerPedId())
        payload.x, payload.y, payload.z = coords.x, coords.y, coords.z
    elseif action == 'set_impound_kiosk' then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        payload.x, payload.y, payload.z = coords.x, coords.y, coords.z
        payload.heading = GetEntityHeading(ped)
    elseif action == 'set_wardrobe_npc' then
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        payload.x, payload.y, payload.z = coords.x, coords.y, coords.z
        payload.heading = GetEntityHeading(ped)
    elseif action == 'toggle_member_map' then
        local enabled = CMPoliceTracking and CMPoliceTracking.ToggleMemberBlips and CMPoliceTracking.ToggleMemberBlips()
        cb({ ok = enabled ~= nil })
        return
    elseif action == 'save_outfit_preset' then
        -- The NUI has no access to ped component/prop variations, so the
        -- outfit to save always comes from the client's own current clothing,
        -- never from anything the NUI/JS supplies.
        payload.sex = sex()
        payload.outfit = captureOutfit()
    end
    local ok, message = lib.callback.await('cm-police:server:action', false, action, payload)
    notify(message or (ok and 'Done.' or 'Police action failed.'), ok and 'success' or 'error')
    if ok then
        -- Wearing a duty outfit happens only at the wardrobe NPC
        -- (client/wardrobe.lua); this generic dispatcher never applies
        -- clothing live.
        loadDashboard()
    end
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_assignLeader', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:adminAssignLeader', false, data.characterId)
    notify(message, ok and 'success' or 'error')
    if ok then loadDashboard() end
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_adminStaffAction', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:adminStaffAction', false, data.action, data)
    notify(message, ok and 'success' or 'error')
    if ok then loadDashboard('admin') end
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_policeAdminConfig', function(_, cb)
    local config, reason = lib.callback.await('cm-police:server:adminConfig', false)
    cb({ ok = config ~= nil, config = config, message = reason })
end)
RegisterNUICallback('police_setPoliceAdminLocation', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local ok, message = lib.callback.await('cm-police:server:setAdminLocation', false, data.locationType, {
        x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped), name = data.name,
    })
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_previewPoliceAdminLocation', function(data, cb)
    local config = lib.callback.await('cm-police:server:adminConfig', false)
    local location = config and (data.locationType == 'booking_desk' and config.bookingDesk
        or data.locationType == 'jail_intake' and config.jailIntake
        or data.locationType == 'service_npc' and config.serviceNpc
        or data.locationType == 'armory_npc' and config.armoryNpc
        or data.locationType == 'storage_npc' and config.storageNpc)
    if not location then notify('That location is not configured.', 'error'); return cb({ ok = false }) end
    SetNewWaypoint(tonumber(location.x) + 0.0, tonumber(location.y) + 0.0)
    notify(('Waypoint set for %s.'):format(location.name or 'configured location'), 'success')
    cb({ ok = true })
end)
RegisterNUICallback('police_teleportPoliceAdminLocation', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:teleportAdminLocation', false, data.locationType)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_resetPoliceAdminLocation', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:resetAdminLocation', false, data.locationType)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_adminReleasePoliceCustody', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:adminReleaseCustody', false, data.characterId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_openPoliceClothingAdmin', function(_, cb)
    local ok, message = lib.callback.await('cm-police:server:openClothingAdmin', false)
    if not ok then notify(message or 'Could not open clothing management.', 'error') end
    if ok then closeMenu() end
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_savePoliceAdminRules', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:saveAdminRules', false, data)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_previewPoliceCinematic', function(data, cb)
    closeMenu()
    SetTimeout(250, function() if type(PolicePreviewCinematic) == 'function' then PolicePreviewCinematic(tostring(data.kind or 'booking')) end end)
    cb({ ok = true })
end)
RegisterNUICallback('police_adminPrisoners', function(_, cb)
    local rows, message = lib.callback.await('cm-police:server:adminPrisoners', false)
    cb({ ok = rows ~= nil, prisoners = rows or {}, message = message })
end)
RegisterNUICallback('police_adminPrisonAction', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:adminPrisonAction', false,
        data.action, data.characterId, tonumber(data.minutes))
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, message = message })
end)

-- MDT: pure NUI-callback relays, same shape as fleetCatalog above -- MDT
-- has no standalone command/thread of its own, unlike every other feature
-- this session, so it lives entirely here rather than in its own client file.
RegisterNUICallback('police_mdtWantedList', function(_, cb)
    local list = lib.callback.await('cm-police:server:mdtWantedList', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_mdtSearch', function(data, cb)
    local results = lib.callback.await('cm-police:server:mdtSearch', false, data.query)
    cb({ ok = results ~= nil, results = results or {} })
end)
RegisterNUICallback('police_mdtCitizenProfile', function(data, cb)
    local profile = lib.callback.await('cm-police:server:mdtCitizenProfile', false, data.characterId)
    cb({ ok = profile ~= nil, profile = profile })
end)
RegisterNUICallback('police_mdtVehicleSearch', function(data, cb)
    local vehicle = lib.callback.await('cm-police:server:mdtVehicleSearch', false, data.plate)
    cb({ ok = vehicle ~= nil, vehicle = vehicle })
end)
local function captureImpoundEvidence(data, cb)
    local message = tostring(data.message or '')
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local nearest, nearestDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local distance = #(origin - GetEntityCoords(vehicle))
            if distance <= (PoliceConfig.Impound.MaxDistance or 8.0)
                and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = vehicle, distance
            end
        end
    end
    if not nearest then
        notify('Stand near the searched vehicle before taking the impound photo.', 'error')
        return cb({ ok = false })
    end
    local plate = tostring(GetVehicleNumberPlateText(nearest) or ''):gsub('%s+', ''):upper()
    TriggerEvent('cm-police:client:closeMenu')
    Wait(300)
    impoundPhotoPreviousView = GetFollowPedCamViewMode()
    SetFollowPedCamViewMode(4)
    impoundPhotoMode = true
    SendNUIMessage({ cmInterface = "police", action = 'impoundCamera:show' })
    local accepted = false
    local deadline = GetGameTimer() + 60000
    while impoundPhotoMode and GetGameTimer() < deadline do
        if IsControlJustReleased(0, 191) or IsControlJustReleased(0, 201) then
            accepted = true
            break
        elseif IsControlJustReleased(0, 200) or IsControlJustReleased(0, 202) then
            break
        end
        Wait(0)
    end
    SendNUIMessage({ cmInterface = "police", action = 'impoundCamera:hide' })
    if not accepted then
        impoundPhotoMode = false
        SetFollowPedCamViewMode(impoundPhotoPreviousView ~= 4 and impoundPhotoPreviousView or 1)
        notify('Vehicle photo cancelled.', 'inform')
        return cb({ ok = false })
    end
    Wait(250)
    local ok, messageResult = lib.callback.await('cm-police:server:captureImpoundEvidence', false,
        NetworkGetNetworkIdFromEntity(nearest), plate, message)
    impoundPhotoMode = false
    SetFollowPedCamViewMode(impoundPhotoPreviousView ~= 4 and impoundPhotoPreviousView or 1)
    notify(messageResult or (ok and 'Impound evidence captured.' or 'Evidence capture failed.'), ok and 'success' or 'error')
    cb({ ok = ok == true })
end

RegisterNUICallback('police_mdtCaptureImpoundEvidence', captureImpoundEvidence)

RegisterNetEvent('cm-police:client:startSharedImpound', function()
    local state = LocalPlayer.state.cmLegalOrg
    if type(state) ~= 'table' or state.onDuty ~= true or state.suspended
        or (state.capabilities and state.capabilities.impound == false)
        or (state.isLeader ~= true and (state.permissions or {})['law.impound'] ~= true) then return end
    local input = lib.inputDialog('Start Vehicle Impound', {
        { type = 'textarea', label = 'Impound reason', required = true, min = 5, max = 500 },
    })
    if not input or not input[1] then return end
    captureImpoundEvidence({ message = input[1] }, function() end)
end)
RegisterNUICallback('police_mdtIssueVehicleLicense', function(data, cb)
    local ok, message, licenseNumber = lib.callback.await('cm-police:server:mdtIssueVehicleLicense', false, data.plate)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, licenseNumber = licenseNumber })
end)
RegisterNUICallback('police_mdtAddNote', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtAddNote', false, data.characterId, data.note)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtDeleteNote', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtDeleteNote', false, data.noteId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtSetCriminalStatus', function(data, cb)
    local ok, message, result = lib.callback.await('cm-police:server:mdtSetCriminalStatus', false, data.characterId, data.stars, data.wanted, data.reason)
    if not ok then notify(message, 'error') end
    cb({ ok = ok == true, stars = result and result.stars, wanted = result and result.wanted })
end)
RegisterNUICallback('police_mdtIssueFine', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtIssueFine', false, data.characterId, data.violationId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtIssueFines', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtIssueFines', false, data.characterId, data.violationIds)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtSetPhoto', function(data, cb)
    local ok, message, result = lib.callback.await('cm-police:server:mdtSetPhoto', false, data.characterId, data.url)
    if not ok then notify(message, 'error') end
    cb({ ok = ok == true, photoUrl = result and result.photoUrl })
end)
RegisterNUICallback('police_mdtSetLicenseStatus', function(data, cb)
    local ok, message, result = lib.callback.await('cm-police:server:mdtSetLicenseStatus', false, data.characterId, data.licenseType, data.status, data.reason)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, license = result })
end)
RegisterNUICallback('police_mdtAddEvidence', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtAddEvidence', false, data.characterId, data.url, data.caption)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtDeleteEvidence', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtDeleteEvidence', false, data.evidenceId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtIssueBolo', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtIssueBolo', false, data.description, data.plate)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtClearBolo', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtClearBolo', false, data.boloId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtActiveBolos', function(_, cb)
    local list = lib.callback.await('cm-police:server:mdtActiveBolos', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_mdtBoloHistory', function(_, cb)
    local list = lib.callback.await('cm-police:server:mdtBoloHistory', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_mdtFileUseOfForce', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtFileUseOfForce', false, data.subject, data.forceType, data.narrative)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_mdtUseOfForceHistory', function(_, cb)
    local list = lib.callback.await('cm-police:server:mdtUseOfForceHistory', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_mdtDeleteUseOfForce', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:mdtDeleteUseOfForce', false, data.reportId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)

-- 911 dispatch (F7 tab): pure NUI-callback relays, same shape as the MDT
-- ones above -- server/dispatch.lua owns every check and the actual state.
RegisterNUICallback('police_dispatchActiveCalls', function(_, cb)
    local list = lib.callback.await('cm-law:server:dispatchActiveCalls', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_dispatchHistory', function(_, cb)
    local list = lib.callback.await('cm-law:server:dispatchHistory', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_dispatchAccept', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:acceptDispatchCall', false, data.callId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_dispatchEnRoute', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setDispatchResponseStatus', false, data.callId, 'en_route')
    if ok and PoliceSetDispatchRoute then
        local routed = PoliceSetDispatchRoute(data.callId)
        message = routed and (message .. ' GPS route set.') or (message .. ' Dispatch location is no longer available.')
    end
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_dispatchResolve', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:resolveDispatchCall', false, data.callId, data.resolution)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)

-- Armory (F7 tab): pure NUI-callback relays, same shape as dispatch/MDT
-- above -- server/armory.lua owns every check and the actual state.
RegisterNUICallback('police_armoryAvailable', function(_, cb)
    local list = lib.callback.await('cm-police:server:armoryAvailable', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_armoryManageList', function(_, cb)
    local list = lib.callback.await('cm-police:server:armoryManageList', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_armoryCheckout', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:armoryCheckout', false, data.itemName)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_setArmoryWeapon', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:setArmoryWeapon', false, data.itemName, data.enabled == true)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_loadArmoryStock', function(_, cb)
    local ok, message = lib.callback.await('cm-police:server:loadArmoryStock', false)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, message = message })
end)

-- ALPR camera management (Administration tab). addAlprCamera captures the
-- officer's current position client-side, same trust level set_meeting/
-- set_holding_cell already use for their own "stand here" buttons.
RegisterNUICallback('police_alprCameraList', function(_, cb)
    local list = lib.callback.await('cm-police:server:alprCameraList', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_addAlprCamera', function(data, cb)
    local coords = GetEntityCoords(PlayerPedId())
    local ok, message = lib.callback.await('cm-police:server:addAlprCamera', false, data.label, coords.x, coords.y, coords.z)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_removeAlprCamera', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:removeAlprCamera', false, data.cameraId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)

-- Barricade model catalog management (Overview page's Barricades card) --
-- same list/add/remove shape as the ALPR camera bridges above.
RegisterNUICallback('police_barricadeCatalogList', function(_, cb)
    local list = lib.callback.await('cm-police:server:barricadeCatalogList', false)
    cb({ ok = list ~= nil, list = list or {} })
end)
RegisterNUICallback('police_addBarricadeModel', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:addBarricadeModel', false, data.modelName)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)
RegisterNUICallback('police_removeBarricadeModel', function(data, cb)
    local ok, message = lib.callback.await('cm-police:server:removeBarricadeModel', false, data.catalogId)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)

RegisterNUICallback('police_officerStats', function(_, cb)
    local list = lib.callback.await('cm-police:server:officerStats', false)
    cb({ ok = list ~= nil, list = list or {} })
end)

-- Purely local -- no server call. Trying on a catalog piece is the exact
-- same native calls applyOutfit() already makes per-component, just for
-- one item at a time; nothing is persisted until the existing "Save
-- current clothing" button (save_outfit_preset) captures whatever the ped
-- ends up wearing.
RegisterNUICallback('police_previewWardrobeItem', function(data, cb)
    local ped = PlayerPedId()
    local componentIndex = tonumber(data.componentIndex) or 0
    local drawableId = tonumber(data.drawableId) or 0
    local textureId = tonumber(data.textureId) or 0
    if tostring(data.componentType) == 'prop' then
        SetPedPropIndex(ped, componentIndex, drawableId, textureId, true)
    else
        SetPedComponentVariation(ped, componentIndex, drawableId, textureId, 0)
    end
    cb({ ok = true })
end)

RegisterNetEvent('cm-police:client:invite', function(data)
    CreateThread(function()
        local accepted = PoliceConfirm('Police Invitation', ('%s invited you to join the Police Department as %s.'):format(tostring(data.inviter or 'Police'), tostring(data.rank or 'Cadet')), 'Join Police', 'Decline')
        local ok, message = lib.callback.await('cm-police:server:respondInvite', false, accepted)
        notify(message, ok and 'success' or 'error')
    end)
end)

RegisterNetEvent('cm-police:client:forceDutyCleanup', function()
    closeMenu()
    SetNuiFocus(false, false)
    SendNUIMessage({ cmInterface = "police", action = 'close' })
    if lib.progressActive and lib.progressActive() then lib.cancelProgress() end
end)

-- Restore from cm-inventory's authoritative equipped clothing whenever the
-- replicated Police state transitions from on duty to off duty. Do not apply
-- civilianOutfit here: after a resource restart that local snapshot can be
-- captured while the Police uniform is already visible and would put the
-- uniform straight back on after Inventory restored civilian clothing.
local lastReplicatedDuty = type(LocalPlayer.state.cmPolice) == 'table'
    and LocalPlayer.state.cmPolice.onDuty == true
AddStateBagChangeHandler('cmPolice', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    local nextDuty = type(value) == 'table' and value.onDuty == true
    if lastReplicatedDuty and not nextDuty then
        civilianOutfit = nil
        TriggerEvent('cm-inventory:client:restoreEquippedClothing')
        CreateThread(function()
            Wait(500)
            TriggerEvent('cm-inventory:client:requestEquipmentRefresh')
        end)
    end
    lastReplicatedDuty = nextDuty
end)

-- Reconciliation on (re)load: a resource restart wipes the client's local
-- civilianOutfit/appearance state even though the database still says the
-- member is on duty. Reapply their duty outfit once the state bag confirms
-- they are still on duty, so a restart mid-shift does not silently drop them
-- back into whatever clothes they happened to be wearing at the time.
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        local state = LocalPlayer.state.cmPolice
        if type(state) ~= 'table' or state.onDuty ~= true then return end
        local outfit = lib.callback.await('cm-police:server:dutyOutfit', false, sex())
        if outfit then
            civilianOutfit = civilianOutfit or captureOutfit()
            applyOutfit(outfit)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ cmInterface = "police", action = 'close' })
end)

RegisterNUICallback('police_escape', function(_, cb) closeMenu(); cb({ ok = true }) end)
