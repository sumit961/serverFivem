if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

if not Config.Prison.PrisonLife or not Config.Prison.PrisonLife.enabled then
    return
end

local spawnedNpcs = {}
local npcAvatarCache = {}
local activeDialogNpcIndex = nil
local dialogCamera = nil

function getNpcMugshot(npcIndex, ped)
    if npcAvatarCache[npcIndex] then
        return npcAvatarCache[npcIndex]
    end
    if not ped or not DoesEntityExist(ped) then
        return nil
    end
    if GetResourceState("MugShotBase64") ~= "started" then
        return nil
    end

    local ok, mugshot = pcall(function()
        return exports.MugShotBase64:GetMugShotBase64(ped, true)
    end)
    if ok and mugshot and mugshot ~= "" then
        npcAvatarCache[npcIndex] = mugshot
        return mugshot
    end
    return nil
end

function focusNpcCamera(ped)
    if dialogCamera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(dialogCamera, false)
        dialogCamera = nil
    end

    local heading = GetEntityHeading(ped)
    local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local distance = 0.8
    local headingRad = math.rad(heading)
    local camX = headCoords.x - math.sin(headingRad) * distance
    local camY = headCoords.y + math.cos(headingRad) * distance
    local camZ = headCoords.z

    dialogCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(dialogCamera, camX, camY, camZ)
    PointCamAtPedBone(dialogCamera, ped, 31086, 0.0, 0.0, 0.0, true)
    SetCamFov(dialogCamera, 50.0)
    RenderScriptCams(true, true, 500, true, true)
end

function clearNpcCamera()
    if not dialogCamera then
        return
    end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(dialogCamera, false)
    dialogCamera = nil
end

CreateThread(function()
    while not Config or not Config.Prison do
        Wait(100)
    end
    while not Prison.Map do
        Wait(100)
    end

    local npcList = Prison.Map.npcs
    if not npcList then
        return
    end

    for npcIndex, npcDef in ipairs(npcList) do
        local modelHash = joaat(npcDef.model)
        lib.requestModel(npcDef.model)
        if HasModelLoaded(modelHash) then
            local ped = CreatePed(
                4, modelHash,
                npcDef.coords.x, npcDef.coords.y, npcDef.coords.z - 1.0,
                npcDef.coords.w,
                false, true
            )
            SetEntityHeading(ped, npcDef.coords.w)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedFleeAttributes(ped, 0, false)
            SetPedCombatAttributes(ped, 46, true)
            SetPedCanRagdollFromPlayerImpact(ped, false)

            if npcDef.scenario then
                TaskStartScenarioInPlace(ped, npcDef.scenario, 0, true)
            end

            spawnedNpcs[npcIndex] = ped
            SetModelAsNoLongerNeeded(modelHash)

            Bridge.Target.addLocalEntity(ped, {
                {
                    label = "Talk to " .. npcDef.label,
                    icon = "fa-solid fa-comments",
                    canInteract = function()
                        return Prison.isInPrison
                    end,
                    onSelect = function()
                        openNpcDialog(npcIndex)
                    end,
                },
            })
        end
    end
end)

function openNpcDialog(npcIndex)
    if not Prison.Map or not Prison.Map.npcs then
        return
    end

    local npcDef = Prison.Map.npcs[npcIndex]
    if not npcDef then
        return
    end

    local ped = spawnedNpcs[npcIndex]
    if ped and DoesEntityExist(ped) then
        focusNpcCamera(ped)
    end

    SendNUIMessage({ action = "setVisiblePrisonDialog", data = true })
    SendNUIMessage({
        action = "setPrisonDialogData",
        data = {
            npcLabel = npcDef.label,
            npcModel = npcDef.model,
            dialogue = npcDef.dialogue,
            npcAvatar = npcAvatarCache[npcIndex],
        },
    })
    SetNuiFocus(true, true)
    activeDialogNpcIndex = npcIndex

    if not npcAvatarCache[npcIndex] then
        CreateThread(function()
            local mugshot = getNpcMugshot(npcIndex, ped)
            if mugshot and activeDialogNpcIndex == npcIndex then
                SendNUIMessage({ action = "setPrisonDialogAvatar", data = mugshot })
            end
        end)
    end
end

RegisterNUICallback("prison/dialog/select", function(data, cb)
    SetNuiFocus(false, false)
    cb({})
    clearNpcCamera()

    if not data or not data.action then
        return
    end
    if data.action == "close" then
        return
    end

    if data.action == "trade" then
        openTradeMenu(activeDialogNpcIndex)
    elseif data.action == "illegal_shop" then
        openShopNui("illegal")
    elseif data.action == "prison_jobs" then
        TriggerEvent("p_policejob/client/prison/openJobs")
    elseif data.action == "check_sentence" then
        local remainingSeconds = lib.callback.await("p_policejob/server/prison/getRemainingTime", false)
        if remainingSeconds then
            lib.alertDialog({
                header = "Sentence Info",
                content = ("You have **%d minutes** remaining on your sentence."):format(
                    math.ceil(remainingSeconds / 60)
                ),
                centered = true,
                cancel = false,
            })
        end
    elseif data.action == "info" then
        Bridge.Notify.showNotify(locale("prison_guard_inspect_hint"), "info")
    end
end)

RegisterNUICallback("prison/dialog/close", function(_, cb)
    SetNuiFocus(false, false)
    clearNpcCamera()
    cb({})
end)

function openTradeMenu(npcIndex)
    if not Prison.isInPrison then
        return
    end

    if npcIndex then
        local npcDef = Prison.Map and Prison.Map.npcs and Prison.Map.npcs[npcIndex]
        local tradeItems = npcDef and npcDef.tradeItems
        if tradeItems and #tradeItems > 0 then
            local npcItems = {}
            for index, item in ipairs(tradeItems) do
                local itemData = Bridge.Inventory.getItemData(item.name)
                npcItems[index] = {
                    name = item.name,
                    label = (itemData and itemData.label) or item.label,
                    price = item.price,
                    description = (itemData and itemData.description) or item.description or "",
                    image = itemData and itemData.image or nil,
                }
            end

            local playerItems = lib.callback.await("p_policejob/server/prison/getTradeItems", false) or {}
            for index, item in ipairs(playerItems) do
                local itemData = Bridge.Inventory.getItemData(item.name)
                playerItems[index].label = (itemData and itemData.label) or item.label or item.name
                playerItems[index].image = itemData and itemData.image or nil
                playerItems[index].value = item.value or 5
            end

            SendNUIMessage({ action = "setVisiblePrisonTrade", data = true })
            SendNUIMessage({
                action = "setNpcTradeData",
                data = {
                    npcName = npcDef.label,
                    npcIndex = npcIndex,
                    playerItems = playerItems,
                    npcItems = npcItems,
                },
            })
            SetNuiFocus(true, true)
            return
        end
    end

    local nearbyPlayers = {}
    local playerCoords = GetEntityCoords(cache.ped)

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= cache.playerId then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                local tradeDistance = Config.Prison.PrisonLife.trading.distance
                if #(playerCoords - targetCoords) < tradeDistance then
                    nearbyPlayers[#nearbyPlayers + 1] = {
                        id = GetPlayerServerId(playerId),
                        name = GetPlayerName(playerId),
                    }
                end
            end
        end
    end

    if #nearbyPlayers == 0 then
        Bridge.Notify.showNotify(locale("prison_trade_no_target"), "error")
        return
    end

    local targetId = nil
    local targetName = nil

    if #nearbyPlayers == 1 then
        targetId = nearbyPlayers[1].id
        targetName = nearbyPlayers[1].name
    else
        local options = {}
        for _, player in ipairs(nearbyPlayers) do
            options[#options + 1] = {
                value = tostring(player.id),
                label = player.name .. " (ID: " .. player.id .. ")",
            }
        end

        local input = lib.inputDialog(locale("prison_trade_select_player"), {
            { type = "select", label = "Player", options = options, required = true },
        })
        if not input then
            return
        end

        targetId = tonumber(input[1])
        for _, player in ipairs(nearbyPlayers) do
            if player.id == targetId then
                targetName = player.name
                break
            end
        end
    end

    if not targetId then
        return
    end

    local myItems = lib.callback.await("p_policejob/server/prison/getTradeItems", false)
    if not myItems or #myItems == 0 then
        Bridge.Notify.showNotify(locale("prison_trade_no_items"), "error")
        return
    end

    SendNUIMessage({ action = "setVisiblePrisonTrade", data = true })
    SendNUIMessage({
        action = "setPrisonTradeData",
        data = {
            targetName = targetName or ("Player " .. targetId),
            targetId = targetId,
            myItems = myItems,
        },
    })
    SetNuiFocus(true, true)
end

RegisterNUICallback("prison/trade/send", function(data, cb)
    SetNuiFocus(false, false)
    cb({})

    if not data or not data.targetId or not data.items then
        return
    end

    TriggerServerEvent("p_policejob/server/prison/trade/send", {
        targetId = data.targetId,
        items = data.items,
    })
end)

RegisterNUICallback("prison/trade/close", function(_, cb)
    SendNUIMessage({ action = "setVisiblePrisonTrade", data = false })
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback("prison/npc_trade/execute", function(data, cb)
    SetNuiFocus(false, false)
    cb({})

    if not data or not data.npcIndex or not data.offeredItems or not data.requestedItem then
        return
    end

    TriggerServerEvent("p_policejob/server/prison/npc_trade/execute", {
        npcIndex = data.npcIndex,
        offeredItems = data.offeredItems,
        requestedItem = data.requestedItem,
    })
end)

RegisterNUICallback("prison/npc_trade/close", function(_, cb)
    SendNUIMessage({ action = "setVisiblePrisonTrade", data = false })
    SetNuiFocus(false, false)
    cb({})
end)

function openShopNui(shopType)
    if not Prison.isInPrison then
        return
    end

    local shopItems = nil
    local shopTitle = nil

    if shopType == "commissary" then
        shopItems = Config.Prison.Commissary.items
        shopTitle = "Commissary"
    elseif shopType == "illegal" then
        shopItems = Config.Prison.IllegalShop.items
        shopTitle = "Black Market"
    else
        return
    end

    local items = {}
    for index, item in ipairs(shopItems) do
        local itemData = Bridge.Inventory.getItemData(item.name)
        items[index] = {
            name = item.name,
            label = (itemData and itemData.label) or item.name,
            price = item.price,
            description = (itemData and itemData.description) or item.description or "",
            image = itemData and itemData.image or nil,
        }
    end

    SendNUIMessage({ action = "setVisiblePrisonShop", data = true })
    SendNUIMessage({
        action = "setPrisonShopData",
        data = {
            shopType = shopType,
            title = shopTitle,
            items = items,
        },
    })
    SetNuiFocus(true, true)
end

RegisterNUICallback("prison/shop/checkout", function(data, cb)
    SetNuiFocus(false, false)
    cb({})

    if not data or not data.shopType or not data.items then
        return
    end

    for _, item in ipairs(data.items) do
        if data.shopType == "commissary" then
            TriggerServerEvent("p_policejob/server/prison/commissary/buy", {
                item = item.name,
                quantity = item.quantity,
                price = item.price,
            })
        elseif data.shopType == "illegal" then
            TriggerServerEvent("p_policejob/server/prison/illegalshop/buy", {
                item = item.name,
                quantity = item.quantity,
                price = item.price,
            })
        elseif data.shopType == "npc_trade" then
            TriggerServerEvent("p_policejob/server/prison/npc_trade/buy", {
                item = item.name,
                quantity = item.quantity,
                price = item.price,
                npcIndex = data.npcIndex,
            })
        end
    end
end)

RegisterNUICallback("prison/shop/close", function(_, cb)
    SendNUIMessage({ action = "setVisiblePrisonShop", data = false })
    SetNuiFocus(false, false)
    cb({})
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    for _, ped in pairs(spawnedNpcs) do
        if DoesEntityExist(ped) then
            Bridge.Target.removeLocalEntity(ped)
            DeleteEntity(ped)
        end
    end
end)
