if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

if not Config.Prison.CommunityService or not Config.Prison.CommunityService.enabled then
    return
end

local communityConfig = Config.Prison.CommunityService
local sentenceData = nil
local trashPickupPool = {}
local activePileByPoolIndex = {}
local trashPiles = {}
local nextPileId = 0
local areaBlip = nil
local carriedBag = nil
local dumpsterState = nil
local trashMinigameCallback = nil

function pickRandomUnusedPoolIndex()
    local available = {}
    for index = 1, #trashPickupPool do
        if not activePileByPoolIndex[index] then
            available[#available + 1] = index
        end
    end
    if #available == 0 then
        return nil
    end
    return available[math.random(#available)]
end

function removeCommunitySphereZone(zoneId)
    if not zoneId then
        return
    end
    if Bridge.Target and Bridge.Target.removeSphereZone then
        pcall(Bridge.Target.removeSphereZone, zoneId)
    end
end

function deleteEntityIfExists(entity)
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

function spawnCommunityProp(model, coords)
    local modelHash = type(model) == "number" and model or joaat(model)
    lib.requestModel(modelHash, 5000)
    if not HasModelLoaded(modelHash) then
        return nil
    end

    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    local prop = CreateObject(
        modelHash, coords.x, coords.y,
        foundGround and groundZ or coords.z,
        false, false, false
    )
    PlaceObjectOnGroundProperly(prop)
    if coords.w then
        SetEntityHeading(prop, coords.w)
    end
    FreezeEntityPosition(prop, true)
    SetModelAsNoLongerNeeded(modelHash)
    return prop
end

function teleportWithFade(coords)
    DoScreenFadeOut(400)
    Wait(400)
    SetEntityCoords(cache.ped, coords.x, coords.y, coords.z, false, false, false, true)
    if coords.w then
        SetEntityHeading(cache.ped, coords.w)
    end
    Wait(300)
    DoScreenFadeIn(400)
end

function runCommunityTrashMinigame()
    local promiseObj = promise.new()

    function resolveTrashMinigame(success)
        if promiseObj then
            local resolve = promiseObj.resolve
            promiseObj = nil
            resolve(success == true)
        end
    end

    trashMinigameCallback = resolveTrashMinigame
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "setVisibleCommunityTrash",
        data = {
            required = communityConfig.requiredPickups or 6,
            time = communityConfig.minigameTime or 16,
        },
    })

    local success = Citizen.Await(promiseObj)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleCommunityTrash", data = false })
    return success
end

RegisterNUICallback("prison/community/trashResult", function(data, cb)
    cb({})
    local callback = trashMinigameCallback
    trashMinigameCallback = nil
    if callback then
        callback(data and data.success == true)
    end
end)

function attachCarriedBag()
    local bagModelName = communityConfig.bagProp or "prop_cs_rub_binbag_01"
    local bagModel = joaat(bagModelName)
    lib.requestModel(bagModel, 5000)
    if not HasModelLoaded(bagModel) then
        return nil
    end

    local playerCoords = GetEntityCoords(cache.ped)
    local bag = CreateObject(bagModel, playerCoords.x, playerCoords.y, playerCoords.z, true, true, false)
    local boneIndex = GetPedBoneIndex(cache.ped, 57005)
    AttachEntityToEntity(
        bag, cache.ped, boneIndex,
        0.12, 0.02, -0.02,
        -130.0, 0.0, 0.0,
        true, true, false, true, 1, true
    )
    SetModelAsNoLongerNeeded(bagModel)
    return bag
end

function startCarryAnimation()
    local carryAnim = communityConfig.carryAnim
    if carryAnim and carryAnim.dict then
        lib.requestAnimDict(carryAnim.dict)
        TaskPlayAnim(
            cache.ped, carryAnim.dict, carryAnim.clip,
            4.0, -4.0, -1,
            49, 0, false, false, false
        )
    end
end

function stopCarryAnimation()
    local carryAnim = communityConfig.carryAnim
    if carryAnim and carryAnim.dict then
        if IsEntityPlayingAnim(cache.ped, carryAnim.dict, carryAnim.clip, 3) then
            StopAnimTask(cache.ped, carryAnim.dict, carryAnim.clip, 1.0)
        end
    end
    ClearPedSecondaryTask(cache.ped)
end

function onDumpsterSelected()
    if not carriedBag then
        Bridge.Notify.showNotify(locale("cs_need_bag"), "error")
        return
    end

    stopCarryAnimation()

    local throwAnim = communityConfig.throwAnim or { dict = "pickup_object", clip = "putdown_low" }
    lib.progressBar({
        duration = communityConfig.throwDuration or 2500,
        label = locale("cs_throwing"),
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        anim = { dict = throwAnim.dict, clip = throwAnim.clip },
    })

    deleteEntityIfExists(carriedBag.bag)
    carriedBag = nil
    ClearPedTasks(cache.ped)

    if not sentenceData then
        return
    end

    TriggerServerEvent("p_policejob/server/prison/communityTaskComplete")
    Bridge.Notify.showNotify(locale("cs_task_done"), "success")

    SetTimeout(communityConfig.respawnDelay or 4000, function()
        if not sentenceData then
            return
        end
        local poolIndex = pickRandomUnusedPoolIndex()
        if poolIndex then
            spawnTrashPileAtPoolIndex(poolIndex)
        end
    end)
end

function onTrashPileSelected(pileId)
    if not sentenceData then
        return
    end
    if carriedBag then
        Bridge.Notify.showNotify(locale("cs_carry_to_dumpster"), "error")
        return
    end

    local pile = trashPiles[pileId]
    if not pile or not pile.prop then
        return
    end

    if not runCommunityTrashMinigame() then
        Bridge.Notify.showNotify(locale("cs_minigame_fail"), "error")
        return
    end

    local pickupAnim = communityConfig.pickupAnim or { dict = "pickup_object", clip = "pickup_low" }
    local completed = lib.progressBar({
        duration = communityConfig.pickupDuration or 4000,
        label = locale("cs_picking_up"),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = pickupAnim.dict, clip = pickupAnim.clip },
    })
    if not completed then
        return
    end

    deleteEntityIfExists(pile.prop)
    removeCommunitySphereZone(pile.zoneId)
    activePileByPoolIndex[pile.poolIndex] = nil
    trashPiles[pileId] = nil

    local bag = attachCarriedBag()
    if not bag then
        return
    end

    carriedBag = { bag = bag }
    startCarryAnimation()
    Bridge.Notify.showNotify(locale("cs_carry_to_dumpster"), "info")
end

function spawnTrashPileAtPoolIndex(poolIndex)
    if not poolIndex or activePileByPoolIndex[poolIndex] then
        return
    end

    local center = trashPickupPool[poolIndex]
    if not center then
        return
    end

    local scatter = tonumber(communityConfig.scatter) or 1.2
    local angle = math.random() * 2 * math.pi
    local offset = math.sqrt(math.random()) * scatter
    local coords = vector3(
        center.x + math.cos(angle) * offset,
        center.y + math.sin(angle) * offset,
        center.z
    )

    nextPileId = nextPileId + 1
    local pileId = nextPileId
    activePileByPoolIndex[poolIndex] = pileId

    local trashModel = communityConfig.trashProp or "prop_rub_binbag_03"
    local prop = spawnCommunityProp(trashModel, coords)
    local zoneId = Bridge.Target.addSphereZone({
        coords = coords,
        radius = 1.4,
        debug = Bridge and Bridge.Config and Bridge.Config.Debug,
        options = {
            {
                name = ("p_policejob_prison_cs_pile_%d"):format(pileId),
                label = locale("cs_pickup_trash"),
                icon = "fa-solid fa-trash",
                distance = 1.8,
                onSelect = function()
                    onTrashPileSelected(pileId)
                end,
            },
        },
    })

    trashPiles[pileId] = {
        poolIndex = poolIndex,
        coords = coords,
        prop = prop,
        zoneId = zoneId,
    }
end

function setupDumpster()
    local mapData = Prison.Map and Prison.Map.communityService
    local dumpsterCoords = mapData and mapData.dumpster
    if not dumpsterCoords then
        return
    end

    dumpsterState = { coords = dumpsterCoords }
    dumpsterState.prop = spawnCommunityProp(
        communityConfig.dumpsterProp or "prop_dumpster_01a",
        dumpsterCoords
    )

    local blip = AddBlipForCoord(dumpsterCoords.x, dumpsterCoords.y, dumpsterCoords.z)
    SetBlipSprite(blip, 318)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(locale("cs_dumpster"))
    EndTextCommandSetBlipName(blip)
    dumpsterState.blip = blip

    dumpsterState.zoneId = Bridge.Target.addSphereZone({
        coords = vector3(dumpsterCoords.x, dumpsterCoords.y, dumpsterCoords.z + 0.5),
        radius = 1.6,
        debug = Bridge and Bridge.Config and Bridge.Config.Debug,
        options = {
            {
                name = "p_policejob_prison_cs_dumpster",
                label = locale("cs_dumpster"),
                icon = "fa-solid fa-dumpster",
                distance = 2.0,
                onSelect = onDumpsterSelected,
            },
        },
    })
end

function cleanupCommunityService()
    for _, pile in pairs(trashPiles) do
        deleteEntityIfExists(pile.prop)
        removeCommunitySphereZone(pile.zoneId)
    end
    trashPiles = {}
    activePileByPoolIndex = {}

    if dumpsterState then
        deleteEntityIfExists(dumpsterState.prop)
        removeCommunitySphereZone(dumpsterState.zoneId)
        if dumpsterState.blip and DoesBlipExist(dumpsterState.blip) then
            RemoveBlip(dumpsterState.blip)
        end
        dumpsterState = nil
    end

    if carriedBag then
        deleteEntityIfExists(carriedBag.bag)
        carriedBag = nil
    end

    stopCarryAnimation()

    if areaBlip and DoesBlipExist(areaBlip) then
        RemoveBlip(areaBlip)
    end
    areaBlip = nil

    if trashMinigameCallback then
        local callback = trashMinigameCallback
        trashMinigameCallback = nil
        callback(false)
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleCommunityTrash", data = false })
end

function startCommunityServiceTasks()
    cleanupCommunityService()

    local mapData = Prison.Map and Prison.Map.communityService
    if not mapData then
        return
    end

    if mapData.location then
        areaBlip = AddBlipForCoord(mapData.location.x, mapData.location.y, mapData.location.z)
        SetBlipSprite(areaBlip, 280)
        SetBlipColour(areaBlip, 5)
        SetBlipScale(areaBlip, 0.9)
        SetBlipAsShortRange(areaBlip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName("Community Service")
        EndTextCommandSetBlipName(areaBlip)
    end

    trashPickupPool = {}
    local pickupLocations = mapData.taskLocations and mapData.taskLocations.trash_pickup
    if pickupLocations then
        for _, location in ipairs(pickupLocations) do
            trashPickupPool[#trashPickupPool + 1] = vector3(location.x, location.y, location.z)
        end
    end

    local pileCount = math.min(
        tonumber(communityConfig.activePiles) or 3,
        #trashPickupPool
    )

    for _ = 1, pileCount do
        local poolIndex = pickRandomUnusedPoolIndex()
        if poolIndex then
            spawnTrashPileAtPoolIndex(poolIndex)
        end
    end

    setupDumpster()
end

function enterCommunityService(data)
    if sentenceData then
        return
    end

    sentenceData = data

    local waitAttempts = 0
    while not (Prison and Prison.Map and Prison.Map.communityService) and waitAttempts < 40 do
        Wait(100)
        waitAttempts = waitAttempts + 1
    end

    LocalPlayer.state:set("isInPrison", true, true)
    LocalPlayer.state:set("prisonSentence", data and data.remaining or 0, true)

    local mapData = Prison.Map and Prison.Map.communityService
    if mapData and mapData.location then
        teleportWithFade(mapData.location)
    end

    Bridge.Notify.showNotify(locale("community_service_arrived"), "info")
    startCommunityServiceTasks()

    if Prison and Prison.pushJailHud then
        Prison.isInPrison = true
        Prison.sentenceData = data
        Prison.cellId = data and data.cellId or nil
        Prison.sentenceData.isCommunityService = true
        Prison:pushJailHud()
    end
end

function releaseCommunityService()
    if not sentenceData then
        return
    end

    sentenceData = nil
    cleanupCommunityService()

    LocalPlayer.state:set("isInPrison", false, true)
    LocalPlayer.state:set("prisonSentence", 0, true)

    local mapData = Prison.Map and Prison.Map.communityService
    local releaseCoords = mapData and (mapData.release or mapData.location)
    if releaseCoords then
        teleportWithFade(releaseCoords)
    end

    SendNUIMessage({ action = "setVisibleJailHud", data = false })
    Bridge.Notify.showNotify(locale("community_service_released"), "success")

    if Prison then
        Prison.isInPrison = false
        Prison.sentenceData = nil
        Prison.cellId = nil
    end
end

RegisterNetEvent("p_policejob/client/prison/communityService/enter", enterCommunityService)
RegisterNetEvent("p_policejob/client/prison/communityService/release", releaseCommunityService)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanupCommunityService()
    end
end)
