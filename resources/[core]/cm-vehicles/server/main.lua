local Config = CMVehicles.Config
local U = CMVehicles.Utils
CMVehicles.Server = CMVehicles.Server or {}
CMVehicles.Server.Spawned = CMVehicles.Server.Spawned or {}
CMVehicles.Server.TrunkOccupants = CMVehicles.Server.TrunkOccupants or {}

local function ensureColumn(tableName, columnName, definition)
    local ok, exists = pcall(function()
        return MySQL.scalar.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    end)
    if ok and not exists then
        pcall(function() MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition)) end)
    end
end

function CMVehicles.Server.EnsureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_owned_vehicles (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            owner_character_id VARCHAR(100) NOT NULL,
            owner_type VARCHAR(24) NOT NULL DEFAULT 'character',
            owner_id VARCHAR(100) NULL,
            model VARCHAR(64) NOT NULL,
            label VARCHAR(100) NOT NULL,
            plate VARCHAR(16) NOT NULL UNIQUE,
            trunk_level INT NOT NULL DEFAULT 1,
            fuel INT NOT NULL DEFAULT 100,
            engine_health FLOAT NOT NULL DEFAULT 1000,
            body_health FLOAT NOT NULL DEFAULT 1000,
            is_locked TINYINT(1) NOT NULL DEFAULT 1,
            is_stored TINYINT(1) NOT NULL DEFAULT 0,
            garage VARCHAR(64) NULL,
            last_position LONGTEXT NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_owner_character_id (owner_character_id),
            INDEX idx_plate (plate),
            INDEX idx_model (model)
        )
    ]])

    ensureColumn('cm_owned_vehicles', 'parking_id', 'VARCHAR(64) NULL')
    ensureColumn('cm_owned_vehicles', 'parked_at', 'TIMESTAMP NULL')
    ensureColumn('cm_owned_vehicles', 'tank_health', 'FLOAT NOT NULL DEFAULT 1000')
    ensureColumn('cm_owned_vehicles', 'dirt_level', 'FLOAT NOT NULL DEFAULT 0')
    ensureColumn('cm_owned_vehicles', 'owner_name', 'VARCHAR(120) NULL')
    ensureColumn('cm_owned_vehicles', 'owner_type', "VARCHAR(24) NOT NULL DEFAULT 'character'")
    ensureColumn('cm_owned_vehicles', 'owner_id', 'VARCHAR(100) NULL')
    pcall(function()
        MySQL.update.await([[UPDATE cm_owned_vehicles
            SET owner_type = 'character', owner_id = owner_character_id
            WHERE (owner_type IS NULL OR owner_type = '' OR owner_type = 'character')
              AND (owner_id IS NULL OR owner_id = '')]])
    end)
    ensureColumn('cm_owned_vehicles', 'insurance_days', 'INT NOT NULL DEFAULT 0')
    ensureColumn('cm_owned_vehicles', 'state_value', 'INT NOT NULL DEFAULT 0')
    -- Cosmetic/mod persistence (colors, extras, wheels, tuning). Stored as JSON.
    ensureColumn('cm_owned_vehicles', 'mods', 'LONGTEXT NULL')
    -- Full physical condition snapshot (windows, doors, tyres and flags).
    ensureColumn('cm_owned_vehicles', 'condition_state', 'LONGTEXT NULL')
    ensureColumn('cm_owned_vehicles', 'sale_pending_token', 'VARCHAR(96) NULL')
    ensureColumn('cm_owned_vehicles', 'sale_pending_at', 'TIMESTAMP NULL')
    -- Phase 2 unified location columns are created in the primary schema pass,
    -- before dependent resources such as cm-house can query them.
    ensureColumn('cm_owned_vehicles', 'location_state', 'VARCHAR(32) NULL')
    ensureColumn('cm_owned_vehicles', 'location_ref', 'VARCHAR(96) NULL')
    ensureColumn('cm_owned_vehicles', 'location_slot', 'INT NULL')
    ensureColumn('cm_owned_vehicles', 'location_updated_at', 'TIMESTAMP NULL')
    -- Police-issued vehicle registration (cm-police MDT). NULL until an
    -- officer issues one -- separate from `plate`, which stays the
    -- internal identity/lookup key every other resource already relies on.
    ensureColumn('cm_owned_vehicles', 'license_number', 'VARCHAR(20) NULL')
    pcall(function() MySQL.query.await('ALTER TABLE cm_owned_vehicles ADD UNIQUE KEY idx_cm_owned_vehicles_license_number (license_number)') end)

    -- v1.3.2.6 one-time, idempotent cleanup. The old window snapshot queried
    -- unsupported eWindowId indexes and could permanently store every pane as
    -- broken. Preserve doors/tyres/flags, discard only the unreliable legacy
    -- window map, and mark the row as schema 2. Real glass damage will be
    -- captured again model-safely the next time the vehicle is stored.
    pcall(function()
        local rows = MySQL.query.await([[
            SELECT id, condition_state
            FROM cm_owned_vehicles
            WHERE condition_state IS NOT NULL AND condition_state <> ''
        ]]) or {}
        local cleaned = 0
        for _, row in ipairs(rows) do
            local state = U.Decode(row.condition_state)
            local schema = type(state) == 'table'
                and (tonumber(state.windowSchema or state.conditionVersion or state.version) or 0) or 0
            if type(state) == 'table' and schema < 2 then
                state.windows = nil
                state.windowSchema = 2
                state.brokenWindows = {}
                MySQL.update.await('UPDATE cm_owned_vehicles SET condition_state = ? WHERE id = ?', {
                    U.Encode(state), tonumber(row.id)
                })
                cleaned = cleaned + 1
            end
        end
        if cleaned > 0 then
            print(('[CM-VEHICLES] Cleaned %s unreliable legacy glass snapshot(s).'):format(cleaned))
        end
    end)

    -- Do not auto-repair zero health here. Zero is valid gameplay damage.
    -- The garage entity now initializes with a separate healthy bootstrap and
    -- then receives the saved condition, so database repair is neither required
    -- nor safe. Legacy fractional values are normalized at read/write boundaries.

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS inventory_items (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            owner_type VARCHAR(50) NOT NULL DEFAULT 'character',
            owner_id VARCHAR(100) NOT NULL,
            slot VARCHAR(50) NOT NULL,
            item_name VARCHAR(100) NOT NULL,
            quantity INT NOT NULL DEFAULT 1,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY unique_owner_slot (owner_type, owner_id, slot),
            INDEX idx_owner (owner_type, owner_id),
            INDEX idx_item_name (item_name)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_audit (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            character_id VARCHAR(100) NULL,
            plate VARCHAR(16) NULL,
            action VARCHAR(64) NOT NULL,
            data LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_character_id (character_id),
            INDEX idx_plate (plate),
            INDEX idx_action (action)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_pending_payouts (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            sale_token VARCHAR(96) NOT NULL,
            vehicle_id BIGINT NOT NULL,
            character_id VARCHAR(100) NOT NULL,
            plate VARCHAR(16) NOT NULL,
            amount INT NOT NULL,
            account VARCHAR(32) NOT NULL DEFAULT 'cash',
            reason VARCHAR(64) NOT NULL,
            status VARCHAR(24) NOT NULL DEFAULT 'pending',
            attempts INT NOT NULL DEFAULT 0,
            last_error VARCHAR(255) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            paid_at TIMESTAMP NULL,
            UNIQUE KEY uq_vehicle_sale_token (sale_token),
            INDEX idx_vehicle_payout_character (character_id, status)
        )
    ]])

    -- A crash after money was sent but before the row was marked paid must not
    -- auto-pay twice. Leave old processing rows for administrator review.
    MySQL.update.await([[
        UPDATE cm_vehicle_pending_payouts
        SET status = 'review_required', last_error = 'server_restart_during_processing'
        WHERE status = 'processing'
    ]])
end

function CMVehicles.Server.Audit(charId, plate, action, data)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_vehicle_audit (character_id, plate, action, data) VALUES (?, ?, ?, ?)', {
            tostring(charId or ''), U.NormalizePlate(plate), action, U.Encode(data or {})
        })
    end)
end

function CMVehicles.Server.GetCharacterId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ok, stateId = pcall(function()
        local st = Player(src).state
        return st.charId or st.characterId or st.character_id or st.citizenid
    end)
    if ok and stateId then return tostring(stateId) end

    ok, stateId = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) == 'table' then
                return p.CharacterId or p.charId or (p.Character and p.Character.id) or (p.character and p.character.id)
            end
        end
    end)
    if ok and stateId then return tostring(stateId) end
    return nil
end


local function numFrom(...)
    for _, v in ipairs({ ... }) do
        local n = tonumber(v)
        if n and n > 0 then return math.floor(n) end
    end
    return 0
end

local function mileagePenaltyInfo(mileage)
    mileage = tonumber(mileage) or 0.0
    if mileage < 5000.0 then return 1.00, 'No mileage penalty yet', 5000 end
    if mileage < 10000.0 then return 0.98, 'Small mileage wear: 2% power loss', 10000 end
    if mileage < 20000.0 then return 0.95, 'Moderate mileage wear: 5% power loss', 20000 end
    if mileage < 50000.0 then return 0.90, 'Heavy mileage wear: 10% power loss', 50000 end
    return 0.85, 'Very high mileage wear: 15% power loss', nil
end

function CMVehicles.Server.GetCharacterName(src, charId)
    local ok, name = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) == 'table' then
                if p.name or p.Name then return p.name or p.Name end
                local c = p.Character or p.character or p.PlayerData or {}
                local first = c.firstName or c.firstname or c.first_name or c.FirstName
                local last = c.lastName or c.lastname or c.last_name or c.LastName
                if first or last then return (tostring(first or '') .. ' ' .. tostring(last or '')):gsub('^%s+', ''):gsub('%s+$', '') end
                if c.name or c.Name then return c.name or c.Name end
            end
        end
    end)
    if ok and name and tostring(name) ~= '' then return tostring(name) end
    return tostring(charId or 'Unknown')
end

local function playerDataMoney(method, src, account, amount, reason)
    if GetResourceState('cm-playerdata') ~= 'started' then return false, nil end
    local ok, result = pcall(function()
        return exports['cm-playerdata'][method](src, account, amount, reason)
    end)
    return ok, result
end

local function corePlayerMoney(method, src, account, amount, reason)
    if GetResourceState('cm-core') ~= 'started' or not exports['cm-core'].GetPlayer then
        return false, nil
    end
    local ok, result = pcall(function()
        local player = exports['cm-core'].GetPlayer(src)
        if type(player) ~= 'table' then error('player_not_found') end
        local fn = player.Functions and player.Functions[method]
            or player[method]
            or player[method:sub(1, 1):lower() .. method:sub(2)]
        if type(fn) ~= 'function' then error('money_method_missing') end
        return fn(account, amount, reason)
    end)
    return ok, result
end

local function genericMoneyExport(method, src, account, amount, reason)
    local attempts = {
        { 'cm-core', method, src, account, amount, reason },
        { 'cm-core', method, src, amount, account, reason },
    }
    if method == 'AddMoney' then
        attempts[#attempts + 1] = { 'cm-core', 'AddCash', src, amount, reason }
        attempts[#attempts + 1] = { 'cm-core', 'GiveMoney', src, amount, reason }
        attempts[#attempts + 1] = { 'cm-core', 'AddPlayerMoney', src, account, amount, reason }
    else
        attempts[#attempts + 1] = { 'cm-core', 'RemoveCash', src, amount, reason }
        attempts[#attempts + 1] = { 'cm-core', 'TakeMoney', src, amount, reason }
        attempts[#attempts + 1] = { 'cm-core', 'RemovePlayerMoney', src, account, amount, reason }
    end

    for _, a in ipairs(attempts) do
        local resource, exportName = a[1], a[2]
        if GetResourceState(resource) == 'started' and exports[resource] and exports[resource][exportName] then
            local args = {}
            for i = 3, #a do args[#args + 1] = a[i] end
            local ok, result = pcall(function()
                return exports[resource][exportName](table.unpack(args))
            end)
            if ok and result ~= false then return true end
        end
    end
    return false
end

function CMVehicles.Server.AddMoney(src, amount, reason, account)
    amount = math.floor(tonumber(amount) or 0)
    account = tostring(account or 'cash')
    if amount <= 0 then return false end

    local ok, result = playerDataMoney('AddMoney', src, account, amount, reason or 'vehicle-payment')
    if ok and result ~= false then return true end
    ok, result = corePlayerMoney('AddMoney', src, account, amount, reason or 'vehicle-payment')
    if ok and result ~= false then return true end
    return genericMoneyExport('AddMoney', src, account, amount, reason or 'vehicle-payment')
end

function CMVehicles.Server.RemoveMoney(src, amount, reason, account)
    amount = math.floor(tonumber(amount) or 0)
    account = tostring(account or 'cash')
    if amount <= 0 then return true end

    local ok, result = playerDataMoney('RemoveMoney', src, account, amount, reason or 'vehicle-charge')
    if ok then return result == true end
    ok, result = corePlayerMoney('RemoveMoney', src, account, amount, reason or 'vehicle-charge')
    if ok then return result ~= false end
    return genericMoneyExport('RemoveMoney', src, account, amount, reason or 'vehicle-charge')
end

function CMVehicles.Server.GetMoney(src, account)
    account = tostring(account or 'cash')
    if GetResourceState('cm-playerdata') == 'started' then
        local ok, value = pcall(function()
            return exports['cm-playerdata']:GetMoney(src, account)
        end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
        local ok, value = pcall(function()
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) ~= 'table' then return nil end
            if p.Functions and p.Functions.GetMoney then return p.Functions.GetMoney(account) end
            if p.GetMoney then return p.GetMoney(account) end
            return nil
        end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

CMVehicles.Server.PayoutLocks = CMVehicles.Server.PayoutLocks or {}

function CMVehicles.Server.ProcessPendingPayout(src, payout)
    if type(payout) ~= 'table' then return false, 'invalid_payout' end
    local payoutId = tonumber(payout.id)
    if not payoutId or CMVehicles.Server.PayoutLocks[payoutId] then return false, 'busy' end
    CMVehicles.Server.PayoutLocks[payoutId] = true

    local claimed = MySQL.update.await([[
        UPDATE cm_vehicle_pending_payouts
        SET status = 'processing', attempts = attempts + 1, last_error = NULL
        WHERE id = ? AND status = 'pending'
    ]], { payoutId })
    if not claimed or tonumber(claimed) <= 0 then
        CMVehicles.Server.PayoutLocks[payoutId] = nil
        return false, 'not_pending'
    end

    local paid = CMVehicles.Server.AddMoney(src, payout.amount, payout.reason, payout.account)
    if not paid then
        MySQL.update.await([[
            UPDATE cm_vehicle_pending_payouts
            SET status = 'pending', last_error = 'economy_add_money_failed'
            WHERE id = ? AND status = 'processing'
        ]], { payoutId })
        CMVehicles.Server.PayoutLocks[payoutId] = nil
        return false, 'economy_add_money_failed'
    end

    local marked = MySQL.update.await([[
        UPDATE cm_vehicle_pending_payouts
        SET status = 'paid', paid_at = NOW(), last_error = NULL
        WHERE id = ? AND status = 'processing'
    ]], { payoutId })
    CMVehicles.Server.PayoutLocks[payoutId] = nil

    if not marked or tonumber(marked) <= 0 then
        pcall(function()
            MySQL.update.await([[
                UPDATE cm_vehicle_pending_payouts
                SET status = 'review_required', last_error = 'money_sent_mark_paid_failed'
                WHERE id = ? AND status = 'processing'
            ]], { payoutId })
        end)
        print(('[cm-vehicles] ^1Payout %s was sent but could not be marked paid. Manual review is required; do not repay automatically.^7')
            :format(tostring(payoutId)))
        return true, 'paid_needs_review'
    end
    return true
end

function CMVehicles.Server.ProcessPendingPayoutsForPlayer(src)
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return end
    local rows = MySQL.query.await([[
        SELECT * FROM cm_vehicle_pending_payouts
        WHERE character_id = ? AND status = 'pending'
        ORDER BY id ASC LIMIT 10
    ]], { tostring(charId) }) or {}
    for _, payout in ipairs(rows) do
        CMVehicles.Server.ProcessPendingPayout(src, payout)
    end
end

CreateThread(function()
    Wait(15000)
    while true do
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            if src then pcall(CMVehicles.Server.ProcessPendingPayoutsForPlayer, src) end
        end
        Wait(60000)
    end
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(playerSource)
    local src = tonumber(playerSource) or tonumber(source)
    if not src then return end
    SetTimeout(2000, function()
        if GetPlayerName(src) then pcall(CMVehicles.Server.ProcessPendingPayoutsForPlayer, src) end
    end)
end)

--- Temporary vehicles are never written to the database. Every save path
--- checks this first: a stray write would turn an admin prop into a real car
--- sitting in someone's garage.
local function skipSave(plate)
    if CMVehicles.Admin and CMVehicles.Admin.IsAdminVehicle then
        return CMVehicles.Admin.IsAdminVehicle(plate)
    end
    return false
end

function CMVehicles.Server.GetVehicleByPlate(plate)
    plate = U.NormalizePlate(plate)
    if plate == '' then return nil end

    -- Admin/temporary vehicles have no database row. Everything downstream --
    -- ResolvePlate, engine start, fuel, locks -- gives up the moment this
    -- returns nil, which is why an admin-spawned car reported "Vehicle not
    -- found" and could not be driven.
    --
    -- Hand back a SYNTHETIC row instead. It is never written anywhere: it
    -- exists only so the rest of the resource can treat the car normally.
    -- (server/admin.lua)
    if CMVehicles.Admin and CMVehicles.Admin.SyntheticRow then
        local fake = CMVehicles.Admin.SyntheticRow(plate)
        if fake then return fake end
    end

    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    if row then
        row.plate = U.NormalizePlate(row.plate)
        row.trunk_level = tonumber(row.trunk_level) or 0
        row.is_locked = U.Truthy(row.is_locked)
        row.is_stored = U.Truthy(row.is_stored)
        row.metadata = U.Decode(row.metadata)
    end
    return row
end

-- Police-issued vehicle registration number (cm-police MDT). Rejects if
-- already registered; otherwise generates a unique number via a retry-loop
-- UPDATE, pcall-guarded so a UNIQUE KEY collision (another vehicle already
-- holding that candidate number) just retries with a new one instead of
-- throwing -- race-safe the same way cm-police's own firearms-license
-- number generator is.
function CMVehicles.Server.IssueVehicleLicense(plate)
    plate = U.NormalizePlate(plate)
    if plate == '' then return false, 'Invalid plate.' end
    local row = MySQL.single.await('SELECT license_number FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not row then return false, 'That vehicle does not exist.' end
    if row.license_number then return false, 'That vehicle is already registered.' end

    for _ = 1, 5 do
        local candidate = ('REG-%06d'):format(math.random(100000, 999999))
        local ok, affected = pcall(function()
            return MySQL.update.await('UPDATE cm_owned_vehicles SET license_number = ? WHERE plate = ? AND license_number IS NULL', { candidate, plate })
        end)
        if ok and tonumber(affected) == 1 then
            return true, ('Registration issued: %s'):format(candidate), candidate
        end
    end
    return false, 'Could not issue a registration number. Try again.'
end

function CMVehicles.Server.GetVehicleById(id)
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { tonumber(id) })
    if row then
        row.plate = U.NormalizePlate(row.plate)
        row.trunk_level = tonumber(row.trunk_level) or 0
        row.is_locked = U.Truthy(row.is_locked)
        row.is_stored = U.Truthy(row.is_stored)
        row.metadata = U.Decode(row.metadata)
    end
    return row
end

function CMVehicles.Server.ResolvePlate(plate, netId)
    plate = U.NormalizePlate(plate)
    netId = tonumber(netId)

    -- When a network entity is supplied it is the source of truth. Never let a
    -- client pair somebody else's database plate with an unrelated nearby car.
    if netId and netId > 0 then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if not ent or ent == 0 or not DoesEntityExist(ent) then return '' end

        local statePlate = ''
        local ok = pcall(function() statePlate = U.NormalizePlate(Entity(ent).state.cmPlate) end)
        if not ok or statePlate == '' then return '' end
        if plate ~= '' and plate ~= statePlate then
            local isLicenseTest = false
            pcall(function() isLicenseTest = Entity(ent).state.cmLicenseTest == true end)
            if not isLicenseTest or plate ~= 'LICENSE' then return '' end
        end
        if not CMVehicles.Server.GetVehicleByPlate(statePlate) then return '' end
        return statePlate
    end

    if plate ~= '' and CMVehicles.Server.GetVehicleByPlate(plate) then return plate end
    return ''
end

local function sameRoutingBucket(src, entity)
    local ok, same = pcall(function()
        return GetPlayerRoutingBucket(src) == GetEntityRoutingBucket(entity)
    end)
    return ok and same == true
end

function CMVehicles.Server.IsOwner(src, plate)
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return false end
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    return row and tostring(row.owner_type or 'character') == 'character'
        and tostring(row.owner_character_id) == tostring(charId) or false
end

function CMVehicles.Server.HasTempKey(src, plate, action)
    local ok, result = U.CallExport(
        'cm-vehiclekeys', 'HasVehicleKey', src, U.NormalizePlate(plate), tostring(action or 'vehicle.drive'))
    if not ok then
        ok, result = U.CallExport('cm-vehiclekeys', 'HasTempKey', src, U.NormalizePlate(plate))
    end
    return ok and result == true
end

function CMVehicles.Server.GetVehicleKeyRecord(src, plate, action)
    local ok, result = U.CallExport(
        'cm-vehiclekeys', 'GetVehicleKeyRecord', src, U.NormalizePlate(plate), tostring(action or 'vehicle.drive'))
    return ok and type(result) == 'table' and result or nil
end

function CMVehicles.Server.HasAccess(src, plate, action)
    -- Admin/temporary vehicles have no row in cm_owned_vehicles, so every
    -- owner check below would fail and the car would report "Vehicle not
    -- found". Ask the admin registry FIRST. (server/admin.lua)
    if CMVehicles.Server.HasAdminAccess and CMVehicles.Server.HasAdminAccess(src, plate) then
        return true
    end

    if CMVehicles.API and CMVehicles.API.CanUseVehicle then
        local allowed = CMVehicles.API.CanUseVehicle(src, plate, action or 'vehicle.drive')
        return allowed == true
    end
    return CMVehicles.Server.IsOwner(src, plate)
        or CMVehicles.Server.HasTempKey(src, plate, action or 'vehicle.drive')
end

function CMVehicles.Server.ValidateNearVehicle(src, netId, maxDistance)
    src = tonumber(src)
    netId = tonumber(netId)
    if not src or src <= 0 or not netId or netId <= 0 then return false, nil, 'missing_entity' end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false, nil, 'entity_missing' end

    local okType, entityType = pcall(GetEntityType, veh)
    if okType and entityType ~= 2 then return false, nil, 'not_vehicle' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, nil, 'ped_missing' end
    if not sameRoutingBucket(src, veh) then return false, nil, 'routing_bucket' end

    local okCoords, dist = pcall(function()
        return #(GetEntityCoords(ped) - GetEntityCoords(veh))
    end)
    if not okCoords then return false, nil, 'coords_failed' end
    local allowed = dist <= (tonumber(maxDistance) or 5.0)
    return allowed, dist, allowed and nil or 'too_far'
end

function CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, rules)
    rules = type(rules) == 'table' and rules or {}
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false, 'Vehicle network id is missing.' end

    local near, dist = CMVehicles.Server.ValidateNearVehicle(src, netId, rules.maxDistance or 8.0)
    if not near then return false, 'You are too far from the vehicle.' end

    local veh = NetworkGetEntityFromNetworkId(netId)
    local resolvedPlate = CMVehicles.Server.ResolvePlate(plate, netId)
    if resolvedPlate == '' then return false, 'Vehicle identity could not be verified.' end

    local row = CMVehicles.Server.GetVehicleByPlate(resolvedPlate)
    if not row then return false, 'Vehicle was not found.' end

    local stateVehicleId
    pcall(function() stateVehicleId = tonumber(Entity(veh).state.cmVehicleId) end)
    if stateVehicleId and tonumber(row.id) ~= stateVehicleId then
        return false, 'Vehicle database identity does not match the entity.'
    end

    local okModel, entityModel = pcall(GetEntityModel, veh)
    if okModel and entityModel and entityModel ~= 0 and entityModel ~= joaat(tostring(row.model or '')) then
        return false, 'Vehicle model does not match the owned record.'
    end

    local active = CMVehicles.Server.SpawnedById and CMVehicles.Server.SpawnedById[tonumber(row.id)] or CMVehicles.Server.Spawned[resolvedPlate]
    if active and tonumber(active.netId) and tonumber(active.netId) ~= netId then
        return false, 'Vehicle network identity is stale.'
    end

    if rules.owner and not CMVehicles.Server.IsOwner(src, resolvedPlate) then
        return false, 'Only the vehicle owner can do that.'
    end
    if rules.access and not CMVehicles.Server.HasAccess(src, resolvedPlate) then
        return false, 'You do not have keys for this vehicle.'
    end
    if rules.driver and not CMVehicles.Server.IsDriverOfVehicle(src, netId) then
        return false, 'You must be the driver of this vehicle.'
    end

    return true, row, veh, dist
end

function CMVehicles.Server.IsDriverOfVehicle(src, netId)
    netId = tonumber(netId)
    if not netId then return false end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return GetVehiclePedIsIn(ped, false) == veh and GetPedInVehicleSeat(veh, -1) == ped
end

function CMVehicles.Server.GetSpawnedNetId(identity)
    local vehicleId = tonumber(identity)
    local plate = vehicleId and '' or U.NormalizePlate(identity)
    if not vehicleId and plate ~= '' and CMVehicles.Server.PlateToVehicleId then
        vehicleId = tonumber(CMVehicles.Server.PlateToVehicleId[plate])
    end
    local data = vehicleId and CMVehicles.Server.SpawnedById
        and CMVehicles.Server.SpawnedById[vehicleId] or nil
    if not data and plate ~= '' then data = CMVehicles.Server.Spawned[plate] end
    return data and data.netId or nil
end

local VehicleCatalogImageCache = {}

function CMVehicles.Server.GetVehicleCatalogImage(model)
    model = tostring(model or ''):lower()
    if model == '' then return nil end
    local cached = VehicleCatalogImageCache[model]
    if cached ~= nil then return cached ~= false and cached or nil end

    if GetResourceState('rn-vehicleshop') == 'started' then
        local ok, image = pcall(function()
            return exports['rn-vehicleshop']:GetVehicleImage(model)
        end)
        if ok and image and tostring(image) ~= '' then
            VehicleCatalogImageCache[model] = tostring(image)
            return VehicleCatalogImageCache[model]
        end
    end

    local ok, image = pcall(function()
        return MySQL.scalar.await(
            'SELECT image FROM cm_vehicle_catalog WHERE LOWER(model) = ? LIMIT 1',
            { model })
    end)
    VehicleCatalogImageCache[model] = ok and image and tostring(image) ~= '' and tostring(image) or false
    return VehicleCatalogImageCache[model] ~= false and VehicleCatalogImageCache[model] or nil
end

function CMVehicles.Server.VehicleInfoFor(src, plate)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return nil end
    local charId = CMVehicles.Server.GetCharacterId(src)
    local owner = charId and tostring(row.owner_type or 'character') == 'character'
        and tostring(row.owner_character_id) == tostring(charId) or false
    local access, accessReason, _, accessContext = false, 'no_access', nil, nil
    if owner then
        access, accessReason = true, 'owner'
    elseif CMVehicles.API and CMVehicles.API.CanUseVehicle then
        access, accessReason, _, accessContext = CMVehicles.API.CanUseVehicle(src, row.id, 'vehicle.info')
    else
        access = CMVehicles.Server.HasTempKey(src, row.plate, 'vehicle.info')
        accessReason = access and 'temporary_key' or 'no_access'
    end

    local keyRecord = CMVehicles.Server.GetVehicleKeyRecord(src, row.plate, 'vehicle.info')
    local familyContext = CMVehicles.API and CMVehicles.API.GetFamilyVehicleContext
        and CMVehicles.API.GetFamilyVehicleContext(src, row, 'vehicle.info') or nil
    if type(accessContext) == 'table' and accessContext.familyId then
        familyContext = accessContext
    elseif type(keyRecord) == 'table' and keyRecord.kind == 'family' then
        familyContext = familyContext or {
            familyId = keyRecord.familyId,
            familyName = keyRecord.familyName,
            vehicleId = keyRecord.vehicleId,
            requiredTier = keyRecord.requiredTier,
            allowed = true,
        }
    end

    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    local stateValue = numFrom(row.state_value, metadata.stateValue, metadata.state_value, metadata.storePrice, metadata.store_price, metadata.purchasePrice, metadata.purchase_price, metadata.price, metadata.vehiclePrice, metadata.vehicle_price)
    local insuranceDays = numFrom(row.insurance_days, row.insurance, metadata.insuranceDays, metadata.insurance_days, metadata.insurance)
    local ownerName = row.owner_name or metadata.ownerName or metadata.owner_name or metadata.owner or CMVehicles.Server.GetCharacterName(src, row.owner_character_id)

    return {
        id = row.id,
        model = row.model,
        label = row.label,
        plate = row.plate,
        ownerCharacterId = tostring(row.owner_type or 'character') == 'character' and tostring(row.owner_character_id) or nil,
        ownerType = tostring(row.owner_type or 'character'),
        ownerId = row.owner_id and tostring(row.owner_id) or tostring(row.owner_character_id),
        ownerName = tostring(ownerName or 'Unknown'),
        insuranceDays = insuranceDays,
        stateValue = stateValue,
        sellValue = math.floor(stateValue * 0.30),
        trunkLevel = row.trunk_level,
        trunkSlots = CMVehicles.Trunk and CMVehicles.Trunk.SlotCount(row.trunk_level) or 0,
        locked = row.is_locked,
        access = access == true,
        accessReason = tostring(accessReason or 'no_access'),
        owner = owner,
        tempKey = keyRecord ~= nil and keyRecord.kind ~= 'family',
        familyKey = keyRecord ~= nil and keyRecord.kind == 'family',
        familyId = familyContext and tonumber(familyContext.familyId) or nil,
        familyName = familyContext and tostring(familyContext.familyName or 'Family') or nil,
        familyTag = familyContext and tostring(familyContext.familyTag or '') or nil,
        familyRequiredTier = familyContext and tonumber(familyContext.requiredTier) or nil,
        familyHouseId = familyContext and tonumber(familyContext.houseId) or nil,
        vehicleImage = CMVehicles.Server.GetVehicleCatalogImage(row.model),
        netId = CMVehicles.Server.GetSpawnedNetId(row.plate),
        fuel = tonumber(row.fuel) or 100,
        engineHealth = U.NormalizeHealth(row.engine_health, 1000.0),
        bodyHealth = U.NormalizeHealth(row.body_health, 1000.0),
        tankHealth = U.NormalizeHealth(row.tank_health, 1000.0),
        dirtLevel = tonumber(row.dirt_level) or 0,
        mileage = tonumber(metadata.mileage) or 0.0,
        mileageMultiplier = select(1, mileagePenaltyInfo(metadata.mileage)),
        mileagePenaltyText = select(2, mileagePenaltyInfo(metadata.mileage)),
        nextMileageService = select(3, mileagePenaltyInfo(metadata.mileage)),
        racingHarness = metadata.racingHarness == true or metadata.racing_harness == true,
        metadata = metadata
    }
end


function CMVehicles.Server.HasRacingHarness(plate)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return false end
    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    return metadata.racingHarness == true or metadata.racing_harness == true
end

function CMVehicles.Server.GeneratePlate(customPrefix, customDigits)
    local prefix = tostring(customPrefix or (Config.Plate and Config.Plate.prefix) or 'CM'):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
    local digits = tonumber(customDigits) or tonumber(Config.Plate and Config.Plate.length) or 6
    digits = math.max(1, math.min(8 - #prefix, math.floor(digits)))
    for _ = 1, 50 do
        local n = math.random(0, (10 ^ digits) - 1)
        local plate = (prefix .. string.format('%0' .. digits .. 'd', n)):upper()
        local exists = MySQL.scalar.await('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not exists then return plate end
    end
    return (prefix .. tostring(os.time() % 1000000)):upper()
end

-- Organization-owned vehicles (fleet cars) are only trusted when the
-- calling resource matches the organization that's supposed to own them --
-- otherwise any resource could mint a vehicle owned by an org it has no
-- business touching. Add a row here (not a new hardcoded == chain) when
-- another resource needs its own organization-owned fleet.
local TRUSTED_ORGANIZATIONS = {
    police = { resource = 'cm-police', prefix = 'POLICE', name = 'Police' },
    ems = { resource = 'cm-ems', prefix = 'EMS', name = 'EMS' },
    sahp = { resource = 'cm-law', prefix = 'SAHP', name = 'SAHP' },
    sheriff = { resource = 'cm-law', prefix = 'BCSO', name = 'Sheriff' },
    fib = { resource = 'cm-law', prefix = 'FIB', name = 'FIB' },
    army = { resource = 'cm-law', prefix = 'ARMY', name = 'Army' },
    -- Legacy pre-migration slots kept so any not-yet-migrated cm-gang fleet
    -- rows (and cm-admin's manual legacy migration path) keep working.
    gang_1 = { resource = 'cm-gang', prefix = 'GNG1', name = 'Gang One' },
    gang_2 = { resource = 'cm-gang', prefix = 'GNG2', name = 'Gang Two' },
    gang_3 = { resource = 'cm-gang', prefix = 'GNG3', name = 'Gang Three' },
    gang_4 = { resource = 'cm-gang', prefix = 'GNG4', name = 'Gang Four' },
    -- Canonical five-gang identities.
    marabunta = { resource = 'cm-gang', prefix = 'MRB', name = 'Marabunta' },
    bloods    = { resource = 'cm-gang', prefix = 'BLD', name = 'Bloods' },
    ballas    = { resource = 'cm-gang', prefix = 'BAL', name = 'Ballas' },
    families  = { resource = 'cm-gang', prefix = 'FAM', name = 'Families' },
    vagos     = { resource = 'cm-gang', prefix = 'VGS', name = 'Vagos' },
}

local function trustedOrgInfo(organization, invokingResource)
    local info = TRUSTED_ORGANIZATIONS[organization]
    if info and info.resource == invokingResource then return info end
    return nil
end

function CMVehicles.Server.CreateOwnedVehicle(src, model, label, trunkLevel, metadata)
    local charId = CMVehicles.Server.GetCharacterId(src)
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    label = tostring(label or model)
    trunkLevel = tonumber(trunkLevel) or Config.DefaultTrunkLevel or 1
    if trunkLevel < 0 then trunkLevel = 0 end
    metadata = type(metadata) == 'table' and metadata or {}
    local ownerType, ownerId, ownerCharacterId
    local organization = tostring(metadata.organization or ''):lower()
    local invokingResource = GetInvokingResource()
    local orgInfo = trustedOrgInfo(organization, invokingResource)
    if orgInfo then
        ownerType, ownerId, ownerCharacterId = 'organization', organization, ('organization:%s'):format(organization)
    else
        if not charId then return false, 'Character is not loaded.' end
        ownerType, ownerId, ownerCharacterId = 'character', tostring(charId), tostring(charId)
    end
    local platePrefix = ownerType == 'organization' and orgInfo.prefix or nil
    local plate = CMVehicles.Server.GeneratePlate(platePrefix, platePrefix and (8 - #platePrefix) or nil)
    local stateValue = numFrom(metadata.stateValue, metadata.state_value, metadata.storePrice, metadata.store_price, metadata.purchasePrice, metadata.purchase_price, metadata.price, metadata.vehiclePrice, metadata.vehicle_price)
    local insuranceDays = numFrom(metadata.insuranceDays, metadata.insurance_days, metadata.insurance)
    local ownerName = ownerType == 'organization' and orgInfo.name
        or metadata.ownerName or metadata.owner_name or CMVehicles.Server.GetCharacterName(src, charId)
    metadata.stateValue = metadata.stateValue or stateValue
    metadata.ownerName = metadata.ownerName or ownerName
    metadata.insuranceDays = metadata.insuranceDays or insuranceDays

    local id = MySQL.insert.await([[INSERT INTO cm_owned_vehicles
        (owner_character_id, owner_type, owner_id, owner_name, model, label, plate, trunk_level, insurance_days, state_value, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], { ownerCharacterId, ownerType, ownerId, tostring(ownerName or ''), model, label, plate, trunkLevel, insuranceDays, stateValue, U.Encode(metadata or {}) })

    CMVehicles.Server.Audit(charId, plate, 'vehicle_created', { model = model, label = label, trunkLevel = trunkLevel, stateValue = stateValue })
    return true, { id = id, owner_character_id = ownerCharacterId, owner_type = ownerType, owner_id = ownerId, owner_name = tostring(ownerName or ''), model = model, label = label, plate = plate, trunk_level = trunkLevel, insurance_days = insuranceDays, state_value = stateValue, is_locked = true, fuel = 100, metadata = metadata or {} }
end

function CMVehicles.Server.CreateOrganizationVehicle(request)
    if GetConvar('cm_environment', GetConvar('cm_env', 'production')) == 'development' then
        print(('[cm-vehicles] CreateOrganizationVehicle request actorSource=%s organizationId=%s model=%s label=%s trunkLevel=%s metadataType=%s'):format(
            type(request) == 'table' and tostring(request.actorSource) or '<unavailable>',
            type(request) == 'table' and tostring(request.organizationId) or '<unavailable>',
            type(request) == 'table' and tostring(request.model) or '<unavailable>',
            type(request) == 'table' and tostring(request.label) or '<unavailable>',
            type(request) == 'table' and tostring(request.trunkLevel) or '<unavailable>',
            type(request) == 'table' and type(request.metadata) or '<unavailable>'))
    end
    if type(request) ~= 'table' then return false, 'invalid_request_type' end

    local src = tonumber(request.actorSource)
    if not src or src <= 0 then return false, 'invalid_actor_source' end
    src = math.floor(src)

    local organization = tostring(request.organizationId or ''):lower():match('^%s*(.-)%s*$')
    if organization == '' or not organization:match('^[a-z0-9_]+$') then return false, 'invalid_organization_id' end
    local orgInfo = TRUSTED_ORGANIZATIONS[organization]
    if not orgInfo then return false, 'unsupported_organization' end

    local model = tostring(request.model or ''):lower():match('^%s*(.-)%s*$')
    if model == '' or not model:match('^[a-z0-9_]+$') then return false, 'invalid_model' end

    local label = request.label == nil and model or tostring(request.label):match('^%s*(.-)%s*$')
    if label == '' or #label > 100 then return false, 'invalid_label' end
    local trunkLevel = request.trunkLevel == nil and (Config.DefaultTrunkLevel or 1) or tonumber(request.trunkLevel)
    if not trunkLevel then return false, 'invalid_trunk_level' end
    trunkLevel = math.max(0, math.min(6, math.floor(trunkLevel)))
    if request.metadata ~= nil and type(request.metadata) ~= 'table' then return false, 'invalid_metadata' end
    local metadata = request.metadata or {}

    if GetResourceState('rn-vehicleshop') ~= 'started' then return false, 'authorization_owner_unavailable' end
    local checked, authorized, authorizationError = pcall(function()
        return exports['rn-vehicleshop']:ConsumeOrganizationVehicleGrant(src, model, organization)
    end)
    if not checked then return false, 'authorization_owner_error' end
    if authorized ~= true then return false, tostring(authorizationError or 'authorization_missing') end

    metadata.source, metadata.organization = 'vehicle_admin_org_grant', organization
    local plate = CMVehicles.Server.GeneratePlate(orgInfo.prefix, 8 - #orgInfo.prefix)
    local actorCharacterId = CMVehicles.Server.GetCharacterId(src)
    local inserted, insertResult = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_owned_vehicles
            (owner_character_id,owner_type,owner_id,owner_name,model,label,plate,trunk_level,metadata)
            VALUES (?,'organization',?,?,?,?,?,?,?)]], {
            ('organization:%s'):format(organization), organization, orgInfo.name, model, label, plate,
            trunkLevel, U.Encode(metadata)
        })
    end)
    if not inserted then
        if GetConvar('cm_environment', GetConvar('cm_env', 'production')) == 'development' then
            print(('[cm-vehicles] CreateOrganizationVehicle database insert failed organizationId=%s model=%s'):format(organization, model))
        end
        return false, 'database_insert_failed'
    end
    local id = tonumber(insertResult)
    if not id then return false, 'database_insert_failed' end
    CMVehicles.Server.Audit(actorCharacterId, plate, 'organization_vehicle_created', {
        vehicleId=id, model=model, organization=organization, actorSource=src
    })
    return true, {success=true,id=id,vehicle_id=id,owner_character_id=('organization:%s'):format(organization),
        owner_type='organization',owner_id=organization,owner_name=orgInfo.name,model=model,label=label,
        plate=plate,trunk_level=trunkLevel,is_locked=true,fuel=100,metadata=metadata}
end

function CMVehicles.Server.DeleteOrganizationVehicle(request)
    if GetInvokingResource() ~= 'cm-gang' or type(request) ~= 'table' then return false, 'untrusted_request' end
    local vehicleId, organization = tonumber(request.vehicleId), tostring(request.organizationId or ''):lower()
    local actorSource = tonumber(request.actorSource)
    if not vehicleId or not TRUSTED_ORGANIZATIONS[organization] or not actorSource or actorSource <= 0 then
        return false, 'invalid_request'
    end
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return false, 'persistent_vehicle_missing' end
    if tostring(row.owner_type) ~= 'organization' or tostring(row.owner_id) ~= organization then
        return false, 'vehicle_ownership_mismatch'
    end
    local active, info = CMVehicles.Spawn and CMVehicles.Spawn.GetSpawnedVehicleInfo(vehicleId)
    if active == true and type(info) == 'table' and tonumber(info.entity) and DoesEntityExist(tonumber(info.entity)) then
        local entity = tonumber(info.entity)
        if GetPedInVehicleSeat(entity, -1) ~= 0 or GetVehicleNumberOfPassengers(entity) > 0 then return false, 'vehicle_occupied' end
    end
    local committed = MySQL.transaction.await({
        { query='DELETE FROM inventory_items WHERE owner_type=? AND owner_id=?', values={'vehicle_trunk',tostring(vehicleId)} },
        { query=[[DELETE FROM cm_owned_vehicles WHERE id=? AND owner_type='organization' AND owner_id=?]], values={vehicleId,organization} },
    })
    if committed ~= true or MySQL.scalar.await('SELECT id FROM cm_owned_vehicles WHERE id=? LIMIT 1',{vehicleId}) then
        return false, 'persistent_delete_failed'
    end
    if CMVehicles.Spawn and CMVehicles.Spawn.DeleteVehicle then pcall(CMVehicles.Spawn.DeleteVehicle, vehicleId) end
    CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(actorSource), row.plate, 'organization_vehicle_deleted', {
        vehicleId=vehicleId,organization=organization,model=row.model
    })
    return true, 'organization_vehicle_deleted'
end

function CMVehicles.Server.EnsureOrganizationOwnership(vehicleId, organization)
    vehicleId = tonumber(vehicleId)
    organization = tostring(organization or ''):lower()
    local invokingResource = GetInvokingResource()
    local orgInfo = trustedOrgInfo(organization, invokingResource)
    if not vehicleId or not orgInfo then return false end
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return false end
    local ownerName = orgInfo.name
    local plate = row.plate
    local active = CMVehicles.Server.GetSpawnedVehicleInfo and CMVehicles.Server.GetSpawnedVehicleInfo(vehicleId)
    local prefix = orgInfo.prefix
    if active ~= true and not tostring(plate or ''):upper():find('^' .. prefix) then
        plate = CMVehicles.Server.GeneratePlate(prefix, 8 - #prefix)
    end
    local changed = MySQL.update.await([[UPDATE cm_owned_vehicles
        SET owner_character_id = ?, owner_type = 'organization', owner_id = ?, owner_name = ?, plate = ?
        WHERE id = ?]], { ('organization:%s'):format(organization), organization, ownerName, plate, vehicleId })
    return tonumber(changed) and tonumber(changed) > 0, plate
end

-- Compatibility helper for integrations that only need to update the
-- human-readable owner name. Legal ownership is determined by owner_type and
-- owner_id; owner_character_id remains populated for legacy schema consumers.
function CMVehicles.Server.SetOwnerDisplay(vehicleId, ownerName)
    vehicleId = tonumber(vehicleId)
    ownerName = tostring(ownerName or '')
    if not vehicleId or ownerName == '' then return false end
    MySQL.update.await('UPDATE cm_owned_vehicles SET owner_name = ? WHERE id = ?', { ownerName, vehicleId })
    return true
end
exports('SetOwnerDisplay', CMVehicles.Server.SetOwnerDisplay)
exports('EnsureOrganizationOwnership', CMVehicles.Server.EnsureOrganizationOwnership)

RegisterNetEvent('cm-vehicles:server:registerNetVehicle', function(plate, netId)
    local src = source
    local ok, row, veh = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, {
        maxDistance = (Config.Interaction.distance or 5.8) + 3.0,
        access = true
    })
    if not ok then return end

    netId = tonumber(netId)
    local registered, info = CMVehicles.Spawn.GetSpawnedVehicleInfo(row.id)
    if registered == true and type(info) == 'table' then
        -- Opening the G menu is informational. It must never re-register a parked
        -- house vehicle as a normal world vehicle, otherwise its house/slot state
        -- is erased and the garage exit callback can no longer resolve it.
        if tonumber(info.netId) == netId then return end
        return
    end

    -- Registry recovery after a resource restart. Reconstruct the lifecycle
    -- context from trusted replicated entity state instead of assuming "world".
    local state = Entity(veh).state
    local houseId = tonumber(state.cmHouseId) or 0
    local slotIndex = tonumber(state.cmHouseSlot) or 0
    local isHouseGarage = state.cmHouseGarageDisplay == true and houseId > 0 and slotIndex > 0

    CMVehicles.Spawn.RegisterEntity(src, row, netId, {
        persistent = isHouseGarage,
        context = isHouseGarage and 'house_garage' or 'world',
        houseId = isHouseGarage and houseId or nil,
        slotIndex = isHouseGarage and slotIndex or nil,
        locked = state.cmLocked == true,
        -- Preserve an already-finalized physical condition during registry repair.
        requiresFinalize = state.cmConditionReady ~= true,
    })
end)

RegisterNetEvent('cm-vehicles:server:requestInfo', function(plate, netId)
    local src = source
    local ok, row = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, {
        maxDistance = (Config.Interaction.lookDistance or 7.5) + 3.0
    })
    if not ok then return U.Notify(src, tostring(row), 'error') end
    local info = CMVehicles.Server.VehicleInfoFor(src, row.plate)
    if not info then return U.Notify(src, 'Vehicle not found.', 'error') end
    info.netId = tonumber(netId)
    TriggerClientEvent('cm-vehicles:client:openMenu', src, info)
end)


local PendingStateSales = {}
local KnownTables = {}

local function databaseTableExists(name)
    if KnownTables[name] ~= nil then return KnownTables[name] end
    local ok, count = pcall(function()
        return MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
        ]], { name })
    end)
    local exists = ok and tonumber(count) and tonumber(count) > 0 or false
    if exists then KnownTables[name] = true end
    return exists
end

local function vehicleHasAnySeatOccupant(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local maxPassengers = 6
    pcall(function() maxPassengers = math.max(0, GetVehicleMaxNumberOfPassengers(entity)) end)
    for seat = -1, maxPassengers do
        local ped = 0
        pcall(function() ped = GetPedInVehicleSeat(entity, seat) end)
        if ped and ped ~= 0 then return true end
    end
    return false
end

RegisterNetEvent('cm-vehicles:server:sellToState', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return U.Notify(src, 'Vehicle not found.', 'error') end
    if not CMVehicles.Server.IsOwner(src, row.plate) then
        return U.Notify(src, 'Only the owner can sell this vehicle to the state.', 'error')
    end

    netId = tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(row.plate)
    local okNear, _, nearReason = CMVehicles.Server.ValidateNearVehicle(src, netId, 10.0)
    if not okNear then
        return U.Notify(src, nearReason == 'routing_bucket'
            and 'You must be in the same location as the vehicle.'
            or 'Move closer to the vehicle.', 'error')
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if vehicleHasAnySeatOccupant(entity) then
        return U.Notify(src, 'Everyone must exit the vehicle before it can be sold.', 'error')
    end
    if CMVehicles.Server.TrunkOccupants and CMVehicles.Server.TrunkOccupants[row.plate] then
        return U.Notify(src, 'Someone is inside the trunk. Remove them before selling.', 'error')
    end

    local vehicleId = tonumber(row.id)
    if GetResourceState('cm-house') == 'started' then
        local checked, garageBusy = pcall(function()
            return exports['cm-house']:IsGarageVehicleOperationActive(vehicleId)
        end)
        if checked and garageBusy == true then
            return U.Notify(src, 'This vehicle is currently moving through a garage operation. Try again when it finishes.', 'error')
        end
    end

    if PendingStateSales[vehicleId] then
        return U.Notify(src, 'This vehicle sale is already being processed.', 'error')
    end

    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    local stateValue = numFrom(row.state_value, metadata.stateValue, metadata.state_value,
        metadata.storePrice, metadata.store_price, metadata.purchasePrice,
        metadata.purchase_price, metadata.price, metadata.vehiclePrice, metadata.vehicle_price)
    if stateValue <= 0 then
        return U.Notify(src, 'State value is missing for this vehicle.', 'error')
    end

    local payout = math.floor(stateValue * 0.30)
    if payout <= 0 then
        return U.Notify(src, 'Sell value is too low.', 'error')
    end

    local operationToken
    if CMVehicles.Operations and CMVehicles.Operations.Begin then
        local opOk, tokenOrReason = CMVehicles.Operations.Begin(vehicleId, 'state_sale', src, {
            stage = 'sale_validated', targetState = 'PENDING_DELETE',
            reason = 'vehicle_state_sale', ttl = 90,
        })
        if opOk ~= true then
            return U.Notify(src, 'This vehicle is already being processed by another operation.', 'error')
        end
        operationToken = tokenOrReason
    end

    PendingStateSales[vehicleId] = true
    local function finish(status, stage, details)
        PendingStateSales[vehicleId] = nil
        if operationToken and CMVehicles.Operations then
            if status == 'completed' and CMVehicles.Operations.Complete then
                pcall(CMVehicles.Operations.Complete, vehicleId, operationToken, stage or 'sale_completed', details or {})
            elseif CMVehicles.Operations.Fail then
                pcall(CMVehicles.Operations.Fail, vehicleId, operationToken, stage or 'sale_failed', details or {})
            end
        end
    end

    local charId = CMVehicles.Server.GetCharacterId(src)
    local saleToken = ('state-sale:%s:%s:%s'):format(vehicleId, os.time(), math.random(100000, 999999))
    local claimed = MySQL.update.await([[
        UPDATE cm_owned_vehicles
        SET sale_pending_token = ?, sale_pending_at = NOW()
        WHERE id = ? AND owner_character_id = ?
          AND (sale_pending_token IS NULL OR sale_pending_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE))
    ]], { saleToken, vehicleId, tostring(charId) })

    if not claimed or tonumber(claimed) <= 0 then
        finish('failed', 'sale_claim_failed')
        return U.Notify(src, 'The vehicle state changed before the sale. Try again.', 'error')
    end

    local affectedHouses = {}
    local hasSlots = databaseTableExists('cm_house_vehicle_slots')
    local hasShared = databaseTableExists('cm_house_shared_vehicles')
    if hasSlots then
        affectedHouses = MySQL.query.await(
            'SELECT DISTINCT house_id FROM cm_house_vehicle_slots WHERE vehicle_id = ?',
            { vehicleId }) or {}
    end

    local tx = {}

    -- The payout row is inserted FROM the exact claimed vehicle row. If the
    -- claim disappeared, this inserts zero rows. Every destructive cleanup
    -- below is conditional on that payout token existing, so a stale request
    -- cannot clear a trunk/house slot without also owning the vehicle sale.
    tx[#tx + 1] = {
        query = [[
            INSERT INTO cm_vehicle_pending_payouts
                (sale_token, vehicle_id, character_id, plate, amount, account, reason, status)
            SELECT ?, v.id, ?, v.plate, ?, 'cash', 'vehicle-state-sale', 'pending'
            FROM cm_owned_vehicles v
            WHERE v.id = ? AND v.owner_character_id = ? AND v.sale_pending_token = ?
        ]],
        values = { saleToken, tostring(charId), payout, vehicleId, tostring(charId), saleToken },
    }
    if hasShared then
        tx[#tx + 1] = {
            query = [[
                DELETE FROM cm_house_shared_vehicles
                WHERE vehicle_id = ?
                  AND EXISTS (SELECT 1 FROM cm_vehicle_pending_payouts WHERE sale_token = ?)
            ]],
            values = { vehicleId, saleToken },
        }
    end
    if hasSlots then
        tx[#tx + 1] = {
            query = [[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = NULL, owner_class = 'personal',
                    assigned_by = NULL, assigned_at = NULL
                WHERE vehicle_id = ?
                  AND EXISTS (SELECT 1 FROM cm_vehicle_pending_payouts WHERE sale_token = ?)
            ]],
            values = { vehicleId, saleToken },
        }
    end
    tx[#tx + 1] = {
        query = [[
            DELETE FROM inventory_items
            WHERE owner_type = ? AND owner_id = ?
              AND EXISTS (SELECT 1 FROM cm_vehicle_pending_payouts WHERE sale_token = ?)
        ]],
        values = { 'vehicle_trunk', tostring(vehicleId), saleToken },
    }
    tx[#tx + 1] = {
        query = [[
            DELETE FROM cm_owned_vehicles
            WHERE id = ? AND owner_character_id = ? AND sale_pending_token = ?
              AND EXISTS (SELECT 1 FROM cm_vehicle_pending_payouts WHERE sale_token = ?)
        ]],
        values = { vehicleId, tostring(charId), saleToken, saleToken },
    }

    local txOk, committed = pcall(function() return MySQL.transaction.await(tx) end)
    if not txOk or committed ~= true then
        MySQL.update.await([[
            UPDATE cm_owned_vehicles SET sale_pending_token = NULL, sale_pending_at = NULL
            WHERE id = ? AND sale_pending_token = ?
        ]], { vehicleId, saleToken })
        finish('failed', 'sale_transaction_failed')
        print(('[cm-vehicles] ^1state sale transaction failed for vehicle %s: %s^7')
            :format(tostring(vehicleId), tostring(committed)))
        return U.Notify(src, 'The vehicle sale could not be completed. Nothing was removed.', 'error')
    end

    local payoutCreated = MySQL.scalar.await(
        'SELECT id FROM cm_vehicle_pending_payouts WHERE sale_token = ? LIMIT 1', { saleToken })
    local stillExists = MySQL.scalar.await('SELECT id FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId })
    if not payoutCreated or stillExists then
        -- Normally an SQL error rolls the entire transaction back. This guard
        -- catches an unexpected zero-row claim without ever paying it.
        if stillExists then
            MySQL.update.await([[
                UPDATE cm_owned_vehicles SET sale_pending_token = NULL, sale_pending_at = NULL
                WHERE id = ? AND sale_pending_token = ?
            ]], { vehicleId, saleToken })
        end
        MySQL.update.await('DELETE FROM cm_vehicle_pending_payouts WHERE sale_token = ?', { saleToken })
        finish('failed', 'sale_commit_not_confirmed')
        return U.Notify(src, 'The vehicle sale was not committed. Nothing was paid.', 'error')
    end

    if CMVehicles.Spawn and CMVehicles.Spawn.DeleteVehicle then
        pcall(CMVehicles.Spawn.DeleteVehicle, vehicleId)
    else
        CMVehicles.Server.Spawned[row.plate] = nil
        if CMVehicles.Server.SpawnedById then CMVehicles.Server.SpawnedById[vehicleId] = nil end
    end
    if entity and entity ~= 0 and DoesEntityExist(entity) then pcall(DeleteEntity, entity) end

    local houseIds = {}
    for _, h in ipairs(affectedHouses) do houseIds[#houseIds + 1] = tonumber(h.house_id) end
    if #houseIds > 0 then TriggerEvent('cm-house:server:vehicleDeleted', vehicleId, houseIds) end

    local payoutRow = MySQL.single.await(
        'SELECT * FROM cm_vehicle_pending_payouts WHERE sale_token = ? LIMIT 1', { saleToken })
    local paid, payStatus = false, 'missing_payout'
    if payoutRow then
        paid, payStatus = CMVehicles.Server.ProcessPendingPayout(src, payoutRow)
    end

    CMVehicles.Server.Audit(charId, row.plate, 'vehicle_sold_to_state', {
        stateValue = stateValue,
        payout = payout,
        payoutStatus = paid and (payStatus or 'paid') or 'queued',
        saleToken = saleToken,
    })

    finish('completed', 'sale_completed', { payout = payout, payoutStatus = paid and payStatus or 'queued' })
    TriggerClientEvent('cm-vehicles:client:soldToState', src, netId, payout)
    if paid then
        U.Notify(src, ('Vehicle sold to state for $%s.'):format(payout), 'success')
    else
        U.Notify(src, ('Vehicle sold. The $%s payout is queued and will retry automatically.'):format(payout), 'info')
    end
end)

CMVehicles.Server.SaveSessions = CMVehicles.Server.SaveSessions or {}
CMVehicles.Server.LastStateSave = CMVehicles.Server.LastStateSave or {}

local function liveNumber(fallback, fn)
    local ok, value = pcall(fn)
    value = ok and tonumber(value) or nil
    return value or tonumber(fallback) or 0.0
end

local function sanitizedNeons(value)
    if type(value) ~= 'table' then return nil end
    local out = {}
    for i = 1, 4 do out[i] = value[i] == true end
    return out
end

RegisterNetEvent('cm-vehicles:server:saveState', function(vehicleId, state)
    local src = source
    state = type(state) == 'table' and state or {}
    local netId = tonumber(state.netId)
    local requested = CMVehicles.Server.GetVehicleById(vehicleId)
    if not requested then return end

    local reason = tostring(state.reason or 'validated_driver_state')
    local recentExit = reason == 'driver_exit' or reason == 'driver_changed_vehicle'
    local ok, row, veh = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, requested.plate, {
        maxDistance = tonumber(Config.Security and Config.Security.maxStateDistance) or 12.0,
        access = true,
        driver = not recentExit
    })
    if not ok or tonumber(row.id) ~= tonumber(vehicleId) then return end

    local now = GetGameTimer()
    local rateKey = ('%s:%s'):format(src, row.id)
    if recentExit then
        -- Once the ped has stepped out, a strict driver-seat check naturally
        -- fails. Accept this one final packet only when this same source had a
        -- server-recorded driver session for the vehicle in the last 6 seconds.
        local previousSession = CMVehicles.Server.SaveSessions[rateKey]
        if not previousSession or not previousSession.at or now - previousSession.at > 6000 then return end
    end
    local minInterval = tonumber(Config.Security and Config.Security.saveStateMinIntervalMs) or 2000
    if now - (CMVehicles.Server.LastStateSave[rateKey] or 0) < minInterval then return end
    CMVehicles.Server.LastStateSave[rateKey] = now

    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    local coords = GetEntityCoords(veh)
    local heading = GetEntityHeading(veh)
    local session = CMVehicles.Server.SaveSessions[rateKey]
    local addedMileage = 0.0
    if session and session.coords and session.at then
        local elapsedSeconds = math.max(0.1, (now - session.at) / 1000.0)
        local actualKm = #(coords - session.coords) / 1000.0
        local maxSpeed = tonumber(Config.Security and Config.Security.maxMileageSpeedKmh) or 450.0
        local maxKm = (maxSpeed * elapsedSeconds / 3600.0) + 0.05
        addedMileage = math.max(0.0, math.min(actualKm, maxKm))
    end
    CMVehicles.Server.SaveSessions[rateKey] = { coords = coords, at = now }
    metadata.mileage = math.max(0.0, (tonumber(metadata.mileage) or 0.0) + addedMileage)

    local neons = sanitizedNeons(state.neons)
    if neons then metadata.neons = neons end

    local entityState = Entity(veh).state
    -- A house garage entity is still a stored vehicle. Never persist its
    -- interior-instance coordinates as the real-world last position.
    if entityState.cmHouseGarageDisplay == true then return end
    -- Never persist the temporary/default skeleton used before final condition
    -- verification. This prevents a failed initialization from writing false
    -- zero health back into an otherwise healthy database vehicle.
    if entityState.cmConditionReady ~= true then return end

    local dbFuel = tonumber(row.fuel) or 100.0
    local dbEngine = U.NormalizeHealth(row.engine_health, 1000.0)
    local dbBody = U.NormalizeHealth(row.body_health, 1000.0)
    local dbTank = U.NormalizeHealth(row.tank_health, 1000.0)
    local dbDirt = tonumber(row.dirt_level) or 0.0

    -- Normal driving may only make condition worse. The validated driver client
    -- owns the live GTA vehicle skeleton; server health natives are not reliable
    -- during OneSync ownership migration and were persisting false low damage.
    -- Submitted values are constrained below by the current DB state, so this
    -- path can record wear but can never perform a free repair.
    local liveFuel = math.max(0.0, math.min(100.0, tonumber(entityState.cmFuel) or dbFuel))
    local function submittedWear(value, dbValue)
        local n = tonumber(value)
        if n == nil or n ~= n then return dbValue end
        -- Client values here come directly from FiveM health natives. Preserve a
        -- real zero; legacy 0..1 percentage conversion applies only to DB data.
        return math.max(0.0, math.min(1000.0, n))
    end
    local liveEngine = submittedWear(state.engineHealth, dbEngine)
    local liveBody = submittedWear(state.bodyHealth, dbBody)
    local liveTank = submittedWear(state.tankHealth, dbTank)
    local liveDirt = math.max(0.0, math.min(15.0, tonumber(state.dirtLevel) or dbDirt))

    local fuel = math.min(liveFuel, dbFuel)
    local engine = math.min(liveEngine, dbEngine)
    local body = math.min(liveBody, dbBody)
    local tank = math.min(liveTank, dbTank)
    local dirt = math.max(liveDirt, dbDirt)

    if liveFuel > dbFuel + 0.75 then entityState:set('cmFuel', dbFuel, true) end
    if liveEngine > dbEngine + 0.5 then pcall(function() SetVehicleEngineHealth(veh, dbEngine) end) end
    if liveBody > dbBody + 0.5 then pcall(function() SetVehicleBodyHealth(veh, dbBody) end) end
    if liveTank > dbTank + 0.5 then pcall(function() SetVehiclePetrolTankHealth(veh, dbTank) end) end
    if liveDirt + 0.05 < dbDirt then pcall(function() SetVehicleDirtLevel(veh, dbDirt) end) end

    local conditionState = type(state.conditionState) == 'table'
        and U.MergeConditionWear(U.Decode(row.condition_state), state.conditionState)
        or U.SanitizeConditionState(U.Decode(row.condition_state))

    local persistOk, persistResult
    if CMVehicles.Persistence and CMVehicles.Persistence.WriteState then
        persistOk, persistResult = CMVehicles.Persistence.WriteState(row, {
            fuel = fuel,
            engineHealth = engine,
            bodyHealth = body,
            tankHealth = tank,
            dirtLevel = dirt,
            conditionState = conditionState,
            position = { x = coords.x, y = coords.y, z = coords.z, w = heading },
            metadata = metadata,
            reason = reason,
        })
    else
        local affected = MySQL.update.await([[UPDATE cm_owned_vehicles SET
            fuel = ?, engine_health = ?, body_health = ?, tank_health = ?, dirt_level = ?, condition_state = ?, last_position = ?, metadata = ?
            WHERE id = ?]], {
            math.floor(fuel + 0.5), engine, body, tank, dirt,
            U.Encode(conditionState),
            U.Encode({ x = coords.x, y = coords.y, z = coords.z, w = heading }),
            U.Encode(metadata), row.id
        })
        persistOk, persistResult = affected ~= nil, { changed = true }
    end
    if persistOk ~= true then return end

    entityState:set('cmFuel', fuel, true)
    entityState:set('cmEngineHealth', engine, true)
    entityState:set('cmBodyHealth', body, true)
    entityState:set('cmTankHealth', tank, true)
    entityState:set('cmDirtLevel', dirt, true)
    entityState:set('cmConditionState', conditionState, true)
    entityState:set('cmEngineDestroyed', engine <= (tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0), true)
    entityState:set('cmMileage', tonumber(metadata.mileage) or 0.0, true)
    entityState:set('cmRacingHarness', metadata.racingHarness == true or metadata.racing_harness == true, true)
end)

-- Client persistence may record natural wear only. It may never improve fuel,
-- health or cleanliness. Paid refuels/repairs/washes must use the server export
-- ServiceVehicle after their own server-side validation and payment.
RegisterNetEvent('cm-vehicles:server:persistService', function(plate, patch, netId)
    local src = source
    patch = type(patch) == 'table' and patch or {}
    local ok, row, veh = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, {
        maxDistance = tonumber(Config.Security and Config.Security.maxServiceDistance) or 8.0,
        access = true
    })
    if not ok then return end

    local sets, params = {}, {}
    local entityState = Entity(veh).state

    if patch.fuel ~= nil then
        local liveFuel = math.max(0.0, math.min(100.0, tonumber(entityState.cmFuel) or tonumber(row.fuel) or 100.0))
        local dbFuel = tonumber(row.fuel) or 100.0
        if liveFuel <= dbFuel + 0.75 then
            sets[#sets+1] = 'fuel = ?'; params[#params+1] = math.floor(math.min(liveFuel, dbFuel) + 0.5)
            if liveFuel > dbFuel then entityState:set('cmFuel', dbFuel, true) end
        else
            entityState:set('cmFuel', dbFuel, true)
        end
    end

    local liveEngine = U.ClampHealth(liveNumber(row.engine_health, function() return GetVehicleEngineHealth(veh) end))
    local liveBody = U.ClampHealth(liveNumber(row.body_health, function() return GetVehicleBodyHealth(veh) end))
    local liveTank = U.ClampHealth(liveNumber(row.tank_health, function() return GetVehiclePetrolTankHealth(veh) end))
    local liveDirt = math.max(0.0, math.min(15.0, liveNumber(row.dirt_level, function() return GetVehicleDirtLevel(veh) end)))

    local dbEngine = U.NormalizeHealth(row.engine_health, 1000.0)
    local dbBody = U.NormalizeHealth(row.body_health, 1000.0)
    local dbTank = U.NormalizeHealth(row.tank_health, 1000.0)
    local dbDirt = tonumber(row.dirt_level) or 0.0
    if patch.engineHealth ~= nil then
        if liveEngine <= dbEngine + 0.5 then
            sets[#sets+1] = 'engine_health = ?'; params[#params+1] = math.min(liveEngine, dbEngine)
            if liveEngine > dbEngine then pcall(function() SetVehicleEngineHealth(veh, dbEngine) end) end
        else pcall(function() SetVehicleEngineHealth(veh, dbEngine) end) end
    end
    if patch.bodyHealth ~= nil then
        if liveBody <= dbBody + 0.5 then
            sets[#sets+1] = 'body_health = ?'; params[#params+1] = math.min(liveBody, dbBody)
            if liveBody > dbBody then pcall(function() SetVehicleBodyHealth(veh, dbBody) end) end
        else pcall(function() SetVehicleBodyHealth(veh, dbBody) end) end
    end
    if patch.tankHealth ~= nil then
        if liveTank <= dbTank + 0.5 then
            sets[#sets+1] = 'tank_health = ?'; params[#params+1] = math.min(liveTank, dbTank)
            if liveTank > dbTank then pcall(function() SetVehiclePetrolTankHealth(veh, dbTank) end) end
        else pcall(function() SetVehiclePetrolTankHealth(veh, dbTank) end) end
    end
    if patch.dirtLevel ~= nil then
        if liveDirt + 0.05 >= dbDirt then
            sets[#sets+1] = 'dirt_level = ?'; params[#params+1] = math.max(liveDirt, dbDirt)
            if liveDirt < dbDirt then pcall(function() SetVehicleDirtLevel(veh, dbDirt) end) end
        else pcall(function() SetVehicleDirtLevel(veh, dbDirt) end) end
    end

    if #sets == 0 then return end
    params[#params+1] = row.plate
    if skipSave(plate) then return end
    MySQL.update.await(('UPDATE cm_owned_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', ')), params)
end)

local function sanitizeMods(mods)
    if type(mods) ~= 'table' then return nil end
    local out = {}
    local numericFields = {
        primaryColor = {0, 255}, secondaryColor = {0, 255}, pearlColor = {0, 255},
        wheelColor = {0, 255}, wheelType = {0, 20}, windowTint = {-1, 10},
        plateIndex = {0, 10}, livery = {-1, 200}, tyreLevel = {0, 4}
    }
    for key, range in pairs(numericFields) do
        if mods[key] ~= nil then
            out[key] = math.floor(math.max(range[1], math.min(range[2], tonumber(mods[key]) or range[1])))
        end
    end
    out.turbo = mods.turbo == true
    out.xenon = mods.xenon == true
    out.bulletproofTyres = mods.bulletproofTyres == true
    out.mods, out.extras = {}, {}
    if type(mods.mods) == 'table' then
        for key, value in pairs(mods.mods) do
            local modType, index = tonumber(key), tonumber(value)
            if modType and modType >= 0 and modType <= 49 and index and index >= -1 and index <= 200 then
                out.mods[tostring(math.floor(modType))] = math.floor(index)
            end
        end
    end
    if type(mods.extras) == 'table' then
        for key, value in pairs(mods.extras) do
            local extra = tonumber(key)
            if extra and extra >= 0 and extra <= 20 then out.extras[tostring(math.floor(extra))] = value == true end
        end
    end
    return out
end

function CMVehicles.Server.SaveVehicleModsAuthorized(src, plate, netId, mods)
    local ok, row = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, {
        maxDistance = tonumber(Config.Security and Config.Security.maxServiceDistance) or 8.0,
        access = true
    })
    if not ok then return false, tostring(row) end
    local clean = sanitizeMods(mods)
    if not clean then return false, 'Invalid modification payload.' end
    MySQL.update.await('UPDATE cm_owned_vehicles SET mods = ? WHERE id = ?', { U.Encode(clean), row.id })
    CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), row.plate, 'authorized_mods_saved', clean)
    return true
end
exports('SaveVehicleModsAuthorized', CMVehicles.Server.SaveVehicleModsAuthorized)

RegisterNetEvent('cm-vehicles:server:saveMods', function()
    U.Notify(source, 'Modification saving requires server-authorized tuning.', 'error')
end)

-- ── Key lending / revoking management ──
-- Thin owner-facing surface over cm-vehiclekeys temp keys, plus a metadata list
-- so the owner can see/revoke who currently holds a key.
RegisterNetEvent('cm-vehicles:server:lendKey', function(plate, targetSrc)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate)
    targetSrc = tonumber(targetSrc)
    if not CMVehicles.Server.IsOwner(src, plate) then return U.Notify(src, 'Only the owner can lend keys.', 'error') end
    if not targetSrc or not GetPlayerName(targetSrc) then return U.Notify(src, 'Target player is not online.', 'error') end

    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    metadata.lentKeys = type(metadata.lentKeys) == 'table' and metadata.lentKeys or {}
    local maxKeys = tonumber(Config.Keys and Config.Keys.maxLentKeysPerVehicle) or 8
    if #metadata.lentKeys >= maxKeys then return U.Notify(src, 'Key limit reached for this vehicle.', 'error') end

    local ok, result = U.CallExport('cm-vehiclekeys', 'GiveTempKey', src, targetSrc, plate)
    if not ok or result ~= true then return U.Notify(src, tostring(result or 'Could not lend key.'), 'error') end

    local targetChar = CMVehicles.Server.GetCharacterId(targetSrc)
    metadata.lentKeys[#metadata.lentKeys + 1] = { charId = tostring(targetChar), name = GetPlayerName(targetSrc), at = os.time() }
    if skipSave(plate) then return end
    MySQL.update.await('UPDATE cm_owned_vehicles SET metadata = ? WHERE plate = ?', { U.Encode(metadata), plate })
    U.Notify(src, ('Key lent to %s.'):format(GetPlayerName(targetSrc)), 'success')
    U.Notify(targetSrc, 'You received a temporary key.', 'success')
end)

RegisterNetEvent('cm-vehicles:server:revokeKey', function(plate, targetCharId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate)
    if not CMVehicles.Server.IsOwner(src, plate) then return U.Notify(src, 'Only the owner can revoke keys.', 'error') end

    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    metadata.lentKeys = type(metadata.lentKeys) == 'table' and metadata.lentKeys or {}

    local kept = {}
    for _, entry in ipairs(metadata.lentKeys) do
        if tostring(entry.charId) ~= tostring(targetCharId) then kept[#kept+1] = entry end
    end
    metadata.lentKeys = kept
    if skipSave(plate) then return end
    MySQL.update.await('UPDATE cm_owned_vehicles SET metadata = ? WHERE plate = ?', { U.Encode(metadata), plate })

    -- Tell cm-vehiclekeys to drop the temp key if that char is online.
    U.CallExport('cm-vehiclekeys', 'RevokeTempKeyByChar', plate, tostring(targetCharId))
    U.Notify(src, 'Key revoked.', 'success')
end)

-- Owner queries current key holders (for a management UI later).
CMVehicles.Server.GetLentKeys = function(plate)
    plate = U.NormalizePlate(plate)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return {} end
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    return type(metadata.lentKeys) == 'table' and metadata.lentKeys or {}
end
exports('GetLentKeys', CMVehicles.Server.GetLentKeys)

-- Server-side service exports so other resources (mechanic script, pump prop
-- placed server-side, admin commands) can act without touching a client.
CMVehicles.Server.ServiceVehicle = function(plate, patch, targetSrc)
    plate = U.NormalizePlate(plate)
    patch = type(patch) == 'table' and patch or {}
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return false end
    local sets, params = {}, {}
    local map = { fuel = 'fuel', engineHealth = 'engine_health', bodyHealth = 'body_health', tankHealth = 'tank_health', dirtLevel = 'dirt_level' }
    for key, col in pairs(map) do
        if patch[key] ~= nil then
            sets[#sets+1] = col .. ' = ?'
            if key == 'fuel' then params[#params+1] = math.floor(math.max(0, math.min(100, tonumber(patch[key]) or 0)))
            elseif key == 'dirtLevel' then params[#params+1] = math.max(0, math.min(15, tonumber(patch[key]) or 0))
            else params[#params+1] = U.NormalizeHealth(patch[key], 1000.0) end
        end
    end
    if patch.clearVisualDamage == true and patch.conditionState == nil then patch.conditionState = {} end
    if type(patch.conditionState) == 'table' then
        patch.conditionState = U.SanitizeConditionState(patch.conditionState)
        sets[#sets+1] = 'condition_state = ?'
        params[#params+1] = U.Encode(patch.conditionState)
    end
    if #sets == 0 then return false end
    params[#params+1] = plate
    if skipSave(plate) then return end
    MySQL.update.await(('UPDATE cm_owned_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', ')), params)
    local active = CMVehicles.Server.SpawnedById and CMVehicles.Server.SpawnedById[tonumber(row.id)] or CMVehicles.Server.Spawned[plate]
    if active then
        local entity = tonumber(active.entity) or 0
        if (entity == 0 or not DoesEntityExist(entity)) and tonumber(active.netId) then
            entity = NetworkGetEntityFromNetworkId(tonumber(active.netId))
        end
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local state = Entity(entity).state
            if patch.fuel ~= nil then state:set('cmFuel', tonumber(patch.fuel) or 100.0, true) end
            if patch.engineHealth ~= nil then
                local repairedEngine = U.NormalizeHealth(patch.engineHealth, 1000.0)
                state:set('cmEngineHealth', repairedEngine, true)
                state:set('cmEngineDestroyed', repairedEngine <= (tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0), true)
            end
            if patch.bodyHealth ~= nil then state:set('cmBodyHealth', U.NormalizeHealth(patch.bodyHealth, 1000.0), true) end
            if patch.tankHealth ~= nil then state:set('cmTankHealth', U.NormalizeHealth(patch.tankHealth, 1000.0), true) end
            if patch.dirtLevel ~= nil then state:set('cmDirtLevel', tonumber(patch.dirtLevel) or 0.0, true) end
            if type(patch.conditionState) == 'table' then
                state:set('cmConditionState', patch.conditionState, true)
            end
            -- A trusted service is not complete until a controlling client has
            -- physically applied and verified the requested condition.
            state:set('cmConditionReady', false, true)
            -- The requested/broadcast target may not currently have this entity
            -- streamed in (e.g. a fleet vehicle serviced from far away). Keep the
            -- patch replicated so the pooled vehicle scan on whichever client
            -- eventually streams it in can retry the trusted apply instead of
            -- leaving the vehicle permanently damaged/undriveable.
            state:set('cmPendingServicePatch', patch, true)
            targetSrc = tonumber(targetSrc)
            if not targetSrc or targetSrc <= 0 or not GetPlayerName(targetSrc) then targetSrc = -1 end
            TriggerClientEvent('cm-vehicles:client:applyTrustedCondition', targetSrc, tonumber(active.netId) or 0, patch)
        end
    end
    return true
end
exports('ServiceVehicle', CMVehicles.Server.ServiceVehicle)

RegisterNetEvent('cm-vehicles:server:pingTracker', function(plate)
    local src = source
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row or not CMVehicles.Server.IsOwner(src, row.plate) then return end
    local metadata = row.metadata or {}
    if metadata.has_tracker ~= true then return U.Notify(src, 'This vehicle has no GPS tracker.', 'error') end
    local active = CMVehicles.Server.SpawnedById and CMVehicles.Server.SpawnedById[tonumber(row.id)] or CMVehicles.Server.Spawned[row.plate]
    if active and active.netId then
        TriggerClientEvent('cm-vehicles:client:trackerPing', src, active.netId, row.label)
    else
        U.Notify(src, 'Tracker signal is offline.', 'error')
    end
end)



-- Public racing-harness installation events were removed in v3.3.9.
-- Paid/authorized server resources must use the InstallRacingHarness export.

RegisterNetEvent('cm-vehicles:server:requestMyVehicles', function()
    local src = source
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return end
    local rows = MySQL.query.await('SELECT id, model, label, plate, trunk_level, is_locked, is_stored FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC', { charId }) or {}
    TriggerClientEvent('cm-vehicles:client:showMyVehicles', src, rows)
end)

RegisterCommand('myvehicles', function(src)
    if src <= 0 then return end
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return U.Notify(src, 'Character is not loaded.', 'error') end
    local rows = MySQL.query.await('SELECT id, model, label, plate, trunk_level, is_locked, is_stored FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC', { charId }) or {}
    TriggerClientEvent('cm-vehicles:client:showMyVehicles', src, rows)
end, false)

RegisterCommand('vehgive', function(src, args)
    if src <= 0 then return end
    if not (Config.Commands and Config.Commands.adminSpawnOwned == true) then
        return U.Notify(src, 'The /vehgive command is disabled.', 'error')
    end
    local ace = tostring(Config.Commands.vehGiveAce or 'cmvehicles.vehgive')
    if not IsPlayerAceAllowed(src, ace) then
        return U.Notify(src, 'You do not have permission to use /vehgive.', 'error')
    end

    local model = tostring(args[1] or 'sultan'):lower()
    local trunkLevel = tonumber(args[2]) or 3
    local label = args[3] or model
    local ok, result = CMVehicles.Server.CreateOwnedVehicle(src, model, label, trunkLevel, { source = 'vehgive' })
    if not ok then return U.Notify(src, tostring(result), 'error') end
    CMVehicles.Spawn.CreateForPlayer(src, result, { warp = true, engineOn = false })
    U.Notify(src, ('Created %s.'):format(result.label), 'success')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    for key in pairs(CMVehicles.Server.SaveSessions or {}) do
        if key:match('^' .. tostring(src) .. ':') then CMVehicles.Server.SaveSessions[key] = nil end
    end
    for key in pairs(CMVehicles.Server.LastStateSave or {}) do
        if key:match('^' .. tostring(src) .. ':') then CMVehicles.Server.LastStateSave[key] = nil end
    end
    if CMVehicles.Persistence and CMVehicles.Persistence.HandlePlayerDropped then
        pcall(CMVehicles.Persistence.HandlePlayerDropped, src)
    elseif Config.Rules.DeletePlayerVehiclesOnLogout and CMVehicles.Spawn then
        CMVehicles.Spawn.DeletePlayerVehicles(src)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CMVehicles.Server.EnsureTables()
    print('[CM-VEHICLES] Started v3.5.0 | revocable family keys + RN catalog images | Engine key: Left Ctrl.')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if CMVehicles.Persistence and CMVehicles.Persistence.FlushAll then
        pcall(CMVehicles.Persistence.FlushAll, 'server_resource_stop')
    end
    if not Config.Rules.DeleteSpawnedVehiclesOnRestart then return end
    local registry = CMVehicles.Server.SpawnedById or CMVehicles.Server.Spawned
    for _, data in pairs(registry) do
        if data.entity and DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
    end
end)

exports('CreateOwnedVehicle', CMVehicles.Server.CreateOwnedVehicle)
exports('CreateOrganizationVehicle', CMVehicles.Server.CreateOrganizationVehicle)
exports('DeleteOrganizationVehicle', CMVehicles.Server.DeleteOrganizationVehicle)
exports('GetVehicleByPlate', CMVehicles.Server.GetVehicleByPlate)
exports('IssueVehicleLicense', CMVehicles.Server.IssueVehicleLicense)
exports('HasVehicleAccess', CMVehicles.Server.HasAccess)
exports('PlayerOwnsVehicle', CMVehicles.Server.IsOwner)
exports('GetCharacterId', CMVehicles.Server.GetCharacterId)
exports('HasRacingHarness', CMVehicles.Server.HasRacingHarness)

-- ────────────────────────────────────────────────────────────────────
--  G-MENU SERVICE ITEMS (jerry can / repair kit)
--  The player must actually own the item. We verify + consume it here, then
--  tell the client to apply the effect. Same items the gas station sells, so
--  there is one source of truth and no way to refuel for free.
-- ────────────────────────────────────────────────────────────────────
local function inventoryHasItem(src, itemName, amount)
    if GetResourceState('cm-inventory') ~= 'started' then return false end
    local ok, has = pcall(function() return exports['cm-inventory']:HasItem(src, itemName, amount or 1) end)
    return ok and has == true
end

local function inventoryRemoveItem(src, itemName, amount)
    if GetResourceState('cm-inventory') ~= 'started' then return false end
    local ok, res = pcall(function()
        return exports['cm-inventory']:RemoveItem(src, itemName, amount or 1, nil, 'cm_vehicles_service')
    end)
    return ok and res ~= false
end

-- Phase 1: player asked to use a service item. We only CHECK they have it and
-- tell the client to start the timed animation. Nothing is consumed yet, so a
-- cancelled action costs them nothing.
local pendingService = {}   -- [src] = { kind, token, expires }

RegisterNetEvent('cm-vehicles:server:useServiceItem', function(kind, plate, netId)
    local src = source
    kind = tostring(kind or '')

    local svc = Config.Service or {}
    local itemName, label
    if kind == 'refuel' then
        itemName = svc.fuelCanItem or 'fuel_can'
        label = 'jerry can'
    elseif kind == 'repair' then
        itemName = svc.repairKitItem or 'repair_kit'
        label = 'repair kit'
    elseif kind == 'wash' then
        itemName = svc.washKitItem or 'wash_kit'
        label = 'wash kit'
    else
        return
    end

    local valid, row = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, {
        maxDistance = tonumber(Config.Security and Config.Security.maxServiceDistance) or 8.0,
        access = true
    })
    if not valid then return U.Notify(src, tostring(row), 'error') end

    if not inventoryHasItem(src, itemName, 1) then
        U.Notify(src, ("You don't have a %s. Buy one at a gas station."):format(label), 'error')
        return
    end

    local token = ('%s-%d-%d'):format(kind, src, math.random(100000, 999999))
    pendingService[src] = { kind = kind, token = token, expires = os.time() + 60, plate = row.plate, netId = tonumber(netId) }

    TriggerClientEvent('cm-vehicles:client:beginServiceItem', src, kind, tonumber(netId) or 0, token)
end)

-- Phase 2: the client finished the animation. NOW consume the item and tell it
-- to apply the effect. The token stops a client from confirming out of nowhere.
RegisterNetEvent('cm-vehicles:server:confirmServiceItem', function(kind, token, netId)
    local src = source
    local pend = pendingService[src]
    if not pend or pend.token ~= token or pend.kind ~= kind then return end
    if os.time() > (pend.expires or 0) then
        pendingService[src] = nil
        return
    end
    pendingService[src] = nil

    local svc = Config.Service or {}
    local itemName, label
    if kind == 'refuel' then
        itemName = svc.fuelCanItem or 'fuel_can'
        label = 'jerry can'
    elseif kind == 'repair' then
        itemName = svc.repairKitItem or 'repair_kit'
        label = 'repair kit'
    elseif kind == 'wash' then
        itemName = svc.washKitItem or 'wash_kit'
        label = 'wash kit'
    else
        return
    end

    if tonumber(netId) ~= tonumber(pend.netId) then return end
    local valid, row = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, pend.plate, {
        maxDistance = tonumber(Config.Security and Config.Security.maxServiceDistance) or 8.0,
        access = true
    })
    if not valid then return U.Notify(src, tostring(row), 'error') end

    -- Re-check + consume (they could have dropped it mid-animation).
    if not inventoryHasItem(src, itemName, 1) then
        U.Notify(src, ("You no longer have a %s."):format(label), 'error')
        return
    end
    if not inventoryRemoveItem(src, itemName, 1) then
        U.Notify(src, ('Could not use the %s.'):format(label), 'error')
        return
    end

    local patch = {}
    if kind == 'refuel' then
        patch.fuel = math.min(tonumber(Config.Service and Config.Service.maxFuel) or 100.0,
            (tonumber(row.fuel) or 0.0) + (tonumber(Config.Service and Config.Service.gasCanRefillAmount) or 25.0))
    elseif kind == 'repair' then
        patch.bodyHealth = tonumber(Config.Service and Config.Service.RepairKit and Config.Service.RepairKit.bodyAmount) or 1000.0
        -- The validated repair item is an explicit repair authority, so it may
        -- clear the monotonic visual-wear snapshot after fixing doors/windows/tyres.
        patch.conditionState = {}
    elseif kind == 'wash' then
        patch.dirtLevel = tonumber(Config.Service and Config.Service.washResetsDirtTo) or 0.0
    end

    if not CMVehicles.Server.ServiceVehicle(row.plate, patch) then
        return U.Notify(src, 'Could not update the vehicle service state.', 'error')
    end
    TriggerClientEvent('cm-vehicles:client:applyServiceItem', src, kind, tonumber(netId) or 0, patch)
end)

AddEventHandler('playerDropped', function()
    pendingService[source] = nil
end)

-- ────────────────────────────────────────────────────────────────────
--  RACING HARNESS — authorized server export only
--  The public client/server installation events and test command were removed.
--  A trusted resource must consume the item or payment first, then call this
--  export with the player, vehicle plate, and network ID.
-- ────────────────────────────────────────────────────────────────────
function CMVehicles.Server.InstallRacingHarness(src, plate, netId)
    src = tonumber(src)
    netId = tonumber(netId)
    if not src or src <= 0 or not GetPlayerName(src) then
        return false, 'A valid online player source is required.'
    end

    local invoking = GetInvokingResource()
    local allow = Config.Security and Config.Security.authorizedHarnessResources or {}
    if invoking and invoking ~= GetCurrentResourceName() and allow[invoking] ~= true then
        print(('[cm-vehicles] ^1Rejected racing harness install from unauthorized resource %s.^7')
            :format(tostring(invoking)))
        return false, 'That resource is not authorized to install racing harnesses.'
    end

    local ok, row, entity = CMVehicles.Server.ResolveAndValidateVehicle(src, netId, plate, {
        maxDistance = tonumber(Config.Security and Config.Security.maxServiceDistance) or 8.0,
        access = true,
    })
    if not ok then return false, row end

    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    if metadata.racingHarness == true or metadata.racing_harness == true then
        return false, 'This vehicle already has a racing harness installed.'
    end

    metadata.racingHarness = true
    metadata.racing_harness = true
    local affected = MySQL.update.await([[
        UPDATE cm_owned_vehicles SET metadata = ?
        WHERE id = ? AND owner_character_id = ?
    ]], { U.Encode(metadata), row.id, tostring(row.owner_character_id) })
    if not affected or tonumber(affected) <= 0 then
        return false, 'The vehicle changed before the harness could be installed.'
    end

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        Entity(entity).state:set('cmRacingHarness', true, true)
    end

    CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), row.plate,
        'racing_harness_installed', { installedByResource = invoking or GetCurrentResourceName() })
    return true
end
exports('InstallRacingHarness', CMVehicles.Server.InstallRacingHarness)
