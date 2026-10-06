-- cm-characters/server/creation.lua
-- Secure character creation. Account/slot ownership is server-authoritative only.


-- Production-safe local logger wrapper.
-- When Config.Debug/Config.VerboseLogs is false, normal CM-CHARACTERS debug prints are hidden.
-- Warnings/errors still print so real problems are visible.
local __cmCharactersPrint = print
local function __cmCharactersShouldVerbose()
    return Config and (Config.Debug == true or Config.VerboseLogs == true or Config.ProductionMode == false)
end
local function print(...)
    if __cmCharactersShouldVerbose() then
        return __cmCharactersPrint(...)
    end

    local first = tostring(select(1, ...) or '')
    local isCmCharactersLog = first:find('%[CM%-CHARACTERS') ~= nil
    if not isCmCharactersLog then
        return __cmCharactersPrint(...)
    end

    local upper = first:upper()
    if upper:find('ERROR', 1, true) or upper:find('WARNING', 1, true) or upper:find('FAILED', 1, true) or upper:find('DENIED', 1, true) then
        return __cmCharactersPrint(...)
    end
end

local creationLocks = {}

-- ═══════════════════════════════════════════════════════════════════════
-- PHASE 4B lifecycle fix: the character DB row is NO LONGER inserted here.
--
-- Previously this handler inserted a permanent `characters` row immediately
-- after identity validation, with appearance_json = '{}'. Character deletion
-- is disabled sitewide (see client/main.lua's own comment: "Character
-- deletion is disabled. Characters are permanent for now."), so a player who
-- backed out anywhere during Appearance permanently consumed a slot with a
-- naked, unfinished character that could never be removed.
--
-- Fix: identity is validated exactly as before (unchanged UX/errors), a
-- character ID is still reserved via CMAllocateCharacterId() (a separate
-- counter table — reserving an ID never touches the characters table), and
-- the validated data is kept as an in-memory PENDING DRAFT keyed by src. The
-- actual INSERT only happens in CommitPendingCharacterRow(), called from
-- server/appearance.lua's saveAppearance handler at "Save & Continue" —
-- confirmed safe because the entire appearance-editing session (camera,
-- sliders, gender switch, starter-clothes preview) is 100% client-side and
-- makes no server round-trip that queries the characters table by ID before
-- that point (verified by reading the complete client/appearance.lua).
--
-- If the player disconnects or backs out before Save & Continue, the draft
-- is simply discarded — no row was ever created, so there is nothing to
-- clean up and no abandoned character to leave behind.
--
-- Known tradeoff: PendingCharacterDrafts is plain Lua memory, not a
-- statebag/DB row, so it does NOT survive a cm-characters resource restart.
-- A restart while a player is actively mid-Appearance (post-identity,
-- pre-save) would lose that in-progress draft, and Save & Continue would
-- fail with a clear "Could not create character, please start again" error
-- rather than silently creating a broken row. This is judged the safer
-- default: it trades a rare admin/dev-restart edge case for eliminating the
-- much more common "every single Back click creates a permanent abandoned
-- character" problem.
CMCharacters.PendingCharacterDrafts = CMCharacters.PendingCharacterDrafts or {}

local function creationFail(src, message)
    TriggerClientEvent('cm-characters:client:createResult', src, false, tostring(message or 'Character creation failed'))
end

RegisterNetEvent('cm-characters:server:create', function(_clientAccountId, charSlot, data)
    local src = source
    if CMCharacters.IsRateLimited(src, 'createCharacter', 3, 30) then
        creationFail(src, 'Please wait before creating another character.')
        return
    end
    local accountId = CMCharacters.RequireAccount(src)
    if not accountId then
        creationFail(src, 'You are not logged in. Please login again.')
        return
    end

    local maxCharacters = CMCharacters.GetMaxCharacters(accountId)
    local valid, cleanOrErr = CMCharacters.ValidateCreationData(data, charSlot, maxCharacters)
    if not valid then
        creationFail(src, cleanOrErr)
        return
    end

    local clean = cleanOrErr
    local lockKey = accountId .. ':' .. tostring(clean.slot)
    if creationLocks[lockKey] then
        creationFail(src, 'This slot is already being created. Please wait a moment.')
        return
    end
    creationLocks[lockKey] = true

    local function done()
        creationLocks[lockKey] = nil
    end

    print(('[CM-CHARACTERS] secure create (pending draft): src=%s account=%s slot=%s name=%s %s'):format(
        tostring(src), tostring(accountId), tostring(clean.slot), clean.firstName, clean.lastName
    ))

    -- Check slot not taken. Re-checked again at commit time in
    -- CommitPendingCharacterRow, since minutes may pass in Appearance
    -- before the row actually gets inserted.
    local existing = CMCharacters.Query(
        'SELECT id FROM characters WHERE account_id = ? AND slot = ? LIMIT 1',
        { accountId, clean.slot }
    )
    if existing and #existing > 0 then
        done()
        creationFail(src, 'Character slot already used')
        return
    end

    -- Check max characters for this account.
    local count = tonumber(CMCharacters.Scalar(
        'SELECT COUNT(*) FROM characters WHERE account_id = ?',
        { accountId }
    ) or 0) or 0

    if count >= maxCharacters then
        done()
        creationFail(src, 'Maximum ' .. tostring(maxCharacters) .. ' characters reached')
        return
    end

    -- Check RP name not taken, case-insensitive.
    local nameTaken = CMCharacters.Query(
        'SELECT id FROM characters WHERE LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?) LIMIT 1',
        { clean.firstName, clean.lastName }
    )
    if nameTaken and #nameTaken > 0 then
        done()
        creationFail(src, 'Name already taken')
        return
    end

    local newCharId, idErr = CMAllocateCharacterId()
    if not newCharId then
        done()
        print('[CM-CHARACTERS] ERROR allocating fixed character ID: ' .. tostring(idErr))
        creationFail(src, 'Could not allocate character ID')
        return
    end

    CMCharacters.PendingCharacterDrafts[src] = {
        charId = tostring(newCharId),
        accountId = accountId,
        slot = clean.slot,
        firstName = clean.firstName,
        lastName = clean.lastName,
        dob = clean.dob,
        gender = clean.gender,
        createdAt = os.time()
    }

    done()

    print('[CM-CHARACTERS] Character draft reserved (not yet in DB): ' .. tostring(newCharId))
    TriggerClientEvent('cm-characters:client:createResult', src, true, {
        charId = tostring(newCharId),
        gender = clean.gender,
        message = 'Character created'
    })
end)

-- Commits a previously-reserved draft (see above) into a real `characters`
-- row. Called only from server/appearance.lua's saveAppearance handler, at
-- the exact moment the player presses Save & Continue for a brand-new
-- character. appearanceJson is the already-sanitized appearance data to
-- store immediately (avoids a separate insert-then-update round trip).
-- Returns (charRow, accountId) on success, or (nil, nil, errorMessage).
function CMCharacters.CommitPendingCharacterRow(src, expectedCharId, appearanceJson)
    local draft = CMCharacters.PendingCharacterDrafts[src]
    if not draft or tostring(draft.charId) ~= tostring(expectedCharId) then
        return nil, nil, 'No pending character found for this session. Please start character creation again.'
    end

    local accountId = draft.accountId

    -- Re-check slot/name/count at commit time — real time (potentially
    -- minutes of Appearance editing) has passed since the identity-time
    -- checks above, so another session could have legitimately taken the
    -- same slot or name in the meantime. The DB's unique constraint on
    -- (account_id, slot) remains the final backstop either way.
    local existing = CMCharacters.Query(
        'SELECT id FROM characters WHERE account_id = ? AND slot = ? LIMIT 1',
        { accountId, draft.slot }
    )
    if existing and #existing > 0 then
        return nil, nil, 'This character slot is no longer available.'
    end

    local maxCharacters = CMCharacters.GetMaxCharacters(accountId)
    local count = tonumber(CMCharacters.Scalar(
        'SELECT COUNT(*) FROM characters WHERE account_id = ?',
        { accountId }
    ) or 0) or 0
    if count >= maxCharacters then
        return nil, nil, 'Maximum ' .. tostring(maxCharacters) .. ' characters reached'
    end

    local nameTaken = CMCharacters.Query(
        'SELECT id FROM characters WHERE LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?) LIMIT 1',
        { draft.firstName, draft.lastName }
    )
    if nameTaken and #nameTaken > 0 then
        return nil, nil, 'This name was just taken. Please go back and choose another.'
    end

    local spawn = { x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0 }
    local finalAppearanceJson = tostring(appearanceJson or '{}')
    local ok, err = pcall(function()
        CMCharacters.Query([[
            INSERT INTO characters
            (id, account_id, slot, first_name, last_name, dob, gender, appearance_json, last_position, cash, bank, has_spawned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            tostring(draft.charId),
            accountId,
            draft.slot,
            draft.firstName,
            draft.lastName,
            draft.dob,
            draft.gender,
            finalAppearanceJson,
            json.encode(spawn),
            tonumber(Config and Config.StartingCash) or 500,
            tonumber(Config and Config.StartingBank) or 2000,
            0
        })
    end)

    if not ok then
        print('[CM-CHARACTERS] ERROR committing pending character: ' .. tostring(err))
        return nil, nil, 'Database error while creating character'
    end

    CMCharacters.PendingCharacterDrafts[src] = nil

    exports['cm-core']:CacheInvalidate('chars:' .. accountId)
    exports['cm-core']:Log('cm-characters', 'info', 'Character created', {
        player_src = src,
        account_id = accountId,
        char_id = tostring(draft.charId),
        slot = draft.slot,
        name = draft.firstName .. ' ' .. draft.lastName
    })

    print('[CM-CHARACTERS] Character committed successfully: ' .. tostring(draft.charId))

    local char = CMCharacters.GetCharacterById(draft.charId)
    if not char then
        return nil, nil, 'Character was created but could not be re-read. Please reconnect.'
    end
    return char, accountId, nil
end

AddEventHandler('playerDropped', function()
    local src = source
    if src then
        CMCharacters.PendingCharacterDrafts[src] = nil
    end
end)
