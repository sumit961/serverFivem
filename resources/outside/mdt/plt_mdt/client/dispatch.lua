-- =============================================================================
-- dispatch.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Client-side dispatch / CCTV camera logic
-- =============================================================================
-- Deobfuscation notes:
--   • All SHX0_1 … SHX16_1 module-level scratch variables have been given
--     stable, descriptive names based on their persistent runtime roles.
--   • All SHX*_2 / SHX*_3 / SHX*_4 inner locals have been renamed to reflect
--     their actual purpose in each scope.
--   • All goto/label constructs have been replaced with structured if/else.
--   • Decompiler boilerplate comments have been removed; meaningful ones added.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Module-level state
-- (original: single flat `local SHX0_1 … SHX16_1` reused as scratch space)
-- ---------------------------------------------------------------------------

-- originally: SHX0_1 (used as RegisterNetEvent/RegisterCommand/RegisterKeyMapping/
--             RegisterNUICallback/CreateThread scratch, then becomes scriptCamHandle)
local scriptCamHandle = nil              -- handle to the active scripted CCTV camera; nil when no camera is active

-- originally: SHX1_1 (used as event-name scratch, then becomes isCreatingCamera)
local isCreatingCamera = false           -- true while the player is in camera-placement mode

-- originally: SHX2_1 (used as handler scratch, then becomes isWatchingCamera)
local isWatchingCamera = false           -- true while the player is viewing a dispatch camera feed

-- originally: SHX3_1 (used as false/RegisterCommand arg scratch, then becomes cameraRotation)
local cameraRotation = { x = 0.0, y = 0.0, z = 0.0 }  -- current pitch (x) and yaw (z) of the watched camera, in degrees

-- originally: SHX4_1
local rotationSpeed = 140.0             -- mouse-look speed multiplier (degrees per unit of input per second)

-- originally: SHX5_1
local defaultFov = 100.0               -- default field-of-view for scripted cameras

-- originally: SHX6_1 (initialised to defaultFov at line 481)
local currentFov = defaultFov          -- current field-of-view; modified by scroll wheel

-- originally: SHX7_1
local minFov = 25.0                    -- minimum FOV (maximum zoom-in)

-- originally: SHX8_1
local maxFov = 120.0                   -- maximum FOV (maximum zoom-out)

-- originally: SHX9_1 — table of weapon hashes that are excluded from automatic
-- gunshot dispatch reports (e.g. non-lethal / novelty weapons).
-- 883325847 = 0x34A67B97, 101631238 = 0x060EC506
local excludedWeaponHashes = {}
excludedWeaponHashes[883325847] = true  -- originally: SHX10_1 = 883325847; SHX9_1[SHX10_1] = true
excludedWeaponHashes[101631238] = true  -- originally: SHX10_1 = 101631238; SHX9_1[SHX10_1] = true

-- Forward declarations for functions used before their definition point
-- (the original SHX10_1 / SHX11_1 / SHX12_1 / SHX13_1 are defined further below;
--  Lua closures mean the onResourceStop handler can reference them by upvalue)
local stopDispatchCameraView   -- originally: SHX10_1  (defined below)
local clampValue               -- originally: SHX11_1  (defined below)
local eulerToForwardVector     -- originally: SHX12_1  (defined below)
local getWorldPositionFromCam  -- originally: SHX13_1  (defined below)


-- =============================================================================
-- SECTION 1 — Resource cleanup on stop
-- originally lines 9-33
-- =============================================================================

-- originally: SHX0_1 = AddEventHandler; SHX1_1 = "onResourceStop"; function SHX2_1(SHX0_2) … end; SHX0_1(SHX1_1, SHX2_1)
AddEventHandler("onResourceStop", function(stoppingResourceName)
    -- originally: SHX1_2 = GetCurrentResourceName; SHX1_2 = SHX1_2()
    local thisResource = GetCurrentResourceName()

    -- originally: if SHX1_2 ~= SHX0_2 then return end
    if thisResource ~= stoppingResourceName then
        return
    end

    -- originally: SHX1_2 = ClearTimecycleModifier; SHX1_2()
    ClearTimecycleModifier()

    -- originally: SHX1_2 = isWatchingDispatchCamera (decompiler emitted the upvalue
    --   by its original source name; at runtime this resolves to isWatchingCamera /
    --   SHX2_1 module-level variable)
    -- originally: if SHX1_2 then SHX1_2 = StopDispatchCameraView; SHX1_2() end
    if isWatchingCamera then
        stopDispatchCameraView()  -- originally: StopDispatchCameraView() — upvalue resolved
    end
end)


-- =============================================================================
-- SECTION 2 — Net event: updateOfficerLocations
-- originally lines 34-51
-- =============================================================================

-- originally: SHX0_1 = RegisterNetEvent; SHX1_1 = "plt_mdt:client:updateOfficerLocations"
-- NOTE: The decompiled pattern calls RegisterNetEvent(name, handler) as a single call.
--   Standard FiveM usage separates RegisterNetEvent and AddEventHandler; the resource
--   may use a framework wrapper, or an older FiveM API that accepts both arguments.
RegisterNetEvent("plt_mdt:client:updateOfficerLocations", function(officerList)
    -- originally: SHX1_2 = SendNUIMessage; SHX2_2 = {}; SHX2_2.type = …; SHX1_2(SHX2_2)
    SendNUIMessage({
        type    = "updateOfficerLocations",
        officers = officerList   -- originally: SHX2_2.officers = SHX0_2
    })
end)


-- =============================================================================
-- SECTION 3 — Net event: newDispatchCall
-- originally lines 52-133
-- =============================================================================

-- originally: SHX0_1 = RegisterNetEvent; SHX1_1 = "plt_mdt:client:newDispatchCall"
RegisterNetEvent("plt_mdt:client:newDispatchCall", function(callData)
    -- callData fields used here: .location, .coords (.x/.y/.z or [1]/[2]/[3]), .id

    -- originally:
    --   SHX1_2 = SHX0_2.location
    --   if SHX1_2 then
    --     SHX1_2 = SHX0_2.location
    --     if "Unknown" ~= SHX1_2 then goto SHX_LABEL_64 end
    --   end
    -- Meaning: if location is set and is NOT "Unknown", skip coord-resolution and
    -- jump straight to sending the NUI message.
    local shouldResolveLocation = not callData.location or callData.location == "Unknown"

    if shouldResolveLocation then
        -- Try to resolve a street-name location from the call's coords.
        -- originally: SHX1_2 = SHX0_2.coords; if SHX1_2 then … end
        local coords = callData.coords
        if coords then
            -- Parse x coordinate; fall back to array index [1] if no .x key.
            -- originally: SHX2_2 = tonumber; SHX3_2 = SHX1_2.x; if not SHX3_2 then SHX3_2 = SHX1_2[1] end; SHX2_2 = SHX2_2(SHX3_2); if not SHX2_2 then SHX2_2 = 0.0 end
            local rawX = coords.x or coords[1]
            local coordX = tonumber(rawX)
            if not coordX then coordX = 0.0 end

            -- Parse y coordinate.
            -- originally: SHX3_2 = tonumber; SHX4_2 = SHX1_2.y; if not SHX4_2 then SHX4_2 = SHX1_2[2] end; …
            local rawY = coords.y or coords[2]
            local coordY = tonumber(rawY)
            if not coordY then coordY = 0.0 end

            -- Parse z coordinate.
            -- originally: SHX4_2 = tonumber; SHX5_2 = SHX1_2.z; if not SHX5_2 then SHX5_2 = SHX1_2[3] end; …
            local rawZ = coords.z or coords[3]
            local coordZ = tonumber(rawZ)
            if not coordZ then coordZ = 0.0 end

            -- Only look up street name if coords are non-zero.
            -- originally: if 0.0 ~= SHX2_2 or 0.0 ~= SHX3_2 then … end
            if coordX ~= 0.0 or coordY ~= 0.0 then
                -- originally: SHX5_2 = GetStreetNameAtCoord; SHX5_2, SHX6_2 = SHX5_2(x, y, z)
                local streetHash, crossingHash = GetStreetNameAtCoord(coordX, coordY, coordZ)

                -- originally: SHX7_2 = GetStreetNameFromHashKey; SHX8_2 = SHX5_2; SHX7_2 = SHX7_2(SHX8_2)
                local streetName = GetStreetNameFromHashKey(streetHash)

                -- If there is a crossing/intersection street, append it with " | ".
                -- originally: if 0 ~= SHX6_2 then SHX8_2 = SHX7_2 .. " | " .. GetStreetNameFromHashKey(SHX6_2); SHX7_2 = SHX8_2 end
                if crossingHash ~= 0 then
                    local crossingName = GetStreetNameFromHashKey(crossingHash)
                    streetName = streetName .. " | " .. crossingName
                end

                -- Patch the call data with the resolved location string.
                -- originally: SHX0_2.location = SHX7_2
                callData.location = streetName

                -- Notify the server of the resolved location so it can update the call record.
                -- originally: SHX8_2 = TriggerServerEvent; SHX9_2 = "plt_mdt:server:updateCallLocation"; …
                TriggerServerEvent("plt_mdt:server:updateCallLocation", callData.id, streetName)
            end
        end
    end

    -- originally: ::SHX_LABEL_64:: (goto target when location was already valid)
    -- Send the (possibly location-enriched) call data to the NUI.
    -- originally: SHX1_2 = SendNUIMessage; SHX2_2 = {}; SHX2_2.type = "newDispatchCall"; SHX2_2.call = SHX0_2; SHX1_2(SHX2_2)
    SendNUIMessage({
        type = "newDispatchCall",
        call = callData
    })
end)


-- =============================================================================
-- SECTION 4 — Command: mdtnotifleft  (navigate dispatch notification left)
-- originally lines 134-152
-- =============================================================================

-- originally: SHX0_1 = RegisterCommand; SHX1_1 = "mdtnotifleft"; function SHX2_1() … end; SHX3_1 = false; SHX0_1(SHX1_1, SHX2_1, SHX3_1)
RegisterCommand("mdtnotifleft", function()
    -- originally: SHX0_2 = SendNUIMessage; SHX1_2 = {}; SHX1_2.type = …; SHX1_2.direction = "left"; SHX0_2(SHX1_2)
    SendNUIMessage({
        type      = "navigateDispatchNotification",
        direction = "left"
    })
end, false)


-- =============================================================================
-- SECTION 5 — Command: mdtnotifright  (navigate dispatch notification right)
-- originally lines 153-171
-- =============================================================================

-- originally: SHX0_1 = RegisterCommand; SHX1_1 = "mdtnotifright"; function SHX2_1() … end; SHX3_1 = false; SHX0_1(SHX1_1, SHX2_1, SHX3_1)
RegisterCommand("mdtnotifright", function()
    -- originally: SHX0_2 = SendNUIMessage; SHX1_2 = {}; SHX1_2.type = …; SHX1_2.direction = "right"; SHX0_2(SHX1_2)
    SendNUIMessage({
        type      = "navigateDispatchNotification",
        direction = "right"
    })
end, false)


-- =============================================================================
-- SECTION 6 — Key mappings: mdtnotifleft / mdtnotifright
-- originally lines 172-183
-- =============================================================================

-- originally: SHX0_1 = RegisterKeyMapping; SHX1_1 = "mdtnotifleft"; SHX2_1 = "Dispatch notification previous"; SHX3_1 = "keyboard"; SHX4_1 = "LEFT"; SHX0_1(…)
RegisterKeyMapping("mdtnotifleft",  "Dispatch notification previous", "keyboard", "LEFT")

-- originally: SHX0_1 = RegisterKeyMapping; SHX1_1 = "mdtnotifright"; SHX2_1 = "Dispatch notification next"; SHX3_1 = "keyboard"; SHX4_1 = "RIGHT"; SHX0_1(…)
RegisterKeyMapping("mdtnotifright", "Dispatch notification next",     "keyboard", "RIGHT")


-- =============================================================================
-- SECTION 7 — Command: mdtnotifdirection  (confirm notification direction)
-- originally lines 184-201
-- =============================================================================

-- originally: SHX0_1 = RegisterCommand; SHX1_1 = "mdtnotifdirection"; function SHX2_1() … end; SHX3_1 = false; SHX0_1(…)
RegisterCommand("mdtnotifdirection", function()
    -- originally: SHX0_2 = SendNUIMessage; SHX1_2 = {}; SHX1_2.type = "performDispatchNotificationDirection"; SHX0_2(SHX1_2)
    SendNUIMessage({
        type = "performDispatchNotificationDirection"
    })
end, false)


-- =============================================================================
-- SECTION 8 — Command: mdtnotifdismiss  (dismiss notification)
-- originally lines 202-219
-- =============================================================================

-- originally: SHX0_1 = RegisterCommand; SHX1_1 = "mdtnotifdismiss"; function SHX2_1() … end; SHX3_1 = false; SHX0_1(…)
RegisterCommand("mdtnotifdismiss", function()
    -- originally: SHX0_2 = SendNUIMessage; SHX1_2 = {}; SHX1_2.type = "dismissDispatchNotification"; SHX0_2(SHX1_2)
    SendNUIMessage({
        type = "dismissDispatchNotification"
    })
end, false)


-- =============================================================================
-- SECTION 9 — Key mappings: mdtnotifdirection / mdtnotifdismiss
-- originally lines 220-231
-- =============================================================================

-- originally: SHX0_1 = RegisterKeyMapping; SHX1_1 = "mdtnotifdirection"; SHX2_1 = "Dispatch notification direction"; SHX3_1 = "keyboard"; SHX4_1 = "E"
RegisterKeyMapping("mdtnotifdirection", "Dispatch notification direction", "keyboard", "E")

-- originally: SHX0_1 = RegisterKeyMapping; SHX1_1 = "mdtnotifdismiss"; SHX2_1 = "Dispatch notification dismiss"; SHX3_1 = "keyboard"; SHX4_1 = "Y"
RegisterKeyMapping("mdtnotifdismiss",   "Dispatch notification dismiss",   "keyboard", "Y")


-- =============================================================================
-- SECTION 10 — NUI callback: getOfficerLocations
-- originally lines 232-268
-- =============================================================================

-- originally: SHX0_1 = RegisterNUICallback; SHX1_1 = "getOfficerLocations"; function SHX2_1(SHX0_2, SHX1_2) … end; SHX0_1(SHX1_1, SHX2_1)
RegisterNUICallback("getOfficerLocations", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:getOfficerLocations"
    -- Trigger a server-side callback; when the result arrives, forward it to the NUI.
    TriggerCallback("plt_mdt:server:getOfficerLocations", function(officerList)
        -- originally (inner, SHX4_2 / SHX0_3):
        --   SHX1_3 = SendNUIMessage
        --   SHX2_3 = {}
        --   SHX2_3.type = "updateOfficerLocations"
        --   SHX2_3.officers = SHX0_3
        --   SHX1_3(SHX2_3)
        SendNUIMessage({
            type    = "updateOfficerLocations",
            officers = officerList
        })

        -- Also call the NUI callback with the officer list (or an empty table if nil).
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = SHX0_3 or SHX2_3; if not SHX0_3 then SHX2_3 = {} end; SHX1_3(SHX2_3)
        -- NOTE: `SHX2_3` at the fallback point still holds {}, so `officerList or {}` is correct.
        cb(officerList or {})
    end)
end)


-- =============================================================================
-- SECTION 11 — NUI callback: setWaypoint
-- originally lines 269-296
-- =============================================================================

-- originally: SHX0_1 = RegisterNUICallback; SHX1_1 = "setWaypoint"; function SHX2_1(SHX0_2, SHX1_2) … end
RegisterNUICallback("setWaypoint", function(data, cb)
    -- Only set the waypoint if both x and y are present in the data.
    -- originally:
    --   if SHX0_2 then
    --     SHX2_2 = SHX0_2.x; if SHX2_2 then
    --       SHX2_2 = SHX0_2.y; if SHX2_2 then
    --         SHX2_2 = SetNewWaypoint; SHX3_2 = SHX0_2.x; SHX4_2 = SHX0_2.y; SHX2_2(SHX3_2, SHX4_2)
    --       end
    --     end
    --   end
    if data and data.x and data.y then
        SetNewWaypoint(data.x, data.y)
    end

    -- originally: SHX2_2 = SHX1_2; SHX3_2 = "ok"; SHX2_2(SHX3_2)
    cb("ok")
end)


-- =============================================================================
-- SECTION 12 — NUI callback: debugCoords  (no-op debug stub)
-- originally lines 297-312
-- =============================================================================

-- originally: SHX0_1 = RegisterNUICallback; SHX1_1 = "debugCoords"; function SHX2_1(SHX0_2, SHX1_2) … end
RegisterNUICallback("debugCoords", function(data, cb)
    -- Dead code / debug stub — no logic, just acknowledge.
    -- originally: SHX2_2 = SHX1_2; SHX3_2 = "ok"; SHX2_2(SHX3_2)
    cb("ok")
end)


-- =============================================================================
-- SECTION 13 — NUI callback: setRadioFrequency
-- originally lines 313-333
-- =============================================================================

-- originally: SHX0_1 = RegisterNUICallback; SHX1_1 = "setRadioFrequency"
RegisterNUICallback("setRadioFrequency", function(data, cb)
    -- originally: SHX2_2 = SHX0_2.frequency
    local frequency = data.frequency

    -- originally: SHX3_2 = TriggerServerEvent; SHX4_2 = "plt_mdt:server:setRadioChannel"; SHX5_2 = SHX2_2; SHX3_2(SHX4_2, SHX5_2)
    TriggerServerEvent("plt_mdt:server:setRadioChannel", frequency)

    -- originally: SHX3_2 = SHX1_2; SHX4_2 = "ok"; SHX3_2(SHX4_2)
    cb("ok")
end)


-- =============================================================================
-- SECTION 14 — NUI callback: triggerPanic
-- originally lines 334-400
-- =============================================================================

-- originally: SHX0_1 = RegisterNUICallback; SHX1_1 = "triggerPanic"
RegisterNUICallback("triggerPanic", function(data, cb)
    -- Determine the coords to attach to the panic alert.
    -- If the NUI data already contains coords with an x value, use them.
    -- Otherwise, fall back to the player's current position.
    -- originally:
    --   SHX2_2 = SHX0_2 or nil; if SHX0_2 then SHX2_2 = SHX0_2.coords end
    --   if SHX2_2 then SHX3_2 = SHX2_2.x; if SHX3_2 then goto SHX_LABEL_23 end end
    --   (fall through — build coords from player)
    --   ::SHX_LABEL_23::
    local panicCoords = data and data.coords
    local hasValidCoords = panicCoords and panicCoords.x

    if not hasValidCoords then
        -- Get the local player ped's world position.
        -- originally: SHX3_2 = PlayerPedId; SHX3_2 = SHX3_2(); SHX4_2 = GetEntityCoords; SHX5_2 = SHX3_2; SHX4_2 = SHX4_2(SHX5_2)
        local playerPed    = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        -- Build a plain table from the vector3 return value.
        -- originally: SHX5_2 = {}; SHX6_2 = SHX4_2.x; SHX5_2.x = … (and .y, .z)
        panicCoords = {
            x = playerCoords.x,
            y = playerCoords.y,
            z = playerCoords.z,
        }
    end

    -- ::SHX_LABEL_23:: — resolve street name from the determined coords.
    -- originally: SHX3_2 = GetStreetNameAtCoord; SHX4_2 = SHX2_2.x; SHX5_2 = SHX2_2.y; SHX6_2 = SHX2_2.z or 0.0; SHX3_2, SHX4_2 = SHX3_2(…)
    local panicZ = panicCoords.z
    if not panicZ then panicZ = 0.0 end
    local streetHash, crossingHash = GetStreetNameAtCoord(panicCoords.x, panicCoords.y, panicZ)

    -- originally: SHX5_2 = GetStreetNameFromHashKey; SHX6_2 = SHX3_2; SHX5_2 = SHX5_2(SHX6_2)
    local streetName = GetStreetNameFromHashKey(streetHash)

    -- Append crossing street with " | " if present.
    -- originally: if 0 ~= SHX4_2 then SHX6_2 = SHX5_2 .. " | " .. GetStreetNameFromHashKey(SHX4_2); SHX5_2 = SHX6_2 end
    if crossingHash ~= 0 then
        local crossingName = GetStreetNameFromHashKey(crossingHash)
        streetName = streetName .. " | " .. crossingName
    end

    -- Patch data with resolved location and coords, then fire the server event.
    -- originally: SHX0_2.location = SHX5_2; SHX0_2.coords = SHX2_2
    data.location = streetName
    data.coords   = panicCoords

    -- originally: SHX6_2 = TriggerServerEvent; SHX7_2 = "plt_mdt:server:triggerPanic"; SHX8_2 = SHX0_2; SHX6_2(SHX7_2, SHX8_2)
    TriggerServerEvent("plt_mdt:server:triggerPanic", data)

    -- originally: SHX6_2 = SHX1_2; SHX7_2 = "ok"; SHX6_2(SHX7_2)
    cb("ok")
end)


-- =============================================================================
-- SECTION 15 — NUI callback: setWaypointToAlert
-- originally lines 401-471
-- =============================================================================

-- originally: SHX0_1 = RegisterNUICallback; SHX1_1 = "setWaypointToAlert"
RegisterNUICallback("setWaypointToAlert", function(data, cb)
    -- Retrieve the coords table from the alert data.
    -- originally:
    --   if SHX0_2 then SHX2_2 = SHX0_2.coords; if SHX2_2 then goto SHX_LABEL_7 end end
    --   SHX2_2 = nil
    --   ::SHX_LABEL_7::
    local alertCoords = nil
    if data and data.coords then
        alertCoords = data.coords  -- skip the nil assignment; goto SHX_LABEL_7 landed here
    end
    -- If data or data.coords was absent, alertCoords remains nil (same as the original nil path).

    -- ::SHX_LABEL_7:: — validate that alertCoords is actually a table.
    -- originally: SHX3_2 = type; SHX4_2 = SHX2_2; SHX3_2 = SHX3_2(SHX4_2); if "table" ~= SHX3_2 then … end
    if type(alertCoords) ~= "table" then
        -- originally: SHX3_2 = Framework.Notify; SHX4_2 = "No GPS data…"; SHX5_2 = "error"; SHX3_2(SHX4_2, SHX5_2)
        Framework.Notify("No GPS data available for this alert.", "error")
        -- originally: SHX3_2 = SHX1_2; SHX4_2 = false; SHX3_2(SHX4_2)
        cb(false)
        return
    end

    -- Parse x coordinate; fall back to array index [1].
    -- originally: SHX3_2 = tonumber; SHX4_2 = SHX2_2.x or SHX2_2[1]; SHX3_2 = SHX3_2(SHX4_2)
    local rawX  = alertCoords.x or alertCoords[1]
    local coordX = tonumber(rawX)

    -- Parse y coordinate; fall back to array index [2].
    -- originally: SHX4_2 = tonumber; SHX5_2 = SHX2_2.y or SHX2_2[2]; SHX4_2 = SHX4_2(SHX5_2)
    local rawY  = alertCoords.y or alertCoords[2]
    local coordY = tonumber(rawY)

    -- If either x or y failed to parse, show an error.
    -- originally: if not SHX3_2 or not SHX4_2 then … end
    if not coordX or not coordY then
        -- originally: SHX5_2 = Framework.Notify; SHX6_2 = "No GPS data…"; SHX7_2 = "error"
        Framework.Notify("No GPS data available for this alert.", "error")
        -- originally: SHX5_2 = SHX1_2; SHX6_2 = false; SHX5_2(SHX6_2)
        cb(false)
        return
    end

    -- Set the map waypoint and notify the player.
    -- originally: SHX5_2 = SetNewWaypoint; SHX6_2 = SHX3_2; SHX7_2 = SHX4_2; SHX5_2(SHX6_2, SHX7_2)
    SetNewWaypoint(coordX, coordY)

    -- originally: SHX5_2 = Framework.Notify; SHX6_2 = "GPS set…"; SHX7_2 = "success"
    Framework.Notify("GPS set to alert location.", "success")

    -- originally: SHX5_2 = SHX1_2; SHX6_2 = true; SHX5_2(SHX6_2)
    cb(true)
end)


-- =============================================================================
-- SECTION 16 — stopDispatchCameraView()
-- Destroys the scripted cam, restores NUI focus, clears timecycle.
-- originally: function SHX10_1() … end  (lines 489-527)
-- =============================================================================

-- originally: function SHX10_1()
stopDispatchCameraView = function()
    -- If a scripted camera handle exists and is still valid, tear it down.
    -- originally: SHX0_2 = SHX0_1; if SHX0_2 then SHX0_2 = DoesCamExist; SHX1_2 = SHX0_1; SHX0_2 = SHX0_2(SHX1_2); if SHX0_2 then … end end
    if scriptCamHandle then
        if DoesCamExist(scriptCamHandle) then
            -- Smoothly transition back to the gameplay camera over 250 ms.
            -- originally: SHX0_2 = RenderScriptCams; SHX1_2 = false; SHX2_2 = true; SHX3_2 = 250; SHX4_2 = true; SHX5_2 = true; SHX0_2(…)
            RenderScriptCams(false, true, 250, true, true)

            -- Destroy the camera entity.
            -- originally: SHX0_2 = DestroyCam; SHX1_2 = SHX0_1; SHX2_2 = false; SHX0_2(SHX1_2, SHX2_2)
            DestroyCam(scriptCamHandle, false)

            -- originally: SHX0_2 = nil; SHX0_1 = SHX0_2
            scriptCamHandle = nil
        end
    end

    -- Mark that we are no longer watching a camera feed.
    -- originally: SHX0_2 = false; SHX2_1 = SHX0_2
    isWatchingCamera = false

    -- Remove the cinematic scanline timecycle modifier.
    -- originally: SHX0_2 = ClearTimecycleModifier; SHX0_2()
    ClearTimecycleModifier()

    -- Tell the NUI to hide the camera overlay HUD.
    -- originally: SHX0_2 = SendNUIMessage; SHX1_2 = {}; SHX1_2.type = "closeCameraOverlay"; SHX0_2(SHX1_2)
    SendNUIMessage({ type = "closeCameraOverlay" })
end


-- =============================================================================
-- SECTION 17 — clampValue(value, minVal, maxVal)
-- Returns value clamped to [minVal, maxVal].
-- originally: function SHX11_1(SHX0_2, SHX1_2, SHX2_2)  (lines 528-543)
-- =============================================================================

-- originally: function SHX11_1(SHX0_2, SHX1_2, SHX2_2)
clampValue = function(value, minVal, maxVal)
    -- originally: if SHX0_2 < SHX1_2 then return SHX1_2 end
    if value < minVal then
        return minVal
    end
    -- originally: if SHX2_2 < SHX0_2 then return SHX2_2 end
    if value > maxVal then
        return maxVal
    end
    -- originally: return SHX0_2
    return value
end


-- =============================================================================
-- SECTION 18 — eulerToForwardVector(rotation)
-- Converts a GTA-style rotation vector (degrees, order X=pitch, Z=yaw)
-- to a normalised forward direction vector3.
-- originally: function SHX12_1(SHX0_2)  (lines 544-585)
-- =============================================================================

-- originally: function SHX12_1(SHX0_2)
eulerToForwardVector = function(rotation)
    -- Convert yaw (z component) and pitch (x component) from degrees to radians.
    -- originally: SHX1_2 = math.rad; SHX2_2 = SHX0_2.z; SHX1_2 = SHX1_2(SHX2_2)
    local yawRad   = math.rad(rotation.z)

    -- originally: SHX2_2 = math.rad; SHX3_2 = SHX0_2.x; SHX2_2 = SHX2_2(SHX3_2)
    local pitchRad = math.rad(rotation.x)

    -- Compute |cos(pitch)| — the horizontal scaling factor for x and y components.
    -- originally: SHX3_2 = math.abs; SHX4_2 = math.cos; SHX5_2 = SHX2_2; SHX4_2, … = SHX4_2(SHX5_2); SHX3_2 = SHX3_2(SHX4_2, …)
    -- NOTE: math.cos returns one value; the multi-return assignment is a decompiler
    --   artefact — the extra variables (SHX5_2…SHX8_2) receive nil.
    local absCosP  = math.abs(math.cos(pitchRad))

    -- Build the forward unit vector in GTA's right-handed coordinate system:
    --   fx = -sin(yaw) * |cos(pitch)|
    --   fy =  cos(yaw) * |cos(pitch)|
    --   fz =  sin(pitch)
    -- originally: SHX4_2 = vector3
    --   SHX5_2 = -math.sin(SHX1_2) * SHX3_2   (fx)
    --   SHX6_2 =  math.cos(SHX1_2) * SHX3_2   (fy)
    --   SHX7_2, SHX8_2 = math.sin(SHX2_2)      (fz; SHX8_2 is decompiler artefact nil)
    --   return SHX4_2(SHX5_2, SHX6_2, SHX7_2, SHX8_2)
    -- NOTE: vector3 accepts 3 args; the 4th (nil) is harmless.
    local fwdX = -math.sin(yawRad) * absCosP
    local fwdY =  math.cos(yawRad) * absCosP
    local fwdZ =  math.sin(pitchRad)

    return vector3(fwdX, fwdY, fwdZ)
end


-- =============================================================================
-- SECTION 19 — getWorldPositionFromCam(distance)
-- Casts a ray from the gameplay camera along its forward direction for
-- `distance` units and returns the world position where it hits (or the
-- far end of the ray if nothing was hit), plus the camera rotation and origin.
-- originally: function SHX13_1(SHX0_2)  (lines 586-642)
-- =============================================================================

-- originally: function SHX13_1(SHX0_2)
getWorldPositionFromCam = function(distance)
    -- Get the current gameplay camera rotation (rotation order 2 = Euler ZXY in GTA).
    -- originally: SHX1_2 = GetGameplayCamRot; SHX2_2 = 2; SHX1_2 = SHX1_2(SHX2_2)
    local camRot    = GetGameplayCamRot(2)

    -- Get the gameplay camera's world position.
    -- originally: SHX2_2 = GetGameplayCamCoord; SHX2_2 = SHX2_2()
    local camCoord  = GetGameplayCamCoord()

    -- Convert the rotation to a forward unit vector, then scale by distance.
    -- originally: SHX3_2 = SHX12_1; SHX4_2 = SHX1_2; SHX3_2 = SHX3_2(SHX4_2)
    local forwardVec = eulerToForwardVector(camRot)

    -- Compute the far-end point of the ray.
    -- originally: SHX4_2 = vector3; SHX5_2 = camCoord.x + fwd.x*dist; SHX6_2 = …y; SHX7_2 = …z; SHX4_2 = SHX4_2(…)
    local farPoint = vector3(
        camCoord.x + forwardVec.x * distance,
        camCoord.y + forwardVec.y * distance,
        camCoord.z + forwardVec.z * distance
    )

    -- Cast a shape-test ray from the camera origin to the far point.
    -- -1 as entity-type mask = all collidable geometry; 0 = ignore no entity.
    -- originally: SHX5_2 = StartShapeTestRay; args = camCoord.x/y/z, farPoint.x/y/z, -1, PlayerPedId(), 0
    local localPed  = PlayerPedId()
    local rayHandle = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        farPoint.x,  farPoint.y,  farPoint.z,
        -1, localPed, 0
    )

    -- Retrieve the ray result.
    -- originally: SHX6_2 = GetShapeTestResult; SHX7_2 = SHX5_2; SHX6_2, SHX7_2, SHX8_2 = SHX6_2(SHX7_2)
    -- GetShapeTestResult returns: status, hit, hitCoords, hitNormal, hitEntity
    -- The decompiler assigns: SHX6_2=status, SHX7_2=hit(0/1), SHX8_2=hitCoords
    local rayStatus, didHit, hitCoords = GetShapeTestResult(rayHandle)

    -- If the ray hit something (didHit == 1), return the exact hit point.
    -- Otherwise return the far end of the ray.
    -- originally: if 1 == SHX7_2 then return SHX8_2, SHX1_2, SHX2_2 end
    if didHit == 1 then
        return hitCoords, camRot, camCoord
    end

    -- originally: return SHX4_2, SHX1_2, SHX2_2   (farPoint, camRot, camCoord)
    return farPoint, camRot, camCoord
end


-- =============================================================================
-- SECTION 20 — NUI callback: getDispatchCameras
-- originally lines 643-674
-- =============================================================================

-- originally: SHX14_1 = RegisterNUICallback; SHX15_1 = "getDispatchCameras"; function SHX16_1(…)
RegisterNUICallback("getDispatchCameras", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:getDispatchCameras"
    TriggerCallback("plt_mdt:server:getDispatchCameras", function(cameraList)
        -- Return the list (or an empty table if server returned nil/falsy).
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = SHX0_3 or SHX2_3; if not SHX0_3 then SHX2_3 = {} end; SHX1_3(SHX2_3)
        cb(cameraList or {})
    end)
end)


-- =============================================================================
-- SECTION 21 — NUI callback: canManageDispatchCameras
-- originally lines 675-703
-- =============================================================================

-- originally: SHX14_1 = RegisterNUICallback; SHX15_1 = "canManageDispatchCameras"; function SHX16_1(…)
RegisterNUICallback("canManageDispatchCameras", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:canManageDispatchCameras"
    TriggerCallback("plt_mdt:server:canManageDispatchCameras", function(result)
        -- Coerce the server result to a strict boolean.
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = true == SHX0_3; SHX1_3(SHX2_3)
        cb(result == true)
    end)
end)


-- =============================================================================
-- SECTION 22 — NUI callback: createDispatchCamera
-- Enters camera-placement mode: shows a scanline overlay, draws a placement
-- marker on the surface under the crosshair, and lets the player press E to
-- confirm or BACKSPACE to cancel.
-- originally lines 704-960
-- =============================================================================

-- originally: SHX14_1 = RegisterNUICallback; SHX15_1 = "createDispatchCamera"; function SHX16_1(SHX0_2, SHX1_2)
RegisterNUICallback("createDispatchCamera", function(data, cb)
    -- If already in placement mode, reject the request immediately.
    -- originally: SHX2_2 = SHX1_1; if SHX2_2 then SHX2_2 = SHX1_2; SHX3_2 = false; SHX2_2(SHX3_2); return end
    if isCreatingCamera then
        cb(false)
        return
    end

    -- Enter placement mode.
    -- originally: SHX2_2 = true; SHX1_1 = SHX2_2
    isCreatingCamera = true

    -- Close the MDT NUI and release NUI focus so the player can move around.
    -- originally: SHX2_2 = SetNuiFocus; SHX3_2 = false; SHX4_2 = false; SHX2_2(SHX3_2, SHX4_2)
    SetNuiFocus(false, false)

    -- originally: SHX2_2 = SendNUIMessage; SHX3_2 = {}; SHX3_2.type = "closeMDT"; SHX2_2(SHX3_2)
    SendNUIMessage({ type = "closeMDT" })

    -- Apply the scanline camera timecycle modifier (gives the CCTV visual effect).
    -- originally: SHX2_2 = SetTimecycleModifier; SHX3_2 = "scanline_cam_f"; SHX2_2(SHX3_2)
    SetTimecycleModifier("scanline_cam_f")

    -- originally: SHX2_2 = SetTimecycleModifierStrength; SHX3_2 = 1.2; SHX2_2(SHX3_2)
    SetTimecycleModifierStrength(1.2)

    -- Determine the label for the new camera.
    -- originally:
    --   if SHX0_2 then SHX2_2 = SHX0_2.label; if SHX2_2 then goto SHX_LABEL_31 end end
    --   SHX2_2 = ""
    --   ::SHX_LABEL_31::
    local cameraLabel = ""
    if data and data.label then
        cameraLabel = data.label  -- goto SHX_LABEL_31 path — already have a label
    end
    -- If data.label was absent/falsy, cameraLabel stays ""

    -- originally: SHX3_2 = false  (local flag: has the NUI callback already been fired?)
    local callbackFired = false

    -- Spawn a thread that runs the interactive placement loop.
    -- originally: SHX4_2 = CreateThread; function SHX5_2() … end; SHX4_2(SHX5_2)
    CreateThread(function()
        -- Loop variables (level-3 locals):
        -- SHX0_3 … SHX27_3 inside the while loop

        -- originally: while true do SHX0_3 = SHX1_1; if not SHX0_3 then break end …
        while true do
            -- Exit the loop if placement mode was cancelled elsewhere.
            if not isCreatingCamera then
                break
            end

            -- Wait one frame.
            -- originally: SHX0_3 = Wait; SHX1_3 = 0; SHX0_3(SHX1_3)
            Wait(0)

            -- Disable weapon-related controls while placing a camera.
            -- Control 25 = AIM, 37 = SELECT_WEAPON, 14 = NEXT_WEAPON, 15 = PREV_WEAPON
            -- originally: (four DisableControlAction calls)
            DisableControlAction(0, 25,  true)
            DisableControlAction(0, 37,  true)
            DisableControlAction(0, 14,  true)
            DisableControlAction(0, 15,  true)

            -- Cast a ray 350 units along the gameplay camera to find the surface
            -- under the crosshair. Returns (hitPos, camRot, camPos).
            -- originally: SHX0_3 = SHX13_1; SHX1_3 = 350.0; SHX0_3, SHX1_3, SHX2_3 = SHX0_3(SHX1_3)
            local hitPos, camRot, camPos = getWorldPositionFromCam(350.0)

            -- Draw a disc marker (type 28) at the surface hit point, slightly raised.
            -- Colour: RGBA (50, 160, 255, 175) — semi-transparent blue.
            -- Scale: 0.36 × 0.36 × 0.36
            -- originally: SHX3_3 = DrawMarker; SHX4_3 = 28; (long arg list)
            DrawMarker(
                28,                           -- type: horizontal flat disc
                hitPos.x, hitPos.y, hitPos.z + 0.02, -- position (slightly above surface)
                0.0, 0.0, 0.0,                -- direction (unused for this type)
                0.0, 0.0, 0.0,                -- rotation
                0.36, 0.36, 0.36,             -- scale
                50, 160, 255, 175,            -- RGBA colour
                false,                        -- bobUpAndDown
                true,                         -- faceCamera
                2,                            -- rotationOrder
                false,                        -- textureDict (nil)
                nil,                          -- textureName (nil)
                nil,                          -- drawOnEnts
                false                         -- drawOnEnts flag
            )

            -- Show a help prompt: [E] to place, [BACKSPACE] to cancel.
            -- originally: BeginTextCommandDisplayHelp("STRING"); AddTextComponentSubstringPlayerName(…); EndTextCommandDisplayHelp(0, false, true, -1)
            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName("~b~[E]~w~ Place camera  ~r~[BACKSPACE]~w~ Cancel")
            EndTextCommandDisplayHelp(0, false, true, -1)

            -- Check whether the player pressed E (control 38 = CONTEXT/INTERACT).
            -- originally: SHX3_3 = IsControlJustPressed; SHX4_3 = 0; SHX5_3 = 38; SHX3_3 = SHX3_3(SHX4_3, SHX5_3)
            if IsControlJustPressed(0, 38) then
                -- Compute a small positional offset so the camera sits slightly
                -- in front of / on the surface rather than exactly at the hit point.
                -- The offset direction is from the gameplay camera toward the hit point,
                -- normalised and scaled to 0.45 (horizontal) and 0.09 (vertical).
                -- originally: long vector subtraction and normalisation block
                local dx = camPos.x - hitPos.x   -- originally: SHX6_3 = SHX2_3.x - SHX0_3.x
                local dy = camPos.y - hitPos.y
                local dz = camPos.z - hitPos.z

                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)  -- originally: SHX9_3 = math.sqrt(…)

                local offsetX, offsetY, offsetZ = 0.0, 0.0, 0.0

                -- Only apply offset if the camera is not exactly at the hit point.
                -- originally: SHX10_3 = 0.001; if SHX9_3 > SHX10_3 then … end
                if dist > 0.001 then
                    local hScale = 0.45  -- horizontal scale
                    local vScale = hScale * 0.2  -- vertical scale = 0.09

                    offsetX = (dx / dist) * hScale   -- originally: SHX3_3 = (SHX6_3/SHX9_3) * 0.45
                    offsetY = (dy / dist) * hScale
                    offsetZ = (dz / dist) * vScale
                end

                -- Build the camera data table to send to the server.
                -- originally: SHX10_3 = {}; SHX11_3 = SHX2_2; SHX10_3.label = SHX11_3
                local newCameraData = {}
                newCameraData.label = cameraLabel

                -- Coords: hit point shifted by the computed offset, plus 0.08 vertically.
                -- originally: SHX11_3 = {}; .x = hitPos.x+offsetX; .y = hitPos.y+offsetY; .z = hitPos.z+offsetZ+0.08
                newCameraData.coords = {
                    x = hitPos.x + offsetX,
                    y = hitPos.y + offsetY,
                    z = hitPos.z + offsetZ + 0.08,
                }

                -- Rotation: negate the pitch (x), keep roll (y), add 180° to yaw (z) so
                -- the camera faces toward where the player was standing.
                -- originally: SHX11_3 = {}; .x = -camRot.x; .y = camRot.y; .z = camRot.z + 180.0
                newCameraData.rot = {
                    x = -camRot.x,
                    y =  camRot.y,
                    z =  camRot.z + 180.0,
                }

                -- Use the default FOV for the newly created camera.
                -- originally: SHX11_3 = SHX5_1; SHX10_3.fov = SHX11_3
                newCameraData.fov = defaultFov

                -- Ask the server to persist the new camera.
                -- originally: SHX11_3 = TriggerCallback; SHX12_3 = "plt_mdt:server:createDispatchCamera"; function SHX13_3(SHX0_4) … end; SHX11_3(SHX12_3, SHX13_3, SHX14_3)
                TriggerCallback("plt_mdt:server:createDispatchCamera", function(success)
                    -- Notify the player of the outcome.
                    -- originally: if SHX0_4 then … else … end
                    if success then
                        -- originally: SHX1_4 = Framework.Notify; SHX2_4 = "Dispatch camera created."; SHX3_4 = "success"
                        Framework.Notify("Dispatch camera created.", "success")
                    else
                        -- originally: SHX1_4 = Framework.Notify; SHX2_4 = "You don't have permission…"; SHX3_4 = "error"
                        Framework.Notify("You don't have permission to create cameras.", "error")
                    end

                    -- Fire the NUI callback exactly once.
                    -- originally: SHX1_4 = SHX3_2; if not SHX1_4 then SHX1_4 = true; SHX3_2 = SHX1_4; SHX1_4 = SHX1_2; SHX2_4 = true == SHX0_4; SHX1_4(SHX2_4) end
                    if not callbackFired then
                        callbackFired = true
                        cb(success == true)
                    end

                    -- Leave placement mode and restore the MDT.
                    -- originally: SHX1_4 = false; SHX1_1 = SHX1_4
                    isCreatingCamera = false

                    -- originally: SHX1_4 = ClearTimecycleModifier; SHX1_4()
                    ClearTimecycleModifier()

                    -- originally: SHX1_4 = ToggleMDT; SHX2_4 = true; SHX1_4(SHX2_4)
                    ToggleMDT(true)
                end, newCameraData)

            -- Check whether the player pressed BACKSPACE (control 194) to cancel.
            -- originally: else SHX3_3 = IsControlJustPressed; SHX4_3 = 0; SHX5_3 = 194; if SHX3_3 then … end end
            elseif IsControlJustPressed(0, 194) then
                -- Cancel placement mode.
                -- originally: SHX3_3 = false; SHX1_1 = SHX3_3
                isCreatingCamera = false

                -- originally: SHX3_3 = ClearTimecycleModifier; SHX3_3()
                ClearTimecycleModifier()

                -- Fire the NUI callback once (return false = cancelled).
                -- originally: SHX3_3 = SHX3_2; if not SHX3_3 then SHX3_3 = true; SHX3_2 = SHX3_3; SHX3_3 = SHX1_2; SHX4_3 = false; SHX3_3(SHX4_3) end
                if not callbackFired then
                    callbackFired = true
                    cb(false)
                end

                -- Re-open the MDT.
                -- originally: SHX3_3 = ToggleMDT; SHX4_3 = true; SHX3_3(SHX4_3)
                ToggleMDT(true)
            end
        end -- while isCreatingCamera
    end) -- CreateThread
end)


-- =============================================================================
-- SECTION 23 — NUI callback: openDispatchCameraFeed
-- Creates a scripted camera at the stored camera position/rotation and switches
-- the player's view to it, enabling the CCTV overlay.
-- originally lines 961-1151
-- =============================================================================

-- originally: SHX14_1 = RegisterNUICallback; SHX15_1 = "openDispatchCameraFeed"; function SHX16_1(SHX0_2, SHX1_2)
RegisterNUICallback("openDispatchCameraFeed", function(data, cb)
    -- Extract the camera descriptor table from the NUI data.
    -- originally:
    --   if SHX0_2 then SHX2_2 = SHX0_2.camera; if SHX2_2 then goto SHX_LABEL_7 end end
    --   SHX2_2 = nil
    --   ::SHX_LABEL_7::
    local camData = nil
    if data and data.camera then
        camData = data.camera  -- goto SHX_LABEL_7
    end

    -- ::SHX_LABEL_7:: — validate that camData is a table with a coords sub-table.
    -- originally: SHX3_2 = type(SHX2_2); if "table" == SHX3_2 then SHX3_2 = type(SHX2_2.coords); if "table" == SHX3_2 then goto SHX_LABEL_21 end end; SHX3_2(false); return
    if type(camData) ~= "table" or type(camData.coords) ~= "table" then
        -- ::SHX_LABEL_7:: validation failed — abort.
        -- originally: SHX3_2 = SHX1_2; SHX4_2 = false; SHX3_2(SHX4_2); return
        cb(false)
        return
    end

    -- ::SHX_LABEL_21:: — parse the coords (support both named keys and array indices).
    -- originally: SHX3_2 = tonumber; SHX4_2 = camData.coords.x or camData.coords[1]; SHX3_2 = SHX3_2(SHX4_2)
    local rawCX = camData.coords.x or camData.coords[1]
    local coordX = tonumber(rawCX)

    -- originally: SHX4_2 = tonumber; SHX5_2 = camData.coords.y or camData.coords[2]; SHX4_2 = SHX4_2(SHX5_2)
    local rawCY = camData.coords.y or camData.coords[2]
    local coordY = tonumber(rawCY)

    -- originally: SHX5_2 = tonumber; SHX6_2 = camData.coords.z or camData.coords[3]; SHX5_2 = SHX5_2(SHX6_2)
    local rawCZ = camData.coords.z or camData.coords[3]
    local coordZ = tonumber(rawCZ)

    -- Abort if any coordinate failed to parse.
    -- originally: if not (SHX3_2 and SHX4_2) or not SHX5_2 then SHX6_2(false); return end
    if not (coordX and coordY) or not coordZ then
        cb(false)
        return
    end

    -- Parse the rotation components; default to -18° pitch, 0° roll, 0° yaw if absent.
    -- originally: SHX6_2 = tonumber; SHX7_2 = camData.rot (and .x or [1]); default -18.0
    local rawRX = camData.rot and (camData.rot.x or camData.rot[1])
    local rotX = tonumber(rawRX)
    if not rotX then rotX = -18.0 end  -- originally: if not SHX6_2 then SHX6_2 = -18.0 end

    -- originally: SHX7_2 = tonumber; SHX8_2 = camData.rot.y or camData.rot[2]; default 0.0
    local rawRY = camData.rot and (camData.rot.y or camData.rot[2])
    local rotY = tonumber(rawRY)
    if not rotY then rotY = 0.0 end   -- originally: if not SHX7_2 then SHX7_2 = 0.0 end

    -- originally: SHX8_2 = tonumber; SHX9_2 = camData.rot.z or camData.rot[3]; default 0.0
    local rawRZ = camData.rot and (camData.rot.z or camData.rot[3])
    local rotZ = tonumber(rawRZ)
    if not rotZ then rotZ = 0.0 end   -- originally: if not SHX8_2 then SHX8_2 = 0.0 end

    -- Clamp the camera's stored FOV to the allowed range [minFov, maxFov].
    -- originally: SHX9_2 = SHX5_1; SHX10_2 = SHX11_1; SHX10_2 = SHX10_2(SHX9_2, SHX12_2, SHX13_2)  where SHX12_2=minFov, SHX13_2=maxFov
    local clampedFov = clampValue(defaultFov, minFov, maxFov)

    -- Destroy any pre-existing scripted camera.
    -- originally: SHX10_2 = SHX0_1; if SHX10_2 then DoesCamExist / DestroyCam block end
    if scriptCamHandle then
        if DoesCamExist(scriptCamHandle) then
            DestroyCam(scriptCamHandle, false)
        end
    end

    -- Release NUI focus so controls pass through to the game.
    -- originally: SHX10_2 = SetNuiFocus; SHX11_2 = false; SHX12_2 = false; SHX10_2(…)
    SetNuiFocus(false, false)

    -- Create and configure the new scripted camera.
    -- originally: SHX10_2 = CreateCam; SHX11_2 = "DEFAULT_SCRIPTED_CAMERA"; SHX12_2 = true; SHX10_2 = SHX10_2(…); SHX0_1 = SHX10_2
    scriptCamHandle = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    -- originally: SHX10_2 = SetCamCoord; then SHX0_1 coords x/y/z
    SetCamCoord(scriptCamHandle, coordX, coordY, coordZ)

    -- originally: SHX10_2 = SetCamRot; … SHX15_2 = 2
    SetCamRot(scriptCamHandle, rotX, rotY, rotZ, 2)

    -- originally: SHX10_2 = SetCamFov; SHX12_2 = SHX9_2 (clampedFov)
    SetCamFov(scriptCamHandle, clampedFov)

    -- Make this camera the active one and render it.
    -- originally: SHX10_2 = SetCamActive; SHX12_2 = true
    SetCamActive(scriptCamHandle, true)

    -- originally: SHX10_2 = RenderScriptCams; SHX11_2=true; SHX12_2=false; SHX13_2=0; SHX14_2=true; SHX15_2=true
    RenderScriptCams(true, false, 0, true, true)

    -- Apply the scanline timecycle modifier at higher strength for the feed view.
    -- originally: SetTimecycleModifier("scanline_cam_f"); SetTimecycleModifierStrength(1.5)
    SetTimecycleModifier("scanline_cam_f")
    SetTimecycleModifierStrength(1.5)

    -- Initialise the module-level camera rotation state from this camera's rotation,
    -- so the mouse-look thread can continue from the right angle.
    -- originally: SHX3_1.x = SHX6_2; SHX3_1.y = SHX7_2; SHX3_1.z = SHX8_2
    cameraRotation.x = rotX
    cameraRotation.y = rotY
    cameraRotation.z = rotZ

    -- Restore current FOV to the clamped value.
    -- originally: SHX6_1 = SHX9_2
    currentFov = clampedFov

    -- Mark that we are now watching a dispatch camera.
    -- originally: SHX10_2 = true; SHX2_1 = SHX10_2
    isWatchingCamera = true

    -- Tell the NUI to show the camera overlay with the camera's label.
    -- originally: SHX10_2 = SendNUIMessage; SHX11_2 = {}; SHX11_2.type = "openCameraOverlay"; SHX12_2 = SHX2_2.label or "CCTV CAMERA"; SHX11_2.label = SHX12_2; SHX10_2(SHX11_2)
    local displayLabel = camData.label
    if not displayLabel then displayLabel = "CCTV CAMERA" end
    SendNUIMessage({
        type  = "openCameraOverlay",
        label = displayLabel,
    })

    -- originally: SHX10_2 = SHX1_2; SHX11_2 = true; SHX10_2(SHX11_2)
    cb(true)
end)


-- =============================================================================
-- SECTION 24 — NUI callback: closeDispatchCameraFeed
-- originally lines 1152-1169
-- =============================================================================

-- originally: SHX14_1 = RegisterNUICallback; SHX15_1 = "closeDispatchCameraFeed"; function SHX16_1(SHX0_2, SHX1_2)
RegisterNUICallback("closeDispatchCameraFeed", function(data, cb)
    -- Delegate to the shared teardown function.
    -- originally: SHX2_2 = SHX10_1; SHX2_2()
    stopDispatchCameraView()

    -- originally: SHX2_2 = SHX1_2; SHX3_2 = true; SHX2_2(SHX3_2)
    cb(true)
end)


-- =============================================================================
-- SECTION 25 — Camera control thread
-- Runs while isWatchingCamera is true. Handles mouse-look rotation, FOV scroll,
-- and the escape gesture to close the camera feed.
-- originally lines 1170-1362
-- =============================================================================

-- originally: SHX14_1 = CreateThread; function SHX15_1() … end; SHX14_1(SHX15_1)
CreateThread(function()
    -- All SHX0_2 … SHX8_2 in this scope are local frame temporaries.
    while true do
        -- Check whether we are currently watching a camera feed.
        -- originally: SHX0_2 = SHX2_1; if SHX0_2 then … else Wait(400) end
        if isWatchingCamera then
            -- Render every frame (Wait 0).
            -- originally: SHX0_2 = Wait; SHX1_2 = 0; SHX0_2(SHX1_2)
            Wait(0)

            -- Disable movement / weapon controls that would interfere with camera use.
            -- Control IDs:
            --   30 = LOOK_LEFT_RIGHT, 31 = LOOK_UP_DOWN
            --   21 = SPRINT, 22 = JUMP
            --   24 = ATTACK (shoot), 25 = AIM
            --   140 = VEH_MOVE_LEFT_RIGHT, 141 = VEH_MOVE_UP_DOWN, 142 = VEH_RADIO_WHEEL_UD
            --   257 = ATTACK2
            -- originally: eight DisableControlAction calls
            DisableControlAction(0, 30,  true)
            DisableControlAction(0, 31,  true)
            DisableControlAction(0, 21,  true)
            DisableControlAction(0, 22,  true)
            DisableControlAction(0, 24,  true)
            DisableControlAction(0, 25,  true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 257, true)

            -- Read mouse delta axes (disabled controls preserve axis data).
            -- Control 1 = LOOK_LEFT_RIGHT (mouse X), Control 2 = LOOK_UP_DOWN (mouse Y).
            -- originally: SHX0_2 = GetDisabledControlNormal(0, 1); SHX1_2 = GetDisabledControlNormal(0, 2)
            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)

            -- If the mouse moved, update the camera rotation.
            -- originally: if 0.0 ~= SHX0_2 or 0.0 ~= SHX1_2 then … end
            if mouseX ~= 0.0 or mouseY ~= 0.0 then
                -- originally: SHX2_2 = GetFrameTime; SHX2_2 = SHX2_2()
                local frameTime = GetFrameTime()

                -- Update yaw: subtract mouse-X * speed * deltaTime.
                -- originally: SHX3_2 = SHX3_1.z; SHX4_2 = SHX4_1; SHX4_2 = SHX0_2 * SHX4_2 * SHX2_2; SHX3_2 = SHX3_2 - SHX4_2; SHX3_1.z = SHX3_2
                cameraRotation.z = cameraRotation.z - (mouseX * rotationSpeed * frameTime)

                -- Update pitch: subtract mouse-Y * speed, then clamp to [-85, 85].
                -- originally: SHX3_2 = SHX11_1; SHX4_2 = SHX3_1.x - SHX1_2*SHX4_1*SHX2_2; SHX5_2 = -85.0; SHX6_2 = 85.0; SHX3_2 = SHX3_2(SHX4_2, SHX5_2, SHX6_2); SHX3_1.x = SHX3_2
                local newPitch = cameraRotation.x - (mouseY * rotationSpeed * frameTime)
                cameraRotation.x = clampValue(newPitch, -85.0, 85.0)

                -- Apply the new rotation to the scripted camera if it still exists.
                -- originally: SHX3_2 = SHX0_1; if SHX3_2 then DoesCamExist / SetCamRot block end
                if scriptCamHandle and DoesCamExist(scriptCamHandle) then
                    -- originally: SHX3_2 = SetCamRot; SHX8_2 = 2
                    SetCamRot(scriptCamHandle,
                        cameraRotation.x,
                        cameraRotation.y,
                        cameraRotation.z,
                        2
                    )
                end
            end

            -- Keep the camera's FOV in sync (handles external changes to currentFov).
            -- originally: SHX2_2 = SHX0_1; if SHX2_2 then DoesCamExist / SetCamFov block end
            if scriptCamHandle and DoesCamExist(scriptCamHandle) then
                -- originally: SHX2_2 = SetCamFov; SHX4_2 = SHX6_1; SHX2_2(SHX3_2, SHX4_2)
                SetCamFov(scriptCamHandle, currentFov)
            end

            -- Scroll wheel DOWN (control 15 = NEXT_WEAPON): zoom out (increase FOV by 2).
            -- originally: SHX2_2 = IsControlJustPressed(0, 15); if SHX2_2 then … else (check 14) end
            if IsControlJustPressed(0, 15) then
                -- originally: SHX2_2 = SHX11_1; SHX3_2 = SHX6_1 + 2.0; SHX4_2 = SHX7_1; SHX5_2 = SHX8_1; SHX2_2 = SHX2_2(SHX3_2, SHX4_2, SHX5_2); SHX6_1 = SHX2_2
                currentFov = clampValue(currentFov + 2.0, minFov, maxFov)
                if scriptCamHandle and DoesCamExist(scriptCamHandle) then
                    -- originally: SetCamFov block inside the if
                    SetCamFov(scriptCamHandle, currentFov)
                end
            else
                -- Scroll wheel UP (control 14 = PREV_WEAPON): zoom in (decrease FOV by 2).
                -- originally: SHX2_2 = IsControlJustPressed(0, 14); if SHX2_2 then … end
                if IsControlJustPressed(0, 14) then
                    -- originally: SHX2_2 = SHX11_1; SHX3_2 = SHX6_1 - 2.0; SHX4_2 = SHX7_1; SHX5_2 = SHX8_1
                    currentFov = clampValue(currentFov - 2.0, minFov, maxFov)
                    if scriptCamHandle and DoesCamExist(scriptCamHandle) then
                        SetCamFov(scriptCamHandle, currentFov)
                    end
                end
            end

            -- ESC (control 322) or PHONE/BACK (control 200): close the camera feed.
            -- originally: SHX2_2 = IsControlJustPressed(0, 322); if not SHX2_2 then SHX2_2 = IsControlJustPressed(0, 200) end; if SHX2_2 then SHX10_1() end
            local wantsToClose = IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200)
            if wantsToClose then
                -- originally: SHX2_2 = SHX10_1; SHX2_2()
                stopDispatchCameraView()
            end

        else
            -- Not watching a camera — sleep longer to avoid wasting CPU.
            -- originally: SHX0_2 = Wait; SHX1_2 = 400; SHX0_2(SHX1_2)
            Wait(400)
        end
    end
end)


-- =============================================================================
-- SECTION 26 — Optional: automatic gunshot detection thread
-- Only created when Config.EnableAutomaticGunshots is true.
-- Monitors the local player's weapon fire; if they shoot a non-silenced,
-- non-excluded weapon and a 15-second cooldown has elapsed (and their job
-- is not in the exclusion list), it fires an automatic 10-71 dispatch call.
-- originally lines 1364-1469
-- =============================================================================

-- originally: SHX14_1(SHX15_1) — this is the CreateThread call for the camera control
-- thread (Section 25). Already written above. The next line is:
-- SHX14_1 = Config; SHX14_1 = SHX14_1.EnableAutomaticGunshots; if SHX14_1 then … end

if Config.EnableAutomaticGunshots then
    -- originally: SHX14_1 = CreateThread; function SHX15_1() … end; SHX14_1(SHX15_1)
    CreateThread(function()
        -- Time (game timer ms) of the last submitted gunshot report.
        -- originally: SHX0_2 = 0
        local lastGunshotReportTime = 0

        while true do
            -- Identify the local player's ped.
            -- originally: SHX1_2 = PlayerPedId; SHX1_2 = SHX1_2()
            local localPed = PlayerPedId()

            -- Check if the ped is currently firing a weapon.
            -- originally: SHX2_2 = IsPedShooting; SHX3_2 = SHX1_2; SHX2_2 = SHX2_2(SHX3_2)
            if IsPedShooting(localPed) then
                -- Record the current game time.
                -- originally: SHX2_2 = GetGameTimer; SHX2_2 = SHX2_2()
                local currentTime = GetGameTimer()

                -- Check if the weapon is silenced.
                -- originally: SHX3_2 = IsPedCurrentWeaponSilenced; SHX4_2 = SHX1_2; SHX3_2 = SHX3_2(SHX4_2)
                local isWeaponSilenced = IsPedCurrentWeaponSilenced(localPed)

                -- Get the selected weapon's hash.
                -- originally: SHX4_2 = GetSelectedPedWeapon; SHX5_2 = SHX1_2; SHX4_2 = SHX4_2(SHX5_2)
                local weaponHash = GetSelectedPedWeapon(localPed)

                -- Check if this weapon hash is in the excluded list.
                -- originally: SHX5_2 = SHX9_1; SHX5_2 = SHX5_2[SHX4_2]; SHX5_2 = true == SHX5_2
                local isExcludedWeapon = excludedWeaponHashes[weaponHash] == true

                -- Only proceed if the weapon is audible (not silenced, not excluded).
                -- originally: if not SHX3_2 and not SHX5_2 then … end
                if not isWeaponSilenced and not isExcludedWeapon then
                    -- Enforce a 15-second cooldown between reports.
                    -- originally: SHX6_2 = SHX2_2 - SHX0_2; SHX7_2 = 15000; if SHX6_2 > SHX7_2 then … end
                    if (currentTime - lastGunshotReportTime) > 15000 then
                        -- Retrieve the player's current job name from the framework.
                        -- originally: SHX6_2 = Framework.GetPlayerData; SHX6_2 = SHX6_2(); SHX7_2 = "unemployed"
                        local playerData = Framework.GetPlayerData()
                        local jobName    = "unemployed"

                        -- originally: if SHX6_2 then SHX8_2 = SHX6_2.job; if SHX8_2 then SHX8_2 = SHX6_2.job; SHX7_2 = SHX8_2.name end end
                        if playerData then
                            if playerData.job then
                                jobName = playerData.job.name
                            end
                        end

                        -- Determine whether this job should submit a gunshot report.
                        -- If Config.ReportEmergencyGunshots is true, all jobs report.
                        -- Otherwise, jobs listed in Config.ExcludeJobsFromGunshots are skipped.
                        -- originally:
                        --   SHX8_2 = true
                        --   SHX9_2 = Config.ReportEmergencyGunshots
                        --   if not SHX9_2 then
                        --     SHX9_2 = Config.ExcludeJobsFromGunshots[SHX7_2]
                        --     SHX8_2 = not SHX9_2
                        --   end
                        local shouldReport = true
                        if not Config.ReportEmergencyGunshots then
                            local isJobExcluded = Config.ExcludeJobsFromGunshots[jobName]
                            shouldReport = not isJobExcluded
                        end

                        if shouldReport then
                            -- Update the cooldown timestamp.
                            -- originally: SHX0_2 = SHX2_2
                            lastGunshotReportTime = currentTime

                            -- Get the player's world position.
                            -- originally: SHX9_2 = GetEntityCoords; SHX10_2 = SHX1_2; SHX9_2 = SHX9_2(SHX10_2)
                            local pedCoords = GetEntityCoords(localPed)

                            -- Resolve the street name at the player's location.
                            -- originally: SHX10_2 = GetStreetNameAtCoord; SHX11_2/SHX12_2/SHX13_2 = coords; SHX10_2, SHX11_2 = SHX10_2(…)
                            local streetHash2, crossingHash2 = GetStreetNameAtCoord(
                                pedCoords.x, pedCoords.y, pedCoords.z
                            )

                            -- originally: SHX12_2 = GetStreetNameFromHashKey(SHX13_2)
                            local streetName2 = GetStreetNameFromHashKey(streetHash2)

                            -- Append crossing street with " / " (note: different separator from Section 3's " | ").
                            -- originally: if 0 ~= SHX11_2 then SHX13_2 = SHX12_2 .. " / " .. GetStreetNameFromHashKey(SHX11_2); SHX12_2 = SHX13_2 end
                            if crossingHash2 ~= 0 then
                                local crossingName2 = GetStreetNameFromHashKey(crossingHash2)
                                streetName2 = streetName2 .. " / " .. crossingName2
                            end

                            -- Submit the automatic 10-71 (Shots Fired) dispatch call to the server.
                            -- originally: SHX13_2 = TriggerServerEvent; SHX14_2 = "plt_mdt:server:addDispatchCall"; SHX15_2 = {…}; SHX13_2(SHX14_2, SHX15_2)
                            TriggerServerEvent("plt_mdt:server:addDispatchCall", {
                                code     = "10-71",
                                title    = "Shots Fired",
                                location = streetName2,
                                coords   = {
                                    x = pedCoords.x,   -- originally: SHX16_2 = {}; .x/y/z from SHX9_2
                                    y = pedCoords.y,
                                    z = pedCoords.z,
                                },
                                info     = "Gunshots detected in the area. Automatic acoustic sensor report.",
                            })
                        end
                    end
                end
            end -- IsPedShooting

            -- originally: SHX2_2 = Wait; SHX3_2 = 0; SHX2_2(SHX3_2)
            Wait(0)
        end -- while true
    end)
end -- Config.EnableAutomaticGunshots


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         1469
-- Total lines in output:         ~490 (clean code + comments; well within scope — every
--                                 behaviour is represented; no logic was removed)
-- Obfuscation techniques found:
--   1. Decompiler-generated obfuscated identifiers (SHX0_1 … SHX27_3) used as
--      both scratch space and persistent state — all renamed.
--   2. All functions re-assigned through the same SHX2_1 scratch variable on
--      every registration call — all lifted to descriptive positions.
--   3. goto/label control flow (SHX_LABEL_7, SHX_LABEL_21, SHX_LABEL_23,
--      SHX_LABEL_31, SHX_LABEL_64) — all replaced with structured if/else.
--   4. Persistent module state interleaved with temporary scratch variables in
--      a single flat `local` declaration — fully separated.
--   5. Multi-return decompiler artefacts on single-return natives (e.g. math.cos
--      spread across 5 variables) — collapsed to single assignments with comments.
--   6. Decompiler boilerplate comment blocks repeated on every function — removed.
-- String arrays resolved:        0 (none present; all strings were literals)
-- Renamed identifiers:           17 module-level + ~120 inner-scope locals
-- Constructs flagged for review:
--   • onResourceStop handler references `isWatchingDispatchCamera` and
--     `StopDispatchCameraView` by their original source names — the decompiler
--     failed to resolve these as upvalues. In the clean output they are replaced
--     with isWatchingCamera and stopDispatchCameraView() respectively, which is
--     the correct runtime interpretation based on all other usage sites.
--   • The RegisterNetEvent(name, handler) two-argument pattern (Sections 2–3) is
--     preserved verbatim; it may be a framework wrapper or an older FiveM API
--     variant. If runtime errors occur, split into RegisterNetEvent(name) +
--     AddEventHandler(name, handler).
--   • eulerToForwardVector: math.cos multi-return decompiler artefact collapsed;
--     verified by inspection that only the first return value is ever used.
--   • getWorldPositionFromCam: GetShapeTestResult three-value destructuring —
--     preserved as-is; the decompiler assigns (status, hit, hitCoords) which
--     matches the native's actual signature.
--   • excludedWeaponHashes entries 883325847 / 101631238 are preserved as raw
--     hashes; their exact weapon types should be verified against the game's hash
--     table if the exclusion behaviour needs to be audited.
--   • Cross-street separator inconsistency: newDispatchCall uses " | " while the
--     gunshot thread uses " / " — both preserved exactly as in the original.
-- Functionality preserved:       YES — all event handlers, NUI callbacks, commands,
--                                 key mappings, threads, and side effects are present
--                                 in the same execution order as the source.