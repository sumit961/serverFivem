-- cm-police wheel clamps. Session-only physical state (a per-vehicle state
-- bag), same class as server/spikes.lua/server/barricades.lua -- nothing
-- persisted, no item/inventory dependency (police.clamp gates it, matching
-- this codebase's standing "no item-gated police tools" rule). The actual
-- immobilization mechanic (handbrake + door lock) and prop attach both live
-- entirely client-side, driven by every client independently reacting to
-- the cmWheelClamped state bag -- see client/clamp.lua.

local function authorizedOfficer(src)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'police.clamp') then
        return nil, characterId
    end
    return member, tostring(characterId)
end

lib.callback.register('cm-police:server:toggleClamp', function(src, netId)
    if not rateLimit(src, 'police_toggle_clamp', 1000) then return false, 'Please wait.' end
    local actor, actorCid = authorizedOfficer(src)
    if not actor then return false, 'You must be an on-duty officer with clamp permission.' end

    netId = tonumber(netId)
    if not netId or netId <= 0 then return false, 'Vehicle could not be identified.' end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'That vehicle no longer exists.' end

    local officerPed = GetPlayerPed(src)
    if not officerPed or officerPed == 0 then return false, 'Officer not found.' end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(vehicle)) > (Config.Clamp.MaxDistance or 3.0) then
        return false, 'You are too far from the vehicle.'
    end

    local clamped = Entity(vehicle).state.cmWheelClamped == true
    Entity(vehicle).state:set('cmWheelClamped', not clamped, true)
    log(actorCid, clamped and 'vehicle_unclamped' or 'vehicle_clamped', {})
    return true, clamped and 'Wheel clamp removed.' or 'Wheel clamp applied.'
end)
