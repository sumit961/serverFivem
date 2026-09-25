-- cm-playerdata/server/hardening.lua
-- Additive extension helpers for CM Player Data.
-- Roadmap read helpers (proximity, affiliation).
-- Persistent identity and P2P transfers are authoritatively owned by server/main.lua.

local RESOURCE = GetCurrentResourceName()

local function getData(src)
    local ok, data = pcall(function() return exports[RESOURCE]:GetPlayerData(src) end)
    if ok then return data end
    return nil
end

-- =============================================================================
-- ROADMAP READ HELPERS
-- =============================================================================

-- True if the two server IDs are within `maxDist` metres of each other, checked
-- server-side. Extension resources should gate any player-to-player action on this.
exports('ArePlayersWithin', function(aSrc, bSrc, maxDist)
    aSrc, bSrc = tonumber(aSrc), tonumber(bSrc)
    maxDist = tonumber(maxDist) or 5.0
    if not aSrc or not bSrc then return false end
    local aPed, bPed = GetPlayerPed(aSrc), GetPlayerPed(bSrc)
    if not aPed or not bPed or aPed == 0 or bPed == 0 then return false end
    local ac, bc = GetEntityCoords(aPed), GetEntityCoords(bPed)
    return #(ac - bc) <= maxDist
end)

-- Current family/org metadata for a player, read-only, for rank/kick logic in
-- the future cm-families / cm-orgs resources.
exports('GetAffiliation', function(src)
    local data = getData(src)
    if not data or not data.metadata then return nil end
    local m = data.metadata
    return {
        familyId = m.family_id, family = m.family,
        organizationId = m.organization_id, organization = m.organization,
    }
end)
