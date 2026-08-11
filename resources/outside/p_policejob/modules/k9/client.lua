while not Config or not Config.K9 do
    Citizen.Wait(500)
end

if not Config.K9.enabled then
    return
end

K9 = {
    ped = nil,
    breed = nil,
    state = "follow",
    target = nil,
    isTargeting = false,
    lastFollowSpeed = nil,
    lastFollowIssued = 0,
}

radialMenuAdded = false

local breedCreatureMap = {
    german_shepherd = "shepherd",
    retriever = "retriever",
    rottweiler = "rottweiler",
}

local dogAnimConfigs = {
    sit = {
        suffix = "amb@world_dog_sitting@base",
        clip = "base",
        scenario = "WORLD_DOG_SITTING",
    },
    lay = {
        suffix = "amb@sleep_in_kennel@",
        clip = "sleep_in_kennel",
        scenario = "WORLD_DOG_LYING",
    },
    search = {
        suffix = "amb@world_dog_barking@idle_a",
        clip = "idle_a",
        scenario = "WORLD_DOG_BARKING",
    },
}

function hasK9JobAccess()
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    local minGrade = Config.Jobs[job.name]
    if not minGrade then
        return false
    end
    return minGrade <= tonumber(job.grade)
end

function isK9Alive()
    return K9.ped and DoesEntityExist(K9.ped) and not IsPedDeadOrDying(K9.ped, true)
end

function getFollowSpeed(distance)
    if distance > 20.0 then
        return 3.0
    end
    if distance > 8.0 then
        return 2.0
    end
    return 1.0
end

function issueFollow(targetPed, speed)
    TaskFollowToOffsetOfEntity(K9.ped, targetPed, 0.0, -1.5, 0.0, speed, -1, 1.5, true)
    K9.lastFollowSpeed = speed
end

function requestAnimDictLoaded(dict)
    RequestAnimDict(dict)
    local attempts = 0
    while not HasAnimDictLoaded(dict) and attempts < 20 do
        Wait(50)
        attempts = attempts + 1
    end
    return HasAnimDictLoaded(dict)
end

function playDogAnim(ped, animState)
    local animConfig = dogAnimConfigs[animState]
    if not animConfig then
        return
    end
    local creature = breedCreatureMap[K9.breed] or "rottweiler"
    local animDict = ("creatures@%s@%s"):format(creature, animConfig.suffix)
    local loaded = requestAnimDictLoaded(animDict)
    if not loaded and creature ~= "rottweiler" then
        animDict = ("creatures@rottweiler@%s"):format(animConfig.suffix)
        loaded = requestAnimDictLoaded(animDict)
    end
    if not isK9Alive() or K9.state ~= animState then
        return
    end
    if loaded then
        TaskPlayAnim(
            ped,
            animDict,
            animConfig.clip,
            8.0, -8.0, -1,
            1, 0.0, false, false, false
        )
    elseif animConfig.scenario then
        TaskStartScenarioInPlace(ped, animConfig.scenario, 0, true)
    end
end

function refreshDogState()
    if not isK9Alive() then
        return
    end
    SetPedFleeAttributes(K9.ped, 0, false)
    if K9.state == "sit" or K9.state == "lay" or K9.state == "search" then
        local ped = K9.ped
        local animState = K9.state
        ClearPedTasksImmediately(ped)
        CreateThread(function()
            Wait(100)
            if isK9Alive() and K9.state == animState then
                playDogAnim(ped, animState)
            end
        end)
    elseif K9.state == "stay" then
        ClearPedTasksImmediately(K9.ped)
    elseif K9.state == "attack" then
        ClearPedTasksImmediately(K9.ped)
        if K9.target and DoesEntityExist(K9.target) then
            SetPedCombatAttributes(K9.ped, 46, true)
            SetPedCombatRange(K9.ped, 0)
            SetPedKeepTask(K9.ped, true)
            TaskCombatPed(K9.ped, K9.target, 0, 0)
        end
    elseif K9.state == "follow" then
        local distance = #(GetEntityCoords(K9.ped) - GetEntityCoords(cache.ped))
        ClearPedTasksImmediately(K9.ped)
        issueFollow(cache.ped, getFollowSpeed(distance))
    elseif K9.state == "follow_player" then
        if K9.target and DoesEntityExist(K9.target) then
            local distance = #(GetEntityCoords(K9.ped) - GetEntityCoords(K9.target))
            ClearPedTasksImmediately(K9.ped)
            issueFollow(K9.target, getFollowSpeed(distance))
        end
    end
end

function updateK9RadialMenu()
    if hasK9JobAccess() then
        if not radialMenuAdded then
            lib.addRadialItem({
                id = "k9_menu",
                icon = "dog",
                label = locale("k9_menu_label"),
                menu = "k9_root_radial",
            })
            radialMenuAdded = true
        end
    elseif radialMenuAdded then
        lib.removeRadialItem("k9_menu")
        radialMenuAdded = false
    end
end

function K9.setState(self, state, target)
    self.state = state
    self.target = target or nil
    refreshDogState()
end

function K9.startBehaviourLoop(self)
    CreateThread(function()
        while isK9Alive() do
            Wait(350)
            if not isK9Alive() then
                lib.callback.await("p_policejob/k9/dismiss", false)
                self.ped = nil
                self.breed = nil
                self.state = "follow"
                self.target = nil
                Bridge.Notify.showNotify(locale("k9_killed"), "error")
                updateK9RadialMenu()
                break
            end
            local dogCoords = GetEntityCoords(self.ped)
            local playerCoords = GetEntityCoords(cache.ped)
            if #(dogCoords - playerCoords) > Config.K9.despawnDistance then
                lib.callback.await("p_policejob/k9/dismiss", false)
                DeleteEntity(self.ped)
                self.ped = nil
                self.breed = nil
                self.state = "follow"
                self.target = nil
                Bridge.Notify.showNotify(locale("k9_lost"), "warning")
                updateK9RadialMenu()
                break
            end
            local now = GetGameTimer()
            if self.state == "follow" then
                local followSpeed = getFollowSpeed(#(dogCoords - playerCoords))
                local compareValue = self.lastFollowSpeed
                local threshold = nil
                if followSpeed == self.lastFollowSpeed then
                    compareValue = now - self.lastFollowIssued
                    threshold = 5000
                end
                if compareValue > threshold then
                    issueFollow(cache.ped, followSpeed)
                    self.lastFollowIssued = now
                end
            elseif self.state == "follow_player" then
                local followTarget = self.target
                if followTarget and DoesEntityExist(followTarget) and not IsEntityDead(followTarget) then
                    local followSpeed = getFollowSpeed(#(dogCoords - GetEntityCoords(followTarget)))
                    local compareValue = self.lastFollowSpeed
                    local threshold = nil
                    if followSpeed == self.lastFollowSpeed then
                        compareValue = now - self.lastFollowIssued
                        threshold = 5000
                    end
                    if compareValue > threshold then
                        issueFollow(followTarget, followSpeed)
                        self.lastFollowIssued = now
                    end
                else
                    self:setState("follow")
                    Bridge.Notify.showNotify(locale("k9_target_lost"), "warning")
                end
            elseif self.state == "attack" then
                local attackTarget = self.target
                if attackTarget and DoesEntityExist(attackTarget) and not IsEntityDead(attackTarget) then
                    TaskCombatPed(self.ped, attackTarget, 0, 0)
                else
                    self:setState("follow")
                    Bridge.Notify.showNotify(locale("k9_neutralised"), "success")
                end
            end
        end
    end)
end

function K9.spawn(self, breed)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_already_deployed"), "error")
    end
    local modelEntry = Config.K9.models[1]
    for _, entry in ipairs(Config.K9.models) do
        if entry.breed == breed then
            modelEntry = entry
            break
        end
    end
    if not lib.callback.await("p_policejob/k9/spawn", false, modelEntry.breed) then
        return Bridge.Notify.showNotify(locale("k9_spawn_denied"), "error")
    end
    local spawnCoords = GetOffsetFromEntityInWorldCoords(cache.ped, 1.5, 0.0, 0.0)
    local heading = GetEntityHeading(cache.ped)
    local model = lib.requestModel(modelEntry.model)
    if not model then
        return Bridge.Notify.showNotify(locale("k9_model_failed"), "error")
    end
    self.ped = CreatePed(28, model, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(self.ped) then
        self.ped = nil
        return Bridge.Notify.showNotify(locale("k9_create_failed"), "error")
    end
    SetEntityHealth(self.ped, Config.K9.health)
    SetPedArmour(self.ped, Config.K9.armor)
    SetEntityInvincible(self.ped, false)
    SetBlockingOfNonTemporaryEvents(self.ped, true)
    SetPedFleeAttributes(self.ped, 0, false)
    SetEntityAsMissionEntity(self.ped, true, true)
    SetPedCanRagdoll(self.ped, true)
    self.breed = modelEntry.breed
    self.state = "follow"
    self.target = nil
    Bridge.Notify.showNotify(locale("k9_deployed"):format(modelEntry.name), "success")
    updateK9RadialMenu()
    self:startBehaviourLoop()
end

function K9.dismiss(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not self.ped then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    lib.callback.await("p_policejob/k9/dismiss", false)
    if DoesEntityExist(self.ped) then
        ClearPedTasksImmediately(self.ped)
        DeleteEntity(self.ped)
    end
    self.ped = nil
    self.breed = nil
    self.state = "follow"
    self.target = nil
    Bridge.Notify.showNotify(locale("k9_dismissed"), "success")
    updateK9RadialMenu()
end

function K9.follow(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    self:setState("follow")
    Bridge.Notify.showNotify(locale("k9_following_you"), "success")
end

function K9.followPlayer(self, serverId)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    local ok, netId = lib.callback.await("p_policejob/k9/getTargetNetId", false, serverId)
    if not ok or not netId then
        return Bridge.Notify.showNotify(locale("k9_target_not_found"), "error")
    end
    local targetPed = NetToPed(netId)
    if not DoesEntityExist(targetPed) then
        return Bridge.Notify.showNotify(locale("k9_not_in_range"), "error")
    end
    self:setState("follow_player", targetPed)
    Bridge.Notify.showNotify(locale("k9_following_player"):format(serverId), "success")
end

function getCameraDirection()
    local rotation = GetFinalRenderedCamRot(2)
    local x = -math.sin(math.rad(rotation.z)) * math.abs(math.cos(math.rad(rotation.x)))
    local y = math.cos(math.rad(rotation.z)) * math.abs(math.cos(math.rad(rotation.x)))
    local z = math.sin(math.rad(rotation.x))
    return vector3(x, y, z)
end

function getTargetedPed(requirePlayer)
    local camCoords = GetFinalRenderedCamCoord()
    local direction = getCameraDirection()
    local destination = camCoords + direction * 80.0
    local rayHandle = StartShapeTestRay(
        camCoords.x, camCoords.y, camCoords.z,
        destination.x, destination.y, destination.z,
        12, cache.ped, 0
    )
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)
    local targetPed = nil
    if hit == 1 and entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) and IsEntityAPed(entityHit) then
        if entityHit ~= cache.ped and entityHit ~= K9.ped then
            if requirePlayer then
                if IsPedAPlayer(entityHit) then
                    targetPed = entityHit
                end
            else
                targetPed = entityHit
            end
        end
    end
    local lineEnd = targetPed and GetEntityCoords(targetPed) or (hit == 1 and hitCoords or destination)
    return targetPed, lineEnd
end

function drawK9TargetingLine(startCoords, endCoords, r, g, b, a)
    DrawLine(startCoords.x, startCoords.y, startCoords.z, endCoords.x, endCoords.y, endCoords.z + 1.0, r, g, b, a)
end

function K9.attack(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    if self.isTargeting then
        return
    end
    self.isTargeting = true
    CreateThread(function()
        lib.showTextUI(locale("k9_targeting_hint"), { position = "bottom-center" })
        while self.isTargeting do
            Wait(0)
            if not isK9Alive() then
                self.isTargeting = false
                break
            end
            local targetPed, lineEnd = getTargetedPed(false)
            local dogCoords = GetEntityCoords(self.ped)
            local lineStart = vector3(dogCoords.x, dogCoords.y, dogCoords.z + 0.5)
            if targetPed then
                drawK9TargetingLine(lineStart, GetEntityCoords(targetPed), 255, 30, 30, 220)
                DrawMarker(
                    1,
                    GetEntityCoords(targetPed).x,
                    GetEntityCoords(targetPed).y,
                    GetEntityCoords(targetPed).z,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.7, 0.7, 0.4,
                    255, 30, 30, 110,
                    false, false, 2, false, nil, nil, false
                )
            else
                drawK9TargetingLine(lineStart, lineEnd, 160, 160, 160, 100)
            end
            if IsControlJustPressed(0, 38) and targetPed then
                self.isTargeting = false
                self:setState("attack", targetPed)
                Bridge.Notify.showNotify(locale("k9_attacking"), "warning")
            elseif IsControlJustPressed(0, 73) then
                self.isTargeting = false
            end
        end
        self.isTargeting = false
        lib.hideTextUI()
    end)
end

function K9.heel(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    self:setState("follow")
    Bridge.Notify.showNotify(locale("k9_heel"), "success")
end

function K9.sit(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    self:setState("sit")
    Bridge.Notify.showNotify(locale("k9_sitting"), "success")
end

function K9.stay(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    self:setState("stay")
    Bridge.Notify.showNotify(locale("k9_staying"), "success")
end

function K9.lay(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    self:setState("lay")
    Bridge.Notify.showNotify(locale("k9_laying"), "success")
end

function getPlayerServerIdFromPed(ped)
    if not ped or ped == 0 or not IsPedAPlayer(ped) then
        return nil
    end
    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if not playerIndex or playerIndex == -1 then
        return nil
    end
    return GetPlayerServerId(playerIndex)
end

function K9.search(self)
    if not hasK9JobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    if not isK9Alive() then
        return Bridge.Notify.showNotify(locale("k9_no_deployed"), "error")
    end
    if self.isTargeting then
        return
    end
    self.isTargeting = true
    CreateThread(function()
        lib.showTextUI(locale("k9_search_hint"), { position = "bottom-center" })
        while self.isTargeting do
            Wait(0)
            if not isK9Alive() then
                self.isTargeting = false
                break
            end
            local targetPed, lineEnd = getTargetedPed(true)
            local dogCoords = GetEntityCoords(self.ped)
            local lineStart = vector3(dogCoords.x, dogCoords.y, dogCoords.z + 0.5)
            if targetPed then
                drawK9TargetingLine(lineStart, GetEntityCoords(targetPed), 40, 120, 255, 220)
                DrawMarker(
                    1,
                    GetEntityCoords(targetPed).x,
                    GetEntityCoords(targetPed).y,
                    GetEntityCoords(targetPed).z,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.7, 0.7, 0.4,
                    40, 120, 255, 110,
                    false, false, 2, false, nil, nil, false
                )
            else
                drawK9TargetingLine(lineStart, lineEnd, 160, 160, 160, 100)
            end
            if IsControlJustPressed(0, 38) then
                if not targetPed then
                    Bridge.Notify.showNotify(locale("k9_search_no_target"), "error")
                else
                    self.isTargeting = false
                    local targetServerId = getPlayerServerIdFromPed(targetPed)
                    if not targetServerId then
                        Bridge.Notify.showNotify(locale("k9_search_no_target"), "error")
                        break
                    end
                    self:setState("search")
                    lib.hideTextUI()
                    if not lib.progressBar({
                        duration = Config.K9.searchDuration,
                        label = locale("k9_searching"),
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                    }) or not isK9Alive() then
                        Bridge.Notify.showNotify(locale("k9_search_cancelled"), "inform")
                        break
                    end
                    local ok, hasIllegal = lib.callback.await("p_policejob/k9/searchPlayer", false, targetServerId)
                    if not ok then
                        Bridge.Notify.showNotify(locale("k9_search_too_far"), "error")
                        break
                    end
                    if hasIllegal then
                        Bridge.Notify.showNotify(locale("k9_search_illegal"), "warning")
                    else
                        Bridge.Notify.showNotify(locale("k9_search_clean"), "success")
                    end
                    break
                end
            elseif IsControlJustPressed(0, 73) then
                self.isTargeting = false
                Bridge.Notify.showNotify(locale("k9_search_cancelled"), "inform")
            end
        end
        self.isTargeting = false
        lib.hideTextUI()
    end)
end

RegisterCommand("k9dismiss", function() K9:dismiss() end, false)
RegisterCommand("k9follow", function() K9:follow() end, false)
RegisterCommand("k9attack", function() K9:attack() end, false)
RegisterCommand("k9heel", function() K9:heel() end, false)
RegisterCommand("k9sit", function() K9:sit() end, false)
RegisterCommand("k9stay", function() K9:stay() end, false)
RegisterCommand("k9lay", function() K9:lay() end, false)
RegisterCommand("k9search", function() K9:search() end, false)
RegisterCommand("k9followplayer", function(_, args)
    local serverId = tonumber(args[1])
    if not serverId then
        return Bridge.Notify.showNotify(locale("k9_followplayer_usage"), "error")
    end
    K9:followPlayer(serverId)
end, false)

lib.addKeybind({
    name = "k9_spawn",
    description = locale("k9_keybind_spawn"),
    defaultKey = "INSERT",
    defaultMapper = "keyboard",
    onPressed = function()
        K9:spawn()
    end,
})

lib.addKeybind({
    name = "k9_dismiss",
    description = locale("k9_keybind_dismiss"),
    defaultKey = "DELETE",
    defaultMapper = "keyboard",
    onPressed = function()
        K9:dismiss()
    end,
})

lib.addKeybind({
    name = "k9_attack",
    description = locale("k9_keybind_attack"),
    defaultKey = "NONE",
    defaultMapper = "keyboard",
    onPressed = function()
        K9:attack()
    end,
})

lib.addKeybind({
    name = "k9_heel",
    description = locale("k9_keybind_heel"),
    defaultKey = "NONE",
    defaultMapper = "keyboard",
    onPressed = function()
        K9:heel()
    end,
})

exports("GetK9Ped", function()
    return K9.ped
end)

exports("IsK9Active", function()
    return isK9Alive()
end)

exports("GetK9State", function()
    return K9.state
end)

exports("SetK9State", function(state, target)
    K9:setState(state, target)
end)
