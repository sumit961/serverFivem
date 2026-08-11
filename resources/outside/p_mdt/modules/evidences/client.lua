Evidences = {}

RegisterNUICallback("mdt/evidences/fetch", function(data, cb)
    local playerCoords = GetEntityCoords(cache.ped)
    local evidences = lib.callback.await("p_mdt/server/evidences/fetch", false, data)
    local streetHash = GetStreetNameAtCoord(playerCoords.x, playerCoords.y, playerCoords.z)

    cb({
        evidences = evidences,
        location = GetStreetNameFromHashKey(streetHash),
    })
end)

RegisterNUICallback("mdt/evidences/search", function(data, cb)
    cb(lib.callback.await("p_mdt/server/evidences/search", false, data))
end)

RegisterNUICallback("mdt/evidences/register", function(data, cb)
    cb(lib.callback.await("p_mdt/server/evidences/register", false, data))
end)

RegisterNUICallback("mdt/evidences/fetchItems", function(data, cb)
    local playerItems = Bridge.Inventory.getPlayerItems()
    local items = {}
    local itemCount = 0

    for _, item in pairs(playerItems) do
        itemCount = itemCount + 1
        local itemData = Bridge.Inventory.getItemData(item.name)
        local metadataFields = {}

        if item.metadata and type(item.metadata) == "table" then
            for metadataKey, metadataLabel in pairs(Config.Evidences.itemsMetadata) do
                if item.metadata[metadataKey] then
                    metadataFields[#metadataFields + 1] = {
                        label = metadataLabel,
                        value = item.metadata[metadataKey],
                    }
                end
            end
        end

        items[itemCount] = {
            name = item.name,
            label = ("%s x%s"):format(itemData and itemData.label or item.name, item.count),
            slot = item.slot,
            metadata = metadataFields,
            count = item.count,
        }
    end

    cb(items)
end)

RegisterNUICallback("mdt/evidences/update", function(data, cb)
    cb(lib.callback.await("p_mdt/server/evidences/update", false, data))
end)

RegisterNUICallback("mdt/evidences/takeOut", function(data, cb)
    TriggerServerEvent("p_mdt/server/evidences/takeOut", data.id)
end)

RegisterNUICallback("mdt/evidences/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/evidences/delete", data.id)
    cb(1)
end)

function Evidences.openDeposit(self)
    local job = Bridge.Framework.fetchPlayerJob()
    local jobName = job and job.name

    if not jobName or not Config.Departments[jobName] then
        return
    end

    local allEvidences = lib.callback.await("p_mdt/server/evidences/fetch", false)
    local undepositedEvidences = {}

    for _, evidence in pairs(allEvidences) do
        if evidence.status == "undeposited" then
            undepositedEvidences[#undepositedEvidences + 1] = evidence
        end
    end

    if #undepositedEvidences == 0 then
        Bridge.Notify.showNotify(locale("no_undeposited_evidences"), "error")
        return
    end

    local menuOptions = {}
    for index, evidence in ipairs(undepositedEvidences) do
        menuOptions[index] = {
            title = ("#%s - %s"):format(evidence.id, evidence.title),
            description = ("Description: %s\nLocation: %s"):format(evidence.description, evidence.location),
            onSelect = function()
                TriggerServerEvent("p_mdt/server/evidences/deposit", evidence.id)
            end,
        }
    end

    lib.registerContext({
        id = "evidence_deposit_menu",
        title = locale("evidence_deposit_menu"),
        options = menuOptions,
    })
    lib.showContext("evidence_deposit_menu")
end

exports("openEvidenceDeposit", function()
    Evidences:openDeposit()
end)

CreateThread(function()
    while not Bridge or not Bridge.Target do
        Wait(0)
    end

    for jobName, points in pairs(Config.Evidences.depositPoints) do
        for _, coords in ipairs(points) do
            Bridge.Target.addSphereZone({
                coords = coords,
                radius = 1.0,
                options = {
                    {
                        label = locale("deposit_evidence"),
                        icon = "fas fa-box",
                        groups = jobName,
                        onSelect = function()
                            Evidences:openDeposit()
                        end,
                    },
                },
            })
        end
    end
end)
