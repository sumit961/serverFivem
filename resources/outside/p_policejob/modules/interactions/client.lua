if not Config?.Interactions?.Enabled then
    return
end

Interactions = {
    isInCuffProcess = false,
    cuffProp = nil,
    cuffSide = "rear",
    isHard = false,
    isCuffed = false,
    ropeTimer = nil,
    dragStatus = {
        draggedBy = nil,
        draggingPlayer = nil,
    },
    carryData = {
        isActive = false,
        playerId = nil,
        playerPed = nil,
        role = "",
    },
    headBagData = {
        object = nil,
        state = false,
    },
    mouthTapes = {},
    _mouthTapeActive = false,
}

local seatLabels = {
    ["-1"] = locale("driver_seat"),
    ["0"] = locale("passenger_seat"),
    ["1"] = locale("back_left_passenger"),
    ["2"] = locale("back_right_passenger"),
}

local policeCompatResources = {
    "qb-policejob",
    "qbx_police",
    "wasabi_police",
}

local HANDS_UP_DICT = "random@mugging3"
local HANDS_UP_CLIP = "handsup_standing_base"
local JOB_CACHE_TTL = 5000
local ITEM_CACHE_TTL = 30000
local HANDS_UP_CACHE_TTL = 250

local resolveCache = { frame = -1 }
local jobCache = { value = nil, expires = 0 }
local itemCountCache = {}
local handsUpCache = { entity = 0, expires = 0, value = false }
local lastGunshotAt = 0

function registerPoliceCompatExport(exportName, handler)
    for _, resourceName in ipairs(policeCompatResources) do
        AddEventHandler(("__cfx_export_%s_%s"):format(resourceName, exportName), function(setCB)
            setCB(handler)
        end)
    end
    exports(exportName, handler)
end

registerPoliceCompatExport("IsHandcuffed", function()
    return LocalPlayer.state.isCuffed
end)

exports("isInCuffProcess", function()
    return Interactions.isInCuffProcess
end)

registerPoliceCompatExport("searchPlayer", function(playerId)
    if not playerId then
        return
    end
    Bridge.Inventory.openInventory("player", tonumber(playerId))
end)

registerPoliceCompatExport("escortPlayer", function(playerId)
    if not playerId then
        return
    end
    Interactions:quickEscort(tonumber(playerId))
end)

function Interactions.canAct()
    return Editable:canAct()
end

function Interactions.isInFront(_, entity)
    return Editable:isInFront(entity)
end

function Interactions.isPlayerDead(_, serverId)
    return Editable:isPlayerDead(serverId)
end

function Interactions.getNetIdFromEntity(_, entity)
    local attempts = 0
    while not NetworkGetEntityIsNetworked(entity) do
        Wait(10)
        attempts = attempts + 1
        if attempts > 100 then
            return 0
        end
    end
    return NetworkGetNetworkIdFromEntity(entity)
end

function getServerIdFromPed(ped)
    return GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
end

function getCachedJob()
    local now = GetGameTimer()
    if jobCache.value and now < jobCache.expires then
        return jobCache.value
    end
    local job = Bridge.Framework.fetchPlayerJob()
    jobCache.value = job
    jobCache.expires = now + JOB_CACHE_TTL
    return job
end

function invalidateJobCache()
    jobCache.value = nil
    jobCache.expires = 0
end

function getCachedItemCount(itemName, metadata)
    local cacheKey = itemName
    if metadata then
        cacheKey = itemName .. "\0" .. tostring(metadata)
    end
    local now = GetGameTimer()
    local cached = itemCountCache[cacheKey]
    if cached and now < cached.expires then
        return cached.value
    end
    local count = Bridge.Inventory.getItemCount(itemName, metadata) or 0
    itemCountCache[cacheKey] = {
        value = count,
        expires = now + ITEM_CACHE_TTL,
    }
    return count
end

function invalidateItemCache()
    itemCountCache = {}
end

RegisterNetEvent("esx:setJob", invalidateJobCache)
RegisterNetEvent("esx:setJob2", invalidateJobCache)
RegisterNetEvent("QBCore:Client:OnJobUpdate", invalidateJobCache)
RegisterNetEvent("QBCore:Client:SetDuty", invalidateJobCache)
RegisterNetEvent("qbx_core:client:onJobUpdate", invalidateJobCache)

RegisterNetEvent("QBCore:Client:OnPlayerLoaded", function()
    invalidateJobCache()
    invalidateItemCache()
end)

RegisterNetEvent("esx:playerLoaded", function()
    invalidateJobCache()
    invalidateItemCache()
end)

RegisterNetEvent("esx:addInventoryItem", invalidateItemCache)
RegisterNetEvent("esx:removeInventoryItem", invalidateItemCache)
AddEventHandler("ox_inventory:updateInventory", invalidateItemCache)

function Interactions.resolve(entity)
    local frame = GetFrameCount()
    if resolveCache.frame == frame and resolveCache.entity == entity then
        return resolveCache
    end

    local serverId = getServerIdFromPed(entity)
    local targetState = nil

    if serverId ~= 0 then
        local state = Player(serverId).state
        targetState = {
            isCuffed = state.isCuffed,
            draggedBy = state.draggedBy,
            carriedBy = state.carriedBy,
            isDead = state.isDead,
            dead = state.dead,
            cuffType = state.cuffType,
            mouthTaped = state.mouthTaped,
            hasHeadBag = state.hasHeadBag,
            hasTrackingBand = state.hasTrackingBand,
        }
    end

    resolveCache = {
        frame = frame,
        entity = entity,
        id = serverId,
        s = targetState,
        canAct = Editable:canAct(),
    }

    return resolveCache
end

function Interactions.getJob()
    return getCachedJob()
end

function Interactions.isHandsUp(cf)
    local now = GetGameTimer()
    if handsUpCache.entity == cf.entity and now < handsUpCache.expires then
        return handsUpCache.value
    end

    local isUp = IsEntityPlayingAnim(cf.entity, HANDS_UP_DICT, HANDS_UP_CLIP, 3)
    handsUpCache.entity = cf.entity
    handsUpCache.value = isUp
    handsUpCache.expires = now + HANDS_UP_CACHE_TTL
    return isUp
end

function Interactions.getItemCount(_, itemName, metadata)
    return getCachedItemCount(itemName, metadata)
end

function Interactions.isTargetDead(state)
    return Editable:isDead(state)
end

Interactions.invalidateJobCache = invalidateJobCache
Interactions.invalidateItemCache = invalidateItemCache

function playPedAnim(ped, dict, clip, blendIn, blendOut, duration, flag, startPhase)
    if not dict then
        return
    end
    lib.requestAnimDict(dict)
    TaskPlayAnim(
        ped, dict, clip,
        blendIn or 8.0,
        blendOut or -8.0,
        duration or -1,
        flag or 49,
        startPhase or 0,
        false, false, false
    )
    RemoveAnimDict(dict)
end

function attachPedWithConfig(ped, targetPed, attachConfig)
    if not attachConfig then
        return
    end
    AttachEntityToEntity(
        ped, targetPed,
        attachConfig.bone or 11816,
        attachConfig.offset,
        attachConfig.rotation,
        false, false, false, false,
        attachConfig.type or 2,
        attachConfig.fixedRot ~= false
    )
end

CreateThread(function()
    LocalPlayer.state:set("cuffType", "none", true)

    local playerTargets = {}
    local vehicleTargets = {}

    for name, targetConfig in pairs(Config.Interactions.Targets) do
        local canInteract = targetConfig.canInteract

        if name == "OutFromVehicle" then
            vehicleTargets[#vehicleTargets + 1] = {
                name = name,
                label = targetConfig.label,
                icon = targetConfig.icon,
                distance = targetConfig.distance or 2,
                groups = targetConfig.groups or nil,
                items = targetConfig.items or nil,
                onSelect = function(data)
                    targetConfig.onSelect(data)
                end,
                canInteract = canInteract,
            }
        elseif name == "StopDragPlayer" then
            if GetResourceState("ox_target") == "started" then
                exports.ox_target:addGlobalOption({
                    {
                        name = name,
                        label = targetConfig.label,
                        icon = targetConfig.icon,
                        distance = targetConfig.distance or 2,
                        groups = targetConfig.groups or nil,
                        onSelect = function()
                            local draggingPlayer = LocalPlayer.state.draggingPlayer
                            if draggingPlayer then
                                local ped = GetPlayerPed(GetPlayerFromServerId(draggingPlayer))
                                targetConfig.onSelect(ped)
                            end
                        end,
                        canInteract = canInteract and function()
                            local draggingPlayer = LocalPlayer.state.draggingPlayer
                            if not draggingPlayer then
                                return false
                            end
                            return canInteract(GetPlayerPed(GetPlayerFromServerId(draggingPlayer)))
                        end or nil,
                    },
                })
            else
                playerTargets[#playerTargets + 1] = {
                    name = name,
                    label = targetConfig.label,
                    icon = targetConfig.icon,
                    distance = targetConfig.distance or 2,
                    groups = targetConfig.groups or nil,
                    items = targetConfig.items or nil,
                    onSelect = function(data)
                        targetConfig.onSelect(data)
                    end,
                    canInteract = canInteract,
                }
            end
        else
            playerTargets[#playerTargets + 1] = {
                name = name,
                label = targetConfig.label,
                icon = targetConfig.icon,
                distance = targetConfig.distance or 2,
                groups = targetConfig.groups or nil,
                items = targetConfig.items or nil,
                onSelect = function(data)
                    targetConfig.onSelect(data)
                end,
                canInteract = canInteract,
            }
        end
    end

    Bridge.Target.addPlayer(playerTargets)
    Bridge.Target.addVehicle(vehicleTargets)
end)

function Interactions.createCuffProp(self, cuffType, isFront)
    local cuffModel = Config.Interactions.Cuffs.Models[cuffType]
    if not cuffModel then
        return
    end

    local model = lib.requestModel(cuffModel.model)
    self.cuffProp = CreateObject(model, GetEntityCoords(cache.ped), true, true, true)
    local netId = self:getNetIdFromEntity(self.cuffProp)

    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, false)
    NetworkSetNetworkIdDynamic(netId, true)

    local side = isFront and "front" or "rear"
    AttachEntityToEntity(
        self.cuffProp, cache.ped,
        GetPedBoneIndex(cache.ped, 60309),
        cuffModel.coords[side], cuffModel.rotation[side],
        true, true, false, true, 1, true
    )
    SetModelAsNoLongerNeeded(model)
end

function Interactions.destroyCuffProp(self)
    if self.cuffProp and DoesEntityExist(self.cuffProp) then
        DeleteObject(self.cuffProp)
    end
    self.cuffProp = nil
end

function Interactions.startCuffThread(self)
    local idleAnims = Config.Interactions.Cuffs.Animations.idle
    local disableKeys = Config.Interactions.DisableKeys
    local hardcuffKeys = disableKeys.hardcuff
    local cuffKeys = disableKeys.cuff

    CreateThread(function()
        while self.isCuffed do
            Wait(500)
            if not self.isCuffed then
                break
            end

            local idleAnim = idleAnims[self.cuffSide]
            if idleAnim and not IsEntityPlayingAnim(cache.ped, idleAnim.dict, idleAnim.clip, 3) then
                playPedAnim(
                    cache.ped,
                    idleAnim.dict,
                    idleAnim.clip,
                    8.0, -8.0, -1,
                    idleAnim.flag or 49,
                    1
                )
            end
        end
    end)

    CreateThread(function()
        while self.isCuffed do
            Wait(1)
            if self.isHard then
                DisableAllControlActions(0)
                if hardcuffKeys then
                    for _, control in pairs(hardcuffKeys) do
                        EnableControlAction(0, control, true)
                        EnableControlAction(1, control, true)
                    end
                end
            else
                for _, control in pairs(cuffKeys) do
                    DisableControlAction(0, control, true)
                    DisableControlAction(1, control, true)
                end
            end
        end
    end)
end

function Interactions.clearRopeTimer(self)
    if self.ropeTimer then
        self.ropeTimer:forceEnd(false)
        self.ropeTimer = nil
    end
end

function Interactions.startRopeTimer(self, timerData)
    self:clearRopeTimer()

    CreateThread(function()
        self.ropeTimer = lib.timer(timerData.time, function()
            self.ropeTimer = nil
            Bridge.Notify.showNotify(locale("cable_ties_came_loose"))
            self.isCuffed = false
            LocalPlayer.state:set("isCuffed", false, true)
            LocalPlayer.state:set("cuffType", "none", true)
            Config.Interactions.OnPlayerUnCuff()
            DetachEntity(cache.ped, true, true)
            self:destroyCuffProp()
            self.isInCuffProcess = false
            Wait(100)
            ClearPedTasks(cache.ped)
        end)
    end)
end

function Interactions.handleArrestedUncuff(self, cuffData, officerPed, useFrontAnim)
    self.isInCuffProcess = true

    local uncuffAnim = Config.Interactions.Cuffs.Animations.uncuff.arrested
    local isDead = self:isPlayerDead(cache.serverId)
    self:clearRopeTimer()
    self.isCuffed = false
    Wait(100)

    if isDead then
        SetTimeout(uncuffAnim.deadDuration or 3000, function()
            DetachEntity(cache.ped)
            LocalPlayer.state:set("isCuffed", false, true)
            Config.Interactions.OnPlayerUnCuff()
            self:destroyCuffProp()
            self.isInCuffProcess = false
            Wait(500)
            ClearPedTasks(cache.ped)
        end)
        return
    end

    local animSide = (useFrontAnim and uncuffAnim.front) or uncuffAnim.rear
    attachPedWithConfig(cache.ped, officerPed, animSide.attach)
    Sounds:playSound("uncuff", 0.5)

    if animSide.dict then
        playPedAnim(
            cache.ped,
            animSide.dict,
            animSide.clip,
            8.0, -8.0,
            animSide.duration or 6000,
            animSide.flag or 33,
            0
        )
    end

    SetTimeout(animSide.duration or 4500, function()
        DetachEntity(cache.ped)
        LocalPlayer.state:set("isCuffed", false, true)
        Config.Interactions.OnPlayerUnCuff()
        self:destroyCuffProp()
        self.isInCuffProcess = false
        Wait(1500)
        ClearPedTasks(cache.ped)
    end)
end

function Interactions.handleArrestedCuff(self, cuffData, officerPed, skipFrontCheck)
    self.isInCuffProcess = true

    local cuffAnims = Config.Interactions.Cuffs.Animations.cuff.arrested
    local isDead = self:isPlayerDead(cache.serverId)
    LocalPlayer.state:set("isCuffed", true, true)
    Sounds:playSound("cuff", 0.5)

    local cuffProcessKeys = Config.Interactions.DisableKeys.cuff
    CreateThread(function()
        while self.isInCuffProcess do
            Wait(1)
            for _, control in pairs(cuffProcessKeys) do
                DisableControlAction(0, control, true)
                DisableControlAction(1, control, true)
            end
        end
    end)

    if cuffData.type == "cable_ties" and cuffData.timer and cuffData.time then
        self:startRopeTimer({ time = cuffData.time })
    end

    if IsEntityAttached(cache.ped) then
        DetachEntity(cache.ped)
        Wait(10)
    end

    if IsEntityAttached(officerPed) then
        DetachEntity(officerPed)
        Wait(10)
    end

    local animConfig
    if cuffData.front then
        if Config.Interactions.Cuffs.cuffAnimation == "basic" then
            animConfig = cuffAnims.frontBasic
        else
            animConfig = cuffAnims.frontAdvanced
        end
    elseif isDead and cuffAnims.rearDead then
        animConfig = cuffAnims.rearDead
    else
        animConfig = cuffAnims.rearAlive
    end

    if isDead then
        ClearPedTasks(cache.ped)
    end

    attachPedWithConfig(cache.ped, officerPed, animConfig.attach)

    if animConfig.dict then
        playPedAnim(
            cache.ped,
            animConfig.dict,
            animConfig.clip,
            8.0, -8.0,
            animConfig.duration or 5000,
            animConfig.flag or 33,
            0
        )
    end

    FreezeEntityPosition(cache.ped, true)

    if not isDead then
        if Config.Interactions.Cuffs.cuffGame(cuffData.isHard) then
            LocalPlayer.state:set("isCuffed", false, true)
            DetachEntity(cache.ped)
            ClearPedTasksImmediately(cache.ped)
            FreezeEntityPosition(cache.ped, false)
            self.isInCuffProcess = false
            return
        end
    end

    SetTimeout(950, function()
        self.cuffSide = cuffData.front and "front" or "rear"
        DetachEntity(cache.ped)
        FreezeEntityPosition(cache.ped, false)
        LocalPlayer.state:set("isCuffed", true, true)
        LocalPlayer.state:set("cuffType", cuffData.type, true)
        self.isCuffed = true

        local waitTime = 3000
        if isDead then
            waitTime = 4500
        elseif skipFrontCheck then
            waitTime = 1000
        end
        Wait(waitTime)

        self:createCuffProp(cuffData.type, cuffData.front)
        Config.Interactions.OnPlayerCuff()
        self:startCuffThread()
        self.isInCuffProcess = false
    end)
end

function Interactions.handleOfficerUncuff(self, cuffData)
    self.isInCuffProcess = true

    local officerAnims = Config.Interactions.Cuffs.Animations.uncuff.officer
    local animConfig = self:isPlayerDead(cuffData.player) and officerAnims.dead or officerAnims.alive

    Wait(150)
    Sounds:playSound("uncuff", 0.5)

    if animConfig.dict then
        playPedAnim(
            cache.ped,
            animConfig.dict,
            animConfig.clip,
            8.0, -8.0,
            animConfig.duration or 6000,
            animConfig.flag or 33,
            0
        )
    end

    SetTimeout((animConfig.duration or 6000) + 100, function()
        self.isInCuffProcess = false
    end)
end

function Interactions.handleOfficerCuff(self, cuffData, targetPed, isFront)
    self.isInCuffProcess = true

    local officerAnims = Config.Interactions.Cuffs.Animations.cuff.officer
    local isDead = self:isPlayerDead(cuffData.player)

    if IsEntityAttached(cache.ped) then
        DetachEntity(cache.ped)
        Wait(10)
    end

    if IsEntityAttached(targetPed) then
        DetachEntity(targetPed)
        Wait(10)
    end

    Wait(400)

    local animConfig
    if isDead then
        animConfig = officerAnims.rearDead
    elseif isFront then
        animConfig = officerAnims.frontAlive
    else
        animConfig = officerAnims.rearAlive
    end

    Sounds:playSound("cuff", 0.5)

    if animConfig and animConfig.dict then
        playPedAnim(
            cache.ped,
            animConfig.dict,
            animConfig.clip,
            8.0, -8.0,
            animConfig.duration or 4500,
            animConfig.flag or 33,
            0
        )
    end

    local duration = (animConfig and animConfig.duration) or 4500
    SetTimeout(duration + 100, function()
        self.isInCuffProcess = false
    end)
end

RegisterNetEvent("p_policejob/client/interactions/HandCuffsAnimation", function(cuffData)
    if not cuffData or type(cuffData) ~= "table" or not cuffData.player or cuffData.player < 1 then
        return
    end

    if cuffData.isArrested then
        RemoveAllPedWeapons(cache.ped, true)
    end

    Wait(1)

    Interactions.isHard = cuffData.isHard

    local targetPed = GetPlayerPed(GetPlayerFromServerId(cuffData.player))
    if not targetPed or targetPed == 0 or targetPed == cache.ped then
        return
    end

    local idleAnims = Config.Interactions.Cuffs.Animations.idle
    local skipFrontCheck = cuffData.front

    if not skipFrontCheck then
        local checkPed = cuffData.isArrested and cache.ped or targetPed
        skipFrontCheck = IsEntityPlayingAnim(checkPed, idleAnims.front.dict, idleAnims.front.clip, 3)
    end

    if cuffData.isCuff and Config.Interactions.Cuffs.cuffAnimation == "basic" then
        skipFrontCheck = true
    end

    if cuffData.isArrested then
        if cuffData.isCuff then
            Interactions:handleArrestedCuff(cuffData, targetPed, skipFrontCheck)
        else
            Interactions:handleArrestedUncuff(cuffData, targetPed, skipFrontCheck)
        end
    elseif cuffData.isCuff then
        Interactions:handleOfficerCuff(cuffData, targetPed, skipFrontCheck)
    else
        Interactions:handleOfficerUncuff(cuffData)
    end
end)

RegisterNetEvent("p_policejob/client/interactions/ForceUncuff", function()
    Wait(100)
    if LocalPlayer.state.isCuffed then
        return
    end

    Interactions.isCuffed = false
    Interactions:clearRopeTimer()
    Config.Interactions.OnPlayerUnCuff()
    DetachEntity(cache.ped, true, true)
    Interactions:destroyCuffProp()
    Interactions.isInCuffProcess = false
    Wait(100)
    ClearPedTasks(cache.ped)
end)

RegisterNetEvent("p_policejob/client/interactions/ForceCuff", function()
    Interactions.cuffSide = "rear"
    DetachEntity(cache.ped)
    FreezeEntityPosition(cache.ped, false)
    Interactions.isCuffed = true
    Interactions:createCuffProp("cuffs", false)
    Config.Interactions.OnPlayerCuff()
    Interactions:startCuffThread()
    Interactions.isInCuffProcess = false
end)

AddEventHandler("gameEventTriggered", function(eventName, eventData)
    if eventName ~= "CEventNetworkEntityDamage" then
        return
    end

    local damagedPed = eventData[1]
    if not IsPedAPlayer(damagedPed) then
        return
    end

    if NetworkGetPlayerIndexFromPed(damagedPed) ~= cache.playerId then
        return
    end

    if not LocalPlayer.state.isCuffed then
        return
    end

    ClearPedTasks(cache.ped)
    Wait(100)

    while IsPedRagdoll(cache.ped) do
        Wait(250)
    end

    ClearPedTasks(cache.ped)
end)

RegisterNetEvent("p_policejob/client/interactions/StartDrag", function(dragData)
    if not dragData.state then
        Interactions.dragStatus.draggingPlayer = nil
        Interactions.dragStatus.draggedBy = nil
        Wait(100)
        ClearPedTasks(cache.ped)
        return
    end

    if dragData.isDragging then
        Interactions.dragStatus.draggingPlayer = dragData.player

        CreateThread(function()
            local dragAnim = Config.Interactions.Drag.animation
            while Interactions.dragStatus.draggingPlayer do
                Wait(1000)

                if not Interactions.dragStatus.draggingPlayer then
                    break
                end

                if not IsEntityPlayingAnim(cache.ped, dragAnim.dict, dragAnim.clip, 3) then
                    playPedAnim(
                        cache.ped,
                        dragAnim.dict,
                        dragAnim.clip,
                        -8.0, -8.0, -1,
                        dragAnim.flag or 49,
                        0
                    )
                end

                local draggedPed = GetPlayerPed(GetPlayerFromServerId(Interactions.dragStatus.draggingPlayer))
                if not draggedPed or draggedPed == 0 or draggedPed == cache.ped or not DoesEntityExist(draggedPed) then
                    ClearPedTasks(cache.ped)
                    LocalPlayer.state:set("draggingPlayer", false, true)
                    Interactions.dragStatus.draggingPlayer = nil
                    DetachEntity(cache.ped, true, true)
                    Config.Interactions.OnStopPlayerDrag()
                end
            end
        end)

        CreateThread(function()
            Wait(1500)
            local oxTargetStarted = GetResourceState("ox_target") == "started"
            if not oxTargetStarted then
                lib.showTextUI(locale("stop_drag_textui"))
            end

            while LocalPlayer.state.draggingPlayer do
                Wait(1)
                SetPlayerMayNotEnterAnyVehicle(cache.playerId)

                for _, control in pairs(Config.Interactions.DisableKeys.drag) do
                    DisableControlAction(0, control, true)
                end

                if not oxTargetStarted then
                    local cancelKey = Config.Interactions.Drag.cancelKey
                    if IsControlJustReleased(0, cancelKey) or IsDisabledControlJustReleased(0, cancelKey) then
                        TriggerServerEvent("p_policejob/server/interactions/DragPlayer", {
                            state = false,
                            player = LocalPlayer.state.draggingPlayer,
                        })
                        break
                    end
                end
            end

            if not oxTargetStarted then
                lib.hideTextUI()
            end
        end)
    else
        Interactions.dragStatus.draggedBy = dragData.player
        Config.Interactions.OnStartPlayerDrag()
        Interactions:startDragThread()
    end
end)

function Interactions.startDragThread(self)
    local isAttached = false

    CreateThread(function()
        while true do
            local waitTime = 1000
            local draggedBy = self.dragStatus.draggedBy

            if draggedBy then
                if self.isCuffed or self:isPlayerDead(cache.serverId) then
                    waitTime = 250
                    local draggerPed = GetPlayerPed(GetPlayerFromServerId(draggedBy))

                    if DoesEntityExist(draggerPed) then
                        if not isAttached then
                            AttachEntityToEntity(
                                cache.ped, draggerPed, 1816,
                                0.15, 0.42, 0.0,
                                0.0, 0.0, 0.0,
                                false, false, false, false, 2, true
                            )
                            isAttached = true
                        else
                            waitTime = 750
                        end
                    else
                        DetachEntity(cache.ped, true, true)
                        isAttached = false
                        self.dragStatus.draggedBy = nil
                        Config.Interactions.OnStopPlayerDrag()
                        break
                    end
                elseif isAttached then
                    DetachEntity(cache.ped, true, true)
                    isAttached = false
                    self.dragStatus.draggedBy = nil
                    Config.Interactions.OnStopPlayerDrag()
                    break
                end
            elseif isAttached then
                DetachEntity(cache.ped, true, true)
                isAttached = false
                self.dragStatus.draggedBy = nil
                Config.Interactions.OnStopPlayerDrag()
                break
            end

            Wait(waitTime)
        end
    end)

    CreateThread(function()
        local draggerPed = GetPlayerPed(GetPlayerFromServerId(self.dragStatus.draggedBy))

        while self.dragStatus.draggedBy do
            Wait(100)

            if DoesEntityExist(draggerPed) then
                if GetEntitySpeed(draggerPed) > 1 and not self:isPlayerDead(cache.serverId) then
                    local walkDict = "move_m@generic_variations@walk"
                    if not IsEntityPlayingAnim(cache.ped, walkDict, "walk_b", 3) then
                        playPedAnim(cache.ped, walkDict, "walk_b", 8.0, -8.0, -1, 0, 1)
                    end
                end
            else
                self.dragStatus.draggedBy = nil
            end
        end
    end)
end

function Interactions.quickEscort(self, targetServerId)
    if cache.vehicle and cache.vehicle ~= 0 then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end

    local draggingPlayer = LocalPlayer.state.draggingPlayer
    if draggingPlayer then
        TriggerServerEvent("p_policejob/server/interactions/DragPlayer", {
            state = false,
            player = draggingPlayer,
        })
        return
    end

    if not targetServerId then
        local closestPlayer = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0, false)
        if not closestPlayer or closestPlayer == 0 then
            return
        end
        targetServerId = GetPlayerServerId(closestPlayer)
    end

    TriggerServerEvent("p_policejob/server/interactions/DragPlayer", {
        state = true,
        player = targetServerId,
    })
end

RegisterCommand("escort", function()
    Interactions:quickEscort()
end, false)

RegisterNetEvent("p_policejob/client/interactions/TakeOutVehicle", function()
    if not IsPedSittingInAnyVehicle(cache.ped) then
        return
    end

    local vehicle = GetVehiclePedIsIn(cache.ped, false)
    TaskLeaveVehicle(cache.ped, vehicle, 16)
    Wait(1000)
    ClearPedTasksImmediately(cache.ped)
end)

RegisterNetEvent("p_policejob/client/interactions/PutInVehicle", function(data)
    if IsPedSittingInAnyVehicle(cache.ped) then
        return
    end

    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0, false)
    if not vehicle or not IsVehicleSeatFree(vehicle, data.seat) then
        return
    end

    if Interactions:isPlayerDead(cache.serverId) then
        SetPedIntoVehicle(cache.ped, vehicle, data.seat)
    else
        TaskWarpPedIntoVehicle(cache.ped, vehicle, data.seat)
    end

    Interactions.dragStatus.draggedBy = nil
    LocalPlayer.state:set("draggedBy", false, true)
    Player(data.player).state:set("draggingPlayer", false, true)
end)

function Interactions.searchPlayer(self, targetPed, targetServerId)
    local searchConfig = Config.Interactions.Search
    local completed = Bridge.Progress.Start({
        duration = searchConfig.duration,
        label = locale("searching_player"),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = searchConfig.animation.dict,
            clip = searchConfig.animation.clip,
        },
    })

    if not completed then
        return
    end

    local targetState = Player(targetServerId).state
    if targetState.isCuffed
        or IsEntityPlayingAnim(targetPed, HANDS_UP_DICT, HANDS_UP_CLIP, 3)
        or self:isPlayerDead(targetServerId)
    then
        Bridge.Inventory.openInventory("player", targetServerId)
    end
end

lib.callback.register("p_policejob/client/interactions/attemptOpenCuffs", function()
    local lockpickConfig = Config.Interactions.LockpickCuffs

    if lockpickConfig.animation.enabled then
        playPedAnim(
            cache.ped,
            lockpickConfig.animation.dict,
            lockpickConfig.animation.clip,
            -8.0, 8.0, -1,
            lockpickConfig.animation.flag or 49,
            1
        )
    end

    local success = lockpickConfig.miniGame()
    ClearPedTasks(cache.ped)
    return success
end)

AddEventHandler("CEventGunShot", function()
    local ped = cache.ped or PlayerPedId()
    if IsPedShooting(ped) then
        lastGunshotAt = GetGameTimer()
    end
end)

CreateThread(function()
    while true do
        Wait(2500)
        if lastGunshotAt ~= 0 and (IsPedSwimming(cache.ped) or IsEntityInWater(cache.ped)) then
            lastGunshotAt = 0
        end
    end
end)

lib.callback.register("p_policejob/client/evidence/checkGunPowder", function()
    if lastGunshotAt == 0 then
        return false
    end

    local windowMs = Config.Interactions.GunPowder?.WindowMs or 300000
    return windowMs >= (GetGameTimer() - lastGunshotAt)
end)

function Interactions.createHeadBag(self)
    local headBagConfig = Config.Interactions.HeadBag
    local model = lib.requestModel(headBagConfig.model)
    self.headBagData.object = CreateObject(model, GetEntityCoords(cache.ped), true, true, true)

    AttachEntityToEntity(
        self.headBagData.object, cache.ped,
        GetPedBoneIndex(cache.ped, headBagConfig.bone),
        headBagConfig.coords, headBagConfig.rotation,
        true, true, false, true, 1, true
    )
    SetEntityCompletelyDisableCollision(self.headBagData.object, false, true)
    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent("p_policejob/client/interactions/ToggleHeadBag", function(state)
    Interactions.headBagData.state = state
    Wait(10)

    if Interactions.headBagData.object and DoesEntityExist(Interactions.headBagData.object) then
        DeleteEntity(Interactions.headBagData.object)
    end

    SendNUIMessage({
        action = "setVisibleHeadBag",
        data = state,
    })

    if state then
        Interactions:createHeadBag()
    end
end)

CreateThread(function()
    while true do
        Wait(3000)
        if Interactions.headBagData.state then
            if Interactions.headBagData.object and not DoesEntityExist(Interactions.headBagData.object) then
                Interactions:createHeadBag()
            end
        end
    end
end)

AddStateBagChangeHandler("mouthTaped", nil, function(bagName, _, value, _, replicated)
    if replicated then
        return
    end

    local playerId = GetPlayerFromStateBagName(bagName)
    if playerId == 0 then
        return
    end

    local playerPed = GetPlayerPed(playerId)
    local serverId = GetPlayerServerId(playerId)

    if not value then
        local existingProp = Interactions.mouthTapes[serverId]
        if existingProp and DoesEntityExist(existingProp) then
            DeleteEntity(existingProp)
            Interactions.mouthTapes[serverId] = nil
        end

        if cache.serverId == serverId then
            Interactions._mouthTapeActive = false
        end
        return
    end

    Wait(1)

    local mouthTapeConfig = Config.Interactions.MouthTape
    local model = lib.requestModel(mouthTapeConfig.model)
    local prop = CreateObject(model, GetEntityCoords(playerPed), false, false, false)

    AttachEntityToEntity(
        prop, playerPed,
        GetPedBoneIndex(playerPed, mouthTapeConfig.bone),
        mouthTapeConfig.coords, mouthTapeConfig.rotation,
        true, true, false, true, 1, true
    )
    SetEntityAsMissionEntity(prop, true, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityCollision(prop, true, false)
    Interactions.mouthTapes[serverId] = prop

    if cache.serverId ~= serverId then
        return
    end

    if Interactions._mouthTapeActive then
        return
    end

    Interactions._mouthTapeActive = true

    CreateThread(function()
        while Interactions._mouthTapeActive do
            Wait(1000)

            if GetResourceState("pma-voice") == "started" then
                exports["pma-voice"]:overrideProximityCheck(function()
                    return false
                end)
            elseif GetResourceState("yaca-voice") == "started" then
                exports["yaca-voice"]:setMaxVoiceRange(0.0)
            end
        end

        Wait(1000)

        if GetResourceState("pma-voice") == "started" then
            exports["pma-voice"]:resetProximityCheck()
        elseif GetResourceState("yaca-voice") == "started" then
            exports["yaca-voice"]:setMaxVoiceRange(-1)
        end
    end)
end)

lib.callback.register("p_policejob/client/interactions/RequestCarryPlayer", function(requestData)
    if Interactions.carryData.isActive then
        return false
    end
    return Config.Interactions.Carry.onRequest(requestData)
end)

function playCarryAnim()
    local carryAnim = Config.Interactions.Carry.animation[Interactions.carryData.role]
    if not carryAnim then
        return
    end
    playPedAnim(
        cache.ped,
        carryAnim.dict,
        carryAnim.clip,
        8.0, -8.0, -1,
        carryAnim.flag,
        0
    )
end

function stopCarryLocally()
    local carryData = Interactions.carryData
    if not carryData.isActive then
        return
    end

    carryData.isActive = false
    carryData.playerId = nil
    carryData.playerPed = nil
    Wait(1)
    ClearPedSecondaryTask(cache.ped)
    DetachEntity(cache.ped, true, false)
end

RegisterNetEvent("p_policejob/client/interactions/StopCarryPlayer", stopCarryLocally)

RegisterNetEvent("p_policejob/client/interactions/StartCarryPlayer", function(carryData)
    local localCarry = Interactions.carryData
    if localCarry.isActive then
        return
    end

    localCarry.isActive = true
    localCarry.playerId = carryData.playerId
    localCarry.playerPed = GetPlayerPed(GetPlayerFromServerId(localCarry.playerId))

    if carryData.isCarrying then
        localCarry.role = "carrying"
        Wait(1)
        playCarryAnim()
    else
        localCarry.role = "carried"
        Wait(1)
        playCarryAnim()

        local carriedAnim = Config.Interactions.Carry.animation.carried
        AttachEntityToEntity(
            cache.ped, localCarry.playerPed, 0,
            carriedAnim.offset.coords, carriedAnim.offset.rotation,
            false, false, false, false, 2, false
        )
    end

    CreateThread(function()
        while localCarry.isActive do
            Wait(100)

            if not localCarry.isActive then
                break
            end

            local roleAnim = Config.Interactions.Carry.animation[localCarry.role]
            if roleAnim and not IsEntityPlayingAnim(cache.ped, roleAnim.dict, roleAnim.clip, 3) then
                playCarryAnim()
            end

            local partnerPed = GetPlayerPed(GetPlayerFromServerId(localCarry.playerId))
            if not partnerPed or partnerPed == 0 or partnerPed == cache.ped or not DoesEntityExist(partnerPed) then
                stopCarryLocally()
            end
        end
    end)
end)

CreateThread(function()
    local stopCarryKey = Config.Interactions.Carry.stopCarryKey
    if not stopCarryKey then
        return
    end

    lib.addKeybind({
        name = "policejob:stopcarry",
        description = locale("stop_carry_player_bind"),
        defaultKey = stopCarryKey,
        onPressed = function()
            local carryData = Interactions.carryData
            if not carryData.isActive or carryData.role ~= "carrying" then
                return
            end
            TriggerServerEvent("p_policejob/server/interactions/StopCarryPlayer", carryData.playerId)
        end,
    })
end)

exports("handcuffs", function()
    if not Config.Interactions.Cuffs.usableItem then
        return
    end

    if cache.vehicle and cache.vehicle ~= 0 then
        return
    end

    local closestPlayer, closestPed = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
    if not closestPlayer or closestPlayer == 0 or IsPedSittingInAnyVehicle(closestPed) then
        return
    end

    local targetServerId = GetPlayerServerId(closestPlayer)
    local cuffAction = Config.Interactions.Cuffs.cuffItemCheck(closestPed, targetServerId)
    if not cuffAction then
        return
    end

    if cuffAction == "cuff" then
        TriggerServerEvent("p_policejob/server/interactions/HandCuffs", {
            type = "cuffs",
            state = true,
            player = targetServerId,
            front = Interactions:isInFront(closestPed),
        })
    else
        TriggerServerEvent("p_policejob/server/interactions/HandCuffs", {
            type = "cuffs",
            state = false,
            player = targetServerId,
        })
    end
end)

RegisterNetEvent("p_policejob/useHandcuffs", function()
    exports.p_policejob:handcuffs()
end)

RegisterNetEvent("p_policejob/hardCuff", function()
    if cache.vehicle and cache.vehicle ~= 0 then
        return
    end

    local closestPlayer, closestPed = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
    if not closestPlayer or closestPlayer == 0 then
        return
    end

    local targetServerId = GetPlayerServerId(closestPlayer)
    TriggerServerEvent("p_policejob/server/interactions/HandCuffs", {
        type = "cuffs",
        state = not Player(targetServerId).state.isCuffed,
        player = targetServerId,
        front = Interactions:isInFront(closestPed),
        isHard = true,
    })
end)

RegisterNetEvent("p_policejob/softCuff", function()
    if cache.vehicle and cache.vehicle ~= 0 then
        return
    end

    local closestPlayer, closestPed = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
    if not closestPlayer or closestPlayer == 0 then
        return
    end

    local localState = LocalPlayer.state
    if localState.draggingPlayer or localState.carryingPlayer then
        return
    end

    local targetServerId = GetPlayerServerId(closestPlayer)
    TriggerServerEvent("p_policejob/server/interactions/HandCuffs", {
        type = "cuffs",
        state = not Player(targetServerId).state.isCuffed,
        player = targetServerId,
        front = Interactions:isInFront(closestPed),
        isHard = false,
    })
end)

RegisterNetEvent("p_policejob/tiePlayer", function()
    if cache.vehicle and cache.vehicle ~= 0 then
        return
    end

    local closestPlayer, closestPed = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
    if not closestPlayer or closestPlayer == 0 then
        return
    end

    local targetServerId = GetPlayerServerId(closestPlayer)
    TriggerServerEvent("p_policejob/server/interactions/HandCuffs", {
        type = "cable_ties",
        state = not Player(targetServerId).state.isCuffed,
        player = targetServerId,
        timer = true,
        time = Config.Interactions.Cuffs.cableTieTimer,
        front = Interactions:isInFront(closestPed),
    })
end)

RegisterNetEvent("p_policejob/searchPlayer", function()
    if cache.vehicle and cache.vehicle ~= 0 then
        return
    end

    local closestPlayer, closestPed = lib.getClosestPlayer(GetEntityCoords(cache.ped), 5.0, false)
    if not closestPlayer or closestPlayer == 0 then
        return
    end

    Interactions:searchPlayer(closestPed, GetPlayerServerId(closestPlayer))
end)

RegisterNetEvent("p_policejob/escortPlayer", function()
    if cache.vehicle and cache.vehicle ~= 0 then
        return
    end

    local draggingPlayer = LocalPlayer.state.draggingPlayer
    if draggingPlayer and type(draggingPlayer) == "number" then
        TriggerServerEvent("p_policejob/server/interactions/DragPlayer", {
            state = false,
            player = draggingPlayer,
        })
        return
    end

    local closestPlayer = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
    if not closestPlayer or closestPlayer == 0 then
        return
    end

    TriggerServerEvent("p_policejob/server/interactions/DragPlayer", {
        state = true,
        player = GetPlayerServerId(closestPlayer),
    })
end)

for _, eventName in ipairs({ "esx_policejob:handcuff", "police:client:CuffPlayer" }) do
    RegisterNetEvent(eventName, function()
        TriggerEvent("p_policejob/softCuff")
    end)
end

for _, eventName in ipairs({ "esx_policejob:search", "police:client:SearchPlayer", "police:client:RobPlayer" }) do
    RegisterNetEvent(eventName, function()
        TriggerEvent("p_policejob/searchPlayer")
    end)
end

for _, eventName in ipairs({ "esx_policejob:drag", "esx_policejob:escort", "police:client:EscortPlayer" }) do
    RegisterNetEvent(eventName, function()
        TriggerEvent("p_policejob/escortPlayer")
    end)
end

for _, eventName in ipairs({ "esx_policejob:putInVehicle", "police:client:PutInVehicle" }) do
    RegisterNetEvent(eventName, function()
        if cache.vehicle and cache.vehicle ~= 0 then
            return
        end

        local closestPlayer = lib.getClosestPlayer(GetEntityCoords(cache.ped), 3.0, false)
        if not closestPlayer or closestPlayer == 0 then
            return
        end

        TriggerServerEvent("p_policejob/server/interactions/PutInVehicle", {
            seat = -1,
            player = GetPlayerServerId(closestPlayer),
        })
    end)
end

for _, eventName in ipairs({ "esx_policejob:OutVehicle", "police:client:SetOutVehicle" }) do
    RegisterNetEvent(eventName, function()
        if cache.vehicle and cache.vehicle ~= 0 then
            return
        end

        local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), 5.0, false)
        if not vehicle or vehicle == 0 then
            return
        end

        for seat = -1, 6 do
            local occupant = GetPedInVehicleSeat(vehicle, seat)
            if occupant and occupant ~= 0 then
                local occupantServerId = getServerIdFromPed(occupant)
                if occupantServerId ~= 0 then
                    TriggerServerEvent("p_policejob/server/interactions/OutVehicle", {
                        seat = seat,
                        player = occupantServerId,
                    })
                    return
                end
            end
        end
    end)
end

function openPoliceMenu()
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Jobs[job.name] then
        return
    end

    local menuOptions = {}
    local playerCoords = GetEntityCoords(cache.ped)
    local _, closestPed = lib.getClosestPlayer(playerCoords, 4.0, false)
    local closestVehicle = lib.getClosestVehicle(playerCoords, 5.0, false)

    for name, targetConfig in pairs(Config.Interactions.Targets) do
        if name == "PutInVehicle" then
            if closestVehicle and closestVehicle ~= 0 then
                for seat = -1, 6 do
                    if IsVehicleSeatFree(closestVehicle, seat) then
                        local seatLabel = seatLabels[tostring(seat)] or locale("addon_seat")
                        menuOptions[#menuOptions + 1] = {
                            label = targetConfig.label:format(seatLabel),
                            args = { name = name, seat = seat },
                            close = false,
                        }
                    end
                end
            end
        elseif name == "OutFromVehicle" then
            if closestVehicle and closestVehicle ~= 0 then
                local canInteract = targetConfig.canInteract and targetConfig.canInteract(closestVehicle)
                if canInteract then
                    menuOptions[#menuOptions + 1] = {
                        label = targetConfig.label,
                        args = { name = name },
                        close = true,
                    }
                end
            end
        else
            menuOptions[#menuOptions + 1] = {
                label = targetConfig.label,
                args = { name = name },
                close = false,
            }
        end
    end

    lib.registerMenu({
        id = "police_menu",
        title = locale("police_menu"),
        options = menuOptions,
    }, function(_, _, args)
        if Interactions.isInCuffProcess then
            return
        end

        local targetConfig = Config.Interactions.Targets[args.name]
        if not targetConfig then
            return
        end

        local targetEntity
        if args.name == "OutFromVehicle" then
            targetEntity = lib.getClosestVehicle(GetEntityCoords(cache.ped), 4.0, false)
            if not targetEntity or targetEntity == 0 then
                Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
                return
            end
        else
            local _, ped = lib.getClosestPlayer(GetEntityCoords(cache.ped), 4.0, false)
            if not ped or ped == 0 then
                Bridge.Notify.showNotify(locale("no_players_nearby"), "error")
                return
            end
            targetEntity = ped
        end

        if targetConfig.canInteract then
            local seat = args.seat or nil
            if not targetConfig.canInteract(targetEntity, seat) then
                Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
                return
            end
        end

        targetConfig.onSelect(targetEntity, args.seat or nil)
    end)

    lib.showMenu("police_menu")
end

if Config.Interactions.PoliceMenu.enabled then
    RegisterCommand(Config.Interactions.PoliceMenu.command, openPoliceMenu)
    RegisterKeyMapping(
        Config.Interactions.PoliceMenu.command,
        locale("police_menu"),
        "keyboard",
        Config.Interactions.PoliceMenu.key
    )
end
