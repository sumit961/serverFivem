-- Server-authoritative family meeting point broadcast.
local meetingCooldowns = {}
local COOLDOWN_MS = 10000

local function validCoordinate(value, limit)
    value = tonumber(value)
    return value and value == value and math.abs(value) <= limit and value or nil
end

function CMFamilySetMeetingPoint(src, actorCid, payload)
    src = tonumber(src)
    payload = type(payload) == 'table' and payload or {}
    local rank, fam = GetRankForCid(actorCid)
    if not src or not rank or not fam then return false, 'not_in_family' end
    if not RankHasPermission(rank, 'family.set_meeting') then return false, 'no_permission' end

    local now = GetGameTimer()
    local nextAllowed = meetingCooldowns[src] or 0
    if now < nextAllowed then
        return false, ('Please wait %d seconds before setting another meeting point.'):format(math.ceil((nextAllowed - now) / 1000))
    end

    local x = validCoordinate(payload.x, 10000.0)
    local y = validCoordinate(payload.y, 10000.0)
    local z = validCoordinate(payload.z, 2500.0)
    if not x or not y or not z then return false, 'invalid_location' end

    -- Do not trust coordinates supplied by NUI alone: ensure they are close to
    -- the authoritative server-side player ped position when OneSync provides it.
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local serverCoords = GetEntityCoords(ped)
        if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then
            return false, 'location_mismatch'
        end
    end

    meetingCooldowns[src] = now + COOLDOWN_MS
    local setterName = CMFamilyBridge.GetCharName(actorCid)
    local recipients = 0
    for memberCid, membership in pairs(MemberByCid) do
        if tonumber(membership.family_id) == tonumber(fam.id) then
            local memberSrc = CMFamilyBridge.GetSrcByCid(memberCid)
            if memberSrc then
                TriggerClientEvent('cm-family:client:setMeetingPoint', memberSrc, {
                    x = x, y = y, z = z, setterName = setterName,
                })
                recipients = recipients + 1
            end
        end
    end

    LogFamily(fam.id, actorCid, 'meeting_point_set', { x = x, y = y, z = z, recipients = recipients })
    return true, ('Meeting point sent to %d online family member%s.'):format(recipients, recipients == 1 and '' or 's')
end

AddEventHandler('playerDropped', function()
    meetingCooldowns[source] = nil
end)
