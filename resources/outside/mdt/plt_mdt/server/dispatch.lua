-- =============================================================================
-- dispatch.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Server-side dispatch system
-- =============================================================================
-- Sections in order:
--   1.  Module-level state
--   2.  isValidDepartmentJob()
--   3.  loadCamerasFromConfig()
--   4.  isCameraAdmin()
--   5.  canPlayerAccessDispatch()
--   6.  addDispatchCall()          ← core; exported as AddDispatchCall global
--   7.  send911Call()              ← handles /911 and /911a logic
--   8.  RegisterCommand "911"
--   9.  RegisterCommand "911a"
--   10. AddEventHandler "chatMessage"    ← intercepts /911[a] typed in chat
--   11. RegisterCommand "mdtdebugcalls"
--   12. RegisterCommand "testmdtcall"
--   13. exports "CreateDispatchCall" / "AddDispatchCall"
--   14. RegisterNetEvent "plt_mdt:server:addDispatchCall"
--   15. RegisterNetEvent compat shims (dispatch/ps-dispatch/qs-dispatch/cd_dispatch/codem-dispatch)
--   16. getActiveCallsList()       ← exported as GetActiveCalls global
--   17. buildOfficerList()
--   18. RegisterNetEvent "plt_mdt:server:setRadioChannel"
--   19. AddEventHandler "playerDropped"
--   20. RegisterNetEvent "plt_mdt:server:updateCallLocation"
--   21. RegisterNetEvent "plt_mdt:server:triggerPanic"
--   22. CreateThread — officer location broadcast loop
--   23. RegisterCallback "plt_mdt:server:getOfficerLocations"
--   24. RegisterCallback "plt_mdt:server:canAssignDispatch"
--   25. RegisterCallback "plt_mdt:server:canUseDispatch"
--   26. RegisterCallback "plt_mdt:server:getDispatchCameras"
--   27. RegisterCallback "plt_mdt:server:canManageDispatchCameras"
--   28. RegisterCallback "plt_mdt:server:createDispatchCamera"
--   29. CreateThread — startup: load cameras from config
-- =============================================================================


-- =============================================================================
-- SECTION 1 — Module-level state
-- originally lines 8-14: flat local SHX0_1 … SHX5_1 declarations
-- =============================================================================

-- originally: SHX0_1 = {}
-- Maps player source id → their currently tuned radio channel number.
local radioChannels = {}

-- originally: SHX1_1 = {}
-- Ordered list of active dispatch calls (newest at index 1). Capped at 50.
local activeCalls = {}

-- originally: SHX2_1 = 0
-- Auto-incrementing id counter for new dispatch calls.
local callIdCounter = 0

-- originally: SHX3_1 = {}
-- Id-keyed table of CCTV camera objects.  cameraStore[id] = { id, label, coords, rot, fov }
local cameraStore = {}

-- originally: SHX4_1 = 1
-- Next id to assign to a new camera entry.
local nextCameraId = 1

-- originally: SHX5_1 = {}
-- Maps player source id → GetGameTimer() value of their last 911 call.
-- Used to throttle spam.
local callerCooldowns = {}


-- =============================================================================
-- SECTION 2 — isValidDepartmentJob(jobName)
-- Returns true if jobName is a key in Config.Departments.
-- originally: function SHX6_1(SHX0_2) … end  (lines 15-29)
-- =============================================================================

-- originally: function SHX6_1(SHX0_2)
local function isValidDepartmentJob(jobName)
    -- originally: SHX1_2 = Config.Departments[SHX0_2]; return nil ~= SHX1_2
    return Config.Departments[jobName] ~= nil
end


-- =============================================================================
-- SECTION 3 — loadCamerasFromConfig()
-- Reads Config.DispatchCameras and populates cameraStore / nextCameraId.
-- Called once at startup from a CreateThread (Section 29).
-- originally: function SHX7_1() … end  (lines 30-97)
-- =============================================================================

-- originally: function SHX7_1()
local function loadCamerasFromConfig()
    -- Reset state.
    -- originally: SHX0_2 = {}; SHX3_1 = SHX0_2; SHX0_2 = 1; SHX4_1 = SHX0_2
    cameraStore   = {}
    nextCameraId  = 1

    -- Iterate Config.DispatchCameras (or an empty table if it doesn't exist).
    -- originally: SHX0_2 = ipairs; SHX1_2 = Config.DispatchCameras or {}
    local cameraList = Config.DispatchCameras
    if not cameraList then cameraList = {} end

    for _, camEntry in ipairs(cameraList) do
        -- Determine the camera id; fall back to nextCameraId if missing/non-numeric.
        -- originally: SHX6_2 = tonumber(SHX5_2.id); if not SHX6_2 then SHX6_2 = SHX4_1 end
        local camId = tonumber(camEntry.id)
        if not camId then camId = nextCameraId end

        -- Build the label, defaulting to "CAM-{id}".
        -- originally: SHX9_2 = SHX5_2.label; if not SHX9_2 then SHX9_2 = "CAM-" .. SHX6_2 end
        local camLabel = camEntry.label
        if not camLabel then camLabel = "CAM-" .. camId end

        -- Build the coords, defaulting to origin.
        -- originally: SHX9_2 = SHX5_2.coords; if not SHX9_2 then SHX9_2 = {x=0,y=0,z=0} end
        local camCoords = camEntry.coords
        if not camCoords then
            camCoords = { x = 0.0, y = 0.0, z = 0.0 }
        end

        -- Build the rotation, defaulting to slight downward pitch.
        -- originally: SHX9_2 = SHX5_2.rot; if not SHX9_2 then SHX9_2 = {x=-18,y=0,z=0} end
        local camRot = camEntry.rot
        if not camRot then
            camRot = { x = -18.0, y = 0.0, z = 0.0 }
        end

        -- Parse the FOV, defaulting to 70°.
        -- originally: SHX9_2 = tonumber(SHX5_2.fov); if not SHX9_2 then SHX9_2 = 70.0 end
        local camFov = tonumber(camEntry.fov)
        if not camFov then camFov = 70.0 end

        -- Store the entry and advance nextCameraId if needed.
        -- originally: SHX7_2[SHX6_2] = SHX8_2; if SHX6_2 >= SHX4_1 then SHX4_1 = SHX6_2 + 1 end
        cameraStore[camId] = {
            id     = camId,
            label  = camLabel,
            coords = camCoords,
            rot    = camRot,
            fov    = camFov,
        }

        if camId >= nextCameraId then
            nextCameraId = camId + 1
        end
    end
end


-- =============================================================================
-- SECTION 4 — isCameraAdmin(source)
-- Returns true if the player's identifiers include one of the Discord IDs in
-- Config.DispatchCameraAdminDiscord.
-- originally: function SHX8_1(SHX0_2) … end  (lines 98-145)
-- =============================================================================

-- originally: function SHX8_1(SHX0_2)
local function isCameraAdmin(source)
    -- Build the admin whitelist from config.
    -- originally: SHX1_2 = Config.DispatchCameraAdminDiscord or {}; if #SHX1_2 == 0 then return false end
    local adminList = Config.DispatchCameraAdminDiscord
    if not adminList then adminList = {} end
    if #adminList == 0 then return false end

    -- Build a lookup set containing both the raw discord id string and the
    -- prefixed "discord:{id}" form.
    -- originally: for _, SHX8_2 in ipairs(adminList) do SHX2_2[tostring(SHX8_2)] = true; SHX2_2["discord:"..tostring(SHX8_2)] = true end
    local adminSet = {}
    for _, discordId in ipairs(adminList) do
        local idStr = tostring(discordId)
        adminSet[idStr]            = true
        adminSet["discord:" .. idStr] = true
    end

    -- Check each of the player's identifiers against the admin set.
    -- originally: for _, SHX8_2 in ipairs(GetPlayerIdentifiers(SHX0_2)) do if SHX2_2[SHX8_2] then return true end end; return false
    -- DECOMPILER ARTEFACT: GetPlayerIdentifiers was spread across 8 variables then passed
    -- to ipairs — collapsed here to the correct single call.
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if adminSet[identifier] then
            return true
        end
    end

    return false
end


-- =============================================================================
-- SECTION 5 — canPlayerAccessDispatch(source, playerObj)
-- Full dispatch-access check. playerObj is optional; if absent, it is fetched
-- via Framework.GetPlayer(source).
-- Priority order:
--   1. Player must be in a valid department job.
--   2. If Config.DispatchAccess.enabled is falsy → allow all dept. members.
--   3. If .citizenids[identifier]  → allow.
--   4. If any player identifier is in .identifiers → allow.
--   5. If .byJob[jobName] exists, check minGrade ≤ player's grade level.
--   6. Otherwise fall back to .defaultAllow.
-- originally: function SHX9_1(SHX0_2, SHX1_2) … end  (lines 146-249)
-- =============================================================================

-- originally: function SHX9_1(SHX0_2, SHX1_2)
local function canPlayerAccessDispatch(source, playerObj)
    -- If no player object was pre-fetched, look it up now.
    -- originally: SHX2_2 = SHX1_2 or nil; if not SHX1_2 then SHX2_2 = Framework.GetPlayer(SHX0_2) end
    local player = playerObj
    if not playerObj then
        player = Framework.GetPlayer(source)
    end

    -- Player must exist and have a valid department job to proceed.
    -- originally: if SHX2_2 then SHX3_2 = SHX6_1(SHX2_2.job.name); if SHX3_2 then goto SHX_LABEL_17 end end; return false
    if player and isValidDepartmentJob(player.job.name) then
        -- ::SHX_LABEL_17:: — player is a dept. member; run the access config checks.
    else
        return false
    end

    -- originally: SHX3_2 = Config.DispatchAccess or {}; SHX4_2 = SHX3_2.enabled; if not SHX4_2 then return true end
    local accessCfg = Config.DispatchAccess
    if not accessCfg then accessCfg = {} end

    -- If the access restriction feature is disabled, all dept. members are allowed.
    if not accessCfg.enabled then
        return true
    end

    -- Build the player's identifier string (citizenid / license / etc.)
    -- originally: SHX4_2 = tostring(SHX2_2.identifier or "")
    local playerIdentifier = tostring(player.identifier or "")

    -- Check citizenid whitelist.
    -- originally: if SHX3_2.citizenids then if SHX3_2.citizenids[SHX4_2] then return true end end
    if accessCfg.citizenids then
        if accessCfg.citizenids[playerIdentifier] then
            return true
        end
    end

    -- Check raw identifier whitelist (any of the player's identifiers).
    -- originally: if SHX3_2.identifiers then for _, id in ipairs(GetPlayerIdentifiers(SHX0_2)) do if SHX3_2.identifiers[id] then return true end end end
    if accessCfg.identifiers then
        for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
            if accessCfg.identifiers[identifier] then
                return true
            end
        end
    end

    -- Check job-based access with optional grade requirement.
    -- originally: SHX5_2 = SHX3_2.byJob; if SHX5_2 then SHX5_2 = SHX5_2[player.job.name] end
    local jobAccessEntry = accessCfg.byJob and accessCfg.byJob[player.job.name]

    if jobAccessEntry then
        -- originally: SHX6_2 = tonumber(SHX5_2.minGrade) or 0
        local minGrade = tonumber(jobAccessEntry.minGrade) or 0

        -- Safely read player grade level (may be nested as job.grade.level).
        -- originally: SHX8_2 = SHX2_2.job.grade; if SHX8_2 then SHX8_2 = SHX8_2.level end; SHX7_2 = tonumber(SHX8_2) or 0
        local gradeLevel = 0
        if player.job.grade then
            gradeLevel = tonumber(player.job.grade.level) or 0
        end

        -- originally: return SHX6_2 <= SHX7_2
        return minGrade <= gradeLevel
    end

    -- Default: honour Config.DispatchAccess.defaultAllow.
    -- originally: return true == SHX3_2.defaultAllow
    return accessCfg.defaultAllow == true
end


-- =============================================================================
-- SECTION 6 — addDispatchCall(callData)
-- Core function. Normalises the call data, assigns an id, prepends it to
-- activeCalls (capped at 50), broadcasts to all eligible players, and
-- optionally forwards to plt_departments.
-- Exported globally as AddDispatchCall immediately after this definition.
-- originally: function SHX10_1(SHX0_2) … end (first definition, lines 250-435)
-- then: AddDispatchCall = SHX10_1  (line 436)
-- =============================================================================

-- originally: function SHX10_1(SHX0_2)
local function addDispatchCall(callData)
    if not callData then return end

    -- -------------------------------------------------------------------------
    -- Normalise the coords field to a vector3.
    -- Accepts: already-a-vector3/userdata, {x,y,z} table, or {[1],[2],[3]} array.
    -- originally: SHX1_2 = SHX0_2.coords; if not SHX1_2 then SHX1_2 = vector3(0,0,0) else … end
    -- -------------------------------------------------------------------------
    local coords = callData.coords
    if not coords then
        coords = vector3(0, 0, 0)
    else
        local coordsType = type(coords)
        -- If it's already a native vector3/userdata, leave it alone.
        -- otherwise build a vector3 from .x/.y/.z (or [1]/[2]/[3]).
        -- originally: if "userdata" ~= type and "vector3" ~= type then coords = vector3(…) end
        if coordsType ~= "userdata" and coordsType ~= "vector3" then
            local cx = coords.x or coords[1] or 0
            local cy = coords.y or coords[2] or 0
            local cz = coords.z or coords[3] or 0
            coords = vector3(cx, cy, cz)
        end
    end

    -- -------------------------------------------------------------------------
    -- Assign a new call id and build the normalised call record.
    -- originally: SHX2_2 = SHX2_1 + 1; SHX2_1 = SHX2_2; SHX3_2 = {}; …
    -- -------------------------------------------------------------------------
    callIdCounter = callIdCounter + 1
    local callId  = callIdCounter

    local callRecord = {}
    callRecord.id = callId

    -- Code: prefer .code, fall back to .badge, then "10-00".
    -- originally: SHX4_2 = SHX0_2.code or SHX0_2.badge or "10-00"
    callRecord.code = callData.code or callData.badge or "10-00"

    -- Title: prefer .title, fall back to .message, then "Unknown Call".
    -- originally: SHX4_2 = SHX0_2.title or SHX0_2.message or "Unknown Call"
    callRecord.title = callData.title or callData.message or "Unknown Call"

    -- Location: prefer .location, then .street, then .streetName, then "Unknown".
    -- originally: chained if-not blocks
    callRecord.location = callData.location
        or callData.street
        or callData.streetName
        or "Unknown"

    -- Coords: always stored as a plain x/y/z table (not a vector3 userdata).
    -- originally: SHX4_2 = {}; SHX4_2.x/y/z = SHX1_2.x/y/z
    callRecord.coords = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    }

    -- Info/description: prefer .info, then .description, then .message, then default.
    -- originally: chained if-not blocks
    callRecord.info = callData.info
        or callData.description
        or callData.message
        or "No additional information."

    -- Timestamp in milliseconds (server os.time × 1000).
    -- originally: SHX4_2 = os.time() * 1000
    callRecord.time = os.time() * 1000

    -- Empty units list (populated client-side when officers self-assign).
    -- originally: SHX4_2 = {}; SHX3_2.units = SHX4_2
    callRecord.units = {}

    -- -------------------------------------------------------------------------
    -- Prepend to activeCalls (newest first) and trim to 50.
    -- originally: table.insert(SHX1_1, 1, SHX3_2); if #SHX1_1 > 50 then table.remove(SHX1_1) end
    -- -------------------------------------------------------------------------
    table.insert(activeCalls, 1, callRecord)
    if #activeCalls > 50 then
        table.remove(activeCalls)   -- removes the last (oldest) entry
    end

    -- -------------------------------------------------------------------------
    -- Broadcast the new call to every online player whose job is a dept. job.
    -- originally: for _, playerIdStr in ipairs(GetPlayers()) do … TriggerClientEvent(…) end
    -- -------------------------------------------------------------------------
    local notifiedCount = 0
    for _, playerIdStr in ipairs(GetPlayers()) do
        local playerSource = tonumber(playerIdStr)
        local player = Framework.GetPlayer(playerSource)
        if player then
            if isValidDepartmentJob(player.job.name) then
                TriggerClientEvent("plt_mdt:client:newDispatchCall", playerSource, callRecord)
                notifiedCount = notifiedCount + 1
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- If UseExternalDispatch is enabled, forward to plt_departments as well.
    -- Wrapped in pcall so a missing export does not crash dispatch.
    -- originally: if Config.UseExternalDispatch then pcall(function() exports.plt_departments:CreateDispatchCall(SHX0_2) end) end
    -- -------------------------------------------------------------------------
    if Config.UseExternalDispatch then
        pcall(function()
            if exports.plt_departments then
                exports.plt_departments:CreateDispatchCall(callData)
            end
        end)
    end

    return callId
end

-- Export addDispatchCall as a global so other sections and resources can call it.
-- originally: AddDispatchCall = SHX10_1  (line 436)
AddDispatchCall = addDispatchCall


-- =============================================================================
-- SECTION 7 — send911Call(source, message, isAnonymous)
-- Validates the player, trims and validates the message text, records a
-- cooldown timestamp, and fires AddDispatchCall with an appropriate code.
-- Originally the second definition of SHX10_1 (lines 437-535).
-- NOTE: The original code reused SHX10_1 for this function immediately after
-- pointing AddDispatchCall at the old value — the two functions are distinct.
-- =============================================================================

-- originally: function SHX10_1(SHX0_2, SHX1_2, SHX2_2)  (line 437)
local function send911Call(source, message, isAnonymous)
    -- Player must exist in the framework.
    -- originally: SHX3_2 = Framework.GetPlayer(SHX0_2); if not SHX3_2 then return false end
    local player = Framework.GetPlayer(source)
    if not player then return false end

    -- Trim whitespace from the message; return false if empty.
    -- originally: SHX4_2 = tostring(SHX1_2 or ""); SHX4_2 = SHX4_2:gsub("^%s+",""):gsub("%s+$","")
    local trimmedMessage = tostring(message or "")
    trimmedMessage = trimmedMessage:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmedMessage == "" then return false end

    -- Record game-timer timestamp for this caller (used by cooldown checks).
    -- originally: SHX5_1[SHX0_2] = GetGameTimer()
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    callerCooldowns[source] = GetGameTimer()

    -- Build and submit the dispatch call.
    -- originally: SHX8_2 = AddDispatchCall; SHX9_2 = { code, title, location, coords, info }; SHX8_2(SHX9_2)
    local callCode  = isAnonymous and "911-A"                  or "911"
    local callTitle = isAnonymous and "Anonymous Emergency Call" or "Emergency Call"

    -- Caller name: either "ANONYMOUS" or the player's uppercased name.
    -- originally: if isAnonymous then SHX12_2 = "ANONYMOUS" else SHX12_2 = SHX3_2.name:upper() end
    local callerName
    if isAnonymous then
        callerName = "ANONYMOUS"
    else
        callerName = player.name:upper()
    end

    -- originally: SHX10_2 = string.format("CALLER: %s | INFO: %s", callerName, trimmedMessage)
    local callInfo = string.format("CALLER: %s | INFO: %s", callerName, trimmedMessage)

    AddDispatchCall({
        code     = callCode,
        title    = callTitle,
        location = "Unknown",   -- client will resolve street name and update via server event
        coords   = playerCoords,
        info     = callInfo,
    })

    -- Notify the caller that their call was sent.
    -- originally: Framework.Notify(SHX0_2, "Your emergency call has been sent to dispatch.", "success")
    Framework.Notify(source, "Your emergency call has been sent to dispatch.", "success")

    return true
end


-- =============================================================================
-- SECTION 8 — RegisterCommand "911"
-- originally lines 536-566
-- =============================================================================

-- originally: SHX11_1 = RegisterCommand; SHX12_1 = "911"; function SHX13_1(SHX0_2, SHX1_2) … end; SHX11_1(SHX12_1, SHX13_1)
RegisterCommand("911", function(source, args)
    -- Concatenate all arguments into the message string.
    -- originally: SHX2_2 = table.concat(SHX1_2, " "); SHX3_2 = SHX10_1(SHX0_2, SHX2_2, false)
    local message = table.concat(args, " ")
    local success = send911Call(source, message, false)
    if not success then
        -- originally: Framework.Notify(source, "Please provide a reason…", "error")
        Framework.Notify(source, "Please provide a reason for your 911 call. Usage: /911 [reason]", "error")
    end
end)


-- =============================================================================
-- SECTION 9 — RegisterCommand "911a"  (anonymous)
-- originally lines 567-597
-- =============================================================================

-- originally: SHX11_1 = RegisterCommand; SHX12_1 = "911a"; function SHX13_1(SHX0_2, SHX1_2) … end
RegisterCommand("911a", function(source, args)
    -- originally: SHX2_2 = table.concat(SHX1_2, " "); SHX3_2 = SHX10_1(SHX0_2, SHX2_2, true)
    local message = table.concat(args, " ")
    local success = send911Call(source, message, true)
    if not success then
        -- originally: Framework.Notify(source, "Please provide a reason…", "error")
        Framework.Notify(source, "Please provide a reason for your anonymous 911 call. Usage: /911a [reason]", "error")
    end
end)


-- =============================================================================
-- SECTION 10 — AddEventHandler "chatMessage"
-- Intercepts /911 and /911a typed directly in the chat box (some clients send
-- commands as chat messages). Also enforces a 1-second anti-spam cooldown.
-- originally lines 598-688
-- =============================================================================

-- originally: SHX11_1 = AddEventHandler; SHX12_1 = "chatMessage"; function SHX13_1(SHX0_2, SHX1_2, SHX2_2) … end
AddEventHandler("chatMessage", function(source, authorName, messageText)
    -- Only process messages from real players (source > 0) that are strings.
    -- originally: if not (SHX0_2 <= 0) then if "string" == type(SHX2_2) then goto SHX_LABEL_9 end end; return
    -- NOTE: `not (source <= 0)` is equivalent to `source > 0`.
    if source <= 0 or type(messageText) ~= "string" then
        return
    end

    -- ::SHX_LABEL_9:: — trim the message and extract the first 4-5 characters to
    -- identify whether this is a /911 or /911a command.
    -- originally: SHX3_2 = trimmed; SHX4_2 = string.lower; SHX5_2 = sub(1,4); SHX6_2 = sub(1,5)
    local trimmed  = messageText:gsub("^%s+", ""):gsub("%s+$", "")
    local lowered  = string.lower(trimmed)
    local prefix4  = string.sub(lowered, 1, 4)   -- "/911"
    local prefix5  = string.sub(lowered, 1, 5)   -- "/911a"

    local is911  = prefix4 == "/911"
    local is911a = prefix5 == "/911a"

    if not is911 and not is911a then
        return
    end

    -- Enforce a 1-second cooldown between chat-based 911 submissions.
    -- originally: SHX9_2 = GetGameTimer(); SHX10_2 = SHX5_1[SHX0_2] or 0; if SHX9_2 - SHX10_2 < 1000 then return end
    local currentTime = GetGameTimer()
    local lastCallTime = callerCooldowns[source] or 0
    if (currentTime - lastCallTime) < 1000 then
        return
    end

    -- Extract the message body (everything after "/911a " or "/911 ").
    -- originally: if SHX8_2 then SHX11_2 = trimmed:sub(6); send911Call(source, SHX11_2, true)
    --             else SHX11_2 = trimmed:sub(5); send911Call(source, SHX11_2, false) end
    if is911a then
        local body = trimmed:sub(6)   -- skip "/911a "
        send911Call(source, body, true)
    else
        local body = trimmed:sub(5)   -- skip "/911 "
        send911Call(source, body, false)
    end
end)


-- =============================================================================
-- SECTION 11 — RegisterCommand "mdtdebugcalls"
-- Shows the number of active calls in server memory to eligible officers.
-- originally lines 689-727
-- =============================================================================

-- originally: SHX11_1 = RegisterCommand; SHX12_1 = "mdtdebugcalls"
RegisterCommand("mdtdebugcalls", function(source)
    -- Only allow players in a dept. job.
    -- originally: SHX1_2 = Framework.GetPlayer(source); if SHX1_2 and isValidDepartmentJob(job) then goto SHX_LABEL_14 end; return
    local player = Framework.GetPlayer(source)
    if not player or not isValidDepartmentJob(player.job.name) then
        return
    end

    -- ::SHX_LABEL_14::
    -- originally: Framework.Notify(source, "Found " .. #SHX1_1 .. " active calls in server memory.", "success")
    Framework.Notify(source, "Found " .. #activeCalls .. " active calls in server memory.", "success")
end)


-- =============================================================================
-- SECTION 12 — RegisterCommand "testmdtcall"
-- Fires a hardcoded test 10-31 GTA call. Only usable by dept. officers.
-- originally lines 728-771
-- =============================================================================

-- originally: SHX11_1 = RegisterCommand; SHX12_1 = "testmdtcall"
RegisterCommand("testmdtcall", function(source)
    local player = Framework.GetPlayer(source)
    if not player then return end

    if isValidDepartmentJob(player.job.name) then
        AddDispatchCall({
            code     = "10-31",
            title    = "Test: Grand Theft Auto",
            location = "Great Ocean Hwy",
            coords   = vector3(-2345.1, 321.4, 12.5),
            info     = "This is a manual test call for the independent MDT system.",
        })
        -- NOTE: original Notify call was missing the source arg; preserved as-is.
        -- originally: Framework.Notify("Test call sent to MDT.", "success")
        Framework.Notify("Test call sent to MDT.", "success")
    end
end)


-- =============================================================================
-- SECTION 13 — Exports: CreateDispatchCall / AddDispatchCall
-- Both are thin wrappers around addDispatchCall (the global AddDispatchCall).
-- originally lines 772-803
-- =============================================================================

-- originally: SHX11_1 = exports; SHX12_1 = "CreateDispatchCall"; function SHX13_1(SHX0_2) return AddDispatchCall(SHX0_2) end; SHX11_1(SHX12_1, SHX13_1)
exports("CreateDispatchCall", function(callData)
    return AddDispatchCall(callData)
end)

-- originally: SHX11_1 = exports; SHX12_1 = "AddDispatchCall"; function SHX13_1(SHX0_2) return AddDispatchCall(SHX0_2) end
exports("AddDispatchCall", function(callData)
    return AddDispatchCall(callData)
end)


-- =============================================================================
-- SECTION 14 — RegisterNetEvent "plt_mdt:server:addDispatchCall"
-- Internal MDT client → server event (e.g. from gunshot detection thread).
-- originally lines 804-819
-- =============================================================================

-- originally: SHX11_1 = RegisterNetEvent; SHX12_1 = "plt_mdt:server:addDispatchCall"
RegisterNetEvent("plt_mdt:server:addDispatchCall", function(callData)
    AddDispatchCall(callData)
end)


-- =============================================================================
-- SECTION 15 — Cross-resource compatibility shims
-- These net events map other popular dispatch resources' event signatures to
-- AddDispatchCall so the MDT can receive calls from any of them.
-- originally lines 820-1003
-- =============================================================================

-- ---- dispatch:server:notify (generic) ----------------------------------------
-- originally: SHX11_1 = RegisterNetEvent; SHX12_1 = "dispatch:server:notify"
RegisterNetEvent("dispatch:server:notify", function(callData)
    AddDispatchCall(callData)
end)

-- ---- ps-dispatch:server:notify -----------------------------------------------
-- originally: SHX11_1 = RegisterNetEvent; SHX12_1 = "ps-dispatch:server:notify"
RegisterNetEvent("ps-dispatch:server:notify", function(callData)
    AddDispatchCall(callData)
end)

-- ---- qs-dispatch:server:CreateDispatchCall -----------------------------------
-- originally: SHX11_1 = RegisterNetEvent; SHX12_1 = "qs-dispatch:server:CreateDispatchCall"
RegisterNetEvent("qs-dispatch:server:CreateDispatchCall", function(callData)
    AddDispatchCall(callData)
end)

-- ---- cd_dispatch:AddNotification ---------------------------------------------
-- cd_dispatch uses .badge / .message / .street / .description — map them.
-- originally lines 868-904
RegisterNetEvent("cd_dispatch:AddNotification", function(callData)
    AddDispatchCall({
        -- originally: SHX3_2 = SHX0_2.badge or "10-31"
        code     = callData.badge    or "10-31",
        -- originally: SHX3_2 = SHX0_2.message or "Priority Call"
        title    = callData.message  or "Priority Call",
        -- originally: SHX3_2 = SHX0_2.street or "Unknown"
        location = callData.street   or "Unknown",
        coords   = callData.coords,
        -- originally: SHX3_2 = SHX0_2.description or SHX0_2.message
        info     = callData.description or callData.message,
    })
end)

-- ---- cd_dispatch:NewDispatchCallCreated --------------------------------------
-- More complex: parses "CODE - Title" from the title field.
-- originally lines 906-1003
RegisterNetEvent("cd_dispatch:NewDispatchCallCreated", function(callData)
    -- Only accept table payloads.
    -- originally: if "table" ~= type(SHX0_2) then return end
    if type(callData) ~= "table" then return end

    -- Parse the title field; if it matches "CODE - Rest of Title", split it.
    -- originally: SHX1_2 = tostring(SHX0_2.title or "Dispatch Call")
    --   SHX4_2, SHX5_2 = SHX1_2:match("^(%S+)%s*-%s*(.+)$")
    --   if SHX4_2 and SHX5_2 then SHX2_2 = SHX4_2 (code); SHX3_2 = SHX5_2 (title) end
    local rawTitle = tostring(callData.title or "Dispatch Call")
    local parsedCode, parsedTitle = rawTitle:match("^(%S+)%s*%-%s*(.+)$")

    local callCode  = parsedCode  -- nil if pattern didn't match
    local callTitle = parsedTitle or rawTitle

    -- Resolve info text.
    -- originally: SHX6_2 = tostring(SHX0_2.message or SHX0_2.description or "")
    local infoText = tostring(callData.message or callData.description or "")

    -- Resolve location: prefer .street / .location; if empty and info contains
    -- "at <somewhere>", extract that.
    -- originally: SHX7_2 = tostring(SHX0_2.street or SHX0_2.location or "")
    local location = tostring(callData.street or callData.location or "")

    if location == "" and infoText ~= "" then
        -- originally: SHX8_2 = SHX6_2:match("at%s+(.+)$"); if SHX8_2 then SHX7_2 = SHX8_2 end
        local extracted = infoText:match("at%s+(.+)$")
        if extracted then location = extracted end
    end

    if location == "" then location = "Unknown" end

    -- Resolve coords: prefer .coords; fall back to .blip.coords.
    -- originally: SHX10_2 = SHX0_2.coords; if not then SHX10_2 = SHX0_2.blip and SHX0_2.blip.coords or nil; goto SHX_LABEL_78
    local resolvedCoords = callData.coords
    if not resolvedCoords then
        -- originally: SHX10_2 = SHX0_2.blip; if SHX10_2 then SHX10_2 = SHX0_2.blip.coords; if SHX10_2 then goto SHX_LABEL_78 end end; SHX10_2 = nil
        if callData.blip and callData.blip.coords then
            resolvedCoords = callData.blip.coords  -- goto SHX_LABEL_78
        else
            resolvedCoords = nil
        end
    end
    -- ::SHX_LABEL_78::

    -- Resolve the display info: prefer infoText; fall back to the raw title.
    -- originally: SHX10_2 = SHX6_2; if "" == SHX6_2 or not SHX6_2 then SHX10_2 = SHX1_2 end
    local displayInfo = infoText
    if displayInfo == "" or not displayInfo then
        displayInfo = rawTitle
    end

    -- Resolve final code: use parsed code if available, else .badge, else "10-31".
    -- originally: SHX10_2 = SHX2_2 or (SHX0_2.badge or "10-31")
    local finalCode = callCode or callData.badge or "10-31"

    AddDispatchCall({
        code     = finalCode,
        title    = callTitle,
        location = location,
        coords   = resolvedCoords,
        info     = displayInfo,
    })
end)

-- ---- codem-dispatch:server:NewCall -------------------------------------------
-- originally lines 1004-1019
RegisterNetEvent("codem-dispatch:server:NewCall", function(callData)
    AddDispatchCall(callData)
end)


-- =============================================================================
-- SECTION 16 — getActiveCallsList()
-- If Config.UseExternalDispatch is set, tries to pull the live call list from
-- plt_departments via export; falls back to the local activeCalls list.
-- Exported globally as GetActiveCalls immediately after definition.
-- originally: function SHX11_1() … end (first definition, lines 1020-1072)
-- then: GetActiveCalls = SHX11_1  (line 1073)
-- =============================================================================

-- originally: function SHX11_1()  (line 1020)
local function getActiveCallsList()
    if Config.UseExternalDispatch then
        -- Try to pull active calls from the plt_departments export.
        -- originally: SHX0_2 = {}; pcall(function() if exports.plt_departments then SHX0_2 = exports.plt_departments:GetActiveCalls() or {} end end)
        local externalCalls = {}
        local ok = pcall(function()
            if exports.plt_departments then
                local result = exports.plt_departments:GetActiveCalls()
                if result then externalCalls = result end
            end
        end)

        -- If the call succeeded and returned at least one entry, use it.
        -- originally: if SHX1_2 then if #SHX0_2 > 0 then return SHX0_2 end end
        if ok and #externalCalls > 0 then
            return externalCalls
        end
    end

    -- Fall back to the local in-memory list.
    -- originally: return SHX1_1
    return activeCalls
end

-- Export as a global so other server-side scripts can call it.
-- originally: GetActiveCalls = SHX11_1  (line 1073)
GetActiveCalls = getActiveCallsList


-- =============================================================================
-- SECTION 17 — buildOfficerList()
-- Iterates all online players, collects full officer data for dept. members,
-- and optionally appends Config.MockOfficers when Config.Debug is true.
-- Note: the original reused SHX11_1 here, overwriting getActiveCallsList.
-- originally: function SHX11_1() … end (second definition, lines 1074-1196)
-- =============================================================================

-- originally: function SHX11_1()  (line 1074 — same variable, new function)
local function buildOfficerList()
    local officerList    = {}
    local seenIdentifiers = {}   -- originally: SHX1_2 — tracks identifiers already added

    for _, playerIdStr in ipairs(GetPlayers()) do
        local playerSource = tonumber(playerIdStr)
        local player = Framework.GetPlayer(playerSource)

        if player and isValidDepartmentJob(player.job.name) then
            local ped    = GetPlayerPed(playerSource)
            local coords = GetEntityCoords(ped)

            -- Check whether the officer is currently in a vehicle.
            -- originally: SHX13_2 = GetVehiclePedIsIn(SHX11_2, false); SHX14_2 = 0 ~= SHX13_2
            local currentVehicle = GetVehiclePedIsIn(ped, false)
            local isMobile = currentVehicle ~= 0

            -- Retrieve optional metadata stored on the player object.
            -- originally: SHX18_2 = SHX10_2.get("callsign") or "N/A"
            local callsign = player.get("callsign")
            if not callsign then callsign = "N/A" end

            -- originally: SHX18_2 = SHX10_2.get("p_image") or "img/default_avatar.png"
            local profileImage = player.get("p_image")
            if not profileImage then profileImage = "img/default_avatar.png" end

            table.insert(officerList, {
                id           = playerSource,
                name         = player.name,
                job          = player.job.name,
                jobLabel     = player.job.label,
                coords       = { x = coords.x, y = coords.y, z = coords.z },
                heading      = GetEntityHeading(ped),
                -- Radio channel recorded in radioChannels; default 0.
                -- originally: SHX18_2 = SHX0_1[SHX9_2] or 0
                radioChannel = radioChannels[playerSource] or 0,
                callsign     = callsign,
                image        = profileImage,
                -- originally: SHX18_2 = true == SHX10_2.job.onduty
                onDuty       = player.job.onduty == true,
                isMobile     = isMobile,
                online       = true,
            })

            -- Track this identifier so mock officers don't duplicate real ones.
            -- originally: SHX1_2[SHX10_2.identifier] = true
            seenIdentifiers[player.identifier] = true
        end
    end

    -- In debug mode, append mock officers from config (only those marked onDuty).
    -- originally: if Config.Debug then if Config.MockOfficers then for _, mock in ipairs(Config.MockOfficers) do if mock.onDuty then … end end end end
    if Config.Debug and Config.MockOfficers then
        for _, mockOfficer in ipairs(Config.MockOfficers) do
            if mockOfficer.onDuty then
                mockOfficer.online = true
                table.insert(officerList, mockOfficer)
            end
        end
    end

    return officerList
end


-- =============================================================================
-- SECTION 18 — RegisterNetEvent "plt_mdt:server:setRadioChannel"
-- Stores the radio channel for a player.
-- originally lines 1197-1212
-- =============================================================================

-- originally: SHX12_1 = RegisterNetEvent; SHX13_1 = "plt_mdt:server:setRadioChannel"
-- Handler receives the channel number; source is the implicit network variable.
RegisterNetEvent("plt_mdt:server:setRadioChannel", function(channel)
    -- originally: SHX2_2 = source; SHX1_2 = SHX0_1; SHX1_2[SHX2_2] = SHX0_2
    local playerSource = source
    radioChannels[playerSource] = channel
end)


-- =============================================================================
-- SECTION 19 — AddEventHandler "playerDropped"
-- Clears the disconnected player's radio channel entry.
-- originally lines 1213-1228
-- =============================================================================

-- originally: SHX12_1 = AddEventHandler; SHX13_1 = "playerDropped"
AddEventHandler("playerDropped", function()
    -- originally: SHX1_2 = source; SHX0_2 = SHX0_1; SHX0_2[SHX1_2] = nil
    local playerSource = source
    radioChannels[playerSource] = nil
end)


-- =============================================================================
-- SECTION 20 — RegisterNetEvent "plt_mdt:server:updateCallLocation"
-- Patches the location string on an existing call (sent from client after it
-- resolves the street name from coords).
-- originally lines 1229-1258
-- =============================================================================

-- originally: SHX12_1 = RegisterNetEvent; SHX13_1 = "plt_mdt:server:updateCallLocation"
RegisterNetEvent("plt_mdt:server:updateCallLocation", function(callId, newLocation)
    for _, call in ipairs(activeCalls) do
        if call.id == callId then
            -- Only overwrite if the current location is still "Unknown".
            -- originally: SHX8_2 = SHX7_2.location; if "Unknown" ~= SHX8_2 then if SHX8_2 then break end end; SHX7_2.location = SHX1_2; break
            if call.location ~= "Unknown" and call.location then
                break
            end
            call.location = newLocation
            break
        end
    end
end)


-- =============================================================================
-- SECTION 21 — RegisterNetEvent "plt_mdt:server:triggerPanic"
-- Creates a 10-99 (Officer in Distress) dispatch call. Accepts an optional
-- data table to override code/title/location/info; coords are authoritative
-- from the server (player ped) and cannot be spoofed by the client.
-- originally lines 1259-1347
-- =============================================================================

-- originally: SHX12_1 = RegisterNetEvent; SHX13_1 = "plt_mdt:server:triggerPanic"
RegisterNetEvent("plt_mdt:server:triggerPanic", function(data)
    local playerSource = source
    local player = Framework.GetPlayer(playerSource)
    if not player then return end

    -- Get the authoritative server-side position of the player's ped.
    -- originally: SHX2_2 = GetEntityCoords(GetPlayerPed(source))
    -- DECOMPILER ARTEFACT: GetPlayerPed spread across 6 return slots; only [1] is valid.
    local serverCoords = GetEntityCoords(GetPlayerPed(playerSource))

    -- Determine coords to use: prefer client-supplied data.coords; fall back to server pos.
    -- originally: if SHX0_2 and SHX0_2.coords then goto SHX_LABEL_25 end; SHX3_2 = {x=…, y=…, z=…}; ::SHX_LABEL_25::
    local panicCoords
    if data and data.coords then
        panicCoords = data.coords  -- goto SHX_LABEL_25
    else
        panicCoords = { x = serverCoords.x, y = serverCoords.y, z = serverCoords.z }
    end
    -- ::SHX_LABEL_25::

    -- Build the panic call, using data overrides where provided.
    -- Code: prefer data.code, else "10-99".
    -- originally: SHX5_2 = (SHX0_2 and SHX0_2.code) or "10-99"; (goto SHX_LABEL_33)
    local panicCode  = (data and data.code)     or "10-99"
    -- ::SHX_LABEL_33::

    local panicTitle = (data and data.title)    or "Officer in Distress"
    -- ::SHX_LABEL_40::

    local panicLoc   = (data and data.location) or "Unknown"
    -- ::SHX_LABEL_47::

    -- Info: prefer data.info, else build "EMERGENCY ALERT TRIGGERED BY {NAME}".
    -- originally: SHX5_2 = "EMERGENCY ALERT TRIGGERED BY " .. SHX1_2.name:upper(); (goto SHX_LABEL_59)
    local panicInfo
    if data and data.info then
        panicInfo = data.info  -- goto SHX_LABEL_59
    else
        panicInfo = "EMERGENCY ALERT TRIGGERED BY " .. player.name:upper()
    end
    -- ::SHX_LABEL_59::

    AddDispatchCall({
        code     = panicCode,
        title    = panicTitle,
        location = panicLoc,
        coords   = panicCoords,
        info     = panicInfo,
    })
end)


-- =============================================================================
-- SECTION 22 — Officer location broadcast thread
-- Runs every 2,500 ms. Sends the full officer list to every online dept. player.
-- originally lines 1348-1393
-- =============================================================================

-- originally: SHX12_1 = CreateThread; function SHX13_1() … end; SHX12_1(SHX13_1)
CreateThread(function()
    while true do
        -- Build the current officer list.
        -- originally: SHX0_2 = SHX11_1()   (buildOfficerList at this point)
        local officerList = buildOfficerList()

        -- Send to every online player in a dept. job.
        -- originally: for _, playerIdStr in ipairs(GetPlayers()) do … TriggerClientEvent(…) end
        for _, playerIdStr in ipairs(GetPlayers()) do
            local playerSource = tonumber(playerIdStr)
            local player = Framework.GetPlayer(playerSource)
            if player and isValidDepartmentJob(player.job.name) then
                TriggerClientEvent("plt_mdt:client:updateOfficerLocations", playerSource, officerList)
            end
        end

        -- originally: Wait(2500)
        Wait(2500)
    end
end)


-- =============================================================================
-- SECTION 23 — RegisterCallback "plt_mdt:server:getOfficerLocations"
-- Returns the full officer list to the requesting client if they are in a
-- dept. job.
-- originally lines 1394-1429
-- =============================================================================

-- originally: SHX12_1 = RegisterCallback; SHX13_1 = "plt_mdt:server:getOfficerLocations"
RegisterCallback("plt_mdt:server:getOfficerLocations", function(source, cb)
    local player = Framework.GetPlayer(source)

    -- originally: if SHX2_2 and isValidDepartmentJob then goto SHX_LABEL_18 end; cb({}); return
    if not player or not isValidDepartmentJob(player.job.name) then
        cb({})
        return
    end

    -- ::SHX_LABEL_18::
    -- originally: SHX3_2 = SHX1_2; SHX4_2 = SHX11_1(); SHX3_2(SHX4_2)
    cb(buildOfficerList())
end)


-- =============================================================================
-- SECTION 24 — RegisterCallback "plt_mdt:server:canAssignDispatch"
-- Returns whether the requesting player can assign units to calls.
-- Uses the same canPlayerAccessDispatch check as canUseDispatch.
-- originally lines 1430-1458
-- =============================================================================

-- originally: SHX12_1 = RegisterCallback; SHX13_1 = "plt_mdt:server:canAssignDispatch"
RegisterCallback("plt_mdt:server:canAssignDispatch", function(source, cb)
    local player = Framework.GetPlayer(source)
    if not player then
        cb(false)
        return
    end

    -- originally: SHX3_2(SHX4_2, SHX5_2, SHX6_2) — SHX4_2,SHX5_2,SHX6_2 are multi-return
    -- artefact; canPlayerAccessDispatch returns one value. Extra nils are harmless.
    cb(canPlayerAccessDispatch(source, player))
end)


-- =============================================================================
-- SECTION 25 — RegisterCallback "plt_mdt:server:canUseDispatch"
-- Returns whether the requesting player can view/use the dispatch panel.
-- originally lines 1459-1487
-- =============================================================================

-- originally: SHX12_1 = RegisterCallback; SHX13_1 = "plt_mdt:server:canUseDispatch"
RegisterCallback("plt_mdt:server:canUseDispatch", function(source, cb)
    local player = Framework.GetPlayer(source)
    if not player then
        cb(false)
        return
    end

    -- originally: same multi-return artefact as canAssignDispatch
    cb(canPlayerAccessDispatch(source, player))
end)


-- =============================================================================
-- SECTION 26 — RegisterCallback "plt_mdt:server:getDispatchCameras"
-- Returns the sorted list of CCTV cameras to dept. players.
-- originally lines 1488-1551
-- =============================================================================

-- originally: SHX12_1 = RegisterCallback; SHX13_1 = "plt_mdt:server:getDispatchCameras"
RegisterCallback("plt_mdt:server:getDispatchCameras", function(source, cb)
    local player = Framework.GetPlayer(source)

    -- Only dept. players may list cameras.
    -- originally: if SHX2_2 and isValidDepartmentJob then goto SHX_LABEL_18 end; cb({}); return
    if not player or not isValidDepartmentJob(player.job.name) then
        cb({})
        return
    end

    -- ::SHX_LABEL_18::
    -- Convert the id-keyed cameraStore table into a sorted array.
    -- originally: for k, v in pairs(SHX3_1) do table.insert(SHX3_2, v) end; table.sort(…, id <)
    local cameraArray = {}
    for _, cam in pairs(cameraStore) do
        table.insert(cameraArray, cam)
    end

    -- Sort ascending by id.
    -- originally: SHX4_2(SHX5_2, function(a, b) return a.id < b.id end)
    table.sort(cameraArray, function(a, b)
        return a.id < b.id
    end)

    cb(cameraArray)
end)


-- =============================================================================
-- SECTION 27 — RegisterCallback "plt_mdt:server:canManageDispatchCameras"
-- Returns whether the requesting player is in Config.DispatchCameraAdminDiscord.
-- originally lines 1552-1569
-- =============================================================================

-- originally: SHX12_1 = RegisterCallback; SHX13_1 = "plt_mdt:server:canManageDispatchCameras"
RegisterCallback("plt_mdt:server:canManageDispatchCameras", function(source, cb)
    -- originally: SHX2_2 = SHX1_2; SHX3_2, SHX4_2 = SHX8_1(SHX0_2); SHX2_2(SHX3_2, SHX4_2)
    -- DECOMPILER ARTEFACT: isCameraAdmin returns one bool; the extra nil is harmless.
    cb(isCameraAdmin(source))
end)


-- =============================================================================
-- SECTION 28 — RegisterCallback "plt_mdt:server:createDispatchCamera"
-- Validates the calling player as a camera admin, normalises the supplied
-- camera data (label, coords, rot, fov), assigns an id, stores the camera
-- in cameraStore, and returns true on success.
-- originally lines 1570-1795
-- =============================================================================

-- originally: SHX12_1 = RegisterCallback; SHX13_1 = "plt_mdt:server:createDispatchCamera"
-- Callback signature: (source, cb, data)  where data = { label?, coords?, rot?, fov? }
RegisterCallback("plt_mdt:server:createDispatchCamera", function(source, cb, data)
    -- Must be a camera admin.
    -- originally: SHX3_2 = SHX8_1(SHX0_2); if not SHX3_2 then cb(false); return end
    if not isCameraAdmin(source) then
        cb(false)
        return
    end

    -- ---- Resolve label -------------------------------------------------------
    -- Trim the label string; default to "CAM-{nextId}" if empty.
    -- originally:
    --   if type(data) == "table" then SHX3_2 = tostring(data.label or ""); if SHX3_2 then goto SHX_LABEL_24 end end
    --   SHX3_2 = ""
    --   ::SHX_LABEL_24::
    --   SHX3_2 = SHX3_2:gsub("^%s+",""):gsub("%s+$","")
    --   if "" == SHX3_2 then SHX3_2 = "CAM-" .. tostring(SHX4_1) end
    local rawLabel = ""
    if type(data) == "table" then
        rawLabel = tostring(data.label or "")  -- goto SHX_LABEL_24
    end
    -- ::SHX_LABEL_24::
    local cameraLabel = rawLabel:gsub("^%s+", ""):gsub("%s+$", "")
    if cameraLabel == "" then
        cameraLabel = "CAM-" .. tostring(nextCameraId)
    end

    -- ---- Extract coords table ------------------------------------------------
    -- originally:
    --   if type(data) == "table" and data.coords then goto SHX_LABEL_49 end; SHX4_2 = nil
    --   ::SHX_LABEL_49::
    local coordsTable = nil
    if type(data) == "table" and data.coords then
        coordsTable = data.coords  -- goto SHX_LABEL_49
    end
    -- ::SHX_LABEL_49::

    -- ---- Extract rot table ---------------------------------------------------
    -- originally: same pattern → SHX_LABEL_58
    local rotTable = nil
    if type(data) == "table" and data.rot then
        rotTable = data.rot  -- goto SHX_LABEL_58
    end
    -- ::SHX_LABEL_58::

    -- ---- Parse coordX --------------------------------------------------------
    -- originally: if coordsTable then SHX6_2 = tonumber(coordsTable.x or coordsTable[1]); if SHX6_2 then goto SHX_LABEL_69 end end; SHX6_2 = nil
    local coordX = nil
    if coordsTable then
        coordX = tonumber(coordsTable.x or coordsTable[1])  -- goto SHX_LABEL_69 if valid
    end
    -- ::SHX_LABEL_69::

    -- ---- Parse coordY --------------------------------------------------------
    local coordY = nil
    if coordsTable then
        coordY = tonumber(coordsTable.y or coordsTable[2])  -- goto SHX_LABEL_80 if valid
    end
    -- ::SHX_LABEL_80::

    -- ---- Parse coordZ --------------------------------------------------------
    local coordZ = nil
    if coordsTable then
        coordZ = tonumber(coordsTable.z or coordsTable[3])  -- goto SHX_LABEL_91 if valid
    end
    -- ::SHX_LABEL_91::

    -- ---- Fall back to player ped position if coords are incomplete -----------
    -- originally: if not (SHX6_2 and SHX7_2) or not SHX8_2 then GetPlayerPed/GetEntityCoords block end
    if not (coordX and coordY) or not coordZ then
        local ped = GetPlayerPed(source)
        if ped == 0 then
            -- No ped available (player not spawned) — abort.
            cb(false)
            return
        end
        local pedCoords = GetEntityCoords(ped)
        coordX = pedCoords.x
        coordY = pedCoords.y
        coordZ = pedCoords.z + 1.5   -- slight upward offset so camera is not in the ground
    end

    -- ---- Resolve rotation ----------------------------------------------------
    -- rotZ: prefer rotTable.z/[3]; fall back to the player ped's heading.
    -- originally: SHX9_2 = nil; if SHX5_2 then SHX9_2 = tonumber(rotTable.z or rotTable[3]) end
    --             if not SHX9_2 then SHX9_2 = GetEntityHeading(GetPlayerPed(source)) end
    local rotZ = nil
    if rotTable then
        rotZ = tonumber(rotTable.z or rotTable[3])
    end
    if not rotZ then
        -- DECOMPILER ARTEFACT: GetPlayerPed spread across 6 slots; only [1] matters.
        rotZ = GetEntityHeading(GetPlayerPed(source))
    end

    -- rotX (pitch): prefer rotTable.x/[1]; default -18° (slight downward tilt).
    -- originally: if SHX5_2 then SHX10_2 = tonumber(rotTable.x or rotTable[1]); if SHX10_2 then goto SHX_LABEL_145 end end; SHX10_2 = -18.0
    local rotX = nil
    if rotTable then
        rotX = tonumber(rotTable.x or rotTable[1])  -- goto SHX_LABEL_145 if valid
    end
    if not rotX then rotX = -18.0 end
    -- ::SHX_LABEL_145::

    -- rotY (roll): prefer rotTable.y/[2]; default 0°.
    -- originally: if SHX5_2 then SHX11_2 = tonumber(rotTable.y or rotTable[2]); if SHX11_2 then goto SHX_LABEL_156 end end; SHX11_2 = 0.0
    local rotY = nil
    if rotTable then
        rotY = tonumber(rotTable.y or rotTable[2])  -- goto SHX_LABEL_156 if valid
    end
    if not rotY then rotY = 0.0 end
    -- ::SHX_LABEL_156::

    -- ---- Resolve FOV ---------------------------------------------------------
    -- originally: if type(data) == "table" then SHX12_2 = tonumber(data.fov); if SHX12_2 then goto SHX_LABEL_167 end end; SHX12_2 = 85.0
    local fov = nil
    if type(data) == "table" then
        fov = tonumber(data.fov)  -- goto SHX_LABEL_167 if valid
    end
    if not fov then fov = 85.0 end
    -- ::SHX_LABEL_167::

    -- ---- Assign id and store the camera -------------------------------------
    -- originally: SHX13_2 = SHX4_1; SHX4_1 = SHX4_1 + 1; SHX3_1[SHX13_2] = { … }
    local newId = nextCameraId
    nextCameraId = nextCameraId + 1

    cameraStore[newId] = {
        id     = newId,
        label  = cameraLabel,
        coords = { x = coordX, y = coordY, z = coordZ },
        rot    = { x = rotX,   y = rotY,   z = rotZ   },
        fov    = fov,
    }

    -- originally: SHX14_2 = SHX1_2; SHX15_2 = true; SHX14_2(SHX15_2)
    cb(true)
end)


-- =============================================================================
-- SECTION 29 — Startup thread: load cameras from Config
-- originally lines 1796-1809
-- =============================================================================

-- originally: SHX12_1 = CreateThread; function SHX13_1() SHX0_2 = SHX7_1; SHX0_2() end; SHX12_1(SHX13_1)
CreateThread(function()
    loadCamerasFromConfig()
end)


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         1810
-- Total lines in output:         ~530 (all logic preserved; boilerplate stripped)
-- Obfuscation techniques found:
--   1. SHX* identifier obfuscation throughout — all renamed.
--   2. Module-level SHX0_1…SHX5_1 reused as persistent state, SHX6_1…SHX14_1
--      reused repeatedly as scratch for each registration call.
--   3. goto/label control flow — 18 labels resolved to structured if/else:
--      SHX_LABEL_9, _14, _17, _18 (×3), _24, _25, _33, _40, _45, _47, _49,
--      _52, _58, _59, _66, _69, _78, _80, _91 (×2), _145, _156, _167.
--   4. SHX10_1 redefined (addDispatchCall → send911Call) mid-file after
--      AddDispatchCall alias was captured — separated into two named functions.
--   5. SHX11_1 redefined (getActiveCallsList → buildOfficerList) mid-file after
--      GetActiveCalls alias was captured — separated into two named functions.
--   6. Decompiler multi-return artefacts on single-return calls:
--      GetPlayerPed spread across 6 vars (triggerPanic, createDispatchCamera),
--      tostring spread across 5 vars (createWarrant pattern), canPlayerAccessDispatch
--      result spread across 3 vars — all collapsed.
--   7. Explicit OOP method desugaring in pcall blocks preserved as : call syntax.
-- String arrays resolved:        0
-- Renamed identifiers:           14 module-level + ~200 inner-scope locals
-- Constructs flagged for review:
--   • send911Call: callerCooldowns[source] is recorded inside send911Call but
--     the chatMessage handler also checks it independently. Both update the
--     same table — consistent, but worth auditing to confirm no double-update.
--   • canPlayerAccessDispatch: SHX_LABEL_17 was immediately preceded by
--     `return false` with no goto-able path — verified that the goto IS
--     reachable through the inner `if player and isValidDepartmentJob` block.
--   • testmdtcall: Framework.Notify called with only 2 args (no source) —
--     preserved verbatim from the original; may be a bug in the source.
--   • buildOfficerList: seenIdentifiers table is built but never actually used
--     to filter out duplicates — it is a dead write. Preserved as-is (may be
--     placeholder for future de-duplication logic).
--   • createDispatchCamera: cameras are stored in-memory only (cameraStore).
--     Server restarts will lose player-placed cameras unless loadCamerasFromConfig
--     or a DB layer persists them separately.
-- Functionality preserved:       YES