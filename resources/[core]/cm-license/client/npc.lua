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
NPC.PublicWorld = false
NPC.DialoguePending = false
NPC.LicenseNuiBlockingInteraction = false
NPC.LicenseBlip = nil
local LICENSE_INTERACT_OWNER = 'cm-license:npc'
local LICENSE_UI_SUPPRESSION_OWNER = 'cm-license:nui'

local function setPromptSuppressed(suppressed)
    pcall(function() exports['cm-ui']:SetInteractSuppressed(LICENSE_UI_SUPPRESSION_OWNER, suppressed) end)
end

local function dialogueOpen()
    local ok, open = pcall(function() return exports['cm-ui']:IsNpcDialogueOpen() end)
    return ok and open == true
end

local function hidePrompt()
    if NPC.PromptVisible then
        pcall(function() exports['cm-ui']:HideInteract(LICENSE_INTERACT_OWNER) end)
        NPC.PromptVisible = false
    end
end

local function setPromptVisible(visible, definition)
    if visible and not NPC.PromptVisible then
        exports['cm-ui']:ShowInteract({
            owner = LICENSE_INTERACT_OWNER,
            priority = 10,
            key = 'E', label = 'LICENCE CENTRE',
            name = definition.name or NPC.Name,
            role = definition.role or NPC.Role,
        })
        NPC.PromptVisible = true
    elseif not visible then
        hidePrompt()
    end
end

local function removeBlip()
    if NPC.LicenseBlip and DoesBlipExist(NPC.LicenseBlip) then RemoveBlip(NPC.LicenseBlip) end
    NPC.LicenseBlip = nil
end

local function createBlip(definitions)
    removeBlip()
    local config = CMLicenseConfig.NPC.Blip or {}
    local definition = definitions and definitions[1]
    local coords = definition and definition.coords
    if config.enabled == false or not coords then return end

    NPC.LicenseBlip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetBlipSprite(NPC.LicenseBlip, tonumber(config.sprite) or 61)
    SetBlipColour(NPC.LicenseBlip, tonumber(config.color) or 3)
    SetBlipScale(NPC.LicenseBlip, tonumber(config.scale) or 0.85)
    SetBlipAsShortRange(NPC.LicenseBlip, config.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(config.label or 'License Centre'))
    EndTextCommandSetBlipName(NPC.LicenseBlip)
end

function NPC.SetPublicWorld(isPublic, requestDefinitions)
    isPublic = isPublic == true
    if NPC.PublicWorld == isPublic then
        if isPublic and requestDefinitions ~= false and #NPC.Peds == 0 then
            TriggerServerEvent('cm-license:server:requestNPCDefinitions')
        end
        return
    end

    NPC.PublicWorld = isPublic
    NPC.DialoguePending = false
    hidePrompt()

    if not isPublic then
        NPC.LicenseNuiBlockingInteraction = false
        setPromptSuppressed(false)
        if dialogueOpen() then pcall(function() exports['cm-ui']:CancelNpcDialogue() end) end
        SendNuiMessage(json.encode({ type = 'forceClose' }))
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        NPC.DespawnAll()
        removeBlip()
        return
    end

    if requestDefinitions ~= false then
        TriggerServerEvent('cm-license:server:requestNPCDefinitions')
    end
end

function NPC.Init()
    NPC.PublicWorld = false
    TriggerServerEvent('cm-license:server:requestNPCDefinitions')
    CMLog('NPC system initialized')
end

RegisterNetEvent(Constants.EVENTS.CLIENT.PUBLIC_WORLD_CHANGED, function(isPublic, requestDefinitions)
    NPC.SetPublicWorld(isPublic == true, requestDefinitions)
end)

function NPC.DespawnAll()
    hidePrompt()
    for _, ped in ipairs(NPC.Peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    NPC.Peds = {}
    NPC.Definitions = {}
    NPC.NearbyPed = nil
    removeBlip()
end

RegisterNetEvent('cm-license:client:setNPCDefinitions', function(definitions)
    if not NPC.PublicWorld then return end
    NPC.DespawnAll()
    for _, definition in ipairs(definitions or {}) do
        local coords = definition.coords
        local ped = coords and NPC.Spawn(definition.model, coords, coords.heading)
        if ped then
            NPC.Peds[#NPC.Peds + 1] = ped
            NPC.Definitions[ped] = definition
        end
    end
    createBlip(definitions)
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
    if not NPC.PublicWorld or not NPC.NearbyPed or dialogueOpen() or NPC.DialoguePending then return end
    NPC.DialoguePending = true
    TriggerServerEvent('cm-license:server:getNPCLocations')
    SetTimeout(2500, function()
        if NPC.DialoguePending then NPC.DialoguePending = false end
    end)
end

-- Cinematic license-selection screen (cm-ui's shared dialogue component).
-- One choice per available license type plus "My Licenses"; picking a
-- license closes this screen and shows the test-confirmation popup.
function NPC.ShowLicenseMenu(licenses)
    local ped = NPC.NearbyPed
    if not NPC.PublicWorld or not ped or not DoesEntityExist(ped) then
        NPC.DialoguePending = false
        return
    end
    NPC.DialoguePending = false
    NPC.PendingLicenses = licenses or {}

    local definition = NPC.Definitions[ped] or {}
    local choices = {}
    for _, license in ipairs(NPC.PendingLicenses) do
        choices[#choices + 1] = {
            id = license.license_type,
            label = license.label,
            description = license.menuDescription or ('$%s'):format(tostring(license.price)),
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

    exports['cm-ui']:OpenNpcDialogue(ped, {
        name = definition.name or NPC.Name,
        role = definition.role or NPC.Role,
        quote = 'Good afternoon. Which license would you like to apply for today?',
        choices = choices,
        closeEvent = 'cm-license:client:dialogueDismissed',
        choiceColumns = 2,
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
    NPC.DialoguePending = false
    NPC.LicenseNuiBlockingInteraction = true
    setPromptSuppressed(true)
    SendNuiMessage(json.encode({
        type = 'showMyLicenses',
        licenses = licenses
    }))
    SetTimeout(0, function()
        if NPC.LicenseNuiBlockingInteraction then SetNuiFocus(true, true) end
    end)
end

-- Show test confirmation dialog. Duration comes from the same config value the
-- server enforces, so the number on screen is the number that applies.
function NPC.ShowTestConfirmation(license)
    NPC.DialoguePending = false
    NPC.LicenseNuiBlockingInteraction = true
    setPromptSuppressed(true)
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
    SetTimeout(0, function()
        if NPC.LicenseNuiBlockingInteraction then SetNuiFocus(true, true) end
    end)
end

-- Close menu
function NPC.CloseMenu()
    NPC.DialoguePending = false
    NPC.LicenseNuiBlockingInteraction = false
    setPromptSuppressed(false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    exports['cm-ui']:CancelNpcDialogue()
    TriggerEvent('cm-hud:client:showAfterUi', 'cm-license:npc-dialogue')
end


CreateThread(function()
    while true do
        local wait, playerCoords = 750, GetEntityCoords(PlayerPedId())
        local showRange = tonumber(CMLicenseConfig.NPC.InteractionDistance) or 3.0
        local hideRange = tonumber(CMLicenseConfig.NPC.InteractionHideDistance) or (showRange + 0.5)
        local previousPed = NPC.NearbyPed
        local nextPed
        for _, ped in ipairs(NPC.Peds) do
            if DoesEntityExist(ped) then
                local range = ped == previousPed and hideRange or showRange
                if #(playerCoords-GetEntityCoords(ped)) <= range then
                    nextPed = ped
                    break
                end
            end
        end
        NPC.NearbyPed = nextPed
        local canInteract = NPC.PublicWorld and NPC.NearbyPed and not Client.IsInTest()
            and not NPC.DialoguePending and not NPC.LicenseNuiBlockingInteraction and not dialogueOpen()
        if canInteract then
            wait=0
            local definition=NPC.Definitions[NPC.NearbyPed] or {}
            local pedCoords=GetEntityCoords(NPC.NearbyPed)
            SetDrawOrigin(pedCoords.x,pedCoords.y,pedCoords.z+1.15,0)
            SetTextFont(4); SetTextScale(0.0,0.31); SetTextCentre(true); SetTextOutline(); SetTextColour(255,255,255,245)
            BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(definition.name or NPC.Name)
            EndTextCommandDisplayText(0.0,0.0); ClearDrawOrigin()
            setPromptVisible(true, definition)
        else
            setPromptVisible(false)
        end
        Wait(wait)
    end
end)

return NPC
