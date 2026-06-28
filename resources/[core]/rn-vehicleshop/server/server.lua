local PurchaseLocks = {}

local function debugPrint(...)
    if Config.Debug then print('[RN-VEHICLESHOP-CM]', ...) end
end

local function encode(value)
    local ok, result = pcall(json.encode, value or {})
    return ok and result or '{}'
end

local function decode(value)
    if type(value) == 'table' then return value end
    if not value or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or {}
end

local function truthy(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local s = tostring(value):lower()
    return s == 'true' or s == 'yes' or s == 'on'
end

local function notify(src, message, kind)
    TriggerClientEvent('rn-vehicleshop:client:notify', src, message or '', kind or 'info')
end

local function callExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    debugPrint(('Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end

local function getCharacterId(src)
    local ok, value = callExport('cm-vehicles', 'GetCharacterId', src)
    if ok and value then return tostring(value) end

    -- 2) cm-core character resolvers (different builds expose different names).
    for _, fn in ipairs({ 'GetCharacterId', 'GetActiveCharacter', 'GetCharacter', 'GetPlayerCharacterId' }) do
        local okc, v = pcall(function() return exports['cm-core'][fn](exports['cm-core'], src) end)
        if okc and v then
            if type(v) == 'table' then
                local id = v.id or v.charId or v.characterId or v.citizenid or v.character_id
                if id then return tostring(id) end
            else
                return tostring(v)
            end
        end
    end

    -- 3) State bag fallbacks.
    ok, value = pcall(function()
        local st = Player(src).state
        return st.charId or st.characterId or st.character_id or st.citizenid
    end)
    if ok and value then return tostring(value) end
    return nil
end

local function getCharacterName(src)
    local fallback = GetPlayerName(src) or ('Player ' .. tostring(src))
    local charId = getCharacterId(src)
    if not charId then return fallback end

    local row = MySQL.single.await('SELECT * FROM characters WHERE id = ? LIMIT 1', { tostring(charId) })
    if row then
        local first = row.first_name or row.firstname or row.firstName
        local last = row.last_name or row.lastname or row.lastName
        if first or last then return (tostring(first or '') .. ' ' .. tostring(last or '')):gsub('^%s+', ''):gsub('%s+$', '') end
        if row.name and row.name ~= '' then return tostring(row.name) end
    end
    return fallback
end

-- Direct fallback that mirrors cm-vehicles' CreateOwnedVehicle exactly (same table,
-- plate format, audit row). Used only if the cm-vehicles export reports the character
-- as "not loaded" even though we resolved a valid charId ourselves. This guarantees
-- the purchase succeeds and the row is identical to what cm-vehicles would have made.
local function generatePlateLikeCmVehicles()
    -- cm-vehicles uses Config.Plate {prefix, length}; default CM + 6 digits.
    local prefix = 'CM'
    local digits = 6
    for _ = 1, 50 do
        local n = math.random(0, (10 ^ digits) - 1)
        local plate = (prefix .. string.format('%0' .. digits .. 'd', n)):upper()
        local exists = MySQL.scalar.await('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not exists then return plate end
    end
    return (prefix .. tostring(os.time() % 1000000)):upper()
end

local function createOwnedVehicleDirect(charId, model, label, trunkLevel, metadata)
    charId = tostring(charId)
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    label = tostring(label or model)
    trunkLevel = tonumber(trunkLevel) or 1
    if trunkLevel < 0 then trunkLevel = 0 end
    local plate = generatePlateLikeCmVehicles()

    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_owned_vehicles
            (owner_character_id, model, label, plate, trunk_level, metadata)
            VALUES (?, ?, ?, ?, ?, ?)]],
            { charId, model, label, plate, trunkLevel, encode(metadata or {}) })
    end)
    if not ok or not id then return false, 'DB insert failed.' end

    -- Match cm-vehicles' audit trail so the row is indistinguishable from a normal create.
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_vehicle_audit (character_id, plate, action, data) VALUES (?, ?, ?, ?)',
            { charId, plate, 'vehicle_created', encode({ model = model, label = label, trunkLevel = trunkLevel, via = 'rn-vehicleshop_direct' }) })
    end)

    return true, { id = id, owner_character_id = charId, model = model, label = label, plate = plate, trunk_level = trunkLevel, is_locked = true, fuel = 100, metadata = metadata or {} }
end

local function resolveAccount(account)
    account = tostring(account or Config.PaymentAccount or 'bank')
    if Config.Accounts and Config.Accounts[account] then return Config.Accounts[account] end
    return account
end

local function removeMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = resolveAccount(account)
    local ok, result = pcall(function()
        return exports['cm-core']:RemoveMoney(src, account, amount)
    end)
    return ok and result == true
end

local function refundMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    account = resolveAccount(account)
    pcall(function() exports['cm-core']:AddMoney(src, account, amount) end)
    pcall(function() exports['cm-core']:AddAccountMoney(src, account, amount) end)
end


local function isAdmin(src)
    if src <= 0 then return true end
    if Config.Admin and Config.Admin.AllPlayers == true then return true end
    local perm = Config.Admin and Config.Admin.AcePermission or 'rnvehicleshop.admin'
    return IsPlayerAceAllowed(src, perm)
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_catalog (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            model VARCHAR(64) NOT NULL UNIQUE,
            label VARCHAR(100) NOT NULL,
            category VARCHAR(64) NOT NULL DEFAULT 'Custom',
            price INT NOT NULL DEFAULT 0,
            trunk_level INT NOT NULL DEFAULT 1,
            available_store TINYINT(1) NOT NULL DEFAULT 0,
            available_server TINYINT(1) NOT NULL DEFAULT 0,
            image VARCHAR(255) NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_category (category),
            INDEX idx_available_store (available_store),
            INDEX idx_available_server (available_server)
        )
    ]])
    -- Migration for servers that created the table before image support existed.
    pcall(function()
        MySQL.query.await('ALTER TABLE cm_vehicle_catalog ADD COLUMN IF NOT EXISTS image VARCHAR(255) NULL')
    end)
end

local function normalizeModel(model)
    return tostring(model or ''):lower():gsub('%s+', '')
end

local function flattenSourceVehicles()
    local byModel, list = {}, {}
    for _, category in ipairs(Config.Vehicles or {}) do
        local title = tostring(category.title or 'Custom')
        for _, vehicle in ipairs(category.buttons or {}) do
            local model = normalizeModel(vehicle.model)
            if model ~= '' and not byModel[model] then
                local row = {
                    model = model,
                    label = tostring(vehicle.name or vehicle.label or vehicle.model),
                    category = title,
                    price = tonumber(vehicle.costs or vehicle.price) or 0,
                    trunkLevel = tonumber(vehicle.trunkLevel or vehicle.trunk_level) or 1
                }
                byModel[model] = row
                list[#list + 1] = row
            end
        end
    end
    table.sort(list, function(a, b)
        if a.category == b.category then return a.label < b.label end
        return a.category < b.category
    end)
    return list, byModel
end

local function parseCatalogRow(row)
    if not row then return nil end
    return {
        id = tonumber(row.id),
        model = normalizeModel(row.model),
        label = tostring(row.label or row.model),
        category = tostring(row.category or 'Custom'),
        price = tonumber(row.price) or 0,
        trunkLevel = tonumber(row.trunk_level) or 1,
        availableStore = truthy(row.available_store),
        availableServer = truthy(row.available_server),
        image = (row.image and tostring(row.image) ~= '' ) and tostring(row.image) or nil,
        metadata = decode(row.metadata)
    }
end

local function getCatalog(includeHidden)
    local rows
    if includeHidden then
        rows = MySQL.query.await('SELECT * FROM cm_vehicle_catalog ORDER BY category ASC, label ASC') or {}
    else
        rows = MySQL.query.await('SELECT * FROM cm_vehicle_catalog WHERE available_store = 1 OR available_server = 1 ORDER BY category ASC, label ASC') or {}
    end
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = parseCatalogRow(row) end
    return out
end

local function getCatalogVehicle(model, requireVisible)
    model = normalizeModel(model)
    if model == '' then return nil end
    local sql = 'SELECT * FROM cm_vehicle_catalog WHERE model = ? LIMIT 1'
    local row = MySQL.single.await(sql, { model })
    row = parseCatalogRow(row)
    if requireVisible and row and not (row.availableStore or row.availableServer) then return nil end
    return row
end

local function buildShopVehicles()
    local groups = {}
    for _, vehicle in ipairs(getCatalog(false)) do
        local category = vehicle.category ~= '' and vehicle.category or 'Custom'
        groups[category] = groups[category] or { title = category, buttons = {} }
        local buyable = vehicle.availableStore == true
        local td = type(vehicle.metadata) == 'table' and type(vehicle.metadata.testDrive) == 'table' and vehicle.metadata.testDrive or {}
        local testEnabled = td.enabled
        if testEnabled == nil then testEnabled = true end
        groups[category].buttons[#groups[category].buttons + 1] = {
            name = vehicle.label,
            costs = tonumber(vehicle.price) or 0,
            model = vehicle.model,
            maxStock = buyable and 'available' or 'event/task only',
            buyable = buyable,
            serverOnly = (vehicle.availableServer == true and not buyable),
            trunkLevel = vehicle.trunkLevel,
            image = vehicle.image,
            testDriveEnabled = testEnabled == true,
            testDriveTimer = tonumber(td.duration) or (Config.TestDrive and tonumber(Config.TestDrive.testDriveTimer)) or 60,
            testDriveCost = tonumber(td.cost) or (Config.TestDrive and tonumber(Config.TestDrive.testDriveCost)) or 0
        }
    end

    local list = {}
    for _, group in pairs(groups) do
        table.sort(group.buttons, function(a, b) return a.name < b.name end)
        list[#list + 1] = group
    end
    table.sort(list, function(a, b) return a.title < b.title end)
    return list
end

local function closeEnoughToShop(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local dist = #(GetEntityCoords(ped) - Config.Location)
    return dist <= 25.0
end

-- Per-player routing bucket so previews never clash between players.
local function playerBucketId(src)
    local base = (Config.Dimension and tonumber(Config.Dimension.base)) or 700000
    return base + tonumber(src)
end

local function enterShopBucket(src)
    if not (Config.Dimension and Config.Dimension.enabled) then return end
    local bucket = playerBucketId(src)
    SetPlayerRoutingBucket(src, bucket)
    -- Relaxed population so the empty private bucket still streams the MLO + props.
    pcall(function() SetRoutingBucketPopulationEnabled(bucket, false) end)
    pcall(function() SetRoutingBucketEntityLockdownMode(bucket, (Config.Dimension.lockdownMode or 'relaxed')) end)
end

local function leaveShopBucket(src)
    if not (Config.Dimension and Config.Dimension.enabled) then return end
    -- Back to the shared world.
    pcall(function() SetPlayerRoutingBucket(src, 0) end)
end

RegisterNetEvent('rn-vehicleshop:server:openUI', function()
    local src = source
    if not closeEnoughToShop(src) then return notify(src, 'You are too far from the dealership.', 'error') end
    enterShopBucket(src)
    TriggerClientEvent('vehicles:client:openUI', src, buildShopVehicles(), {}, getCharacterName(src))
end)

-- Client tells us it has fully left the showroom (closed UI, finished buy/test drive).
RegisterNetEvent('rn-vehicleshop:server:leaveShop', function()
    leaveShopBucket(source)
end)

AddEventHandler('playerDropped', function()
    PurchaseLocks[source] = nil
    leaveShopBucket(source)
end)

RegisterNetEvent('rn-vehicleshop:server:buyVehicle', function(details)
    local src = source
    if PurchaseLocks[src] then return end
    PurchaseLocks[src] = true

    -- IMPORTANT: leave the private showroom bucket BEFORE talking to cm-vehicles.
    -- cm-vehicles tracks "loaded characters" per session; creating an owned vehicle
    -- while the player sits in a custom routing bucket makes it report
    -- "Character is not loaded." Putting them back in bucket 0 first fixes that.
    leaveShopBucket(src)

    local function finish()
        PurchaseLocks[src] = nil
    end

    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)
    local catalog = getCatalogVehicle(model, true)

    if not catalog then
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Vehicle is not available.')
        finish()
        return
    end

    if catalog.availableStore ~= true then
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Event/task only vehicle.')
        finish()
        return
    end

    local price = tonumber(catalog.price) or 0
    local account = Config.PaymentAccount or 'bank'

    if not removeMoney(src, account, price) then
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'You do not have enough money.')
        finish()
        return
    end

    -- Resolve the character so cm-vehicles can attach ownership. If we cannot find a
    -- character, refund and tell the player clearly instead of a vague failure.
    local charId = getCharacterId(src)
    if not charId then
        refundMoney(src, account, price)
        TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, 'Character not found. Relog and try again.')
        finish()
        return
    end

    local meta = {
        boughtFrom = 'rn-vehicleshop',
        price = price,
        category = catalog.category,
        charId = charId,            -- pass through in case cm-vehicles uses it
        characterId = charId,
        owner = charId,
        stored = true,              -- bought but not spawned; parking system handles spawning
        paint = {
            gtaColor = tonumber(details.gtaColor) or 111,
            r = tonumber(details.r) or 255,
            g = tonumber(details.g) or 255,
            b = tonumber(details.b) or 255,
            label = tostring(details.color or 'White')
        }
    }

    local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, meta)

    -- cm-vehicles resolves the character from the player's state bag only; in some
    -- sessions that lookup returns "Character is not loaded" even though we have a
    -- valid charId. In that case, write the owned-vehicle row directly using the same
    -- schema so the purchase still completes and the row is identical.
    if not okExport or createOk ~= true then
        debugPrint(('cm-vehicles create failed (src=%s char=%s model=%s okExport=%s createOk=%s err=%s); using direct insert')
            :format(src, tostring(charId), catalog.model, tostring(okExport), tostring(createOk), tostring(vehicleData)))
        local dok, dres = createOwnedVehicleDirect(charId, catalog.model, catalog.label, catalog.trunkLevel, meta)
        if dok then
            createOk, vehicleData = true, dres
        else
            refundMoney(src, account, price)
            local msg = tostring(dres or vehicleData or 'Could not register vehicle. Payment refunded.')
            TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, false, msg)
            finish()
            return
        end
    end

    -- Purchased and registered to the player. We intentionally do NOT spawn the car;
    -- a parking/retrieve system will spawn it later.
    TriggerClientEvent('rn-vehicleshop:client:purchaseResult', src, true, ('Purchased %s for $%s. It is stored in your garage.'):format(catalog.label, price))
    finish()
end)

RegisterNetEvent('rn-vehicleshop:server:testDriveRequest', function(details)
    local src = source
    details = type(details) == 'table' and details or {}
    local model = normalizeModel(details.model)
    local catalog = getCatalogVehicle(model, true)
    if not catalog then return notify(src, 'This vehicle is not available.', 'error') end
    if not (Config.TestDrive and Config.TestDrive.enabled) then return notify(src, 'Test drive is disabled.', 'error') end

    local td = type(catalog.metadata) == 'table' and type(catalog.metadata.testDrive) == 'table' and catalog.metadata.testDrive or {}
    if td.enabled == false then return notify(src, 'Test drive is disabled for this vehicle.', 'error') end

    local cost = tonumber(td.cost) or tonumber(Config.TestDrive.testDriveCost) or 0
    local duration = tonumber(td.duration) or tonumber(Config.TestDrive.testDriveTimer) or 60
    local account = Config.PaymentAccount or 'bank'
    if not removeMoney(src, account, cost) then return notify(src, 'You do not have enough money for the test drive.', 'error') end

    -- Keep the player in their private showroom bucket while they test drive at the airport.
    enterShopBucket(src)
    TriggerClientEvent('rn-vehicleshop:client:startTestDrive', src, details, duration)
end)


RegisterNetEvent('rn-vehicleshop:server:openAdmin', function()
    local src = source
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    enterShopBucket(src)
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:openAdmin', src, sourceList, getCatalog(true))
end)

RegisterNetEvent('rn-vehicleshop:server:saveAdminVehicle', function(data)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    data = type(data) == 'table' and data or {}

    local model = normalizeModel(data.model)
    if model == '' then return notify(src, 'Model is required.', 'error') end

    local label = tostring(data.label or model):sub(1, 100)
    local category = tostring(data.category or 'Custom'):sub(1, 64)
    local price = math.floor(tonumber(data.price) or 0)
    if price < 0 then price = 0 end
    local trunkLevel = math.floor(tonumber(data.trunkLevel or data.trunk_level) or 1)
    if trunkLevel < 0 then trunkLevel = 0 end

    local availableStore = truthy(data.availableStore or data.available_store)
    local availableServer = truthy(data.availableServer or data.available_server)
    if availableStore then availableServer = true end

    local testDriveEnabled = data.testDriveEnabled
    if testDriveEnabled == nil then testDriveEnabled = data.test_drive_enabled end
    if testDriveEnabled == nil then testDriveEnabled = true end
    testDriveEnabled = truthy(testDriveEnabled)
    local testDriveTimer = math.floor(tonumber(data.testDriveTimer or data.test_drive_timer) or tonumber(Config.TestDrive.testDriveTimer) or 60)
    if testDriveTimer < 10 then testDriveTimer = 10 end
    if testDriveTimer > 600 then testDriveTimer = 600 end
    local testDriveCost = math.floor(tonumber(data.testDriveCost or data.test_drive_cost) or tonumber(Config.TestDrive.testDriveCost) or 0)
    if testDriveCost < 0 then testDriveCost = 0 end

    -- Keep any previously captured image unless this save provides a new path.
    local image = data.image and tostring(data.image) ~= '' and tostring(data.image):sub(1, 255) or nil
    if not image then
        local existing = MySQL.scalar.await('SELECT image FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
        if existing and tostring(existing) ~= '' then image = tostring(existing) end
    end

    -- A car can only be enabled (store or server) once it has a captured image.
    if (availableStore or availableServer) and (not image or image == '') then
        notify(src, 'Capture an image first. A vehicle cannot be enabled without an image.', 'error')
        TriggerClientEvent('rn-vehicleshop:client:adminNeedsImage', src, model, {
            label = label, category = category, price = price, trunkLevel = trunkLevel,
            availableStore = availableStore, availableServer = availableServer,
            testDriveEnabled = testDriveEnabled, testDriveTimer = testDriveTimer, testDriveCost = testDriveCost
        })
        return
    end

    MySQL.insert.await([[
        INSERT INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server, image, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            category = VALUES(category),
            price = VALUES(price),
            trunk_level = VALUES(trunk_level),
            available_store = VALUES(available_store),
            available_server = VALUES(available_server),
            image = VALUES(image),
            metadata = VALUES(metadata)
    ]], { model, label, category, price, trunkLevel, availableStore and 1 or 0, availableServer and 1 or 0, image, encode({
        savedBy = GetPlayerName(src),
        savedAt = os.time(),
        testDrive = {
            enabled = testDriveEnabled,
            duration = testDriveTimer,
            cost = testDriveCost
        }
    }) })

    notify(src, ('Saved %s.'):format(label), 'success')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true))
end)

RegisterNetEvent('rn-vehicleshop:server:disableAdminVehicle', function(model)
    local src = source
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    model = normalizeModel(model)
    if model == '' then return notify(src, 'Model is required.', 'error') end
    local changed = MySQL.update.await('UPDATE cm_vehicle_catalog SET available_store = 0, available_server = 0 WHERE model = ?', { model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        MySQL.insert.await('INSERT IGNORE INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server) VALUES (?, ?, ?, 0, 1, 0, 0)', { model, model, 'Custom' })
    end
    notify(src, ('Disabled %s.'):format(model), 'success')
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true))
end)

-- ============================================================================
-- Transparent vehicle image capture (admin). Mirrors nv_cloth: NUI sends a
-- background-removed PNG (base64), we save it into this resource and store the
-- nui:// path in cm_vehicle_catalog.image so the admin list + store can show it.
-- ============================================================================
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, #b64chars do b64lookup[b64chars:sub(i, i)] = i - 1 end

local function base64Decode(data)
    data = tostring(data or ''):gsub('%s', '')
    data = data:gsub('^data:image/%w+;base64,', '')
    local out, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c ~= '=' then
            local val = b64lookup[c]
            if val ~= nil then
                buffer = buffer * 64 + val
                bits = bits + 6
                if bits >= 8 then
                    bits = bits - 8
                    out[#out + 1] = string.char(math.floor(buffer / (2 ^ bits)) % 256)
                    buffer = buffer % (2 ^ bits)
                end
            end
        end
    end
    return table.concat(out)
end

local function safeFilePart(value)
    value = tostring(value or ''):lower():gsub('[^%w_%-%.]', '_'):gsub('_+', '_')
    return value
end

RegisterNetEvent('rn-vehicleshop:server:saveVehicleImage', function(data)
    local src = source
    if not isAdmin(src) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'no_permission')
        return notify(src, 'No permission to capture vehicle images.', 'error')
    end
    if not (Config.ImageCapture and Config.ImageCapture.enabled) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'capture_disabled')
        return
    end

    data = type(data) == 'table' and data or {}
    local model = normalizeModel(data.model)
    if model == '' then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'invalid_model')
        return
    end

    local raw = data.imageBase64 or data.dataUrl
    if not raw or raw == '' then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'empty_image')
        return
    end

    local bytes = base64Decode(raw)
    if not bytes or #bytes < 100 then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'decode_failed')
        return notify(src, 'Vehicle image decode failed.', 'error')
    end

    local folder = (Config.ImageCapture.folder or 'ui/images/vehicles'):gsub('^/', ''):gsub('/$', '')
    local ext = tostring(data.ext or ''):lower():gsub('[^%w]', '')
    local mime = tostring(data.mime or ''):lower()
    if ext == '' then
        ext = mime:find('webp', 1, true) and 'webp' or 'png'
    end
    if ext ~= 'webp' and ext ~= 'png' then ext = 'png' end
    local fileName = ('%s_%s.%s'):format(safeFilePart(model), os.time(), ext)
    local savePath = ('%s/%s'):format(folder, fileName)
    if not SaveResourceFile(GetCurrentResourceName(), savePath, bytes, #bytes) then
        TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, false, 'save_file_failed')
        return notify(src, 'Could not save vehicle image. Create the ui/images/vehicles folder and check write permission.', 'error')
    end

    -- nui path the UI can load directly: nui://<resource>/<folder>/<file>
    local nuiPath = ('nui://%s/%s/%s'):format(GetCurrentResourceName(), folder, fileName)

    -- Upsert the image onto the catalog row (create a hidden row if it does not exist yet).
    local changed = MySQL.update.await('UPDATE cm_vehicle_catalog SET image = ? WHERE model = ?', { nuiPath, model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        MySQL.insert.await([[
            INSERT INTO cm_vehicle_catalog (model, label, category, price, trunk_level, available_store, available_server, image)
            VALUES (?, ?, ?, 0, 1, 0, 0, ?)
            ON DUPLICATE KEY UPDATE image = VALUES(image)
        ]], { model, tostring(data.label or model), tostring(data.category or 'Custom'), nuiPath })
    end

    TriggerClientEvent('rn-vehicleshop:client:vehicleImageSaved', src, true, nuiPath, model)
    local sourceList = flattenSourceVehicles()
    TriggerClientEvent('rn-vehicleshop:client:adminData', src, sourceList, getCatalog(true))
end)

RegisterCommand('vehicleadmin', function(src)
    if src <= 0 then return end
    if not isAdmin(src) then return notify(src, 'You do not have vehicle admin permission.', 'error') end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src)
end, false)

exports('GetCatalogVehicle', function(model)
    return getCatalogVehicle(model, true)
end)

exports('GiveCatalogVehicle', function(src, model, metadata)
    local catalog = getCatalogVehicle(model, true)
    if not catalog then return false, 'Vehicle is not enabled in catalog.' end
    local okExport, createOk, vehicleData = callExport('cm-vehicles', 'CreateOwnedVehicle', src, catalog.model, catalog.label, catalog.trunkLevel, metadata or { source = 'catalog_export' })
    if not okExport or createOk ~= true then
        local charId = getCharacterId(src)
        if charId then
            local dok, dres = createOwnedVehicleDirect(charId, catalog.model, catalog.label, catalog.trunkLevel, metadata or { source = 'catalog_export' })
            if dok then return true, dres end
        end
        return false, vehicleData or createOk or 'CreateOwnedVehicle failed.'
    end
    return true, vehicleData
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ensureTables()
    debugPrint('Started. Vehicles must be enabled with /vehicleadmin before they appear.')
end)
