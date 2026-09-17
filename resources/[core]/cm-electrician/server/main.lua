local Config = CMElectrician.Config
CMElectrician.Server = CMElectrician.Server or {}

local PLAYERDATA = 'cm-playerdata'
local VEHICLES = 'cm-vehicles'

local employed = {}
local cooldowns = {}
local outageActive = false
local outageLocation = nil
local jobVehicles = {} -- [src] = { plate = ..., netId = ... }

local function dbg(...)
    if Config.Debug then print('[CM-ELECTRICIAN]', ...) end
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-electrician:client:notify', src, tostring(message or ''), kind or 'info')
end

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

local function getMeta(src, key, default)
    local api = playerData()
    if not api then return default end
    local ok, value = pcall(function() return api:GetMetadata(src, key) end)
    if ok and value ~= nil then return value end
    return default
end

local function setMeta(src, key, value)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:SetMetadata(src, key, value) end)
    return ok and result == true
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:AddCash(src, amount, reason) end)
    return ok and result == true
end

local function getStatus(src)
    return {
        level = math.max(1, math.floor(tonumber(getMeta(src, 'cmElectricianLevel', 1)) or 1)),
        panels = math.max(0, math.floor(tonumber(getMeta(src, 'cmElectricianPanels', 0)) or 0)),
        plates = math.max(0, math.floor(tonumber(getMeta(src, 'cmElectricianPlates', 0)) or 0)),
    }
end

local function onCooldown(src)
    local now = GetGameTimer()
    if (cooldowns[src] or 0) > now then return true end
    cooldowns[src] = now + (tonumber(Config.Security.actionCooldownMs) or 900)
    return false
end

local function pickRandomLocation(list, exclude)
    if #list <= 1 then return list[1] end
    local pick
    repeat
        pick = list[math.random(1, #list)]
    until pick ~= exclude
    return pick
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

local function vehiclesApi()
    if GetResourceState(VEHICLES) ~= 'started' then return nil end
    return exports[VEHICLES]
end

local function deleteJobVehicle(src)
    local rec = jobVehicles[src]
    if not rec then return end
    jobVehicles[src] = nil
    local api = vehiclesApi()
    if api then pcall(function() api:DeleteAdminVehicle(rec.plate) end) end
end

-- Spawned through cm-vehicles' trusted-placement bridge (see its
-- Config.Placement.authorizedResources), which auto-assigns owner access
-- tied to the requesting player's own character -- the truck behaves like a
-- normal owned vehicle (locks, keys, engine) instead of a bare admin prop.
RegisterNetEvent('cm-electrician:server:requestServiceTruck', function(wantVehicle)
    local src = source
    wantVehicle = wantVehicle == true

    -- Returning/cleaning up a truck must work regardless of employment state
    -- or location -- e.g. the level-1 job-area leash or a manual resignation
    -- can fire while the player is off driving it somewhere else entirely.
    if not wantVehicle then
        if not jobVehicles[src] then return end
        deleteJobVehicle(src)
        TriggerClientEvent('cm-electrician:client:serviceTruck', src, false)
        notify(src, 'Service truck returned.', 'info')
        return
    end

    if not employed[src] then return end
    local rent = Config.RentVehicle
    local status = getStatus(src)
    if status.level < (tonumber(rent.unlockLevel) or 2) then return end

    -- Rental is now requested by talking to the switchboard NPC rather than
    -- walking to a separate point, so the proximity check is against the
    -- NPC's own location.
    local coords = playerCoords(src)
    if not coords then return end
    local npc = Config.NPC or {}
    local npcCoords = npc.coords or Config.Employment.coords
    local maxDistance = (tonumber(Config.Security.employmentDistance) or 3.0) + (tonumber(npc.interactDistance) or 3.0)
    if #(coords - vector3(npcCoords.x, npcCoords.y, npcCoords.z)) > maxDistance then
        notify(src, 'You are too far from the electrician foreman.', 'error')
        return
    end

    if jobVehicles[src] then return end

    -- Charged up front so a spawn failure or the vehicle bridge being
    -- offline can't leave the player billed with nothing to show for it --
    -- RemoveCash itself fails atomically if they can't afford it, and any
    -- failure past this point refunds via addCash.
    local rentCost = math.max(0, math.floor(tonumber(rent.cost) or 0))
    local billingApi = rentCost > 0 and playerData() or nil
    if rentCost > 0 then
        if not billingApi then
            notify(src, 'Vehicle service is unavailable.', 'error')
            return
        end
        local ok, removed = pcall(function() return billingApi:RemoveCash(src, rentCost, 'electrician_truck_rental') end)
        if not ok or removed ~= true then
            notify(src, ('You need $%d to rent the service truck.'):format(rentCost), 'error')
            return
        end
    end

    local api = vehiclesApi()
    if not api then
        notify(src, 'Vehicle service is unavailable.', 'error')
        if rentCost > 0 then addCash(src, rentCost, 'electrician_truck_rental_refund') end
        return
    end

    local spawn = rent.spawnCoords
    local ok, result = pcall(function()
        return api:SpawnAdminVehicle(src, rent.model, { x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.w }, {
            placementKind = 'car',
            label = 'Electrician Service Truck',
            engineOn = true,
            warp = true,
        })
    end)

    if not ok or type(result) ~= 'table' or result.ok ~= true then
        notify(src, 'The service truck could not be spawned.', 'error')
        if rentCost > 0 then addCash(src, rentCost, 'electrician_truck_rental_refund') end
        return
    end

    jobVehicles[src] = { plate = result.plate, netId = result.netId }
    TriggerClientEvent('cm-electrician:client:serviceTruck', src, true)
    notify(src, rentCost > 0
        and ('Service truck rented for $%d. Drive safe.'):format(rentCost)
        or 'Service truck ready. Drive safe.', 'success')
end)

-- Catches anyone who reconnects, restarts the resource, opens the job menu,
-- or gets set to level 3 by an admin command while an outage is already
-- active and unresolved -- otherwise only the exact moment it started or
-- they leveled up naturally notifies them.
local function checkOutageAlert(src, status)
    if employed[src] and outageActive and status.level >= (tonumber(Config.PowerOutage.unlockLevel) or 3) then
        TriggerClientEvent('cm-electrician:client:outageAlert', src, outageLocation)
    end
end

-- Tells bystanders near the fault the power just went out -- NOT the whole
-- city, only whoever happens to already be within the same radius the
-- blackout effect itself uses, so it reads as "this block lost power" rather
-- than a server-wide announcement. Level-3+ employed electricians are
-- skipped here since they're about to get checkOutageAlert's own "head to
-- your GPS" message right after -- otherwise they'd see two notifications.
local function notifyOutageStart()
    if not outageLocation then return end
    local unlockLevel = tonumber(Config.PowerOutage.unlockLevel) or 3
    local radius = tonumber(Config.PowerOutage.blackoutExitRadius) or 60.0

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local respondingElectrician = employed[src] and getStatus(src).level >= unlockLevel
        if not respondingElectrician then
            local coords = playerCoords(src)
            if coords and #(coords - outageLocation) <= radius then
                TriggerClientEvent('cm-electrician:client:notify', src,
                    'The power just went out around here.', 'info')
            end
        end
    end
end

-- No point blacking out a fault (and running its auto-fix countdown) when
-- nobody currently on duty could even respond to it.
local function hasOnlineResponder()
    local unlockLevel = tonumber(Config.PowerOutage.unlockLevel) or 3
    for src in pairs(employed) do
        if getStatus(src).level >= unlockLevel then return true end
    end
    return false
end

RegisterNetEvent('cm-electrician:server:requestStatus', function()
    local src = source
    local status = getStatus(src)
    TriggerClientEvent('cm-electrician:client:status', src, status)
    checkOutageAlert(src, status)
end)

RegisterNetEvent('cm-electrician:server:setEmployed', function(wantEmployed)
    local src = source
    wantEmployed = wantEmployed == true

    -- Starting the job requires standing at the switchboard; resigning (or
    -- being auto-released by the client-side level-1 job-area leash) does not,
    -- since the player may already be far away by the time that happens.
    if wantEmployed then
        local coords = playerCoords(src)
        if not coords then return end

        local maxDistance = (tonumber(Config.Security.employmentDistance) or 3.0) + (tonumber(Config.Employment.interactDistance) or 1.4)
        if #(coords - Config.Employment.coords) > maxDistance then
            TriggerClientEvent('cm-electrician:client:employedSet', src, employed[src] == true, 'You are too far from the switchboard.')
            return
        end
    end

    employed[src] = wantEmployed or nil
    TriggerClientEvent('cm-electrician:client:employedSet', src, employed[src] == true)
end)

RegisterNetEvent('cm-electrician:server:fixPanel', function(index)
    local src = source
    index = tonumber(index)
    local point = index and Config.Panels[index]
    if not employed[src] or not point then return end
    if onCooldown(src) then return end

    local coords = playerCoords(src)
    if not coords then return end
    if #(coords - point) > (tonumber(Config.Security.panelDistance) or 2.0) then
        notify(src, 'You are too far from the panel.', 'error')
        return
    end

    local status = getStatus(src)
    local panels = status.panels + 1
    setMeta(src, 'cmElectricianPanels', panels)

    local level, leveledUp = status.level, false
    if level < 2 and panels >= (tonumber(Config.LevelUp.panelsForLevel2) or 50) then
        level = 2
        setMeta(src, 'cmElectricianLevel', level)
        leveledUp = true
    end

    addCash(src, Config.Earnings.perPanel, 'electrician_panel_repair')
    notify(src, ('Panel repaired. Earned $%d.'):format(Config.Earnings.perPanel), 'success')
    if leveledUp then
        notify(src, 'Level up! You can now rent a service truck and repair deposit plates.', 'success')
    end

    TriggerClientEvent('cm-electrician:client:panelResult', src, {
        index = index, panels = panels, level = level, leveledUp = leveledUp,
    })
end)

RegisterNetEvent('cm-electrician:server:fixPlate', function(index)
    local src = source
    index = tonumber(index)
    local point = index and Config.Plates[index]
    if not employed[src] or not point then return end

    local status = getStatus(src)
    if status.level < 2 then
        notify(src, 'You need to reach level 2 before repairing deposit plates.', 'error')
        return
    end
    if onCooldown(src) then return end

    local coords = playerCoords(src)
    if not coords then return end
    if #(coords - point) > (tonumber(Config.Security.plateDistance) or 2.0) then
        notify(src, 'You are too far from the deposit plate.', 'error')
        return
    end

    local plates = status.plates + 1
    setMeta(src, 'cmElectricianPlates', plates)

    local level, leveledUp = status.level, false
    if level < 3 and plates >= (tonumber(Config.LevelUp.platesForLevel3) or 500) then
        level = 3
        setMeta(src, 'cmElectricianLevel', level)
        leveledUp = true
    end

    addCash(src, Config.Earnings.perPlate, 'electrician_plate_repair')
    notify(src, ('Deposit plate repaired. Earned $%d.'):format(Config.Earnings.perPlate), 'success')
    if leveledUp then
        notify(src, 'Level up! You will now be dispatched to city power outages.', 'success')

        -- The scheduled-outage alert loop only fires once, at the moment an
        -- outage starts, to whoever was already level 3+ then. Someone who
        -- levels up mid-outage would otherwise never be told about it.
        if outageActive then
            TriggerClientEvent('cm-electrician:client:outageAlert', src, outageLocation)
        end
    end

    TriggerClientEvent('cm-electrician:client:plateResult', src, {
        index = index, plates = plates, level = level, leveledUp = leveledUp,
    })
end)

local outageId = 0

local function broadcastOutage(active, location)
    outageActive = active
    outageLocation = active and location or nil
    if active then outageId = outageId + 1 end
    TriggerClientEvent('cm-electrician:client:outageState', -1, active, outageLocation)
end

-- scheduleOutage and scheduleAutoFix call each other (the next outage gets
-- queued whether it was fixed by a player or auto-resolved), so scheduleOutage
-- needs a forward declaration.
local scheduleOutage

-- If nobody fixes the outage within autoFixMinutes, the utility company
-- resolves it for free so a fault never sits unattended forever when no
-- level-3 electrician is online. outageId guards against a stale timer
-- closing out a *later* outage that started after this one was fixed.
local function scheduleAutoFix(id)
    CreateThread(function()
        local minutes = tonumber(Config.PowerOutage.autoFixMinutes) or 10
        Wait(minutes * 60000)
        if not outageActive or outageId ~= id then return end

        broadcastOutage(false)
        TriggerClientEvent('cm-electrician:client:notify', -1,
            'The city outage was resolved automatically after going unattended too long.', 'info')
        scheduleOutage()
    end)
end

scheduleOutage = function()
    CreateThread(function()
        local minWait = tonumber(Config.PowerOutage.minWaitMs) or 300000
        local maxWait = tonumber(Config.PowerOutage.maxWaitMs) or 9000000
        Wait(math.random(minWait, maxWait))
        if outageActive then return end

        -- Nobody who could respond is even on duty -- wait for a level-3
        -- electrician to clock in instead of blacking out an area that can
        -- only ever resolve via the unattended auto-fix timer.
        while not hasOnlineResponder() do
            Wait(30000)
            if outageActive then return end
        end

        local location = pickRandomLocation(Config.PowerOutage.locations, outageLocation)
        broadcastOutage(true, location)
        scheduleAutoFix(outageId)
        notifyOutageStart()

        for src in pairs(employed) do
            checkOutageAlert(src, getStatus(src))
        end
    end)
end

RegisterNetEvent('cm-electrician:server:fixOutage', function()
    local src = source
    if not outageActive or not outageLocation or not employed[src] then return end

    local status = getStatus(src)
    if status.level < (tonumber(Config.PowerOutage.unlockLevel) or 3) then
        notify(src, 'You are not yet certified to handle city outages.', 'error')
        return
    end
    if onCooldown(src) then return end

    local coords = playerCoords(src)
    if not coords then return end
    if #(coords - outageLocation) > (tonumber(Config.Security.outageDistance) or 3.0) then
        notify(src, 'You are too far from the fault.', 'error')
        return
    end

    broadcastOutage(false)
    addCash(src, Config.Earnings.perOutageFix, 'electrician_outage_repair')
    TriggerClientEvent('cm-electrician:client:notify', -1,
        'Electricians responded to the city power outage and restored power.', 'success')
    scheduleOutage()
end)

local function isAdminAllowed(src, permission)
    if tonumber(src) == 0 then return true end
    if GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function reply(src, message)
    if tonumber(src) == 0 then
        print('[CM-ELECTRICIAN] ' .. tostring(message))
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-ELECTRICIAN]', tostring(message) } })
    end
end

RegisterCommand('setelectricianlevel', function(src, args)
    if not isAdminAllowed(src, 'electrician.admin.setlevel') then
        return reply(src, 'You do not have permission to do that.')
    end

    local level = math.floor(tonumber(args[1]) or -1)
    if level < 1 or level > 3 then
        return reply(src, 'Usage: /setelectricianlevel <1-3> [playerId]')
    end

    local targetSrc = tonumber(args[2])
    if not targetSrc then
        if tonumber(src) == 0 then return reply(src, 'Usage from console: /setelectricianlevel <1-3> <playerId>') end
        targetSrc = tonumber(src)
    end
    if not GetPlayerName(targetSrc) then return reply(src, 'That player is not online.') end

    setMeta(targetSrc, 'cmElectricianLevel', level)
    local status = getStatus(targetSrc)
    TriggerClientEvent('cm-electrician:client:status', targetSrc, status)
    checkOutageAlert(targetSrc, status)
    notify(targetSrc, ('Your electrician level was set to %d.'):format(level), 'info')
    reply(src, ('Set electrician level %d for player %d.'):format(level, targetSrc))
end, false)

RegisterCommand('triggerelectricianoutage', function(src)
    if not isAdminAllowed(src, 'electrician.admin.setlevel') then
        return reply(src, 'You do not have permission to do that.')
    end
    if outageActive then return reply(src, 'A power outage is already active.') end

    broadcastOutage(true, pickRandomLocation(Config.PowerOutage.locations, outageLocation))
    scheduleAutoFix(outageId)
    notifyOutageStart()
    for employedSrc in pairs(employed) do
        checkOutageAlert(employedSrc, getStatus(employedSrc))
    end
    reply(src, 'Power outage triggered.')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    employed[src] = nil
    cooldowns[src] = nil
    deleteJobVehicle(src)
end)

CreateThread(function()
    math.randomseed(os.time())
    scheduleOutage()
end)
