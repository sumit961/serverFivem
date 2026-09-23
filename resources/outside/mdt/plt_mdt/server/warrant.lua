-- =============================================================================
-- warrant.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Server-side warrant management callbacks
-- =============================================================================
-- Four RegisterCallback handlers:
--   getAllWarrants   — fetch last 50 warrants with resolved citizen names
--   createWarrant   — insert a new warrant, notify plt_departments
--   deleteWarrant   — mark a warrant cancelled, notify plt_departments
--   completeWarrant — mark a warrant completed, notify plt_departments
--
-- Framework branching: ESX uses (firstname, lastname) columns directly;
-- all other frameworks (QBCore etc.) use a charinfo column that may be
-- stored as a JSON string or a Lua table.
-- =============================================================================


-- =============================================================================
-- SHARED HELPER — resolveCharinfoName(row)
-- Extracts "Firstname Lastname" from a DB player row, handling both the ESX
-- flat-column layout and the QBCore/other charinfo layout.
-- This logic appears identically in getAllWarrants and createWarrant; extracted
-- here to avoid duplication (the original had it inlined twice).
-- originally: repeated inline blocks in SHX2_1 bodies
-- =============================================================================

--- Resolve a display name from a raw DB player row.
--- @param playerRow table   Row from the players table (MySQL result)
--- @return string           "Firstname Lastname" or "Unknown" if unresolvable
local function resolvePlayerName(playerRow)
    if not playerRow then
        return "Unknown"
    end

    -- originally: SHX13_2 = Framework.GetFramework(); if "esx" == SHX13_2 then … else … end
    local framework = Framework.GetFramework()

    if framework == "esx" then
        -- ESX stores name in separate firstname / lastname columns.
        -- originally: SHX13_2 = SHX12_2.firstname .. " " .. SHX12_2.lastname; SHX10_2 = SHX13_2
        return playerRow.firstname .. " " .. playerRow.lastname

    else
        -- QBCore (and others) store name inside a charinfo field, which may be
        -- a raw Lua table (when fetched via oxmysql) or a JSON string.
        -- originally:
        --   SHX13_2 = type(SHX12_2.charinfo)
        --   if "string" == SHX13_2 then
        --     SHX13_2 = json.decode(SHX12_2.charinfo)
        --     if SHX13_2 then goto SHX_LABEL_74 end
        --   end
        --   SHX13_2 = SHX12_2.charinfo   ← already a table, use directly
        --   ::SHX_LABEL_74::
        --   SHX10_2 = SHX13_2.firstname .. " " .. SHX13_2.lastname
        local charinfo = playerRow.charinfo

        -- If stored as a JSON string, decode it first.
        -- Otherwise it is already a table — use it directly.
        -- originally: goto SHX_LABEL_74 jumps over the "charinfo = playerRow.charinfo"
        --   fallback assignment, meaning the decoded table is used; when it is already
        --   a table, the decode branch is skipped and charinfo stays as-is.
        if type(charinfo) == "string" then
            local decoded = json.decode(charinfo)
            if decoded then
                charinfo = decoded  -- originally: goto SHX_LABEL_74 (skip raw-table path)
            end
            -- NOTE: if json.decode returns nil (malformed JSON), charinfo remains
            -- the original string, and the .firstname/.lastname access below will
            -- return nil. Consider adding a guard here if data quality is a concern.
        end
        -- ::SHX_LABEL_74:: / ::SHX_LABEL_91:: — charinfo is now a table (or raw value)
        -- originally: SHX14_2 = SHX13_2.firstname .. " " .. SHX13_2.lastname
        return charinfo.firstname .. " " .. charinfo.lastname
    end
end


-- =============================================================================
-- SHARED HELPER — buildPlayerSelectSQL()
-- Constructs the SELECT query string used to look up a citizen's name and
-- profile image by their citizenid/identifier.
-- originally: inline SQL concatenation in both getAllWarrants and createWarrant
-- =============================================================================

--- Build the player-lookup SELECT statement for the current framework.
--- @return string   Full SQL query with one positional parameter (?)
local function buildPlayerSelectSQL()
    -- originally:
    --   SHX13_2 = "SELECT "
    --   if "esx" == Framework.GetFramework() then SHX14_2 = "firstname, lastname" goto SHX_LABEL_34
    --   else SHX14_2 = "charinfo" end
    --   ::SHX_LABEL_34::
    --   SHX13_2 = "SELECT " .. columns .. ", p_image FROM " .. table .. " WHERE " .. idCol .. " = ? LIMIT 1"
    local columns
    if Framework.GetFramework() == "esx" then
        columns = "firstname, lastname"   -- originally: goto SHX_LABEL_34 / SHX_LABEL_49
    else
        columns = "charinfo"
    end

    -- originally: SHX15_2/SHX9_2 = ", p_image FROM "; SHX16_2/SHX10_2 = Framework.DB.PlayersTable; …
    return "SELECT "
        .. columns
        .. ", p_image FROM "
        .. Framework.DB.PlayersTable
        .. " WHERE "
        .. Framework.DB.IdentifierColumn
        .. " = ? LIMIT 1"
end


-- =============================================================================
-- SECTION 1 — Server callback: getAllWarrants
-- Fetches the 50 most recent warrants and enriches each row with the
-- suspect's resolved display name and profile image.
-- originally lines 9-100:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:getAllWarrants"
--   function SHX2_1(SHX0_2, SHX1_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

-- originally: SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:getAllWarrants"
-- Callback signature: (source, cb) — no extra data argument
RegisterCallback("plt_mdt:server:getAllWarrants", function(source, cb)
    -- Fetch the 50 most recent warrant records (newest first).
    -- originally: SHX2_2 = MySQL.query.await; SHX3_2 = "SELECT * …"; SHX2_2 = SHX2_2(SHX3_2)
    local warrantRows = MySQL.query.await("SELECT * FROM mdt_warrants ORDER BY id DESC LIMIT 50")

    -- If the query returned nothing, respond with an empty list.
    -- originally: if not SHX2_2 then SHX3_2 = SHX1_2; SHX4_2 = {}; return SHX3_2(SHX4_2) end
    if not warrantRows then
        return cb({})
    end

    -- Build the enriched result list.
    -- originally: SHX3_2 = {}
    local results = {}

    -- originally: SHX4_2, SHX5_2, SHX6_2, SHX7_2 = ipairs(SHX2_2); for SHX8_2, SHX9_2 in … do
    for _, warrantRow in ipairs(warrantRows) do
        -- Default values for name and image in case the citizen lookup fails.
        -- originally: SHX10_2 = "Unknown Suspect"; SHX11_2 = "img/default_avatar.png"
        local citizenName  = "Unknown Suspect"
        local suspectImage = "img/default_avatar.png"

        -- Look up the citizen's display name and profile image from the players table.
        -- originally: SHX12_2 = MySQL.single.await; SHX13_2 = (built SQL); SHX14_2 = {warrantRow.citizenid}; SHX12_2 = SHX12_2(…)
        local sql    = buildPlayerSelectSQL()
        local params = { warrantRow.citizenid }
        local playerRow = MySQL.single.await(sql, params)

        if playerRow then
            -- Resolve "Firstname Lastname" from the player row.
            citizenName = resolvePlayerName(playerRow)

            -- Use the player's profile image if one is set (non-empty string).
            -- originally: SHX13_2 = SHX12_2.p_image; if SHX13_2 then if "" ~= SHX13_2 then SHX11_2 = SHX12_2.p_image end end
            if playerRow.p_image and playerRow.p_image ~= "" then
                suspectImage = playerRow.p_image
            end
        end

        -- Append the enriched warrant entry to the results list.
        -- originally: SHX13_2 = table.insert; SHX14_2 = SHX3_2; SHX15_2 = { … }; SHX13_2(SHX14_2, SHX15_2)
        table.insert(results, {
            id           = warrantRow.id,
            citizenid    = warrantRow.citizenid,
            citizenName  = citizenName,
            suspectImage = suspectImage,

            -- Title defaults to "Warrant" if the DB column is NULL.
            -- originally: SHX16_2 = SHX9_2.title; if not SHX16_2 then SHX16_2 = "Warrant" end
            title        = warrantRow.title       or "Warrant",

            -- Description defaults to "" if the DB column is NULL.
            -- originally: SHX16_2 = SHX9_2.description; if not SHX16_2 then SHX16_2 = "" end
            description  = warrantRow.description or "",

            image        = warrantRow.image,

            -- Officer defaults to "SYSTEM" if the DB column is NULL.
            -- originally: SHX16_2 = SHX9_2.officer; if not SHX16_2 then SHX16_2 = "SYSTEM" end
            officer      = warrantRow.officer     or "SYSTEM",

            status       = warrantRow.status,
            created_at   = warrantRow.created_at,
        })
    end

    -- Return the enriched list to the callback caller.
    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2; SHX4_2(SHX5_2)
    cb(results)
end)


-- =============================================================================
-- SECTION 2 — Server callback: createWarrant
-- Inserts a new warrant for a citizen, resolves their display name, and
-- notifies the plt_departments resource via export.
-- originally lines 101-190:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:createWarrant"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

-- originally: SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:createWarrant"
-- Callback signature: (source, cb, data) where data = { citizenid, title, description, image }
RegisterCallback("plt_mdt:server:createWarrant", function(source, cb, data)
    -- Validate that the calling player exists in the framework.
    -- originally: SHX3_2 = Framework.GetPlayer(SHX0_2); if not SHX3_2 then return SHX1_2(false) end
    local player = Framework.GetPlayer(source)
    if not player then
        return cb(false)
    end

    -- Insert the new warrant row. Status is always "active" on creation.
    -- originally: SHX4_2 = MySQL.insert.await; SHX5_2 = "INSERT …"; SHX6_2 = {…}; SHX4_2 = SHX4_2(SHX5_2, SHX6_2)
    local insertedId = MySQL.insert.await(
        "INSERT INTO mdt_warrants (citizenid, title, description, image, officer, status) VALUES (?, ?, ?, ?, ?, ?)",
        {
            tostring(data.citizenid),    -- originally: SHX7_2 = tostring(SHX2_2.citizenid)
            tostring(data.title),        -- originally: SHX8_2 = tostring(SHX2_2.title)
            tostring(data.description),  -- originally: SHX9_2 = tostring(SHX2_2.description)
            tostring(data.image),        -- originally: SHX10_2 = tostring(SHX2_2.image)
            player.name,                 -- originally: SHX11_2 = SHX3_2.name
            "active",                    -- originally: SHX12_2 = "active"
        }
    )
    -- NOTE: insertedId is the auto-increment id of the new row (MySQL.insert returns
    -- the last insert id, not rows-affected). The original checks `insertedId > 0`.

    if insertedId > 0 then
        -- Resolve the citizen's display name for the departments export call.
        -- originally: SHX5_2 = "Unknown" (default)
        local citizenName = "Unknown"

        -- originally: same buildPlayerSelectSQL / MySQL.single.await pattern as getAllWarrants
        -- DECOMPILER ARTEFACT: the original spreads tostring()'s single return value across
        -- five variables (SHX9_2…SHX13_2) and stuffs them all into the params array [1]-[5].
        -- Since tostring() only returns one value, params[2]-[5] are nil — MySQL only uses
        -- the first param anyway. Collapsed here to the correct single-element array.
        -- originally: SHX9_2, SHX10_2, SHX11_2, SHX12_2, SHX13_2 = tostring(SHX2_2.citizenid)
        --             SHX8_2 = {SHX9_2, SHX10_2, SHX11_2, SHX12_2, SHX13_2}
        local nameRow = MySQL.single.await(
            buildPlayerSelectSQL(),
            { tostring(data.citizenid) }   -- originally: only [1] is meaningful
        )

        if nameRow then
            -- originally: same ESX / charinfo branch logic as getAllWarrants
            citizenName = resolvePlayerName(nameRow)
        end

        -- Notify the plt_departments resource about the new warrant.
        -- Wrapped in pcall so a missing/broken export does not crash the callback.
        -- originally: SHX7_2 = pcall; function SHX8_2() … end; SHX7_2(SHX8_2)
        pcall(function()
            -- originally: SHX0_3 = exports.plt_departments; SHX0_3 = SHX0_3.AddWarrant; SHX0_3(SHX1_3, SHX2_3)
            -- NOTE: SHX1_3 = SHX0_3 (the export table itself) is passed as `self`
            -- because the decompiler preserved the explicit method-call desugaring
            -- (obj.Method(obj, args) instead of obj:Method(args)).
            exports.plt_departments:AddWarrant({
                id          = insertedId,            -- originally: SHX2_3.id = SHX4_2
                subject     = citizenName,           -- originally: SHX2_3.subject = SHX5_2
                charges     = tostring(data.title),  -- originally: SHX3_3 = tostring(SHX2_2.title)
                priority    = "Standard",            -- originally: SHX2_3.priority = "Standard"
                issuedBy    = player.name,           -- originally: SHX3_3 = SHX3_2.name
                description = tostring(data.description), -- originally: SHX3_3 = tostring(SHX2_2.description)
            })
        end)
    end

    -- Return true if the insert produced a valid id, false otherwise.
    -- originally: SHX5_2 = SHX1_2; SHX6_2 = SHX4_2 > 0; SHX5_2(SHX6_2)
    cb(insertedId > 0)
end)


-- =============================================================================
-- SECTION 3 — Server callback: deleteWarrant
-- Marks a warrant as "cancelled" in the database and notifies plt_departments.
-- originally lines 191-240:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:deleteWarrant"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

-- originally: SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:deleteWarrant"
-- Callback signature: (source, cb, warrantId)
RegisterCallback("plt_mdt:server:deleteWarrant", function(source, cb, warrantId)
    -- Set status = 'cancelled' rather than physically deleting the row.
    -- originally: SHX3_2 = MySQL.update.await; SHX4_2 = "UPDATE …"; SHX5_2 = {"cancelled", SHX2_2}; SHX3_2 = SHX3_2(…)
    local affectedRows = MySQL.update.await(
        "UPDATE mdt_warrants SET status = ? WHERE id = ?",
        { "cancelled", warrantId }
    )

    if affectedRows > 0 then
        -- Notify plt_departments that the warrant is gone.
        -- originally: SHX4_2 = pcall; function SHX5_2() … end; SHX4_2(SHX5_2)
        pcall(function()
            -- originally: SHX0_3 = exports.plt_departments.DeleteWarrant; SHX2_3 = SHX2_2; SHX0_3(SHX1_3, SHX2_3)
            exports.plt_departments:DeleteWarrant(warrantId)
        end)
    end

    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2 > 0; SHX4_2(SHX5_2)
    cb(affectedRows > 0)
end)


-- =============================================================================
-- SECTION 4 — Server callback: completeWarrant
-- Marks a warrant as "completed" in the database and notifies plt_departments.
-- NOTE: The departments export call is identical to deleteWarrant (DeleteWarrant),
-- meaning completing a warrant also removes it from the departments system.
-- This matches the original exactly — not a deobfuscation error.
-- originally lines 241-290:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:completeWarrant"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

-- originally: SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:completeWarrant"
-- Callback signature: (source, cb, warrantId)
RegisterCallback("plt_mdt:server:completeWarrant", function(source, cb, warrantId)
    -- Set status = 'completed'.
    -- originally: SHX3_2 = MySQL.update.await; SHX4_2 = "UPDATE …"; SHX5_2 = {"completed", SHX2_2}; SHX3_2 = SHX3_2(…)
    local affectedRows = MySQL.update.await(
        "UPDATE mdt_warrants SET status = ? WHERE id = ?",
        { "completed", warrantId }
    )

    if affectedRows > 0 then
        -- originally: SHX4_2 = pcall; function SHX5_2() SHX0_3 = exports.plt_departments.DeleteWarrant; SHX0_3(SHX1_3, SHX2_3) end
        -- NOTE: uses DeleteWarrant (not CompleteWarrant) — the departments resource
        -- treats both cancellation and completion as warrant removal. Preserved as-is.
        pcall(function()
            exports.plt_departments:DeleteWarrant(warrantId)
        end)
    end

    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2 > 0; SHX4_2(SHX5_2)
    cb(affectedRows > 0)
end)


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         290
-- Total lines in output:         ~270 (code + comments; all logic preserved)
-- Obfuscation techniques found:
--   1. SHX* identifier obfuscation — all renamed.
--   2. Module-level SHX0_1/SHX1_1/SHX2_1 reused as scratch on every
--      RegisterCallback call — separated into inline literals.
--   3. goto/label control flow (SHX_LABEL_34, SHX_LABEL_74 in getAllWarrants;
--      SHX_LABEL_49, SHX_LABEL_91 in createWarrant) — all replaced with
--      structured if/else; the inlined SQL and charinfo helpers extracted into
--      shared local functions.
--   4. Decompiler multi-return artefact in createWarrant:
--      `SHX9_2, SHX10_2, SHX11_2, SHX12_2, SHX13_2 = tostring(citizenid)` —
--      collapsed to the single meaningful return value; nil entries [2]-[5]
--      in the params array removed.
--   5. Explicit OOP method desugaring in pcall blocks:
--      `exports.plt_departments.AddWarrant(self, args)` → `exports…:AddWarrant(args)`
-- String arrays resolved:        0
-- Renamed identifiers:           3 module-level + ~60 inner-scope locals
-- Constructs flagged for review:
--   • createWarrant: MySQL.insert returns last-insert-id; the original checks
--     `id > 0` which is correct for a valid insert, but would be false if the
--     DB assigned id = 0 (unlikely but possible with non-AUTO_INCREMENT schemas).
--   • getAllWarrants has no source/player validation — any connected client can
--     request the full warrant list. This may be intentional (MDT access
--     controlled at the NUI/client level) but worth auditing.
--   • completeWarrant calls exports.plt_departments:DeleteWarrant (not a
--     hypothetical CompleteWarrant). This is preserved verbatim from the source —
--     completing a warrant removes it from the departments system just like
--     cancelling one does.
--   • resolvePlayerName: if charinfo is a malformed JSON string, json.decode
--     returns nil and charinfo remains a string, causing .firstname to return nil.
--     The concatenation will produce "nil nil". A guard could be added.
-- Functionality preserved:       YES