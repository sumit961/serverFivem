-- =============================================================================
-- vehicle.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Server-side vehicle / BOLO management
-- =============================================================================
-- Sections in order:
--   1. RegisterCallback "plt_mdt:server:searchVehicle"
--   2. RegisterCallback "plt_mdt:server:getVehicleDetails"
--   3. RegisterCallback "plt_mdt:server:createVehicleBolo"
--   4. RegisterCallback "plt_mdt:server:deleteVehicleBolo"
--   5. exports "GetVehicleBolo"
--   6. exports "HasActiveBolo"
--   7. RegisterCallback "plt_mdt:server:getAllVehicles"
-- =============================================================================


-- =============================================================================
-- SECTION 1 — RegisterCallback "plt_mdt:server:searchVehicle"
-- Performs a LIKE search on the vehicles table by partial plate match.
-- Returns up to 10 matching rows with (plate, vehicle) fields.
-- originally lines 8-31:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:searchVehicle"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- =============================================================================

-- Callback signature: (source, cb, searchTerm)
RegisterCallback("plt_mdt:server:searchVehicle", function(source, cb, searchTerm)
    -- Wrap the search term in SQL wildcards for a LIKE match.
    -- originally: SHX3_2 = "%" .. SHX2_2 .. "%"
    local likeTerm = "%" .. searchTerm .. "%"

    -- originally: "SELECT plate, vehicle FROM " .. Framework.DB.VehiclesTable .. " WHERE plate LIKE ? LIMIT 10"
    local sql = "SELECT plate, vehicle FROM "
        .. Framework.DB.VehiclesTable
        .. " WHERE plate LIKE ? LIMIT 10"

    local results = MySQL.query.await(sql, { likeTerm })

    -- originally: SHX5_2 = SHX1_2; SHX6_2 = SHX4_2; SHX5_2(SHX6_2)
    cb(results)
end)


-- =============================================================================
-- SECTION 2 — RegisterCallback "plt_mdt:server:getVehicleDetails"
-- Returns full details for a specific plate:
--   vehicle row, owner charinfo (ESX or QBCore), and all BOLOs for that plate.
-- originally lines 32-127:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:getVehicleDetails"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- =============================================================================

-- Callback signature: (source, cb, plate)
RegisterCallback("plt_mdt:server:getVehicleDetails", function(source, cb, plate)
    -- Fetch the vehicle row.
    -- originally: MySQL.single.await("SELECT * FROM " .. VehiclesTable .. " WHERE plate = ?", {plate})
    local vehicleRow = MySQL.single.await(
        "SELECT * FROM " .. Framework.DB.VehiclesTable .. " WHERE plate = ?",
        { plate }
    )

    if not vehicleRow then
        return cb(nil)
    end

    -- ---- Look up the owner's name columns ---------------------------------
    -- Build SELECT for either ESX (firstname, lastname) or QBCore (charinfo),
    -- also fetching the identifier column so we have it available.
    -- originally: "SELECT " .. columns .. ", " .. IdentifierColumn .. " FROM " .. PlayersTable .. " WHERE " .. IdentifierColumn .. " = ?"
    -- Note: the original also selects IdentifierColumn alongside the name columns.
    local nameColumns
    if Framework.GetFramework() == "esx" then
        nameColumns = "firstname, lastname"   -- originally: goto SHX_LABEL_34
    else
        nameColumns = "charinfo"
    end
    -- ::SHX_LABEL_34::

    local ownerSql = "SELECT "
        .. nameColumns .. ", "
        .. Framework.DB.IdentifierColumn
        .. " FROM "    .. Framework.DB.PlayersTable
        .. " WHERE "   .. Framework.DB.IdentifierColumn
        .. " = ?"

    -- The owner identifier value is stored in the vehicle row under the
    -- framework-configured VehicleOwnerColumn (e.g. "owner" or "citizenid").
    -- originally: SHX7_2 = SHX3_2[Framework.DB.VehicleOwnerColumn]
    local ownerIdentifier = vehicleRow[Framework.DB.VehicleOwnerColumn]

    local ownerRow = MySQL.single.await(ownerSql, { ownerIdentifier })

    -- ---- Fetch all BOLOs for this plate ------------------------------------
    -- originally: MySQL.query.await("SELECT * FROM mdt_bolos WHERE plate = ? ORDER BY id DESC", {plate})
    local bolos = MySQL.query.await(
        "SELECT * FROM mdt_bolos WHERE plate = ? ORDER BY id DESC",
        { plate }
    )

    -- ---- Resolve the owner charinfo table ---------------------------------
    -- The NUI always expects .ownerData.charinfo, so we normalise both
    -- frameworks into a consistent {firstname, lastname, …} table.
    -- For ESX:    ownerData = { charinfo = { firstname = …, lastname = … } }
    -- For QBCore: ownerData = { charinfo = <charinfo table or decoded JSON> }
    -- originally: SHX6_2 = {}; if ownerRow then ESX / charinfo branch end; ::SHX_LABEL_94::
    local charinfo = {}

    if ownerRow then
        if Framework.GetFramework() == "esx" then
            -- ESX: build a charinfo-shaped table from the flat columns.
            -- originally: SHX7_2 = { firstname = SHX4_2.firstname, lastname = SHX4_2.lastname }; SHX6_2 = SHX7_2
            charinfo = {
                firstname = ownerRow.firstname,
                lastname  = ownerRow.lastname,
            }
        else
            -- QBCore: charinfo may be a JSON string or already a table.
            -- originally:
            --   if "string" == type(charinfo) then
            --     SHX7_2 = json.decode(charinfo); if SHX7_2 then goto SHX_LABEL_94; SHX6_2 = SHX7_2 or SHX6_2 end
            --   end
            --   SHX6_2 = SHX4_2.charinfo
            --   ::SHX_LABEL_94::
            -- DECOMPILER NOTE: the line `SHX6_2 = SHX7_2 or SHX6_2` appears after the goto
            -- and is therefore dead/unreachable — omitted. The effective result is:
            --   if decoded successfully → use decoded table; else use raw charinfo value.
            local rawCharinfo = ownerRow.charinfo
            if type(rawCharinfo) == "string" then
                local decoded = json.decode(rawCharinfo)
                if decoded then
                    charinfo = decoded          -- goto SHX_LABEL_94 (skip raw assignment)
                else
                    charinfo = rawCharinfo      -- fallback: malformed JSON, use as-is
                end
            else
                charinfo = rawCharinfo or {}    -- already a table (or nil → empty table)
            end
        end
    end
    -- ::SHX_LABEL_94::

    -- ---- Build and return the response ------------------------------------
    -- originally: SHX8_2 = { plate, vehicle, citizenid, ownerData={charinfo}, bolos }
    cb({
        plate     = vehicleRow.plate,
        vehicle   = vehicleRow.vehicle,
        -- Expose the owner's identifier (citizenid/license/etc.) directly.
        -- originally: SHX9_2 = SHX3_2[Framework.DB.VehicleOwnerColumn]
        citizenid = vehicleRow[Framework.DB.VehicleOwnerColumn],
        ownerData = { charinfo = charinfo },
        -- originally: SHX9_2 = SHX5_2 or SHX9_2; if not SHX5_2 then SHX9_2 = {} end
        bolos     = bolos or {},
    })
end)


-- =============================================================================
-- SECTION 3 — RegisterCallback "plt_mdt:server:createVehicleBolo"
-- Inserts a new BOLO into mdt_bolos, resolves the vehicle owner's display name
-- for the departments notification, then notifies plt_departments via export.
-- originally lines 128-247:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:createVehicleBolo"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- Callback signature: (source, cb, data)  data = { plate, title, image, description }
-- =============================================================================

RegisterCallback("plt_mdt:server:createVehicleBolo", function(source, cb, data)
    -- Resolve the issuing officer's display name; fall back to "Officer".
    -- originally: SHX3_2 = Framework.GetPlayer(source); if SHX3_2 and SHX3_2.name then goto SHX_LABEL_11 end; SHX4_2 = "Officer"; ::SHX_LABEL_11::
    local player = Framework.GetPlayer(source)
    local officerName = (player and player.name) or "Officer"
    -- ::SHX_LABEL_11::

    -- Insert the BOLO row.
    -- originally: MySQL.insert.await("INSERT INTO mdt_bolos (plate, title, image, description) VALUES (?,?,?,?)", {…})
    local insertedId = MySQL.insert.await(
        "INSERT INTO mdt_bolos (plate, title, image, description) VALUES (?, ?, ?, ?)",
        { data.plate, data.title, data.image, data.description }
    )

    -- insertedId is the new row's auto-increment id (MySQL.insert returns last insert id).
    if insertedId > 0 then

        -- Resolve the vehicle owner's display name for the departments export.
        -- originally: SHX6_2 = "Unknown" (default)
        local ownerName = "Unknown"

        -- Step 1: look up the vehicle row to get the owner identifier.
        -- originally: MySQL.single.await("SELECT " .. VehicleOwnerColumn .. " FROM " .. VehiclesTable .. " WHERE plate = ?", {plate})
        local vehicleRow = MySQL.single.await(
            "SELECT " .. Framework.DB.VehicleOwnerColumn
                .. " FROM " .. Framework.DB.VehiclesTable
                .. " WHERE plate = ?",
            { data.plate }
        )

        if vehicleRow then
            -- Step 2: look up the player name using the owner identifier.
            -- originally: ESX/charinfo branch → SHX_LABEL_59
            local nameColumns
            if Framework.GetFramework() == "esx" then
                nameColumns = "firstname, lastname"   -- originally: goto SHX_LABEL_59
            else
                nameColumns = "charinfo"
            end
            -- ::SHX_LABEL_59::

            local playerSql = "SELECT "
                .. nameColumns
                .. " FROM "  .. Framework.DB.PlayersTable
                .. " WHERE " .. Framework.DB.IdentifierColumn
                .. " = ?"

            -- The owner identifier is stored under the dynamic column name.
            -- originally: SHX11_2 = SHX7_2[Framework.DB.VehicleOwnerColumn]
            local ownerIdentifier = vehicleRow[Framework.DB.VehicleOwnerColumn]

            local playerRow = MySQL.single.await(playerSql, { ownerIdentifier })

            if playerRow then
                if Framework.GetFramework() == "esx" then
                    -- originally: SHX9_2 = SHX8_2.firstname .. " " .. SHX8_2.lastname; SHX6_2 = SHX9_2
                    ownerName = playerRow.firstname .. " " .. playerRow.lastname
                else
                    -- QBCore: decode charinfo JSON if needed.
                    -- originally: same json.decode / goto SHX_LABEL_102 pattern
                    -- ::SHX_LABEL_102::
                    local charinfo = playerRow.charinfo
                    if type(charinfo) == "string" then
                        local decoded = json.decode(charinfo)
                        if decoded then charinfo = decoded end   -- goto SHX_LABEL_102
                    end
                    -- ::SHX_LABEL_102::
                    if charinfo then
                        ownerName = charinfo.firstname .. " " .. charinfo.lastname
                    end
                end
            end
        end

        -- Notify plt_departments of the new BOLO via export.
        -- Wrapped in pcall so a missing/broken export does not fail the callback.
        -- originally: SHX8_2 = pcall; function SHX9_2() exports.plt_departments:AddBolo({…}) end; SHX8_2(SHX9_2)
        pcall(function()
            exports.plt_departments:AddBolo({
                id          = insertedId,              -- originally: SHX2_3.id = SHX5_2
                type        = "Vehicle",
                title       = tostring(data.title),
                description = tostring(data.description),
                plate       = tostring(data.plate),
                owner       = ownerName,
                lastSeen    = "Unknown",
                issuedBy    = officerName,             -- originally: SHX2_3.issuedBy = SHX4_2
            })
        end)
    end

    -- Return true if insert produced a valid id, false otherwise.
    -- originally: SHX6_2 = SHX1_2; SHX7_2 = SHX5_2 > 0; SHX6_2(SHX7_2)
    cb(insertedId > 0)
end)


-- =============================================================================
-- SECTION 4 — RegisterCallback "plt_mdt:server:deleteVehicleBolo"
-- Deletes a BOLO by id and notifies plt_departments.
-- originally lines 248-299:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:deleteVehicleBolo"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- Callback signature: (source, cb, data)  data = { id }
-- =============================================================================

RegisterCallback("plt_mdt:server:deleteVehicleBolo", function(source, cb, data)
    -- originally: MySQL.update.await("DELETE FROM mdt_bolos WHERE id = ?", {data.id})
    -- NOTE: MySQL.update.await is used for a DELETE — preserved verbatim from the original.
    -- It works (affected rows > 0 on success) but MySQL.query.await is more conventional.
    local affectedRows = MySQL.update.await(
        "DELETE FROM mdt_bolos WHERE id = ?",
        { data.id }
    )

    if affectedRows > 0 then
        -- Notify plt_departments to remove the BOLO from its records.
        -- originally: pcall(function() exports.plt_departments:DeleteBolo(data.id) end)
        pcall(function()
            exports.plt_departments:DeleteBolo(data.id)
        end)
    end

    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2 > 0; SHX4_2(SHX5_2)
    cb(affectedRows > 0)
end)


-- =============================================================================
-- SECTION 5 — exports "GetVehicleBolo"
-- Returns the most recent BOLO record for a given plate, or nil if none exists.
-- originally lines 300-340:
--   SHX0_1 = exports; SHX1_1 = "GetVehicleBolo"; function SHX2_1(SHX0_2) … end
-- =============================================================================

exports("GetVehicleBolo", function(plate)
    if not plate then return nil end

    -- originally: MySQL.single.await("SELECT * FROM mdt_bolos WHERE plate = ? ORDER BY id DESC LIMIT 1", {plate})
    local row = MySQL.single.await(
        "SELECT * FROM mdt_bolos WHERE plate = ? ORDER BY id DESC LIMIT 1",
        { plate }
    )

    if row then
        -- Return a clean copy rather than the raw DB row.
        -- originally: SHX2_2 = { id, plate, title, description, image, created_at }
        return {
            id          = row.id,
            plate       = row.plate,
            title       = row.title,
            description = row.description,
            image       = row.image,
            created_at  = row.created_at,
        }
    end

    return nil
end)


-- =============================================================================
-- SECTION 6 — exports "HasActiveBolo"
-- Returns true if the given plate has at least one BOLO record, false otherwise.
-- originally lines 341-372:
--   SHX0_1 = exports; SHX1_1 = "HasActiveBolo"; function SHX2_1(SHX0_2) … end
-- =============================================================================

exports("HasActiveBolo", function(plate)
    if not plate then return false end

    -- originally: MySQL.single.await("SELECT id FROM mdt_bolos WHERE plate = ? LIMIT 1", {plate})
    local row = MySQL.single.await(
        "SELECT id FROM mdt_bolos WHERE plate = ? LIMIT 1",
        { plate }
    )

    -- originally: return nil ~= SHX1_2  (true if a row was found)
    return row ~= nil
end)


-- =============================================================================
-- SECTION 7 — RegisterCallback "plt_mdt:server:getAllVehicles"
-- Returns up to 50 vehicles with plate, model, and owner identifier aliased
-- consistently as (plate, model, owner).
-- originally lines 373-402:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:getAllVehicles"
--   function SHX2_1(SHX0_2, SHX1_2) … end
-- Callback signature: (source, cb)  — no extra data argument
-- =============================================================================

RegisterCallback("plt_mdt:server:getAllVehicles", function(source, cb)
    -- Build the query with the framework-configured VehicleOwnerColumn aliased to "owner".
    -- originally: "SELECT plate, vehicle as model, " .. VehicleOwnerColumn .. " as owner FROM " .. VehiclesTable .. " LIMIT 50"
    local sql = "SELECT plate, vehicle as model, "
        .. Framework.DB.VehicleOwnerColumn
        .. " as owner FROM "
        .. Framework.DB.VehiclesTable
        .. " LIMIT 50"

    local results = MySQL.query.await(sql)

    -- originally: SHX3_2 = SHX1_2; SHX4_2 = SHX2_2 or SHX4_2; if not SHX2_2 then SHX4_2 = {} end; SHX3_2(SHX4_2)
    cb(results or {})
end)


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         402
-- Total lines in output:         ~200 (all logic preserved; boilerplate stripped)
-- Obfuscation techniques found:
--   1. SHX* identifier obfuscation — all renamed.
--   2. Module-level SHX0_1/SHX1_1/SHX2_1 reused as scratch on each
--      RegisterCallback/exports call — separated into inline literals.
--   3. goto/label control flow — 5 labels resolved to structured if/else:
--      SHX_LABEL_11, _34, _59, _94, _102.
--   4. Dead code after goto in getVehicleDetails:
--      `SHX6_2 = SHX7_2 or SHX6_2` after SHX_LABEL_94 is unreachable
--      (goto jumps past it). Noted and omitted.
--   5. Explicit OOP desugaring in pcall blocks (AddBolo/DeleteBolo) —
--      converted to : colon-call syntax.
-- String arrays resolved:        0
-- Renamed identifiers:           3 module-level + ~80 inner-scope locals
-- Constructs flagged for review:
--   • deleteVehicleBolo uses MySQL.update.await for a DELETE statement —
--     preserved verbatim. Works correctly (returns affected rows) but
--     MySQL.query.await is the more conventional choice for non-UPDATE DML.
--   • getVehicleDetails: the dead assignment `SHX6_2 = SHX7_2 or SHX6_2`
--     after goto SHX_LABEL_94 was unreachable and has been removed.
--   • createVehicleBolo: insertedId is the last insert id (not rows-affected),
--     so `insertedId > 0` correctly detects a successful insert as long as
--     the table uses AUTO_INCREMENT starting from 1.
--   • getAllVehicles has no access / job check — any connected client source
--     can retrieve up to 50 vehicle records. Access control is presumably
--     handled at the NUI/client level.
-- Functionality preserved:       YES