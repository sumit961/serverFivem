-- cm-law/server/records.lua
-- Cross-agency record lookup.
--
-- cm-law's own MDT already reads the police tables directly
-- (cm_police_licenses / _bookings / _citations / _impounds), so a lawyer sees
-- the full police picture. Nothing went the other way: cm-police contains no
-- reference to any cm_legal_* table, so a citation or booking created by SAHP
-- or any other legal organization was invisible to an officer running that
-- citizen in the police MDT.
--
-- Rather than have cm-police query cm-law's tables directly -- which would
-- hardcode this resource's schema into another resource and break the moment
-- either changes -- the records are exposed here as a read-only export.
-- cm-police calls it through pcall, so a server running cm-police without
-- cm-law simply gets nothing back instead of erroring.
--
-- Read-only by design: nothing here writes, and it deliberately exposes only
-- what an officer would legitimately see on an MDT profile. Authorization is
-- the caller's job -- cm-police already gates the profile behind
-- authorizedForMdt() before it ever reaches this export.

local function orgLabel(organizationId)
    local id = tostring(organizationId or '')
    local org = id ~= '' and (Config.Organizations or {})[id]
    if org then return tostring(org.shortLabel or org.label or id:upper()) end
    return id ~= '' and id:upper() or 'Legal'
end

local function rows(query, params)
    local ok, result = pcall(function() return MySQL.query.await(query, params) end)
    if not ok or type(result) ~= 'table' then return {} end
    return result
end

-- Citations issued by legal organizations. Column names are normalised to the
-- police MDT's shape (amount -> fine) so both sets render through the same
-- template without the NUI needing to know where a row came from.
local function citationsFor(characterId)
    local list = {}
    for _, row in ipairs(rows([[SELECT id, organization_id, violation_label, amount, status, created_at
        FROM cm_legal_citations WHERE target_cid = ? ORDER BY id DESC LIMIT 50]], { characterId })) do
        list[#list + 1] = {
            id = tonumber(row.id),
            violation_label = tostring(row.violation_label or ''),
            fine = tonumber(row.amount) or 0,
            status = row.status and tostring(row.status) or nil,
            createdAt = tostring(row.created_at or ''),
            agency = orgLabel(row.organization_id),
        }
    end
    return list
end

-- Legal bookings carry no wanted_stars, mugshot or cinematic state -- those
-- are police-booking concepts. The fields are returned as nil rather than
-- faked so the MDT can render them as absent instead of as zero.
local function bookingsFor(characterId)
    local list = {}
    for _, row in ipairs(rows([[SELECT id, organization_id, reason, charges, sentence_minutes,
        handoff_status, failure_reason, booked_at, release_at, released_at
        FROM cm_legal_bookings WHERE character_id = ? ORDER BY id DESC LIMIT 50]], { characterId })) do
        list[#list + 1] = {
            id = tonumber(row.id),
            reason = row.reason and tostring(row.reason) or nil,
            charges = row.charges and tostring(row.charges) or nil,
            sentenceMinutes = tonumber(row.sentence_minutes) or 0,
            handoffStatus = tostring(row.handoff_status or 'legacy'),
            releaseReason = row.failure_reason and tostring(row.failure_reason) or nil,
            bookedAt = tostring(row.booked_at or ''),
            releaseAt = row.release_at and tostring(row.release_at) or '',
            releasedAt = row.released_at and tostring(row.released_at) or nil,
            agency = orgLabel(row.organization_id),
        }
    end
    return list
end

-- Current custody state, if any. One row per character by primary key.
local function custodyFor(characterId)
    local row = rows([[SELECT organization_id, status, reason, booking_minutes, created_at
        FROM cm_legal_custody WHERE character_id = ? LIMIT 1]], { characterId })[1]
    if not row then return nil end
    return {
        status = tostring(row.status or ''),
        reason = row.reason and tostring(row.reason) or nil,
        bookingMinutes = tonumber(row.booking_minutes) or 0,
        createdAt = tostring(row.created_at or ''),
        agency = orgLabel(row.organization_id),
    }
end

-- Active and closed warrants. cm-police has no warrants table of its own --
-- it carries a `wanted` boolean on cm_police_criminal_status plus an
-- auto-generated note -- so a warrant issued by a legal organization was
-- previously invisible to officers even though it is the record that actually
-- authorises an arrest.
local function warrantsFor(characterId)
    local list = {}
    for _, row in ipairs(rows([[SELECT id, organization_id, author_cid, reason, stars, status,
        closed_by, created_at, closed_at
        FROM cm_legal_mdt_warrants WHERE target_cid = ? ORDER BY id DESC LIMIT 50]], { characterId })) do
        list[#list + 1] = {
            id = tonumber(row.id),
            reason = tostring(row.reason or ''),
            stars = tonumber(row.stars) or 1,
            status = tostring(row.status or 'active'),
            authorName = row.author_cid and nameFor(row.author_cid) or 'Unknown',
            closedByName = row.closed_by and nameFor(row.closed_by) or nil,
            createdAt = tostring(row.created_at or ''),
            closedAt = row.closed_at and tostring(row.closed_at) or nil,
            agency = orgLabel(row.organization_id),
        }
    end
    return list
end

-- Incident reports. Only the metadata and title cross the boundary, never the
-- narrative body: an officer should see that a report exists and who filed it,
-- but reading another agency's full write-up belongs in that agency's own MDT.
local function reportsFor(characterId)
    local list = {}
    for _, row in ipairs(rows([[SELECT id, organization_id, author_cid, title, status, created_at
        FROM cm_legal_mdt_reports WHERE target_cid = ? ORDER BY id DESC LIMIT 25]], { characterId })) do
        list[#list + 1] = {
            id = tonumber(row.id),
            title = tostring(row.title or ''),
            status = tostring(row.status or 'open'),
            authorName = row.author_cid and nameFor(row.author_cid) or 'Unknown',
            createdAt = tostring(row.created_at or ''),
            agency = orgLabel(row.organization_id),
        }
    end
    return list
end

-- One call returns everything cm-police needs for a profile, so the police MDT
-- makes a single export call rather than three.
exports('GetCitizenLegalRecords', function(characterId)
    characterId = tostring(characterId or '')
    if characterId == '' then return nil end
    if not LawIsReady or not LawIsReady() then return nil end
    return {
        citations = citationsFor(characterId),
        bookings = bookingsFor(characterId),
        custody = custodyFor(characterId),
        warrants = warrantsFor(characterId),
        reports = reportsFor(characterId),
    }
end)
