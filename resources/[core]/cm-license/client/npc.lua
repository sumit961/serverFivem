-- CM License System — Client NPC Interaction
--
-- Interact prompt + the cinematic license-selection screen are now provided
-- by cm-ui (exports['cm-ui']:ShowInteract/HideInteract/OpenNpcDialogue) so
-- this NPC looks and behaves the same as any other cm-ui-powered NPC (e.g.
-- cm-police). See cm-ui/docs/CM_UI_USAGE.md for the full API.

NPC = {}

-- NPC state tracking
NPC.LoadedModels = {}
NPC.Peds = {}
NPC.Definitions = {}
NPC.NearbyPed = nil
NPC.Name = 'Alex Morgan'
NPC.Role = 'CM License Instructor'
NPC.PromptVisible = false
NPC.PendingLicenses = {}

function NPC.Init()
    TriggerServerEvent('cm-license:server:requestNPCDefinitions')
    CMLog('NPC system initialized')
end

function NPC.DespawnAll()
    for _, ped in ipairs(NPC.Peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    NPC.Peds = {}
    NPC.Definitions = {}
    NPC.NearbyPed = nil
end

RegisterNetEvent('cm-license:client:setNPCDefinitions', function(definitions)
    NPC.DespawnAll()
    for _, definition in ipairs(definitions or {}) do
        local coords = definition.coords
        local ped = coords and NPC.Spawn(definition.model, coords, coords.heading)
        if ped then
            NPC.Peds[#NPC.Peds + 1] = ped
            NPC.Definitions[ped] = definition
        end
    end
end)

-- Load NPC model
function NPC.LoadModel(modelName)
    if not modelName then return false end

    local modelHash = GetHashKey(modelName)
    if NPC.LoadedModels[modelHash] then
        return true
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        NPC.LoadedModels[modelHash] = true
        return true
    end

    print('^1[CM-License]^7 Failed to load NPC model: ' .. modelName)
    return false
end

-- Spawn NPC
function NPC.Spawn(model, coords, heading)
    if not NPC.LoadModel(model) then
        return nil
    end

    local modelHash = GetHashKey(model)
    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z - 1.0, heading or 0.0, false, false)

    if not DoesEntityExist(ped) then
        return nil
    end

    -- Configure NPC
    SetBlockingOfNonTemporaryEvents(ped, true)
    if coords.scenario then TaskStartScenarioInPlace(ped, coords.scenario, 0, true) end
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)

    return ped
end

-- Check if player is near NPC and show interaction prompt
function NPC.CheckNPCInteraction()
    if not NPC.NearbyPed then return end
    if NPC.PromptVisible then exports['cm-ui']:HideInteract(); NPC.PromptVisible = false end
    TriggerServerEvent('cm-license:server:getNPCLocations')
end

-- Cinematic license-selection screen (cm-ui's shared dialogue component).
-- One choice per available license type plus "My Licenses"; picking a
-- license closes this screen and shows the test-confirmation popup.
function NPC.ShowLicenseMenu(licenses)
    local ped = NPC.NearbyPed
    if not ped or not DoesEntityExist(ped) then return end
    NPC.PendingLicenses = licenses or {}

    local definition = NPC.Definitions[ped] or {}
    local choices = {}
    for _, license in ipairs(NPC.PendingLicenses) do
        choices[#choices + 1] = {
            id = license.license_type,
            label = license.label,
            description = ('$%s'):format(tostring(license.price)),
            icon = license.vehicle_category,
            event = 'cm-license:client:dialogueChoice',
            payload = { licenseType = license.license_type },
        }
    end
    choices[#choices + 1] = {
        id = 'my_licenses',
        label = 'My Licenses',
        description = 'View your current licenses',
        event = 'cm-license:client:dialogueMyLicenses',
    }

    TriggerEvent('cm-hud:client:hideForUi', 'cm-license:npc-dialogue')
    exports['cm-ui']:OpenNpcDialogue(ped, {
        name = definition.name or NPC.Name,
        role = definition.role or NPC.Role,
        quote = 'Good afternoon. Which license would you like to apply for today?',
        choices = choices,
        closeEvent = 'cm-license:client:dialogueDismissed',
    })
end

AddEventHandler('cm-license:client:dialogueChoice', function(payload)
    payload = type(payload) == 'table' and payload or {}
    local license
    for _, entry in ipairs(NPC.PendingLicenses) do
        if entry.license_type == payload.licenseType then license = entry break end
    end
    if license then NPC.ShowTestConfirmation(license) end
end)

AddEventHandler('cm-license:client:dialogueMyLicenses', function()
    TriggerServerEvent('cm-license:server:requestMyLicenses')
end)

AddEventHandler('cm-license:client:dialogueDismissed', function()
    NPC.CloseMenu()
end)

-- Show my licenses dialog via NUI
function NPC.ShowMyLicenses(licenses)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'showMyLicenses',
        licenses = licenses
    }))
end

-- Show test confirmation dialog. Duration comes from the same config value the
-- server enforces, so the number on screen is the number that applies.
function NPC.ShowTestConfirmation(license)
    SetNuiFocus(true, true)
    SendNuiMessage(json.encode({
        type = 'showTestConfirmation',
        license_type = license.license_type,
        category = license.vehicle_category,
        label = license.label,
        price = license.price,
        validDays = license.valid_days,
        vehicleModel = license.vehicle_model,
        durationMinutes = tonumber(CMLicenseConfig.TestSession.TimeoutMinutes) or 20,
        maxMistakes = license.vehicle_category == Constants.VEHICLE_CATEGORY.GROUND
            and (tonumber(CMLicenseConfig.TestSession.MaxMistakes) or 0) or 0
    }))
end

-- Close menu
function NPC.CloseMenu()
    SetNuiFocus(false, false)
    exports['cm-ui']:CancelNpcDialogue()
    FreezeEntityPosition(PlayerPedId(), false)
    TriggerEvent('cm-hud:client:showAfterUi', 'cm-license:npc-dialogue')
end


CreateThread(function()
    while true do
        local wait, playerCoords = 750, GetEntityCoords(PlayerPedId())
        local range = tonumber(CMLicenseConfig.NPC.InteractionDistance) or 3.0
        NPC.NearbyPed = nil
        for _, ped in ipairs(NPC.Peds) do
            if DoesEntityExist(ped) and #(playerCoords-GetEntityCoords(ped))<=range then NPC.NearbyPed=ped; break end
        end
        if NPC.NearbyPed and not Client.IsInTest() then
            wait=0
            local definition=NPC.Definitions[NPC.NearbyPed] or {}
            local pedCoords=GetEntityCoords(NPC.NearbyPed)
            SetDrawOrigin(pedCoords.x,pedCoords.y,pedCoords.z+1.15,0)
            SetTextFont(4); SetTextScale(0.0,0.31); SetTextCentre(true); SetTextOutline(); SetTextColour(255,255,255,245)
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(definition.name or NPC.Name)
            EndTextCommandDisplayText(0.0,0.0); ClearDrawOrigin()
            if not NPC.PromptVisible then
                exports['cm-ui']:ShowInteract({ key = 'E', label = 'INTERACTION', name = definition.name or NPC.Name, role = definition.role or NPC.Role })
                NPC.PromptVisible=true
            end
        elseif NPC.PromptVisible then exports['cm-ui']:HideInteract(); NPC.PromptVisible=false end
        Wait(wait)
    end
end)

return NPC
