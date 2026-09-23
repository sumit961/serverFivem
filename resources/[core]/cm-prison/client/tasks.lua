-- Task-based sentence reduction: while jailed (LocalPlayer.state.cmPrison),
-- a prisoner can walk up to a task point near their own assigned spawn and
-- perform a short task to shave time off their sentence via the server's
-- existing ReduceSentence export (server/main.lua). Task points are offsets
-- from the player's own spawn rather than fixed world coordinates, since
-- jail spawn placement is admin-configured and can move (client/main.lua's
-- own "teleport back if you wander >35 units" thread already keys off the
-- same per-player spawn for the same reason).

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end

local function taskPoints(spawn)
    local points = {}
    for _, offset in ipairs((PrisonConfig.Tasks or {}).Offsets or {}) do
        points[#points + 1] = {
            x = spawn.x + (tonumber(offset.x) or 0.0), y = spawn.y + (tonumber(offset.y) or 0.0), z = spawn.z + (tonumber(offset.z) or 0.0),
            label = offset.label or 'Task', anim = offset.anim,
        }
    end
    return points
end

local function drawLabel(point)
    SetDrawOrigin(point.x, point.y, point.z + 1.0, 0)
    SetTextFont(4); SetTextScale(0.0, 0.28); SetTextCentre(true); SetTextOutline(); SetTextColour(255, 255, 255, 235)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('[E] %s'):format(point.label))
    EndTextCommandDisplayText(0.0, 0.0); ClearDrawOrigin()
end

local doingTask = false

local function performTask(point)
    if doingTask then return end
    doingTask = true
    local ped = PlayerPedId()
    local anim = point.anim
    if anim and anim.dict then
        RequestAnimDict(anim.dict)
        local deadline = GetGameTimer() + 2000
        while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(50) end
        if HasAnimDictLoaded(anim.dict) then
            TaskPlayAnim(ped, anim.dict, anim.clip or 'base', 8.0, -8.0, -1, anim.flag or 1, 0, false, false, false)
        end
    end
    local duration = tonumber((PrisonConfig.Tasks or {}).DurationMs) or 8000
    local completed = lib.progressBar({
        duration = duration, label = point.label, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
    ClearPedTasks(ped)
    doingTask = false
    if completed then TriggerServerEvent('cm-prison:server:completeTask') else notify('Task cancelled.', 'inform') end
end

CreateThread(function()
    while true do
        local wait = 1000
        local state = LocalPlayer.state.cmPrison
        if (PrisonConfig.Tasks or {}).Enabled and type(state) == 'table' and state.active == true and type(state.spawn) == 'table' and tonumber(state.spawn.x) then
            local points = taskPoints(state.spawn)
            local coords = GetEntityCoords(PlayerPedId())
            local nearest, nearestDistance
            for _, point in ipairs(points) do
                local distance = #(coords - vector3(point.x, point.y, point.z))
                if not nearestDistance or distance < nearestDistance then nearest, nearestDistance = point, distance end
            end
            local interactDistance = tonumber((PrisonConfig.Tasks or {}).InteractDistance) or 2.0
            if nearest and nearestDistance <= 8.0 then
                wait = 0
                if nearestDistance <= interactDistance then
                    drawLabel(nearest)
                    if not doingTask and IsControlJustPressed(0, 38) then performTask(nearest) end
                end
            end
        end
        Wait(wait)
    end
end)
