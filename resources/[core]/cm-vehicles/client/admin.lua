--- ═══════════════════════════════════════════════════════════════════════
---  cm-vehicles | client/admin.lua
---  Client half of the admin/temporary vehicle system.
--- ═══════════════════════════════════════════════════════════════════════

--- Start the engine of an admin-spawned car. Server-spawned entities arrive
--- with the engine off, and a car you cannot start is not much of a car.
RegisterNetEvent('cm-vehicles:client:adminEngine', function(netId, on)
    CreateThread(function()
        local t = GetGameTimer()
        local ent = 0

        -- Wait for the entity to stream in before touching it.
        while GetGameTimer() - t < 5000 do
            ent = NetworkGetEntityFromNetworkId(netId)
            if ent ~= 0 and DoesEntityExist(ent) then break end
            Wait(50)
        end

        if ent == 0 or not DoesEntityExist(ent) then return end

        -- Admin/placement vehicles are already marked condition-ready by
        -- the server. Apply a matching physical baseline on the controlling
        -- client before starting the engine so the generic safety loop cannot
        -- quarantine a perfectly valid temporary vehicle.
        SetVehicleEngineHealth(ent, 1000.0)
        SetVehicleBodyHealth(ent, 1000.0)
        SetVehiclePetrolTankHealth(ent, 1000.0)
        SetVehicleFuelLevel(ent, 100.0)
        SetVehicleUndriveable(ent, false)
        SetVehicleEngineOn(ent, on ~= false, true, false)
        SetVehicleDoorsLocked(ent, 1)   -- unlocked: it belongs to nobody
        SetVehicleOnGroundProperly(ent)
    end)
end)

--- Is the car I am looking at a temporary one? Used by the HUD so a player is
--- not told they lack keys to a car that has no owner at all.
exports('IsAdminVehicleClient', function(entity)
    if not entity or not DoesEntityExist(entity) then return false end
    local ok, flag = pcall(function() return Entity(entity).state.cmAdmin end)
    return ok and flag == true
end)
