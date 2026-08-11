if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

if not Config.Prison.CellStash or not Config.Prison.CellStash.enabled then
    return
end

local cellStashConfig = Config.Prison.CellStash
local stashZoneIds = {}

function removeCellStashZone(zoneId)
    if not zoneId then
        return
    end
    if Bridge.Target and Bridge.Target.removeSphereZone then
        pcall(Bridge.Target.removeSphereZone, zoneId)
    end
end

function cleanupCellStashZones()
    for _, zoneId in ipairs(stashZoneIds) do
        removeCellStashZone(zoneId)
    end
    stashZoneIds = {}
end

function openCellStash(cellId)
    if not Prison or not Prison.isInPrison or Prison.cellId ~= cellId then
        Bridge.Notify.showNotify(locale("cell_stash_no_access"), "error")
        return
    end

    TriggerServerEvent("p_policejob/server/prison/cellStash/open", cellId)
    Citizen.Wait(150)
    Bridge.Inventory.openInventory("stash", {
        id = "p_policejob_cell",
        owner = tostring(cellId),
    })
end

function setupCellStashZones()
    cleanupCellStashZones()

    if not Prison.Map or not Prison.Map.cells then
        return
    end

    local offset = cellStashConfig.offset or vec3(0.0, 0.0, -0.2)
    local radius = tonumber(cellStashConfig.radius) or 0.5

    for _, cell in ipairs(Prison.Map.cells) do
        local stashCoords = cell.stash
        if not stashCoords then
            stashCoords = vector3(
                cell.coords.x + offset.x,
                cell.coords.y + offset.y,
                cell.coords.z + offset.z
            )
        end

        local cellId = cell.id
        local zoneId = Bridge.Target.addSphereZone({
            coords = vector3(stashCoords.x, stashCoords.y, stashCoords.z),
            radius = radius,
            debug = Bridge and Bridge.Config and Bridge.Config.Debug,
            options = {
                {
                    name = ("p_policejob_cell_stash_%d"):format(cellId),
                    label = cellStashConfig.label or "Hidden Stash",
                    icon = cellStashConfig.icon or "fa-solid fa-box-archive",
                    distance = 1.2,
                    onSelect = function()
                        openCellStash(cellId)
                    end,
                },
            },
        })

        stashZoneIds[#stashZoneIds + 1] = zoneId
    end
end

CreateThread(function()
    while not Prison or not Prison.Map or not Prison.Map.cells do
        Wait(250)
    end
    setupCellStashZones()
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanupCellStashZones()
    end
end)
