-- Public front-desk services shared by every cm-law organization.
-- The NPC/client only presents choices; all identity, proximity, inventory,
-- wanted, jail, and dispatch checks are repeated here.

local Confirmations, SurrenderBusy = {}, {}

local function clean(value, limit)
    return tostring(value or ''):gsub('[%c]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, limit)
end

local function deskAuthority(src, orgId)
    orgId = validOrgId(orgId)
    if not orgId or not nearFacility(src, orgId, 'front_desk') then return nil, nil, 'You must remain at that organization front desk.' end
    local characterId = characterIdFor(src)
    if not characterId then return nil, nil, 'Your character is unavailable.' end
    return orgId, tostring(characterId)
end

local function wantedStatus(characterId)
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT stars,wanted,wanted_reason FROM cm_police_criminal_status WHERE character_id=? LIMIT 1', { characterId })
    end)
    if not ok then return nil end
    local stars = row and math.max(0, math.min(6, math.floor(tonumber(row.stars) or 0))) or 0
    return { wanted = row and tonumber(row.wanted) == 1 and stars > 0 or false, stars = stars,
        reason = clean(row and row.wanted_reason, 160) }
end

local function inventoryDefinitions()
    local weapons, ammo, illegal = {}, {}, {}
    for _, row in ipairs(exports['cm-weapons']:GetAllWeapons(true) or {}) do
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name ~= '' then weapons[name] = tostring(row.label or name) end
    end
    for _, row in ipairs(exports['cm-weapons']:GetAllAmmo(true) or {}) do
        local name = tostring(row.itemName or row.item_name or ''):lower()
        if name ~= '' then ammo[name] = tostring(row.label or name) end
    end
    for name, row in pairs(exports['cm-items']:GetAllItems() or {}) do
        if type(row) == 'table' and row.illegal == true then illegal[tostring(name):lower()] = tostring(row.label or name) end
    end
    return weapons, ammo, illegal
end

local function confiscatableInventory(src, characterId)
    if GetResourceState('cm-inventory') ~= 'started' or GetResourceState('cm-weapons') ~= 'started'
        or GetResourceState('cm-items') ~= 'started' then return nil, 'Inventory services are unavailable.' end
    local inventory = exports['cm-inventory']:GetInventory(src)
    if type(inventory) ~= 'table' then return nil, 'Your inventory could not be verified.' end
    local personallyLicensed = false
    if GetResourceState('cm-police') == 'started' then
        pcall(function() personallyLicensed = exports['cm-police']:HasValidLicense(src, 'firearms') == true end)
    end
    local issues = {}
    for _, row in ipairs(MySQL.query.await([[SELECT license_number,status FROM cm_legal_armory_issues WHERE character_id=?]], { characterId }) or {}) do
        issues[tostring(row.license_number)] = tostring(row.status)
    end
    local weapons, ammo, illegal = inventoryDefinitions()
    local result, seen = {}, {}
    for _, item in ipairs(inventory.items or {}) do
        local name = tostring(item.item_name or item.name or ''):lower()
        local quantity, metadata = math.max(0, math.floor(tonumber(item.quantity) or 0)), type(item.metadata) == 'table' and item.metadata or {}
        local issueNumber = tostring(metadata.issueLicenseNumber or metadata.licenseNumber or '')
        local issueValid = issueNumber ~= '' and issues[issueNumber] == 'issued'
        local reason, label
        if illegal[name] then reason, label = 'illegal_item', illegal[name]
        elseif weapons[name] and not personallyLicensed and not issueValid then reason, label = 'unlicensed_weapon', weapons[name]
        elseif ammo[name] and not personallyLicensed and not issueValid then reason, label = 'unlicensed_ammunition', ammo[name] end
        local slot = tostring(item.slot or '')
        if reason and quantity > 0 and slot ~= '' and not seen[slot] then
            seen[slot] = true
            result[#result + 1] = { slot = slot, label = label, quantity = quantity, reason = reason }
        end
    end
    return result
end

local function tokenFor(src, orgId, action)
    local token = ('%s:%d:%d:%06d'):format(action, tonumber(src), os.time(), math.random(0, 999999))
    Confirmations[src] = { token = token, orgId = orgId, action = action, expiresAt = GetGameTimer() + 20000 }
    return token
end

local function validToken(src, orgId, action, token)
    local pending = Confirmations[src]
    Confirmations[src] = nil
    return pending and pending.orgId == orgId and pending.action == action and pending.token == tostring(token or '')
        and pending.expiresAt >= GetGameTimer()
end

lib.callback.register('cm-law:server:frontDeskService', function(src, orgId, service, token)
    orgId, service = tostring(orgId or ''), tostring(service or '')
    local authorizedOrg, characterId, failure = deskAuthority(src, orgId)
    if not authorizedOrg then return { ok = false, error = failure } end
    if not rateLimit(src, 'law_front_desk_' .. service, service:find('confirm', 1, true) and 1200 or 500) then
        return { ok = false, error = 'Please wait.' }
    end
    local org = Config.Organizations[authorizedOrg]

    if service == 'assistance' then
        local ok, message = exports[GetCurrentResourceName()]:CreateLawCallForOrganization(src, authorizedOrg,
            ('Citizen requesting assistance at the %s front desk.'):format(org.shortLabel))
        if ok then logActivity(authorizedOrg, characterId, 'front_desk_service_requested', {}) end
        return { ok = ok, message = ok and 'A unit has been notified.' or nil, error = not ok and message or nil }
    end

    if service == 'surrender' then
        local status = wantedStatus(characterId)
        if not status then return { ok = false, error = 'Wanted records are unavailable.' } end
        if not status.wanted then return { ok = false, error = 'You have no active warrants or wanted level.' } end
        local minutes = status.stars * (tonumber(Config.Custody.SurrenderMinutesPerStar) or 15)
        return { ok = true, confirmation = true, confirmAction = 'confirm_surrender', token = tokenFor(src, authorizedOrg, 'surrender'),
            message = ('Surrender for %d wanted star%s and serve %d minutes?'):format(status.stars, status.stars == 1 and '' or 's', minutes) }
    end

    if service == 'confirm_surrender' then
        if not validToken(src, authorizedOrg, 'surrender', token) then return { ok = false, error = 'Surrender confirmation expired.' } end
        if SurrenderBusy[characterId] then return { ok = false, error = 'Your surrender is already processing.' } end
        local status = wantedStatus(characterId)
        if not status or not status.wanted then return { ok = false, error = 'You no longer have an active wanted level.' } end
        local jail = exports[GetCurrentResourceName()]:GetSharedJailConfiguration()
        if type(jail) ~= 'table' or type(jail.spawns) ~= 'table' or #jail.spawns < 1 or type(jail.release) ~= 'table' then
            return { ok = false, error = 'The shared jail is not configured.' }
        end
        local existing = MySQL.single.await("SELECT status FROM cm_legal_custody WHERE character_id=? AND status IN ('cuffed','processing','jailed') LIMIT 1", { characterId })
        if existing then return { ok = false, error = 'You already have active custody.' } end
        SurrenderBusy[characterId] = tonumber(src)
        local minutes = status.stars * (tonumber(Config.Custody.SurrenderMinutesPerStar) or 15)
        local reason = status.reason ~= '' and ('Voluntary surrender: ' .. status.reason) or 'Voluntary surrender for active wanted level'
        local charges = json.encode({ { id = 'wanted_surrender', label = 'Active Wanted Level', jailMinutes = minutes, stars = status.stars } })
        local bookingId = MySQL.insert.await([[INSERT INTO cm_legal_bookings
            (organization_id,character_id,officer_cid,reason,charges,sentence_minutes,handoff_status)
            VALUES (?,?,?,?,?,?,'processing')]], { authorizedOrg, characterId, characterId, reason, charges, minutes })
        if not bookingId then SurrenderBusy[characterId] = nil; return { ok = false, error = 'Could not journal your surrender.' } end
        MySQL.insert.await([[INSERT INTO cm_legal_custody(organization_id,character_id,officer_cid,status,reason,booking_minutes)
            VALUES(?,?,NULL,'processing',?,?) ON DUPLICATE KEY UPDATE organization_id=VALUES(organization_id),officer_cid=NULL,
            status='processing',reason=VALUES(reason),booking_minutes=VALUES(booking_minutes),updated_at=NOW()]],
            { authorizedOrg, characterId, reason, minutes })
        local jailed, jailFailure = exports['cm-prison']:JailSelf(src, minutes, reason, 10000, {
            spawns = jail.spawns, release = jail.release, arrestedBy = org.label, bookingId = bookingId })
        if not jailed and jailFailure == 'target_disconnected' then
            local stateOk, imprisoned = pcall(function() return exports['cm-prison']:IsPrisoner(src) end)
            if stateOk and imprisoned == true then jailed = true end
        end
        if not jailed then
            MySQL.transaction.await({
                { query = "UPDATE cm_legal_custody SET status='released',updated_at=NOW() WHERE character_id=? AND status='processing'", values = { characterId } },
                { query = "UPDATE cm_legal_bookings SET handoff_status='failed',failure_reason=? WHERE id=?", values = { clean(jailFailure, 64), bookingId } },
            })
            SurrenderBusy[characterId] = nil
            return { ok = false, error = jailFailure == 'prison_full' and 'The shared jail is currently full.' or 'Prison could not accept your surrender.' }
        end
        MySQL.transaction.await({
            { query = "UPDATE cm_legal_custody SET status='jailed',updated_at=NOW() WHERE character_id=?", values = { characterId } },
            { query = "UPDATE cm_legal_bookings SET handoff_status='confirmed',confirmed_at=NOW(),release_at=DATE_ADD(NOW(),INTERVAL ? MINUTE) WHERE id=?", values = { minutes, bookingId } },
            { query = "UPDATE cm_police_criminal_status SET stars=0,wanted=0,wanted_reason=NULL WHERE character_id=?", values = { characterId } },
        })
        pcall(function() exports[Config.PlayerDataResource]:ClearWantedStars(src) end)
        SurrenderBusy[characterId] = nil
        logActivity(authorizedOrg, characterId, 'front_desk_surrendered', { bookingId = bookingId, stars = status.stars, minutes = minutes })
        return { ok = true, message = ('Your surrender has been accepted. Sentence: %d minutes.'):format(minutes) }
    end

    if service == 'weapons' then
        local items, itemFailure = confiscatableInventory(src, characterId)
        if not items then return { ok = false, error = itemFailure } end
        if #items < 1 then return { ok = false, error = 'No unlicensed weapons, ammunition, or illegal items were found.' } end
        local labels = {}
        for _, item in ipairs(items) do labels[#labels + 1] = ('%s x%d'):format(item.label, item.quantity) end
        return { ok = true, confirmation = true, confirmAction = 'confirm_weapons', token = tokenFor(src, authorizedOrg, 'weapons'),
            message = ('Place these items on the counter: %s. Permanently surrender them?'):format(table.concat(labels, ', ')) }
    end

    if service == 'confirm_weapons' then
        if not validToken(src, authorizedOrg, 'weapons', token) then return { ok = false, error = 'Confiscation confirmation expired.' } end
        local items, itemFailure = confiscatableInventory(src, characterId)
        if not items then return { ok = false, error = itemFailure } end
        local moved, failed = {}, {}
        for _, item in ipairs(items) do
            local ok, result = exports['cm-inventory']:TransferItemToContainer(src, item.slot, 'legal_org_evidence', authorizedOrg,
                authorizedOrg .. '-evidence-', 100, ('front_desk_surrender:%s'):format(characterId))
            if ok then
                moved[#moved + 1] = { itemName = result.itemName, quantity = result.quantity }
                if result.metadata and result.metadata.issueId then
                    MySQL.update.await("UPDATE cm_legal_armory_issues SET status='confiscated' WHERE id=? AND character_id=?",
                        { tonumber(result.metadata.issueId), characterId })
                end
            else failed[#failed + 1] = { slot = item.slot, reason = tostring(result) } end
        end
        logActivity(authorizedOrg, characterId, 'front_desk_contraband_surrendered', { moved = moved, failedCount = #failed })
        if #moved < 1 then return { ok = false, error = failed[1] and failed[1].reason or 'No confiscatable items remained.' } end
        return { ok = true, message = ('%d item stack%s moved into %s evidence custody.'):format(#moved, #moved == 1 and '' or 's', org.shortLabel) }
    end

    return { ok = false, error = 'Unknown front-desk service.' }
end)

AddEventHandler('playerDropped', function()
    Confirmations[source] = nil
    local dropped = tonumber(source)
    for characterId, ownerSrc in pairs(SurrenderBusy) do
        if ownerSrc == dropped then SurrenderBusy[characterId] = nil end
    end
end)
