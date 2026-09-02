-- CM-LAW routine Army supply orders.
-- This module owns the order state machine and cm_legal_* ledger only. It does
-- not create inventory containers or duplicate cm-weapons/cm-items definitions.

local LogisticsReady = false
local orderLocks = {}
local carrierLocks = {}
local missingConvoys = {}
local requestRate = {}

local L = Config.Logistics
local SOURCE_ORG = tostring(L.SourceOrganization or 'army'):lower()
local ACTIVE_STATES = { requested = true, accepted = true, prepared = true, loaded = true, in_transit = true }
local R = L.Robbery or {}

local function normalizedName(value)
    value = tostring(value or ''):lower():gsub('%s+', '_'):gsub('[^a-z0-9_%-%.]', '')
    return value ~= '' and value or nil
end

local function realItem(itemName)
    itemName = normalizedName(itemName)
    if not itemName then return nil end

    local ok, weapon = pcall(function() return exports['cm-weapons']:GetWeapon(itemName) end)
    if ok and type(weapon) == 'table' and weapon.enabled ~= false then
        return {
            itemName = itemName, itemType = 'weapon', label = tostring(weapon.label or itemName),
            image = tostring(weapon.image or ''), description = tostring(weapon.description or ''),
        }
    end
    local okAmmo, ammo = pcall(function() return exports['cm-weapons']:GetAmmo(itemName) end)
    if okAmmo and type(ammo) == 'table' and ammo.enabled ~= false then
        return {
            itemName = itemName, itemType = 'ammo', label = tostring(ammo.label or itemName),
            image = tostring(ammo.image or ''), description = tostring(ammo.description or ''),
        }
    end
    local okItem, item = pcall(function() return exports['cm-items']:GetPhysicalItem(itemName) end)
    if okItem and type(item) == 'table' and item.inventory ~= false and item.virtual ~= true then
        return {
            itemName = itemName, itemType = tostring(item.category or 'supply'),
            label = tostring(item.label or itemName), image = tostring(item.image or ''),
            description = tostring(item.description or ''),
        }
    end
    -- Armor is authored by cm-gunstore and synchronized into cm-items on
    -- startup. Keep this fallback for servers where that sync is delayed.
    local okStore, catalog = pcall(function() return exports['cm-gunstore']:GetCatalog(true) end)
    if okStore and type(catalog) == 'table' then
        for _, row in ipairs(catalog) do
            local rowName = normalizedName(row.item_name or row.itemName)
            local rowType = tostring(row.item_type or row.itemType or ''):lower()
            if rowName == itemName and rowType == 'armor' then
                return {
                    itemName = itemName, itemType = 'armor', label = tostring(row.label or itemName),
                    image = tostring(row.image or ''), description = tostring(row.description or ''),
                }
            end
        end
    end
    return nil
end

local function requestableMap()
    local out = {}
    for key, entry in pairs(L.RequestableItems or {}) do
        local configured = type(entry) == 'table' and entry or { itemName = entry }
        if type(key) == 'string' and configured.itemName == nil then configured.itemName = key end
        if configured.enabled ~= false then
            local item = realItem(configured.itemName)
            if item then
                item.maxQuantity = math.max(1, math.min(tonumber(L.MaxQuantityPerLine) or 1000,
                    math.floor(tonumber(configured.maxQuantity) or tonumber(L.MaxQuantityPerLine) or 1000)))
                out[item.itemName] = item
            end
        end
    end
    return out
end

local function logisticsPermission(member, key)
    local permission = L.Permissions and L.Permissions[key]
    return member and (member.isLeader or (permission and member.permissions[permission] == true)) or false
end

local function actorFor(src, permission, requireDuty)
    local member, characterId = activeMemberForSource(src)
    if not member then return nil, nil, 'You are not a member of a legal organization.' end
    if member.suspended then return nil, characterId, 'Your organization access is suspended.' end
    if requireDuty and not member.onDuty then return nil, characterId, 'You must be on duty for logistics.' end
    if permission and not logisticsPermission(member, permission) then
        return nil, characterId, 'Your rank cannot perform this logistics action.'
    end
    return member, characterId
end

local function receivingPoint(orgId)
    local configured = L.ReceivingPoints and L.ReceivingPoints[orgId]
    if type(configured) == 'table' and tonumber(configured.x) and tonumber(configured.y) and tonumber(configured.z) then
        return {
            x = tonumber(configured.x), y = tonumber(configured.y), z = tonumber(configured.z),
            heading = tonumber(configured.heading or configured.h) or 0.0,
            bucket = tonumber(configured.bucket or configured.routing_bucket) or 0,
        }
    end
    local facility = LawFacilityLocation(orgId, L.ReceivingFacilityType or 'armory')
    if not facility then return nil end
    return { x = facility.x, y = facility.y, z = facility.z, heading = facility.heading, bucket = facility.bucket }
end

local function nearPoint(src, point, radius)
    local ped = GetPlayerPed(src)
    if not point or not ped or ped == 0 then return false end
    if GetPlayerRoutingBucket(src) ~= (tonumber(point.bucket) or 0) then return false end
    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= (radius or 3.0)
end

local function withOrderLock(orderId, callback)
    orderId = tonumber(orderId)
    if not orderId or type(callback) ~= 'function' then return false, 'Invalid order.' end
    if orderLocks[orderId] then return false, 'That order is already being processed.' end
    orderLocks[orderId] = true
    local result = { pcall(callback) }
    orderLocks[orderId] = nil
    local called = table.remove(result, 1)
    if not called then return false, tostring(result[1] or 'Order operation failed safely.') end
    if #result == 0 then return true end
    return true, table.unpack(result)
end

local function withCarrierLock(characterId, callback)
    characterId = tostring(characterId or '')
    if characterId == '' or type(callback) ~= 'function' then return false, 'Invalid carrier.' end
    if carrierLocks[characterId] then return false, 'That character is already handling a cargo crate.' end
    carrierLocks[characterId] = true
    local result = { pcall(callback) }
    carrierLocks[characterId] = nil
    local called = table.remove(result, 1)
    if not called then return false, tostring(result[1] or 'Cargo operation failed safely.') end
    return true, table.unpack(result)
end

local function orderRows(orderId)
    return MySQL.query.await([[SELECT l.id AS line_id, l.item_name, l.quantity,
        o.id, o.requester_org, o.requester_cid, o.status, o.robbery_state,
        o.wreck_x, o.wreck_y, o.wreck_z, o.wreck_bucket, o.wreck_expires_at,
        o.accepted_by_cid,
        o.shipment_plate, o.receiving_x, o.receiving_y, o.receiving_z,
        o.receiving_heading, o.receiving_bucket, o.created_at, o.accepted_at,
        o.prepared_at, o.loaded_at, o.departed_at, o.delivered_at, o.cancelled_at
        FROM cm_legal_logistics_orders o
        JOIN cm_legal_logistics_order_lines l ON l.order_id = o.id
        WHERE o.id = ? ORDER BY l.id]], { tonumber(orderId) }) or {}
end

local function orderHeader(orderId)
    return MySQL.single.await('SELECT * FROM cm_legal_logistics_orders WHERE id = ? LIMIT 1', { tonumber(orderId) })
end

local function orderPayload(rowList, actor)
    local first = rowList[1]
    if not first then return nil end
    local itemMap = requestableMap()
    local lines = {}
    for _, row in ipairs(rowList) do
        local item = itemMap[tostring(row.item_name):lower()] or realItem(row.item_name) or {}
        lines[#lines + 1] = {
            itemName = tostring(row.item_name), label = tostring(item.label or row.item_name),
            itemType = tostring(item.itemType or 'supply'), quantity = tonumber(row.quantity) or 0,
        }
    end
    local status = tostring(first.status)
    local isArmy = actor and actor.organizationId == SOURCE_ORG
    local isRequester = actor and actor.organizationId == tostring(first.requester_org)
    local actions = {}
    if isArmy and status == 'requested' and logisticsPermission(actor, 'accept') then actions.accept = true end
    if isArmy and status == 'accepted' and logisticsPermission(actor, 'prepare') then actions.prepare = true end
    if isArmy and status == 'prepared' and logisticsPermission(actor, 'load') then actions.load = true end
    if isArmy and status == 'loaded' and logisticsPermission(actor, 'load') then actions.depart = true end
    if isArmy and status == 'in_transit' and logisticsPermission(actor, 'deliver') then actions.deliver = true end
    if isArmy and ACTIVE_STATES[status] and tostring(first.robbery_state or 'eligible') == 'eligible'
        and logisticsPermission(actor, 'cancel') then actions.cancel = true end
    if isRequester and status == 'requested' and logisticsPermission(actor, 'cancel') then actions.cancel = true end
    if isArmy and (status == 'prepared' or status == 'loaded' or status == 'in_transit' or status == 'wrecked')
        and logisticsPermission(actor, 'recover') then actions.recover = true end
    return {
        id = tonumber(first.id), requesterOrg = tostring(first.requester_org),
        requesterLabel = Config.Organizations[tostring(first.requester_org)]
            and Config.Organizations[tostring(first.requester_org)].shortLabel or tostring(first.requester_org),
        status = status, robberyState = tostring(first.robbery_state or 'eligible'),
        lines = lines, shipment = first.shipment_plate and tostring(first.shipment_plate) or nil,
        createdAt = tostring(first.created_at or ''), receiving = {
            x = tonumber(first.receiving_x), y = tonumber(first.receiving_y), z = tonumber(first.receiving_z),
            bucket = tonumber(first.receiving_bucket) or 0,
        }, actions = actions,
    }
end

local function visibleOrders(actor)
    local rows
    if actor.organizationId == SOURCE_ORG then
        rows = MySQL.query.await([[SELECT id FROM cm_legal_logistics_orders
            WHERE status NOT IN ('delivered','cancelled') ORDER BY id DESC LIMIT 100]]) or {}
    else
        rows = MySQL.query.await([[SELECT id FROM cm_legal_logistics_orders
            WHERE requester_org = ? ORDER BY id DESC LIMIT 50]], { actor.organizationId }) or {}
    end
    local out = {}
    for _, row in ipairs(rows) do
        local payload = orderPayload(orderRows(row.id), actor)
        if payload then out[#out + 1] = payload end
    end
    return out
end

local function requestablePayload()
    local out = {}
    for _, item in pairs(requestableMap()) do
        out[#out + 1] = item
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function requireOrderLineRows(orderId)
    local rows = MySQL.query.await('SELECT id AS line_id, item_name, quantity FROM cm_legal_logistics_order_lines WHERE order_id = ? ORDER BY id',
        { tonumber(orderId) }) or {}
    return rows
end

local function stockKeys(rows, destinationOrg)
    local keys = {}
    for _, row in ipairs(rows) do
        keys[#keys + 1] = SOURCE_ORG .. ':' .. tostring(row.item_name)
        if destinationOrg then keys[#keys + 1] = destinationOrg .. ':' .. tostring(row.item_name) end
    end
    return keys
end

local function normalizePlate(value)
    return tostring(value or ''):upper():gsub('%s+', '')
end

local function currentShipmentVehicle(src, shipmentPlate, orderId)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 'Character is not loaded.' end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil, 'You must be driving the shipment vehicle.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil, 'Only the shipment driver can do that.' end
    if normalizePlate(GetVehicleNumberPlateText(vehicle)) ~= normalizePlate(shipmentPlate) then
        return nil, 'This is not the shipment vehicle for that order.'
    end
    local known, isAdminVehicle = pcall(function()
        return exports['cm-vehicles']:IsAdminVehicle(shipmentPlate)
    end)
    if not known or isAdminVehicle ~= true then return nil, 'This is not an authorized shipment vehicle.' end
    if orderId then
        local state = Entity(vehicle).state.cmLegalLogistics
        if type(state) ~= 'table' or tonumber(state.orderId) ~= tonumber(orderId) then
            return nil, 'The shipment vehicle identity does not match this order.'
        end
    end
    return vehicle
end

local function logOrder(orgId, cid, action, orderId, extra)
    extra = type(extra) == 'table' and extra or {}
    extra.orderId = tonumber(orderId)
    logActivity(orgId, cid, action, extra)
end

local function notifyShipmentAttack(header)
    for _, rawSource in ipairs(GetPlayers()) do
        local target = tonumber(rawSource)
        local member = target and select(1, activeMemberForSource(target)) or nil
        if member and (member.organizationId == SOURCE_ORG
            or (R.NotifyDestination == true and member.organizationId == tostring(header.requester_org))) then
            TriggerClientEvent('cm-hud:client:notify', target,
                member.organizationId == SOURCE_ORG and 'Military cargo breach detected.'
                    or 'Supply shipment under attack.', 'error')
        end
    end
end

local function gangContext(src)
    if GetResourceState('cm-gang') ~= 'started' then return nil, 'Gang services are unavailable.' end
    local cid = characterIdFor(src)
    if not cid then return nil, 'Character is not loaded.' end
    local ok, membership = pcall(function()
        return exports['cm-gang']:GetGangForCharacter(cid)
    end)
    if not ok or type(membership) ~= 'table' or membership.enabled ~= true
        or tostring(membership.gangId or '') == '' then
        return nil, 'You must be an active gang member.' 
    end
    local permission = tostring(R.GangPermission or 'gang.rob_items')
    local permissionOk, allowed = pcall(function()
        return exports['cm-gang']:HasPermission(cid, permission)
    end)
    if not permissionOk or allowed ~= true then
        return nil, 'Your gang rank cannot rob convoy cargo.'
    end
    return { characterId = tostring(cid), gangId = tostring(membership.gangId) }
end

local function sourceAlive(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    local ok, dead = pcall(function() return exports['cm-playerdata']:IsDead(src) end)
    if not ok or dead == true then return false end
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityHealth(ped) > 0
end

local function vehicleForOrder(orderId, header)
    header = header or orderHeader(orderId)
    if not header or not header.shipment_plate then return nil, 'That shipment vehicle is no longer available.' end
    local plate = normalizePlate(header.shipment_plate)
    local ok, listed = pcall(function() return exports['cm-vehicles']:ListAdminVehicles() end)
    if not ok or type(listed) ~= 'table' then return nil, 'Shipment vehicle services are unavailable.' end
    for _, row in ipairs(listed) do
        if normalizePlate(row.plate) == plate and row.alive == true then
            local entity = tonumber(row.entity)
            if not entity or entity == 0 then
                entity = row.netId and NetworkGetEntityFromNetworkId(tonumber(row.netId)) or 0
            end
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                local registered, isAdminVehicle = pcall(function()
                    return exports['cm-vehicles']:IsAdminVehicle(header.shipment_plate)
                end)
                local state = Entity(entity).state.cmLegalLogistics
                if isAdminVehicle and type(state) == 'table' and tonumber(state.orderId) == tonumber(orderId) then
                    return entity
                end
            end
        end
    end
    return nil, 'The shipment vehicle is not present.'
end

local function convoyRear(vehicle)
    local coords = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local distance = tonumber(R.RearDistance) or 3.5
    return vector3(coords.x - forward.x * distance, coords.y - forward.y * distance, coords.z + 0.7)
end

local function nearConvoyRear(src, vehicle)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return false end
    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(vehicle) then return false end
    return #(GetEntityCoords(ped) - convoyRear(vehicle)) <= (tonumber(R.InteractionDistance) or 2.5)
end

local function vehicleStopped(vehicle)
    return GetEntitySpeed(vehicle) <= (tonumber(R.MaxStoppedSpeed) or 0.75)
end

local function cargoUnitSize(itemName, quantity)
    local configured = R.CargoUnits and R.CargoUnits[tostring(itemName):lower()]
    configured = math.floor(tonumber(configured) or 0)
    if configured < 1 then configured = math.max(1, math.floor(tonumber(quantity) or 1)) end
    return configured
end

local function cargoRows(orderId, states)
    local query = 'SELECT * FROM cm_legal_logistics_cargo WHERE order_id = ?'
    local values = { tonumber(orderId) }
    if type(states) == 'table' and #states > 0 then
        local marks = {}
        for _, state in ipairs(states) do marks[#marks + 1] = '?' ; values[#values + 1] = state end
        query = query .. ' AND state IN (' .. table.concat(marks, ',') .. ')'
    end
    return MySQL.query.await(query .. ' ORDER BY id', values) or {}
end

local function cargoPayload(row, stateOverride)
    if not row then return nil end
    return {
        id = tonumber(row.id), orderId = tonumber(row.order_id), itemName = tostring(row.item_name),
        quantity = tonumber(row.quantity) or 0, state = stateOverride or tostring(row.state),
        carrierSource = tonumber(row.carrier_source), x = tonumber(row.x), y = tonumber(row.y),
        z = tonumber(row.z), bucket = tonumber(row.bucket) or 0,
    }
end

local function sendCargoNearby(row, stateOverride)
    local payload = cargoPayload(row, stateOverride)
    if not payload then return end
    local x, y, z = payload.x, payload.y, payload.z
    if payload.carrierSource then
        local carrierPed = GetPlayerPed(payload.carrierSource)
        if carrierPed and carrierPed ~= 0 then
            local position = GetEntityCoords(carrierPed)
            x, y, z = position.x, position.y, position.z
        end
    end
    if not x or not y or not z then return end
    local radius = tonumber(R.VisualRadius) or 100.0
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local ped = target and GetPlayerPed(target) or 0
        if ped and ped ~= 0 and GetPlayerRoutingBucket(target) == (payload.bucket or 0)
            and #(GetEntityCoords(ped) - vector3(x, y, z)) <= radius then
            TriggerClientEvent('cm-law:client:logisticsCargoSync', target, payload)
        end
    end
end

local function gangCredit(row)
    if GetResourceState('cm-gang') ~= 'started' then return false, 'Gang services are unavailable.' end
    local operationId = tostring(row.credit_operation_id or '')
    if operationId == '' then return false, 'Cargo credit operation is incomplete.' end
    local ok, applied, reason = pcall(function()
        return exports['cm-gang']:AddGangArmoryStock(row.extracted_gang_id, row.item_name,
            tonumber(row.quantity) or 0, { operationId = operationId, orderId = row.order_id, cargoId = row.id })
    end)
    if not ok or applied ~= true then return false, tostring(reason or 'Gang armory credit failed safely.') end
    local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo
        SET credit_state='credited',credited_at=NOW()
        WHERE id=? AND state='extracted' AND credit_state='pending']], { row.id })
    return tonumber(changed) == 1, reason
end

lib.callback.register('cm-law:server:logistics', function(src)
    if not LogisticsReady then return { ok = false, error = 'Logistics is still starting.' } end
    local actor, _, reason = actorFor(src, nil, false)
    if not actor then return { ok = false, error = reason } end
    return {
        ok = true, items = requestablePayload(), orders = visibleOrders(actor),
        canRequest = logisticsPermission(actor, 'request'),
    }
end)

lib.callback.register('cm-law:server:logisticsCreate', function(src, rawLines)
    if not LogisticsReady then return { ok = false, error = 'Logistics is still starting.' } end
    if not rateLimit(src, 'law_logistics_request', L.RequestCooldownMs or 1500) then return { ok = false, error = 'Please wait.' } end
    local actor, actorCid, reason = actorFor(src, 'request', true)
    if not actor then return { ok = false, error = reason } end
    if not nearFacility(src, actor.organizationId, L.SourceFacilityType or 'armory') then
        return { ok = false, error = 'You must request supplies at your organization armory.' }
    end
    local receive = receivingPoint(actor.organizationId)
    if not receive then return { ok = false, error = 'Your organization has no configured receiving point.' } end
    if type(rawLines) ~= 'table' then return { ok = false, error = 'Choose at least one supply.' } end

    local allowed, merged, total, count = requestableMap(), {}, 0, 0
    for _, raw in ipairs(rawLines) do
        if type(raw) == 'table' then
            local itemName = normalizedName(raw.itemName)
            local item = itemName and allowed[itemName]
            local quantity = math.floor(tonumber(raw.quantity) or 0)
            if item and quantity > 0 then
                if quantity > item.maxQuantity then
                    return { ok = false, error = ('Quantity for %s exceeds the per-line limit.'):format(itemName) }
                end
                merged[itemName] = (merged[itemName] or 0) + quantity
            end
        end
    end
    for itemName, quantity in pairs(merged) do
        count = count + 1
        total = total + quantity
        if quantity > (allowed[itemName].maxQuantity or tonumber(L.MaxQuantityPerLine) or 1000) then
            return { ok = false, error = ('Quantity for %s exceeds the per-line limit.'):format(itemName) }
        end
    end
    if count < 1 then return { ok = false, error = 'Choose at least one valid supply.' } end
    if count > (tonumber(L.MaxLinesPerOrder) or 8) then return { ok = false, error = 'That order has too many line items.' } end
    if total > (tonumber(L.MaxTotalQuantity) or 5000) then return { ok = false, error = 'That order exceeds the total quantity limit.' } end
    local openCount = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_legal_logistics_orders
        WHERE requester_org = ? AND status IN ('requested','accepted','prepared','loaded','in_transit')]], { actor.organizationId })) or 0
    if openCount >= (tonumber(L.MaxOpenOrdersPerOrganization) or 3) then
        return { ok = false, error = 'Your organization already has the maximum number of open supply orders.' }
    end

    local requestKey = ('%s-%s-%08d'):format(actor.organizationId, tostring(actorCid):gsub('[^%w]', ''), math.random(0, 99999999))
    local lineStatements = {{
        query = [[INSERT INTO cm_legal_logistics_orders
            (request_key,requester_org,requester_cid,status,receiving_x,receiving_y,receiving_z,receiving_heading,receiving_bucket)
            VALUES (?, ?,?,'requested',?,?,?,?,?)]],
        values = { requestKey, actor.organizationId, actorCid, receive.x, receive.y, receive.z, receive.heading, receive.bucket },
    }}
    for itemName, quantity in pairs(merged) do
        lineStatements[#lineStatements + 1] = {
            query = [[INSERT INTO cm_legal_logistics_order_lines (order_id,item_name,quantity)
                SELECT id,?,? FROM cm_legal_logistics_orders WHERE request_key=? LIMIT 1]],
            values = { itemName, quantity, requestKey },
        }
    end
    if MySQL.transaction.await(lineStatements) ~= true then
        return { ok = false, error = 'Supply order lines failed safely; no order was created.' }
    end
    local orderId = tonumber(MySQL.scalar.await('SELECT id FROM cm_legal_logistics_orders WHERE request_key=? LIMIT 1', { requestKey }))
    if not orderId then return { ok = false, error = 'Could not create the supply order.' } end
    logOrder(actor.organizationId, actorCid, 'logistics_order_created', orderId, { lines = merged })
    TriggerEvent('cm-admin:server:addLog', src, 'legal_logistics_order_created', {
        category = 'orgs', organizationId = actor.organizationId, orderId = orderId,
    })
    return { ok = true, orderId = orderId, message = ('Supply order #%d submitted to Army.'):format(orderId) }
end)

local function acceptOrder(src, actor, actorCid, orderId)
    local header = orderHeader(orderId)
    if not header or tostring(header.status) ~= 'requested' then return false, 'That order is no longer awaiting Army acceptance.' end
    local rows = requireOrderLineRows(orderId)
    if #rows == 0 then return false, 'That order has no supply lines.' end
    local allowed = requestableMap()
    for _, row in ipairs(rows) do
        if not allowed[tostring(row.item_name):lower()] then return false, 'That order contains an item no longer on the allowlist.' end
    end
    local lockOk, operationOk, operationError = LawWithStockLock(stockKeys(rows), function()
        for _, row in ipairs(rows) do
            local stock = MySQL.single.await([[SELECT stock FROM cm_legal_armory_stock
                WHERE organization_id=? AND item_name=? AND enabled=1 LIMIT 1]],
                { SOURCE_ORG, row.item_name })
            if not stock or (tonumber(stock.stock) or 0) < (tonumber(row.quantity) or 0) then
                return false, ('Army does not have enough %s in stock.'):format(row.item_name)
            end
        end
        local statements = {}
        for _, row in ipairs(rows) do
            statements[#statements + 1] = {
                query = [[UPDATE cm_legal_armory_stock SET stock=stock-?
                    WHERE organization_id=? AND item_name=? AND enabled=1 AND stock>=?]],
                values = { row.quantity, SOURCE_ORG, row.item_name, row.quantity },
            }
            statements[#statements + 1] = {
                query = [[INSERT INTO cm_legal_logistics_ledger
                    (order_id,line_id,action,quantity,applied) VALUES (?,?, 'reserve',?,1)
                    ON DUPLICATE KEY UPDATE quantity=VALUES(quantity)]],
                values = { orderId, row.line_id, row.quantity },
            }
        end
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_logistics_orders SET status='accepted',accepted_by_cid=?,accepted_at=NOW()
                WHERE id=? AND status='requested']], values = { actorCid, orderId },
        }
        local committed = MySQL.transaction.await(statements)
        if committed ~= true then return false, 'Army stock reservation failed safely.' end
        return true
    end)
    if lockOk ~= true then return false, operationOk or 'Army stock is busy. Please try again.' end
    if operationOk ~= true then return false, operationError or 'Army stock reservation failed safely.' end
    logOrder(SOURCE_ORG, actorCid, 'logistics_order_accepted', orderId, { requesterOrg = header.requester_org })
    return true, ('Order #%d accepted and reserved from Army stock.'):format(orderId)
end

local function prepareOrder(src, actor, actorCid, orderId)
    local header = orderHeader(orderId)
    if not header or tostring(header.status) ~= 'accepted' then return false, 'That order is not ready for preparation.' end
    if header.shipment_plate then return false, 'That order already has a shipment vehicle.' end
    local source = LawFacilityLocation(SOURCE_ORG, L.SourceFacilityType or 'armory')
    if not source then return false, 'Army has no configured logistics source facility.' end
    local model = tostring(L.ShipmentVehicleModel or '')
    if model == '' then return false, 'No shipment vehicle model is configured.' end
    local rad = math.rad(source.heading or 0.0)
    local coords = { x = source.x - math.sin(rad) * 4.0, y = source.y + math.cos(rad) * 4.0, z = source.z + 0.5, h = source.heading }
    local spawned = exports['cm-vehicles']:SpawnAdminVehicle(src, model, coords, {
        access = 'owner', ownerCid = actorCid, warp = true, engineOn = true,
        placementKind = 'car', label = L.ShipmentVehicleLabel or 'Army Logistics Transport',
    })
    if type(spawned) ~= 'table' or spawned.ok ~= true or not spawned.plate then
        return false, tostring(spawned and spawned.error or 'Could not create the shipment vehicle.')
    end
    local changed = MySQL.update.await([[UPDATE cm_legal_logistics_orders
        SET status='prepared',shipment_plate=?,prepared_by_cid=?,prepared_at=NOW()
        WHERE id=? AND status='accepted' AND shipment_plate IS NULL]],
        { spawned.plate, actorCid, orderId })
    if tonumber(changed) ~= 1 then
        pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(spawned.plate) end)
        return false, 'The order changed before its shipment vehicle was assigned.'
    end
    if spawned.entity and DoesEntityExist(spawned.entity) then
        Entity(spawned.entity).state:set('cmLegalLogistics', { orderId = orderId, organizationId = SOURCE_ORG }, true)
    end
    logOrder(SOURCE_ORG, actorCid, 'logistics_order_prepared', orderId, { shipmentPlate = spawned.plate })
    return true, ('Shipment vehicle prepared for order #%d. Load it at Army logistics.'):format(orderId)
end

local function changeVehicleState(src, actorCid, orderId, expected, nextState, action)
    local header = orderHeader(orderId)
    if not header or tostring(header.status) ~= expected then return false, ('That order is not in %s state.'):format(expected) end
    if not header.shipment_plate then return false, 'That order has no shipment vehicle.' end
    local _, reason = currentShipmentVehicle(src, header.shipment_plate, orderId)
    if not _ then return false, reason end
    local changed = MySQL.update.await(('UPDATE cm_legal_logistics_orders SET status=?,%s=NOW() WHERE id=? AND status=?'):format(
        nextState == 'loaded' and 'loaded_at' or 'departed_at'), { nextState, orderId, expected })
    if tonumber(changed) ~= 1 then return false, 'The order changed before this action completed.' end
    logOrder(SOURCE_ORG, actorCid, action, orderId, { shipmentPlate = header.shipment_plate })
    return true, nextState == 'loaded' and 'Shipment loaded. Depart when ready.' or 'Shipment is now in transit.'
end

local function transferOrder(src, actor, actorCid, orderId)
    local header = orderHeader(orderId)
    if header and tostring(header.status) == 'delivered' then return true, ('Order #%d was already delivered.'):format(orderId) end
    if not header or tostring(header.status) ~= 'in_transit' then return false, 'That order is not in transit.' end
    if not nearPoint(src, { x = tonumber(header.receiving_x), y = tonumber(header.receiving_y),
        z = tonumber(header.receiving_z), bucket = tonumber(header.receiving_bucket) or 0 }, L.DeliveryRadius or 15.0) then
        return false, 'Drive the shipment to the configured receiving point.'
    end
    local vehicle, reason = currentShipmentVehicle(src, header.shipment_plate, orderId)
    if not vehicle then return false, reason end
    local rows = requireOrderLineRows(orderId)
    if #rows == 0 then return false, 'That order has no supply lines.' end
    local cargo = cargoRows(orderId)
    local lockOk, operationOk, operationError = LawWithStockLock(stockKeys(rows, tostring(header.requester_org)), function()
        local statements = {}
        if #cargo > 0 then
            -- Once the convoy has been breached, only crates that are still
            -- available at the convoy or have been dropped are delivered.
            -- Carried, extracted, expired, and recovered crates are never
            -- silently recreated as requester stock.
            for _, crate in ipairs(cargo) do
                if tostring(crate.state) == 'available' or tostring(crate.state) == 'dropped' then
                    local item = realItem(crate.item_name) or {}
                    statements[#statements + 1] = {
                        query = [[INSERT INTO cm_legal_armory_stock
                            (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                            VALUES (?,?,1,0,?,?,0,?)
                            ON DUPLICATE KEY UPDATE item_name=VALUES(item_name)]],
                        values = { header.requester_org, crate.item_name,
                            math.max(tonumber(L.DefaultReceivingMaxStock) or 10000, tonumber(crate.quantity) or 0),
                            item.itemType == 'ammo' and 1 or 1, actorCid },
                    }
                    statements[#statements + 1] = {
                        query = [[INSERT IGNORE INTO cm_legal_logistics_ledger
                            (order_id,line_id,action,quantity,applied) VALUES (?,?, 'transfer',?,0)]],
                        values = { orderId, crate.id, crate.quantity },
                    }
                    statements[#statements + 1] = {
                        query = [[UPDATE cm_legal_armory_stock s SET stock=stock+?
                            WHERE s.organization_id=? AND s.item_name=? AND EXISTS
                            (SELECT 1 FROM cm_legal_logistics_ledger t WHERE t.order_id=? AND t.line_id=?
                                AND t.action='transfer' AND t.applied=0)]],
                        values = { crate.quantity, header.requester_org, crate.item_name, orderId, crate.id },
                    }
                    statements[#statements + 1] = {
                        query = [[UPDATE cm_legal_logistics_ledger SET applied=1
                            WHERE order_id=? AND line_id=? AND action='transfer' AND applied=0]],
                        values = { orderId, crate.id },
                    }
                    statements[#statements + 1] = {
                        query = "UPDATE cm_legal_logistics_cargo SET state='delivered' WHERE id=? AND state IN ('available','dropped')",
                        values = { crate.id },
                    }
                end
            end
        end
        if #cargo > 0 then
            statements[#statements + 1] = {
                query = [[UPDATE cm_legal_logistics_orders SET status='delivered',
                    robbery_state='delivered',delivered_at=NOW(),shipment_plate=NULL
                    WHERE id=? AND status='in_transit']], values = { orderId },
            }
        else
        for _, row in ipairs(rows) do
            local item = realItem(row.item_name) or {}
            statements[#statements + 1] = {
                query = [[INSERT INTO cm_legal_armory_stock
                    (organization_id,item_name,enabled,stock,max_stock,issue_amount,min_tier,updated_by)
                    VALUES (?,?,1,0,?,?,0,?)
                    ON DUPLICATE KEY UPDATE item_name=VALUES(item_name)]],
                values = { header.requester_org, row.item_name, math.max(tonumber(L.DefaultReceivingMaxStock) or 10000, tonumber(row.quantity) or 0),
                    item.itemType == 'ammo' and 1 or 1, actorCid },
            }
            statements[#statements + 1] = {
                query = [[INSERT IGNORE INTO cm_legal_logistics_ledger
                    (order_id,line_id,action,quantity,applied) VALUES (?,?, 'transfer',?,0)]],
                values = { orderId, row.line_id, row.quantity },
            }
            statements[#statements + 1] = {
                query = [[UPDATE cm_legal_armory_stock s SET stock=stock+?
                    WHERE s.organization_id=? AND s.item_name=? AND EXISTS
                    (SELECT 1 FROM cm_legal_logistics_ledger t WHERE t.order_id=? AND t.line_id=?
                        AND t.action='transfer' AND t.applied=0)]],
                values = { row.quantity, header.requester_org, row.item_name, orderId, row.line_id },
            }
            statements[#statements + 1] = {
                query = [[UPDATE cm_legal_logistics_ledger SET applied=1
                    WHERE order_id=? AND line_id=? AND action='transfer' AND applied=0]],
                values = { orderId, row.line_id },
            }
        end
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_logistics_orders SET status='delivered',delivered_at=NOW(),shipment_plate=NULL
                WHERE id=? AND status='in_transit']], values = { orderId },
        }
        end
        local committed = MySQL.transaction.await(statements)
        if committed ~= true then return false, 'Supply transfer failed safely.' end
        return true
    end)
    if lockOk ~= true then return false, operationOk or 'Stock is busy. Please try again.' end
    if operationOk ~= true then return false, operationError or 'Supply transfer failed safely.' end
    pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(header.shipment_plate) end)
    for _, crate in ipairs(cargo) do
        if tostring(crate.state) == 'available' or tostring(crate.state) == 'dropped' then
            sendCargoNearby(crate, 'removed')
        end
    end
    logOrder(SOURCE_ORG, actorCid, 'logistics_order_delivered', orderId, { requesterOrg = header.requester_org })
    return true, ('Order #%d delivered and transferred atomically.'):format(orderId)
end

local function cancelOrder(actor, actorCid, orderId)
    local header = orderHeader(orderId)
    if not header then return false, 'That order does not exist.' end
    local status = tostring(header.status)
    local isArmy = actor.organizationId == SOURCE_ORG
    if not isArmy and tostring(header.requester_org) ~= actor.organizationId then return false, 'You cannot cancel that order.' end
    if status == 'cancelled' then return true, 'That order is already cancelled.' end
    if status == 'delivered' then return false, 'Delivered orders cannot be cancelled.' end
    if status == 'wrecked' or tostring(header.robbery_state or 'eligible') ~= 'eligible' then
        return false, 'A convoy that has entered robbery handling cannot be cancelled.'
    end
    if not isArmy and status ~= 'requested' then return false, 'Only requested orders can be cancelled by the requester.' end
    local rows = requireOrderLineRows(orderId)
    local lockOk, operationOk, operationError = LawWithStockLock(stockKeys(rows), function()
        local statements = {}
        if isArmy and status ~= 'requested' then
            for _, row in ipairs(rows) do
                statements[#statements + 1] = {
                    query = [[INSERT IGNORE INTO cm_legal_logistics_ledger
                        (order_id,line_id,action,quantity,applied) VALUES (?,?, 'release',?,0)]],
                    values = { orderId, row.line_id, row.quantity },
                }
                statements[#statements + 1] = {
                    query = [[UPDATE cm_legal_armory_stock s SET stock=stock+?
                        WHERE s.organization_id=? AND s.item_name=? AND EXISTS
                        (SELECT 1 FROM cm_legal_logistics_ledger t WHERE t.order_id=? AND t.line_id=?
                            AND t.action='release' AND t.applied=0)]],
                    values = { row.quantity, SOURCE_ORG, row.item_name, orderId, row.line_id },
                }
                statements[#statements + 1] = {
                    query = [[UPDATE cm_legal_logistics_ledger SET applied=1
                        WHERE order_id=? AND line_id=? AND action='release' AND applied=0]],
                    values = { orderId, row.line_id },
                }
            end
        end
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_logistics_orders SET status='cancelled',cancelled_at=NOW(),
                reservation_released=? WHERE id=? AND status=?]],
            values = { isArmy and status ~= 'requested' and 1 or 0, orderId, status },
        }
        local committed = MySQL.transaction.await(statements)
        if committed ~= true then return false, 'Cancellation failed safely.' end
        return true
    end)
    if lockOk ~= true then return false, operationOk or 'Stock is busy. Please try again.' end
    if operationOk ~= true then return false, operationError or 'Cancellation failed safely.' end
    if header.shipment_plate then pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(header.shipment_plate) end) end
    logOrder(actor.organizationId, actorCid, 'logistics_order_cancelled', orderId, { previousStatus = status })
    return true, ('Order #%d cancelled; any Army reservation was returned.'):format(orderId)
end

local function recoverOrder(actorCid, orderId)
    local header = orderHeader(orderId)
    if not header or not ({ prepared = true, loaded = true, in_transit = true })[tostring(header.status)] then
        return false, 'That order is not an interrupted shipment.'
    end
    local plate = header.shipment_plate
    if plate then pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(plate) end) end
    local changed = MySQL.update.await([[UPDATE cm_legal_logistics_orders SET status='accepted',
        shipment_plate=NULL,prepared_by_cid=NULL,prepared_at=NULL,loaded_at=NULL,departed_at=NULL
        WHERE id=? AND status IN ('prepared','loaded','in_transit')]], { orderId })
    if tonumber(changed) ~= 1 then return false, 'That order changed before recovery completed.' end
    logOrder(SOURCE_ORG, actorCid, 'logistics_order_recovered', orderId, {})
    return true, ('Order #%d recovered to accepted state.'):format(orderId)
end

local function wreckOrder(orderId, header, vehicle)
    if not header or tostring(header.status) ~= 'in_transit' then return false end
    local rows = requireOrderLineRows(orderId)
    if #rows == 0 then return false end
    local coords = GetEntityCoords(vehicle)
    local bucket = GetEntityRoutingBucket(vehicle)
    local expiresAt = os.time() + (tonumber(R.CargoExpirySeconds) or 1800)
    local statements = {}
    for _, row in ipairs(rows) do
        statements[#statements + 1] = {
            query = [[INSERT IGNORE INTO cm_legal_logistics_cargo
                (order_id,line_id,item_name,quantity,state,x,y,z,bucket,expires_at)
                VALUES (?,?,?,?, 'wrecked',?,?,?,?,FROM_UNIXTIME(?))]],
            values = { orderId, row.line_id, row.item_name, row.quantity,
                coords.x, coords.y, coords.z, bucket, expiresAt },
        }
    end
    -- Only cargo still at the vehicle becomes wreck cargo.  A dropped or
    -- carried crate is already outside the vehicle and must remain recoverable
    -- by its own persisted state.
    statements[#statements + 1] = {
        query = [[UPDATE cm_legal_logistics_cargo SET state='wrecked',
            x=?,y=?,z=?,bucket=?,expires_at=FROM_UNIXTIME(?)
            WHERE order_id=? AND state='available']],
        values = { coords.x, coords.y, coords.z, bucket, expiresAt, orderId },
    }
    statements[#statements + 1] = {
        query = [[UPDATE cm_legal_logistics_orders SET status='wrecked',
            robbery_state='wrecked',wreck_x=?,wreck_y=?,wreck_z=?,wreck_bucket=?,
            wreck_expires_at=FROM_UNIXTIME(?),shipment_plate=NULL
            WHERE id=? AND status='in_transit']],
        values = { coords.x, coords.y, coords.z, bucket, expiresAt, orderId },
    }
    if MySQL.transaction.await(statements) ~= true then return false end
    pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(header.shipment_plate) end)
    logOrder(SOURCE_ORG, nil, 'logistics_convoy_wrecked', orderId, {
        x = coords.x, y = coords.y, z = coords.z,
    })
    for _, row in ipairs(cargoRows(orderId, { 'wrecked', 'dropped', 'carried' })) do sendCargoNearby(row) end
    return true
end

local function wreckMissingOrder(orderId, header)
    if not header or tostring(header.status) ~= 'in_transit'
        or tostring(header.robbery_state or 'eligible') ~= 'breached' then return false end
    local cargo = cargoRows(orderId, { 'available', 'dropped', 'carried' })
    local position = cargo[1]
    local expiresAt = os.time() + (tonumber(R.CargoExpirySeconds) or 1800)
    local statements = {}
    if position and position.state == 'available' then
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_logistics_cargo SET state='wrecked',
                expires_at=FROM_UNIXTIME(?) WHERE order_id=? AND state='available']],
            values = { expiresAt, orderId },
        }
    end
    statements[#statements + 1] = {
        query = [[UPDATE cm_legal_logistics_orders SET status='wrecked',
            robbery_state='wrecked',wreck_x=?,wreck_y=?,wreck_z=?,wreck_bucket=?,
            wreck_expires_at=FROM_UNIXTIME(?),shipment_plate=NULL
            WHERE id=? AND status='in_transit']],
        values = {
            position and position.x or nil, position and position.y or nil, position and position.z or nil,
            position and position.bucket or 0, expiresAt, orderId,
        },
    }
    if MySQL.transaction.await(statements) ~= true then return false end
    logOrder(SOURCE_ORG, nil, 'logistics_convoy_wrecked', orderId, { recoveredAfterMissingVehicle = true })
    for _, row in ipairs(cargoRows(orderId, { 'wrecked', 'dropped', 'carried' })) do sendCargoNearby(row) end
    return true
end

local function extractionPoint(src, gangId)
    local configured = R.ExtractionPoints or {}
    if type(configured[gangId]) == 'table' then configured = configured[gangId] end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    for _, point in ipairs(configured) do
        if type(point) == 'table' and tonumber(point.x) and tonumber(point.y) and tonumber(point.z)
            and GetPlayerRoutingBucket(src) == (tonumber(point.bucket or point.routing_bucket) or 0)
            and #(coords - vector3(point.x, point.y, point.z)) <= (tonumber(R.ExtractionRadius) or 4.0) then
            return point
        end
    end
    return nil
end

local function recoverWreckOrder(actorSrc, actorCid, orderId)
    local header = orderHeader(orderId)
    if not header or tostring(header.status) ~= 'wrecked' then
        return false, 'That order has no recoverable wreck.'
    end
    if not tonumber(header.wreck_x) or not tonumber(header.wreck_y) or not tonumber(header.wreck_z) then
        return false, 'The wreck location is unavailable; recovery is blocked safely.'
    end
    if not nearPoint(actorSrc, {
        x = tonumber(header.wreck_x), y = tonumber(header.wreck_y), z = tonumber(header.wreck_z),
        bucket = tonumber(header.wreck_bucket) or 0,
    }, tonumber(R.RecoveryRadius) or 6.0) then
        return false, 'Stand at the shipment wreck to recover it.'
    end
    local cargo = cargoRows(orderId, { 'wrecked' })
    local rows = requireOrderLineRows(orderId)
    local lockOk, operationOk, operationError = LawWithStockLock(stockKeys(rows), function()
        local statements = {}
        for _, crate in ipairs(cargo) do
            statements[#statements + 1] = {
                query = [[INSERT IGNORE INTO cm_legal_logistics_ledger
                    (order_id,line_id,action,quantity,applied) VALUES (?,?, 'wreck_release',?,0)]],
                values = { orderId, crate.line_id, crate.quantity },
            }
            statements[#statements + 1] = {
                query = [[UPDATE cm_legal_armory_stock s SET stock=stock+?
                    WHERE s.organization_id=? AND s.item_name=? AND EXISTS
                    (SELECT 1 FROM cm_legal_logistics_ledger t WHERE t.order_id=? AND t.line_id=?
                        AND t.action='wreck_release' AND t.applied=0)]],
                values = { crate.quantity, SOURCE_ORG, crate.item_name, orderId, crate.id },
            }
            statements[#statements + 1] = {
                query = [[UPDATE cm_legal_logistics_ledger SET applied=1
                    WHERE order_id=? AND line_id=? AND action='wreck_release' AND applied=0]],
                values = { orderId, crate.id },
            }
            statements[#statements + 1] = {
                query = "UPDATE cm_legal_logistics_cargo SET state='recovered' WHERE id=? AND state='wrecked'",
                values = { crate.id },
            }
        end
        statements[#statements + 1] = {
            query = [[UPDATE cm_legal_logistics_orders SET status='recovered',robbery_state='recovered',
                reservation_released=1 WHERE id=? AND status='wrecked']], values = { orderId },
        }
        if MySQL.transaction.await(statements) ~= true then return false, 'Wreck recovery failed safely.' end
        return true
    end)
    if lockOk ~= true then return false, operationOk or 'Army stock is busy. Please try again.' end
    if operationOk ~= true then return false, operationError or 'Wreck recovery failed safely.' end
    logOrder(SOURCE_ORG, actorCid, 'logistics_convoy_wreck_recovered', orderId, {})
    for _, row in ipairs(cargoRows(orderId, { 'recovered' })) do sendCargoNearby(row, 'removed') end
    return true, ('Order #%d wreck cargo recovered to Army stock.'):format(orderId)
end

local function robberyAction(src, action, orderId, vehicleNetId, cargoId)
    if R.Enabled ~= true then return false, 'Convoy robbery is disabled.' end
    orderId, cargoId = tonumber(orderId), tonumber(cargoId)
    if not orderId then return false, 'Invalid shipment order.' end
    local gang, reason = gangContext(src)
    if not gang then return false, reason end
    if not sourceAlive(src) then return false, 'You must be alive to handle convoy cargo.' end
    local header = orderHeader(orderId)
    if not header then return false, 'That shipment order does not exist.' end
    return withOrderLock(orderId, function()
        if action == 'breach_start' then
            if tostring(header.status) ~= 'in_transit' then return false, 'That convoy is not in transit.' end
            if tostring(header.robbery_state or 'eligible') ~= 'eligible' then
                return true, 'That convoy has already been breached.'
            end
            local vehicle, vehicleReason = vehicleForOrder(orderId, header)
            if not vehicle then return false, vehicleReason end
            if not vehicleNetId or tonumber(vehicleNetId) ~= NetworkGetNetworkIdFromEntity(vehicle) then
                return false, 'That is not the shipment vehicle for this order.'
            end
            if not vehicleStopped(vehicle) then return false, 'The shipment must be stopped before it can be breached.' end
            if not nearConvoyRear(src, vehicle) then return false, 'Move to the rear of the stopped shipment.' end
            local changed = MySQL.update.await([[UPDATE cm_legal_logistics_orders SET robbery_state='breaching',
                breach_by_cid=?,breach_started_at=NOW()
                WHERE id=? AND status='in_transit' AND robbery_state='eligible']], { gang.characterId, orderId })
            if tonumber(changed) ~= 1 then return false, 'That convoy is already being breached.' end
            logOrder(SOURCE_ORG, nil, 'logistics_convoy_breach_started', orderId, {})
            return true, 'Cargo breach started.'
        end

        if action == 'breach_cancel' then
            local changed = MySQL.update.await([[UPDATE cm_legal_logistics_orders SET robbery_state='eligible',
                breach_by_cid=NULL,breach_started_at=NULL
                WHERE id=? AND status='in_transit' AND robbery_state='breaching' AND breach_by_cid=?]],
                { orderId, gang.characterId })
            return tonumber(changed) == 1, tonumber(changed) == 1 and 'Cargo breach cancelled.' or 'The breach is no longer active.'
        end

        if action == 'breach_complete' then
            if tostring(header.status) ~= 'in_transit' or tostring(header.robbery_state or '') ~= 'breaching'
                or tostring(header.breach_by_cid or '') ~= gang.characterId then
                return false, 'The cargo breach is no longer active.'
            end
            local vehicle, vehicleReason = vehicleForOrder(orderId, header)
            if not vehicle then return false, vehicleReason end
            if not vehicleNetId or tonumber(vehicleNetId) ~= NetworkGetNetworkIdFromEntity(vehicle)
                or not vehicleStopped(vehicle) or not nearConvoyRear(src, vehicle) then
                MySQL.update.await("UPDATE cm_legal_logistics_orders SET robbery_state='eligible',breach_by_cid=NULL,breach_started_at=NULL WHERE id=? AND robbery_state='breaching'", { orderId })
                return false, 'The shipment moved before the breach completed.'
            end
            local coords, bucket = GetEntityCoords(vehicle), GetEntityRoutingBucket(vehicle)
            local rows = requireOrderLineRows(orderId)
            local statements = {{
                query = [[UPDATE cm_legal_logistics_orders SET robbery_state='breached',
                    breach_by_cid=NULL,breach_started_at=NULL
                    WHERE id=? AND status='in_transit' AND robbery_state='breaching' AND breach_by_cid=?]],
                values = { orderId, gang.characterId },
            }}
            for _, row in ipairs(rows) do
                local left, unitIndex, unitSize = tonumber(row.quantity) or 0, 0, cargoUnitSize(row.item_name, row.quantity)
                while left > 0 do
                    unitIndex = unitIndex + 1
                    local amount = math.min(left, unitSize)
                    statements[#statements + 1] = {
                        query = [[INSERT INTO cm_legal_logistics_cargo
                            (order_id,line_id,unit_index,item_name,quantity,state,x,y,z,bucket)
                            VALUES (?,?,?,?,?,'available',?,?,?,?,?)]],
                        values = { orderId, row.line_id, unitIndex, row.item_name, amount,
                            coords.x, coords.y, coords.z, bucket },
                    }
                    left = left - amount
                end
            end
            if MySQL.transaction.await(statements) ~= true then return false, 'Convoy breach failed safely.' end
            notifyShipmentAttack(header)
            logOrder(SOURCE_ORG, nil, 'logistics_convoy_breached', orderId, {})
            return true, 'The convoy is breached. Take a cargo crate from the rear.'
        end

        if action == 'claim' then
            local carrierLockOk, claimResult, claimMessage = withCarrierLock(gang.characterId, function()
                if not cargoId then return false, 'Choose a cargo crate.' end
                local existing = MySQL.scalar.await([[SELECT id FROM cm_legal_logistics_cargo
                    WHERE carrier_cid=? AND state='carried' LIMIT 1]], { gang.characterId })
                if existing then return false, 'You are already carrying a cargo crate.' end
                local crate = MySQL.single.await('SELECT * FROM cm_legal_logistics_cargo WHERE id=? AND order_id=? LIMIT 1',
                    { cargoId, orderId })
                if not crate or (crate.state ~= 'available' and crate.state ~= 'dropped' and crate.state ~= 'wrecked') then
                    return false, 'That cargo crate is no longer available.'
                end
                local validPosition = false
                if crate.state == 'available' then
                    if tostring(header.status) ~= 'in_transit' then return false, 'The convoy is no longer active.' end
                    local vehicle, vehicleReason = vehicleForOrder(orderId, header)
                    if not vehicle then return false, vehicleReason end
                    if not vehicleNetId or tonumber(vehicleNetId) ~= NetworkGetNetworkIdFromEntity(vehicle)
                        or not vehicleStopped(vehicle) or not nearConvoyRear(src, vehicle) then
                        return false, 'Move to the stopped shipment rear.'
                    end
                    validPosition = true
                else
                    validPosition = nearPoint(src, {
                        x = tonumber(crate.x), y = tonumber(crate.y), z = tonumber(crate.z),
                        bucket = tonumber(crate.bucket) or 0,
                    }, tonumber(R.InteractionDistance) or 2.5)
                end
                if not validPosition then return false, 'Move closer to the cargo crate.' end
                local coords = GetEntityCoords(GetPlayerPed(src))
                local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo
                    SET state='carried',carrier_cid=?,carrier_source=?,x=?,y=?,z=?,bucket=?,expires_at=NULL
                    WHERE id=? AND order_id=? AND state IN ('available','dropped','wrecked')
                        AND (expires_at IS NULL OR expires_at>NOW())]], {
                        gang.characterId, tonumber(src), coords.x, coords.y, coords.z,
                        GetPlayerRoutingBucket(src), cargoId, orderId,
                    })
                if tonumber(changed) ~= 1 then return false, 'That crate was taken before you reached it.' end
                local updated = MySQL.single.await('SELECT * FROM cm_legal_logistics_cargo WHERE id=?', { cargoId })
                sendCargoNearby(updated)
                return true, 'Cargo secured. Take it to a configured extraction point.'
            end)
            if carrierLockOk ~= true then return false, claimResult end
            return claimResult, claimMessage
        end

        if action == 'drop' then
            if not cargoId then return false, 'Choose a cargo crate.' end
            local crate = MySQL.single.await([[SELECT * FROM cm_legal_logistics_cargo
                WHERE id=? AND order_id=? AND state='carried' AND carrier_cid=? LIMIT 1]],
                { cargoId, orderId, gang.characterId })
            if not crate or tonumber(crate.carrier_source) ~= tonumber(src) then return false, 'You are not carrying that crate.' end
            local coords = GetEntityCoords(GetPlayerPed(src))
            local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo SET state='dropped',
                carrier_cid=NULL,carrier_source=NULL,x=?,y=?,z=?,bucket=?,expires_at=FROM_UNIXTIME(?)
                WHERE id=? AND state='carried' AND carrier_cid=? AND carrier_source=?]], {
                coords.x, coords.y, coords.z, GetPlayerRoutingBucket(src),
                os.time() + (tonumber(R.DroppedExpirySeconds) or 1800), cargoId, gang.characterId, tonumber(src),
            })
            if tonumber(changed) ~= 1 then return false, 'Cargo drop failed safely.' end
            local updated = MySQL.single.await('SELECT * FROM cm_legal_logistics_cargo WHERE id=?', { cargoId })
            sendCargoNearby(updated)
            return true, 'Cargo crate dropped.'
        end

        if action == 'heartbeat' then
            if not cargoId then return false, 'Choose a cargo crate.' end
            local coords = GetEntityCoords(GetPlayerPed(src))
            local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo SET x=?,y=?,z=?,bucket=?
                WHERE id=? AND state='carried' AND carrier_cid=? AND carrier_source=?]], {
                coords.x, coords.y, coords.z, GetPlayerRoutingBucket(src), cargoId, gang.characterId, tonumber(src),
            })
            return tonumber(changed) == 1, tonumber(changed) == 1 and nil or 'You are not carrying that crate.'
        end

        if action == 'extract' then
            if not cargoId then return false, 'Choose a cargo crate.' end
            if not extractionPoint(src, gang.gangId) then return false, 'This is not a configured cargo extraction point.' end
            local crate = MySQL.single.await([[SELECT * FROM cm_legal_logistics_cargo
                WHERE id=? AND order_id=? AND state='carried' AND carrier_cid=? AND carrier_source=? LIMIT 1]],
                { cargoId, orderId, gang.characterId, tonumber(src) })
            if not crate then return false, 'You are not carrying that crate.' end
            local operationId = ('convoy:%d:cargo:%d:%s'):format(orderId, cargoId, gang.gangId)
            local extractionStatements = {
                { query = [[UPDATE cm_legal_logistics_cargo SET state='extracted',
                    carrier_cid=NULL,carrier_source=NULL,extracted_gang_id=?,credit_state='pending',
                    credit_operation_id=?,extracted_at=NOW() WHERE id=? AND state='carried'
                    AND carrier_cid=? AND carrier_source=?]],
                  values = { gang.gangId, operationId, cargoId, gang.characterId, tonumber(src) } },
                { query = [[INSERT IGNORE INTO cm_legal_logistics_ledger
                    (order_id,line_id,action,quantity,applied) VALUES (?,?, 'convoy_extract',?,1)]],
                  values = { orderId, crate.id, crate.quantity } },
            }
            if MySQL.transaction.await(extractionStatements) ~= true then
                return false, 'Cargo extraction failed safely.'
            end
            local extracted = MySQL.single.await('SELECT * FROM cm_legal_logistics_cargo WHERE id=?', { cargoId })
            local credited, creditReason = gangCredit(extracted)
            sendCargoNearby(extracted, 'removed')
            logOrder(SOURCE_ORG, nil, 'logistics_convoy_cargo_extracted', orderId, {
                cargoId = cargoId, credited = credited == true,
            })
            if not credited then
                return true, 'Cargo extracted; gang armory credit is pending recovery.'
            end
            return true, 'Cargo extracted and credited to your gang armory.'
        end
        return false, 'Unknown convoy cargo action.'
    end)
end

lib.callback.register('cm-law:server:logisticsCargoNearby', function(src, orderId, vehicleNetId)
    if not LogisticsReady or not R.Enabled then return {} end
    local gang = gangContext(src)
    if not gang then return { eligible = false, crates = {} } end
    local header = orderHeader(orderId)
    if not header or tostring(header.status) ~= 'in_transit' then return { eligible = false, crates = {} } end
    local vehicle = vehicleForOrder(orderId, header)
    if not vehicle or tonumber(vehicleNetId) ~= NetworkGetNetworkIdFromEntity(vehicle)
        or not nearConvoyRear(src, vehicle) then return { eligible = false, crates = {} } end
    local result = {}
    for _, row in ipairs(cargoRows(orderId, { 'available' })) do result[#result + 1] = cargoPayload(row) end
    return { eligible = tostring(header.robbery_state or 'eligible') == 'eligible' or #result > 0, crates = result }
end)

lib.callback.register('cm-law:server:logisticsRobbery', function(src, action, orderId, vehicleNetId, cargoId)
    if not LogisticsReady then return { ok = false, error = 'Logistics is still starting.' } end
    action = tostring(action or '')
    if not rateLimit(src, 'law_logistics_robbery_' .. action, action == 'heartbeat' and 1800 or 700) then
        return { ok = false, error = 'Please wait.' }
    end
    local lockOk, result, message = robberyAction(src, action, orderId, vehicleNetId, cargoId)
    if lockOk ~= true then return { ok = false, error = result or 'Cargo operation is busy.' } end
    if result ~= true then return { ok = false, error = message or 'Cargo operation failed safely.' } end
    return { ok = true, message = message }
end)

local function reconcileCargo()
    if not LogisticsReady then return end
    local now = os.time()
    MySQL.update.await([[UPDATE cm_legal_logistics_orders SET robbery_state='eligible',
        breach_by_cid=NULL,breach_started_at=NULL
        WHERE status='in_transit' AND robbery_state='breaching'
        AND breach_started_at IS NOT NULL AND breach_started_at < FROM_UNIXTIME(?)]],
        { now - math.max(60, (tonumber(R.BreachSeconds) or 20) * 3) })
    local expired = MySQL.query.await([[SELECT * FROM cm_legal_logistics_cargo
        WHERE state IN ('dropped','wrecked') AND expires_at IS NOT NULL AND expires_at<=NOW()]]) or {}
    for _, row in ipairs(expired) do
        local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo SET state='expired',
            carrier_cid=NULL,carrier_source=NULL WHERE id=? AND state IN ('dropped','wrecked')
            AND expires_at IS NOT NULL AND expires_at<=NOW()]], { row.id })
        if tonumber(changed) == 1 then sendCargoNearby(row, 'removed') end
    end

    for _, row in ipairs(MySQL.query.await([[SELECT * FROM cm_legal_logistics_cargo
        WHERE state='extracted' AND credit_state='pending' ORDER BY id LIMIT 50]]) or {}) do
        local credited = gangCredit(row)
        if not credited then
            -- Keep the row pending.  The operation ID is the idempotency
            -- boundary shared with cm-gang, so retrying cannot double stock.
        end
    end

    local carried = MySQL.query.await([[SELECT * FROM cm_legal_logistics_cargo WHERE state='carried']]) or {}
    for _, row in ipairs(carried) do
        local src = tonumber(row.carrier_source)
        if not src or not GetPlayerName(src) or not sourceAlive(src) then
            local x, y, z, bucket = tonumber(row.x), tonumber(row.y), tonumber(row.z), tonumber(row.bucket) or 0
            local ped = src and GetPlayerPed(src) or 0
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                x, y, z, bucket = coords.x, coords.y, coords.z, GetPlayerRoutingBucket(src)
            end
            local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo SET state='dropped',
                carrier_cid=NULL,carrier_source=NULL,x=?,y=?,z=?,bucket=?,expires_at=FROM_UNIXTIME(?)
                WHERE id=? AND state='carried']], {
                x, y, z, bucket, now + (tonumber(R.DroppedExpirySeconds) or 1800), row.id,
            })
            if tonumber(changed) == 1 then
                local updated = MySQL.single.await('SELECT * FROM cm_legal_logistics_cargo WHERE id=?', { row.id })
                sendCargoNearby(updated)
            end
        end
    end

    for _, row in ipairs(MySQL.query.await([[SELECT id,shipment_plate,status FROM cm_legal_logistics_orders
        WHERE status='in_transit' AND shipment_plate IS NOT NULL]]) or {}) do
        local header = orderHeader(row.id)
        local vehicle = header and select(1, vehicleForOrder(row.id, header)) or nil
        if vehicle then missingConvoys[row.id] = nil end
        if vehicle and (GetVehicleEngineHealth(vehicle) <= 0.0 or GetEntityHealth(vehicle) <= 0) then
            local lockOk = withOrderLock(row.id, function()
                local current = orderHeader(row.id)
                return wreckOrder(row.id, current, vehicle)
            end)
            if lockOk ~= true then
                print(('[cm-law] convoy wreck reconciliation deferred for order #%s'):format(tostring(row.id)))
            end
        elseif not vehicle and header and tostring(header.robbery_state or 'eligible') == 'breached' then
            local nowTick = GetGameTimer()
            missingConvoys[row.id] = missingConvoys[row.id] or nowTick
            if nowTick - missingConvoys[row.id] >= 10000 then
                withOrderLock(row.id, function()
                    local current = orderHeader(row.id)
                    return wreckMissingOrder(row.id, current)
                end)
                missingConvoys[row.id] = nil
            end
        end
    end

    -- Targeted visual resync lets a player who walks into a dropped/wreck
    -- location (or joins after the drop) discover the persisted crate without
    -- broadcasting convoy or route coordinates server-wide.
    for _, row in ipairs(MySQL.query.await([[SELECT * FROM cm_legal_logistics_cargo
        WHERE state IN ('dropped','wrecked','carried')]]) or {}) do
        sendCargoNearby(row)
    end
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    local rows = MySQL.query.await([[SELECT * FROM cm_legal_logistics_cargo
        WHERE state='carried' AND carrier_source=?]], { src }) or {}
    local ped = GetPlayerPed(src)
    local coords = ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityCoords(ped) or nil
    for _, row in ipairs(rows) do
        local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
        if coords then x, y, z = coords.x, coords.y, coords.z end
        local changed = MySQL.update.await([[UPDATE cm_legal_logistics_cargo SET state='dropped',
            carrier_cid=NULL,carrier_source=NULL,x=?,y=?,z=?,expires_at=FROM_UNIXTIME(?)
            WHERE id=? AND state='carried' AND carrier_source=?]], {
            x, y, z, os.time() + (tonumber(R.DroppedExpirySeconds) or 1800), row.id, src,
        })
        if tonumber(changed) == 1 then
            local updated = MySQL.single.await('SELECT * FROM cm_legal_logistics_cargo WHERE id=?', { row.id })
            sendCargoNearby(updated)
        end
    end
end)

lib.callback.register('cm-law:server:logisticsAction', function(src, action, orderId)
    action, orderId = tostring(action or ''), tonumber(orderId)
    if not LogisticsReady then return { ok = false, error = 'Logistics is still starting.' } end
    if not orderId or not rateLimit(src, 'law_logistics_' .. action, 800) then return { ok = false, error = 'Please wait.' } end
    local actor, actorCid, reason = actorFor(src, nil, true)
    if not actor then return { ok = false, error = reason } end
    local allowed = {
        accept = 'accept', prepare = 'prepare', load = 'load', depart = 'load',
        deliver = 'deliver', cancel = 'cancel', recover = 'recover',
    }
    if not allowed[action] or not logisticsPermission(actor, allowed[action]) then
        return { ok = false, error = 'Your rank cannot perform this logistics action.' }
    end
    local lockOk, result, message = withOrderLock(orderId, function()
        if action == 'accept' then
            if actor.organizationId ~= SOURCE_ORG or not nearFacility(src, SOURCE_ORG, L.SourceFacilityType or 'armory') then
                return false, 'Army acceptance must be performed at the Army armory.'
            end
            return acceptOrder(src, actor, actorCid, orderId)
        elseif action == 'prepare' then
            if actor.organizationId ~= SOURCE_ORG or not nearFacility(src, SOURCE_ORG, L.SourceFacilityType or 'armory') then
                return false, 'Shipment preparation must be performed at Army logistics.'
            end
            return prepareOrder(src, actor, actorCid, orderId)
        elseif action == 'load' then
            if actor.organizationId ~= SOURCE_ORG or not nearFacility(src, SOURCE_ORG, L.SourceFacilityType or 'armory') then
                return false, 'Shipment loading must be performed at Army logistics.'
            end
            return changeVehicleState(src, actorCid, orderId, 'prepared', 'loaded', 'logistics_order_loaded')
        elseif action == 'depart' then
            return changeVehicleState(src, actorCid, orderId, 'loaded', 'in_transit', 'logistics_order_departed')
        elseif action == 'deliver' then
            if actor.organizationId ~= SOURCE_ORG then return false, 'Only Army logistics can deliver supplies.' end
            return transferOrder(src, actor, actorCid, orderId)
        elseif action == 'cancel' then
            if not nearFacility(src, actor.organizationId == SOURCE_ORG and SOURCE_ORG or actor.organizationId,
                L.SourceFacilityType or 'armory') then
                return false, 'Cancellation must be performed at the organization armory.'
            end
            return cancelOrder(actor, actorCid, orderId)
        elseif action == 'recover' then
            if actor.organizationId ~= SOURCE_ORG then return false, 'Only Army logistics can recover shipments.' end
            local current = orderHeader(orderId)
            if current and tostring(current.status) == 'wrecked' then
                return recoverWreckOrder(src, actorCid, orderId)
            end
            if not nearFacility(src, SOURCE_ORG, L.SourceFacilityType or 'armory') then
                return false, 'Recovery must be performed at Army logistics.'
            end
            return recoverOrder(actorCid, orderId)
        end
        return false, 'Unknown logistics action.'
    end)
    if lockOk ~= true then return { ok = false, error = result or 'Order is busy.' } end
    -- withOrderLock returns callback's two values after its success flag.
    local ok, text = result, message
    if ok ~= true then return { ok = false, error = text or 'Logistics action failed safely.' } end
    TriggerEvent('cm-admin:server:addLog', src, 'legal_logistics_' .. action, {
        category = 'orgs', organizationId = actor.organizationId, orderId = orderId,
    })
    return { ok = true, message = text or 'Logistics action complete.' }
end)

exports('GetLogisticsRequestableItems', function() return requestablePayload() end)
exports('GetLogisticsOrder', function(orderId)
    local rows = orderRows(orderId)
    return orderPayload(rows, { organizationId = SOURCE_ORG, isLeader = true, permissions = {} })
end)

local function existingTemporaryPlates()
    local out = {}
    local ok, rows = pcall(function() return exports['cm-vehicles']:ListAdminVehicles() end)
    if ok and type(rows) == 'table' then
        for _, row in ipairs(rows) do
            if row.alive == true and (not row.entity or DoesEntityExist(tonumber(row.entity))) then
                out[normalizePlate(row.plate)] = true
            end
        end
    end
    return out
end

local function recoverInterruptedOrders()
    if GetResourceState('cm-vehicles') ~= 'started' then return end
    local plates = existingTemporaryPlates()
    local liveShipmentPlates = {}
    local rows = MySQL.query.await([[SELECT id,shipment_plate,status,robbery_state FROM cm_legal_logistics_orders
        WHERE status IN ('prepared','loaded','in_transit') AND shipment_plate IS NOT NULL]]) or {}
    for _, row in ipairs(rows) do
        liveShipmentPlates[normalizePlate(row.shipment_plate)] = true
        if not plates[normalizePlate(row.shipment_plate)] then
            if tostring(row.robbery_state or 'eligible') == 'breached' then
                local cargo = cargoRows(row.id, { 'available' })
                local position = cargo[1]
                local expiresAt = os.time() + (tonumber(R.CargoExpirySeconds) or 1800)
                if position then
                    MySQL.transaction.await({
                        { query = [[UPDATE cm_legal_logistics_cargo SET state='wrecked',
                            expires_at=FROM_UNIXTIME(?) WHERE order_id=? AND state='available']],
                          values = { expiresAt, row.id } },
                        { query = [[UPDATE cm_legal_logistics_orders SET status='wrecked',
                            robbery_state='wrecked',wreck_x=?,wreck_y=?,wreck_z=?,wreck_bucket=?,
                            wreck_expires_at=FROM_UNIXTIME(?),shipment_plate=NULL
                            WHERE id=? AND status IN ('prepared','loaded','in_transit')]],
                          values = { position.x, position.y, position.z, position.bucket or 0, expiresAt, row.id } },
                    })
                else
                    MySQL.update.await([[UPDATE cm_legal_logistics_orders SET status='wrecked',
                        robbery_state='wrecked',shipment_plate=NULL
                        WHERE id=? AND status IN ('prepared','loaded','in_transit')]], { row.id })
                end
            else
                MySQL.update.await([[UPDATE cm_legal_logistics_orders SET status='accepted',
                    shipment_plate=NULL,prepared_by_cid=NULL,prepared_at=NULL,loaded_at=NULL,departed_at=NULL
                    WHERE id=? AND status IN ('prepared','loaded','in_transit')]], { row.id })
            end
            print(('[cm-law] logistics recovery reset order #%s after missing temporary shipment vehicle'):format(tostring(row.id)))
        end
    end
    -- A crash after a terminal DB update can leave a labelled temporary
    -- vehicle behind. Remove only this module's labelled vehicles; unrelated
    -- admin/placement vehicles remain untouched.
    local ok, temporaryRows = pcall(function() return exports['cm-vehicles']:ListAdminVehicles() end)
    if ok and type(temporaryRows) == 'table' then
        for _, vehicle in ipairs(temporaryRows) do
            local plate = normalizePlate(vehicle.plate)
            if not liveShipmentPlates[plate]
                and tostring(vehicle.label or '') == tostring(L.ShipmentVehicleLabel or 'Army Logistics Transport') then
                pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(vehicle.plate) end)
            end
        end
    end
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_logistics_orders (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        request_key VARCHAR(96) NOT NULL,
        requester_org VARCHAR(32) NOT NULL, requester_cid VARCHAR(64) NOT NULL,
        status VARCHAR(24) NOT NULL DEFAULT 'requested',
        robbery_state VARCHAR(24) NOT NULL DEFAULT 'eligible',
        accepted_by_cid VARCHAR(64) NULL, prepared_by_cid VARCHAR(64) NULL,
        shipment_plate VARCHAR(16) NULL, reservation_released TINYINT(1) NOT NULL DEFAULT 0,
        receiving_x DOUBLE NOT NULL, receiving_y DOUBLE NOT NULL, receiving_z DOUBLE NOT NULL,
        receiving_heading FLOAT NOT NULL DEFAULT 0, receiving_bucket INT NOT NULL DEFAULT 0,
        wreck_x DOUBLE NULL, wreck_y DOUBLE NULL, wreck_z DOUBLE NULL, wreck_bucket INT NULL,
        wreck_expires_at TIMESTAMP NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, accepted_at TIMESTAMP NULL,
        prepared_at TIMESTAMP NULL, loaded_at TIMESTAMP NULL, departed_at TIMESTAMP NULL,
        delivered_at TIMESTAMP NULL, cancelled_at TIMESTAMP NULL,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_logistics_request_key (request_key),
        KEY idx_cm_legal_logistics_org_status (requester_org,status),
        KEY idx_cm_legal_logistics_status (status),
        KEY idx_cm_legal_logistics_robbery (robbery_state)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_logistics_order_lines (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, order_id BIGINT UNSIGNED NOT NULL,
        item_name VARCHAR(80) NOT NULL, quantity INT UNSIGNED NOT NULL,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_logistics_line (order_id,item_name),
        KEY idx_cm_legal_logistics_lines_order (order_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_logistics_ledger (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, order_id BIGINT UNSIGNED NOT NULL,
        line_id BIGINT UNSIGNED NOT NULL, action VARCHAR(16) NOT NULL,
        quantity INT UNSIGNED NOT NULL, applied TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_logistics_ledger (order_id,line_id,action),
        KEY idx_cm_legal_logistics_ledger_pending (order_id,action,applied)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_logistics_cargo (
       id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, order_id BIGINT UNSIGNED NOT NULL,
       line_id BIGINT UNSIGNED NOT NULL, unit_index INT UNSIGNED NOT NULL DEFAULT 1,
       item_name VARCHAR(80) NOT NULL,
       quantity INT UNSIGNED NOT NULL, state VARCHAR(16) NOT NULL DEFAULT 'available',
       carrier_cid VARCHAR(64) NULL, carrier_source INT NULL,
       extracted_gang_id VARCHAR(32) NULL, credit_state VARCHAR(16) NOT NULL DEFAULT 'none',
       credit_operation_id VARCHAR(96) NULL, credited_at TIMESTAMP NULL, extracted_at TIMESTAMP NULL,
       x DOUBLE NULL, y DOUBLE NULL, z DOUBLE NULL, bucket INT NOT NULL DEFAULT 0,
       expires_at TIMESTAMP NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
       updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
       PRIMARY KEY (id), UNIQUE KEY uq_cm_legal_logistics_cargo_line (order_id,line_id,unit_index),
       UNIQUE KEY uq_cm_legal_logistics_cargo_operation (credit_operation_id),
       KEY idx_cm_legal_logistics_cargo_state (state,expires_at),
       KEY idx_cm_legal_logistics_cargo_carrier (carrier_cid,state)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- The tables are additive, but these guarded alters make an early
    -- development copy safe if it was created from a pre-release schema.
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_orders ADD COLUMN request_key VARCHAR(96) NULL') end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_legal_logistics_orders ADD COLUMN robbery_state VARCHAR(24) NOT NULL DEFAULT 'eligible'") end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_legal_logistics_orders ADD COLUMN breach_by_cid VARCHAR(64) NULL") end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_legal_logistics_orders ADD COLUMN breach_started_at TIMESTAMP NULL") end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_orders ADD COLUMN wreck_x DOUBLE NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_orders ADD COLUMN wreck_y DOUBLE NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_orders ADD COLUMN wreck_z DOUBLE NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_orders ADD COLUMN wreck_bucket INT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_orders ADD COLUMN wreck_expires_at TIMESTAMP NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_cargo ADD COLUMN unit_index INT UNSIGNED NOT NULL DEFAULT 1 AFTER line_id') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_logistics_cargo DROP INDEX uq_cm_legal_logistics_cargo_line') end)
    pcall(function() MySQL.query.await('CREATE UNIQUE INDEX uq_cm_legal_logistics_cargo_line ON cm_legal_logistics_cargo (order_id,line_id,unit_index)') end)
    pcall(function() MySQL.query.await('CREATE UNIQUE INDEX uq_cm_legal_logistics_request_key ON cm_legal_logistics_orders (request_key)') end)
    LogisticsReady = true
    SetTimeout(1000, function()
        recoverInterruptedOrders()
        reconcileCargo()
    end)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'cm-vehicles' then
        SetTimeout(1000, function()
            recoverInterruptedOrders()
            reconcileCargo()
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(tonumber(R.ReconcileIntervalMs) or 3000)
        if LogisticsReady then reconcileCargo() end
    end
end)
