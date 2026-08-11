while not Config do
    Citizen.Wait(50)
end

local compatResources = {
    "qb-policejob",
    "qbx_police",
    "esx_policejob",
    "wasabi_police",
}

function registerCompatExport(exportName, handler)
    for _, resourceName in ipairs(compatResources) do
        AddEventHandler(("__cfx_export_%s_%s"):format(resourceName, exportName), function(setCB)
            setCB(handler)
        end)
    end
    exports(exportName, handler)
end

function isHandcuffed()
    return LocalPlayer.state.isCuffed == true
end

function isPoliceJob()
    return Bridge.Framework.fetchPlayerJob() ~= nil
end

registerCompatExport("IsHandcuffed", isHandcuffed)
registerCompatExport("isHandcuffed", isHandcuffed)
registerCompatExport("IsPlayerHandcuffed", isHandcuffed)
registerCompatExport("IsCop", isPoliceJob)
registerCompatExport("IsPolice", isPoliceJob)
