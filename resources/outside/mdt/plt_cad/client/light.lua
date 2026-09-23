-- ============================================================
-- light.lua  -  PLT CAD  |  Client-side light rendering module
-- Deobfuscated: all L0_1 / L1_1  style variables renamed to
-- meaningful identifiers.  Zero logic changes.
-- ============================================================

-- mouseActiveMap: tracks which server IDs currently have mouse
-- active (i.e. are using the in-world CAD panel).
-- Key = tostring(serverId), Value = boolean
local mouseActiveMap = {}

-- ----------------------------------------------------------
-- NetEvent: plt_cad:client:updateMouseActive
-- Fired by the server to sync mouse-active state to all clients.
-- Parameters:
--   serverId  - the server ID of the player whose state changed
--   isActive  - boolean, true = mouse active / light should render
-- ----------------------------------------------------------
RegisterNetEvent("plt_cad:client:updateMouseActive", function(serverId, isActive)
    local key = tostring(serverId)
    mouseActiveMap[key] = isActive
end)

-- ----------------------------------------------------------
-- Thread: Initial sync request
-- Waits 1 second after resource start then asks the server
-- to re-broadcast all currently active mouse states so this
-- client's mouseActiveMap is populated correctly on join.
-- ----------------------------------------------------------
CreateThread(function()
    Wait(1000)
    TriggerServerEvent("plt_cad:server:requestLightSync")
end)

-- ----------------------------------------------------------
-- Thread: Light rendering loop
-- Runs continuously.  For every server ID that has mouse active,
-- it checks whether that player exists, is in a vehicle, and if
-- so draws a red point light (DrawLightWithRange) slightly in
-- front of and above their ped to indicate they are using the
-- in-world CAD screen.
--
-- Performance:
--   waitMs defaults to 500ms (idle, nobody active).
--   Drops to 0ms (every frame) the moment at least one active
--   player is found in a vehicle, so the light renders smoothly.
-- ----------------------------------------------------------
CreateThread(function()
    while true do
        -- Default to a relaxed 500ms poll; tighten to 0 if we draw a light
        local waitMs      = 500
        local anyRendered = false

        for serverIdStr, isActive in pairs(mouseActiveMap) do
            if isActive then
                local serverId = tonumber(serverIdStr)
                local playerHandle = GetPlayerFromServerId(serverId)

                -- -1 means the player is not found / not connected
                if playerHandle ~= -1 then
                    local ped = GetPlayerPed(playerHandle)

                    if DoesEntityExist(ped) then
                        local vehicle = GetVehiclePedIsIn(ped, false)

                        -- Only render if the ped is actually inside a vehicle
                        if vehicle ~= 0 then
                            anyRendered = true
                            waitMs      = 0  -- switch to per-frame rendering

                            -- Calculate a world-space offset slightly in front
                            -- of and above the ped (x=0.4, y=0.5, z=0.6)
                            local lightPos = GetOffsetFromEntityInWorldCoords(ped, 0.4, 0.5, 0.6)

                            -- Draw a red (255, 0, 0) point light with:
                            --   intensity = 1.5
                            --   range     = 5.0 units
                            DrawLightWithRange(
                                lightPos.x, lightPos.y, lightPos.z,  -- world position
                                255, 0, 0,                           -- R, G, B
                                1.5,                                 -- intensity
                                5.0                                  -- range (metres)
                            )
                        end
                    end
                end
            end
        end

        Wait(waitMs)
    end
end)
