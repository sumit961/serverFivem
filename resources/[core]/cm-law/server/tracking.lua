-- cm-law/server/tracking.lua
-- Member map broadcasts and meeting points, scoped per legal organization.
--
-- cm-ems and cm-police both broadcast to "every member of the organization"
-- because each of those resources IS one organization. cm-law hosts several
-- (SAHP, and whatever else Config.Organizations defines), so every broadcast
-- here filters on organization_id: a SAHP supervisor routes SAHP and sees
-- SAHP, never another agency's units.
--
-- Positions are read server-side from the ped, never accepted from the client,
-- so a member cannot spoof their location on a supervisor's map. Meeting
-- points do take client coordinates (the NUI has no other way to say "here"),
-- but the server re-reads the ped and rejects a mismatch -- same 25-unit gate
-- and 10-second cooldown cm-police uses.

local meetingCooldowns = {}
local BROADCAST_INTERVAL_MS = 3000

local function permitted(member, permission)
    if not member then return false end
    if member.isLeader then return true end
    return type(member.permissions) == 'table' and member.permissions[permission] == true
end

-- Everyone currently on duty for a given organization, with their position.
local function onDutyMembers(organizationId)
    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local characterId = src and characterIdFor(src)
        local member = characterId and memberFor(characterId, organizationId)
        if member and member.onDuty and not member.suspended then
            local ped = GetPlayerPed(src)
            if ped and ped > 0 then
                local coords = GetEntityCoords(ped)
                list[#list + 1] = {
                    characterId = tostring(characterId),
                    name = nameFor(characterId),
                    onDuty = true,
                    x = coords.x, y = coords.y, z = coords.z,
                }
            end
        end
    end
    return list
end

-- Only players who have asked for the map get a push, so an organization with
-- nobody watching costs one membership lookup per tick and nothing else.
local watchers = {}

RegisterNetEvent('cm-law:server:toggleMemberMap', function(watching)
    local src = source
    local characterId = characterIdFor(src)
    if not characterId then return end
    local orgRow = MySQL.single.await([[
        SELECT m.organization_id FROM cm_legal_members m
        WHERE m.character_id = ? ORDER BY m.on_duty DESC LIMIT 1
    ]], { tostring(characterId) })
    local member = orgRow and memberFor(characterId, orgRow.organization_id)
    if not permitted(member, 'law.view_member_map') then
        watchers[src] = nil
        return
    end
    watchers[src] = watching == true and member.organizationId or nil
end)

AddEventHandler('playerDropped', function()
    watchers[source] = nil
end)

CreateThread(function()
    while true do
        Wait(BROADCAST_INTERVAL_MS)
        -- Build each organization's roster once, however many watchers it has.
        local byOrg = {}
        for src, organizationId in pairs(watchers) do
            if GetPlayerName(src) then
                if organizationId and not byOrg[organizationId] then
                    byOrg[organizationId] = onDutyMembers(organizationId)
                end
            else
                watchers[src] = nil
            end
        end
        for src, organizationId in pairs(watchers) do
            local roster = organizationId and byOrg[organizationId]
            if roster then TriggerClientEvent('cm-law:client:memberPositions', src, roster) end
        end
    end
end)

lib.callback.register('cm-law:server:setMeetingPoint', function(src, payload)
    payload = type(payload) == 'table' and payload or {}
    local characterId = characterIdFor(src)
    if not characterId then return false, 'Character not found.' end
    local orgRow = MySQL.single.await([[
        SELECT m.organization_id FROM cm_legal_members m
        WHERE m.character_id = ? ORDER BY m.on_duty DESC LIMIT 1
    ]], { tostring(characterId) })
    local member = orgRow and memberFor(characterId, orgRow.organization_id)
    if not permitted(member, 'law.set_meeting') then
        return false, 'Your rank cannot set meeting points.'
    end

    local org = Config.Organizations[member.organizationId] or {}
    local label = ('%s meeting point'):format(tostring(org.shortLabel or org.label or 'Legal'))

    if payload.clear == true then
        local cleared = 0
        for _, playerId in ipairs(GetPlayers()) do
            local targetSrc = tonumber(playerId)
            local targetCid = targetSrc and characterIdFor(targetSrc)
            if targetCid and memberFor(targetCid, member.organizationId) then
                TriggerClientEvent('cm-law:client:clearMeetingPoint', targetSrc)
                cleared = cleared + 1
            end
        end
        logActivity(member.organizationId, characterId, 'meeting_point_cleared', { recipients = cleared })
        return true, ('Meeting point cleared for %d online member(s).'):format(cleared)
    end

    local now = GetGameTimer()
    if now < (meetingCooldowns[src] or 0) then return false, 'Please wait before setting another meeting point.' end

    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    if not x or not y or not z or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or math.abs(z) > 2500.0 then
        return false, 'Invalid meeting point.'
    end
    -- Anti-spoof: the coordinates came from the client, so check them against
    -- where the server thinks the ped actually is.
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local serverCoords = GetEntityCoords(ped)
        if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then
            return false, 'Meeting point location mismatch.'
        end
    end
    meetingCooldowns[src] = now + 10000

    local recipients = 0
    local setterName = nameFor(characterId)
    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        local targetCid = targetSrc and characterIdFor(targetSrc)
        if targetCid and memberFor(targetCid, member.organizationId) then
            TriggerClientEvent('cm-law:client:setMeetingPoint', targetSrc, {
                x = x, y = y, z = z, setterName = setterName, label = label,
            })
            recipients = recipients + 1
        end
    end
    logActivity(member.organizationId, characterId, 'meeting_point_set', { recipients = recipients })
    return true, ('Meeting point sent to %d online member(s).'):format(recipients)
end)
