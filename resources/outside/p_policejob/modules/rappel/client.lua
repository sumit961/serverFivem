while not Config or not Config.Rappel do
    Citizen.Wait(50)
end

if not Config.Rappel.enabled then
    return
end

Rappel = {
    busy = false,
    active = false,
    rope = nil,
}

function Rappel.hasJobAccess(self)
    if not Config.Rappel.requireJob then
        return true
    end
    local job = Bridge.Framework.fetchPlayerJob()
    return job and Config.Jobs[job.name] ~= nil
end

function Rappel.validateHeli(self)
    local ped = cache.ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not IsThisModelAHeli(GetEntityModel(vehicle)) then
        return nil, "rappel_no_point"
    end
    if GetPedInVehicleSeat(vehicle, -1) == ped then
        return nil, "rappel_pilot"
    end
    if GetEntityHeightAboveGround(vehicle) < Config.Rappel.heli.minHeight then
        return nil, "rappel_heli_too_low"
    end
    return vehicle
end

function Rappel.startRappel(self)
    TaskRappelFromHeli(cache.ped, Config.Rappel.heli.ropeLength + 0.0)
    Bridge.Notify.showNotify(locale("rappel_heli_started"), "inform")
    CreateThread(function()
        while IsPedRappellingFromHelicopter(cache.ped) do
            Wait(250)
        end
    end)
end

function Rappel.attempt(self)
    if self.busy or self.active then
        return
    end
    if not self:hasJobAccess() then
        return Bridge.Notify.showNotify(locale("no_access"), "error")
    end
    local vehicle, errorKey = self:validateHeli()
    if not vehicle then
        return Bridge.Notify.showNotify(locale(errorKey), "error")
    end
    if Bridge.Inventory.getItemCount(Config.Rappel.item) < 1 then
        return Bridge.Notify.showNotify(locale("rappel_no_kit"), "error")
    end
    self.busy = true
    local authorized = lib.callback.await("p_policejob/server/rappel/authorize", false)
    self.busy = false
    if not authorized then
        return
    end
    self:startRappel()
end

RegisterNetEvent("p_policejob/client/rappel/use", function()
    CreateThread(function()
        Rappel:attempt()
    end)
end)

exports("startRappel", function()
    CreateThread(function()
        Rappel:attempt()
    end)
end)

exports("isRappelling", function()
    return Rappel.active
end)
