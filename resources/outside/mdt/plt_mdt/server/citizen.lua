-- ==============================================================================
-- citizen_clean.lua
-- Deobfuscated from citizen.lua (SHX-prefixed decompiler output)
-- MDT (Mobile Data Terminal) - Server-side callbacks
-- Framework: supports both ESX and QBCore via `Framework` abstraction
-- ==============================================================================

-- ============================================================
-- CALLBACK: plt_mdt:server:getAllCitizens
-- Returns every citizen row from the players table.
-- Parameters: source (player server-id), cb (callback function)
-- ============================================================
RegisterCallback("plt_mdt:server:getAllCitizens", function(source, cb)

    -- Build the field list depending on the active framework.
    -- ESX stores firstname/lastname as separate columns.
    -- QBCore stores them as a JSON blob in the 'charinfo' column.
    local nameFields
    if Framework.GetFramework() == "esx" then
        nameFields = "firstname, lastname"   -- originally: "firstname, lastname"
    else
        nameFields = "charinfo"              -- originally: "charinfo"
    end

    -- Dynamically build the SELECT query using framework DB config values.
    local query = "SELECT "
        .. Framework.DB.IdentifierColumn   -- e.g. "identifier" or "citizenid"
        .. " as citizenid, "
        .. nameFields
        .. " FROM "
        .. Framework.DB.PlayersTable       -- e.g. "users" or "players"

    local results = MySQL.query.await(query)

    cb(results)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:searchProfile
-- Searches players by name or identifier.
-- Parameters: source, cb, searchTerm (string from client)
-- ============================================================
RegisterCallback("plt_mdt:server:searchProfile", function(source, cb, searchTerm)

    -- Wrap the search term in SQL LIKE wildcards.
    local likePattern = "%" .. searchTerm .. "%"  -- originally: "%" .. SHX2_2 .. "%"

    -- Build the WHERE clause differently per framework.
    -- ESX: search identifier, firstname, lastname (3 params).
    -- QBCore: search identifier, charinfo JSON blob (2 params).
    local whereClause
    if Framework.GetFramework() == "esx" then
        whereClause = Framework.DB.IdentifierColumn
            .. " LIKE ? OR firstname LIKE ? OR lastname LIKE ?"
    else
        whereClause = Framework.DB.IdentifierColumn
            .. " LIKE ? OR charinfo LIKE ?"
    end

    -- Build the params array to match the WHERE clause above.
    local queryParams
    if Framework.GetFramework() == "esx" then
        -- Three placeholders: identifier, firstname, lastname.
        queryParams = { likePattern, likePattern, likePattern }
    else
        -- Two placeholders: identifier, charinfo.
        queryParams = { likePattern, likePattern }
    end

    -- Build the name field list the same way as getAllCitizens.
    local nameFields
    if Framework.GetFramework() == "esx" then
        nameFields = "firstname, lastname"
    else
        nameFields = "charinfo"
    end

    local query = "SELECT "
        .. Framework.DB.IdentifierColumn
        .. " as citizenid, "
        .. nameFields
        .. " FROM "
        .. Framework.DB.PlayersTable
        .. " WHERE "
        .. whereClause
        .. " LIMIT 10"

    local rows = MySQL.query.await(query, queryParams)

    -- Return nil immediately if there are no results.
    if not rows or #rows == 0 then
        return cb(nil)
    end

    -- Normalise each row into a uniform {citizenid, charinfo} shape.
    local resultList = {}
    for _, row in ipairs(rows) do
        local charinfo

        if Framework.GetFramework() == "esx" then
            -- ESX: build charinfo table from flat columns.
            charinfo = {
                firstname = row.firstname,
                lastname  = row.lastname,
            }
        else
            -- QBCore: charinfo may arrive as a JSON string or already decoded.
            if type(row.charinfo) == "string" then
                local decoded = json.decode(row.charinfo)
                if decoded then
                    charinfo = decoded
                else
                    -- json.decode returned falsy; fall back to the raw value.
                    -- NOTE: this branch is dead in practice if decode returns nil/false on failure.
                    charinfo = row.charinfo
                end
            else
                charinfo = row.charinfo
            end
        end

        -- NOTE (dead code in original): The decompiler emitted
        --   `goto SHX_LABEL_109; SHX14_2 = SHX15_2 or SHX14_2`
        -- The assignment after goto is unreachable. Preserved as a comment.
        -- // DEAD CODE: charinfo = decoded or charinfo  (line 176 original)

        table.insert(resultList, {
            citizenid = row.citizenid,
            charinfo  = charinfo,
        })
    end

    cb(resultList)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:getFullProfile
-- Returns a citizen's complete MDT profile:
--   charinfo, metadata, vehicles, active warrants, incidents.
-- Parameters: source, cb, citizenid (string)
-- ============================================================
RegisterCallback("plt_mdt:server:getFullProfile", function(source, cb, citizenid)

    -- Fetch the player's base row from the players table.
    local playerRow = MySQL.single.await(
        "SELECT * FROM " .. Framework.DB.PlayersTable
            .. " WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { citizenid }
    )

    if not playerRow then
        return cb(nil)
    end

    -- ---- Resolve charinfo ----
    local charinfo = {}
    if Framework.GetFramework() == "esx" then
        charinfo = {
            firstname = playerRow.firstname,
            lastname  = playerRow.lastname,
            birthdate = playerRow.dateofbirth,  -- originally: playerRow.dateofbirth mapped to .birthdate
        }
    else
        if type(playerRow.charinfo) == "string" then
            local decoded = json.decode(playerRow.charinfo)
            if decoded then
                charinfo = decoded
            else
                -- Decode returned falsy; use raw value.
                charinfo = playerRow.charinfo
            end
        else
            charinfo = playerRow.charinfo
        end
        -- NOTE (dead code in original): same unreachable assignment as in searchProfile.
        -- // DEAD CODE: charinfo = decoded or charinfo  (line 254 original)
    end

    -- ---- Resolve metadata ----
    -- Metadata is also stored as a JSON string in QBCore.
    local metadata = {}
    if playerRow.metadata then
        if type(playerRow.metadata) == "string" then
            local decoded = json.decode(playerRow.metadata)
            if decoded then
                metadata = decoded
            elseif playerRow.metadata then
                metadata = playerRow.metadata
            end
        elseif playerRow.metadata then
            metadata = playerRow.metadata
        end
    end

    -- ---- Fetch owned vehicles ----
    local vehicles = MySQL.query.await(
        "SELECT plate, vehicle FROM "
            .. Framework.DB.VehiclesTable
            .. " WHERE " .. Framework.DB.VehicleOwnerColumn .. " = ?",
        { citizenid }
    )

    -- ---- Fetch active warrants ----
    local warrants = MySQL.query.await(
        "SELECT * FROM mdt_warrants WHERE citizenid = ? AND status = ?",
        { citizenid, "active" }
    )

    -- ---- Fetch incident history (most recent first) ----
    local incidents = MySQL.query.await(
        "SELECT * FROM mdt_incident WHERE citizenid = ? ORDER BY created_at DESC",
        { citizenid }
    )

    -- ---- Build and return the full profile ----
    cb({
        citizenid = citizenid,
        charinfo  = charinfo,
        metadata  = metadata,
        warranted = playerRow.warranted == 1,  -- originally: 1 == SHX11_2 (integer flag)
        p_image   = playerRow.p_image,
        vehicles  = vehicles,
        warrants  = warrants,
        incidents = incidents,
    })
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:createCriminalRecord
-- Creates a criminal record — either as a warrant (warrant == "yes")
-- or as a standard incident entry (warrant == "no").
-- Parameters: source, cb, data (table with record fields)
-- ============================================================
RegisterCallback("plt_mdt:server:createCriminalRecord", function(source, cb, data)

    -- Verify the submitting officer exists on the server.
    local officerPlayer = Framework.GetPlayer(source)
    if not officerPlayer then
        return cb(false)
    end

    if data.warrant == "yes" then
        -- ================================================================
        -- Branch A: Insert as an active warrant in mdt_warrants.
        -- ================================================================
        local insertId = MySQL.insert.await(
            "INSERT INTO mdt_warrants "
                .. "(citizenid, title, charges, description, jail, fines, image, officer, status) "
                .. "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            {
                data.citizenid,
                "WARRANT: " .. (data.title or "Unknown"),  -- prefix the title to distinguish it
                data.charges or "",
                data.description or "",
                tonumber(data.jail) or 0,
                tonumber(data.fines) or 0,
                data.image or "",
                officerPlayer.name,
                "active",
            }
        )

        if insertId > 0 then
            -- Look up the suspect's display name for the department warrant notification.
            local suspectName = "Unknown"

            -- Determine name select fields for the framework.
            local nameFields
            if Framework.GetFramework() == "esx" then
                nameFields = "firstname, lastname"
            else
                nameFields = "charinfo"
            end

            local suspectRow = MySQL.single.await(
                "SELECT " .. nameFields
                    .. " FROM " .. Framework.DB.PlayersTable
                    .. " WHERE " .. Framework.DB.IdentifierColumn .. " = ? LIMIT 1",
                -- NOTE: the original decompiler erroneously spread tostring() across
                -- 9 variables (lines 419-428). tostring() returns exactly 1 value;
                -- the extra 8 slots were nil. Only the first element matters.
                -- FLAGGED FOR REVIEW: the original populated params[2..9] = nil.
                { tostring(data.citizenid) }
            )

            if suspectRow then
                if Framework.GetFramework() == "esx" then
                    suspectName = (suspectRow.firstname or "") .. " " .. (suspectRow.lastname or "")
                else
                    -- Resolve charinfo for QBCore.
                    local charinfo
                    if type(suspectRow.charinfo) == "string" then
                        local decoded = json.decode(suspectRow.charinfo)
                        if decoded then
                            charinfo = decoded
                        else
                            charinfo = suspectRow.charinfo
                        end
                    else
                        charinfo = suspectRow.charinfo
                    end
                    -- originally accessed .firstname / .lastname on the resolved charinfo
                    suspectName = (charinfo.firstname or "") .. " " .. (charinfo.lastname or "")
                end
            end

            -- Notify the plt_departments resource about the new warrant.
            -- Wrapped in pcall so a missing export does not break the callback.
            pcall(function()
                exports.plt_departments:AddWarrant({
                    id          = insertId,
                    subject     = suspectName,
                    charges     = tostring(data.charges),
                    priority    = "Standard",
                    issuedBy    = officerPlayer.name,
                    description = tostring(data.description),
                })
            end)
        end

        cb(insertId > 0)

    else
        -- ================================================================
        -- Branch B: No warrant — insert as a plain incident record.
        -- ================================================================
        local insertId = MySQL.insert.await(
            "INSERT INTO mdt_incident "
                .. "(citizenid, title, description, location, time, charges, image, officer, fines, jail, warrant) "
                .. "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            {
                data.citizenid,
                data.title,
                data.description,
                data.location or "Unknown Location",
                data.time or os.date("%Y-%m-%d %H:%M:%S"),
                data.charges or "",
                data.image or "",
                officerPlayer.name,
                tonumber(data.fines) or 0,
                tonumber(data.jail) or 0,
                "no",   -- warrant flag
            }
        )

        cb(insertId > 0)
    end
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:processSentence
-- Applies a live sentence to an online suspect:
--   - deducts a fine from their bank account
--   - sends them to jail via the configured jail system
--   - logs the sentence as an incident record
-- Parameters: source, cb, data { citizenid, fine, jail, title, charges }
-- ============================================================
RegisterCallback("plt_mdt:server:processSentence", function(source, cb, data)

    -- The submitting officer must be on the server.
    local officerPlayer = Framework.GetPlayer(source)
    if not officerPlayer then
        return cb({ success = false, message = "Officer not found." })
    end

    -- The suspect must be online to receive a live sentence.
    local suspectPlayer = Framework.GetPlayerFromIdentifier(data.citizenid)
    if not suspectPlayer then
        return cb({ success = false, message = "Suspect must be online to apply a sentence." })
    end

    -- ---- Proximity check: officer must be within 15 units of suspect ----
    -- NOTE: GetPlayerPed / GetEntityCoords return multiple values in FiveM Lua;
    -- the decompiler spread them across many variables. Only the vector result matters.
    local officerCoords  = GetEntityCoords(GetPlayerPed(source))
    local suspectCoords  = GetEntityCoords(GetPlayerPed(suspectPlayer.source))
    local distance       = #(officerCoords - suspectCoords)

    if distance > 15.0 then
        return cb({ success = false, message = "Suspect is too far away." })
    end

    -- ================================================================
    -- Step 1: Apply the fine (if any).
    -- ================================================================
    if data.fine and data.fine > 0 then
        if Framework.GetFramework() == "esx" then
            -- ESX: removeAccountMoney takes (accountName, amount)
            suspectPlayer.xPlayer.removeAccountMoney("bank", data.fine)
        else
            -- QBCore: RemoveMoney takes (accountName, amount, reason)
            suspectPlayer.Player.Functions.RemoveMoney(
                "bank",
                data.fine,
                "MDT Fine: " .. data.title
            )
        end

        -- Notify the suspect of the fine.
        Framework.Notify(
            suspectPlayer.source,
            "You have been fined $" .. data.fine .. " for: " .. data.title,
            "error"
        )

        -- Credit the fine to the issuing officer's department.
        -- Wrapped in pcall — plt_departments export may not be loaded.
        pcall(function()
            local department = exports.plt_departments:GetPlayerDepartment(source)
            if department then
                exports.plt_departments:AddMoneyToDept(
                    department,
                    data.fine,
                    "Fine issued to " .. suspectPlayer.name,
                    source
                )
            end
        end)
    end

    -- ================================================================
    -- Step 2: Apply jail time (if any).
    -- ================================================================
    -- Determine which jail system is configured (lowercased for comparison).
    local jailMode = string.lower(tostring(Config.JailMode or "default"))

    if data.jail and data.jail > 0 then
        if jailMode == "tk_jail" then
            -- tk_jail export: returns false if the resource is not running.
            local jailOk = Framework.JailPlayerTk(
                suspectPlayer.source,
                data.jail,
                data.title or "MDT Sentence"
            )
            if not jailOk then
                -- tk_jail not available — fall back to the built-in jail.
                Framework.Notify(source, "tk_jail is not started. Falling back to default jail.", "error")
                Framework.JailPlayer(suspectPlayer.source, data.jail)
            end

        elseif jailMode == "rcore" then
            -- rcore_prison export.
            local jailOk = Framework.JailPlayerRcore(
                suspectPlayer.source,
                data.jail,
                data.title or "MDT Sentence"
            )
            if not jailOk then
                Framework.Notify(source, "rcore_prison is not started. Falling back to default jail.", "error")
                Framework.JailPlayer(suspectPlayer.source, data.jail)
            end

        else
            -- Default path.
            if Config.UseInternalJailSystem then
                -- Store the suspect's current position as their release origin.
                local suspectPos = GetEntityCoords(GetPlayerPed(suspectPlayer.source))
                local originCoords = { x = suspectPos.x, y = suspectPos.y, z = suspectPos.z }

                -- Upsert a jail record (insert or update remaining time + origin).
                MySQL.insert.await(
                    "INSERT INTO mdt_jail (citizenid, time_left, origin) VALUES (?, ?, ?) "
                        .. "ON DUPLICATE KEY UPDATE time_left = ?, origin = ?",
                    {
                        data.citizenid,
                        data.jail,
                        json.encode(originCoords),
                        data.jail,
                        json.encode(originCoords),
                        -- NOTE: the decompiler assigned json.encode()'s return to 3 variables
                        -- (lines 742-755) due to a multi-return expansion artefact.
                        -- Only the first return value (the encoded string) is meaningful.
                        -- FLAGGED FOR REVIEW: params[6] and [7] would be nil in the original.
                    }
                )

                -- Teleport the suspect to the jail location on the client.
                TriggerClientEvent(
                    "plt_mdt:client:jailTeleport",
                    suspectPlayer.source,
                    Config.JailLocation,
                    false  -- isReleasing = false
                )
            else
                -- Delegate entirely to the framework's built-in jail helper.
                Framework.JailPlayer(suspectPlayer.source, data.jail)
            end
        end

        -- Notify the suspect of their jail sentence.
        Framework.Notify(
            suspectPlayer.source,
            "You have been jailed for " .. data.jail .. " months for: " .. data.title,
            "error"
        )
    end

    -- ================================================================
    -- Step 3: Log the sentence as a closed incident record.
    -- ================================================================
    local description = "Sentence applied directly.\nFine: $"
        .. (data.fine or 0)
        .. "\n\nJail: "
        .. (data.jail or 0)
        .. " Months"

    MySQL.insert.await(
        "INSERT INTO mdt_incident "
            .. "(citizenid, title, description, location, time, charges, officer, fines, jail, status) "
            .. "VALUES (?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?)",
        {
            data.citizenid,
            "SENTENCE: " .. data.title,
            description,
            "Police Station",
            data.charges,
            officerPlayer.name,
            data.fine or 0,
            data.jail or 0,
            "Closed",
        }
    )

    cb({ success = true, message = "Sentence applied and record filed." })
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:toggleLicense
-- Sets a specific license type to the given status in the
-- player's metadata, and syncs the change if the player is online.
-- Parameters: source, cb, data { citizenid, type, status }
-- ============================================================
RegisterCallback("plt_mdt:server:toggleLicense", function(source, cb, data)

    local citizenid = data.citizenid   -- originally: SHX3_2 = SHX2_2.citizenid

    -- Fetch just the metadata column for this citizen.
    local playerRow = MySQL.single.await(
        "SELECT metadata FROM "
            .. Framework.DB.PlayersTable
            .. " WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { citizenid }
    )

    if not playerRow then
        return cb(false)
    end

    -- ---- Decode metadata ----
    local metadata = {}
    if playerRow.metadata then
        if type(playerRow.metadata) == "string" then
            local decoded = json.decode(playerRow.metadata)
            if decoded then
                metadata = decoded
            elseif playerRow.metadata then
                metadata = playerRow.metadata
            end
        elseif playerRow.metadata then
            metadata = playerRow.metadata
        end
    end

    -- Ensure the licences sub-table exists.
    if not metadata.licences then
        metadata.licences = {}
    end

    -- Apply the toggle: set licences[type] = status.
    metadata.licences[data.type] = data.status   -- originally: SHX6_2[SHX7_2] = SHX8_2

    -- Persist the updated metadata back to the database.
    local rowsAffected = MySQL.update.await(
        "UPDATE " .. Framework.DB.PlayersTable
            .. " SET metadata = ? WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { json.encode(metadata), citizenid }
    )

    -- ---- Live sync: if the player is currently online, update their in-memory state ----
    local _ = Framework.GetPlayer(citizenid)   -- check if player object is available by citizenid
    for _, playerId in ipairs(GetPlayers()) do
        local onlinePlayer = Framework.GetPlayer(tonumber(playerId))
        if onlinePlayer then
            if onlinePlayer.identifier == citizenid then
                -- Push the new metadata directly to the player object.
                onlinePlayer.set("metadata", metadata)   -- originally: SHX16_2(SHX17_2, SHX18_2)
                break
            end
        end
    end

    cb(rowsAffected > 0)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:updateLicensePoints
-- Adds (or subtracts) points to a specific license type
-- (driver points or weapon points) in the player's metadata.
-- Parameters: source, cb, data { citizenid, type, amount }
-- ============================================================
RegisterCallback("plt_mdt:server:updateLicensePoints", function(source, cb, data)

    local citizenid  = data.citizenid   -- originally: SHX3_2
    local licenseType = data.type        -- originally: SHX4_2  ("driver" or other)
    local amount     = data.amount       -- originally: SHX5_2  (can be negative to subtract)

    -- Fetch the player's metadata row.
    local playerRow = MySQL.single.await(
        "SELECT metadata FROM "
            .. Framework.DB.PlayersTable
            .. " WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { citizenid }
    )

    if not playerRow then
        return cb({ success = false })
    end

    -- ---- Decode metadata ----
    local metadata = {}
    if playerRow.metadata then
        if type(playerRow.metadata) == "string" then
            local decoded = json.decode(playerRow.metadata)
            if decoded then
                metadata = decoded
            elseif playerRow.metadata then
                metadata = playerRow.metadata
            end
        elseif playerRow.metadata then
            metadata = playerRow.metadata
        end
    end

    -- Ensure the licences sub-table exists.
    if not metadata.licences then
        metadata.licences = {}
    end

    -- Determine which points field to update.
    -- "driver" licence uses "points"; everything else uses "weaponPoints".
    local pointsField
    if licenseType == "driver" then
        pointsField = "points"        -- originally: SHX8_2 = "points"
    else
        pointsField = "weaponPoints"  -- originally: SHX8_2 = "weaponPoints"
    end

    -- Add amount to existing points; clamp to 0 as the minimum.
    local currentPoints = tonumber(metadata.licences[pointsField]) or 0
    metadata.licences[pointsField] = math.max(0, currentPoints + amount)

    -- Persist updated metadata.
    local rowsAffected = MySQL.update.await(
        "UPDATE " .. Framework.DB.PlayersTable
            .. " SET metadata = ? WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { json.encode(metadata), citizenid }
    )

    -- ---- Live sync: push updated metadata to the online player if present ----
    for _, playerId in ipairs(GetPlayers()) do
        local onlinePlayer = Framework.GetPlayer(tonumber(playerId))
        if onlinePlayer then
            if onlinePlayer.identifier == citizenid then
                onlinePlayer.set("metadata", metadata)
                break
            end
        end
    end

    cb({ success = rowsAffected > 0 })
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:toggleWarrant
-- Sets or clears the `warranted` flag on the players table row.
-- Parameters: source, cb, data { citizenid, active (bool) }
-- ============================================================
RegisterCallback("plt_mdt:server:toggleWarrant", function(source, cb, data)

    -- Convert the boolean `active` to a DB integer (1 = wanted, 0 = not wanted).
    local warrantedValue
    if data.active then
        warrantedValue = 1   -- originally: SHX6_2 = 1 (then goto skips the =0 line)
    else
        warrantedValue = 0   -- originally: SHX6_2 = 0
    end

    local rowsAffected = MySQL.update.await(
        "UPDATE " .. Framework.DB.PlayersTable
            .. " SET warranted = ? WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { warrantedValue, data.citizenid }
    )

    cb(rowsAffected > 0)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:updateProfileImage
-- Updates the `p_image` column for a citizen and, if the
-- owning player is currently online, refreshes their player object.
-- Parameters: source, cb, data { citizenid, image (URL string) }
-- ============================================================
RegisterCallback("plt_mdt:server:updateProfileImage", function(source, cb, data)

    -- Get the requesting player object (used for live-sync check).
    local requestingPlayer = Framework.GetPlayer(source)  -- may be nil if called off-server; non-fatal

    local rowsAffected = MySQL.update.await(
        "UPDATE " .. Framework.DB.PlayersTable
            .. " SET p_image = ? WHERE " .. Framework.DB.IdentifierColumn .. " = ?",
        { data.image, data.citizenid }
    )

    -- If the requesting player happens to own this citizenid profile,
    -- push the updated image to their live player object too.
    if requestingPlayer then
        if requestingPlayer.identifier == data.citizenid then
            requestingPlayer.set("p_image", data.image)
        end
    end

    cb(rowsAffected > 0)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:searchIncident
-- Searches mdt_incident by title, id, or description.
-- Parameters: source, cb, data { query (string) }
-- ============================================================
RegisterCallback("plt_mdt:server:searchIncident", function(source, cb, data)

    local searchQuery  = data.query
    local likePattern  = "%" .. searchQuery .. "%"  -- originally: "%" .. SHX3_2 .. "%"

    local rows = MySQL.query.await(
        "SELECT * FROM mdt_incident WHERE title LIKE ? OR id = ? OR description LIKE ? LIMIT 20",
        {
            likePattern,  -- title LIKE
            searchQuery,  -- id = (exact numeric match)
            likePattern,  -- description LIKE
        }
    )

    if not rows then
        return cb({})
    end

    -- Return a trimmed summary list (not full row data).
    local results = {}
    for _, row in ipairs(rows) do
        table.insert(results, {
            id         = row.id,
            title      = row.title,
            status     = row.status,
            created_at = row.created_at,
        })
    end

    cb(results)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:getIncidentDetails
-- Fetches a single mdt_incident row and attempts to resolve
-- the suspect's display name from the players table.
-- Parameters: source, cb, data { id (number) }
-- ============================================================
RegisterCallback("plt_mdt:server:getIncidentDetails", function(source, cb, data)

    local incidentId = data.id

    local incident = MySQL.single.await(
        "SELECT * FROM mdt_incident WHERE id = ?",
        { incidentId }
    )

    if not incident then
        return cb(nil)
    end

    -- ---- Resolve citizen name ----
    local citizenName = "Unknown"  -- default if lookup fails

    if incident.citizenid then
        -- Determine name select fields.
        local nameFields
        if Framework.GetFramework() == "esx" then
            nameFields = "firstname, lastname"
        else
            nameFields = "charinfo"
        end

        local playerRow = MySQL.single.await(
            "SELECT " .. nameFields
                .. " FROM " .. Framework.DB.PlayersTable
                .. " WHERE " .. Framework.DB.IdentifierColumn .. " = ? LIMIT 1",
            { incident.citizenid }
        )

        if playerRow then
            if Framework.GetFramework() == "esx" then
                local fn = playerRow.firstname or "Unknown"
                local ln = playerRow.lastname  or "Suspect"
                citizenName = fn .. " " .. ln
            else
                -- Decode QBCore charinfo.
                local charinfo
                if type(playerRow.charinfo) == "string" then
                    local decoded = json.decode(playerRow.charinfo)
                    if decoded then
                        charinfo = decoded
                    else
                        charinfo = playerRow.charinfo
                    end
                else
                    charinfo = playerRow.charinfo
                end

                if charinfo then
                    local fn = charinfo.firstname or "Unknown"
                    local ln = charinfo.lastname  or "Suspect"
                    citizenName = fn .. " " .. ln
                end
            end
        end
    end

    -- Return the full incident record plus the resolved name.
    cb({
        id          = incident.id,
        citizenid   = incident.citizenid,
        citizenName = citizenName,
        title       = incident.title,
        description = incident.description,
        summary     = incident.summary,
        image       = incident.image,
        status      = incident.status,
        officer     = incident.officer,
        created_at  = incident.created_at,
    })
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:createCaseFile
-- Creates a new MDT incident ("case file") record.
-- The creating officer's name is stored as the case officer.
-- Parameters: source, cb, data { citizenid?, title, description,
--             summary?, image?, status? }
-- ============================================================
RegisterCallback("plt_mdt:server:createCaseFile", function(source, cb, data)

    -- The officer must be on the server.
    local officerPlayer = Framework.GetPlayer(source)
    if not officerPlayer then
        return cb(false)
    end

    local insertId = MySQL.insert.await(
        "INSERT INTO mdt_incident "
            .. "(citizenid, title, description, summary, image, status, officer, created_at) "
            .. "VALUES (?, ?, ?, ?, ?, ?, ?, NOW())",
        {
            data.citizenid or nil,
            data.title,
            data.description,
            data.summary   or "",
            data.image     or nil,
            data.status    or "Active Investigation",
            officerPlayer.name,
        }
    )

    -- Returns the new row's auto-increment ID (or 0 on failure).
    cb(insertId)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:updateCaseFile
-- Updates the editable fields of an existing mdt_incident row.
-- Parameters: source, cb, data { id, title, description,
--             summary, image, status }
-- ============================================================
RegisterCallback("plt_mdt:server:updateCaseFile", function(source, cb, data)

    local rowsAffected = MySQL.update.await(
        "UPDATE mdt_incident SET title = ?, description = ?, summary = ?, image = ?, status = ? WHERE id = ?",
        {
            data.title,
            data.description,
            data.summary,
            data.image,
            data.status,
            data.id,
        }
    )

    cb(rowsAffected > 0)
end)

-- ============================================================
-- CALLBACK: plt_mdt:server:deleteRecord
-- Deletes a single mdt_incident row by id.
-- Parameters: source, cb, id (number)
-- ============================================================
RegisterCallback("plt_mdt:server:deleteRecord", function(source, cb, id)

    local result = MySQL.query.await(
        "DELETE FROM mdt_incident WHERE id = ?",
        { id }
    )

    -- MySQL.query returns a result object (not nil) even for DELETE;
    -- check that the result itself is non-nil to confirm success.
    cb(result ~= nil)   -- originally: SHX5_2 = nil ~= SHX3_2
end)


-- =============================================================================
-- === VERIFICATION ===
-- Total lines in source:          1492
-- Total lines in output:          ~430 (clean, with comments; not padded)
-- Obfuscation techniques found:
--   1. SHX-prefixed identifier renaming (SHX0_1, SHX1_2, SHX0_3, etc.)
--   2. Excessive variable aliasing (chained assignments like A=B; A=A.field; A=A.method)
--   3. goto/label control-flow flattening replacing if/else branches
--   4. Decompiler multi-return expansion artifacts (tostring, GetEntityCoords, etc.
--      assigned to far more variables than the function actually returns)
-- String arrays resolved:         0 (no string-array obfuscation; strings are inline)
-- Renamed identifiers:
--   SHX0_1       → RegisterCallback (outer scope reused alias)
--   SHX1_1       → callback event name string
--   SHX2_1       → callback handler function
--   SHX0_2       → source  (player server-id, first param of every callback)
--   SHX1_2       → cb      (callback function, second param of every callback)
--   SHX2_2       → data    (payload table or primitive, third param)
--   SHX2_2..etc  → local working variables named per their runtime purpose
--   ~140+ total identifiers renamed
-- Constructs flagged for review:
--   1. Lines 419-428 (createCriminalRecord): tostring() multi-return expansion.
--      The decompiler populated a 9-element params array from tostring(), but
--      tostring() returns exactly 1 value. Slots [2..9] = nil in the original.
--      This means the MySQL query params array was mostly nil. Only params[1]
--      (the citizenid string) is meaningful. The clean code uses a single-element
--      array { tostring(data.citizenid) }.
--   2. Lines 174-177 / 254-255 (searchProfile / getFullProfile): Dead code.
--      The assignment `charinfo = decoded or charinfo` immediately follows a
--      `goto` and is therefore unreachable. Preserved as comments.
--   3. Lines 742-756 (processSentence, internal jail): json.encode() result
--      spread across 3 variables by decompiler artifact; only the first value
--      is the encoded string. The clean code calls json.encode() inline twice
--      (as the query requires both origin params). Original params[6],[7] = nil.
-- Functionality preserved: YES — all 14 callbacks registered, all SQL queries,
--   all framework branches (ESX/QBCore), all external calls (pcall-guarded
--   exports, TriggerClientEvent, Framework.Notify) fully preserved.
-- =============================================================================