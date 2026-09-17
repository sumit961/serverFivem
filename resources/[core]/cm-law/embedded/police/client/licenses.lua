-- cm-police driver's license enforcement. Runs for every connected client
-- (like impound.lua/cuffs.lua's own always-on threads) -- zero changes to
-- cm-vehicles anywhere. "Am I currently the driver" reuses the exact same
-- native shape already established in client/spikes.lua/vehicles.lua/
-- escort.lua: IsPedInAnyVehicle -> GetVehiclePedIsIn -> the driver seat
-- (-1) is occupied by my own ped.

local wasDriver = false
local nextCheck = 0

CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
        local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
        local now = GetGameTimer()
        -- Checked the moment someone becomes the driver, then re-checked
        -- every ~30s while they keep driving -- catches a license revoked
        -- mid-drive (an officer can revoke it on the spot during a stop),
        -- not just at the moment of getting in.
        if isDriver and (not wasDriver or now >= nextCheck) then
            nextCheck = now + 30000
            local valid = lib.callback.await('cm-police:server:hasValidLicense', false, 'drivers')
            if valid == false then
                TaskLeaveVehicle(ped, vehicle, 0)
                PoliceNotify("You don't have a valid driver's license.", 'error')
            end
        end
        wasDriver = isDriver
    end
end)
