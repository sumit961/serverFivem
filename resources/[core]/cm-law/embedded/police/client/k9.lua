-- Server-owned Police K9 with server-authorized target commands.
local dogPed, followThread, dogMode = nil, false, 'heel'
local heelBand, lastHeelDistance, lastHeelProgress = nil, nil, 0
local scentBlip, scentToken = nil, 0

local function notify(message, kind) PoliceNotify(message, kind) end

local function serverCallback(name, ...)
    if type(LocalPlayer.state.cmPolice) ~= 'table' and type(LocalPlayer.state.cmLegalOrg) == 'table' then
        name = tostring(name):gsub('^cm%-police:', 'cm-law:')
    end
    local result = table.pack(pcall(lib.callback.await, name, false, ...))
    if not result[1] then
        notify(('Police K9 callback failed: %s'):format(tostring(result[2] or 'unknown error')), 'error')
        return nil
    end
    return table.unpack(result, 2, result.n)
end

local function canUseK9()
    local state = LocalPlayer.state.cmPolice
    if type(state) == 'table' and state.onDuty == true then
        local permissions = state.permissions or {}
        return state.isLeader == true or permissions['police.k9'] == true
    end
    state = LocalPlayer.state.cmLegalOrg
    local permissions = type(state) == 'table' and (state.permissions or {}) or {}
    return type(state) == 'table' and state.onDuty == true and not state.suspended
        and (not state.capabilities or state.capabilities.k9 ~= false)
        and (state.isLeader == true or permissions['law.k9'] == true)
end

local function controlDog()
    if not dogPed or not DoesEntityExist(dogPed) then return false end
    NetworkRequestControlOfEntity(dogPed)
    return true
end

local function heel()
    if not controlDog() then return end
    dogMode = 'heel'
    heelBand, lastHeelDistance, lastHeelProgress = nil, nil, GetGameTimer()
    ClearPedTasks(dogPed)
    TaskFollowToOffsetOfEntity(dogPed, PlayerPedId(), 0.6, -1.15, 0.0, 1.35, -1, 1.35, true)
end

local function startFollow()
    if followThread then return end
    followThread = true
    CreateThread(function()
        while dogPed and DoesEntityExist(dogPed) do
            if dogMode == 'heel' then
                local handler = PlayerPedId()
                local distance = #(GetEntityCoords(dogPed) - GetEntityCoords(handler))
                local band, speed
                if distance <= 2.0 then
                    band, speed = 'heel', 1.35
                elseif distance <= 6.0 then
                    band, speed = 'follow', 2.2
                elseif distance <= 20.0 then
                    band, speed = 'catchup', 3.5
                else
                    band, speed = 'urgent', 5.0
                end

                local now = GetGameTimer()
                if not lastHeelDistance or distance < lastHeelDistance - 0.25 then
                    lastHeelDistance, lastHeelProgress = distance, now
                elseif distance > 6.0 and now - (lastHeelProgress or now) >= 4000 then
                    -- Retask only after a real lack of progress, rather than
                    -- clearing the K9 task on every polling interval.
                    ClearPedTasks(dogPed)
                    heelBand, lastHeelProgress = nil, now
                end

                if distance >= 40.0 and controlDog() then
                    -- Heel is the only mode allowed to recover an unreachable
                    -- dog. Attack, chase, suspect-follow, hold and search
                    -- states never reposition the animal.
                    local handlerCoords = GetEntityCoords(handler)
                    local heading = math.rad(GetEntityHeading(handler))
                    local x = handlerCoords.x - math.sin(heading) * 2.0
                    local y = handlerCoords.y + math.cos(heading) * 2.0
                    local z = handlerCoords.z
                    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
                    if foundGround then z = groundZ end
                    SetEntityCoordsNoOffset(dogPed, x, y, z, false, false, false)
                    distance, band, speed = 2.0, 'heel', 1.35
                    heelBand, lastHeelDistance, lastHeelProgress = nil, distance, now
                end

                -- A band change adapts speed; the stuck timer above is the
                -- only other path that resets an already-running follow task.
                if band ~= heelBand then
                    TaskFollowToOffsetOfEntity(dogPed, handler, 0.6, -1.15, 0.0, speed, -1, 1.35, true)
                    heelBand = band
                end
            end
            Wait(500)
        end
        followThread = false
    end)
end

local function selectedPlayer(maxDistance)
    local aiming, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
    if aiming and entity ~= 0 and IsEntityAPed(entity) and IsPedAPlayer(entity) then
        local player = NetworkGetPlayerIndexFromPed(entity)
        if player ~= -1 and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) <= maxDistance then
            return GetPlayerServerId(player)
        end
    end
    local coords, nearest, nearestDistance = GetEntityCoords(PlayerPedId()), nil, maxDistance
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            local distance = #(coords - GetEntityCoords(ped))
            if distance <= nearestDistance then nearest, nearestDistance = GetPlayerServerId(player), distance end
        end
    end
    return nearest
end

local function targetPed(targetSrc)
    local player = GetPlayerFromServerId(tonumber(targetSrc) or -1)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    return ped ~= 0 and DoesEntityExist(ped) and ped or nil
end

local function targetCommand(action)
    if not PoliceIsK9Deployed() then return notify('Deploy your K9 first.', 'error') end
    local targetSrc = selectedPlayer(action == 'attack' and (PoliceConfig.K9.AttackDistance or 20.0) or (PoliceConfig.K9.ChaseDistance or 75.0))
    if not targetSrc then return notify('Aim at or stand near a suspect first.', 'error') end
    if action == 'attack' and not PoliceConfirm('Confirm K9 Attack', 'Order the K9 to bite this recent attacker?', 'Attack', 'Cancel') then return end
    local ok, message, approvedTarget = serverCallback('cm-police:server:k9CommandTarget', action, targetSrc)
    if ok == nil then return end
    notify(message, ok and 'success' or 'error')
    if not ok then return end
    local ped = targetPed(approvedTarget)
    if not ped or not controlDog() then return notify('Target is no longer available.', 'error') end
    ClearPedTasks(dogPed)
    dogMode = action
    if action == 'attack' then
        SetPedCombatAttributes(dogPed, 5, true)
        TaskCombatPed(dogPed, ped, 0, 16)
    elseif action == 'follow' then
        TaskFollowToOffsetOfEntity(dogPed, ped, 0.8, -1.5, 0.0, 1.25, -1, 2.0, true)
    else
        TaskGoToEntity(dogPed, ped, -1, 2.5, 2.2, 0.0, 0)
    end
end

function PoliceIsK9Deployed() return dogPed ~= nil and DoesEntityExist(dogPed) end

function PoliceDeployK9()
    if not canUseK9() then return notify('You must be an on-duty officer with a K9 unit.', 'error') end
    if PoliceIsK9Deployed() then return notify('Your K9 is already deployed.', 'error') end
    if not PoliceConfirm('Deploy K9', 'Deploy your Police K9 companion?', 'Deploy', 'Cancel') then return end
    local ok, message, netId = serverCallback('cm-police:server:deployK9')
    if ok == nil then return end
    if not ok then return notify(message, 'error') end
    local deadline = GetGameTimer() + 5000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(0) end
    dogPed = NetworkDoesNetworkIdExist(netId) and NetToPed(netId) or nil
    if not dogPed or dogPed == 0 then
        serverCallback('cm-police:server:recallK9')
        return notify('Could not synchronize the K9.', 'error')
    end
    SetPedFleeAttributes(dogPed, 0, false)
    SetBlockingOfNonTemporaryEvents(dogPed, true)
    heel()
    startFollow()
    notify(message, 'success')
end

function PoliceRecallK9()
    if not PoliceIsK9Deployed() then return notify('You have no K9 deployed.', 'error') end
    if not PoliceConfirm('Recall K9', 'Recall and remove your deployed K9?', 'Recall', 'Cancel') then return end
    local ok, message = serverCallback('cm-police:server:recallK9')
    if ok == nil then return end
    if not ok then return notify(message, 'error') end
    dogPed, dogMode = nil, 'heel'
    notify(message, 'success')
end

function PoliceK9Heel() heel(); notify('K9 returned to heel.', 'success') end
function PoliceK9FollowSuspect() targetCommand('follow') end
function PoliceK9Chase() targetCommand('chase') end
function PoliceK9Attack() targetCommand('attack') end

function PoliceK9HoldBark()
    if not controlDog() then return notify('Deploy your K9 first.', 'error') end
    dogMode = 'hold'
    ClearPedTasks(dogPed)
    TaskStandStill(dogPed, -1)
    PlayAmbientSpeech1(dogPed, 'BARK', 'SPEECH_PARAMS_FORCE')
    notify('K9 is holding position.', 'success')
end

function PoliceK9StopAttack()
    local ok, message = serverCallback('cm-police:server:k9StopAttack')
    if ok == nil then return end
    notify(message, ok and 'success' or 'error')
    if ok then heel() end
end

local function forceStopK9()
    if PoliceIsK9Deployed() then heel(); notify('K9 attack authorization ended; K9 recalled to heel.', 'info') end
end

RegisterNetEvent('cm-law:client:k9ForceStop', forceStopK9)
RegisterNetEvent('cm-police:client:k9ForceStop', forceStopK9)

function PoliceK9Track()
    if not PoliceIsK9Deployed() then return notify('Deploy your K9 first.', 'error') end
    local ok, message, targetSrc, coords = serverCallback('cm-police:server:k9Track')
    if ok == nil then return end
    notify(message, ok and 'success' or 'error')
    if not ok or not coords then return end
    scentToken = scentToken + 1
    local token = scentToken
    if scentBlip and DoesBlipExist(scentBlip) then RemoveBlip(scentBlip) end
    scentBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(scentBlip, 161); SetBlipColour(scentBlip, 5); SetBlipScale(scentBlip, 1.1)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('K9 Scent'); EndTextCommandSetBlipName(scentBlip)
    CreateThread(function()
        local expires = GetGameTimer() + (PoliceConfig.K9.TrackDurationMs or 60000)
        while token == scentToken and GetGameTimer() < expires do
            Wait(PoliceConfig.K9.TrackUpdateMs or 5000)
            local fresh, _, nextCoords = serverCallback('cm-police:server:k9TrackUpdate', targetSrc)
            if not fresh or not nextCoords then break end
            if scentBlip and DoesBlipExist(scentBlip) then SetBlipCoords(scentBlip, nextCoords.x, nextCoords.y, nextCoords.z) end
        end
        if token == scentToken and scentBlip and DoesBlipExist(scentBlip) then RemoveBlip(scentBlip); scentBlip = nil end
    end)
end

function PoliceK9SearchPlayer()
    local targetSrc = selectedPlayer(4.0)
    if not targetSrc then return notify('Stand near or aim at the player to search.', 'error') end
    if not PoliceConfirm('K9 Player Search', 'Use the K9 to sniff this wanted or restrained player?', 'Search', 'Cancel') then return end
    local ok, message = serverCallback('cm-police:server:k9SearchPlayer', targetSrc)
    if ok ~= nil then notify(message, ok and 'success' or 'error') end
end

function PoliceK9SearchVehicle()
    local coords = GetEntityCoords(PlayerPedId())
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 4.0, 0, 71)
    if not vehicle or vehicle == 0 then return notify('Stand near a persistent vehicle to search.', 'error') end
    if not PoliceConfirm('K9 Vehicle Search', 'Use the K9 to sniff this vehicle?', 'Search', 'Cancel') then return end
    local ok, message = serverCallback('cm-police:server:k9SearchVehicle', NetworkGetNetworkIdFromEntity(vehicle))
    if ok ~= nil then notify(message, ok and 'success' or 'error') end
end

function PoliceK9Menu()
    local deployed = PoliceIsK9Deployed()
    PoliceQuickMenu('K9 Commands', {
        { title = deployed and 'Recall K9' or 'Deploy K9', icon = 'dog', onSelect = deployed and PoliceRecallK9 or PoliceDeployK9 },
        { title = 'Heel / Follow Officer', icon = 'person-walking', disabled = not deployed, onSelect = PoliceK9Heel },
        { title = 'Track Wanted Suspect', icon = 'location-crosshairs', disabled = not deployed, onSelect = PoliceK9Track },
        { title = 'Follow Selected Suspect', icon = 'eye', disabled = not deployed, onSelect = PoliceK9FollowSuspect },
        { title = 'Chase Selected Suspect', icon = 'person-running', disabled = not deployed, onSelect = PoliceK9Chase },
        { title = 'Bark / Hold Position', icon = 'volume-high', disabled = not deployed, onSelect = PoliceK9HoldBark },
        { title = 'Attack Recent Attacker', description = 'Requires confirmation and recent server damage evidence', icon = 'shield-halved', disabled = not deployed, onSelect = PoliceK9Attack },
        { title = 'Stop Attack / Heel', icon = 'hand', disabled = not deployed, onSelect = PoliceK9StopAttack },
        { title = 'Search Player', icon = 'user-shield', disabled = not deployed, onSelect = PoliceK9SearchPlayer },
        { title = 'Search Vehicle', icon = 'car', disabled = not deployed, onSelect = PoliceK9SearchVehicle },
    })
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    dogPed = nil
    if scentBlip and DoesBlipExist(scentBlip) then RemoveBlip(scentBlip) end
end)
