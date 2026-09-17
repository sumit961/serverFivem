-- CM-LAW Phase 5: Arsenal Resupply major event.
-- This is intentionally independent from routine cm_legal_logistics_orders.
-- cm-law owns Army authority, the event ledger and physical cargo state.

local A = Config.ArsenalResupply or {}
local ready, runtime, operationLock = false, nil, false
local missingVehicles, actionLocks, requestRate = {}, {}, {}
local EVENT_TYPE = 'arsenal_resupply'
print('[cm-law] Arsenal server script loading')

local function now() return os.time() end
local function clean(value, max)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, max or 96)
end
local function bool(value) return value == true or tonumber(value) == 1 or tostring(value) == '1' end
local function decode(value, fallback)
    if type(value) == 'table' then return value end
    local ok, result = pcall(json.decode, value or '')
    return ok and type(result) == 'table' and result or fallback
end
local function distance(a, b)
    local x, y, z = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return math.sqrt(x * x + y * y + z * z)
end
local function sourceCharacter(src) return characterIdFor(tonumber(src)) end
local function itemCatalog(item)
    item = tostring(item or ''):lower()
    if item == '' then return nil end
    if GetResourceState('cm-weapons') == 'started' then
        local okWeapon, weapon = pcall(function() return exports['cm-weapons']:GetWeapon(item) end)
        if okWeapon and type(weapon) == 'table' and weapon.enabled ~= false then
            return { item = item, label = tostring(weapon.label or item) }
        end
        local okAmmo, ammo = pcall(function() return exports['cm-weapons']:GetAmmo(item) end)
        if okAmmo and type(ammo) == 'table' and ammo.enabled ~= false then
            return { item = item, label = tostring(ammo.label or item) }
        end
    end
    if GetResourceState('cm-items') == 'started' then
        local ok, row = pcall(function() return exports['cm-items']:GetPhysicalItem(item) end)
        if ok and type(row) == 'table' and row.inventory ~= false and row.virtual ~= true then
            return { item = item, label = tostring(row.label or item) }
        end
    end
    return nil
end
local function admin(src) return adminAllowed(tonumber(src)) end
local function lock(key, callback)
    if actionLocks[key] then return false, 'operation_busy' end
    actionLocks[key] = true
    local result = { pcall(callback) }
    actionLocks[key] = nil
    local ok = table.remove(result, 1)
    if not ok then return false, tostring(result[1] or 'operation_failed') end
    return table.unpack(result)
end
local function armyMember(src, permission)
    local member, cid = activeMemberForSource(tonumber(src))
    if not member or member.organizationId ~= 'army' then return nil, cid, 'Army authority is required.' end
    if member.suspended or not member.onDuty then return nil, cid, 'You must be an on-duty Army member.' end
    if permission and not member.isLeader and member.permissions[permission] ~= true then
        return nil, cid, 'Your Army rank cannot perform this action.'
    end
    return member, cid
end
local function gangMember(src)
    if GetResourceState('cm-gang') ~= 'started' then return nil, 'Gang services are unavailable.' end
    local cid = sourceCharacter(src)
    if not cid then return nil, 'Character is not loaded.' end
    local ok, membership = pcall(function() return exports['cm-gang']:GetGangForCharacter(cid) end)
    if not ok or type(membership) ~= 'table' or membership.enabled ~= true then return nil, 'You must be an active gang member.' end
    local allowed, result = pcall(function() return exports['cm-gang']:HasPermission(cid, 'gang.rob_items') end)
    if not allowed or result ~= true then return nil, 'Your gang rank cannot take Arsenal cargo.' end
    return { cid = tostring(cid), gangId = tostring(membership.gangId) }
end
local function notifyGang(gangId, event, payload)
    if GetResourceState('cm-gang') ~= 'started' then return end
    for _, raw in ipairs(GetPlayers()) do
        local src, cid = tonumber(raw), sourceCharacter(raw)
        if cid then
            local ok, member = pcall(function() return exports['cm-gang']:GetGangForCharacter(cid) end)
            if ok and type(member) == 'table' and member.enabled == true and tostring(member.gangId) == tostring(gangId) then
                TriggerClientEvent(event, src, payload)
            end
        end
    end
end
local function notifyArmy(message, kind)
    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src and armyMember(src) then TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'inform') end
    end
end

local function settings()
    local row = MySQL.single.await('SELECT setting_json FROM cm_legal_arsenal_settings WHERE setting_key=? LIMIT 1', { 'main' })
    local saved = decode(row and row.setting_json, {})
    local schedule = type(saved.dailySchedule) == 'table' and saved.dailySchedule or {}
    return {
        enabled = saved.enabled == nil and A.Enabled == true or saved.enabled == true,
        dailyEnabled = schedule.enabled == nil and A.DailySchedule.enabled ~= false or schedule.enabled == true,
        hour = math.max(0, math.min(23, math.floor(tonumber(schedule.hour) or tonumber(A.DailySchedule.hour) or 22))),
        minute = math.max(0, math.min(59, math.floor(tonumber(schedule.minute) or tonumber(A.DailySchedule.minute) or 0))),
        warmupSeconds = math.max(30, math.min(1800, math.floor(tonumber(saved.warmupSeconds) or tonumber(A.DailySchedule.warmupSeconds) or 300))),
        minimumArmyOnline = math.max(1, math.min(100, math.floor(tonumber(saved.minimumArmyOnline) or tonumber(A.MinimumArmyOnline) or 2))),
        preparationSeconds = math.max(10, math.min(1800, math.floor(tonumber(saved.preparationSeconds) or tonumber(A.PreparationSeconds) or 120))),
        maximumDurationSeconds = math.max(300, math.min(14400, math.floor(tonumber(saved.maximumDurationSeconds) or tonumber(A.MaximumDurationSeconds) or 3600))),
        intelIntervalSeconds = math.max(30, math.min(300, math.floor(tonumber(saved.intelIntervalSeconds) or tonumber(A.IntelIntervalSeconds) or 75))),
        unloadSeconds = math.max(5, math.min(300, math.floor(tonumber(saved.unloadSeconds) or tonumber(A.UnloadSeconds) or 20))),
        resultQuickViewSeconds = math.max(10, math.min(300, math.floor(tonumber(saved.resultQuickViewSeconds) or tonumber(A.ResultQuickViewSeconds) or 60))),
        leadEscortCount = math.max(0, math.min(3, math.floor(tonumber(saved.leadEscortCount) or tonumber(A.LeadEscortCount) or 1))),
        cargoTruckCount = math.max(1, math.min(3, math.floor(tonumber(saved.cargoTruckCount) or tonumber(A.CargoTruckCount) or 2))),
        rearEscortCount = math.max(0, math.min(3, math.floor(tonumber(saved.rearEscortCount) or tonumber(A.RearEscortCount) or 1))),
        intelEnabled = saved.intelEnabled == nil and A.IntelEnabled ~= false or saved.intelEnabled == true,
        approximateSearchRadius = math.max(200, math.min(1000, tonumber(saved.approximateSearchRadius) or tonumber(A.ApproximateSearchRadius) or 750)),
        maxStoppedSpeed = math.max(0.05, math.min(3.0, tonumber(saved.maxStoppedSpeed) or tonumber(A.MaxStoppedSpeed) or 0.75)),
        interactionDistance = math.max(1.0, math.min(5.0, tonumber(saved.interactionDistance) or tonumber(A.InteractionDistance) or 2.5)),
        breachSeconds = math.max(5, math.min(180, math.floor(tonumber(saved.breachSeconds) or tonumber(A.BreachSeconds) or 20))),
    }
end
local function manifest()
    local rows = MySQL.query.await([[SELECT item_name,quantity,crate_size,value_weight FROM cm_legal_arsenal_manifest
        WHERE enabled=1 ORDER BY id]]) or {}
    if #rows == 0 then rows = A.Manifest or {} end
    local result, total = {}, 0
    for _, row in ipairs(rows) do
        local item = tostring(row.item_name or row.item or ''):lower()
        local quantity = math.floor(tonumber(row.quantity) or 0)
        local weight = math.floor(tonumber(row.value_weight or row.valueWeight) or 0)
        local crateSize = math.floor(tonumber(row.crate_size or row.crateSize) or quantity)
        if item ~= '' and quantity > 0 and weight > 0 then
            result[#result + 1] = { item = item, quantity = quantity, crateSize = math.max(1,math.min(quantity,crateSize)), valueWeight = weight }
            total = total + quantity * weight
        end
    end
    return result, total
end
local function routes()
    local rows = MySQL.query.await([[SELECT route_id,label,intel_text,start_x,start_y,start_z,start_h,
        destination_x,destination_y,destination_z,destination_h,waypoints_json,routing_bucket FROM cm_legal_arsenal_routes
        WHERE enabled=1 ORDER BY route_id]]) or {}
    if #rows > 0 then
        local result = {}
        for _, row in ipairs(rows) do
            result[#result + 1] = { id = tostring(row.route_id), label = clean(row.label, 96),
                intel = clean(row.intel_text, 160), start = { x=tonumber(row.start_x), y=tonumber(row.start_y), z=tonumber(row.start_z), h=tonumber(row.start_h) or 0 },
                destination = { x=tonumber(row.destination_x), y=tonumber(row.destination_y), z=tonumber(row.destination_z), h=tonumber(row.destination_h) or 0 },
                waypoints = decode(row.waypoints_json, {}),
                bucket = tonumber(row.routing_bucket) or 0 }
        end
        return result
    end
    return A.Routes or {}
end
local function extractions()
    local rows = MySQL.query.await([[SELECT id,gang_id,x,y,z,radius,routing_bucket FROM cm_legal_arsenal_extraction_points
        WHERE enabled=1 ORDER BY id]]) or {}
    if #rows > 0 then return rows end
    return A.ExtractionPoints or {}
end
local function validateManifest(rows)
    local problems, total = {}, 0
    if type(rows) ~= 'table' or #rows < 1 or #rows > 32 then return false, 'Manifest must contain 1-32 entries.' end
    for _, row in ipairs(rows) do
        local item, quantity, weight = tostring(row.item or row.item_name or ''):lower(), math.floor(tonumber(row.quantity) or 0), math.floor(tonumber(row.valueWeight or row.value_weight) or 0)
        local crateSize=math.floor(tonumber(row.crateSize or row.crate_size)or 0)
        if not itemCatalog(item) then problems[#problems + 1] = 'Unknown catalog item: '..item end
        if quantity < 1 or quantity > 100000 or crateSize < 1 or crateSize > quantity or weight < 1 or weight > 100000 then problems[#problems + 1] = 'Invalid manifest line: '..item end
        total = total + quantity * weight
    end
    if total < 1 or total > 1000000000 then problems[#problems + 1] = 'Manifest value is outside the safe range.' end
    return #problems == 0, table.concat(problems, '; ')
end
local function validateRoute(route)
    return type(route) == 'table' and route.start and route.destination
        and tonumber(route.start.x) and tonumber(route.start.y) and tonumber(route.start.z)
        and tonumber(route.destination.x) and tonumber(route.destination.y) and tonumber(route.destination.z)
        and (tonumber(route.bucket) or 0) == 0
end
local function onlineArmyCount()
    local count = 0
    for _, raw in ipairs(GetPlayers()) do if armyMember(tonumber(raw)) then count = count + 1 end end
    return count
end
local function routeById(id)
    for _, route in ipairs(routes()) do if tostring(route.id) == tostring(id) and validateRoute(route) then return route end end
end
local function selectedRoute()
    local list = routes()
    local valid = {}
    for _, route in ipairs(list) do if validateRoute(route) then valid[#valid + 1] = route end end
    return #valid > 0 and valid[math.random(1, #valid)] or nil
end

local function stockMutation(runId, item, quantity, direction, suffix, alreadyLocked)
    if not alreadyLocked then
        local locked, applied, reason = LawWithStockLock({ 'army:' .. tostring(item) }, function()
            return stockMutation(runId, item, quantity, direction, suffix, true)
        end)
        if locked ~= true then return false, applied or 'Army stock is busy.' end
        return applied, reason
    end
    local operationId = ('arsenal:%s:%s:%s'):format(runId, suffix, item):gsub('[^%w:_.-]', '')
    local existing = MySQL.scalar.await('SELECT status FROM cm_legal_arsenal_stock_ledger WHERE operation_id=? LIMIT 1', { operationId })
    if existing == 'completed' then return true end
    local row = MySQL.single.await('SELECT stock FROM cm_legal_armory_stock WHERE organization_id=? AND item_name=? AND enabled=1 LIMIT 1', { 'army', item })
    if not row then return false, 'Army item is not enabled.' end
    if direction == 'remove' and (tonumber(row.stock) or 0) < quantity then return false, 'Army stock is insufficient.' end
    local statements = {
        { query = [[INSERT IGNORE INTO cm_legal_arsenal_stock_ledger(operation_id,run_id,item_name,quantity,direction,status)
            VALUES(?,?,?,?,?,'pending')]], values = { operationId, runId, item, quantity, direction } },
    }
    if direction == 'remove' then
        statements[#statements + 1] = { query = [[UPDATE cm_legal_armory_stock SET stock=stock-?
            WHERE organization_id='army' AND item_name=? AND enabled=1 AND stock>=?]], values = { quantity, item, quantity } }
    else
        statements[#statements + 1] = { query = [[UPDATE cm_legal_armory_stock SET stock=stock+?
            WHERE organization_id='army' AND item_name=? AND enabled=1]], values = { quantity, item } }
    end
    statements[#statements + 1] = { query = [[UPDATE cm_legal_arsenal_stock_ledger SET status='completed'
        WHERE operation_id=? AND status='pending']], values = { operationId } }
    if MySQL.transaction.await(statements) ~= true then return false, 'Army stock operation failed safely.' end
    return MySQL.scalar.await('SELECT status FROM cm_legal_arsenal_stock_ledger WHERE operation_id=? LIMIT 1', { operationId }) == 'completed'
end
local function releaseUnsettled(runId)
    -- Arsenal cargo is new incoming stock. Unresolved cargo is lost; it must
    -- never be returned to or deducted from pre-existing Army warehouse stock.
    MySQL.update.await([[UPDATE cm_legal_arsenal_cargo SET state='expired',carrier_cid=NULL,carrier_source=NULL
        WHERE run_id=? AND state NOT IN ('extracted','delivered','recovered','expired')]], { runId })
end
local function sendArmyRoute(route)
    local points={};for _,point in ipairs(route.waypoints or{})do points[#points+1]={x=tonumber(point.x),y=tonumber(point.y),z=tonumber(point.z)}end
    points[#points+1]={x=tonumber(route.destination.x),y=tonumber(route.destination.y),z=tonumber(route.destination.z)}
    for _,raw in ipairs(GetPlayers())do local src=tonumber(raw);if src and armyMember(src)then TriggerClientEvent('cm-law:client:arsenalRoute',src,{points=points})end end
end
local function nextOccurrence(cfg)
    cfg=cfg or settings();if not cfg.enabled or not cfg.dailyEnabled then return nil end
    local date=os.date('*t');date.hour=cfg.hour;date.min=cfg.minute;date.sec=0
    local candidate=os.time(date);if candidate<=now()then candidate=candidate+86400 end
    return candidate
end

local function vehicleRows(runId)
    local list = {}
    local ok, rows = pcall(function() return exports['cm-vehicles']:ListAdminVehicles() end)
    if not ok or type(rows) ~= 'table' then return list end
    for _, row in ipairs(rows) do
        if tostring(row.label or ''):find('^Arsenal Resupply '..tostring(runId), 1, false) then
            local entity = tonumber(row.entity)
            if entity and entity ~= 0 and DoesEntityExist(entity) then list[#list + 1] = { plate=row.plate, entity=entity, netId=row.netId } end
        end
    end
    return list
end
local function vehicleFor(runId, truckIndex)
    for _, row in ipairs(vehicleRows(runId)) do
        local state = Entity(row.entity).state.cmArsenalResupply
        if type(state) == 'table' and tostring(state.runId) == tostring(runId) and tonumber(state.truckIndex) == tonumber(truckIndex) then return row.entity, row end
    end
end
local function rearOf(vehicle)
    local c, f, d = GetEntityCoords(vehicle), GetEntityForwardVector(vehicle), tonumber(A.RearDistance) or 3.5
    return vector3(c.x - f.x * d, c.y - f.y * d, c.z + 0.7)
end
local function nearRear(src, vehicle)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and GetEntityHealth(ped) > 0 and not IsEntityDead(ped) and GetVehiclePedIsIn(ped, false) == 0
        and GetPlayerRoutingBucket(src) == GetEntityRoutingBucket(vehicle)
        and #(GetEntityCoords(ped) - rearOf(vehicle)) <= (runtime and runtime.settings.interactionDistance or tonumber(A.InteractionDistance) or 2.5)
end
local function sendCargo(row, override)
    local payload = { id=tonumber(row.id),runId=row.run_id,truckIndex=tonumber(row.truck_index),item=row.item_name,
        quantity=tonumber(row.quantity),state=override or row.state,carrierSource=tonumber(row.carrier_source),
        x=tonumber(row.x),y=tonumber(row.y),z=tonumber(row.z),bucket=tonumber(row.bucket) or 0 }
    local x,y,z = payload.x,payload.y,payload.z
    if payload.carrierSource then local ped=GetPlayerPed(payload.carrierSource);if ped and ped~=0 then local c=GetEntityCoords(ped);x,y,z=c.x,c.y,c.z end end
    if not x then return end
    for _, raw in ipairs(GetPlayers()) do
        local src=tonumber(raw);local ped=src and GetPlayerPed(src) or 0
        if ped and ped~=0 and GetPlayerRoutingBucket(src)==payload.bucket and #(GetEntityCoords(ped)-vector3(x,y,z)) <= 100.0 then
            TriggerClientEvent('cm-law:client:arsenalCargoSync',src,payload)
        end
    end
end
local function cargoPointNear(src, row)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetEntityHealth(ped) <= 0 or IsEntityDead(ped) or not row.x or not row.y or not row.z then return false end
    if GetPlayerRoutingBucket(src) ~= (tonumber(row.bucket) or 0) then return false end
    return #(GetEntityCoords(ped) - vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z))) <= (runtime and runtime.settings.interactionDistance or tonumber(A.InteractionDistance) or 2.5)
end
local function extractionNear(src, gangId)
    local ped=GetPlayerPed(src);if not ped or ped==0 or GetEntityHealth(ped)<=0 or IsEntityDead(ped) then return false end
    local c=GetEntityCoords(ped);local bucket=GetPlayerRoutingBucket(src)
    for _, point in ipairs(extractions()) do
        if (not point.gang_id and not point.gangId or tostring(point.gang_id or point.gangId)==tostring(gangId))
            and tonumber(point.x) and tonumber(point.y) and tonumber(point.z)
            and bucket==(tonumber(point.routing_bucket or point.bucket) or 0)
            and #(c-vector3(point.x,point.y,point.z)) <= (tonumber(point.radius) or 4.0) then return true end
    end
    return false
end

local function participant(runId, gangId, cid)
    MySQL.insert.await([[INSERT IGNORE INTO cm_legal_arsenal_participants(run_id,gang_id,first_character_id)
        VALUES(?,?,?)]], { runId, gangId, cid })
end
local function resultPayload(runId)
    local run=MySQL.single.await([[SELECT *,UNIX_TIMESTAMP(scheduled_at) AS started_epoch,
        UNIX_TIMESTAMP(ended_at) AS ended_epoch FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1]],{runId});if not run then return nil end
    local rows=MySQL.query.await([[SELECT gang_id,stolen_value,cargo_count FROM cm_legal_arsenal_participants
        WHERE run_id=? ORDER BY stolen_value DESC,gang_id]],{runId}) or {}
    local armyValue=tonumber(run.delivered_value)or 0
    local winner='ARMY'
    if rows[1] and (tonumber(rows[1].stolen_value)or 0)>armyValue then winner=rows[1].gang_id end
    for _,row in ipairs(rows) do row.stolenValue=tonumber(row.stolen_value)or 0;row.cargoCount=tonumber(row.cargo_count)or 0;row.stolen_value=nil;row.cargo_count=nil end
    local saved=decode(run.result_json,{})
    local total=tonumber(run.total_value)or 0
    local function percent(value) return total>0 and math.floor(((tonumber(value)or 0)*1000/total)+0.5)/10 or 0 end
    for _,row in ipairs(rows) do row.percent=percent(row.stolenValue) end
    return { eventId=runId,eventType=EVENT_TYPE,status=run.state,winner=winner,totalValue=total,
        startedAt=tonumber(run.started_epoch),endedAt=tonumber(run.ended_epoch),
        deliveredValue=tonumber(run.delivered_value)or 0,stolenValue=tonumber(run.stolen_value)or 0,lostValue=tonumber(run.lost_value)or 0,
        armyPercent=percent(run.delivered_value),lostPercent=percent(run.lost_value),standings=rows,presentation=A.Presentation,
        saved=saved }
end
local function cargoInvariant(runId,context)
    local run=MySQL.single.await('SELECT manifest_json FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1',{runId});if not run then print(('[cm-law:arsenal] invariant unavailable run=%s context=%s run_not_found'):format(tostring(runId),tostring(context)));return false end
    local incoming={};for _,row in ipairs(decode(run.manifest_json,{}))do incoming[row.item]=(incoming[row.item]or 0)+(tonumber(row.quantity)or 0)end
    local rows=MySQL.query.await('SELECT item_name,state,SUM(quantity) quantity FROM cm_legal_arsenal_cargo WHERE run_id=? GROUP BY item_name,state',{runId})or{};local accounted={};local ok=true
    local valid={on_truck=true,available=true,carried=true,dropped=true,wrecked=true,delivered=true,extracted=true,expired=true,recovered=true}
    for _,row in ipairs(rows)do if not valid[row.state]then ok=false;print(('[cm-law:arsenal] ERROR invariant run=%s context=%s invalid_state=%s'):format(runId,tostring(context),tostring(row.state)))end;accounted[row.item_name]=(accounted[row.item_name]or 0)+(tonumber(row.quantity)or 0)end
    for item,quantity in pairs(incoming)do if(accounted[item]or 0)~=quantity then ok=false;print(('[cm-law:arsenal] ERROR invariant run=%s context=%s item=%s incoming=%d accounted=%d'):format(runId,tostring(context),item,quantity,accounted[item]or 0))end end
    for item,quantity in pairs(accounted)do if incoming[item]==nil then ok=false;print(('[cm-law:arsenal] ERROR invariant run=%s context=%s unexpected_item=%s accounted=%d'):format(runId,tostring(context),item,quantity))end end
    return ok
end
local function finish(runId, state, reason)
    local run=MySQL.single.await('SELECT * FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1',{runId});if not run then return false end
    if run.state=='COMPLETED' or run.state=='CANCELLED' or run.state=='INTERRUPTED' then return true end
    if state=='CANCELLED' or state=='INTERRUPTED' or reason=='maximum_duration_elapsed' then releaseUnsettled(runId) end
    MySQL.update.await("UPDATE cm_legal_arsenal_runs SET state='ENDING',end_reason=? WHERE run_id=? AND state NOT IN ('COMPLETED','CANCELLED','INTERRUPTED')",{reason,runId})
    local totals=MySQL.single.await([[SELECT
        COALESCE(SUM(CASE WHEN state='delivered' THEN quantity*value_weight ELSE 0 END),0) delivered,
        COALESCE(SUM(CASE WHEN state='extracted' THEN quantity*value_weight ELSE 0 END),0) stolen,
        COALESCE(SUM(CASE WHEN state='expired' THEN quantity*value_weight ELSE 0 END),0) lost
        FROM cm_legal_arsenal_cargo WHERE run_id=?]],{runId}) or {}
    local finalState=state or 'COMPLETED'
    MySQL.update.await([[UPDATE cm_legal_arsenal_runs SET state=?,ended_at=NOW(),delivered_value=?,stolen_value=?,lost_value=?,
        result_json=?,quick_available_until=DATE_ADD(NOW(),INTERVAL ? SECOND) WHERE run_id=? AND state='ENDING']],{
        finalState,tonumber(totals.delivered)or 0,tonumber(totals.stolen)or 0,tonumber(totals.lost)or 0,
        json.encode({reason=reason}),settings().resultQuickViewSeconds,runId})
    for _,row in ipairs(vehicleRows(runId)) do pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(row.plate) end) end
    for _,raw in ipairs(GetPlayers())do TriggerClientEvent('cm-law:client:arsenalRoute',tonumber(raw),{clear=true})end
    for _,row in ipairs(MySQL.query.await('SELECT gang_id FROM cm_legal_arsenal_participants WHERE run_id=?',{runId}) or {}) do
        notifyGang(row.gang_id,'cm-gang:client:arsenalResupplyResultAvailable',{eventId=runId,availableUntil=now()+settings().resultQuickViewSeconds})
    end
    runtime=nil
    cargoInvariant(runId,'event_finished')
    return true
end

local function beginPreparation(runId)
    if not runtime or runtime.id~=runId or runtime.state~='WARMUP' then return end
    local run=MySQL.single.await('SELECT * FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1',{runId});if not run then return end
    runtime.state='ARMY_PREPARATION';MySQL.update.await("UPDATE cm_legal_arsenal_runs SET state='ARMY_PREPARATION',preparation_at=NOW() WHERE run_id=? AND state='WARMUP'",{runId})
    local rows=decode(run.manifest_json,{})
    if onlineArmyCount() < (tonumber(runtime.settings.minimumArmyOnline) or 2) then return finish(runId,'CANCELLED','army_authority_lost') end
    local route=runtime.route;local base=route.start;local heading=tonumber(base.h)or 0;local rad=math.rad(heading)
    local positions={};local spacing=tonumber(A.VehicleSpacing)or 12
    local function addVehicles(count,role,model) for _=1,count do positions[#positions+1]={role=role,model=model,offset=#positions*spacing} end end
    addVehicles(runtime.settings.leadEscortCount,'lead',A.LeadVehicleModel)
    addVehicles(runtime.settings.cargoTruckCount,'cargo',A.CargoVehicleModel)
    addVehicles(runtime.settings.rearEscortCount,'rear',A.RearVehicleModel)
    local vehicles, spawned = {}, {}
    for index,spec in ipairs(positions) do
        local x=base.x+math.sin(rad)*spec.offset;local y=base.y-math.cos(rad)*spec.offset
        local created=exports['cm-vehicles']:SpawnAdminVehicle(0,spec.model,{x=x,y=y,z=base.z,h=heading},{access='public',engineOn=true,placementKind='car',label=('Arsenal Resupply %s %s %d'):format(runId,spec.role,index)})
        if type(created)~='table' or created.ok~=true then
            for _,row in ipairs(spawned) do pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(row.plate) end) end
            return finish(runId,'CANCELLED','vehicle_spawn_failed')
        end
        local entity=tonumber(created.entity);if entity and entity~=0 then Entity(entity).state:set('cmArsenalResupply',{runId=runId,role=spec.role,truckIndex=index},true) end
        vehicles[#vehicles+1]={plate=created.plate,role=spec.role,truckIndex=index};spawned[#spawned+1]=created
    end
    local cargoIndices={};for index,spec in ipairs(positions)do if spec.role=='cargo'then cargoIndices[#cargoIndices+1]=index end end
    -- Split into physical crate units across actual cargo-truck indices. The
    -- remainder is emitted once, so configured quantity is conserved exactly.
    local statements={}
    for _,row in ipairs(rows) do
        local remaining=row.quantity;local unit=0
        while remaining>0 do
            unit=unit+1;local amount=math.min(row.crateSize,remaining);remaining=remaining-amount
            local truck=cargoIndices[((unit-1)%#cargoIndices)+1]
            statements[#statements+1]={query=[[INSERT INTO cm_legal_arsenal_cargo
                (run_id,truck_index,item_name,quantity,value_weight,state,x,y,z,bucket) VALUES(?,?,?,?,?,'on_truck',NULL,NULL,NULL,0)]],values={runId,truck,row.item,amount,row.valueWeight}}
        end
    end
    for _,truck in ipairs(cargoIndices)do statements[#statements+1]={query='INSERT INTO cm_legal_arsenal_trucks(run_id,truck_index) VALUES(?,?)',values={runId,truck}} end
    if #statements==0 or MySQL.transaction.await(statements)~=true then
        for _,row in ipairs(spawned) do pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(row.plate) end) end
        return finish(runId,'CANCELLED','cargo_create_failed')
    end
    cargoInvariant(runId,'cargo_created')
    runtime.vehicles=vehicles
    notifyArmy(('Arsenal Resupply vehicles are ready. Depart in %d seconds.'):format(runtime.settings.preparationSeconds),'inform')
    SetTimeout(runtime.settings.preparationSeconds*1000,function()
        if not runtime or runtime.id~=runId or runtime.state~='ARMY_PREPARATION' then return end
        runtime.state='CONVOY_ACTIVE'
        runtime.endsAt=now()+runtime.settings.maximumDurationSeconds
        MySQL.update.await("UPDATE cm_legal_arsenal_runs SET state='CONVOY_ACTIVE',active_at=NOW(),vehicles_json=? WHERE run_id=? AND state='ARMY_PREPARATION'",{json.encode(vehicles),runId})
        notifyArmy(('Arsenal Resupply convoy active. Exact Army route: %s'):format(runtime.route.label or runtime.route.id),'inform')
        sendArmyRoute(runtime.route)
        if GetResourceState('cm-gang')=='started' then pcall(function() exports['cm-gang']:AnnounceArsenalResupply({eventId=runId,presentation=A.Presentation}) end) end
        SetTimeout(runtime.settings.maximumDurationSeconds*1000,function()
            if runtime and runtime.id==runId then finish(runId,'COMPLETED','maximum_duration_elapsed') end
        end)
    end)
end
local function finishIfResolved(runId)
    local remaining=tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM cm_legal_arsenal_cargo
        WHERE run_id=? AND state IN ('on_truck','available','dropped','carried','wrecked')]],{runId})or 0)
    if remaining==0 then return finish(runId,'COMPLETED','all_cargo_resolved') end
    return true
end

local function startRun(src, automatic)
    if operationLock then return false,'operation_busy' end;operationLock=true
    local function done(ok, reason) operationLock=false;return ok,reason end
    if not ready then return done(false,'database_not_ready') end
    if automatic ~= true and not admin(src) then return done(false,'permission_denied') end
    local cfg=settings();if not cfg.enabled then return done(false,'event_disabled') end
    if onlineArmyCount()<cfg.minimumArmyOnline then return done(false,'minimum_army_online_not_met') end
    if GetResourceState('cm-gang')=='started' then
        local ok,state=pcall(function() return exports['cm-gang']:GetGangEventState() end)
        if not ok or (type(state)=='table' and state.state~='IDLE' and state.state~='ENDED') then return done(false,'exclusive_gang_event_active') end
    end
    local rows,total=manifest();local valid,why=validateManifest(rows);if not valid then return done(false,why) end
    local route=selectedRoute();if not route then return done(false,'no_valid_route_configured') end
    local active=MySQL.scalar.await([[SELECT run_id FROM cm_legal_arsenal_runs WHERE state IN
        ('WARMUP','ARMY_PREPARATION','CONVOY_ACTIVE','WAREHOUSE_UNLOADING','ENDING') LIMIT 1]])
    if active then return done(false,'event_already_active') end
    local id=automatic and ('arsenal:auto:%s'):format(os.date('!%Y%m%d')) or ('arsenal:%d:%06d'):format(now(),math.random(0,999999))
    if MySQL.scalar.await('SELECT run_id FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1',{id}) then return done(false,'scheduled_event_already_processed') end
    local warmup=now()+cfg.warmupSeconds
    local inserted=MySQL.insert.await([[INSERT INTO cm_legal_arsenal_runs(run_id,state,scheduled_at,warmup_at,route_id,manifest_json,config_snapshot,total_value)
        VALUES(?,'WARMUP',NOW(),FROM_UNIXTIME(?),?,?,?,?)]],{id,warmup,route.id,json.encode(rows),json.encode(cfg),total})
    if not inserted then return done(false,'run_persistence_failed') end
    runtime={id=id,state='WARMUP',route=route,settings=cfg,vehicles={},missing={},positions={},nextIntelAt=0}
    notifyArmy(('Arsenal Resupply warmup started. %d seconds until Army preparation.'):format(cfg.warmupSeconds),'inform')
    SetTimeout(cfg.warmupSeconds*1000,function() beginPreparation(id) end)
    return done(true,id)
end

local function cargoAction(src, action, runId, truckIndex, cargoId)
    local gang,why=gangMember(src);if not gang then return false,why end
    local run=MySQL.single.await('SELECT * FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1',{tostring(runId)})
    if not run or (run.state~='CONVOY_ACTIVE' and run.state~='WAREHOUSE_UNLOADING') then return false,'The Arsenal event is not active.' end
    return lock(('cargo:%s:%s'):format(runId,tostring(cargoId or truckIndex)),function()
        if action=='breach_start' or action=='breach_complete' or action=='breach_cancel' then
            if action=='breach_cancel' then MySQL.update.await("UPDATE cm_legal_arsenal_trucks SET breach_by_cid=NULL,breach_started_at=NULL WHERE run_id=? AND truck_index=? AND breach_by_cid=?",{runId,truckIndex,gang.cid});return true,'Breach cancelled.' end
            local vehicle=vehicleFor(runId,truckIndex);local breachSeconds=runtime and runtime.settings.breachSeconds or tonumber(A.BreachSeconds)or 20;if not vehicle or not nearRear(src,vehicle) or GetEntitySpeed(vehicle)>(runtime and runtime.settings.maxStoppedSpeed or tonumber(A.MaxStoppedSpeed)or 0.75) then return false,'The cargo truck must be stopped at its rear.' end
            local role=Entity(vehicle).state.cmArsenalResupply
            if type(role)~='table' or role.role~='cargo' then return false,'This is not an Arsenal cargo truck.' end
            if action=='breach_start' then
                local changed=MySQL.update.await([[UPDATE cm_legal_arsenal_trucks SET breach_by_cid=?,breach_started_at=NOW()
                    WHERE run_id=? AND truck_index=? AND (breach_by_cid IS NULL OR breach_started_at<?)]],{gang.cid,runId,truckIndex,os.date('%Y-%m-%d %H:%M:%S',now()-breachSeconds)})
                return tonumber(changed)==1,'Breach started.'
            end
            local current=MySQL.single.await('SELECT breach_by_cid,UNIX_TIMESTAMP(breach_started_at) started_at FROM cm_legal_arsenal_trucks WHERE run_id=? AND truck_index=?',{runId,truckIndex})
            if not current or tostring(current.breach_by_cid)~=gang.cid or now()-(tonumber(current.started_at)or 0)<breachSeconds then return false,'The breach is not complete.' end
            MySQL.update.await("UPDATE cm_legal_arsenal_trucks SET breach_by_cid=NULL,breach_started_at=NULL WHERE run_id=? AND truck_index=? AND breach_by_cid=?",{runId,truckIndex,gang.cid})
            local truckCoords = GetEntityCoords(vehicle)
            local changed=MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET state='available',x=?,y=?,z=?,bucket=? WHERE run_id=? AND truck_index=? AND state='on_truck'",{truckCoords.x,truckCoords.y,truckCoords.z,GetEntityRoutingBucket(vehicle),runId,truckIndex})
            for _, available in ipairs(MySQL.query.await("SELECT * FROM cm_legal_arsenal_cargo WHERE run_id=? AND truck_index=? AND state='available'", { runId, truckIndex }) or {}) do sendCargo(available) end
            participant(runId,gang.gangId,gang.cid);cargoInvariant(runId,'truck_breached');notifyGang(gang.gangId,'cm-gang:client:arsenalResupplyParticipating',{eventId=runId,routeIntel=clean((runtime and runtime.route.intel) or 'Convoy route intel unavailable.',160),stage='cargo_breached'})
            return tonumber(changed)>0,'Cargo truck breached. Take a crate.'
        end
        local crate=MySQL.single.await('SELECT * FROM cm_legal_arsenal_cargo WHERE id=? AND run_id=? LIMIT 1',{tonumber(cargoId),runId})
        if not crate then return false,'Cargo crate not found.' end
        if action=='claim' then
            if MySQL.scalar.await("SELECT id FROM cm_legal_arsenal_cargo WHERE carrier_cid=? AND state='carried' LIMIT 1",{gang.cid}) then return false,'You are already carrying a crate.' end
            local valid=false
            if crate.state=='available' then local vehicle=vehicleFor(runId,crate.truck_index);valid=vehicle and nearRear(src,vehicle) end
            if crate.state=='dropped' or crate.state=='wrecked' then valid=cargoPointNear(src,crate) end
            if not valid then return false,'Move closer to the cargo.' end
            local c=GetEntityCoords(GetPlayerPed(src));local changed=MySQL.update.await([[UPDATE cm_legal_arsenal_cargo SET state='carried',
                carrier_cid=?,carrier_source=?,x=?,y=?,z=?,bucket=?,expires_at=NULL WHERE id=? AND state IN ('available','dropped','wrecked')]],{gang.cid,tonumber(src),c.x,c.y,c.z,GetPlayerRoutingBucket(src),crate.id})
            if tonumber(changed)~=1 then return false,'That crate was taken first.' end;sendCargo(MySQL.single.await('SELECT * FROM cm_legal_arsenal_cargo WHERE id=?',{crate.id}));return true,'Cargo secured.'
        elseif action=='drop' then
            if crate.state~='carried' or tostring(crate.carrier_cid)~=gang.cid or tonumber(crate.carrier_source)~=tonumber(src) then return false,'You are not carrying that crate.' end
            local c=GetEntityCoords(GetPlayerPed(src));local changed=MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET state='dropped',carrier_cid=NULL,carrier_source=NULL,x=?,y=?,z=?,bucket=?,expires_at=FROM_UNIXTIME(?) WHERE id=? AND state='carried'",{c.x,c.y,c.z,GetPlayerRoutingBucket(src),now()+tonumber(A.DroppedExpirySeconds or 1800),crate.id})
            if tonumber(changed)~=1 then return false,'Cargo drop failed safely.' end;sendCargo(MySQL.single.await('SELECT * FROM cm_legal_arsenal_cargo WHERE id=?',{crate.id}));return true,'Cargo dropped.'
        elseif action=='heartbeat' then
            if crate.state~='carried' or tostring(crate.carrier_cid)~=gang.cid or tonumber(crate.carrier_source)~=tonumber(src) then return false,'You are not carrying that crate.' end
            local c=GetEntityCoords(GetPlayerPed(src));MySQL.update.await('UPDATE cm_legal_arsenal_cargo SET x=?,y=?,z=?,bucket=? WHERE id=? AND state=\'carried\' AND carrier_source=?',{c.x,c.y,c.z,GetPlayerRoutingBucket(src),crate.id,tonumber(src)});return true
        elseif action=='extract' then
            if crate.state~='carried' or tostring(crate.carrier_cid)~=gang.cid or tonumber(crate.carrier_source)~=tonumber(src) then return false,'You are not carrying that crate.' end
            if not extractionNear(src,gang.gangId) then return false,'This is not a configured extraction point.' end
            local op=('arsenal:%s:cargo:%s:%s'):format(runId,crate.id,gang.gangId)
            local changed=MySQL.update.await([[UPDATE cm_legal_arsenal_cargo SET state='extracted',carrier_cid=NULL,carrier_source=NULL,
                extracted_gang_id=?,credit_state='pending',credit_operation_id=?,extracted_at=NOW() WHERE id=? AND state='carried' AND carrier_cid=? AND carrier_source=?]],{gang.gangId,op,crate.id,gang.cid,tonumber(src)})
            if tonumber(changed)~=1 then return false,'Cargo extraction failed safely.' end
            participant(runId,gang.gangId,gang.cid);MySQL.update.await('UPDATE cm_legal_arsenal_participants SET stolen_value=stolen_value+?,cargo_count=cargo_count+1 WHERE run_id=? AND gang_id=?',{(tonumber(crate.quantity)or 0)*(tonumber(crate.value_weight)or 0),runId,gang.gangId})
            local called,success=pcall(function()
                return exports['cm-gang']:AddGangArmoryStock(gang.gangId,crate.item_name,crate.quantity,{operationId=op,runId=runId,cargoId=crate.id})
            end)
            local applied=called and success==true
            if applied then MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET credit_state='credited',credited_at=NOW() WHERE id=? AND state='extracted'",{crate.id}) end
            sendCargo(crate,'removed');cargoInvariant(runId,'gang_extracted');finishIfResolved(runId);return true,applied and 'Cargo extracted and credited.' or 'Cargo extracted; gang credit is pending retry.'
        end
        return false,'Unknown cargo action.'
    end)
end

lib.callback.register('cm-law:server:arsenalCargoNearby',function(src,runId,truckIndex,netId)
    if not ready then return {} end
    local gang=gangMember(src);if not gang then return {eligible=false,crates={}} end
    local vehicle=vehicleFor(tostring(runId),tonumber(truckIndex));if not vehicle or tonumber(netId)~=NetworkGetNetworkIdFromEntity(vehicle) or not nearRear(src,vehicle) then return {eligible=false,crates={}} end
    local rows=MySQL.query.await("SELECT * FROM cm_legal_arsenal_cargo WHERE run_id=? AND truck_index=? AND state='available' ORDER BY id",{runId,truckIndex}) or {}
    local out={};for _,row in ipairs(rows)do out[#out+1]={id=tonumber(row.id),runId=row.run_id,truckIndex=tonumber(row.truck_index),state=row.state,x=GetEntityCoords(vehicle).x,y=GetEntityCoords(vehicle).y,z=GetEntityCoords(vehicle).z}end
    return {eligible=true,crates=out}
end)
lib.callback.register('cm-law:server:arsenalCargo',function(src,action,runId,truckIndex,cargoId)
    if not ready then return {ok=false,error='Arsenal Resupply is still starting.'} end
    local key=('request:%s:%s'):format(src,tostring(action));if (requestRate[key]or 0)>GetGameTimer() then return {ok=false,error='Please wait.'} end;requestRate[key]=GetGameTimer()+700
    local ok,result= cargoAction(src,tostring(action),runId,truckIndex,cargoId)
    return {ok=ok==true,message=ok and result or nil,error=ok and nil or result,duration=tostring(action)=='breach_start'and(runtime and runtime.settings.breachSeconds or settings().breachSeconds)or nil}
end)

lib.callback.register('cm-law:server:arsenalUnload',function(src,action,runId,truckIndex,netId)
    local member,cid,why=armyMember(src,'law.logistics.deliver');if not member then return {ok=false,error=why} end
    local run=MySQL.single.await('SELECT * FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1',{runId});if not run or run.state~='WAREHOUSE_UNLOADING' then return {ok=false,error='The convoy is not at the warehouse.'} end
    truckIndex=tonumber(truckIndex);local route=routeById(run.route_id);local ped=GetPlayerPed(src);local entity=vehicleFor(runId,truckIndex)
    if not route or not ped or ped==0 or GetEntityHealth(ped)<=0 or IsEntityDead(ped) or not entity or tonumber(netId)~=NetworkGetNetworkIdFromEntity(entity) or #(GetEntityCoords(entity)-vector3(route.destination.x,route.destination.y,route.destination.z))>(tonumber(A.ArrivalRadius)or 28) or #(GetEntityCoords(ped)-GetEntityCoords(entity))>(tonumber(A.InteractionDistance)or 2.5)+5.0 then return {ok=false,error='Move with the cargo truck to the configured Army warehouse.'} end
    local vehicleState=Entity(entity).state.cmArsenalResupply;if type(vehicleState)~='table' or vehicleState.role~='cargo' then return {ok=false,error='This is not an Arsenal cargo truck.'} end
    if action=='start' then
        local changed=MySQL.update.await([[UPDATE cm_legal_arsenal_trucks SET unloading_by_cid=?,unloading_started_at=NOW()
            WHERE run_id=? AND truck_index=? AND unloaded_at IS NULL AND (unloading_by_cid IS NULL OR unloading_started_at<?)]],{tostring(cid),runId,truckIndex,os.date('%Y-%m-%d %H:%M:%S',now()-settings().unloadSeconds)})
        return {ok=tonumber(changed)==1,message='Unloading started.',duration=settings().unloadSeconds,error=tonumber(changed)==1 and nil or 'This truck is already unloading.'}
    end
    local ok,result=lock('unload:'..runId..':'..truckIndex,function()
        local unload=MySQL.single.await('SELECT unloading_by_cid,UNIX_TIMESTAMP(unloading_started_at) started_at,unloaded_at FROM cm_legal_arsenal_trucks WHERE run_id=? AND truck_index=?',{runId,truckIndex})
        if not unload or unload.unloaded_at or tostring(unload.unloading_by_cid)~=tostring(cid) or now()-(tonumber(unload.started_at)or 0)<settings().unloadSeconds then return false,'Truck unloading is not complete.' end
        local rows=MySQL.query.await("SELECT * FROM cm_legal_arsenal_cargo WHERE run_id=? AND truck_index=? AND state IN ('on_truck','available')",{runId,truckIndex}) or {}
        for _,row in ipairs(rows) do
            local applied=stockMutation(runId,row.item_name,row.quantity,'add','unload:'..tostring(row.id));if not applied then return false,'Army stock credit failed safely.' end
            MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET state='delivered',credit_state='credited' WHERE id=? AND state IN ('on_truck','available','dropped')",{row.id})
        end
        MySQL.update.await('UPDATE cm_legal_arsenal_trucks SET unloaded_at=NOW() WHERE run_id=? AND truck_index=? AND unloaded_at IS NULL',{runId,truckIndex});cargoInvariant(runId,'truck_unloaded')
        local remaining=tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_legal_arsenal_cargo WHERE run_id=? AND state IN ('on_truck','available','dropped','carried','wrecked')",{runId})or 0)
        if remaining==0 then return finish(runId,'COMPLETED','all_cargo_resolved') end
        return true,'Truck unloading completed; unresolved cargo remains in play.'
    end)
    return {ok=ok==true,message=ok and 'Army warehouse unloading completed.' or nil,error=ok and nil or result}
end)
lib.callback.register('cm-law:server:arsenalRecover',function(src,runId,cargoId)
    local member,cid,why=armyMember(src,'law.logistics.recover');if not member then return {ok=false,error=why} end
    local row=MySQL.single.await("SELECT * FROM cm_legal_arsenal_cargo WHERE id=? AND run_id=? AND state IN ('wrecked','dropped')",{cargoId,runId});if not row then return {ok=false,error='Dropped cargo is unavailable.'} end
    if not cargoPointNear(src,row) then return {ok=false,error='Move to the saved wreck location.'} end
    local ok,result=lock('recover:'..runId..':'..cargoId,function()
        local applied=stockMutation(runId,row.item_name,row.quantity,'add','recovery:'..tostring(row.id));if not applied then return false,'Army stock recovery failed safely.' end
        local changed=MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET state='delivered',credit_state='credited' WHERE id=? AND state IN ('wrecked','dropped')",{row.id});if tonumber(changed)==1 then cargoInvariant(runId,'army_recovered');finishIfResolved(runId) end;return tonumber(changed)==1,'Cargo secured into Army warehouse stock.'
    end)
    return {ok=ok==true,message=ok and result or nil,error=ok and nil or result}
end)

local function reconcile()
    if not ready then return end
    for _,row in ipairs(MySQL.query.await("SELECT * FROM cm_legal_arsenal_cargo WHERE state='extracted' AND credit_state='pending' LIMIT 50") or {}) do
        if GetResourceState('cm-gang')=='started' then
            local success=exports['cm-gang']:AddGangArmoryStock(row.extracted_gang_id,row.item_name,row.quantity,{operationId=row.credit_operation_id,runId=row.run_id,cargoId=row.id})
            if success==true then MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET credit_state='credited',credited_at=NOW() WHERE id=? AND state='extracted'",{row.id}) end
        end
    end
    for _,row in ipairs(MySQL.query.await("SELECT * FROM cm_legal_arsenal_cargo WHERE state='carried'") or {}) do
        local src=tonumber(row.carrier_source);        local alive = src and GetPlayerName(src) and GetPlayerPed(src) ~= 0 and GetEntityHealth(GetPlayerPed(src)) > 0
        if not alive then
            MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET state='dropped',carrier_cid=NULL,carrier_source=NULL,expires_at=FROM_UNIXTIME(?) WHERE id=? AND state='carried'",{now()+tonumber(A.DroppedExpirySeconds or 1800),row.id})
        end
    end
    for _,row in ipairs(MySQL.query.await("SELECT * FROM cm_legal_arsenal_cargo WHERE state IN ('dropped','wrecked') AND expires_at<=NOW()") or {}) do MySQL.update.await("UPDATE cm_legal_arsenal_cargo SET state='expired' WHERE id=? AND state IN ('dropped','wrecked')",{row.id});finishIfResolved(row.run_id) end
end
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_settings(setting_key VARCHAR(32) PRIMARY KEY,setting_json LONGTEXT NOT NULL,updated_by VARCHAR(64),updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_manifest(id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,item_name VARCHAR(80) NOT NULL,quantity INT UNSIGNED NOT NULL,crate_size INT UNSIGNED NOT NULL DEFAULT 1,value_weight INT UNSIGNED NOT NULL,enabled TINYINT(1) NOT NULL DEFAULT 1,updated_by VARCHAR(64),UNIQUE KEY uq_arsenal_manifest_item(item_name))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_routes(route_id VARCHAR(48) PRIMARY KEY,label VARCHAR(96) NOT NULL,intel_text VARCHAR(160) NOT NULL,start_x DOUBLE NOT NULL,start_y DOUBLE NOT NULL,start_z DOUBLE NOT NULL,start_h FLOAT NOT NULL DEFAULT 0,destination_x DOUBLE NOT NULL,destination_y DOUBLE NOT NULL,destination_z DOUBLE NOT NULL,destination_h FLOAT NOT NULL DEFAULT 0,waypoints_json LONGTEXT NULL,routing_bucket INT NOT NULL DEFAULT 0,enabled TINYINT(1) NOT NULL DEFAULT 1,updated_by VARCHAR(64),updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]])
    MySQL.query.await([[ALTER TABLE cm_legal_arsenal_manifest ADD COLUMN IF NOT EXISTS crate_size INT UNSIGNED NOT NULL DEFAULT 1 AFTER quantity]])
    MySQL.query.await([[ALTER TABLE cm_legal_arsenal_routes ADD COLUMN IF NOT EXISTS waypoints_json LONGTEXT NULL AFTER destination_h]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_extraction_points(id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,gang_id VARCHAR(32) NULL,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,radius FLOAT NOT NULL DEFAULT 4,routing_bucket INT NOT NULL DEFAULT 0,enabled TINYINT(1) NOT NULL DEFAULT 1,updated_by VARCHAR(64),KEY idx_arsenal_extract_enabled(enabled))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_runs(run_id VARCHAR(80) PRIMARY KEY,state VARCHAR(32) NOT NULL,scheduled_at TIMESTAMP NULL,warmup_at TIMESTAMP NULL,preparation_at TIMESTAMP NULL,active_at TIMESTAMP NULL,ended_at TIMESTAMP NULL,route_id VARCHAR(48) NOT NULL,manifest_json LONGTEXT NOT NULL,config_snapshot LONGTEXT NOT NULL,vehicles_json LONGTEXT NULL,total_value BIGINT UNSIGNED NOT NULL DEFAULT 0,delivered_value BIGINT UNSIGNED NOT NULL DEFAULT 0,stolen_value BIGINT UNSIGNED NOT NULL DEFAULT 0,lost_value BIGINT UNSIGNED NOT NULL DEFAULT 0,army_stock_applied TINYINT(1) NOT NULL DEFAULT 0,end_reason VARCHAR(96),result_json LONGTEXT NULL,quick_available_until TIMESTAMP NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,KEY idx_arsenal_run_state(state),KEY idx_arsenal_run_quick(quick_available_until))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_cargo(id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,run_id VARCHAR(80) NOT NULL,truck_index TINYINT UNSIGNED NOT NULL,item_name VARCHAR(80) NOT NULL,quantity INT UNSIGNED NOT NULL,value_weight INT UNSIGNED NOT NULL,state VARCHAR(16) NOT NULL DEFAULT 'on_truck',carrier_cid VARCHAR(64),carrier_source INT,extracted_gang_id VARCHAR(32),credit_state VARCHAR(16) NOT NULL DEFAULT 'none',credit_operation_id VARCHAR(128),credited_at TIMESTAMP NULL,extracted_at TIMESTAMP NULL,x DOUBLE,y DOUBLE,z DOUBLE,bucket INT NOT NULL DEFAULT 0,expires_at TIMESTAMP NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,UNIQUE KEY uq_arsenal_credit(credit_operation_id),KEY idx_arsenal_cargo_state(run_id,state))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_participants(run_id VARCHAR(80) NOT NULL,gang_id VARCHAR(32) NOT NULL,first_character_id VARCHAR(64) NOT NULL,stolen_value BIGINT UNSIGNED NOT NULL DEFAULT 0,cargo_count INT UNSIGNED NOT NULL DEFAULT 0,joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(run_id,gang_id))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_stock_ledger(operation_id VARCHAR(160) PRIMARY KEY,run_id VARCHAR(80) NOT NULL,item_name VARCHAR(80) NOT NULL,quantity INT UNSIGNED NOT NULL,direction VARCHAR(8) NOT NULL,status VARCHAR(16) NOT NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,KEY idx_arsenal_stock_run(run_id))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_arsenal_trucks(run_id VARCHAR(80) NOT NULL,truck_index TINYINT UNSIGNED NOT NULL,breach_by_cid VARCHAR(64),breach_started_at TIMESTAMP NULL,unloading_by_cid VARCHAR(64),unloading_started_at TIMESTAMP NULL,unloaded_at TIMESTAMP NULL,PRIMARY KEY(run_id,truck_index))]])
    -- Any live Phase 5 run cannot safely resume after a cm-law restart:
    -- reconcile the reservation and preserve an explicit interrupted result.
    for _,row in ipairs(MySQL.query.await("SELECT run_id FROM cm_legal_arsenal_runs WHERE state IN ('WARMUP','ARMY_PREPARATION','CONVOY_ACTIVE','WAREHOUSE_UNLOADING','ENDING')") or {}) do
        releaseUnsettled(row.run_id)
        local totals=MySQL.single.await([[SELECT
            COALESCE(SUM(CASE WHEN state='delivered' THEN quantity*value_weight ELSE 0 END),0) delivered,
            COALESCE(SUM(CASE WHEN state='extracted' THEN quantity*value_weight ELSE 0 END),0) stolen,
            COALESCE(SUM(CASE WHEN state='expired' THEN quantity*value_weight ELSE 0 END),0) lost
            FROM cm_legal_arsenal_cargo WHERE run_id=?]],{row.run_id}) or {}
        MySQL.update.await([[UPDATE cm_legal_arsenal_runs SET state='INTERRUPTED',ended_at=NOW(),
            end_reason='resource_or_server_restart',delivered_value=?,stolen_value=?,lost_value=?,
            result_json=?,quick_available_until=DATE_ADD(NOW(),INTERVAL ? SECOND) WHERE run_id=?]],
            {tonumber(totals.delivered)or 0,tonumber(totals.stolen)or 0,tonumber(totals.lost)or 0,
             json.encode({reason='resource_or_server_restart'}),settings().resultQuickViewSeconds,row.run_id})
    end
    ready=true;reconcile()
end)
CreateThread(function()
    while true do
        Wait(tonumber(A.ReconcileIntervalMs) or 3000)
        reconcile()
        if runtime and (runtime.state == 'CONVOY_ACTIVE' or runtime.state == 'WAREHOUSE_UNLOADING') then
            if runtime.settings.intelEnabled and now()>=(runtime.nextIntelAt or 0) then
                runtime.nextIntelAt=now()+runtime.settings.intelIntervalSeconds
                if GetResourceState('cm-gang')=='started' then pcall(function() exports['cm-gang']:SendArsenalResupplyIntel({eventId=runtime.id,text=clean(runtime.route.intel or 'Convoy sighting reported in the area.',160),radius=runtime.settings.approximateSearchRadius}) end) end
            end
            for _,vehicleSpec in ipairs(runtime.vehicles or {}) do
                local index=tonumber(vehicleSpec.truckIndex)
                local entity = vehicleFor(runtime.id, index)
                if entity then
                    missingVehicles[index] = nil
                    local position = GetEntityCoords(entity)
                    runtime.positions[index] = { x=position.x, y=position.y, z=position.z, bucket=GetEntityRoutingBucket(entity) }
                    if GetVehicleEngineHealth(entity) <= 0 or GetEntityHealth(entity) <= 0 then
                        local c = runtime.positions[index]
                        MySQL.update.await([[UPDATE cm_legal_arsenal_cargo SET state='wrecked',
                            x=?,y=?,z=?,bucket=?,expires_at=FROM_UNIXTIME(?)
                            WHERE run_id=? AND truck_index=? AND state IN ('on_truck','available')]],
                            { c.x, c.y, c.z, GetEntityRoutingBucket(entity),
                              now() + tonumber(A.CargoExpirySeconds or 1800), runtime.id, index })
                    end
                else
                    missingVehicles[index] = missingVehicles[index] or GetGameTimer()
                    if GetGameTimer() - missingVehicles[index] > 10000 then
                        MySQL.update.await([[UPDATE cm_legal_arsenal_cargo SET state='wrecked',
                            x=?,y=?,z=?,bucket=?,expires_at=FROM_UNIXTIME(?) WHERE run_id=? AND truck_index=?
                            AND state IN ('on_truck','available')]],
                            { runtime.positions[index] and runtime.positions[index].x,
                              runtime.positions[index] and runtime.positions[index].y,
                              runtime.positions[index] and runtime.positions[index].z,
                              runtime.positions[index] and runtime.positions[index].bucket or 0,
                              now() + tonumber(A.CargoExpirySeconds or 1800), runtime.id, index })
                        missingVehicles[index] = nil
                    end
                end
            end
            local destination = runtime.route.destination
            if runtime.state=='CONVOY_ACTIVE' then
              for _, row in ipairs(vehicleRows(runtime.id)) do
                local state=Entity(row.entity).state.cmArsenalResupply
                if type(state)=='table' and state.role=='cargo' and #(GetEntityCoords(row.entity) - vector3(destination.x, destination.y, destination.z)) <= (tonumber(A.ArrivalRadius) or 28) then
                    runtime.state = 'WAREHOUSE_UNLOADING'
                    MySQL.update.await([[UPDATE cm_legal_arsenal_runs SET state='WAREHOUSE_UNLOADING'
                        WHERE run_id=? AND state='CONVOY_ACTIVE']], { runtime.id })
                    notifyArmy('Arsenal Resupply convoy reached the warehouse. Army unloading authority is required.', 'inform')
                    break
                end
              end
            end
            local remaining = MySQL.scalar.await([[SELECT COUNT(*) FROM cm_legal_arsenal_cargo
                WHERE run_id=? AND state IN ('on_truck','available','dropped','carried')]], { runtime.id }) or 0
            if #vehicleRows(runtime.id) == 0 and tonumber(remaining) == 0 then
                runtime.state = 'WAREHOUSE_UNLOADING'
                MySQL.update.await([[UPDATE cm_legal_arsenal_runs SET state='WAREHOUSE_UNLOADING'
                    WHERE run_id=? AND state='CONVOY_ACTIVE']], { runtime.id })
            end
        end
    end
end)
CreateThread(function() while not ready do Wait(500) end;while true do local cfg=settings();if cfg.dailyEnabled and cfg.enabled then local date=os.date('*t');if date.hour==cfg.hour and date.min==cfg.minute then startRun(nil,true) end end;Wait(15000) end end)

exports('AdminGetArsenalResupply',function(src)
    if not admin(src) then return {ok=false,error='Permission denied.'} end
    local cfg=settings();return {ok=true,settings=cfg,manifest=manifest(),routes=routes(),extractionPoints=extractions(),state=runtime and runtime.state or 'IDLE',runId=runtime and runtime.id or nil,nextStartAt=nextOccurrence(cfg),presentation=A.Presentation}
end)
exports('AdminConfigureArsenalResupply',function(src,data)
    if not admin(src) or type(data)~='table' then return false,'permission_denied' end
    local cfg=settings();local saved={enabled=data.enabled==true,dailySchedule={enabled=data.dailyEnabled==true,hour=math.max(0,math.min(23,math.floor(tonumber(data.hour)or cfg.hour))),minute=math.max(0,math.min(59,math.floor(tonumber(data.minute)or cfg.minute)))},warmupSeconds=math.max(30,math.min(1800,math.floor(tonumber(data.warmupSeconds)or cfg.warmupSeconds))),minimumArmyOnline=math.max(1,math.min(100,math.floor(tonumber(data.minimumArmyOnline)or cfg.minimumArmyOnline))),preparationSeconds=math.max(10,math.min(1800,math.floor(tonumber(data.preparationSeconds)or cfg.preparationSeconds))),maximumDurationSeconds=math.max(300,math.min(14400,math.floor(tonumber(data.maximumDurationSeconds)or cfg.maximumDurationSeconds))),intelIntervalSeconds=math.max(30,math.min(300,math.floor(tonumber(data.intelIntervalSeconds)or cfg.intelIntervalSeconds))),unloadSeconds=math.max(5,math.min(300,math.floor(tonumber(data.unloadSeconds)or cfg.unloadSeconds))),resultQuickViewSeconds=math.max(10,math.min(300,math.floor(tonumber(data.resultQuickViewSeconds)or cfg.resultQuickViewSeconds))),leadEscortCount=math.max(0,math.min(3,math.floor(tonumber(data.leadEscortCount)or cfg.leadEscortCount))),cargoTruckCount=math.max(1,math.min(3,math.floor(tonumber(data.cargoTruckCount)or cfg.cargoTruckCount))),rearEscortCount=math.max(0,math.min(3,math.floor(tonumber(data.rearEscortCount)or cfg.rearEscortCount))),intelEnabled=data.intelEnabled==true,approximateSearchRadius=math.max(200,math.min(1000,tonumber(data.approximateSearchRadius)or cfg.approximateSearchRadius)),maxStoppedSpeed=math.max(.05,math.min(3,tonumber(data.maxStoppedSpeed)or cfg.maxStoppedSpeed)),interactionDistance=math.max(1,math.min(5,tonumber(data.interactionDistance)or cfg.interactionDistance)),breachSeconds=math.max(5,math.min(180,math.floor(tonumber(data.breachSeconds)or cfg.breachSeconds)))}
    MySQL.query.await([[INSERT INTO cm_legal_arsenal_settings(setting_key,setting_json,updated_by) VALUES('main',?,?) ON DUPLICATE KEY UPDATE setting_json=VALUES(setting_json),updated_by=VALUES(updated_by)]],{json.encode(saved),sourceCharacter(src)})
    TriggerEvent('cm-admin:server:addLog',src,'arsenal_resupply_settings_updated',{category='orgs'});return true,'Arsenal Resupply settings saved.'
end)
exports('AdminSaveArsenalManifest',function(src,data)
    if not admin(src) or type(data)~='table' then return false,'permission_denied' end
    local row={data};local valid,why=validateManifest(row);if not valid then return false,why end
    local item=tostring(data.item or data.itemName):lower();MySQL.query.await([[INSERT INTO cm_legal_arsenal_manifest(item_name,quantity,crate_size,value_weight,enabled,updated_by) VALUES(?,?,?,?,1,?) ON DUPLICATE KEY UPDATE quantity=VALUES(quantity),crate_size=VALUES(crate_size),value_weight=VALUES(value_weight),enabled=1,updated_by=VALUES(updated_by)]],{item,math.floor(data.quantity),math.floor(data.crateSize),math.floor(data.valueWeight),sourceCharacter(src)});return true,'Manifest line saved.'
end)
exports('GetArsenalResupplyPresentation',function(src)
    local cid=sourceCharacter(src);if not cid or GetResourceState('cm-gang')~='started'then return{ok=false,reason='not_in_gang'}end
    local member=exports['cm-gang']:GetGangForCharacter(cid);if type(member)~='table'or member.enabled~=true then return{ok=false,reason='not_in_gang'}end
    local cfg=settings();local state=runtime and runtime.state or'IDLE';local historyRows=MySQL.query.await([[SELECT r.run_id FROM cm_legal_arsenal_runs r JOIN cm_legal_arsenal_participants p ON p.run_id=r.run_id WHERE p.gang_id=? AND r.state IN ('COMPLETED','CANCELLED','INTERRUPTED') ORDER BY r.ended_at DESC LIMIT 12]],{member.gangId})or{};local history={}
    for _,row in ipairs(historyRows)do local result=resultPayload(row.run_id);if result then history[#history+1]=result end end
    return{ok=true,serverTime=now(),event=A.Presentation,runtime={state=state,nextStartAt=nextOccurrence(cfg),warmupStartsAt=nextOccurrence(cfg),endsAt=runtime and runtime.endsAt or nil,duration=cfg.maximumDurationSeconds},history=history}
end)
exports('GetArsenalResupplyHistory',function(src)
    local member,_,why=armyMember(src);if not member then return{ok=false,error=why}end
    local rows=MySQL.query.await([[SELECT run_id,state,UNIX_TIMESTAMP(scheduled_at) started_at,UNIX_TIMESTAMP(ended_at) ended_at,total_value,delivered_value,stolen_value,lost_value,end_reason FROM cm_legal_arsenal_runs ORDER BY created_at DESC LIMIT 25]])or{};local out={}
    for _,row in ipairs(rows)do local total=tonumber(row.total_value)or 0;local function pct(v)return total>0 and math.floor(((tonumber(v)or 0)*1000/total)+.5)/10 or 0 end;local result=resultPayload(row.run_id);out[#out+1]={eventId=row.run_id,eventType=EVENT_TYPE,title=A.Presentation.title,status=row.state,startedAt=tonumber(row.started_at),endedAt=tonumber(row.ended_at),totalValue=total,armyValue=tonumber(row.delivered_value)or 0,gangValue=tonumber(row.stolen_value)or 0,lostValue=tonumber(row.lost_value)or 0,armyPercent=pct(row.delivered_value),gangPercent=pct(row.stolen_value),lostPercent=pct(row.lost_value),reason=row.end_reason,standings=result and result.standings or{}}end
    return{ok=true,history=out,presentation=A.Presentation}
end)
lib.callback.register('cm-law:server:arsenalHistory',function(src)
    return exports['cm-law']:GetArsenalResupplyHistory(src)
end)
exports('AdminDeleteArsenalManifest',function(src,item)if not admin(src)then return false,'permission_denied'end;item=tostring(item or''):lower();local changed=MySQL.update.await('UPDATE cm_legal_arsenal_manifest SET enabled=0,updated_by=? WHERE item_name=?',{sourceCharacter(src),item});return tonumber(changed)>0,tonumber(changed)>0 and'Manifest line disabled.'or'manifest_not_found'end)
exports('AdminCaptureArsenalRoutePoint',function(src,routeId,point,data)
    if not admin(src) then return false,'permission_denied' end
    local ped=GetPlayerPed(src);if not ped or ped==0 then return false,'admin_entity_unavailable' end
    if GetPlayerRoutingBucket(src) ~= 0 then return false,'route_capture_requires_normal_world' end
    local c=GetEntityCoords(ped);local h=GetEntityHeading(ped);routeId=clean(routeId,48);point=tostring(point or '')
    if routeId=='' or (point~='start' and point~='destination' and point~='waypoint_add' and point~='waypoint_remove') then return false,'invalid_route_point' end
    local current=MySQL.single.await('SELECT * FROM cm_legal_arsenal_routes WHERE route_id=? LIMIT 1',{routeId}) or {};local start=current.start_x and {current.start_x,current.start_y,current.start_z,current.start_h} or {c.x,c.y,c.z,h};local dest=current.destination_x and {current.destination_x,current.destination_y,current.destination_z,current.destination_h} or {c.x,c.y,c.z,h};local waypoints=decode(current.waypoints_json,{})
    if point=='start'then start={c.x,c.y,c.z,h}elseif point=='destination'then dest={c.x,c.y,c.z,h}elseif point=='waypoint_add'then if #waypoints>=12 then return false,'waypoint_limit_reached'end;waypoints[#waypoints+1]={x=c.x,y=c.y,z=c.z,h=h}elseif point=='waypoint_remove'then local index=math.floor(tonumber(data and data.index)or 0);if index<1 or index>#waypoints then return false,'invalid_waypoint'end;table.remove(waypoints,index)end
    MySQL.query.await([[INSERT INTO cm_legal_arsenal_routes(route_id,label,intel_text,start_x,start_y,start_z,start_h,destination_x,destination_y,destination_z,destination_h,waypoints_json,routing_bucket,enabled,updated_by) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,1,?) ON DUPLICATE KEY UPDATE start_x=VALUES(start_x),start_y=VALUES(start_y),start_z=VALUES(start_z),start_h=VALUES(start_h),destination_x=VALUES(destination_x),destination_y=VALUES(destination_y),destination_z=VALUES(destination_z),destination_h=VALUES(destination_h),waypoints_json=VALUES(waypoints_json),updated_by=VALUES(updated_by)]],{routeId,current.label or routeId,current.intel_text or 'Approximate route intelligence available.',start[1],start[2],start[3],start[4],dest[1],dest[2],dest[3],dest[4],json.encode(waypoints),tonumber(GetPlayerRoutingBucket(src))or 0,sourceCharacter(src)});return true,'Route updated.'
end)
exports('AdminDeleteArsenalRoute',function(src,routeId)if not admin(src)then return false,'permission_denied'end;local changed=MySQL.update.await('UPDATE cm_legal_arsenal_routes SET enabled=0,updated_by=? WHERE route_id=?',{sourceCharacter(src),clean(routeId,48)});return tonumber(changed)>0,tonumber(changed)>0 and'Route disabled.'or'route_not_found'end)
exports('AdminCaptureArsenalExtractionPoint',function(src,data)
    if not admin(src) or type(data)~='table' then return false,'permission_denied' end
    local ped=GetPlayerPed(src);if not ped or ped==0 then return false,'admin_entity_unavailable' end;local c=GetEntityCoords(ped);local gangId=data.gangId and tostring(data.gangId)or nil;if gangId and GetResourceState('cm-gang')=='started' and not exports['cm-gang']:IsFixedGangId(gangId) then return false,'invalid_gang_id'end
    MySQL.insert.await('INSERT INTO cm_legal_arsenal_extraction_points(gang_id,x,y,z,radius,routing_bucket,enabled,updated_by) VALUES(?,?,?,?,?,?,1,?)',{gangId,c.x,c.y,c.z,math.max(2,math.min(15,tonumber(data.radius)or 4)),GetPlayerRoutingBucket(src),sourceCharacter(src)});return true,'Extraction point captured.'
end)
exports('AdminDeleteArsenalExtractionPoint',function(src,id)if not admin(src)then return false,'permission_denied'end;local changed=MySQL.update.await('UPDATE cm_legal_arsenal_extraction_points SET enabled=0,updated_by=? WHERE id=?',{sourceCharacter(src),math.floor(tonumber(id)or 0)});return tonumber(changed)>0,tonumber(changed)>0 and'Extraction point disabled.'or'extraction_not_found'end)
exports('AdminStartArsenalResupply',function(src) return startRun(src,false) end)
exports('AdminCancelArsenalResupply',function(src) if not admin(src) then return false,'permission_denied' end;if not runtime then return false,'no_active_event'end;return finish(runtime.id,'CANCELLED','admin_cancel') end)
exports('GetArsenalResupplyQuickResult',function(src,eventId)
    local cid=sourceCharacter(src);if not cid or GetResourceState('cm-gang')~='started' then return {ok=false,reason='result_unavailable'} end
    local member=exports['cm-gang']:GetGangForCharacter(cid);local participantRow=member and MySQL.scalar.await('SELECT 1 FROM cm_legal_arsenal_participants WHERE run_id=? AND gang_id=? LIMIT 1',{eventId,member.gangId});local run=MySQL.single.await("SELECT quick_available_until FROM cm_legal_arsenal_runs WHERE run_id=? AND state IN ('COMPLETED','CANCELLED','INTERRUPTED') LIMIT 1",{eventId})
    if not participantRow or not run or not run.quick_available_until or tostring(run.quick_available_until)=='' then return {ok=false,reason='result_unavailable'} end
    local untilAt=MySQL.scalar.await('SELECT UNIX_TIMESTAMP(quick_available_until) FROM cm_legal_arsenal_runs WHERE run_id=?',{eventId});if tonumber(untilAt or 0)<=now() then return {ok=false,reason='result_expired'} end;return {ok=true,availableUntil=tonumber(untilAt),result=resultPayload(eventId)}
end)
exports('GetLatestArsenalResupplyQuickResult',function(src)
    local cid=sourceCharacter(src);if not cid or GetResourceState('cm-gang')~='started' then return {ok=false,reason='result_unavailable'} end
    local member=exports['cm-gang']:GetGangForCharacter(cid);if not member then return {ok=false,reason='result_unavailable'} end
    local row=MySQL.single.await([[SELECT p.run_id,r.quick_available_until FROM cm_legal_arsenal_participants p
        JOIN cm_legal_arsenal_runs r ON r.run_id=p.run_id
        WHERE p.gang_id=? AND r.quick_available_until>NOW()
        ORDER BY r.ended_at DESC LIMIT 1]],{member.gangId})
    if not row then return {ok=false,reason='result_unavailable'} end
    local untilAt=MySQL.scalar.await('SELECT UNIX_TIMESTAMP(quick_available_until) FROM cm_legal_arsenal_runs WHERE run_id=?',{row.run_id})
    return {ok=true,eventId=row.run_id,availableUntil=tonumber(untilAt),result=resultPayload(row.run_id)}
end)
local function commandReply(src,text,kind)
    if tonumber(src)==0 then print('[cm-law] '..tostring(text)) else TriggerClientEvent('cm-hud:client:notify',src,tostring(text),kind or'inform') end
end
local function arsenalStatus()
    if not runtime then local cfg=settings();return ('ARSENAL RESUPPLY | State: IDLE | Run: none | Eligible Army: %d | Required Army: %d | Next: %s'):format(onlineArmyCount(),cfg.minimumArmyOnline,tostring(nextOccurrence(cfg)or'not_scheduled')) end
    local run=MySQL.single.await([[SELECT total_value,route_id,
        COALESCE((SELECT SUM(quantity*value_weight) FROM cm_legal_arsenal_cargo WHERE run_id=? AND state='delivered'),0) army_value,
        COALESCE((SELECT SUM(quantity*value_weight) FROM cm_legal_arsenal_cargo WHERE run_id=? AND state='extracted'),0) gang_value,
        COALESCE((SELECT SUM(quantity*value_weight) FROM cm_legal_arsenal_cargo WHERE run_id=? AND state='expired'),0) lost_value,
        COALESCE((SELECT SUM(quantity*value_weight) FROM cm_legal_arsenal_cargo WHERE run_id=? AND state IN ('on_truck','available','carried','dropped','wrecked')),0) unresolved_value,
        (SELECT COUNT(*) FROM cm_legal_arsenal_trucks WHERE run_id=?) cargo_trucks
        FROM cm_legal_arsenal_runs WHERE run_id=? LIMIT 1]],{runtime.id,runtime.id,runtime.id,runtime.id,runtime.id,runtime.id})or{}
    return ('ARSENAL RESUPPLY | Run: %s | State: %s | Route: %s | Eligible Army: %d | Vehicles: %d | Cargo trucks: %d | Incoming: %d | Army secured: %d | Gang extracted: %d | Lost: %d | Unresolved: %d'):format(runtime.id,runtime.state,tostring(run.route_id or runtime.route.id),onlineArmyCount(),#vehicleRows(runtime.id),tonumber(run.cargo_trucks)or 0,tonumber(run.total_value)or 0,tonumber(run.army_value)or 0,tonumber(run.gang_value)or 0,tonumber(run.lost_value)or 0,tonumber(run.unresolved_value)or 0)
end
RegisterCommand('cm_arsenal_start',function(src)
    local ok,why=startRun(src,false)
    if not ok and why=='minimum_army_online_not_met'then local cfg=settings();commandReply(src,('ARSENAL START REFUSED | Eligible Army: %d | Required Army: %d'):format(onlineArmyCount(),cfg.minimumArmyOnline),'error')else commandReply(src,('ARSENAL START %s | %s'):format(ok and'ACCEPTED'or'REFUSED',tostring(why)),ok and'success'or'error')end
end,false)
RegisterCommand('cm_arsenal_cancel',function(src)
    if not admin(src)then return end
    if not runtime then return commandReply(src,'ARSENAL CANCEL REFUSED | No active event.','error')end
    local runId=runtime.id;local ok=finish(runId,'CANCELLED','admin_cancel');commandReply(src,('ARSENAL CANCEL %s | Run: %s'):format(ok and'ACCEPTED'or'FAILED',runId),ok and'success'or'error')
end,false)
RegisterCommand('cm_arsenal_status',function(src)if src~=0 and not admin(src)then return end;commandReply(src,arsenalStatus())end,false)
RegisterCommand('cm_arsenal_capture_route',function(src,args) if src>0 then exports['cm-law']:AdminCaptureArsenalRoutePoint(src,args[1],args[2]) end end,false)
RegisterCommand('cm_arsenal_capture_extraction',function(src,args) if src>0 then exports['cm-law']:AdminCaptureArsenalExtractionPoint(src,{gangId=args[1]}) end end,false)
RegisterCommand('cm_arsenal_check',function(src,args)
    if src~=0 and not admin(src)then return end
    local runId=clean(args[1]or(runtime and runtime.id),80)
    if runId==''then return commandReply(src,'ARSENAL INVARIANT FAILED | No active run and no run ID supplied.','error')end
    local ok=cargoInvariant(runId,'admin_check');commandReply(src,('ARSENAL INVARIANT %s | Run: %s'):format(ok and'PASS'or'FAILED',runId),ok and'success'or'error')
end,false)
