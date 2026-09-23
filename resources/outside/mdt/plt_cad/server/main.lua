-- ============================================================
-- PLT_CAD - FiveM Police CAD System (Server-Side)
-- Deobfuscated by Claude
-- ============================================================

-- ============================================================
-- SECTION 1: FRAMEWORK INITIALIZATION
-- QBCore / QBX-Core / ESX auto-detection and object loading
-- ============================================================

local QBCore = nil   -- QBCore/QBX framework object (L0_1)
local ESX = nil      -- ESX framework object (L1_1)

-- Auto-detect framework if Config.Framework == "AUTO"
local frameworkConfig = Config.Framework
if "AUTO" == frameworkConfig then
    -- Check if qb-core or qbx-core is started
    local qbState = GetResourceState("qb-core")
    if "started" ~= qbState then
        local qbxState = GetResourceState("qbx-core")
        if "started" ~= qbxState then
            goto check_esx
        end
    end
    Config.Framework = "QB"
    goto framework_detected

    ::check_esx::
    local esxState = GetResourceState("es_extended")
    if "started" == esxState then
        Config.Framework = "ESX"
    end
end

::framework_detected::

-- Load the framework core object based on detected framework
local detectedFramework = Config.Framework
if "QB" == detectedFramework then
    -- Try qb-core first, then qbx-core
    local qbState = GetResourceState("qb-core")
    if "started" == qbState then
        QBCore = exports["qb-core"]:GetCoreObject()
    else
        local qbxState = GetResourceState("qbx-core")
        if "started" == qbxState then
            QBCore = exports["qbx-core"]:GetCoreObject()
        end
    end
    -- Fallback: listen for QBCore object event
    if not QBCore then
        TriggerEvent("QBCore:GetObject", function(coreObject)
            QBCore = coreObject
        end)
    end
else
    -- ESX framework
    if "ESX" == Config.Framework then
        local esxState = GetResourceState("es_extended")
        if "started" == esxState then
            ESX = exports.es_extended:getSharedObject()
        end
    end
end


-- ============================================================
-- SECTION 2: HELPER FUNCTIONS
-- ============================================================

-- Checks if a job name is in Config.Jobs whitelist
-- @param jobName (string) - the job name to check
-- @return boolean - true if job is whitelisted, false otherwise
local function IsJobWhitelisted(jobName)   -- was L2_1
    if not jobName then
        return false
    end
    for _, whitelistedJob in ipairs(Config.Jobs) do
        if whitelistedJob == jobName then
            return true
        end
    end
    return false
end

-- Returns a table of all online players who have a whitelisted job
-- Handles both QB and ESX frameworks
-- @return table - map of source->playerObject for whitelisted players
local function GetOnlineOfficers()   -- was L3_1
    if "QB" == Config.Framework then
        if QBCore then
            local officerMap = {}
            -- Use built-in GetQBPlayers if available (newer QBX)
            if QBCore.Functions.GetQBPlayers then
                return QBCore.Functions.GetQBPlayers()
            else
                -- Manual fallback: iterate GetPlayers() and fetch each
                local allPlayers = GetPlayers()
                for _, playerId in ipairs(allPlayers) do
                    local player = QBCore.Functions.GetPlayer(tonumber(playerId))
                    if player then
                        officerMap[playerId] = player
                    end
                end
                return officerMap
            end
        end
    else
        if "ESX" == Config.Framework then
            if ESX then
                local officerMap = {}
                -- For each whitelisted job, get all players with that job
                for _, jobName in ipairs(Config.Jobs) do
                    local playersWithJob = ESX.GetExtendedPlayers("job", jobName)
                    for _, player in ipairs(playersWithJob) do
                        local sourceStr = tostring(player.source)
                        officerMap[sourceStr] = player
                    end
                end
                return officerMap
            end
        end
    end
    return {}
end

-- Returns a player's full name ("Firstname Lastname") from their framework object
-- @param playerObject - QB or ESX player object
-- @return string - full name or "Unknown"
local function GetPlayerFullName(playerObject)   -- was L9_1
    if "QB" == Config.Framework then
        if playerObject then
            if playerObject.PlayerData then
                if playerObject.PlayerData.charinfo then
                    local firstName = playerObject.PlayerData.charinfo.firstname
                    local lastName  = playerObject.PlayerData.charinfo.lastname
                    return firstName .. " " .. lastName
                end
            end
        end
    else
        if "ESX" == Config.Framework and playerObject then
            if playerObject.get then
                local firstName = playerObject.get("firstName")
                local lastName  = playerObject.get("lastName")
                if firstName and lastName then
                    return firstName .. " " .. lastName
                end
                -- Fallback to getName()
                local name = playerObject.getName()
                if not name then
                    name = "Unknown"
                end
                return name
            end
        end
    end
    return "Unknown"
end


-- ============================================================
-- SECTION 3: UNIT STATUS / OFFICER DATA TABLES
-- ============================================================

local unitStatuses    = {}   -- was L4_1 - maps source -> status string (e.g. "AVAILABLE", "BUSY")
local callAssignments = {}   -- was L5_1 - maps callId (string) -> table of assigned unit names
local resolvedCalls   = {}   -- was L6_1 - maps callId (string) -> true if resolved


-- ============================================================
-- SECTION 4: SESSION PERSISTENCE (MySQL)
-- Saves and loads callAssignments / resolvedCalls to/from DB
-- ============================================================

-- Saves current session data (assignments + resolved) to the database
local function SaveSessionData()   -- was L7_1
    local sessionData = {}
    sessionData.assignments = callAssignments
    sessionData.resolved    = resolvedCalls

    MySQL.Async.execute(
        "INSERT INTO plt_cad_data (id, data) VALUES (@id, @data) ON DUPLICATE KEY UPDATE data = @data",
        {
            ["@id"]   = "session_data",
            ["@data"] = json.encode(sessionData)
        }
    )
end

-- Loads session data from the database and populates callAssignments / resolvedCalls
local function LoadSessionData()   -- was L8_1
    MySQL.Async.fetchAll(
        "SELECT data FROM plt_cad_data WHERE id = @id",
        { ["@id"] = "session_data" },
        function(results)
            if results then
                if results[1] then
                    local decoded = json.decode(results[1].data)
                    if decoded then
                        -- Restore assignments
                        local assignments = decoded.assignments
                        if not assignments then assignments = {} end
                        callAssignments = assignments

                        -- Restore resolved calls
                        local resolved = decoded.resolved
                        if not resolved then resolved = {} end
                        resolvedCalls = resolved

                        print("[PLT_CAD] Session data loaded from database.")
                    end
                end
            end
        end
    )
end

-- ============================================================
-- SECTION 5: DATABASE INITIALIZATION
-- Creates tables if they don't exist, then loads session data
-- ============================================================

local mysqlReady = MySQL.ready   -- was L9_1 (used as function reference before redefinition)

local function InitializeDatabase()   -- was L10_1 (first definition)
    -- Create session data table
    MySQL.Async.execute(
        [[
        CREATE TABLE IF NOT EXISTS `plt_cad_data` (
            `id` VARCHAR(50) NOT NULL,
            `data` LONGTEXT NOT NULL,
            PRIMARY KEY (`id`)
        )
    ]],
        {},
        function(result)
            if result then
                LoadSessionData()
            end
        end
    )

    -- Create reports table
    MySQL.Async.execute(
        [[
        CREATE TABLE IF NOT EXISTS `plt_cad_reports` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `type` VARCHAR(50) NOT NULL,
            `officer` VARCHAR(100) NOT NULL,
            `subject` VARCHAR(100) DEFAULT NULL,
            `data` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        )
    ]],
        {},
        function(result)
            if result then
                print("[PLT_CAD] Reports table initialized.")
            end
        end
    )
end

-- Run DB init when MySQL is ready
mysqlReady(InitializeDatabase)


-- ============================================================
-- SECTION 6: BROADCAST UPDATED CAD DATA TO ALL CLIENTS
-- Collects officers and active dispatch calls, sends to clients
-- ============================================================

-- Builds officer list and call list, then broadcasts to all clients via "plt_cad:updateData"
local function BroadcastCadData()   -- was L10_1 (second/main definition)
    local officerList = {}   -- list of officer data tables

    -- Get all online officers from the framework
    local onlinePlayers = GetOnlineOfficers()

    for sourceStr, playerObject in pairs(onlinePlayers) do
        local sourceNum = tonumber(sourceStr)

        if "QB" == Config.Framework then
            -- QB: read job from PlayerData
            local jobData = playerObject.PlayerData.job
            if jobData then
                if IsJobWhitelisted(jobData.name) then
                    -- Get callsign from metadata; default to "N/A"
                    local callsign = playerObject.PlayerData.metadata.callsign
                    if not callsign then callsign = "N/A" end

                    -- Get status; default to "AVAILABLE"
                    local status = unitStatuses[sourceNum]
                    if not status then status = "AVAILABLE" end

                    -- Get agency label; default to "LSPD"
                    local agency = jobData.label
                    if not agency then agency = "LSPD" end

                    table.insert(officerList, {
                        name   = GetPlayerFullName(playerObject),
                        unit   = callsign,
                        status = status,
                        agency = agency,
                        source = sourceNum,
                    })
                end
            end
        else
            if "ESX" == Config.Framework then
                -- ESX: read job from player object
                local callsign = playerObject.get("callsign")
                if not callsign then
                    callsign = "UNIT-" .. sourceStr
                end

                local status = unitStatuses[sourceStr]
                if not status then status = "AVAILABLE" end

                local agencyLabel = playerObject.job.label
                if not agencyLabel then agencyLabel = "LSPD" end

                table.insert(officerList, {
                    name   = GetPlayerFullName(playerObject),
                    unit   = callsign,
                    status = status,
                    agency = agencyLabel,
                    source = sourceStr,
                })
            end
        end
    end

    -- Build active calls list from plt_mdt exports
    local callList = {}
    local success, activeCalls = pcall(function()
        return exports.plt_mdt:GetActiveDispatchCalls()
    end)

    if success and activeCalls then
        for _, callData in ipairs(activeCalls) do
            local callIdStr = tostring(callData.id)

            -- Get assignment string for this call
            local assignedUnits = callAssignments[callIdStr]
            if not assignedUnits then assignedUnits = {} end

            local assignedStr
            if #assignedUnits > 0 then
                assignedStr = table.concat(assignedUnits, ", ")
                if not assignedStr then
                    -- Fallback to call's own assigned field
                    assignedStr = callData.assigned
                    if not assignedStr then assignedStr = "NONE" end
                end
            else
                assignedStr = callData.assigned
                if not assignedStr then assignedStr = "NONE" end
            end

            -- Determine call status; mark as RESOLVED if in resolvedCalls
            local callStatus = callData.status
            if not callStatus then callStatus = "PENDING" end
            if resolvedCalls[callIdStr] then
                callStatus = "RESOLVED"
            end

            table.insert(callList, {
                id       = callData.id,
                code     = callData.code,
                title    = callData.title,
                location = callData.location,
                status   = callStatus,
                assigned = assignedStr,
            })
        end
    end

    -- Broadcast officer list and call list to ALL clients (-1 = everyone)
    TriggerClientEvent("plt_cad:updateData", -1, officerList, callList)
end


-- ============================================================
-- SECTION 7: NET EVENTS - STATUS, ASSIGNMENTS, CALLS
-- ============================================================

-- Event: officer updates their own status
RegisterNetEvent("plt_cad:updateStatus")
AddEventHandler("plt_cad:updateStatus", function(newStatus)
    local playerSource = source
    unitStatuses[playerSource] = newStatus
    BroadcastCadData()
end)

-- Event: client requests a full data refresh
RegisterNetEvent("plt_cad:requestUpdate")
AddEventHandler("plt_cad:requestUpdate", function()
    BroadcastCadData()
end)

-- ============================================================
-- SECTION 8: VEHICLE INFO LOOKUP
-- Looks up vehicle owner by plate; handles QB and ESX DB schemas
-- ============================================================

RegisterNetEvent("plt_cad:getVehicleInfo")
AddEventHandler("plt_cad:getVehicleInfo", function(plate, vehicleModel)
    local playerSource = source
    local ownerName = "UNREGISTERED"
    local boloInfo  = nil

    -- Try to get BOLO info from plt_mdt
    pcall(function()
        boloInfo = exports.plt_mdt:GetVehicleBolo(plate)
    end)

    if "QB" == Config.Framework then
        -- QB: look up citizenid in player_vehicles table
        MySQL.Async.fetchAll(
            "SELECT citizenid FROM player_vehicles WHERE plate = @plate",
            { ["@plate"] = plate },
            function(results)
                if results then
                    if results[1] then
                        local citizenId = results[1].citizenid

                        -- Try to find the player online first
                        local onlinePlayer = QBCore.Functions.GetPlayerByCitizenId(citizenId)
                        if onlinePlayer then
                            -- Player is online, read charinfo directly
                            local firstName = onlinePlayer.PlayerData.charinfo.firstname
                            local lastName  = onlinePlayer.PlayerData.charinfo.lastname
                            ownerName = firstName .. " " .. lastName

                            TriggerClientEvent("plt_cad:vehicleInfoResult",
                                playerSource, plate, ownerName, vehicleModel, boloInfo)
                        else
                            -- Player is offline, query players table
                            MySQL.Async.fetchAll(
                                "SELECT charinfo FROM players WHERE citizenid = @citizenid",
                                { ["@citizenid"] = citizenId },
                                function(offlineResults)
                                    if offlineResults then
                                        if offlineResults[1] then
                                            local charinfo = json.decode(offlineResults[1].charinfo)
                                            ownerName = charinfo.firstname .. " " .. charinfo.lastname
                                        end
                                    end
                                    TriggerClientEvent("plt_cad:vehicleInfoResult",
                                        playerSource, plate, ownerName, vehicleModel, boloInfo)
                                end
                            )
                        end
                    end
                else
                    -- No results - vehicle unregistered
                    TriggerClientEvent("plt_cad:vehicleInfoResult",
                        playerSource, plate, ownerName, vehicleModel, boloInfo)
                end
            end
        )
    else
        if "ESX" == Config.Framework then
            -- ESX: look up owner identifier in owned_vehicles table
            MySQL.Async.fetchAll(
                "SELECT owner FROM owned_vehicles WHERE plate = @plate",
                { ["@plate"] = plate },
                function(results)
                    if results then
                        if results[1] then
                            local ownerIdentifier = results[1].owner

                            -- Try to find the player online first
                            local onlinePlayer = ESX.GetPlayerFromIdentifier(ownerIdentifier)
                            if onlinePlayer then
                                local firstName = onlinePlayer.get("firstName")
                                local lastName  = onlinePlayer.get("lastName")
                                ownerName = firstName .. " " .. lastName

                                TriggerClientEvent("plt_cad:vehicleInfoResult",
                                    playerSource, plate, ownerName, vehicleModel, boloInfo)
                            else
                                -- Player is offline, query users table
                                MySQL.Async.fetchAll(
                                    "SELECT firstname, lastname FROM users WHERE identifier = @identifier",
                                    { ["@identifier"] = ownerIdentifier },
                                    function(offlineResults)
                                        if offlineResults then
                                            if offlineResults[1] then
                                                ownerName = offlineResults[1].firstname .. " " .. offlineResults[1].lastname
                                            end
                                        end
                                        TriggerClientEvent("plt_cad:vehicleInfoResult",
                                            playerSource, plate, ownerName, vehicleModel, boloInfo)
                                    end
                                )
                            end
                        end
                    else
                        -- No results - vehicle unregistered
                        TriggerClientEvent("plt_cad:vehicleInfoResult",
                            playerSource, plate, ownerName, vehicleModel, boloInfo)
                    end
                end
            )
        end
    end
end)


-- ============================================================
-- SECTION 9: CALL DETAIL RETRIEVAL
-- ============================================================

-- Event: client requests full details for a specific call ID
RegisterNetEvent("plt_cad:getCallDetails")
AddEventHandler("plt_cad:getCallDetails", function(callId)
    local playerSource = source

    local callDetails = exports.plt_mdt:GetDispatchCallDetails(callId)
    if callDetails then
        -- Mark as RESOLVED if it's in our resolved table
        local callIdStr = tostring(callId)
        if resolvedCalls[callIdStr] then
            callDetails.status = "RESOLVED"
        end
        TriggerClientEvent("plt_cad:callDetailsResult", playerSource, callDetails)
    end
end)


-- ============================================================
-- SECTION 10: CALL ASSIGNMENT
-- Assigns the requesting officer's unit to a given call
-- ============================================================

-- Event: officer requests to be assigned to a call
RegisterNetEvent("plt_cad:assignCall")
AddEventHandler("plt_cad:assignCall", function(callId)
    local playerSource = source
    local callIdStr    = tostring(callId)

    -- Default unit identifier based on source
    local unitLabel = "UNIT-" .. playerSource

    -- Try to get real callsign from the framework
    if "QB" == Config.Framework then
        if QBCore then
            local player = QBCore.Functions.GetPlayer(playerSource)
            if player then
                local callsign = player.PlayerData.metadata.callsign
                if callsign then
                    unitLabel = callsign
                end
            end
        end
    else
        if "ESX" == Config.Framework then
            if ESX then
                local player = ESX.GetPlayerFromId(playerSource)
                if player then
                    local callsign = player.get("callsign")
                    if callsign then
                        unitLabel = callsign
                    else
                        -- Fallback to full name as unit label
                        unitLabel = GetPlayerFullName(player)
                    end
                end
            end
        end
    end

    print("[PLT_CAD] Assigning " .. unitLabel .. " to call " .. callIdStr)

    -- Initialize assignment list for this call if needed
    if not callAssignments[callIdStr] then
        callAssignments[callIdStr] = {}
    end

    -- Only add if not already assigned
    local alreadyAssigned = false
    for _, assignedUnit in ipairs(callAssignments[callIdStr]) do
        if assignedUnit == unitLabel then
            alreadyAssigned = true
            break
        end
    end

    if not alreadyAssigned then
        table.insert(callAssignments[callIdStr], unitLabel)
        SaveSessionData()
    end

    -- Also notify plt_mdt (safe, wrapped in pcall)
    pcall(function()
        exports.plt_mdt:AssignUnitToCall(callId, unitLabel)
    end)

    BroadcastCadData()
end)


-- ============================================================
-- SECTION 11: RESOLVE CALL
-- ============================================================

-- Event: officer resolves / closes a call
RegisterNetEvent("plt_cad:resolveCall")
AddEventHandler("plt_cad:resolveCall", function(callId)
    local playerSource = source
    local callIdStr    = tostring(callId)

    print("[PLT_CAD] Resolving call " .. callIdStr .. " by source " .. playerSource)

    -- Mark call as resolved in our table and persist
    resolvedCalls[callIdStr] = true
    SaveSessionData()

    -- Also notify plt_mdt (safe, wrapped in pcall)
    pcall(function()
        exports.plt_mdt:ResolveCall(callId)
    end)

    BroadcastCadData()
end)


-- ============================================================
-- SECTION 12: DISCORD WEBHOOK - REPORT NOTIFICATION
-- Sends a Discord embed when a new report is filed
-- ============================================================

-- Sends a Discord webhook embed for a newly filed report
-- @param reportData table - contains type, officer, subject, data (key-value pairs)
local function SendDiscordWebhook(reportData)   -- was L11_1 (second definition)
    -- Skip if no webhook URL configured
    if "" == Config.Webhook then
        return
    end

    -- Build embed fields from report data key-value pairs
    local embedFields = {}
    for fieldKey, fieldValue in pairs(reportData.data) do
        local displayValue = fieldValue or fieldKey
        if "" == fieldValue or not fieldValue then
            displayValue = "N/A"
        end
        table.insert(embedFields, {
            name   = fieldKey:upper(),
            value  = displayValue,
            inline = false,
        })
    end

    -- Build the embed object
    local embed = {}
    embed.color = 3447003  -- Blue color

    -- Title: "NEW <TYPE> FILED" (uppercase)
    local reportTypeName = reportData.typeName
    embed.title = "NEW " .. reportTypeName:upper() .. " FILED"

    -- Description: officer name and subject
    local subject = reportData.subject
    if not subject then subject = "N/A" end
    embed.description = "**OFFICER:** " .. reportData.officer ..
        "\n\n**SUBJECT:** " .. subject

    embed.fields = embedFields

    -- Footer with timestamp
    local footer = {}
    footer.text     = "LSPD Record Management System - " .. os.date("%Y-%m-%d %H:%M:%S")
    footer.icon_url = Config.WebhookIcon
    embed.footer    = footer

    -- Send the webhook POST request
    PerformHttpRequest(
        Config.Webhook,
        function(statusCode, responseText, responseHeaders) end,   -- callback (unused)
        "POST",
        json.encode({
            username   = Config.WebhookName,
            embeds     = { embed },
            avatar_url = Config.WebhookIcon,
        }),
        { ["Content-Type"] = "application/json" }
    )
end


-- ============================================================
-- SECTION 13: REPORT SUBMISSION
-- Stores a new report in plt_cad_reports and fires webhook
-- ============================================================

-- Event: client submits a new report (arrest report, citation, etc.)
RegisterNetEvent("plt_cad:submitForm")
AddEventHandler("plt_cad:submitForm", function(reportData)
    local playerSource = source

    MySQL.Async.insert(
        "INSERT INTO plt_cad_reports (type, officer, subject, data) VALUES (@type, @officer, @subject, @data)",
        {
            ["@type"]    = reportData.type,
            ["@officer"] = reportData.officer,
            ["@subject"] = reportData.subject,
            ["@data"]    = json.encode(reportData.data),
        },
        function(insertId)
            if insertId then
                print("[PLT_CAD] New report filed by " .. reportData.officer ..
                    " (ID: " .. insertId .. ")")
                SendDiscordWebhook(reportData)
            end
        end
    )
end)


-- ============================================================
-- SECTION 14: RECORDS RETRIEVAL
-- ============================================================

-- Event: client requests the 50 most recent reports
RegisterNetEvent("plt_cad:getRecords")
AddEventHandler("plt_cad:getRecords", function()
    local playerSource = source

    MySQL.Async.fetchAll(
        "SELECT * FROM plt_cad_reports ORDER BY created_at DESC LIMIT 50",
        {},
        function(records)
            TriggerClientEvent("plt_cad:recordsResult", playerSource, records)
        end
    )
end)

-- Event: client requests full details for a specific report by ID
RegisterNetEvent("plt_cad:getRecordDetails")
AddEventHandler("plt_cad:getRecordDetails", function(reportId)
    local playerSource = source

    MySQL.Async.fetchAll(
        "SELECT * FROM plt_cad_reports WHERE id = @id",
        { ["@id"] = reportId },
        function(results)
            if results then
                if results[1] then
                    TriggerClientEvent("plt_cad:recordDetailsResult", playerSource, results[1])
                end
            end
        end
    )
end)


-- ============================================================
-- SECTION 15: FRAMEWORK PLAYER JOIN / JOB CHANGE EVENTS
-- Keeps unitStatuses table up to date
-- ============================================================

if "QB" == Config.Framework then
    -- When a QB player's job changes, remove them from unitStatuses if no longer whitelisted
    RegisterNetEvent("QBCore:Server:OnJobUpdate")
    AddEventHandler("QBCore:Server:OnJobUpdate", function(playerSource, newJob)
        local jobIsWhitelisted = IsJobWhitelisted(newJob.name)
        if not jobIsWhitelisted then
            unitStatuses[playerSource] = nil
        end
        BroadcastCadData()
    end)

    -- When a QB player loads in, set their initial status if job is whitelisted
    AddEventHandler("QBCore:Server:PlayerLoaded", function(player)
        local jobName = player.PlayerData.job.name
        if IsJobWhitelisted(jobName) then
            local playerSource = player.PlayerData.source
            unitStatuses[playerSource] = "AVAILABLE"
        end
        BroadcastCadData()
    end)
else
    if "ESX" == Config.Framework then
        -- When an ESX player's job changes, remove them if no longer whitelisted
        RegisterNetEvent("esx:setJob")
        AddEventHandler("esx:setJob", function(playerSource, newJob)
            local jobIsWhitelisted = IsJobWhitelisted(newJob.name)
            if not jobIsWhitelisted then
                unitStatuses[playerSource] = nil
            end
            BroadcastCadData()
        end)

        -- When an ESX player loads in, set their initial status if whitelisted
        AddEventHandler("esx:playerLoaded", function(playerSource, player)
            local jobName = player.job.name
            if IsJobWhitelisted(jobName) then
                unitStatuses[playerSource] = "AVAILABLE"
            end
            BroadcastCadData()
        end)
    end
end


-- ============================================================
-- SECTION 16: PLAYER DROP HANDLER
-- Cleans up unit status on disconnect
-- ============================================================

AddEventHandler("playerDropped", function()
    local playerSource = source
    unitStatuses[playerSource] = nil
    BroadcastCadData()
end)


-- ============================================================
-- SECTION 17: EXPORTS
-- ============================================================

-- Export: force a full CAD data refresh
exports("RefreshData", function()
    BroadcastCadData()
end)


-- ============================================================
-- SECTION 18: POLLING THREAD
-- Broadcasts updated CAD data every 1 second
-- ============================================================

CreateThread(function()
    while true do
        BroadcastCadData()
        Wait(1000)
    end
end)


-- ============================================================
-- SECTION 19: PLT_MDT CALL EVENT LISTENERS
-- Re-broadcasts CAD data whenever dispatch calls change
-- ============================================================

-- New call created in dispatch
AddEventHandler("plt_mdt:server:newCall", function()
    BroadcastCadData()
end)

-- Existing call updated in dispatch
AddEventHandler("plt_mdt:server:updateCall", function()
    BroadcastCadData()
end)

-- Call deleted from dispatch
AddEventHandler("plt_mdt:server:deleteCall", function()
    BroadcastCadData()
end)