-- cm-police MDT records lookup. Unlike every other feature this session,
-- this isn't a G-menu action or a standalone command -- it's a new tab
-- inside the existing F7 dashboard NUI, so all of this is plain
-- lib.callbacks the NUI calls on demand (mirrors the Fleet tab's own
-- on-demand fetch, not part of the dashboard() preload payload).
--
-- Citizen search reads the `characters` table directly, the same
-- established precedent this resource's own nameFor() already uses (no
-- name-search export exists anywhere, and none is needed).

local MdtReady = false

local function authorizedForMdt(src)
    local databaseReady = PoliceDatabaseReady()
    if not MdtReady or not databaseReady then return false, cid(src) end
    local characterId = cid(src)
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if isAdmin then return true, characterId end
    local member = characterId and memberFor(characterId)
    if member and not dbBoolean(member.is_suspended) and dbBoolean(member.on_duty) and has(member, 'police.mdt') then
        return true, characterId
    end
    return false, characterId
end

-- Real license enforcement (Phase 3/4). 'firearms' must be explicitly
-- purchased/issued -- absence of a row means UNLICENSED (Phase 4: a
-- self-service purchase now exists via cm-gunstore's vendor NPC). Every
-- OTHER license type keeps Phase 2's original "active unless explicitly
-- revoked" default -- flipping those too would instantly block every
-- player from driving (client/licenses.lua checks 'drivers') since no
-- purchase flow exists for them yet.
function HasValidLicense(characterId, licenseType)
    if not characterId or not licenseType then return true end
    if not MdtReady then return licenseType ~= 'firearms' end
    local row = MySQL.single.await('SELECT status FROM cm_police_licenses WHERE character_id = ? AND license_type = ? LIMIT 1', { tostring(characterId), licenseType })
    if licenseType == 'firearms' then
        return row ~= nil and row.status == 'active'
    end
    return not (row and row.status == 'revoked')
end

function GetLicenseNumber(characterId, licenseType)
    if not characterId or not licenseType then return nil end
    if not MdtReady then return nil end
    local row = MySQL.single.await('SELECT license_number FROM cm_police_licenses WHERE character_id = ? AND license_type = ? AND status = ? LIMIT 1', { tostring(characterId), licenseType, 'active' })
    return row and row.license_number or nil
end

-- Self-service purchase (Phase 4). Rejects if already active; deducts the
-- configured price; keeps the same license_number across a later revoke ->
-- re-purchase cycle instead of minting a fresh one (upsert, not insert).
-- The number itself is generated via a retry-loop INSERT relying on the
-- table's own UNIQUE KEY to reject a collision -- genuinely race-safe,
-- unlike a check-then-generate approach.
function PurchaseLicense(characterId, licenseType, src)
    if not characterId or not licenseType then return false, 'Invalid request.' end
    if not MdtReady or not PoliceDatabaseReady() then return false, 'License service is still starting. Try again shortly.' end
    local price = tonumber(Config.Mdt.LicensePrices and Config.Mdt.LicensePrices[licenseType])
    if not price then return false, 'That license is not available for purchase.' end
    local existing = MySQL.single.await('SELECT status, license_number FROM cm_police_licenses WHERE character_id = ? AND license_type = ? LIMIT 1', { tostring(characterId), licenseType })
    if existing and existing.status == 'active' then return false, 'You already have that license.' end
    local operationId = BeginPoliceOperation('license_purchase', tostring(characterId), nil, price, { licenseType = licenseType })
    if not operationId then return false, 'Could not start the license purchase.' end

    local removed = false
    pcall(function() removed = exports[Config.PlayerDataResource]:RemoveMoney(src, 'bank', price, 'license_purchase', { licenseType = licenseType }) end)
    if not removed then
        FinishPoliceOperation(operationId, 'refunded', { reason = 'insufficient_funds', moneyRemoved = false })
        return false, ('You need $%d in your bank account to buy this license.'):format(price)
    end

    local licenseNumber = existing and existing.license_number or nil
    if not licenseNumber then
        for _ = 1, 5 do
            local candidate = ('FL-%06d'):format(math.random(100000, 999999))
            local ok = pcall(function()
                MySQL.insert.await('INSERT INTO cm_police_licenses (character_id, license_type, status, license_number, set_by) VALUES (?, ?, ?, ?, ?)', { tostring(characterId), licenseType, 'active', candidate, nil })
            end)
            if ok then licenseNumber = candidate break end
        end
        if not licenseNumber then
            local refunded = false
            pcall(function() refunded = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', price, 'license_purchase_refund', {}) == true end)
            FinishPoliceOperation(operationId, refunded and 'refunded' or 'reconciliation_required', { reason = 'license_number_failed', refund = refunded })
            return false, 'Could not issue a license number. Try again.'
        end
    else
        local updated = false
        local updateCalled = pcall(function()
            updated = tonumber(MySQL.update.await('UPDATE cm_police_licenses SET status = ?, reason = NULL WHERE character_id = ? AND license_type = ?', { 'active', tostring(characterId), licenseType })) == 1
        end)
        if not updateCalled or not updated then
            local refunded = false
            pcall(function() refunded = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', price, 'license_purchase_refund', {}) == true end)
            FinishPoliceOperation(operationId, refunded and 'refunded' or 'reconciliation_required', { reason = 'license_update_failed', refund = refunded })
            return false, refunded and 'License update failed; your payment was refunded.' or 'License update requires administrator reconciliation.'
        end
    end

    FinishPoliceOperation(operationId, 'completed', { licenseType = licenseType, licenseNumber = licenseNumber })
    log(characterId, 'license_purchased', { licenseType = licenseType, price = price, licenseNumber = licenseNumber })
    return true, ('License issued: %s'):format(licenseNumber), licenseNumber
end

-- For OTHER resources to call -- they only ever have `src`, never a
-- character id (confirmed cm-gunstore has no charId resolution of its own
-- anywhere), so these accept src and resolve it internally via cid().
exports('HasValidLicense', function(src, licenseType)
    return HasValidLicense(cid(tonumber(src)), licenseType)
end)
exports('GetLicenseNumber', function(src, licenseType)
    return GetLicenseNumber(cid(tonumber(src)), licenseType)
end)
exports('PurchaseLicense', function(src, licenseType)
    src = tonumber(src)
    return PurchaseLicense(cid(src), licenseType, src)
end)

-- For cm-police's own client (client/licenses.lua) to self-check its own
-- driver's license before entering a vehicle.
lib.callback.register('cm-police:server:hasValidLicense', function(src, licenseType)
    return HasValidLicense(cid(src), licenseType)
end)

-- Every citizen currently flagged Wanted, newest-set first -- lets an
-- officer see who's wanted at a glance instead of searching each one by
-- name individually. Same authorization gate as every other MDT callback.
lib.callback.register('cm-police:server:mdtWantedList', function(src)
    local authorized = authorizedForMdt(src)
    if not authorized then return {} end
    local rows = MySQL.query.await([[
        SELECT s.character_id, s.stars,
               TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, ''))) AS name
        FROM cm_police_criminal_status s
        JOIN characters c ON c.id = s.character_id
        WHERE s.wanted = 1
        ORDER BY s.updated_at DESC LIMIT 50
    ]]) or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = {
            characterId = tostring(row.character_id),
            name = row.name ~= '' and row.name or ('Character #%s'):format(row.character_id),
            stars = tonumber(row.stars) or 0,
        }
    end
    return list
end)

lib.callback.register('cm-police:server:mdtSearch', function(src, query)
    local authorized = authorizedForMdt(src)
    if not authorized or not rateLimit(src, 'police_mdt_search', 600) then return {} end
    query = tostring(query or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if query == '' then return {} end
    local limit = math.max(1, math.min(tonumber(Config.Mdt.SearchLimit) or 20, 50))
    local like = '%' .. query .. '%'
    local numericId = tonumber(query)
    local rows
    if numericId then
        rows = MySQL.query.await('SELECT id, first_name, last_name FROM characters WHERE id = ? OR first_name LIKE ? OR last_name LIKE ? LIMIT ?', { numericId, like, like, limit })
    else
        rows = MySQL.query.await('SELECT id, first_name, last_name FROM characters WHERE first_name LIKE ? OR last_name LIKE ? LIMIT ?', { like, like, limit })
    end
    local results = {}
    for _, row in ipairs(rows or {}) do
        local name = (('%s %s'):format(row.first_name or '', row.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
        local status = MySQL.single.await('SELECT stars, wanted FROM cm_police_criminal_status WHERE character_id = ? LIMIT 1', { tostring(row.id) })
        results[#results + 1] = {
            characterId = tostring(row.id),
            name = name ~= '' and name or ('Character #%s'):format(row.id),
            stars = status and tonumber(status.stars) or 0,
            wanted = status and dbBoolean(status.wanted) or false,
        }
    end
    return results
end)

lib.callback.register('cm-police:server:mdtCitizenProfile', function(src, characterId)
    local authorized = authorizedForMdt(src)
    if not authorized or not rateLimit(src, 'police_mdt_profile', 600) then return nil end
    characterId = tostring(characterId or '')
    if characterId == '' then return nil end

    local citations = MySQL.query.await('SELECT id, violation_label, fine, created_at FROM cm_police_citations WHERE target_cid = ? ORDER BY id DESC LIMIT 50', { characterId }) or {}
    for _, row in ipairs(citations) do
        row.id, row.fine = tonumber(row.id), tonumber(row.fine)
        row.createdAt = tostring(row.created_at or ''); row.created_at = nil
    end

    local bookings = MySQL.query.await([[SELECT id, reason, charges, wanted_stars, sentence_minutes,
        handoff_status, release_reason, mugshot_url, cinematic_status, completed_at, booked_at, release_at, released_at FROM cm_police_bookings
        WHERE character_id = ? ORDER BY id DESC LIMIT 50]], { characterId }) or {}
    for _, row in ipairs(bookings) do
        row.id = tonumber(row.id)
        row.wantedStars = tonumber(row.wanted_stars) or 0
        row.sentenceMinutes = tonumber(row.sentence_minutes) or 0
        row.handoffStatus = tostring(row.handoff_status or 'legacy')
        row.releaseReason = row.release_reason and tostring(row.release_reason) or nil
        row.mugshotUrl = row.mugshot_url and tostring(row.mugshot_url) or nil
        row.cinematicStatus = row.cinematic_status and tostring(row.cinematic_status) or nil
        row.completedAt = row.completed_at and tostring(row.completed_at) or nil
        row.bookedAt = tostring(row.booked_at or '')
        row.releaseAt = tostring(row.release_at or '')
        row.releasedAt = row.released_at and tostring(row.released_at) or nil
        row.wanted_stars, row.sentence_minutes, row.handoff_status, row.release_reason, row.mugshot_url, row.cinematic_status = nil, nil, nil, nil, nil, nil
        row.completed_at, row.booked_at, row.release_at, row.released_at = nil, nil, nil, nil
    end

    local impounds = MySQL.query.await([[SELECT i.id, i.plate, i.fee, i.impounded_at, i.released_at,
        i.cinematic_status, i.completed_at, i.officer_cid, e.locked_at, e.image_url, e.message
        FROM cm_police_impounds i LEFT JOIN cm_police_impound_evidence e ON e.impound_id = i.id
        WHERE i.owner_cid = ? ORDER BY i.id DESC LIMIT 50]], { characterId }) or {}
    for _, row in ipairs(impounds) do
        row.id, row.fee = tonumber(row.id), tonumber(row.fee)
        row.impoundedAt = tostring(row.impounded_at or '')
        row.releasedAt = row.released_at and tostring(row.released_at) or nil
        row.cinematicStatus = row.cinematic_status and tostring(row.cinematic_status) or nil
        row.completedAt = row.completed_at and tostring(row.completed_at) or nil
        row.evidenceLockedAt = row.locked_at and tostring(row.locked_at) or nil
        row.imageUrl = row.image_url and tostring(row.image_url) or nil
        row.reason = row.message and tostring(row.message) or nil
        row.officerName = row.officer_cid and nameFor(tostring(row.officer_cid)) or 'Police Department'
        row.impounded_at, row.released_at, row.cinematic_status, row.completed_at = nil, nil, nil, nil
        row.locked_at, row.image_url, row.message, row.officer_cid = nil, nil, nil, nil
    end

    local vehicles = {}
    pcall(function() vehicles = exports[Config.VehiclesResource]:GetVehiclesByOwner(characterId) or {} end)
    -- Only vehicles police have actually registered (issued a license
    -- number for) show up here -- an unlicensed car stays invisible in a
    -- citizen's passive vehicle list. Location/storage state is dropped
    -- entirely, from here and from the standalone plate lookup below.
    local vehicleList = {}
    for _, row in ipairs(vehicles) do
        if row.license_number and tostring(row.license_number) ~= '' then
            vehicleList[#vehicleList + 1] = { plate = row.plate, model = tostring(row.model or ''), licenseNumber = tostring(row.license_number) }
        end
    end

    local notes = MySQL.query.await('SELECT id, author_cid, note, created_at FROM cm_police_notes WHERE target_cid = ? ORDER BY id DESC LIMIT 100', { characterId }) or {}
    local noteList = {}
    for _, row in ipairs(notes) do
        noteList[#noteList + 1] = {
            id = tonumber(row.id),
            authorCid = row.author_cid and tostring(row.author_cid) or nil,
            authorName = row.author_cid and nameFor(row.author_cid) or 'System',
            note = tostring(row.note or ''),
            createdAt = tostring(row.created_at or ''),
        }
    end

    local evidence = MySQL.query.await('SELECT id, author_cid, url, caption, created_at FROM cm_police_evidence WHERE target_cid = ? ORDER BY id DESC LIMIT 100', { characterId }) or {}
    local evidenceList = {}
    for _, row in ipairs(evidence) do
        evidenceList[#evidenceList + 1] = {
            id = tonumber(row.id),
            authorCid = row.author_cid and tostring(row.author_cid) or nil,
            authorName = row.author_cid and nameFor(row.author_cid) or 'System',
            url = tostring(row.url or ''),
            caption = tostring(row.caption or ''),
            createdAt = tostring(row.created_at or ''),
        }
    end

    local status = MySQL.single.await('SELECT stars, wanted, photo_url FROM cm_police_criminal_status WHERE character_id = ? LIMIT 1', { characterId })
    -- Real bank balance, read directly off the characters table -- same
    -- table cm-playerdata itself owns cash/bank on, works for offline
    -- citizens too (unlike cm-playerdata's own GetBank export, which only
    -- covers currently-connected src's).
    local bankRow = MySQL.single.await('SELECT bank FROM characters WHERE id = ? LIMIT 1', { characterId })

    -- Absence of a row means "active" for every type EXCEPT firearms
    -- (Phase 4: must be explicitly purchased/issued) -- matches
    -- HasValidLicense's own per-type default above.
    local licenseRows = MySQL.query.await('SELECT license_type, status, reason, license_number FROM cm_police_licenses WHERE character_id = ?', { characterId }) or {}
    local licenseByType = {}
    for _, row in ipairs(licenseRows) do licenseByType[row.license_type] = row end
    local licenses = {}
    for _, licenseType in ipairs(Config.Mdt.LicenseTypes) do
        local row = licenseByType[licenseType]
        local defaultStatus = licenseType == 'firearms' and 'unlicensed' or 'active'
        licenses[#licenses + 1] = {
            type = licenseType,
            status = row and row.status or defaultStatus,
            reason = row and row.reason or nil,
            number = row and row.license_number or nil,
        }
    end

    return {
        characterId = characterId,
        name = nameFor(characterId),
        citations = citations,
        bookings = bookings,
        impounds = impounds,
        vehicles = vehicleList,
        notes = noteList,
        evidence = evidenceList,
        licenses = licenses,
        criminalStars = status and tonumber(status.stars) or 0,
        wanted = status and dbBoolean(status.wanted) or false,
        photoUrl = status and status.photo_url or nil,
        bank = bankRow and tonumber(bankRow.bank) or 0,
    }
end)

-- Same permission tier as notes/criminal status (police.mdt) -- this is
-- record-keeping, not the stricter police.cite fine gate. No enforcement
-- anywhere reads this (see shared/config.lua's LicenseTypes comment) --
-- purely a settable record shown in the MDT.
lib.callback.register('cm-police:server:mdtSetLicenseStatus', function(src, characterId, licenseType, status, reason)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_license', 800) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    local validType = false
    for _, t in ipairs(Config.Mdt.LicenseTypes) do if t == licenseType then validType = true break end end
    if characterId == '' or not validType then return false, 'Invalid license type.' end
    if status ~= 'active' and status ~= 'revoked' then return false, 'Invalid license status.' end
    local cleanReason = tostring(reason or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 160)
    MySQL.insert.await(
        'INSERT INTO cm_police_licenses (character_id, license_type, status, set_by, reason) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE status = VALUES(status), set_by = VALUES(set_by), reason = VALUES(reason)',
        { characterId, licenseType, status, actorCid, cleanReason ~= '' and cleanReason or nil }
    )
    log(actorCid, 'mdt_license_set', { targetCid = characterId, licenseType = licenseType, status = status })
    return true, ('%s license %s.'):format(licenseType, status), { type = licenseType, status = status, reason = cleanReason ~= '' and cleanReason or nil }
end)

-- Any on-duty officer with MDT access can set this -- same permission tier
-- as adding a note (police.mdt), not the stricter police.cite fine gate.
lib.callback.register('cm-police:server:mdtSetCriminalStatus', function(src, characterId, stars, wanted, reason)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_status', 800) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    if characterId == '' then return false, 'Invalid character.' end
    -- Officers may manually assess only 1-5 stars. Six is reserved for the
    -- automatic cm-playerdata escalation that enables native GTA police AI.
    stars = math.max(0, math.min(5, math.floor(tonumber(stars) or 0)))
    wanted = wanted == true and stars > 0
    if not wanted then stars = 0 end
    reason = tostring(reason or ''):gsub('[%c]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 160)
    if wanted and #reason < 3 then return false, 'A wanted reason is required when assigning stars.' end
    if not wanted then reason = nil end
    MySQL.insert.await(
        'INSERT INTO cm_police_criminal_status (character_id, stars, wanted, wanted_reason, set_by) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE stars = VALUES(stars), wanted = VALUES(wanted), wanted_reason = VALUES(wanted_reason), set_by = VALUES(set_by)',
        { characterId, stars, wanted, reason, actorCid }
    )
    log(actorCid, 'mdt_criminal_status_set', { targetCid = characterId, stars = stars, wanted = wanted })

    -- Also pushes this rating onto the target's LIVE HUD wanted level (the
    -- GTA5-style system AutoIssueWarrant below already reads), not just this
    -- MDT record -- only while online, and only the actual stars value when
    -- "wanted" is on; un-marking wanted clears the live level to 0 even if
    -- the stars rating itself stays on file for records purposes.
    local onlineSrc = sourceFor(characterId)
    if onlineSrc then
        pcall(function() exports[Config.PlayerDataResource]:SetWantedStars(onlineSrc, wanted and stars or 0) end)
    end

    return true, 'Criminal status updated.', { stars = stars, wanted = wanted }
end)

-- Auto-generated arrest warrants: cm-playerdata calls this the moment a
-- player's own wanted stars (this session's GTA5-style system, fully
-- separate from the manual `stars` rating above) first reach their
-- configured max. Flips the exact same `wanted` flag the MDT's warrant
-- banner already reads, and reads the citizen's CURRENT stars rating
-- first so this never clobbers an officer's own manual assessment -- only
-- `wanted` is ever touched here. Clearing a warrant stays a deliberate
-- officer action via mdtSetCriminalStatus above, same as any other
-- warrant; nothing here ever auto-clears it.
exports('AutoIssueWarrant', function(characterId, reason)
    characterId = tostring(characterId or '')
    if characterId == '' then return false end
    local existing = MySQL.single.await('SELECT stars FROM cm_police_criminal_status WHERE character_id = ? LIMIT 1', { characterId })
    local stars = existing and tonumber(existing.stars) or 0
    MySQL.insert.await(
        'INSERT INTO cm_police_criminal_status (character_id, stars, wanted) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE wanted = VALUES(wanted)',
        { characterId, stars, true }
    )
    local cleanReason = tostring(reason or 'Automatic warrant'):sub(1, 400)
    -- author_cid = NULL renders as "System" in the MDT notes list already
    -- (html/app.js's existing notes renderer) -- no new UI needed.
    MySQL.insert.await('INSERT INTO cm_police_notes (target_cid, author_cid, note) VALUES (?, ?, ?)', { characterId, nil, ('AUTOMATIC WARRANT: %s'):format(cleanReason) })
    log(nil, 'auto_warrant_issued', { targetCid = characterId, reason = cleanReason })
    return true
end)

exports('SyncWantedStars', function(characterId, stars)
    if GetInvokingResource() ~= Config.PlayerDataResource then return false end
    characterId = tostring(characterId or '')
    if characterId == '' then return false end
    stars = math.max(0, math.min(6, math.floor(tonumber(stars) or 0)))
    MySQL.insert.await(
        'INSERT INTO cm_police_criminal_status (character_id, stars, wanted) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE stars = VALUES(stars), wanted = VALUES(wanted)',
        { characterId, stars, stars > 0 }
    )
    return true
end)

-- No character-creation photo exists anywhere in this codebase (checked
-- cm-characters/cm-playerdata directly) -- this is an officer-pasted image
-- URL instead, stored on the same one-row-per-character assessment table
-- stars/wanted already use. Same permission tier as notes/criminal status
-- (police.mdt), not the stricter fine-issuing gate.
lib.callback.register('cm-police:server:mdtSetPhoto', function(src, characterId, url)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_photo', 1000) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    if characterId == '' then return false, 'Invalid character.' end
    url = tostring(url or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if url ~= '' then
        if not (url:match('^https?://') and #url <= 300) then
            return false, 'Photo must be a valid http(s) URL, 300 characters or fewer.'
        end
    end
    local dbUrl = url ~= '' and url or nil
    MySQL.insert.await(
        'INSERT INTO cm_police_criminal_status (character_id, photo_url, set_by) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE photo_url = VALUES(photo_url), set_by = VALUES(set_by)',
        { characterId, dbUrl, actorCid }
    )
    log(actorCid, 'mdt_photo_set', { targetCid = characterId })
    return true, url ~= '' and 'Photo updated.' or 'Photo cleared.', { photoUrl = dbUrl }
end)

-- Issues a fine straight from the MDT record, whether the citizen is online
-- or not. Online uses the same live cm-playerdata money path the G-menu
-- citation flow uses (server/citations.lua); offline debits `characters`
-- directly, mirroring cm-characters/server/admin.lua's own established
-- "offline-capable" direct-DB-write pattern (there is no mail/queue system
-- anywhere in this codebase to defer it instead). Extracted so both the
-- original single-violation callback (still used by the F7 tab) and the
-- newer multi-charge one below share the exact same money/citation logic.
local function issueSingleFine(actorCid, characterId, violation)
    local operationId = BeginPoliceOperation('citation', characterId, nil, violation.fine, {
        officerCid = actorCid, violationId = violation.id,
    })
    if not operationId then return false, 'Could not start the citation operation.' end
    local onlineSrc = sourceFor(characterId)
    local removed = false
    if onlineSrc then
        removed = exports[Config.PlayerDataResource]:RemoveMoney(onlineSrc, 'bank', violation.fine, 'police_citation', { violation = violation.id })
    else
        -- Single atomic UPDATE, not a SELECT-then-UPDATE: the balance check
        -- and the deduction happen in one statement, so two officers fining
        -- the same offline citizen at the same moment can't both pass a
        -- stale balance check -- MySQL serializes the two UPDATEs against
        -- the same row, and the second one's own `bank >= ?` condition sees
        -- the first's already-decremented value. `affected` is the number
        -- of rows the UPDATE actually changed (0 if the WHERE didn't match,
        -- i.e. insufficient funds or the character no longer exists).
        local affected = MySQL.update.await('UPDATE characters SET bank = bank - ? WHERE id = ? AND bank >= ?', { violation.fine, characterId, violation.fine })
        removed = tonumber(affected) == 1
    end
    if not removed then
        FinishPoliceOperation(operationId, 'refunded', { reason = 'insufficient_funds', moneyRemoved = false })
        return false, ('%s does not have enough money in their bank account.'):format(nameFor(characterId))
    end

    local detail = json.encode({ targetCid = characterId, violation = violation.label, fine = violation.fine, viaMdt = true })
    local called, committed = pcall(function()
        return MySQL.transaction.await({
            { query = 'UPDATE cm_police_organization SET fund_balance = fund_balance + ? WHERE id = 1', values = { violation.fine } },
            { query = 'INSERT INTO cm_police_citations (target_cid, officer_cid, violation_id, violation_label, fine) VALUES (?, ?, ?, ?, ?)', values = { characterId, actorCid, violation.id, violation.label, violation.fine } },
            { query = 'INSERT INTO cm_police_activity (actor_cid, action, detail) VALUES (?, ?, ?)', values = { actorCid, 'citation_issued', detail } },
        })
    end)
    if not called or committed ~= true then
        local refunded = false
        if onlineSrc then
            refunded = exports[Config.PlayerDataResource]:AddMoney(onlineSrc, 'bank', violation.fine, 'police_citation_refund', { violation = violation.id }) == true
        else
            refunded = tonumber(MySQL.update.await('UPDATE characters SET bank = bank + ? WHERE id = ?', { violation.fine, characterId })) == 1
        end
        if not refunded then
            FinishPoliceOperation(operationId, 'reconciliation_required', { reason = 'database_commit_failed', refund = false })
            print(('[cm-police] CRITICAL: citation refund failed for character %s amount %s'):format(characterId, violation.fine))
        else
            FinishPoliceOperation(operationId, 'refunded', { reason = 'database_commit_failed', refund = true })
        end
        return false, refunded and 'Citation failed safely; the fine was refunded.' or 'Citation failed and requires administrator reconciliation.'
    end
    FinishPoliceOperation(operationId, 'completed', { citationCommitted = true })
    if onlineSrc then
        TriggerClientEvent('cm-playerdata:client:interactionNotify', onlineSrc, ('You were fined $%d for %s.'):format(violation.fine, violation.label), 'error')
    end
    return true, violation.fine
end

lib.callback.register('cm-police:server:mdtIssueFine', function(src, characterId, violationId)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    local actor = memberFor(actorCid)
    if not has(actor, 'police.cite') then return false, 'Your rank cannot issue citations.' end
    if isFtoRestricted(actor) then return false, 'Cadets must be signed off by a training officer before issuing fines.' end
    if not rateLimit(src, 'police_mdt_fine', 1000) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    local violation = violationById(violationId)
    if characterId == '' or not violation then return false, 'Invalid violation.' end

    local ok, feeOrMessage = issueSingleFine(actorCid, characterId, violation)
    if not ok then return false, feeOrMessage end
    return true, ('Issued a $%d citation to %s for %s.'):format(violation.fine, nameFor(characterId), violation.label)
end)

-- MDT terminal's multi-charge checklist: applies each selected violation
-- as its own itemized citation row (same as a real ticket book listing
-- several charges), reusing issueSingleFine per charge. Stops at the first
-- failure (e.g. ran out of money partway through) rather than silently
-- skipping it, so the officer knows exactly how many of the selected
-- charges actually went through.
lib.callback.register('cm-police:server:mdtIssueFines', function(src, characterId, violationIds)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    local actor = memberFor(actorCid)
    if not has(actor, 'police.cite') then return false, 'Your rank cannot issue citations.' end
    if isFtoRestricted(actor) then return false, 'Cadets must be signed off by a training officer before issuing fines.' end
    if not rateLimit(src, 'police_mdt_fine', 1000) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    if characterId == '' or type(violationIds) ~= 'table' or #violationIds == 0 then return false, 'Select at least one charge.' end
    if #violationIds > 10 then return false, 'Select at most 10 charges at once.' end

    local violations = {}
    for _, violationId in ipairs(violationIds) do
        local violation = violationById(violationId)
        if not violation then return false, 'Invalid violation selected.' end
        violations[#violations + 1] = violation
    end

    local issuedCount, totalFine = 0, 0
    for _, violation in ipairs(violations) do
        local ok, feeOrMessage = issueSingleFine(actorCid, characterId, violation)
        if not ok then
            if issuedCount == 0 then return false, feeOrMessage end
            return true, ('Issued %d of %d charges ($%d total) before %s ran out of funds.'):format(issuedCount, #violations, totalFine, nameFor(characterId))
        end
        issuedCount = issuedCount + 1
        totalFine = totalFine + feeOrMessage
    end
    return true, ('Issued %d charges to %s totaling $%d.'):format(issuedCount, nameFor(characterId), totalFine)
end)

lib.callback.register('cm-police:server:mdtVehicleSearch', function(src, plate)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized or not rateLimit(src, 'police_mdt_vehicle', 600) then return nil end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return nil end
    local row
    pcall(function() row = exports[Config.VehiclesResource]:GetVehicleByPlate(plate) end)
    if not row then return nil end
    local ownerCid = row.owner_character_id and tostring(row.owner_character_id) or nil
    local impound = MySQL.single.await('SELECT fee, impounded_at FROM cm_police_impounds WHERE vehicle_id = ? AND released_at IS NULL ORDER BY id DESC LIMIT 1', { row.id })
    local impoundEvidence = MySQL.single.await([[SELECT image_url, message, officer_cid, captured_at, used_at
        FROM cm_police_impound_evidence WHERE vehicle_id = ? ORDER BY id DESC LIMIT 1]], { row.id })
    return {
        plate = row.plate,
        model = tostring(row.model or ''),
        ownerCid = ownerCid,
        ownerName = ownerCid and nameFor(ownerCid) or 'Unknown',
        -- Location/storage state is deliberately NOT returned here (or in
        -- mdtCitizenProfile's vehicle list above) -- the MDT no longer shows
        -- where a car is currently parked/stored. Impound status stays --
        -- that's an active police process (release fee owed), not a
        -- location leak.
        licenseNumber = (row.license_number and tostring(row.license_number) ~= '') and tostring(row.license_number) or nil,
        impound = impound and { fee = tonumber(impound.fee), impoundedAt = tostring(impound.impounded_at or '') } or nil,
        impoundEvidence = impoundEvidence and {
            imageUrl = tostring(impoundEvidence.image_url or ''),
            message = tostring(impoundEvidence.message or ''),
            capturedAt = tostring(impoundEvidence.captured_at or ''),
        } or nil,
        impoundProcess = {
            readyForTow = not impound and impoundEvidence ~= nil
                and impoundEvidence.used_at == nil
                and tostring(impoundEvidence.officer_cid or '') == tostring(actorCid or ''),
        },
    }
end)

-- Police-issued vehicle registration (record-only, same as the person-
-- license flows above -- no enforcement anywhere reads this; an unlicensed
-- car still drives/stores/sells exactly as before). Same permission tier as
-- the rest of the MDT (police.mdt), no fee -- this is an administrative
-- action, not a citizen purchase like the earlier self-service firearms
-- license.
lib.callback.register('cm-police:server:mdtIssueVehicleLicense', function(src, plate)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_vehicle_license', 1000) then return false, 'Please wait.' end
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return false, 'Invalid plate.' end

    local ok, message, licenseNumber = false, 'The registration office is unavailable right now.', nil
    pcall(function() ok, message, licenseNumber = exports[Config.VehiclesResource]:IssueVehicleLicense(plate) end)
    if ok then log(actorCid, 'vehicle_license_issued', { plate = plate, licenseNumber = licenseNumber }) end
    return ok, message, licenseNumber
end)

lib.callback.register('cm-police:server:mdtAddNote', function(src, characterId, note)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_note', 1000) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    local clean = tostring(note or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if characterId == '' or clean == '' then return false, 'Invalid note.' end
    local maxLen = tonumber(Config.Mdt.NoteMaxLength) or 500
    if #clean > maxLen then clean = clean:sub(1, maxLen) end
    MySQL.insert.await('INSERT INTO cm_police_notes (target_cid, author_cid, note) VALUES (?, ?, ?)', { characterId, actorCid, clean })
    log(actorCid, 'mdt_note_added', { targetCid = characterId })
    return true, 'Note added.'
end)

lib.callback.register('cm-police:server:mdtDeleteNote', function(src, noteId)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    noteId = tonumber(noteId)
    if not noteId then return false, 'Invalid note.' end
    local note = MySQL.single.await('SELECT id, target_cid, author_cid FROM cm_police_notes WHERE id = ? LIMIT 1', { noteId })
    if not note then return false, 'Note not found.' end
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not isAdmin and tostring(note.author_cid) ~= tostring(actorCid) then
        return false, 'You can only delete your own notes.'
    end
    MySQL.update.await('DELETE FROM cm_police_notes WHERE id = ?', { noteId })
    log(actorCid, 'mdt_note_deleted', { targetCid = note.target_cid })
    return true, 'Note deleted.'
end)

-- Evidence attachments: same shape as notes (add/delete, author-or-admin
-- delete rule) with one extra check -- the pasted value must look like a
-- real http(s) URL, since this renders as an <img>/link client-side.
local function validEvidenceUrl(url)
    if url:match('^img/bodycam/[A-Za-z0-9_-]+%.jpg$') then return true end
    if not url:match('^https://') or url:find('@', 1, true) then return false end
    local host = url:match('^https://([^/%?#:]+)')
    if not host then return false end
    host = host:lower()
    if host == 'localhost' or host:match('^127%.') or host:match('^10%.') or host:match('^192%.168%.')
        or host:match('^169%.254%.') or host:match('^172%.1[6-9]%.') or host:match('^172%.2%d%.') or host:match('^172%.3[01]%.') then return false end
    return true
end

lib.callback.register('cm-police:server:mdtAddEvidence', function(src, characterId, url, caption)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_evidence', 1000) then return false, 'Please wait.' end
    characterId = tostring(characterId or '')
    url = tostring(url or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if characterId == '' or url == '' or #url > 300 or not validEvidenceUrl(url) then
        return false, 'Evidence needs an approved HTTPS URL, 300 characters or fewer.'
    end
    local cleanCaption = tostring(caption or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 200)
    MySQL.insert.await('INSERT INTO cm_police_evidence (target_cid, author_cid, url, caption) VALUES (?, ?, ?, ?)', { characterId, actorCid, url, cleanCaption ~= '' and cleanCaption or 'Evidence' })
    log(actorCid, 'mdt_evidence_added', { targetCid = characterId })
    return true, 'Evidence added.'
end)

lib.callback.register('cm-police:server:mdtDeleteEvidence', function(src, evidenceId)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    evidenceId = tonumber(evidenceId)
    if not evidenceId then return false, 'Invalid evidence.' end
    local row = MySQL.single.await('SELECT id, target_cid, author_cid FROM cm_police_evidence WHERE id = ? LIMIT 1', { evidenceId })
    if not row then return false, 'Evidence not found.' end
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not isAdmin and tostring(row.author_cid) ~= tostring(actorCid) then
        return false, 'You can only delete your own evidence.'
    end
    MySQL.update.await('DELETE FROM cm_police_evidence WHERE id = ?', { evidenceId })
    log(actorCid, 'mdt_evidence_deleted', { evidenceId = evidenceId, targetCid = row.target_cid })
    return true, 'Evidence deleted.'
end)

-- BOLO alerts: purely MDT-driven (no command, no client gameplay hook,
-- unlike dispatch's citizen/gunfire-triggered calls). Broadcasting reuses
-- server/dispatch.lua's own recipients() -- same on-duty audience dispatch
-- calls already reach, exposed as a bare global there for exactly this.
local function publicBolo(row)
    return {
        id = tonumber(row.id),
        description = row.description,
        plate = row.plate,
        officerName = nameFor(row.officer_cid),
        createdAt = tostring(row.created_at or ''),
        clearedByName = row.cleared_by and nameFor(row.cleared_by) or nil,
        clearedAt = row.cleared_at and tostring(row.cleared_at) or nil,
    }
end

lib.callback.register('cm-police:server:mdtIssueBolo', function(src, description, plate)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_bolo', 1500) then return false, 'Please wait.' end
    local clean = tostring(description or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 200)
    if clean == '' then return false, 'Enter a description.' end
    local cleanPlate = tostring(plate or ''):gsub('%s+', ''):upper():sub(1, 16)
    local boloId = MySQL.insert.await('INSERT INTO cm_police_bolos (description, plate, officer_cid) VALUES (?, ?, ?)', { clean, cleanPlate ~= '' and cleanPlate or nil, actorCid })
    PoliceAlprRefreshBolos()
    log(actorCid, 'bolo_issued', { boloId = boloId, description = clean, plate = cleanPlate ~= '' and cleanPlate or nil })
    local alertText = cleanPlate ~= '' and ('%s (Plate: %s)'):format(clean, cleanPlate) or clean
    for _, targetSrc in ipairs(recipients('police.receive_dispatch')) do
        TriggerClientEvent('cm-police:client:boloIssued', targetSrc, alertText)
    end
    return true, 'BOLO issued.'
end)

lib.callback.register('cm-police:server:mdtClearBolo', function(src, boloId)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    boloId = tonumber(boloId)
    if not boloId then return false, 'Invalid BOLO.' end
    local affected = MySQL.update.await('UPDATE cm_police_bolos SET status = ?, cleared_by = ?, cleared_at = CURRENT_TIMESTAMP WHERE id = ? AND status = ?', { 'cleared', actorCid, boloId, 'active' })
    if tonumber(affected) == 1 then PoliceAlprRefreshBolos() end
    if tonumber(affected) ~= 1 then return false, 'That BOLO is no longer active.' end
    log(actorCid, 'bolo_cleared', { boloId = boloId })
    for _, targetSrc in ipairs(recipients('police.receive_dispatch')) do
        TriggerClientEvent('cm-police:client:boloCleared', targetSrc)
    end
    return true, 'BOLO cleared.'
end)

lib.callback.register('cm-police:server:mdtActiveBolos', function(src)
    local authorized = authorizedForMdt(src)
    if not authorized then return {} end
    local rows = MySQL.query.await('SELECT * FROM cm_police_bolos WHERE status = ? ORDER BY id DESC', { 'active' }) or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = publicBolo(row) end
    return list
end)

lib.callback.register('cm-police:server:mdtBoloHistory', function(src)
    local authorized = authorizedForMdt(src)
    if not authorized then return {} end
    local rows = MySQL.query.await('SELECT * FROM cm_police_bolos WHERE status = ? ORDER BY id DESC LIMIT 50', { 'cleared' }) or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = publicBolo(row) end
    return list
end)

-- Use-of-force reports: same permission tier and shape as BOLO above --
-- record-keeping visible to every MDT user, not an enforcement action.
lib.callback.register('cm-police:server:mdtFileUseOfForce', function(src, subject, forceType, narrative)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    if not rateLimit(src, 'police_mdt_uof', 1500) then return false, 'Please wait.' end
    local validType = false
    for _, t in ipairs(Config.Mdt.UseOfForceTypes) do if t == forceType then validType = true break end end
    if not validType then return false, 'Invalid force type.' end
    local cleanSubject = tostring(subject or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 120)
    local cleanNarrative = tostring(narrative or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 800)
    if cleanSubject == '' or cleanNarrative == '' then return false, 'Subject and narrative are required.' end
    MySQL.insert.await('INSERT INTO cm_police_uof_reports (officer_cid, subject, force_type, narrative) VALUES (?, ?, ?, ?)', { actorCid, cleanSubject, forceType, cleanNarrative })
    log(actorCid, 'use_of_force_filed', { subject = cleanSubject, forceType = forceType })
    return true, 'Use-of-force report filed.'
end)

lib.callback.register('cm-police:server:mdtUseOfForceHistory', function(src)
    local authorized = authorizedForMdt(src)
    if not authorized then return {} end
    local rows = MySQL.query.await('SELECT * FROM cm_police_uof_reports ORDER BY id DESC LIMIT 100') or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = {
            id = tonumber(row.id),
            officerCid = tostring(row.officer_cid),
            officerName = nameFor(row.officer_cid),
            subject = row.subject,
            forceType = row.force_type,
            narrative = row.narrative,
            createdAt = tostring(row.created_at or ''),
        }
    end
    return list
end)

lib.callback.register('cm-police:server:mdtDeleteUseOfForce', function(src, reportId)
    local authorized, actorCid = authorizedForMdt(src)
    if not authorized then return false, 'You must be an on-duty officer with MDT permission.' end
    reportId = tonumber(reportId)
    if not reportId then return false, 'Invalid report.' end
    local row = MySQL.single.await('SELECT id, officer_cid FROM cm_police_uof_reports WHERE id = ? LIMIT 1', { reportId })
    if not row then return false, 'Report not found.' end
    local isAdmin = false
    pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
    if not isAdmin and tostring(row.officer_cid) ~= tostring(actorCid) then
        return false, 'You can only delete your own reports.'
    end
    MySQL.update.await('DELETE FROM cm_police_uof_reports WHERE id = ?', { reportId })
    log(actorCid, 'use_of_force_deleted', { reportId = reportId })
    return true, 'Report deleted.'
end)

CreateThread(function()
    -- note's width must stay >= Config.Mdt.NoteMaxLength (shared/config.lua)
    -- -- raising that value alone without widening this column silently
    -- over-truncates instead of the intended Lua-side truncation above.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_notes (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        target_cid VARCHAR(64) NOT NULL,
        author_cid VARCHAR(64) NULL,
        note VARCHAR(500) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_cm_police_notes_target (target_cid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- One row per assessed character -- the star rating and Wanted flag are
    -- one officer assessment record, not two features to keep in sync.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_criminal_status (
        character_id VARCHAR(64) NOT NULL,
        stars TINYINT UNSIGNED NOT NULL DEFAULT 0,
        wanted TINYINT(1) NOT NULL DEFAULT 0,
        wanted_reason VARCHAR(160) NULL,
        set_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Column add for servers upgrading from before the MDT terminal's
    -- mugshot box existed -- same idempotent-alter pattern server/main.lua's
    -- own setupDatabase() already uses (pcall-wrapped so re-running on an
    -- already-migrated install is a silent no-op).
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_criminal_status ADD COLUMN photo_url VARCHAR(300) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_criminal_status ADD COLUMN wanted_reason VARCHAR(160) NULL') end)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_evidence (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        target_cid VARCHAR(64) NOT NULL,
        author_cid VARCHAR(64) NULL,
        url VARCHAR(300) NOT NULL,
        caption VARCHAR(200) NOT NULL DEFAULT 'Evidence',
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_cm_police_evidence_target (target_cid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- MDT Phase 2 (shared/config.lua's LicenseTypes comment): absence of a
    -- row means active for drivers/commercial/hunting, only an explicit
    -- revoke ever inserts one for those. Firearms is the one exception
    -- (Phase 4) -- absence means UNLICENSED, and a row only appears once
    -- purchased/issued; see HasValidLicense above.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_licenses (
        character_id VARCHAR(64) NOT NULL,
        license_type VARCHAR(32) NOT NULL,
        status ENUM('active','revoked') NOT NULL DEFAULT 'active',
        set_by VARCHAR(64) NULL,
        reason VARCHAR(160) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id, license_type)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Column + unique-key add for servers upgrading from before self-service
    -- license purchases existed (Phase 4). Same idempotent-alter pattern as
    -- photo_url above -- pcall-wrapped so re-running on an already-migrated
    -- install is a silent no-op. The UNIQUE KEY is what makes PurchaseLicense's
    -- retry-loop INSERT race-safe (a collision fails the INSERT instead of
    -- silently issuing a duplicate number to two players).
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_licenses ADD COLUMN license_number VARCHAR(20) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_licenses ADD UNIQUE KEY idx_cm_police_licenses_number (license_number)') end)
    -- BOLO alerts (MDT-only, no command/gameplay hook) -- plate is optional
    -- free text, not validated against a real vehicle: a BOLO is often
    -- issued on a partial/witnessed plate before anyone's looked it up,
    -- same "record what was reported" spirit as dispatch's own free-text
    -- details column.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_bolos (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        description VARCHAR(200) NOT NULL,
        plate VARCHAR(16) NULL,
        officer_cid VARCHAR(64) NOT NULL,
        status ENUM('active','cleared') NOT NULL DEFAULT 'active',
        cleared_by VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        cleared_at TIMESTAMP NULL,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Use-of-force reports: subject is free text (name/CID/description),
    -- same "record what was reported" spirit as BOLO's free-text plate --
    -- not every incident has (or needs) a resolvable MDT profile.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_uof_reports (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        officer_cid VARCHAR(64) NOT NULL,
        subject VARCHAR(120) NOT NULL,
        force_type VARCHAR(32) NOT NULL,
        narrative VARCHAR(800) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_cm_police_uof_officer (officer_cid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MdtReady = true
    PoliceSchemaMarkReady('mdt')
end)
