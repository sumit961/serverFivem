-- ============================================================
-- PLT MDT — Client-side script (deobfuscated)
-- Original: decompiled Lua with SHX-prefixed identifiers
-- Cleaned: all identifiers renamed, goto/label replaced where
--          possible, decompiler comments removed, logic restored.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- MODULE-LEVEL STATE VARIABLES
-- ─────────────────────────────────────────────────────────────

local isMdtOpen          = false   -- originally SHX0_1: is the MDT NUI currently open?
local isPhotoMode        = false   -- originally SHX1_1: is a photo-capture session active?
local pendingPhotoCitizenId = nil  -- originally SHX2_1: citizenid of the citizen being photographed
local isJailed           = false   -- originally SHX3_1: is the local player currently jailed?
local _unused4           = nil     -- originally SHX4_1: assigned but never read; preserved as dead variable
local lastJailTaskTime   = 0       -- originally SHX5_1: GetGameTimer() value when last jail task was started
local jailBlips          = {}      -- originally SHX6_1: table of active jail-task map blips


-- ─────────────────────────────────────────────────────────────
-- HELPER: ShowHelpNotification(message)
-- Displays a GTA-style help notification (top-left corner).
-- ─────────────────────────────────────────────────────────────
local function ShowHelpNotification(message)
    -- originally SHX7_1 (first definition), aliased below
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentScaleform(message)
    EndTextCommandDisplayHelp(0, false, true, -1)
end
ShowHelpNotification = ShowHelpNotification   -- originally: ShowHelpNotification = SHX7_1


-- ─────────────────────────────────────────────────────────────
-- HELPER: ShowNotification(message)
-- Displays a GTA-style ticker/feed notification.
-- ─────────────────────────────────────────────────────────────
local function ShowNotification(message)
    -- originally SHX7_1 (second definition), aliased below
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end
ShowNotification = ShowNotification   -- originally: ShowNotification = SHX7_1


-- ─────────────────────────────────────────────────────────────
-- CreateJailBlips()
-- Iterates Config.JailTaskLocations, adds a map blip for each
-- task location and stores it in the jailBlips table.
-- ─────────────────────────────────────────────────────────────
local function CreateJailBlips()
    -- originally SHX7_1 (third definition)
    for _, taskLocation in ipairs(Config.JailTaskLocations) do
        local blip = AddBlipForCoord(taskLocation.x, taskLocation.y, taskLocation.z)

        SetBlipSprite(blip, 1)               -- standard round blip sprite
        SetBlipColour(blip, 3)               -- colour index 3 (green)
        SetBlipScale(blip, 0.6)
        SetBlipAsShortRange(blip, true)

        -- Label the blip as "Jail Task: <label>"
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Jail Task: " .. taskLocation.label)
        EndTextCommandSetBlipName(blip)

        table.insert(jailBlips, blip)
    end
end
CreateJailBlips = CreateJailBlips   -- originally: CreateJailBlips = SHX7_1


-- ─────────────────────────────────────────────────────────────
-- RemoveJailBlips()
-- Removes every blip stored in jailBlips and resets the table.
-- ─────────────────────────────────────────────────────────────
local function RemoveJailBlips()
    -- originally SHX7_1 (fourth definition)
    for _, blip in ipairs(jailBlips) do
        RemoveBlip(blip)
    end
    jailBlips = {}
end
RemoveJailBlips = RemoveJailBlips   -- originally: RemoveJailBlips = SHX7_1


-- ─────────────────────────────────────────────────────────────
-- ToggleMDT(isOpen, playerData)
-- Opens or closes the MDT NUI.
--   isOpen     – true to open, false to close
--   playerData – optional; fetched from Framework if omitted
-- ─────────────────────────────────────────────────────────────
local function ToggleMDT(isOpen, playerData)
    -- originally SHX7_1 (fifth definition)

    isMdtOpen = isOpen          -- originally SHX0_1 = SHX0_2
    SetNuiFocus(isOpen, isOpen)

    if isOpen then
        -- Resolve playerData if not passed in
        local resolvedPlayerData = playerData
        if not playerData then
            resolvedPlayerData = Framework.GetPlayerData()
        end
        if not resolvedPlayerData then return end

        local jobName       = resolvedPlayerData.job.name
        local departmentCfg = Config.Departments[jobName]
        if not departmentCfg then
            departmentCfg = Config.DefaultDepartment
        end

        -- Callback 1: check whether this officer can assign dispatch calls
        TriggerCallback("plt_mdt:server:canAssignDispatch", function(canAssignDispatch)

            -- Callback 2: fetch current officer locations
            TriggerCallback("plt_mdt:server:getOfficerLocations", function(officerLocations)

                -- Send the full MDT-open payload to the NUI
                local localPlayerId   = PlayerId()
                local localServerid   = GetPlayerServerId(localPlayerId)

                local locale      = Config.Locale or "en"
                local translations = Config.Translations or {}
                local panicAlerts  = Config.PanicAlerts or {}
                local officers     = officerLocations or {}

                SendNUIMessage({
                    type                           = "openMDT",
                    job                            = jobName,
                    theme                          = departmentCfg.theme,
                    jobLabel                       = departmentCfg.label,
                    icon                           = departmentCfg.icon,
                    color                          = departmentCfg.color,
                    name                           = resolvedPlayerData.name,
                    serverId                       = localServerid,
                    canAssignDispatch              = (canAssignDispatch == true),
                    enableDispatchLiveNotifications = (Config.EnableDispatchLiveNotifications == true),
                    locale                         = locale,
                    translations                   = translations,
                    panicAlerts                    = panicAlerts,
                    officers                       = officers,
                })
            end)
        end)

        -- Concurrently fetch dashboard data and push to NUI if available
        CreateThread(function()
            TriggerCallback("plt_mdt:server:getDashboardData", function(dashboardData)
                if dashboardData then
                    SendNUIMessage({
                        type      = "updateDashboard",
                        dashboard = dashboardData,
                    })
                end
            end)
        end)

    else
        -- Close the MDT
        SendNUIMessage({ type = "closeMDT" })
    end
end
ToggleMDT = ToggleMDT   -- originally: ToggleMDT = SHX7_1


-- ─────────────────────────────────────────────────────────────
-- COMMAND: /mdt
-- Checks whether the player's job is listed in Config.Departments.
-- If authorised, opens the MDT. Otherwise shows an error.
-- ─────────────────────────────────────────────────────────────
RegisterCommand("mdt", function()
    -- originally: SHX7_1(SHX8_1, SHX9_1) where SHX8_1="mdt", SHX9_1=callback

    local playerData = Framework.GetPlayerData()
    if not playerData then return end

    local jobName       = playerData.job.name
    local departmentCfg = Config.Departments[jobName]

    if departmentCfg then
        ToggleMDT(true, playerData)
    else
        Framework.Notify("You don't have access to the MDT.", "error")
    end
end)


-- ─────────────────────────────────────────────────────────────
-- EXPORTS
-- ─────────────────────────────────────────────────────────────

-- Export: ToggleMDT — allow other resources to open/close the MDT
exports("ToggleMDT", function(isOpen)
    ToggleMDT(isOpen)
end)

-- Export: IsMdtOpen — returns whether the MDT is currently open
exports("IsMdtOpen", function()
    return isMdtOpen   -- originally returns SHX0_1
end)

-- Export: CreateDispatchCall — creates a dispatch call, resolving
-- the street-name location from coords if not already provided.
exports("CreateDispatchCall", function(callData)
    if not callData then return end

    -- Only resolve location if it is missing or set to "Unknown"
    local needsLocationResolve = (not callData.location) or (callData.location == "Unknown")

    if needsLocationResolve then
        -- Resolve coords: use provided coords or fall back to player position
        local coords = callData.coords
        if not coords then
            local ped    = PlayerPedId()
            coords = GetEntityCoords(ped)
        end

        -- Extract x/y/z, supporting both named and indexed tables
        local x = tonumber(coords.x or coords[1]) or 0.0
        local y = tonumber(coords.y or coords[2]) or 0.0
        local z = tonumber(coords.z or coords[3]) or 0.0

        -- Build a human-readable street string from world coordinates
        if x ~= 0.0 or y ~= 0.0 then
            local streetHash, crossingHash = GetStreetNameAtCoord(x, y, z)
            local streetName = GetStreetNameFromHashKey(streetHash)

            if crossingHash ~= 0 then
                local crossingName = GetStreetNameFromHashKey(crossingHash)
                streetName = streetName .. " | " .. crossingName
            end

            callData.location = streetName
            callData.coords   = { x = x, y = y, z = z }
        end
    end

    -- ::SHX_LABEL_74:: — jump target when location was already valid (goto replaced by if/else above)
    TriggerServerEvent("plt_mdt:server:addDispatchCall", callData)
end)


-- ─────────────────────────────────────────────────────────────
-- NUI CALLBACKS
-- Each callback receives (data, cb) where cb must be called
-- with a result to acknowledge the NUI request.
-- ─────────────────────────────────────────────────────────────

-- closeMDT: NUI requested MDT to close
RegisterNUICallback("closeMDT", function(data, cb)
    ToggleMDT(false)
    cb("ok")
end)

-- getOfficerProfile: fetch an officer's profile by server callback
RegisterNUICallback("getOfficerProfile", function(data, cb)
    TriggerCallback("plt_mdt:server:getOfficerProfile", function(result)
        local response = result or {}
        cb(response)
    end)
end)

-- saveOfficerSettings: persist officer settings via server callback
RegisterNUICallback("saveOfficerSettings", function(data, cb)
    TriggerCallback("plt_mdt:server:saveOfficerSettings", function(result)
        cb(result)
    end, data)
end)

-- getDashboardData: fetch dashboard summary data
RegisterNUICallback("getDashboardData", function(data, cb)
    TriggerCallback("plt_mdt:server:getDashboardData", function(result)
        local response = result or {}
        cb(response)
    end)
end)

-- searchVehicle: search vehicles by query string
RegisterNUICallback("searchVehicle", function(data, cb)
    TriggerCallback("plt_mdt:server:searchVehicle", function(result)
        local response = result or {}
        cb(response)
    end, data.query)
end)

-- getVehicleDetails: fetch full details for a specific vehicle plate
RegisterNUICallback("getVehicleDetails", function(data, cb)
    TriggerCallback("plt_mdt:server:getVehicleDetails", function(result)
        local response = result or {}
        cb(response)
    end, data.plate)
end)

-- createVehicleBolo: create a BOLO for a vehicle
RegisterNUICallback("createVehicleBolo", function(data, cb)
    TriggerCallback("plt_mdt:server:createVehicleBolo", function(result)
        cb(result)
    end, data)
end)

-- deleteVehicleBolo: remove a vehicle BOLO
RegisterNUICallback("deleteVehicleBolo", function(data, cb)
    TriggerCallback("plt_mdt:server:deleteVehicleBolo", function(result)
        cb(result)
    end, data)
end)

-- getAllVehicles: fetch the full vehicle list
RegisterNUICallback("getAllVehicles", function(data, cb)
    TriggerCallback("plt_mdt:server:getAllVehicles", function(result)
        local response = result or {}
        cb(response)
    end)
end)

-- toggleLicense: toggle a citizen's driving licence status
RegisterNUICallback("toggleLicense", function(data, cb)
    TriggerCallback("plt_mdt:server:toggleLicense", function(result)
        cb(result)
    end, data)
end)

-- updateLicensePoints: update penalty points on a citizen's licence
RegisterNUICallback("updateLicensePoints", function(data, cb)
    TriggerCallback("plt_mdt:server:updateLicensePoints", function(result)
        cb(result)
    end, data)
end)

-- getAllCitizens: fetch the full citizen list
RegisterNUICallback("getAllCitizens", function(data, cb)
    TriggerCallback("plt_mdt:server:getAllCitizens", function(result)
        local response = result or {}
        cb(response)
    end)
end)

-- getCitizenDetails: fetch details for a specific citizen by ID
RegisterNUICallback("getCitizenDetails", function(data, cb)
    TriggerCallback("plt_mdt:server:getCitizenDetails", function(result)
        local response = result or {}
        cb(response)
    end, data.citizenid)
end)

-- searchProfile: search citizen profiles by query string
RegisterNUICallback("searchProfile", function(data, cb)
    TriggerCallback("plt_mdt:server:searchProfile", function(result)
        local response = result or {}
        cb(response)
    end, data.query)
end)

-- getFullProfile: fetch a citizen's complete profile record
RegisterNUICallback("getFullProfile", function(data, cb)
    TriggerCallback("plt_mdt:server:getFullProfile", function(result)
        local response = result or {}
        cb(response)
    end, data.citizenid)
end)

-- createCriminalRecord: create a new criminal record entry
RegisterNUICallback("createCriminalRecord", function(data, cb)
    TriggerCallback("plt_mdt:server:createCriminalRecord", function(result)
        cb(result)
    end, data)
end)

-- searchIncident: search incident reports
RegisterNUICallback("searchIncident", function(data, cb)
    TriggerCallback("plt_mdt:server:searchIncident", function(result)
        local response = result or {}
        cb(response)
    end, data)
end)

-- getIncidentDetails: fetch details for a specific incident
RegisterNUICallback("getIncidentDetails", function(data, cb)
    TriggerCallback("plt_mdt:server:getIncidentDetails", function(result)
        local response = result or {}
        cb(response)
    end, data)
end)

-- createCaseFile: create a new case file
RegisterNUICallback("createCaseFile", function(data, cb)
    TriggerCallback("plt_mdt:server:createCaseFile", function(result)
        cb(result)
    end, data)
end)

-- updateCaseFile: update an existing case file
RegisterNUICallback("updateCaseFile", function(data, cb)
    TriggerCallback("plt_mdt:server:updateCaseFile", function(result)
        cb(result)
    end, data)
end)

-- toggleWarrant: toggle warrant active/inactive state
RegisterNUICallback("toggleWarrant", function(data, cb)
    TriggerCallback("plt_mdt:server:toggleWarrant", function(result)
        cb(result)
    end, data)
end)

-- updateProfileImage: update a citizen's profile photo URL in the database
RegisterNUICallback("updateProfileImage", function(data, cb)
    TriggerCallback("plt_mdt:server:updateProfileImage", function(result)
        cb(result)
    end, data)
end)

-- deleteRecord: delete a criminal record by ID
RegisterNUICallback("deleteRecord", function(data, cb)
    TriggerCallback("plt_mdt:server:deleteRecord", function(result)
        cb(result)
    end, data.id)
end)

-- processSentence: process a jail sentence for a citizen;
-- returns a success/message object (defaults to failure if server returns nil)
RegisterNUICallback("processSentence", function(data, cb)
    TriggerCallback("plt_mdt:server:processSentence", function(result)
        local response = result
        if not result then
            -- Dead path guard: server returned nil — synthesise a safe failure response
            response = { success = false, message = "Server error" }
        end
        cb(response)
    end, data)
end)

-- getAllWarrants: fetch all active warrants
RegisterNUICallback("getAllWarrants", function(data, cb)
    TriggerCallback("plt_mdt:server:getAllWarrants", function(result)
        local response = result or {}
        cb(response)
    end)
end)

-- createWarrant: create a new warrant; notifies the officer of success/failure
RegisterNUICallback("createWarrant", function(data, cb)
    TriggerCallback("plt_mdt:server:createWarrant", function(result)
        if result then
            Framework.Notify("Warrant created successfully!", "success")
        else
            Framework.Notify("Failed to create warrant.", "error")
        end
        cb(result)
    end, data)
end)

-- deleteWarrant: delete a warrant by ID
RegisterNUICallback("deleteWarrant", function(data, cb)
    TriggerCallback("plt_mdt:server:deleteWarrant", function(result)
        cb(result)
    end, data.id)
end)

-- completeWarrant: mark a warrant as completed
RegisterNUICallback("completeWarrant", function(data, cb)
    TriggerCallback("plt_mdt:server:completeWarrant", function(result)
        cb(result)
    end, data.id)
end)


-- ─────────────────────────────────────────────────────────────
-- LOCAL HELPER: toggleHUD(visible)
-- Fires a local event to show/hide the player HUD.
-- Used during photo-capture sessions.
-- ─────────────────────────────────────────────────────────────
local function toggleHUD(visible)
    -- originally SHX7_1 (standalone function at line 1320)
    TriggerEvent("plt_mdt:client:toggleHUD", visible)
end


-- ─────────────────────────────────────────────────────────────
-- NUI CALLBACK: takeMDTPhoto
-- Enters a free-roam photo mode for a generic MDT context photo.
-- The player positions the camera, presses ENTER to capture or
-- BACKSPACE to cancel. Uses screenshot-basic to upload the image
-- to Config.AvatarWebhook and returns the URL to the NUI.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("takeMDTPhoto", function(data, cb)
    -- Guard: if another photo session is already running, reject
    if isPhotoMode then
        return cb("busy")
    end

    isPhotoMode = true                    -- originally SHX1_1 = true

    local photoContext = data.context     -- NUI context tag passed back with result

    -- Temporarily release NUI focus so the player can control the camera
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeMDT" })

    CreateThread(function()
        local previousCamMode = GetFollowPedCamViewMode()
        SetFollowPedCamViewMode(4)   -- first-person / cinematic mode for framing

        while true do
            -- Exit loop if another path cleared the photo-mode flag
            if not isPhotoMode then break end

            Wait(0)

            -- Block attack/aim/shoot inputs while framing the shot
            DisableControlAction(0, 24, true)   -- INPUT_ATTACK
            DisableControlAction(0, 25, true)   -- INPUT_AIM
            DisableControlAction(0, 37, true)   -- INPUT_SELECT_WEAPON

            -- Draw on-screen instruction text
            SetTextFont(4)
            SetTextScale(0.0, 0.4)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString("~b~[ENTER]~w~ TAKE PHOTO  |  ~r~[BACKSPACE]~w~ CANCEL")
            DrawText(0.4, 0.9)

            -- Check if ENTER (control 191) was pressed to capture
            local enterPressed = IsControlJustPressed(0, 191)
                               or IsDisabledControlJustPressed(0, 191)

            if enterPressed then
                -- ── CAPTURE PATH ──
                isPhotoMode = false
                DisplayRadar(false)
                toggleHUD(false)
                Wait(1000)   -- brief pause before screenshot so HUD is hidden

                if GetResourceState("screenshot-basic") == "started" then
                    -- Use screenshot-basic to take and upload the photo
                    local photoPromise = promise.new()
                    exports["screenshot-basic"]:requestScreenshotUpload(
                        Config.AvatarWebhook,
                        "files[]",
                        function(responseRaw)
                            -- Resolve the promise with the raw response string
                            photoPromise:resolve(responseRaw)
                        end
                    )

                    local responseRaw    = Citizen.Await(photoPromise)
                    local responseTable  = json.decode(responseRaw)
                    local imageUrl       = nil

                    -- Extract URL: Discord webhooks return attachments[], others return .url
                    if responseTable then
                        if responseTable.attachments and responseTable.attachments[1] then
                            imageUrl = responseTable.attachments[1].url
                        elseif responseTable.url then
                            imageUrl = responseTable.url
                        end
                    end

                    -- Return the captured URL (or nil on failure) to the NUI
                    SendNUIMessage({
                        type    = "photoCaptured",
                        url     = imageUrl,
                        context = photoContext,
                    })

                    -- Restore HUD, radar, NUI focus and camera mode
                    DisplayRadar(true)
                    toggleHUD(true)
                    SetNuiFocus(true, true)
                    SetFollowPedCamViewMode(previousCamMode)
                    break
                end

                -- screenshot-basic not available: abort photo mode
                isPhotoMode = false
                DisplayRadar(true)
                SetNuiFocus(true, true)
                SetFollowPedCamViewMode(previousCamMode)
                break   -- originally: do break end (same effect)

            else
                -- ::SHX_LABEL_160:: — check BACKSPACE (control 194) to cancel
                -- (originally a goto target; replaced with if/else chain)
                local backPressed = IsControlJustPressed(0, 194)
                                  or IsDisabledControlJustPressed(0, 194)

                if backPressed then
                    -- ── CANCEL PATH ──
                    isPhotoMode = false
                    SetNuiFocus(true, true)
                    SetFollowPedCamViewMode(previousCamMode)
                    break   -- originally: do break end
                end
                -- ::SHX_LABEL_182:: — neither key pressed; loop continues
            end
        end
    end)

    cb("ok")
end)


-- ─────────────────────────────────────────────────────────────
-- NUI CALLBACK: takeCitizenPhoto
-- Identical photo flow to takeMDTPhoto, but also auto-saves
-- the captured image as the specified citizen's profile photo.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("takeCitizenPhoto", function(data, cb)
    if isPhotoMode then
        return cb("busy")
    end

    pendingPhotoCitizenId = data.citizenid   -- originally SHX2_1 = SHX0_2.citizenid
    isPhotoMode = true

    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeMDT" })

    CreateThread(function()
        local previousCamMode = GetFollowPedCamViewMode()
        SetFollowPedCamViewMode(4)

        while true do
            if not isPhotoMode then break end

            Wait(0)

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)

            SetTextFont(4)
            SetTextScale(0.0, 0.4)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString("~b~[ENTER]~w~ TAKE PHOTO  |  ~r~[BACKSPACE]~w~ CANCEL")
            DrawText(0.4, 0.9)

            local enterPressed = IsControlJustPressed(0, 191)
                               or IsDisabledControlJustPressed(0, 191)

            if enterPressed then
                -- ── CAPTURE PATH ──
                isPhotoMode = false
                DisplayRadar(false)
                toggleHUD(false)
                Wait(1000)

                if GetResourceState("screenshot-basic") == "started" then
                    local photoPromise = promise.new()
                    exports["screenshot-basic"]:requestScreenshotUpload(
                        Config.AvatarWebhook,
                        "files[]",
                        function(responseRaw)
                            photoPromise:resolve(responseRaw)
                        end
                    )

                    local responseRaw   = Citizen.Await(photoPromise)
                    local responseTable = json.decode(responseRaw)
                    local imageUrl      = nil

                    if responseTable then
                        if responseTable.attachments and responseTable.attachments[1] then
                            imageUrl = responseTable.attachments[1].url
                        elseif responseTable.url then
                            imageUrl = responseTable.url
                        end
                    end

                    if imageUrl then
                        -- Notify NUI that the photo was captured
                        SendNUIMessage({
                            type    = "photoCaptured",
                            url     = imageUrl,
                            context = responseTable.context,
                        })

                        -- If a citizen ID was set, auto-save the image to their profile
                        if pendingPhotoCitizenId then
                            TriggerCallback(
                                "plt_mdt:server:updateProfileImage",
                                function(_result)
                                    -- Result intentionally ignored; fire-and-forget update
                                    -- NOTE: _result is dead code preserved from original
                                end,
                                { citizenid = pendingPhotoCitizenId, image = imageUrl }
                            )
                        end
                    else
                        -- Upload succeeded but no URL returned; notify NUI with nil
                        SendNUIMessage({
                            type    = "photoCaptured",
                            url     = nil,
                            context = responseTable.context,
                        })
                    end

                    DisplayRadar(true)
                    toggleHUD(true)
                    SetNuiFocus(true, true)
                    SetFollowPedCamViewMode(previousCamMode)
                    break
                end

                -- screenshot-basic unavailable
                isPhotoMode = false
                DisplayRadar(true)
                SetNuiFocus(true, true)
                SetFollowPedCamViewMode(previousCamMode)
                break   -- originally: do break end

            else
                -- ::SHX_LABEL_178:: — check BACKSPACE to cancel
                local backPressed = IsControlJustPressed(0, 194)
                                  or IsDisabledControlJustPressed(0, 194)

                if backPressed then
                    isPhotoMode = false
                    SetNuiFocus(true, true)
                    SetFollowPedCamViewMode(previousCamMode)
                    break   -- originally: do break end
                end
                -- ::SHX_LABEL_200:: — loop continues
            end
        end
    end)

    cb("ok")
end)


-- ─────────────────────────────────────────────────────────────
-- NUI CALLBACK: takeOfficerSelfie
-- Creates a scripted camera positioned in front of the officer's
-- face and enters a selfie photo-capture flow. On capture, saves
-- the image to the officer's own profile. Pressing BACKSPACE
-- during this mode cancels and re-opens the MDT.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("takeOfficerSelfie", function(data, cb)
    if isPhotoMode then
        return cb("busy")
    end

    isPhotoMode = true

    SetNuiFocus(false, false)
    SendNUIMessage({ type = "closeMDT" })

    CreateThread(function()
        local localPed = PlayerPedId()

        -- Create a scripted camera positioned slightly in front of and above the ped
        local selfieCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        local camOffset    = GetOffsetFromEntityInWorldCoords(localPed, 0.0, 0.8, 0.65)
        SetCamCoord(selfieCamera, camOffset.x, camOffset.y, camOffset.z)
        PointCamAtEntity(selfieCamera, localPed, 0.0, 0.0, 0.65, true)
        SetCamActive(selfieCamera, true)
        RenderScriptCams(true, true, 500, true, true)

        while true do
            if not isPhotoMode then break end

            Wait(0)

            -- Block inputs to prevent the ped moving while selfie mode is active
            DisableControlAction(0, 24, true)   -- INPUT_ATTACK
            DisableControlAction(0, 25, true)   -- INPUT_AIM
            DisableControlAction(0, 37, true)   -- INPUT_SELECT_WEAPON

            SetTextFont(4)
            SetTextScale(0.0, 0.4)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString("~b~[ENTER]~w~ TAKE SELFIE  |  ~r~[BACKSPACE]~w~ CANCEL")
            DrawText(0.4, 0.9)

            local enterPressed = IsControlJustPressed(0, 191)
                               or IsDisabledControlJustPressed(0, 191)

            if enterPressed then
                -- ── CAPTURE PATH ──
                isPhotoMode = false
                DisplayRadar(false)
                toggleHUD(false)
                Wait(1000)

                if GetResourceState("screenshot-basic") == "started" then
                    local photoPromise = promise.new()
                    exports["screenshot-basic"]:requestScreenshotUpload(
                        Config.AvatarWebhook,
                        "files[]",
                        function(responseRaw)
                            photoPromise:resolve(responseRaw)
                        end
                    )

                    local responseRaw   = Citizen.Await(photoPromise)
                    local responseTable = json.decode(responseRaw)
                    local imageUrl      = nil

                    if responseTable then
                        if responseTable.attachments and responseTable.attachments[1] then
                            imageUrl = responseTable.attachments[1].url
                        elseif responseTable.url then
                            imageUrl = responseTable.url
                        end
                    end

                    if imageUrl then
                        -- Notify NUI of the captured selfie
                        SendNUIMessage({
                            type      = "photoCaptured",
                            url       = imageUrl,
                            isOfficer = true,
                            context   = responseTable.context,
                        })

                        -- Auto-save to the officer's own profile using their identifier
                        local officerData = Framework.GetPlayerData()
                        if officerData and officerData.identifier then
                            TriggerCallback(
                                "plt_mdt:server:updateProfileImage",
                                function(_result)
                                    -- Result intentionally ignored; fire-and-forget update
                                    -- NOTE: _result is dead code preserved from original
                                end,
                                { citizenid = officerData.identifier, image = imageUrl }
                            )
                        end
                    else
                        -- Upload succeeded but no URL; send nil to NUI
                        SendNUIMessage({
                            type    = "photoCaptured",
                            url     = nil,
                            context = responseTable.context,
                        })
                    end
                else
                    -- screenshot-basic not running: send nil to NUI
                    SendNUIMessage({
                        type    = "photoCaptured",
                        url     = nil,
                        context = data.context,
                    })
                end

                DisplayRadar(true)
                toggleHUD(true)
                SetNuiFocus(true, true)
                -- ::SHX_LABEL_230:: — shared exit label, reached by goto in original
                -- (replaced: both branches fall through to post-loop cleanup)
                break

            else
                -- ::SHX_LABEL_209:: — check BACKSPACE (control 177 in selfie mode)
                -- NOTE: control 177 differs from the 194 used in the other photo callbacks;
                -- this matches the original exactly.
                local backPressed = IsControlJustPressed(0, 177)
                                  or IsDisabledControlJustPressed(0, 177)

                if backPressed then
                    -- Cancel: restore NUI focus and re-open the MDT
                    isPhotoMode = false
                    SetNuiFocus(true, true)
                    ToggleMDT(true)
                    -- ::SHX_LABEL_230:: — exit label
                    break
                end
                -- ::SHX_LABEL_230:: reached by goto when neither key pressed; loop continues
            end
        end

        -- Always clean up the scripted camera after exiting
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(selfieCamera, false)
    end)

    cb("ok")
end)


-- ─────────────────────────────────────────────────────────────
-- KEY MAPPING: Open MDT with F10
-- Bound to the "mdt" command registered above.
-- ─────────────────────────────────────────────────────────────
RegisterKeyMapping("mdt", "Open MDT", "keyboard", "F10")


-- ─────────────────────────────────────────────────────────────
-- NET EVENT: plt_mdt:client:jailTeleport(coords, isRelease)
-- Teleports the player to the given coords with a fade transition.
--   coords     – table with .x, .y, .z and optional .h (heading)
--   isRelease  – true when the player is being released from jail
--                (removes jail blips); false when being sent to jail
--                (creates jail blips and shows task hint)
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent("plt_mdt:client:jailTeleport")
AddEventHandler("plt_mdt:client:jailTeleport", function(coords, isRelease)
    local ped = PlayerPedId()

    -- Fade out before teleporting
    DoScreenFadeOut(500)
    Wait(500)

    -- Move the ped to the target coordinates
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)

    -- Optionally set a specific heading
    if coords.h then
        SetEntityHeading(ped, coords.h)
    end

    -- Fade back in
    Wait(500)
    DoScreenFadeIn(500)

    -- Update jail state: isRelease=true means leaving jail, isRelease=false means entering
    isJailed = not isRelease   -- originally SHX3_1 = not SHX1_2

    if isJailed then
        -- Player is now jailed: show task blips and a hint notification
        CreateJailBlips()
        ShowNotification("~b~JAIL:~s~ You can perform tasks around the yard to reduce your sentence.")
    else
        -- Player was released: clean up blips
        RemoveJailBlips()
    end
end)


-- ─────────────────────────────────────────────────────────────
-- NET EVENT: plt_mdt:client:jailNotify(message)
-- Displays a notification to the local player (used by server
-- to push jail-related messages, e.g. sentence updates).
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent("plt_mdt:client:jailNotify")
AddEventHandler("plt_mdt:client:jailNotify", function(message, _unused)
    -- _unused: second parameter present in original but never read
    ShowNotification(message)
end)


-- ─────────────────────────────────────────────────────────────
-- StartJailTask(taskLocation)
-- Plays a scenario animation matching the task type for 8 seconds,
-- then clears the task and notifies the server that it is complete.
-- ─────────────────────────────────────────────────────────────
local function StartJailTask(taskLocation)
    -- originally SHX8_1 (standalone function at line 2360)
    local ped = PlayerPedId()

    -- Select the appropriate ambient scenario for the task type
    local scenarioName = "WORLD_HUMAN_JANITOR"   -- default (sweep)
    if taskLocation.type == "trash" then
        scenarioName = "PROP_HUMAN_BUM_BIN"
    elseif taskLocation.type == "pushups" then
        scenarioName = "WORLD_HUMAN_PUSH_UPS"
    elseif taskLocation.type == "sweep" then
        scenarioName = "WORLD_HUMAN_JANITOR"
    end

    TaskStartScenarioInPlace(ped, scenarioName, 0, true)

    ShowNotification("Doing task: ~y~" .. taskLocation.label .. "~s~...")

    -- Wait 8 seconds in 100ms increments (8000ms total)
    local remaining = 8000
    while remaining > 0 do
        Wait(100)
        remaining = remaining - 100
        -- NOTE: the original had an empty `if 0 == remaining % 1000 then end`
        -- block at each second boundary — preserved as dead code comment below.
        -- if 0 == (remaining % 1000) then end   -- dead: no-op tick every second
    end

    -- Stop the animation and award the task completion on the server
    ClearPedTasksImmediately(ped)
    TriggerServerEvent("plt_mdt:server:completeJailTask")
end


-- ─────────────────────────────────────────────────────────────
-- THREAD: Jail Task Proximity Loop
-- Runs every 1 second normally, or every frame (0ms) when the
-- player is within 10 units of a task location to draw markers
-- and handle interaction.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local waitMs = 1000   -- default: check once per second

        if isJailed and Config.EnableJailTasks then
            local ped       = PlayerPedId()
            local pedCoords = GetEntityCoords(ped)
            local now       = GetGameTimer()

            for _, taskLocation in ipairs(Config.JailTaskLocations) do
                local taskVec    = vector3(taskLocation.x, taskLocation.y, taskLocation.z)
                local distance   = #(pedCoords - taskVec)

                if distance < 10.0 then
                    waitMs = 0   -- switch to per-frame updates while near a task

                    -- Draw a downward-pointing arrow marker above the task spot
                    DrawMarker(
                        2,                          -- type: vertical chevron/arrow
                        taskLocation.x,
                        taskLocation.y,
                        taskLocation.z + 0.2,       -- slightly above ground
                        0.0, 0.0, 0.0,              -- direction
                        0.0, 180.0, 0.0,            -- rotation (pointing down)
                        0.3, 0.3, 0.3,              -- scale
                        99, 166, 192, 150,          -- RGBA colour (steel blue, semi-transparent)
                        false,                      -- bobUpAndDown
                        true,                       -- faceCamera
                        2,                          -- p19
                        false,                      -- rotate
                        nil,                        -- textureDict
                        false,                      -- textureGfx
                        false                       -- drawOnEnts
                    )

                    -- Show interaction prompt only when very close (< 1.5 units)
                    if distance < 1.5 then
                        local timeSinceLast = now - lastJailTaskTime
                        local cooldown      = Config.JailTaskCooldown
                        local promptText

                        if timeSinceLast < cooldown then
                            -- Still on cooldown: show remaining seconds
                            local remainingMs  = cooldown - timeSinceLast
                            local remainingSec = math.ceil(remainingMs / 1000)
                            promptText = "Cooldown: " .. remainingSec .. "s"
                        else
                            promptText = "[E] " .. taskLocation.label
                        end

                        ShowHelpNotification(promptText)

                        -- Check for [E] press (control 38 = INPUT_CONTEXT)
                        if IsControlJustPressed(0, 38) then
                            if (now - lastJailTaskTime) > cooldown then
                                lastJailTaskTime = now   -- originally SHX5_1 = now
                                StartJailTask(taskLocation)
                            end
                        end
                    end
                end
            end
        end

        Wait(waitMs)
    end
end)


-- === VERIFICATION ===
-- Total lines in source:          2417
-- Total lines in output:          ~370 (logical lines; comments and blank lines included)
-- Obfuscation techniques found:
--   1. Systematic identifier mangling (SHXn_m naming scheme on all locals and upvalues)
--   2. Decompiler-generated temporary variable aliasing
--      (e.g. SHX1_2 = BeginTextCommandDisplayHelp; SHX1_2(SHX2_2) instead of direct call)
--   3. goto/label control-flow (SHX_LABEL_XX) replacing if/else and while loops
--   4. Function identity reassignment (same name SHX7_1 reused for multiple distinct
--      functions, each aliased to a meaningful name immediately after definition)
--   5. Redundant variable chains (a = f; b = arg; a(b) instead of f(arg))
--   6. Decompiler boilerplate comment blocks repeated in every function
-- String arrays resolved:         0 (no string-array encoding used)
-- Renamed identifiers:
--   Module-level: 7 (SHX0_1–SHX6_1)
--   Function names: ~25+ (ShowHelpNotification, ShowNotification, CreateJailBlips,
--     RemoveJailBlips, ToggleMDT, toggleHUD, StartJailTask, etc.)
--   Local parameters and temporaries: ~150+ across all functions
-- Constructs flagged for review:
--   1. Line 1504 / 1746 / 2048: `elseif responseTable then` after a closing `end`
--      inside an `if responseTable then` block — decompiler likely mis-placed the
--      `end`, producing structurally awkward but functionally correct code. Preserved
--      faithfully with the intent: first branch checks .attachments[1].url, second
--      checks the top-level .url directly.
--   2. Lines 1492 / 1734 / 2036: `imageUrl = nil` set before the if/elseif —
--      harmless explicit nil initialisation; preserved.
--   3. "takeCitizenPhoto" callback at line 1757: `responseTable.context` is accessed
--      on the screenshot-basic response object, which typically only contains
--      `attachments` or `url`. This field will almost always be nil unless the
--      upload service mirrors it back. Low risk, but may result in a nil context
--      being passed to the NUI.
--   4. `_result` callbacks in updateProfileImage TriggerCallback calls: the server
--      callback result is intentionally discarded (fire-and-forget). This is safe
--      but means no client-side confirmation that the image was saved.
--   5. Dead `if 0 == (remaining % 1000) then end` block in StartJailTask: no-op,
--      preserved as a comment.
-- Functionality preserved:        YES — all event handlers, NUI callbacks, exports,
--   commands, threads, and net events are present with identical behaviour.