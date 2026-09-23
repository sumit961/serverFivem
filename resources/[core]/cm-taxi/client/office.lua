local Config = CMTaxi.Config
local State = CMTaxi.Client.State
local notify = CMTaxi.Client.Notify
local sendUI = CMTaxi.Client.SendUI
local request = CMTaxi.Client.Request

local function findClearSpawn(office)
    local pool = GetGamePool('CVehicle')
    for index, spawn in ipairs(office.rentalSpawns) do
        local clear = true
        local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)
        for _, vehicle in ipairs(pool) do
            if #(spawnCoords - GetEntityCoords(vehicle)) <= 2.5 then
                clear = false
                break
            end
        end
        if clear then return index end
    end
    return nil
end

local function buildLevelsPayload(progressionLevel)
    local levels = {}
    for level, data in pairs(Config.Levels) do
        levels[#levels + 1] = {
            level = level,
            label = data.label,
            vehicleLabel = data.vehicleLabel,
            vehicleModel = data.vehicle,
            vehicleRentCost = data.vehicleRentCost,
            unlocked = progressionLevel >= level,
        }
    end
    table.sort(levels, function(a, b) return a.level < b.level end)
    return levels
end

function CMTaxi.Client.OpenOffice()
    local officeKey = State.officeKey
    local office = Config.Offices[officeKey]
    if not office then return end

    local progression = State.progression or { xp = 0, level = 1 }
    local rental = State.rental
    local xpNeeded = math.max(1, math.floor(progression.level * 100 * Config.SkillMultiplier))

    sendUI('openOffice', {
        officeName = office.name,
        onDuty = State.onDuty,
        progression = {
            level = progression.level,
            xp = progression.xp,
            xpNeeded = xpNeeded,
            percent = math.min(100, math.max(1, (progression.xp / xpNeeded) * 100)),
        },
        rental = rental and { plate = rental.plate, cost = rental.cost } or nil,
        levels = buildLevelsPayload(progression.level),
        currency = '$',
    })
    SetNuiFocus(true, true)
end

RegisterNUICallback('office:close', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('office:toggleDuty', function(_, cb)
    CMTaxi.Client.ToggleDuty()
    SetTimeout(150, function()
        if State.officeKey then CMTaxi.Client.OpenOffice() end
    end)
    cb({ ok = true })
end)

RegisterNUICallback('office:rent', function(data, cb)
    local officeKey = State.officeKey
    local office = officeKey and Config.Offices[officeKey]
    if not office then return cb({ success = false }) end

    if not State.onDuty then
        notify(CMTaxi.Locale('offduty'), 'error')
        return cb({ success = false })
    end

    local spawnIndex = findClearSpawn(office)
    if not spawnIndex then
        notify(CMTaxi.Locale('no_spawns'), 'error')
        return cb({ success = false })
    end

    local result = request('cm-taxi:server:requestRent', 8000, officeKey, tonumber(data.model), spawnIndex)
    if result.success then
        SetTimeout(150, function() CMTaxi.Client.OpenOffice() end)
    end
    cb(result)
end)

RegisterNUICallback('office:returnRental', function(_, cb)
    local result = request('cm-taxi:server:returnTaxi', 6000)
    if result.success then
        SetTimeout(150, function() CMTaxi.Client.OpenOffice() end)
    end
    cb(result)
end)

-- ============================================================
-- Meter panel callbacks (Fares tab + active-job cancel button)
-- ============================================================

RegisterNUICallback('takejob', function(data, cb)
    if State.currentJob ~= nil then
        notify(CMTaxi.Locale('fare_active'), 'error')
        return cb({ success = false })
    end
    cb(request('cm-taxi:server:takeJob', 6000, tonumber(data.id)))
end)

RegisterNUICallback('canceljob', function(_, cb)
    if State.currentJob == nil then
        notify(CMTaxi.Locale('fare_none'), 'error')
        return cb({ success = false })
    end
    local result = request('cm-taxi:server:cancelJob', 6000)
    if result.success then CMTaxi.Client.ResetFare() end
    cb(result)
end)

RegisterCommand('taxicancel', function()
    TriggerServerEvent('cm-taxi:server:cancelTaxiRequest')
end, false)

RegisterNUICallback('escape', function(_, cb)
    if State.guiVisible then CMTaxi.Client.ToggleMeter(false) end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    cb({ ok = true })
end)
