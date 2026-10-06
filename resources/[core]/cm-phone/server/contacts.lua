-- Contacts and blocks. Every row is owned by a character id resolved from the caller's session;
-- ids supplied by the client are only ever used together with that owner id in the WHERE clause.
local S = CMPhone.Server
local Config = CMPhone.Config

function S.ListContacts(cid)
    local rows = MySQL.query.await([[SELECT id, contact_number, display_name, favourite
        FROM cm_phone_contacts WHERE owner_character_id = ? ORDER BY favourite DESC, display_name ASC LIMIT ?]],
        { cid, Config.Contacts.max }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.id, number = r.contact_number, name = r.display_name, favourite = r.favourite == 1 or r.favourite == true }
    end
    return out
end

-- data = { id?, number, name, favourite? }
function S.SaveContact(cid, data)
    if type(data) ~= 'table' then return false, 'invalid_request' end
    local number = S.NormalizeNumber(data.number)
    local name = S.cleanText(data.name, Config.Contacts.nameMax)
    if not number then return false, 'invalid_number' end
    if not name then return false, 'invalid_name' end
    local favourite = data.favourite == true and 1 or 0

    if data.id ~= nil then
        local id = math.floor(tonumber(data.id) or 0)
        if id <= 0 then return false, 'invalid_request' end
        -- Ownership is part of the predicate: another character's row can never match.
        local owned = MySQL.single.await('SELECT id FROM cm_phone_contacts WHERE id = ? AND owner_character_id = ? LIMIT 1', { id, cid })
        if not owned then return false, 'not_found' end
        local ok, err = pcall(function()
            return MySQL.update.await([[UPDATE cm_phone_contacts SET contact_number = ?, display_name = ?, favourite = ?
                WHERE id = ? AND owner_character_id = ?]], { number, name, favourite, id, cid })
        end)
        if not ok then
            if tostring(err):lower():find('duplicate', 1, true) then return false, 'duplicate_number' end
            return false, 'internal_error'
        end
        return true, id
    end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM cm_phone_contacts WHERE owner_character_id = ?', { cid }) or 0
    if count >= Config.Contacts.max then return false, 'contact_limit' end
    local ok, result = pcall(function()
        return MySQL.insert.await('INSERT INTO cm_phone_contacts (owner_character_id, contact_number, display_name, favourite) VALUES (?, ?, ?, ?)',
            { cid, number, name, favourite })
    end)
    if not ok then
        if tostring(result):lower():find('duplicate', 1, true) then return false, 'duplicate_number' end
        return false, 'internal_error'
    end
    return true, result
end

function S.DeleteContact(cid, id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return false, 'invalid_request' end
    local affected = MySQL.update.await('DELETE FROM cm_phone_contacts WHERE id = ? AND owner_character_id = ?', { id, cid })
    if (tonumber(affected) or 0) < 1 then return false, 'not_found' end
    return true
end

-- Blocks ------------------------------------------------------------------

function S.ListBlocks(cid)
    local rows = MySQL.query.await('SELECT blocked_number FROM cm_phone_blocks WHERE owner_character_id = ? ORDER BY created_at DESC LIMIT 200', { cid }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.blocked_number end
    return out
end

-- Has `ownerCid` blocked `number`?
function S.IsBlocked(ownerCid, number)
    if not ownerCid or not number then return false end
    local row = MySQL.single.await('SELECT 1 AS hit FROM cm_phone_blocks WHERE owner_character_id = ? AND blocked_number = ? LIMIT 1', { ownerCid, number })
    return row ~= nil
end

function S.Block(cid, ownNumber, rawNumber)
    local number = S.NormalizeNumber(rawNumber)
    if not number then return false, 'invalid_number' end
    if number == ownNumber then return false, 'invalid_target' end
    MySQL.query.await('INSERT IGNORE INTO cm_phone_blocks (owner_character_id, blocked_number) VALUES (?, ?)', { cid, number })
    return true
end

function S.Unblock(cid, rawNumber)
    local number = S.NormalizeNumber(rawNumber)
    if not number then return false, 'invalid_number' end
    MySQL.update.await('DELETE FROM cm_phone_blocks WHERE owner_character_id = ? AND blocked_number = ?', { cid, number })
    return true
end
