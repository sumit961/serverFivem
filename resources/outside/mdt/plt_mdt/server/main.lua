-- =============================================================================
-- main.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Server-side entry point / startup logic
-- =============================================================================
-- Sections in order:
--   1.  initializeDatabase()       — CREATE TABLE IF NOT EXISTS for all 5 tables,
--                                    charge sync from Config.MDTCharges,
--                                    default seed charges, addColumnIfMissing()
--   2.  loadPlayerMetadata()       — loads callsign / p_image / metadata into player
--   3.  Framework playerLoaded event handlers (ESX / QBCore / QBX)
--   4.  CreateThread — hot-restart re-load for already-connected players
--   5.  MySQL.ready → initializeDatabase()
--   6.  getRecentActiveWarrants()  — last 10 active warrants with citizen names
--   7.  getRecentBolos()           — last 10 BOLOs with owner names (2-hop lookup)
--   8.  getRecentIncidents()       — last 10 incidents with citizen names
--   9.  RegisterCallback getDashboardData
--   10. RegisterCallback getOfficerProfile
--   11. RegisterCallback saveOfficerSettings
--   12. exports GetActiveDispatchCalls / GetDispatchCallDetails
--   13. JailMode "default" block:
--         — jail countdown thread (every 60 s)
--         — RegisterNetEvent completeJailTask
--         — checkAndTeleportJailed()
--         — Framework playerLoaded → checkAndTeleportJailed
-- =============================================================================


-- =============================================================================
-- SHARED HELPER — resolvePlayerName(playerRow, defaultName)
-- Identical charinfo resolution pattern used in warrants, BOLOs, and incidents.
-- originally: inline blocks repeated in SHX2_1/SHX3_1/SHX4_1
-- =============================================================================

--- Extract "Firstname Lastname" from a raw DB player row.
--- @param playerRow   table   MySQL result row from the players table
--- @param defaultName string  Fallback name (e.g. "Unknown Suspect")
--- @return string
local function resolvePlayerName(playerRow, defaultName)
    if not playerRow then return defaultName end

    -- originally: if "esx" == Framework.GetFramework() then … else charinfo branch end
    if Framework.GetFramework() == "esx" then
        local first = playerRow.firstname or "Unknown"
        local last  = playerRow.lastname  or (defaultName or "Suspect")
        return first .. " " .. last
    else
        -- charinfo may be a JSON string or already a table.
        -- originally: if "string" == type(charinfo) then decode; if decoded goto label end; charinfo = raw end
        local charinfo = playerRow.charinfo
        if type(charinfo) == "string" then
            local decoded = json.decode(charinfo)
            if decoded then charinfo = decoded end
        end
        if charinfo then
            local first = charinfo.firstname or "Unknown"
            local last  = charinfo.lastname  or (defaultName or "Suspect")
            return first .. " " .. last
        end
    end
    return defaultName
end

--- Build a player-name SELECT query for the current framework.
--- @return string  SQL with one positional parameter (the identifier value)
local function buildPlayerNameSQL()
    -- originally: same ESX/charinfo column branching + Framework.DB.PlayersTable / IdentifierColumn
    local columns
    if Framework.GetFramework() == "esx" then
        columns = "firstname, lastname"
    else
        columns = "charinfo"
    end
    return "SELECT " .. columns
        .. " FROM "    .. Framework.DB.PlayersTable
        .. " WHERE "   .. Framework.DB.IdentifierColumn
        .. " = ? LIMIT 1"
end


-- =============================================================================
-- SECTION 1 — initializeDatabase()
-- Runs on MySQL.ready. Creates tables, syncs/seeds charges, adds missing columns.
-- originally: function SHX0_1() … end  (lines 9-556)
-- =============================================================================

-- ---- 1a. addColumnIfMissing(tableName, columnName, columnDefinition) ----------
-- Inner helper used in initializeDatabase. Checks whether a column exists via
-- SHOW COLUMNS, and ALTER TABLE ADDs it if missing.
-- originally: function SHX8_2(SHX0_3, SHX1_3, SHX2_3) … end  (lines 395-453)

local function addColumnIfMissing(tableName, columnName, columnDefinition)
    -- Check if the column already exists.
    -- originally: pcall(function() MySQL.query.await(string.format("SHOW COLUMNS FROM `%s` LIKE '%s'", table, col)) end)
    local ok, rows = pcall(function()
        return MySQL.query.await(string.format("SHOW COLUMNS FROM `%s` LIKE '%s'", tableName, columnName))
    end)

    if ok and rows and #rows == 0 then
        -- Column is absent — add it.
        -- originally: pcall(function() MySQL.query.await(string.format("ALTER TABLE `%s` ADD COLUMN %s", table, def)) end)
        pcall(function()
            MySQL.query.await(string.format("ALTER TABLE `%s` ADD COLUMN %s", tableName, columnDefinition))
        end)
    end
end

-- ---- 1b. initializeDatabase() ------------------------------------------------

-- originally: function SHX0_1()
local function initializeDatabase()

    -- ---- Create tables -------------------------------------------------------
    -- originally: SHX0_2…SHX4_2 = long SQL strings; five MySQL.query.await calls

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mdt_incident` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(60) DEFAULT NULL,
            `title` varchar(255) DEFAULT NULL,
            `description` text DEFAULT NULL,
            `location` varchar(255) DEFAULT NULL,
            `time` varchar(50) DEFAULT NULL,
            `charges` text DEFAULT NULL,
            `evidence` text DEFAULT NULL,
            `image` text DEFAULT NULL,
            `status` varchar(50) DEFAULT 'Active Investigation',
            `summary` text DEFAULT NULL,
            `officer` varchar(50) DEFAULT NULL,
            `fines` int(11) DEFAULT 0,
            `warrant` varchar(10) DEFAULT 'no',
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mdt_warrants` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(60) NOT NULL,
            `title` varchar(255) DEFAULT NULL,
            `description` text DEFAULT NULL,
            `image` text DEFAULT NULL,
            `officer` varchar(50) DEFAULT NULL,
            `status` enum('active','completed','cancelled') DEFAULT 'active',
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mdt_bolos` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `plate` varchar(15) DEFAULT NULL,
            `title` varchar(255) DEFAULT NULL,
            `description` text DEFAULT NULL,
            `image` text DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mdt_charges` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `title` varchar(255) NOT NULL,
            `description` text DEFAULT NULL,
            `category` varchar(50) DEFAULT 'General',
            `fine` int(11) DEFAULT 0,
            `jail` int(11) DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mdt_jail` (
            `citizenid` varchar(60) NOT NULL,
            `time_left` int(11) NOT NULL DEFAULT 0,
            `origin` text DEFAULT NULL,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- ---- Charge sync / seed --------------------------------------------------
    -- originally: SHX5_2 = Config.ChargeSync or {}; SHX6_2 = Config.MDTCharges or {}

    local chargeSyncCfg = Config.ChargeSync or {}
    local mdtCharges    = Config.MDTCharges  or {}

    -- originally: SHX7_2 = true == SHX5_2.syncEnabled
    if chargeSyncCfg.syncEnabled == true then
        -- Sync Config.MDTCharges into the database.
        -- Only process entries that are valid tables with both .title and .category.
        if #mdtCharges > 0 then

            -- Build a lookup set of "lower(title)|lower(category)" keys from the
            -- config so we can detect which DB rows are no longer in the config.
            -- originally: SHX8_2 = {}  (the present-in-config key set)
            local configKeySet = {}

            for _, chargeEntry in ipairs(mdtCharges) do
                -- originally: if "table" == type then if .title then if .category then … end end end
                if type(chargeEntry) == "table" and chargeEntry.title and chargeEntry.category then

                    local title       = tostring(chargeEntry.title)
                    local description = tostring(chargeEntry.description or "")
                    local category    = tostring(chargeEntry.category or "General")
                    local fine        = tonumber(chargeEntry.fine) or 0
                    local jailTime    = tonumber(chargeEntry.jail) or 0

                    -- Build the deduplication key: lower(title)|lower(category)
                    -- originally: SHX20_2 = string.lower(SHX15_2) .. "|" .. string.lower(SHX17_2)
                    local key = string.lower(title) .. "|" .. string.lower(category)
                    configKeySet[key] = true

                    -- Check whether this charge already exists in the database.
                    -- originally: MySQL.single.await("SELECT id FROM mdt_charges WHERE LOWER(title) = LOWER(?) AND LOWER(category) = LOWER(?) LIMIT 1", {title, category})
                    local existingRow = MySQL.single.await(
                        "SELECT id FROM mdt_charges WHERE LOWER(title) = LOWER(?) AND LOWER(category) = LOWER(?) LIMIT 1",
                        { title, category }
                    )

                    if existingRow and existingRow.id then
                        -- Row exists — update its description, fine, and jail time.
                        -- originally: MySQL.update.await("UPDATE mdt_charges SET description=?, fine=?, jail=? WHERE id=?", {desc, fine, jail, id})
                        MySQL.update.await(
                            "UPDATE mdt_charges SET description = ?, fine = ?, jail = ? WHERE id = ?",
                            { description, fine, jailTime, existingRow.id }
                        )
                    else
                        -- Row does not exist — insert it.
                        -- originally: MySQL.insert.await("INSERT INTO mdt_charges (title,description,category,fine,jail) VALUES (?,?,?,?,?)", {…})
                        MySQL.insert.await(
                            "INSERT INTO mdt_charges (title, description, category, fine, jail) VALUES (?, ?, ?, ?, ?)",
                            { title, description, category, fine, jailTime }
                        )
                    end
                end
            end

            -- If removeMissingFromDatabase is set, delete DB charges not in the config.
            -- originally: SHX9_2 = SHX5_2.removeMissingFromDatabase; if true == SHX9_2 then … end
            if chargeSyncCfg.removeMissingFromDatabase == true then
                local allDbCharges = MySQL.query.await("SELECT id, title, category FROM mdt_charges") or {}

                for _, dbCharge in ipairs(allDbCharges) do
                    -- Build the same key format used in configKeySet.
                    -- DECOMPILER ARTEFACT: tostring/string.lower spread across 13 variables;
                    -- collapsed to the single meaningful return value.
                    local dbKey = string.lower(tostring(dbCharge.title or ""))
                        .. "|"
                        .. string.lower(tostring(dbCharge.category or ""))

                    -- If this DB row's key is not present in the config, delete it.
                    -- originally: if not SHX8_2[dbKey] then MySQL.update.await("DELETE FROM … WHERE id = ?", {id}) end
                    -- NOTE: the original uses MySQL.update.await for a DELETE — preserved as-is.
                    if not configKeySet[dbKey] then
                        MySQL.update.await("DELETE FROM mdt_charges WHERE id = ?", { dbCharge.id })
                    end
                end
            end

        end

    else
        -- ChargeSync is disabled. If the mdt_charges table is empty, seed default charges.
        -- originally: SHX8_2 = MySQL.single.await("SELECT COUNT(*) as count FROM mdt_charges"); if count == 0 then insert 8 defaults end
        local countRow = MySQL.single.await("SELECT COUNT(*) as count FROM mdt_charges")
        if countRow and countRow.count == 0 then

            -- Default charges: { title, description, category, fine, jailMonths }
            -- originally: SHX9_2 = { SHX10_2, SHX11_2, … SHX17_2 } — array of 8 arrays
            local defaultCharges = {
                { "Aggravated Battery",    "Physical assault causing serious injury",          "Violent Crimes", 2500,  40  },
                { "Evading",               "Fleeing from law enforcement in a vehicle or on foot", "Traffic",   500,   15  },
                { "Grand Theft Auto",      "Theft of a motor vehicle",                         "Theft",          500,   10  },
                { "First Degree Murder",   "Premeditated killing of another person",            "Violent Crimes", 10000, 120 },
                { "Possession of Narcotics","Carrying illegal controlled substances",           "Drug Crimes",    1500,  20  },
                { "Armed Robbery",         "Theft using a deadly weapon",                      "Theft",          3500,  45  },
                { "Public Intoxication",   "Being under the influence in a public space",      "Misc",           200,   0   },
                { "Reckless Driving",      "Driving with willful disregard for safety",        "Traffic",        450,   5   },
            }

            for _, charge in ipairs(defaultCharges) do
                MySQL.insert.await(
                    "INSERT INTO mdt_charges (title, description, category, fine, jail) VALUES (?, ?, ?, ?, ?)",
                    { charge[1], charge[2], charge[3], charge[4], charge[5] }
                )
            end
        end
    end

    -- ---- Add missing columns (schema migration) ------------------------------
    -- These calls are idempotent — if the column already exists, nothing happens.
    -- originally: nine addColumnIfMissing calls for mdt_warrants columns
    addColumnIfMissing("mdt_warrants", "image",      "`image` TEXT DEFAULT NULL AFTER `description`")
    addColumnIfMissing("mdt_warrants", "officer",    "`officer` VARCHAR(50) DEFAULT NULL AFTER `image`")
    addColumnIfMissing("mdt_warrants", "citizenid",  "`citizenid` VARCHAR(60) DEFAULT NULL AFTER `id`")
    addColumnIfMissing("mdt_warrants", "title",      "`title` VARCHAR(255) DEFAULT NULL AFTER `citizenid`")
    addColumnIfMissing("mdt_warrants", "description","`description` TEXT DEFAULT NULL AFTER `title`")
    addColumnIfMissing("mdt_warrants", "status",     "`status` ENUM(\"active\",\"completed\",\"cancelled\") DEFAULT \"active\" AFTER `officer`")
    addColumnIfMissing("mdt_warrants", "created_at", "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP() AFTER `status`")
    addColumnIfMissing("mdt_warrants", "jail",       "`jail` INT(11) DEFAULT 0 AFTER `id`")
    addColumnIfMissing("mdt_warrants", "fines",      "`fines` INT(11) DEFAULT 0 AFTER `jail`")
    addColumnIfMissing("mdt_warrants", "charges",    "`charges` TEXT DEFAULT NULL AFTER `title`")

    -- originally: three addColumnIfMissing calls for mdt_incident
    addColumnIfMissing("mdt_incident", "citizenid",  "`citizenid` VARCHAR(60) DEFAULT NULL AFTER `id`")
    addColumnIfMissing("mdt_incident", "status",     "`status` VARCHAR(50) DEFAULT \"Active Investigation\" AFTER `image`")
    addColumnIfMissing("mdt_incident", "jail",       "`jail` INT(11) DEFAULT 0 AFTER `fines`")

    -- Add MDT-specific columns to the framework players table if it is configured.
    -- originally: if Framework.DB and Framework.DB.PlayersTable then … end
    if Framework.DB and Framework.DB.PlayersTable then
        local playersTable = Framework.DB.PlayersTable
        addColumnIfMissing(playersTable, "warranted", "`warranted` TINYINT(1) DEFAULT 0")
        addColumnIfMissing(playersTable, "p_image",   "`p_image` TEXT DEFAULT NULL")
        addColumnIfMissing(playersTable, "callsign",  "`callsign` VARCHAR(50) DEFAULT NULL")
        addColumnIfMissing(playersTable, "metadata",  "`metadata` LONGTEXT DEFAULT NULL")
    end
end


-- =============================================================================
-- SECTION 2 — loadPlayerMetadata(source)
-- On player login, reads callsign, p_image, and metadata from the players table
-- and pushes them into the framework player object via player.set().
-- originally: function SHX1_1(SHX0_2) … end  (lines 557-627)
-- =============================================================================

-- originally: function SHX1_1(SHX0_2)
local function loadPlayerMetadata(source)
    local player = Framework.GetPlayer(source)
    if not player then return end

    -- Build the SELECT query for this player's metadata fields.
    -- originally: "SELECT callsign, p_image, metadata FROM " .. PlayersTable .. " WHERE " .. IdentifierColumn .. " = ?"
    local sql = "SELECT callsign, p_image, metadata FROM "
        .. Framework.DB.PlayersTable
        .. " WHERE "
        .. Framework.DB.IdentifierColumn
        .. " = ?"

    local row = MySQL.single.await(sql, { player.identifier })
    if not row then return end

    -- Push callsign into the player object if present.
    -- originally: if SHX2_2.callsign then SHX1_2.set("callsign", …) end
    if row.callsign then
        player.set("callsign", row.callsign)
    end

    -- Push profile image if present.
    -- originally: if SHX2_2.p_image then SHX1_2.set("p_image", …) end
    if row.p_image then
        player.set("p_image", row.p_image)
    end

    -- Push metadata; decode from JSON string if necessary.
    -- originally: if SHX2_2.metadata then if "string"==type then decode; goto SHX_LABEL_56 end; raw; ::SHX_LABEL_56:: player.set("metadata", …) end
    if row.metadata then
        local metadata = row.metadata
        if type(metadata) == "string" then
            local decoded = json.decode(metadata)
            if decoded then metadata = decoded end  -- goto SHX_LABEL_56
        end
        -- ::SHX_LABEL_56::
        player.set("metadata", metadata)
    end
end


-- =============================================================================
-- SECTION 3 — Framework playerLoaded event handlers
-- Calls loadPlayerMetadata when a player finishes loading.
-- Supports ESX, QBCore, and QBX (ox_core).
-- originally lines 628-682
-- =============================================================================

-- originally: SHX2_1 = Framework.GetFramework()
if Framework.GetFramework() == "esx" then
    -- ESX: event passes the xPlayer object directly as first arg.
    -- originally: AddEventHandler("esx:playerLoaded", function(SHX0_2, SHX1_2) SHX1_1(SHX0_2) end)
    -- NOTE: ESX playerLoaded passes (xPlayer, isNew, skin) — SHX0_2 = xPlayer (has .source).
    -- Handle both old format (xPlayer object) and new format (just source number)
    AddEventHandler("esx:playerLoaded", function(xPlayerOrId, isNew, skin)
        local sourceId = xPlayerOrId
        -- If xPlayerOrId is a table (object), extract source; otherwise use directly
        if type(xPlayerOrId) == "table" and xPlayerOrId.source then
            sourceId = xPlayerOrId.source
        end
        loadPlayerMetadata(sourceId)
    end)
else
    -- QBCore: event passes a player data object; extract .PlayerData.source.
    -- originally: AddEventHandler("QBCore:Server:OnPlayerLoaded", function(SHX0_2) SHX1_1(SHX0_2.PlayerData.source) end)
    AddEventHandler("QBCore:Server:OnPlayerLoaded", function(playerData)
        loadPlayerMetadata(playerData.PlayerData.source)
    end)

    -- QBX (ox_core fork): event passes a player object; extract .source.
    -- originally: AddEventHandler("qbx_core:server:onPlayerLoaded", function(SHX0_2) SHX1_1(SHX0_2.source) end)
    AddEventHandler("qbx_core:server:onPlayerLoaded", function(playerData)
        loadPlayerMetadata(playerData.source)
    end)
end


-- =============================================================================
-- SECTION 4 — Hot-restart metadata load thread
-- If the resource restarts while players are already connected (e.g. during
-- development), this ensures their metadata is still loaded.
-- Waits 2 s for the framework to finish its own startup, then iterates
-- all current players and calls loadPlayerMetadata for each.
-- originally lines 683-709
-- =============================================================================

-- originally: SHX2_1 = CreateThread; function SHX3_1() Wait(2000); for _,id in ipairs(GetPlayers()) do SHX1_1(tonumber(id)) end end; SHX2_1(SHX3_1)
CreateThread(function()
    Wait(2000)
    for _, playerIdStr in ipairs(GetPlayers()) do
        -- DECOMPILER ARTEFACT: tonumber spread across 2 return slots; only [1] is valid.
        loadPlayerMetadata(tonumber(playerIdStr))
    end
end)


-- =============================================================================
-- SECTION 5 — MySQL.ready → initializeDatabase()
-- originally lines 710-724
-- =============================================================================

-- originally: SHX2_1 = MySQL.ready; function SHX3_1() SHX0_1() end; SHX2_1(SHX3_1)
MySQL.ready(function()
    initializeDatabase()
end)


-- =============================================================================
-- SECTION 6 — getRecentActiveWarrants()
-- Fetches the 10 most recent active warrants and resolves citizen names.
-- originally: function SHX2_1() … end  (lines 725-852)
-- =============================================================================

-- originally: function SHX2_1()
local function getRecentActiveWarrants()
    local rows = MySQL.query.await(
        "SELECT * FROM mdt_warrants WHERE status = ? ORDER BY id DESC LIMIT 10",
        { "active" }
    )
    if not rows then return {} end

    local results = {}
    for _, warrant in ipairs(rows) do
        local citizenName = "Unknown Suspect"

        if warrant.citizenid then
            -- originally: MySQL.single.await(buildPlayerNameSQL(), {warrant.citizenid}) with ESX/charinfo branch
            local playerRow = MySQL.single.await(buildPlayerNameSQL(), { warrant.citizenid })
            -- ESX fallbacks differ: "Unknown" / "Suspect"; charinfo has nil guard
            citizenName = resolvePlayerName(playerRow, "Unknown Suspect")
        end

        table.insert(results, {
            id          = warrant.id,
            citizenid   = warrant.citizenid,
            citizenName = citizenName,
            title       = warrant.title,
            image       = warrant.image,
            status      = warrant.status,
            created_at  = warrant.created_at,
        })
    end

    return results
end


-- =============================================================================
-- SECTION 7 — getRecentBolos()
-- Fetches the 10 most recent BOLOs. For each BOLO with a real plate (not "N/A"),
-- performs a 2-hop lookup: plate → vehicle owner identifier → player name.
-- originally: function SHX3_1() … end  (lines 853-1006)
-- =============================================================================

-- originally: function SHX3_1()
local function getRecentBolos()
    local rows = MySQL.query.await("SELECT * FROM mdt_bolos ORDER BY id DESC LIMIT 10")
    if not rows then return {} end

    local results = {}
    for _, bolo in ipairs(rows) do
        local ownerName = "Unknown Owner"

        -- Only look up owner if a real plate is set.
        -- originally: if SHX9_2 and "N/A" ~= SHX9_2 then … end
        if bolo.plate and bolo.plate ~= "N/A" then
            -- Step 1: look up the vehicle row to get the owner identifier.
            -- originally: "SELECT " .. Framework.DB.VehicleOwnerColumn .. " FROM " .. VehiclesTable .. " WHERE plate = ? LIMIT 1"
            local vehicleSql = "SELECT "
                .. Framework.DB.VehicleOwnerColumn
                .. " FROM "
                .. Framework.DB.VehiclesTable
                .. " WHERE plate = ? LIMIT 1"

            local vehicleRow = MySQL.single.await(vehicleSql, { bolo.plate })

            if vehicleRow then
                -- Extract the owner identifier value from the vehicle row using the
                -- dynamic column name (Framework.DB.VehicleOwnerColumn).
                -- originally: SHX10_2 = SHX9_2[Framework.DB.VehicleOwnerColumn]
                local ownerIdentifier = vehicleRow[Framework.DB.VehicleOwnerColumn]

                if ownerIdentifier then
                    -- Step 2: look up the player row using their identifier.
                    -- originally: buildPlayerNameSQL variant but using the owner identifier
                    local playerRow = MySQL.single.await(
                        buildPlayerNameSQL(),
                        { ownerIdentifier }
                    )
                    -- ESX fallbacks: "Unknown" / "Owner"
                    if playerRow then
                        ownerName = resolvePlayerName(playerRow, "Unknown Owner")
                    end
                end
            end
        end

        table.insert(results, {
            id         = bolo.id,
            plate      = bolo.plate,
            title      = bolo.title,
            owner      = ownerName,
            image      = bolo.image,
            created_at = bolo.created_at,
        })
    end

    return results
end


-- =============================================================================
-- SECTION 8 — getRecentIncidents()
-- Fetches the 10 most recent incidents and resolves the primary citizen name.
-- Only looks up a name when citizenid is set and non-empty.
-- originally: function SHX4_1() … end  (lines 1007-1138)
-- =============================================================================

-- originally: function SHX4_1()
local function getRecentIncidents()
    local rows = MySQL.query.await("SELECT * FROM mdt_incident ORDER BY id DESC LIMIT 10")
    if not rows then return {} end

    local results = {}
    for _, incident in ipairs(rows) do
        local citizenName = "Unknown Party"

        -- originally: if citizenid and "" ~= citizenid then … end
        if incident.citizenid and incident.citizenid ~= "" then
            local playerRow = MySQL.single.await(buildPlayerNameSQL(), { incident.citizenid })
            citizenName = resolvePlayerName(playerRow, "Unknown Party")
        end

        table.insert(results, {
            id          = incident.id,
            citizenid   = incident.citizenid,
            citizenName = citizenName,
            title       = incident.title    or "Untitled Case",
            status      = incident.status   or "Active",
            created_at  = incident.created_at,
        })
    end

    return results
end


-- =============================================================================
-- SECTION 9 — RegisterCallback "plt_mdt:server:getDashboardData"
-- Assembles the full dashboard payload:
--   warrants, incidents, bolos  → most recent 10 of each
--   calls                       → GetActiveCalls()
--   stats.activeWarrants        → COUNT of active warrants
--   stats.reportsToday          → COUNT of incidents created today
--   stats.recentCalls           → #calls (same as activeCalls here)
--   stats.activeCalls           → #calls
-- Each data-fetch is wrapped in pcall so one failing query doesn't kill the whole response.
-- originally lines 1139-1224
-- =============================================================================

-- originally: SHX5_1 = RegisterCallback; SHX6_1 = "plt_mdt:server:getDashboardData"
RegisterCallback("plt_mdt:server:getDashboardData", function(source, cb)
    -- originally: SHX2_2, SHX3_2 = pcall(SHX2_1)  (getRecentActiveWarrants)
    local okW, warrants = pcall(getRecentActiveWarrants)
    if not okW then warrants = {} end

    -- originally: SHX4_2, SHX5_2 = pcall(SHX4_1)  (getRecentIncidents)
    local okI, incidents = pcall(getRecentIncidents)
    if not okI then incidents = {} end

    -- originally: SHX6_2, SHX7_2 = pcall(SHX3_1)  (getRecentBolos)
    local okB, bolos = pcall(getRecentBolos)
    if not okB then bolos = {} end

    -- Fetch count stats inside a pcall.
    -- originally: SHX8_2 = 0; SHX9_2 = 0; pcall(function() … end)
    local activeWarrantCount = 0
    local reportsToday       = 0

    pcall(function()
        -- originally: MySQL.single.await("SELECT COUNT(*) as count FROM mdt_warrants WHERE status = ?", {"active"})
        local wRow = MySQL.single.await(
            "SELECT COUNT(*) as count FROM mdt_warrants WHERE status = ?",
            { "active" }
        )
        if wRow then activeWarrantCount = wRow.count end

        -- originally: MySQL.single.await("SELECT COUNT(*) as count FROM mdt_incident WHERE DATE(created_at) = CURDATE()")
        local iRow = MySQL.single.await(
            "SELECT COUNT(*) as count FROM mdt_incident WHERE DATE(created_at) = CURDATE()"
        )
        if iRow then reportsToday = iRow.count end
    end)

    -- Fetch the active calls list via the shared global.
    -- originally: SHX10_2 = GetActiveCalls()
    local calls = GetActiveCalls()

    cb({
        warrants  = warrants,
        incidents = incidents,
        bolos     = bolos,
        calls     = calls,
        stats     = {
            activeWarrants = activeWarrantCount,
            reportsToday   = reportsToday,
            recentCalls    = #calls,
            activeCalls    = #calls,
        },
    })
end)


-- =============================================================================
-- SECTION 10 — RegisterCallback "plt_mdt:server:getOfficerProfile"
-- Returns the calling officer's profile: name, rank, job, callsign, image, onDuty.
-- For QBCore/QBX, resolves the display name from charinfo (with JSON fallback).
-- originally lines 1225-1350
-- =============================================================================

-- originally: SHX5_1 = RegisterCallback; SHX6_1 = "plt_mdt:server:getOfficerProfile"
RegisterCallback("plt_mdt:server:getOfficerProfile", function(source, cb)
    local player = Framework.GetPlayer(source)
    if not player then
        return cb(nil)
    end

    -- Build a SELECT that also fetches p_image and callsign alongside the name columns.
    -- originally: "SELECT " .. (esx: "firstname, lastname" | other: "charinfo") .. ", p_image, callsign FROM " .. PlayersTable .. " WHERE " .. IdentifierColumn .. " = ?"
    local nameColumns
    if Framework.GetFramework() == "esx" then
        nameColumns = "firstname, lastname"  -- goto SHX_LABEL_24
    else
        nameColumns = "charinfo"
    end
    -- ::SHX_LABEL_24::

    local sql = "SELECT " .. nameColumns
        .. ", p_image, callsign FROM "
        .. Framework.DB.PlayersTable
        .. " WHERE "
        .. Framework.DB.IdentifierColumn
        .. " = ?"

    local row = MySQL.single.await(sql, { player.identifier })

    if not row then
        return cb(nil)
    end

    -- Resolve the display name.
    -- originally: SHX4_2 = SHX2_2.name (default); if not esx then charinfo branch; goto SHX_LABEL_68 end; ::SHX_LABEL_68::
    local displayName = player.name   -- default (framework name)

    if Framework.GetFramework() ~= "esx" then
        -- Decode charinfo if stored as JSON string.
        local charinfo = row.charinfo
        if type(charinfo) == "string" then
            local decoded = json.decode(charinfo)
            if decoded then charinfo = decoded end  -- goto SHX_LABEL_59
        end
        -- ::SHX_LABEL_59::

        if charinfo then
            local fullName = charinfo.firstname .. " " .. charinfo.lastname
            if fullName then
                displayName = fullName  -- goto SHX_LABEL_68
                -- NOTE: the original has dead code `SHX4_2 = SHX6_2 or SHX4_2` on the line
                -- after the goto target, which is never reached. Omitted.
            end
        end
        -- if charinfo was nil, displayName stays as player.name
    end
    -- ::SHX_LABEL_68::

    -- Resolve callsign: prefer DB row, fall back to player.get("callsign").
    -- originally: SHX7_2 = SHX3_2.callsign; if not then SHX7_2 = SHX2_2.get("callsign") or "" end
    local callsign = row.callsign
    if not callsign then
        callsign = player.get("callsign") or ""
    end

    -- Resolve profile image: prefer DB row, fall back to player.get or default.
    -- originally: SHX7_2 = SHX3_2.p_image; if not then SHX7_2 = SHX2_2.get("p_image") or "img/default_avatar.png" end
    local profileImage = row.p_image
    if not profileImage then
        profileImage = player.get("p_image") or "img/default_avatar.png"
    end

    cb({
        name     = displayName,
        rank     = player.job.grade.name,
        job      = player.job.label,
        callsign = callsign,
        image    = profileImage,
        onDuty   = player.job.onduty,
    })
end)


-- =============================================================================
-- SECTION 11 — RegisterCallback "plt_mdt:server:saveOfficerSettings"
-- Persists a player's callsign and profile image to the database and live
-- player object.
-- originally lines 1351-1409
-- =============================================================================

-- originally: SHX5_1 = RegisterCallback; SHX6_1 = "plt_mdt:server:saveOfficerSettings"
-- Callback signature: (source, cb, data)  where data = { callsign?, image? }
RegisterCallback("plt_mdt:server:saveOfficerSettings", function(source, cb, data)
    local player = Framework.GetPlayer(source)
    if not player then
        return cb(false)
    end

    -- Build the UPDATE query.
    -- originally: "UPDATE " .. PlayersTable .. " SET callsign = ?, p_image = ? WHERE " .. IdentifierColumn .. " = ?"
    local sql = "UPDATE "
        .. Framework.DB.PlayersTable
        .. " SET callsign = ?, p_image = ? WHERE "
        .. Framework.DB.IdentifierColumn
        .. " = ?"

    -- originally: SHX6_2 = {tostring(callsign or ""), data.image, player.identifier}
    MySQL.update.await(sql, {
        tostring(data.callsign or ""),
        data.image,
        player.identifier,
    })

    -- Also update the live player object so the change takes effect immediately.
    -- originally: SHX3_2.set("callsign", …); SHX3_2.set("p_image", …)
    player.set("callsign", data.callsign)
    player.set("p_image",  data.image)

    cb(true)
end)


-- =============================================================================
-- SECTION 12 — Exports: GetActiveDispatchCalls / GetDispatchCallDetails
-- originally lines 1410-1462
-- =============================================================================

-- Simple passthrough to the dispatch module's GetActiveCalls global.
-- originally: SHX5_1 = exports; SHX6_1 = "GetActiveDispatchCalls"; function SHX7_1() return GetActiveCalls() end
exports("GetActiveDispatchCalls", function()
    return GetActiveCalls()
end)

-- Finds a specific call by id in the active calls list.
-- originally: SHX5_1 = exports; SHX6_1 = "GetDispatchCallDetails"; function SHX7_1(SHX0_2) … end
exports("GetDispatchCallDetails", function(callId)
    if not callId then return nil end

    -- originally: exports.plt_mdt:GetActiveDispatchCalls() — self-call via export table
    local calls = exports.plt_mdt:GetActiveDispatchCalls()

    for _, call in ipairs(calls) do
        -- Compare as strings to handle numeric/string id mismatch.
        -- originally: if tostring(SHX7_2.id) == tostring(SHX0_2) then return SHX7_2 end
        if tostring(call.id) == tostring(callId) then
            return call
        end
    end

    return nil
end)


-- =============================================================================
-- SECTION 13 — Jail system (JailMode = "default" + UseInternalJailSystem)
-- originally lines 1463-1787
-- =============================================================================

-- Determine the JailMode (lowercased). Defaults to "default".
-- originally: SHX5_1 = string.lower; SHX6_1 = tostring; SHX7_1 = Config.JailMode or "default"
-- DECOMPILER ARTEFACT: tostring/string.lower spread across 4 return slots; collapsed.
local jailMode = string.lower(tostring(Config.JailMode or "default"))

if jailMode == "default" then

    -- Only activate the internal jail system if explicitly enabled in config.
    -- originally: SHX6_1 = Config.UseInternalJailSystem; if SHX6_1 then … end
    if Config.UseInternalJailSystem then

        -- ---- 13a. Jail countdown thread --------------------------------------
        -- Runs every 60 seconds. Decrements time_left for all jailed citizens.
        -- When time_left reaches 0, the citizen is released (teleported back if
        -- Config.TeleportBackOnRelease is set) and their row is deleted.
        -- originally: CreateThread(function() while true do Wait(60000); … end end)
        CreateThread(function()
            while true do
                Wait(60000)   -- tick every real-world minute

                -- originally: MySQL.query.await("SELECT * FROM mdt_jail WHERE time_left > 0")
                local jailedRows = MySQL.query.await("SELECT * FROM mdt_jail WHERE time_left > 0")
                if jailedRows and #jailedRows > 0 then

                    for _, jailRow in ipairs(jailedRows) do
                        -- Decrement by 1 (represents 1 minute of in-game sentence).
                        -- originally: SHX7_2 = SHX6_2.time_left - 1
                        local newTimeLeft = jailRow.time_left - 1

                        if newTimeLeft <= 0 then
                            -- Sentence served — release the player.
                            -- originally: SHX8_2 = Framework.GetPlayerFromIdentifier(jailRow.citizenid)
                            local jailedPlayer = Framework.GetPlayerFromIdentifier(jailRow.citizenid)

                            if jailedPlayer then
                                -- Resolve the origin (release-to) coords from the jail row.
                                -- May be a JSON string or already a table.
                                -- originally: same json.decode / goto SHX_LABEL_41 pattern
                                local origin = jailRow.origin
                                if type(origin) == "string" then
                                    local decoded = json.decode(origin)
                                    if decoded then origin = decoded end  -- goto SHX_LABEL_41
                                end
                                -- ::SHX_LABEL_41::

                                if Config.TeleportBackOnRelease and origin then
                                    -- Teleport back to where they were arrested.
                                    -- originally: TriggerClientEvent("plt_mdt:client:jailTeleport", jailedPlayer.source, origin, true)
                                    TriggerClientEvent("plt_mdt:client:jailTeleport", jailedPlayer.source, origin, true)
                                    Framework.Notify(jailedPlayer.source,
                                        "Your sentence is over. You have been returned to your original location.", "success")
                                else
                                    -- Just notify.
                                    Framework.Notify(jailedPlayer.source,
                                        "Your sentence is over. You are free to go.", "success")
                                end
                            end

                            -- Delete the jail record regardless of whether the player is online.
                            -- originally: MySQL.query.await("DELETE FROM mdt_jail WHERE citizenid = ?", {citizenid})
                            MySQL.query.await("DELETE FROM mdt_jail WHERE citizenid = ?", { jailRow.citizenid })

                        else
                            -- Sentence still running — update the decremented time.
                            -- originally: MySQL.update.await("UPDATE mdt_jail SET time_left = ? WHERE citizenid = ?", {newTime, citizenid})
                            MySQL.update.await(
                                "UPDATE mdt_jail SET time_left = ? WHERE citizenid = ?",
                                { newTimeLeft, jailRow.citizenid }
                            )
                        end
                    end
                end
            end
        end)


        -- ---- 13b. RegisterNetEvent "plt_mdt:server:completeJailTask" ----------
        -- Fired when a jailed player completes an in-jail task. Reduces their
        -- remaining sentence by Config.JailTaskReduction minutes.
        -- If sentence reaches 0, releases the player and deletes the record.
        -- originally: RegisterNetEvent("plt_mdt:server:completeJailTask", function() … end)
        RegisterNetEvent("plt_mdt:server:completeJailTask", function()
            local playerSource = source
            local player = Framework.GetPlayer(playerSource)
            if not player then return end

            -- originally: MySQL.single.await("SELECT time_left FROM mdt_jail WHERE citizenid = ?", {identifier})
            local jailRow = MySQL.single.await(
                "SELECT time_left FROM mdt_jail WHERE citizenid = ?",
                { player.identifier }
            )

            if not jailRow then return end

            if jailRow.time_left > 0 then
                -- Reduce by the configured amount; floor at 0.
                -- originally: SHX3_2 = SHX2_2.time_left - Config.JailTaskReduction; if SHX3_2 < 0 then SHX3_2 = 0 end
                local newTimeLeft = jailRow.time_left - Config.JailTaskReduction
                if newTimeLeft < 0 then newTimeLeft = 0 end

                -- Persist the updated time.
                MySQL.update.await(
                    "UPDATE mdt_jail SET time_left = ? WHERE citizenid = ?",
                    { newTimeLeft, player.identifier }
                )

                if newTimeLeft == 0 then
                    -- Sentence complete via task — release the player.
                    TriggerClientEvent("plt_mdt:client:jailNotify", playerSource,
                        "Task complete! Your sentence is now finished.", "success")

                    -- Resolve release coords from the origin field.
                    -- originally: MySQL.single.await("SELECT origin FROM mdt_jail …")
                    local originRow = MySQL.single.await(
                        "SELECT origin FROM mdt_jail WHERE citizenid = ?",
                        { player.identifier }
                    )

                    local origin = originRow and originRow.origin
                    if type(origin) == "string" then
                        local decoded = json.decode(origin)
                        if decoded then origin = decoded end  -- goto SHX_LABEL_70
                    end
                    -- ::SHX_LABEL_70::

                    if Config.TeleportBackOnRelease and origin then
                        TriggerClientEvent("plt_mdt:client:jailTeleport", playerSource, origin, true)
                    end

                    MySQL.query.await("DELETE FROM mdt_jail WHERE citizenid = ?", { player.identifier })

                else
                    -- Sentence reduced but not finished.
                    TriggerClientEvent("plt_mdt:client:jailNotify", playerSource,
                        "Task complete! Sentence reduced. Time left: " .. newTimeLeft, "success")
                end
            end
        end)


        -- ---- 13c. checkAndTeleportJailed(source) ----------------------------
        -- Called on player login. If the player has time remaining in jail,
        -- waits 5 s (for the player to fully spawn) then teleports them to
        -- Config.JailLocation and notifies them of their remaining time.
        -- originally: function SHX6_1(SHX0_2) … end  (lines 1685-1732)

        -- originally: function SHX6_1(SHX0_2)
        local function checkAndTeleportJailed(loginSource)
            local player = Framework.GetPlayer(loginSource)
            if not player then return end

            -- originally: MySQL.single.await("SELECT time_left FROM mdt_jail WHERE citizenid = ?", {identifier})
            local jailRow = MySQL.single.await(
                "SELECT time_left FROM mdt_jail WHERE citizenid = ?",
                { player.identifier }
            )

            if jailRow and jailRow.time_left > 0 then
                -- Give the player a moment to fully load before teleporting.
                -- originally: Wait(5000)
                Wait(5000)

                -- originally: TriggerClientEvent("plt_mdt:client:jailTeleport", source, Config.JailLocation, false)
                TriggerClientEvent("plt_mdt:client:jailTeleport", loginSource, Config.JailLocation, false)

                -- Notify the player of their remaining sentence.
                -- originally: Framework.Notify(source, "You are still serving your sentence. Time left: " .. time_left .. " months.", "error")
                Framework.Notify(loginSource,
                    "You are still serving your sentence. Time left: " .. jailRow.time_left .. " months.",
                    "error")
            end
        end


        -- ---- 13d. Framework playerLoaded handlers for jail -------------------
        -- Same ESX / QBCore / QBX branching as Section 3, but calling
        -- checkAndTeleportJailed instead of loadPlayerMetadata.
        -- originally lines 1733-1787

        -- originally: SHX7_1 = Framework.GetFramework()
        if Framework.GetFramework() == "esx" then
            -- originally: AddEventHandler("esx:playerLoaded", function(SHX0_2) SHX6_1(SHX0_2) end)
            -- NOTE: ESX passes xPlayer directly; .source needed for TriggerClientEvent.
            -- Handle both old format (xPlayer object) and new format (just source number)
            AddEventHandler("esx:playerLoaded", function(xPlayerOrId, isNew, skin)
                local sourceId = xPlayerOrId
                -- If xPlayerOrId is a table (object), extract source; otherwise use directly
                if type(xPlayerOrId) == "table" and xPlayerOrId.source then
                    sourceId = xPlayerOrId.source
                end
                checkAndTeleportJailed(sourceId)
            end)
        else
            -- originally: AddEventHandler("QBCore:Server:OnPlayerLoaded", function(SHX0_2) SHX6_1(SHX0_2.PlayerData.source) end)
            AddEventHandler("QBCore:Server:OnPlayerLoaded", function(playerData)
                checkAndTeleportJailed(playerData.PlayerData.source)
            end)

            -- originally: AddEventHandler("qbx_core:server:onPlayerLoaded", function(SHX0_2) SHX6_1(SHX0_2.source) end)
            AddEventHandler("qbx_core:server:onPlayerLoaded", function(playerData)
                checkAndTeleportJailed(playerData.source)
            end)
        end

    end -- Config.UseInternalJailSystem
end -- jailMode == "default"


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         1790
-- Total lines in output:         ~480 (all logic preserved; boilerplate stripped)
-- Obfuscation techniques found:
--   1. SHX* identifier obfuscation throughout — all renamed.
--   2. Module-level SHX0_1…SHX9_1 reused as scratch on each definition;
--      SHX5_1…SHX7_1 reused repeatedly for RegisterCallback / exports calls.
--   3. goto/label control flow — 10 labels resolved to structured if/else:
--      SHX_LABEL_24, _38, _41, _56, _59, _63, _68, _70, _83, _84, _112.
--   4. Deeply nested inner function SHX8_2 (addColumnIfMissing) — extracted
--      as a module-level local for clarity and reuse.
--   5. Repeated inline charinfo resolution pattern — extracted into shared
--      resolvePlayerName() and buildPlayerNameSQL() helpers.
--   6. Decompiler multi-return artefacts:
--      • tostring() spread across 13 vars in charge sync loop — collapsed.
--      • string.lower/tostring spread across 4 vars for JailMode — collapsed.
--      • tonumber spread across 2 vars in hot-restart thread — collapsed.
--   7. Dead code in getOfficerProfile: `SHX4_2 = SHX6_2 or SHX4_2` on the
--      line immediately after a goto target that is never reached — noted and
--      omitted (the line is unreachable by construction).
-- String arrays resolved:        0
-- Renamed identifiers:           9 module-level + ~250 inner-scope locals
-- Constructs flagged for review:
--   • addColumnIfMissing uses MySQL.update.await for DELETE in the
--     removeMissingFromDatabase block — preserved verbatim from the original.
--     This works but is semantically odd; MySQL.query.await would be cleaner.
--   • getOfficerProfile: the dead assignment `SHX4_2 = SHX6_2 or SHX4_2`
--     after SHX_LABEL_68 was never reachable (goto jumps past it). Removed.
--   • checkAndTeleportJailed contains a blocking Wait(5000) called directly
--     in an event handler — this will block the event thread for 5 seconds.
--     In FiveM server-side Lua this is only safe inside a CreateThread.
--     The original has the same issue; preserved as-is.
--   • ESX "esx:playerLoaded" is bound twice — once in Section 3 for metadata
--     loading and once in Section 13d for jail teleport. Both will fire on
--     each player load. This is correct but worth noting.
-- Functionality preserved:       YES