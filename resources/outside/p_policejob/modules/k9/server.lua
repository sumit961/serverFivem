if not Config.K9 or not Config.K9.enabled then
    return
end

K9 = {}
deployedK9ByPlayer = {}

function hasK9JobAccess(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    local minGrade = Config.Jobs[job.name]
    if not minGrade then
        return false
    end
    return minGrade <= tonumber(job.grade)
end

lib.callback.register("p_policejob/k9/spawn", function(playerId, breed)
    if not hasK9JobAccess(playerId) then
        return false, locale("no_access")
    end
    if deployedK9ByPlayer[playerId] then
        return false, "K9 already deployed"
    end
    local selectedBreed = Config.K9.models[1].breed
    for _, modelEntry in ipairs(Config.K9.models) do
        if modelEntry.breed == breed then
            selectedBreed = breed
            break
        end
    end
    deployedK9ByPlayer[playerId] = { breed = selectedBreed }
    Bridge.Debug(("[K9] %s deployed K9: %s"):format(playerId, selectedBreed))
    return true
end)

lib.callback.register("p_policejob/k9/dismiss", function(playerId)
    deployedK9ByPlayer[playerId] = nil
    return true
end)

lib.callback.register("p_policejob/k9/getTargetNetId", function(playerId, targetId)
    if not deployedK9ByPlayer[playerId] then
        return false, "No K9 deployed"
    end
    if playerId == targetId then
        return false, "Cannot target yourself"
    end
    local targetPed = GetPlayerPed(targetId)
    if not targetPed or targetPed == 0 then
        return false, "Player not found"
    end
    return true, NetworkGetNetworkIdFromEntity(targetPed)
end)

lib.callback.register("p_policejob/k9/searchPlayer", function(playerId, targetId)
    if not hasK9JobAccess(playerId) then
        return false
    end
    if not deployedK9ByPlayer[playerId] then
        return false
    end
    if not targetId or playerId == targetId then
        return false
    end
    local officerPed = GetPlayerPed(playerId)
    local targetPed = GetPlayerPed(targetId)
    if not targetPed or targetPed == 0 then
        return false
    end
    local searchDistance = Config.K9.searchDistance or 5.0
    if #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > searchDistance then
        return false, "too_far"
    end
    local foundItems = {}
    for _, itemName in ipairs(Config.K9.searchItems or {}) do
        local count = Bridge.Inventory.getItemCount(targetId, itemName)
        if count and count > 0 then
            foundItems[#foundItems + 1] = itemName
        end
    end
    local itemsLabel = #foundItems > 0 and table.concat(foundItems, ", ") or "none"
    Bridge.Debug(("[K9] %s searched %s - illegal items found: %s"):format(playerId, targetId, itemsLabel))
    return true, #foundItems > 0, foundItems
end)

AddEventHandler("playerDropped", function()
    deployedK9ByPlayer[source] = nil
end)

exports("GetActiveK9", function(playerId)
    return deployedK9ByPlayer[playerId]
end)

exports("IsK9Active", function(playerId)
    return deployedK9ByPlayer[playerId] ~= nil
end)
