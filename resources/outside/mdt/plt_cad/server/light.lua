-- ============================================================
-- sv_light.lua  -  PLT CAD  |  Server-side light sync module
-- Deobfuscated: all L0_1 / L1_1  style variables renamed to
-- meaningful identifiers.  Zero logic changes.
-- ============================================================

-- mouseActiveState: server-side registry of which players
-- currently have mouse/CAD active.
-- Key = server ID (integer), Value = boolean
local mouseActiveState = {}

-- ----------------------------------------------------------
-- NetEvent: plt_cad:server:setMouseActive
-- Fired by a client when they open or close the in-world CAD.
-- Stores the state for this player and broadcasts it to ALL
-- connected clients so every client's light renderer stays
-- in sync.
-- Parameters:
--   isActive - boolean sent by the triggering client
-- ----------------------------------------------------------
RegisterNetEvent("plt_cad:server:setMouseActive", function(isActive)
    local playerId = source  -- 'source' is the server ID of the triggering player

    -- Store the state server-side
    mouseActiveState[playerId] = isActive

    -- Broadcast the change to every client (-1 = all players)
    -- so their local mouseActiveMap stays in sync for light rendering
    TriggerClientEvent("plt_cad:client:updateMouseActive", -1, playerId, isActive)
end)

-- ----------------------------------------------------------
-- EventHandler: playerDropped
-- Cleans up the mouseActiveState entry when a player leaves.
-- Also broadcasts a "false" update to all clients so they
-- stop rendering a light for this now-disconnected player.
-- ----------------------------------------------------------
AddEventHandler("playerDropped", function()
    local playerId = source  -- server ID of the player who dropped

    -- Only act if this player had an active entry
    if mouseActiveState[playerId] then
        -- Remove from server registry
        mouseActiveState[playerId] = nil

        -- Notify all clients to clear this player's active state
        TriggerClientEvent("plt_cad:client:updateMouseActive", -1, playerId, false)
    end
end)

-- ----------------------------------------------------------
-- NetEvent: plt_cad:server:requestLightSync
-- Fired by a freshly-joined client (after 1 s delay in light.lua)
-- to receive the full current state of all active players.
-- The server iterates mouseActiveState and sends one
-- "updateMouseActive" event per active player directly to the
-- requesting client only.
-- ----------------------------------------------------------
RegisterNetEvent("plt_cad:server:requestLightSync", function()
    local requestingClient = source  -- only send back to this player

    for playerId, isActive in pairs(mouseActiveState) do
        if isActive then
            -- Tell the requesting client that this player is active
            TriggerClientEvent("plt_cad:client:updateMouseActive", requestingClient, playerId, true)
        end
    end
end)
