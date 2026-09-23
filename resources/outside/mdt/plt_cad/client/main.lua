local QBCore  = nil   -- QBCore / QBX core object (QB framework)
local ESX     = nil   -- ESX shared object (ESX framework)

-- Active panel / prop handles
local activePanelId  = nil   -- CR3D panel ID currently displayed
local activeVehicle  = nil   -- vehicle entity the CAD is attached to
local laptopPropEntity = nil -- spawned laptop prop entity handle

-- Interaction state
local mouseActive    = false  -- true when the player is interacting with the CAD
local cursorU        = 0.5    -- normalised cursor X position (0-1)
local cursorV        = 0.5    -- normalised cursor Y position (0-1)
local cursorSensitivity = 0.10 -- how fast the cursor moves per axis input unit

-- Prop config (these globals can be updated by edit mode and printed)
local LAPTOP_PROP_HASH = 1665536489          -- prop model hash
local LAPTOP_BONE_NAME = "seat_pside_f"      -- vehicle bone to attach to
DASH_PROP_OFFSET = vector3(-0.5, 0.38, 0.39) -- local-space offset from bone
DASH_PROP_ROT    = vector3(0.0, 0.0, -25.0)  -- local-space rotation (degrees)

-- Panel display dimensions (metres)
local panelWidth  = 0.27
local panelHeight = 0.17

-- Panel local-space orientation (computed once in openCAD, reused in edit mode)
local localOffset = nil
local localNormal = nil
local localUp     = nil


-- ============================================================
-- SECTION 1 - Framework detection
-- ============================================================

-- Auto-detect framework from running resources if Config.Framework == "AUTO"
if Config.Framework == "AUTO" then
    if GetResourceState("qb-core") == "started"
    or GetResourceState("qbx-core") == "started" then
        Config.Framework = "QB"
    elseif GetResourceState("es_extended") == "started" then
        Config.Framework = "ESX"
    end
end

-- Auto-detect notification type from framework if Config.NotifyType == "AUTO"
if Config.NotifyType == "AUTO" then
    if Config.Framework == "QB" then
        Config.NotifyType = "qb"
    elseif Config.Framework == "ESX" then
        Config.NotifyType = "esx"
    else
        Config.NotifyType = "chat"
    end
end

-- Obtain the framework core object
if Config.Framework == "QB" then
    if GetResourceState("qb-core") == "started" then
        -- Standard QBCore export
        QBCore = exports["qb-core"]:GetCoreObject()

    elseif GetResourceState("qbx-core") == "started" then
        -- QBX-core: wrap its exports into a QBCore-shaped table
        local qbxFunctions = {}

        function qbxFunctions.GetPlayerData()
            return exports.qbx_core:GetPlayerData()
        end

        function qbxFunctions.Notify(message, notifyType)
            exports.qbx_core:Notify(message, notifyType)
        end

        QBCore = { Functions = qbxFunctions }

    else
        -- Fallback: request the object via legacy event
        TriggerEvent("QBCore:GetObject", function(coreObject)
            QBCore = coreObject
        end)
    end

elseif Config.Framework == "ESX" then
    if GetResourceState("es_extended") == "started" then
        ESX = exports.es_extended:getSharedObject()
    end
end


-- ============================================================
-- SECTION 2 - Notification helper
-- sendNotify(message, notifyType)
--   message     - string to display
--   notifyType  - optional type hint ("primary", "error", etc.)
-- ============================================================
local function sendNotify(message, notifyType)
    if Config.NotifyType == "qb" then
        if QBCore then
            QBCore.Functions.Notify(message, notifyType or "primary")
        end

    elseif Config.NotifyType == "esx" then
        if ESX then
            ESX.ShowNotification(message)
        end

    else
        -- Fallback: post to the game chat
        TriggerEvent("chat:addMessage", {
            args = { "CAD", message }
        })
    end
end


-- ============================================================
-- SECTION 3 - Vector math helpers (local, not part of CR3D)
-- These duplicate some CR3D helpers so main.lua is self-contained
-- for the panel-orientation calculation done in openCAD().
-- ============================================================

-- vecNormLocal(v) -> unit vector, falls back to (0,1,0) if near-zero
local function vecNormLocal(vec)
    local len = math.sqrt(
        vec.x * vec.x + vec.y * vec.y + vec.z * vec.z
    )
    if len <= 1e-6 then
        return vector3(0.0, 1.0, 0.0)
    end
    return vector3(vec.x / len, vec.y / len, vec.z / len)
end

-- vecCrossLocal(a, b) -> cross product
local function vecCrossLocal(vecA, vecB)
    return vector3(
        (vecA.y * vecB.z) - (vecA.z * vecB.y),
        (vecA.z * vecB.x) - (vecA.x * vecB.z),
        (vecA.x * vecB.y) - (vecA.y * vecB.x)
    )
end

-- vecDotLocal(a, b) -> dot product (scalar)
local function vecDotLocal(vecA, vecB)
    return (vecA.x * vecB.x)
         + (vecA.y * vecB.y)
         + (vecA.z * vecB.z)
end

-- rotateVecAroundAxis(vec, axis, angleDeg)
-- Rodrigues' rotation formula: rotates `vec` around `axis` by `angleDeg` degrees.
local function rotateVecAroundAxis(vec, axis, angleDeg)
    local rad     = math.rad(angleDeg)
    local cosA    = math.cos(rad)
    local sinA    = math.sin(rad)
    local crossed = vecCrossLocal(axis, vec)
    local dotVal  = vecDotLocal(axis, vec)

    return vector3(
        vec.x  * cosA + crossed.x * sinA + axis.x * dotVal * (1 - cosA),
        vec.y  * cosA + crossed.y * sinA + axis.y * dotVal * (1 - cosA),
        vec.z  * cosA + crossed.z * sinA + axis.z * dotVal * (1 - cosA)
    )
end


-- ============================================================
-- SECTION 4 - CAD teardown
-- closeCAD()
-- Destroys the active panel, laptop prop, and resets all state.
-- ============================================================
local function closeCAD()
    -- Tell server this player is no longer interacting
    if mouseActive then
        TriggerServerEvent("plt_cad:server:setMouseActive", false)
    end
    mouseActive = false

    -- Destroy the CR3D DUI panel
    if activePanelId then
        CR3D.DestroyPanel(activePanelId)
        activePanelId = nil
    end

    -- Delete the laptop prop entity
    if laptopPropEntity then
        if DoesEntityExist(laptopPropEntity) then
            DeleteEntity(laptopPropEntity)
        end
        laptopPropEntity = nil
    end

    -- Clear the vehicle reference
    activeVehicle = nil
end


-- ============================================================
-- SECTION 5 - Model loading helper
-- loadModel(hash) -> boolean
-- Requests a model and waits up to 5 seconds for it to load.
-- Returns true on success, false on timeout or invalid model.
-- ============================================================
local function loadModel(modelHash)
    if not IsModelInCdimage(modelHash) then
        return false
    end

    RequestModel(modelHash)

    local deadline = GetGameTimer() + 5000
    while true do
        if HasModelLoaded(modelHash) then
            return true
        end
        Wait(0)
        if GetGameTimer() > deadline then
            return false
        end
    end
end


-- ============================================================
-- SECTION 6 - CAD initialisation
-- openCAD(vehicle)
-- Spawns the laptop prop, creates the CR3D panel, and wires up
-- the entity attachment so the panel follows the vehicle.
-- ============================================================
local function openCAD(vehicle)
    -- Tear down any existing session first
    closeCAD()
    activeVehicle = vehicle

    -- -- Spawn laptop prop ----------------------------------
    if loadModel(LAPTOP_PROP_HASH) then
        local vehiclePos = GetEntityCoords(vehicle)

        -- Create the prop at the vehicle's current position
        laptopPropEntity = CreateObject(
            LAPTOP_PROP_HASH,
            vehiclePos.x, vehiclePos.y, vehiclePos.z,
            true, true, true
        )

        -- Validate the entity handle (0 means creation failed)
        if laptopPropEntity == 0 or not DoesEntityExist(laptopPropEntity) then
            laptopPropEntity = nil
        end

        if laptopPropEntity then
            -- Disable collision so it doesn't interfere with physics
            SetEntityCollision(laptopPropEntity, false, false)

            -- Attach prop to the passenger seat bone with the configured offsets
            local boneIndex = GetEntityBoneIndexByName(vehicle, LAPTOP_BONE_NAME)
            AttachEntityToEntity(
                laptopPropEntity,
                vehicle,
                boneIndex,
                DASH_PROP_OFFSET.x, DASH_PROP_OFFSET.y, DASH_PROP_OFFSET.z,
                DASH_PROP_ROT.x,    DASH_PROP_ROT.y,    DASH_PROP_ROT.z,
                false, false, false, false,
                2,      -- attachment type
                true    -- useSoftPinning
            )
        end
    end

    -- -- Compute panel world orientation -------------------
    local duiUrl = "nui://plt_cad/ui/index.html"

    -- Local-space offset from the prop (or vehicle) origin where the panel sits
    localOffset = vector3(0.0, 0.068, 0.09)

    -- Local-space normal and up vectors for the panel face
    localNormal = vector3(0.781, -0.003, 0.0)
    localUp     = vector3(0.0,   0.0,   -1.0)

    -- Rotate the normal -90 around the up vector to align with the screen face
    localNormal = rotateVecAroundAxis(localNormal, localUp, -90.0)

    -- Build a perpendicular "right" vector for the panel (cross of normal  up)
    local panelRight = vecNormLocal(vecCrossLocal(localNormal, localUp))

    -- Fine-tune both normal and up with a 3 rotation around panelRight
    local tweakAngle = 3.0
    localNormal = rotateVecAroundAxis(localNormal, panelRight, tweakAngle)
    localUp     = rotateVecAroundAxis(localUp,     panelRight, tweakAngle)

    -- -- Create the CR3D panel ------------------------------
    -- Use the prop entity if spawned, otherwise fall back to the vehicle
    local anchorEntity = laptopPropEntity or vehicle
    local panelWorldPos = GetOffsetFromEntityInWorldCoords(
        anchorEntity,
        localOffset.x, localOffset.y, localOffset.z
    )

    activePanelId = CR3D.CreatePanel({
        url     = duiUrl,
        resW    = 900,
        resH    = 530,
        pos     = panelWorldPos,
        normal  = vector3(0, 0, 1),  -- initial; overridden by attachment below
        width   = panelWidth,
        height  = panelHeight,
        alpha   = 255,
        enabled = true,
        faceCamera = false,
    })

    if not activePanelId then
        sendNotify("Failed to create CAD panel", "error")
        return
    end

    -- -- Wire up CR3D entity attachment --------------------
    local panelKey   = tostring(activePanelId)
    local boneIndex  = GetEntityBoneIndexByName(vehicle, LAPTOP_BONE_NAME)

    -- Compute the panel's world position relative to the anchor entity
    local propWorldPos  = GetOffsetFromEntityInWorldCoords(
        anchorEntity,
        localOffset.x, localOffset.y, localOffset.z
    )
    local boneWorldPos  = GetWorldPositionOfEntityBone(vehicle, boneIndex)

    -- Get the vehicle's rotation matrix axes
    local matRight, matForward, matUp, matOrigin = GetEntityMatrix(vehicle)

    -- Offset from bone to prop panel position, expressed in entity local space
    local worldOffset = propWorldPos - boneWorldPos
    local localSpaceOffset = vector3(
        vecDotLocal(worldOffset, matRight),
        vecDotLocal(worldOffset, matForward),
        vecDotLocal(worldOffset, matUp)
    )

    -- Helper: transform a local-space direction into entity local coords
    -- (projects a world-offset vector onto the entity matrix axes)
    local function toLocalDir(worldVec)
        local vecFromProp = GetOffsetFromEntityInWorldCoords(
            anchorEntity,
            worldVec.x, worldVec.y, worldVec.z
        ) - GetEntityCoords(anchorEntity)

        return vector3(
            vecDotLocal(vecFromProp, matRight),
            vecDotLocal(vecFromProp, matForward),
            vecDotLocal(vecFromProp, matUp)
        )
    end

    -- Register the attachment so the render thread updates the panel each frame
    CR3D.ATTACHMENTS[panelKey] = {
        entity       = vehicle,
        boneIndex    = boneIndex,
        offset       = localSpaceOffset,
        localNormal  = toLocalDir(localNormal),
        localUp      = toLocalDir(localUp),
        rotateNormal = true,
    }

    -- -- Resolve officer name -------------------------------
    local officerName = "Unknown Officer"

    if Config.Framework == "QB" and QBCore then
        local playerData = QBCore.Functions.GetPlayerData()
        if playerData and playerData.charinfo then
            local first = playerData.charinfo.firstname or "Unknown"
            local last  = playerData.charinfo.lastname  or "Officer"
            officerName = first .. " " .. last
        end

    elseif Config.Framework == "ESX" and ESX then
        local playerData = ESX.GetPlayerData()
        if playerData then
            local first = playerData.firstName or playerData.firstname or "Unknown"
            local last  = playerData.lastName  or playerData.lastname  or "Officer"
            officerName = first .. " " .. last
        end
    end

    -- -- Send setup message after DUI has had 2 s to load --
    SetTimeout(2000, function()
        if not activePanelId then return end

        CR3D.SendMessage(activePanelId, {
            type        = "setup",
            name        = officerName,
            headerLeft  = Config.HeaderLeftText,
            headerRight = Config.HeaderRightText,
        })

        -- Ask server to push the latest officer/call data
        TriggerServerEvent("plt_cad:requestUpdate")
    end)

    -- -- Guard thread: close CAD if vehicle is deleted ------
    CreateThread(function()
        while true do
            -- Exit if panel was closed or vehicle changed
            if not activePanelId             then break end
            if activeVehicle ~= vehicle      then break end

            if not DoesEntityExist(vehicle) then
                closeCAD()
                sendNotify("CAD Closed: Vehicle deleted", "error")
                break
            end

            Wait(1000)
        end
    end)

    sendNotify("Police CAD Initialized")
end


-- ============================================================
-- SECTION 7 - Job authorisation check
-- isAuthorisedJob(jobName) -> boolean
-- Returns true if jobName is in Config.Jobs list.
-- ============================================================
local function isAuthorisedJob(jobName)
    if not jobName then return false end

    for _, allowedJob in ipairs(Config.Jobs) do
        if allowedJob == jobName then
            return true
        end
    end

    return false
end


-- ============================================================
-- SECTION 8 - Commands
-- ============================================================

-- /[open]  -  Open the in-world CAD (must be in a vehicle, authorised job)
RegisterCommand(Config.Commands.open, function()
    local playerPed = PlayerPedId()
    local vehicle   = GetVehiclePedIsIn(playerPed, false)

    if vehicle == 0 then
        sendNotify("You must be in a vehicle to use the CAD", "error")
        return
    end

    -- Job check
    if Config.Framework == "QB" and QBCore then
        local playerData = QBCore.Functions.GetPlayerData()
        if not playerData or not playerData.job or not isAuthorisedJob(playerData.job.name) then
            sendNotify("Access Denied: Authorized Jobs Only", "error")
            return
        end

    elseif Config.Framework == "ESX" and ESX then
        local playerData = ESX.GetPlayerData()
        if playerData.job and not isAuthorisedJob(playerData.job.name) then
            sendNotify("Access Denied: Authorized Jobs Only", "error")
            return
        end
    end

    openCAD(vehicle)
end)

-- /[key]  -  Toggle mouse interaction with the CAD panel
-- Default key binding: J
RegisterCommand(Config.Commands.key, function()
    if not activePanelId then
        sendNotify(
            "CAD is not active. Use /" .. Config.Commands.open .. " first.",
            "error"
        )
        return
    end

    -- Toggle the mouse-active flag
    mouseActive = not mouseActive
    TriggerServerEvent("plt_cad:server:setMouseActive", mouseActive)

    if mouseActive then
        sendNotify("CAD Interaction Started (ESC to exit)")
        -- Reset cursor to centre
        cursorU = 0.5
        cursorV = 0.5
    else
        sendNotify("CAD Interaction Stopped")
        -- Hide the DUI cursor
        CR3D.SendMessage(activePanelId, { type = "dui_cursor", show = false })
    end
end)

RegisterKeyMapping(Config.Commands.key, "Toggle CAD Interaction", "keyboard", "J")

-- /[close]  -  Explicitly close and clean up the CAD
RegisterCommand(Config.Commands.close, function()
    closeCAD()
    sendNotify("CAD Deactivated")
end)


-- ============================================================
-- SECTION 9 - Test mode (flat NUI overlay, no in-world panel)
-- /[test]  -  Toggle a 2D NUI overlay version of the CAD for
--             UI development without needing a vehicle.
-- ============================================================
local testModeActive = false   -- is test mode currently on?

RegisterCommand(Config.Commands.test, function()
    testModeActive = not testModeActive

    if testModeActive then
        -- Enable NUI focus so mouse interacts with the HTML page
        SetNuiFocus(true, true)

        -- Resolve officer name (same logic as openCAD)
        local officerName = "Unknown Officer"

        if Config.Framework == "QB" and QBCore then
            local playerData = QBCore.Functions.GetPlayerData()
            if playerData and playerData.charinfo then
                local first = playerData.charinfo.firstname or "Unknown"
                local last  = playerData.charinfo.lastname  or "Officer"
                officerName = first .. " " .. last
            end
        elseif Config.Framework == "ESX" and ESX then
            local playerData = ESX.GetPlayerData()
            if playerData then
                local first = playerData.firstName or playerData.firstname or "Unknown"
                local last  = playerData.lastName  or playerData.lastname  or "Officer"
                officerName = first .. " " .. last
            end
        end

        -- Show and initialise the NUI overlay
        SendNUIMessage({ type = "show", state = true })
        SendNUIMessage({
            type        = "setup",
            name        = officerName,
            headerLeft  = Config.HeaderLeftText,
            headerRight = Config.HeaderRightText,
        })

        TriggerServerEvent("plt_cad:requestUpdate")

    else
        -- Disable NUI focus and hide overlay
        SetNuiFocus(false, false)
        SendNUIMessage({ type = "show", state = false })
    end
end)

-- NUI callback: closeNui
-- Fired by the NUI page when the user clicks the close button in test mode.
RegisterNUICallback("closeNui", function(data, cb)
    testModeActive = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "show", state = false })
    cb("ok")
end)


-- ============================================================
-- SECTION 10 - NUI -> Server message relay
-- NUI callback: openFieldInput
-- Opens the NUI overlay as a transparent input layer so the player
-- can type into a field. SetNuiFocus only works on the NUI overlay,
-- not on DUI browser textures, so we use the overlay for typing.
RegisterNUICallback("openFieldInput", function(data, cb)
    SetNuiFocus(true, true)
    -- Send the field info to the NUI overlay so it can show the input
    SendNUIMessage({
        type     = "fieldInput",
        fieldId  = data.fieldId,
        label    = data.label,
        current  = data.current or ""
    })
    cb("ok")
end)

-- NUI callback: closeFieldInput
-- Hides the NUI input overlay and returns focus to game/DUI
RegisterNUICallback("closeFieldInput", function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "hideFieldInput" })
    -- Forward the typed value to the DUI panel
    if activePanelId and data.fieldId then
        CR3D.SendMessage(activePanelId, {
            type    = "fieldResult",
            fieldId = data.fieldId,
            value   = data.value or ""
        })
    end
    cb("ok")
end)


-- NUI callback: syncInteraction
-- The NUI page sends all user-initiated actions here.
-- This function forwards them to the relevant server event and
-- also mirrors them to the CR3D DUI panel if one is active.
-- ============================================================
RegisterNUICallback("syncInteraction", function(data, cb)
    -- Mirror to CR3D in-world DUI panel
    if activePanelId then
        CR3D.SendMessage(activePanelId, data)
    end

    -- Mirror to NUI overlay in test mode
    if testModeActive then
        SendNUIMessage(data)
    end

    -- Dispatch by message type
    local msgType = data.type

    if msgType == "setStatus" then
        TriggerServerEvent("plt_cad:updateStatus", data.status)

    elseif msgType == "scanVehicle" then
        -- Raycast for the vehicle directly in front
        local frontVehicle = GetVehicleInFront()
        if frontVehicle and frontVehicle ~= 0 then
            local plate     = GetVehicleNumberPlateText(frontVehicle)
            local modelName = GetLabelText(
                GetDisplayNameFromVehicleModel(GetEntityModel(frontVehicle))
            )
            TriggerServerEvent("plt_cad:getVehicleInfo", plate, modelName)
        else
            -- No vehicle found; clear the vehicle result panel
            SendVehicleResult(nil, nil, nil)
        end

    elseif msgType == "getCallDetails" then
        TriggerServerEvent("plt_cad:getCallDetails", data.callId)

    elseif msgType == "submitForm" then
        TriggerServerEvent("plt_cad:submitForm", data.formData)

    elseif msgType == "getRecords" then
        TriggerServerEvent("plt_cad:getRecords")

    elseif msgType == "getRecordDetails" then
        TriggerServerEvent("plt_cad:getRecordDetails", data.recordId)

    elseif msgType == "assignCall" then
        TriggerServerEvent("plt_cad:assignCall", data.callId)

    elseif msgType == "resolveCall" then
        TriggerServerEvent("plt_cad:resolveCall", data.callId)
    end

    cb("ok")
end)


-- ============================================================
-- SECTION 11 - GetVehicleInFront
-- Casts a capsule shape test forward from the player/vehicle
-- and returns the first vehicle entity hit, or nil.
-- ============================================================
local function getVehicleInFront()
    local playerPed = PlayerPedId()
    local vehicle   = GetVehiclePedIsIn(playerPed, false)

    -- Start and end positions of the capsule test
    local startPos = GetEntityCoords(playerPed)
    local endPos   = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 10.0, 0.0)

    -- If in a vehicle, extend range to 15 m and use vehicle position
    if vehicle ~= 0 then
        startPos = GetEntityCoords(vehicle)
        endPos   = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 15.0, 0.0)
    end

    -- Exclude the player ped or vehicle from the hit test
    local ignoreEntity = (vehicle ~= 0 and vehicle) or playerPed

    local shapeTestHandle = StartShapeTestCapsule(
        startPos.x, startPos.y, startPos.z,
        endPos.x,   endPos.y,   endPos.z,
        2.0,        -- capsule radius
        10,         -- flags (detect vehicles)
        ignoreEntity,
        7           -- shapeTestType
    )

    local _, hitResult, _, _, hitEntity = GetShapeTestResult(shapeTestHandle)

    if hitResult == 1 and IsEntityAVehicle(hitEntity) then
        return hitEntity
    end

    return nil
end

-- Expose as global so syncInteraction can call it
GetVehicleInFront = getVehicleInFront


-- ============================================================
-- SECTION 12 - SendVehicleResult
-- Packages a vehicle lookup result and pushes it to the active
-- panel or test-mode NUI overlay.
-- ============================================================
local function sendVehicleResult(plate, owner, modelName, boloData)
    local msg = {
        type  = "vehicleResult",
        plate = plate,
        owner = owner,
        model = modelName,
        bolo  = boloData,
    }

    if activePanelId then
        CR3D.SendMessage(activePanelId, msg)
    end

    if testModeActive then
        SendNUIMessage(msg)
    end
end

-- Expose as global so the net event handler below can call it
SendVehicleResult = sendVehicleResult


-- ============================================================
-- SECTION 13 - Net events (server -> client data push)
-- ============================================================

-- Vehicle info lookup result
RegisterNetEvent("plt_cad:vehicleInfoResult", function(plate, owner, modelName, boloData)
    SendVehicleResult(plate, owner, modelName, boloData)
end)

-- Call details result
RegisterNetEvent("plt_cad:callDetailsResult", function(callDetails)
    local msg = { type = "callDetails", details = callDetails }
    if activePanelId  then CR3D.SendMessage(activePanelId, msg) end
    if testModeActive then SendNUIMessage(msg)                   end
end)

-- Criminal records list result
RegisterNetEvent("plt_cad:recordsResult", function(records)
    local msg = { type = "recordsData", records = records }
    if activePanelId  then CR3D.SendMessage(activePanelId, msg) end
    if testModeActive then SendNUIMessage(msg)                   end
end)

-- Single record details result
RegisterNetEvent("plt_cad:recordDetailsResult", function(details)
    local msg = { type = "recordDetails", details = details }
    if activePanelId  then CR3D.SendMessage(activePanelId, msg) end
    if testModeActive then SendNUIMessage(msg)                   end
end)

-- Officer / call list update (main CAD data refresh)
RegisterNetEvent("plt_cad:updateData", function(officers, calls)
    -- Optionally inject fake officers for testing purposes
    if Config.AddFakeOfficers then
        table.insert(officers, {
            name   = "John Doe",
            unit   = "K9-01",
            status = "BUSY",
            agency = "LSPD",
            source = nil,
        })
        table.insert(officers, {
            name   = "Jane Smith",
            unit   = "AIR-05",
            status = "UNAVAILABLE",
            agency = "BCSO",
            source = nil,
        })
    end

    local msg = {
        type     = "updateData",
        officers = officers,
        calls    = calls,
    }

    if activePanelId  then CR3D.SendMessage(activePanelId, msg) end
    if testModeActive then SendNUIMessage(msg)                   end
end)


-- ============================================================
-- SECTION 14 - Edit mode
-- /[edit]  -  Move the laptop prop (and its attached DUI panel)
--             using arrow keys / numpad while in-vehicle.
--             Press ENTER to print new coordinates to console.
-- ============================================================
local editModeActive = false  -- is edit mode currently on?
local editMoveStep   = 0.005  -- movement increment per key press (metres)
local editRotStep    = 0.5    -- rotation increment per key press (degrees)

RegisterCommand(Config.Commands.edit, function()
    -- Require both a panel and a laptop prop to be active
    if not (activePanelId and laptopPropEntity) then
        sendNotify(
            "CAD or Laptop not active. Use /" .. Config.Commands.open .. " first.",
            "error"
        )
        return
    end

    editModeActive = not editModeActive

    if editModeActive then
        sendNotify("EDIT MODE: Moving PC & CAD together. [ENTER] to Save.")
    else
        sendNotify("Edit Mode Stopped.")
    end
end)

-- Edit mode input thread
-- Runs continuously but only does work when editModeActive is true.
CreateThread(function()
    while true do
        local waitMs = 500  -- idle; will become 0 in edit mode

        if editModeActive and laptopPropEntity and activeVehicle then
            waitMs = 0

            -- SHIFT held -> multiply move/rot step by 5/2 respectively
            local shiftHeld   = IsControlPressed(0, 21)
            local moveStep    = shiftHeld and (editMoveStep * 5) or editMoveStep
            local rotStep     = shiftHeld and (editRotStep  * 2) or editRotStep

            local propMoved   = false  -- did we change DASH_PROP_OFFSET or DASH_PROP_ROT?

            if not shiftHeld then
                -- -- Translation mode (arrow keys / numpad) ----------
                -- Left arrow  -> X-
                if IsControlPressed(0, 174) then
                    DASH_PROP_OFFSET = DASH_PROP_OFFSET + vector3(-moveStep, 0, 0)
                    propMoved = true

                -- Right arrow -> X+
                elseif IsControlPressed(0, 175) then
                    DASH_PROP_OFFSET = DASH_PROP_OFFSET + vector3(moveStep, 0, 0)
                    propMoved = true
                end

                -- Up arrow    -> Z+
                if IsControlPressed(0, 172) then
                    DASH_PROP_OFFSET = DASH_PROP_OFFSET + vector3(0, 0, moveStep)
                    propMoved = true

                -- Down arrow  -> Z-
                elseif IsControlPressed(0, 173) then
                    DASH_PROP_OFFSET = DASH_PROP_OFFSET + vector3(0, 0, -moveStep)
                    propMoved = true
                end

                -- Num+        -> Y+
                if IsControlPressed(0, 10) then
                    DASH_PROP_OFFSET = DASH_PROP_OFFSET + vector3(0, moveStep, 0)
                    propMoved = true

                -- Num-        -> Y-
                elseif IsControlPressed(0, 11) then
                    DASH_PROP_OFFSET = DASH_PROP_OFFSET + vector3(0, -moveStep, 0)
                    propMoved = true
                end

            else
                -- -- Rotation mode (SHIFT + arrow keys) --------------
                -- SHIFT + Left  -> rotate Z-
                if IsControlPressed(0, 174) then
                    DASH_PROP_ROT = DASH_PROP_ROT + vector3(0, 0, -rotStep)
                    propMoved = true

                -- SHIFT + Right -> rotate Z+
                elseif IsControlPressed(0, 175) then
                    DASH_PROP_ROT = DASH_PROP_ROT + vector3(0, 0, rotStep)
                    propMoved = true
                end

                -- SHIFT + Up   -> rotate X+
                if IsControlPressed(0, 172) then
                    DASH_PROP_ROT = DASH_PROP_ROT + vector3(rotStep, 0, 0)
                    propMoved = true

                -- SHIFT + Down -> rotate X-
                elseif IsControlPressed(0, 173) then
                    DASH_PROP_ROT = DASH_PROP_ROT + vector3(-rotStep, 0, 0)
                    propMoved = true
                end
            end

            -- If the prop moved, re-attach it with the new offsets
            if propMoved then
                local anchorEnt = laptopPropEntity or activeVehicle
                local boneIndex = GetEntityBoneIndexByName(activeVehicle, LAPTOP_BONE_NAME)

                if laptopPropEntity then
                    AttachEntityToEntity(
                        laptopPropEntity,
                        activeVehicle,
                        boneIndex,
                        DASH_PROP_OFFSET.x, DASH_PROP_OFFSET.y, DASH_PROP_OFFSET.z,
                        DASH_PROP_ROT.x,    DASH_PROP_ROT.y,    DASH_PROP_ROT.z,
                        false, false, false, false,
                        2, true
                    )
                end

                -- Also update the CR3D attachment offset so the panel follows
                local attachmentData = CR3D.ATTACHMENTS[tostring(activePanelId)]
                if attachmentData then
                    local boneWorldPos  = GetWorldPositionOfEntityBone(activeVehicle, boneIndex)
                    local propWorldPos  = GetOffsetFromEntityInWorldCoords(
                        anchorEnt,
                        localOffset.x, localOffset.y, localOffset.z
                    )

                    local matRight, matForward, matUp, _ = GetEntityMatrix(activeVehicle)
                    local worldOffset = propWorldPos - boneWorldPos

                    -- Recompute local-space offset from bone to panel
                    attachmentData.offset = vector3(
                        vecDotLocal(worldOffset, matRight),
                        vecDotLocal(worldOffset, matForward),
                        vecDotLocal(worldOffset, matUp)
                    )

                    -- Recompute local normal and up direction
                    local function toLocalDir(worldVec)
                        local vecFromProp = GetOffsetFromEntityInWorldCoords(
                            anchorEnt,
                            worldVec.x, worldVec.y, worldVec.z
                        ) - GetEntityCoords(anchorEnt)

                        return vector3(
                            vecDotLocal(vecFromProp, matRight),
                            vecDotLocal(vecFromProp, matForward),
                            vecDotLocal(vecFromProp, matUp)
                        )
                    end

                    attachmentData.localNormal = toLocalDir(localNormal)
                    attachmentData.localUp     = toLocalDir(localUp)
                end
            end

            -- ENTER pressed -> print updated coordinates to F8 console
            if IsControlJustPressed(0, 18) then
                print("================ UPDATED PC & CAD COORDINATES ================")
                print("-- Copy these to the top of main.lua (Prop Config):")
                print(string.format(
                    "DASH_PROP_OFFSET = vector3(%.3f, %.3f, %.3f)",
                    DASH_PROP_OFFSET.x, DASH_PROP_OFFSET.y, DASH_PROP_OFFSET.z
                ))
                print(string.format(
                    "DASH_PROP_ROT = vector3(%.1f, %.1f, %.1f)",
                    DASH_PROP_ROT.x, DASH_PROP_ROT.y, DASH_PROP_ROT.z
                ))
                print("==============================================================")
                sendNotify("Coordinates printed to F8 Console!")
                editModeActive = false
            end
        end

        Wait(waitMs)
    end
end)


-- ============================================================
-- SECTION 15 - Mouse interaction thread
-- Runs when mouseActive is true:
--    Disables game controls (look, attack, etc.)
--    Reads mouse axis input and accumulates cursor position
--    Forwards cursor position and clicks to the CR3D DUI panel
--    Auto-disables if player moves too far from the panel
--    ESC / BACK_SPACE exits interaction mode
-- ============================================================
CreateThread(function()
    while true do
        if mouseActive and activePanelId then

            local playerPed = PlayerPedId()
            local playerPos = GetEntityCoords(playerPed)

            -- Distance check: auto-stop interaction if too far from panel
            local panelData = CR3D.PANELS[tostring(activePanelId)]
            if panelData then
                local distToPanel = #(playerPos - panelData.pos)
                local maxDist     = Config.RenderDistance or 10.0

                if distToPanel > maxDist then
                    mouseActive = false
                    CR3D.SendMessage(activePanelId, { type = "dui_cursor", show = false })
                    TriggerServerEvent("plt_cad:server:setMouseActive", false)
                    sendNotify("CAD Interaction Stopped (Too far away)")
                end
            end

            if mouseActive then
                -- Disable game controls that would interfere with CAD interaction
                DisableControlAction(0, 1,   true)  -- LookLeftRight
                DisableControlAction(0, 2,   true)  -- LookUpDown
                DisableControlAction(0, 24,  true)  -- Attack (left click)
                DisableControlAction(0, 25,  true)  -- Aim
                DisableControlAction(0, 142, true)  -- MeleeAttackAlternate
                DisableControlAction(0, 257, true)  -- Attack2

                -- Read raw mouse axis input (returns -1.0 to 1.0)
                local mouseX = GetDisabledControlNormal(0, 1)  -- horizontal
                local mouseY = GetDisabledControlNormal(0, 2)  -- vertical

                -- Accumulate cursor position clamped to [0, 1]
                cursorU = math.max(0.0, math.min(1.0, cursorU + mouseX * cursorSensitivity))
                cursorV = math.max(0.0, math.min(1.0, cursorV + mouseY * cursorSensitivity))

                -- Forward cursor position to the DUI browser
                CR3D.SendMouseMove(activePanelId, cursorU, cursorV)

                -- Send cursor overlay position to DUI
                CR3D.SendMessage(activePanelId, {
                    type = "dui_cursor",
                    show = true,
                    u    = cursorU,
                    v    = cursorV,
                })

                -- Forward left mouse button events
                if IsDisabledControlJustPressed(0, 24) then
                    CR3D.SendMouseDown(activePanelId, "left")
                elseif IsDisabledControlJustReleased(0, 24) then
                    CR3D.SendMouseUp(activePanelId, "left")
                end

                -- ESC (322) or BACK_SPACE (177) -> exit interaction
                local escPressed   = IsDisabledControlJustPressed(0, 322)
                local backPressed  = IsDisabledControlJustPressed(0, 177)
                local backPressed2 = IsControlJustPressed(0, 177)

                if escPressed or backPressed or backPressed2 then
                    mouseActive = false
                    CR3D.SendMessage(activePanelId, { type = "dui_cursor", show = false })
                    TriggerServerEvent("plt_cad:server:setMouseActive", false)
                    sendNotify("CAD Interaction Stopped")
                end

                Wait(0)  -- run every frame while interacting
            else
                Wait(250)
            end

        else
            Wait(250)
        end
    end
end)


-- ============================================================
-- SECTION 16 - Resource cleanup
-- Close the CAD cleanly when this resource is stopped.
-- ============================================================
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        closeCAD()
    end
end)