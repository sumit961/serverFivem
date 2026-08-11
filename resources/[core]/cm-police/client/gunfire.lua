-- cm-police automatic "heavy gunfire" detection. Runs for every connected
-- client (like impound.lua/cuffs.lua's own always-on threads), each one
-- watching only its OWN player's shots -- there is no reliable way to
-- detect a DIFFERENT client's gunfire from here, so self-reporting is the
-- only sound design (matches how cm-inventory's own ammo tracker already
-- works: client/main.lua there polls IsPedShooting on the local ped only).
-- Reuses that exact same native/polling shape rather than the less certain
-- CEventNetworkWeaponFireBullet network event, since IsPedShooting is
-- already proven working in this codebase.

local shotTimestamps = {}
local lastReportAt = -1e9

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if IsPedShooting(ped) then
            local now = GetGameTimer()
            shotTimestamps[#shotTimestamps + 1] = now
            local windowMs = Config.Dispatch.GunfireWindowMs or 10000
            while shotTimestamps[1] and now - shotTimestamps[1] > windowMs do
                table.remove(shotTimestamps, 1)
            end
            local threshold = Config.Dispatch.GunfireShotThreshold or 8
            local cooldown = Config.Dispatch.GunfireCooldownMs or 120000
            if #shotTimestamps >= threshold and now - lastReportAt >= cooldown then
                lastReportAt = now
                shotTimestamps = {}
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('cm-police:server:reportGunfire', coords.x, coords.y, coords.z)
            end
            Wait(120) -- debounce so the same shot isn't re-counted across consecutive frames
        else
            -- IsPedShooting is only true for a couple of frames right as a
            -- shot fires -- Wait(0) every idle frame is what actually catches
            -- that window (matches cm-inventory's own shot-tracker exactly;
            -- a slower idle poll here was silently missing most single shots).
            Wait(0)
        end
    end
end)
