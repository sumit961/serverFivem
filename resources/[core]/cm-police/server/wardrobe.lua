-- cm-police wardrobe NPC. Wearing a duty preset is only possible while
-- standing at this admin-placed ped -- there is no instant-apply path
-- anywhere else anymore (the old choose_outfit action, server/main.lua's
-- generic dispatcher, has been removed). cm_police_member_outfit still
-- means exactly what it always did ("the preset id this officer last
-- actually wore", read by resolveMemberOutfit for restart reconciliation in
-- server/main.lua) -- wearOutfit below upserts it the same way
-- choose_outfit used to. Personal quick-slots are a separate, new concept:
-- up to Config.Wardrobe.MaxQuickSlots pointers any real member can set for
-- themselves into the shared, manager-curated preset list.

local NpcLocation -- { x, y, z, heading } cached from cm_police_settings; nil until an admin sets it

function GetWardrobeNpcStatus()
    if not NpcLocation then return { set = false } end
    return { set = true, x = NpcLocation.x, y = NpcLocation.y, z = NpcLocation.z, heading = NpcLocation.heading }
end

-- Called from server/main.lua's action dispatcher (the 'set_wardrobe_npc'
-- case) -- same anti-spoof shape as SetImpoundKioskLocation, broadcast
-- live to every connected client since the ped needs to exist for
-- everyone, not just officers.
function SetWardrobeNpcLocation(src, actor, payload)
    if not has(actor, 'police.manage_outfits') then return false, 'Your rank cannot configure the wardrobe NPC.' end
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    local heading = tonumber(payload.heading) or 0.0
    if not x or not y or not z or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or math.abs(z) > 2500.0 then
        return false, 'Invalid wardrobe NPC location.'
    end
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local serverCoords = GetEntityCoords(ped)
        if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then return false, 'Wardrobe NPC location mismatch.' end
    end
    NpcLocation = { x = x, y = y, z = z, heading = heading }
    local actorCid = cid(src)
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
        { 'wardrobe_npc', json.encode(NpcLocation), actorCid })
    log(actorCid, 'wardrobe_npc_set', { x = x, y = y, z = z, heading = heading })
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-police:client:wardrobeNpcUpdated', tonumber(playerId), NpcLocation)
    end
    return true, 'Wardrobe NPC location saved.'
end

function ResetWardrobeNpcLocation(src, actor)
    if not has(actor, 'police.manage_outfits') then return false, 'Your rank cannot configure the wardrobe NPC.' end
    NpcLocation = nil
    MySQL.update.await("DELETE FROM cm_police_settings WHERE setting_key = 'wardrobe_npc'")
    TriggerClientEvent('cm-police:client:wardrobeNpcUpdated', -1, false)
    log(cid(src), 'wardrobe_npc_reset', {})
    return true, 'Wardrobe NPC reset.'
end

-- Any player, no permission gate -- deploy can happen before the F7
-- dashboard has ever been opened, same reasoning as the impound kiosk
-- location's own public pull callback.
lib.callback.register('cm-police:server:wardrobeNpcLocation', function(src)
    return NpcLocation
end)

local function nearWardrobeNpc(ped)
    if not NpcLocation then return false end
    return #(GetEntityCoords(ped) - vector3(NpcLocation.x, NpcLocation.y, NpcLocation.z)) <= (Config.Wardrobe.NpcInteractDistance or 2.5)
end

local function wardrobeOfficer(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local ped = GetPlayerPed(src)
    if not member or dbBoolean(member.is_suspended) then return nil, characterId, 'You are not an active Police member.' end
    if not ped or ped == 0 or not nearWardrobeNpc(ped) then return nil, characterId, 'You must be at the clothing NPC.' end
    return member, characterId
end

local function favoriteRows(characterId)
    local rows = MySQL.query.await('SELECT slot, name, outfit FROM cm_police_outfit_favorites WHERE character_id = ? ORDER BY slot ASC', { characterId }) or {}
    for _, row in ipairs(rows) do row.slot = tonumber(row.slot); row.outfit = decode(row.outfit) end
    return rows
end

local function approvedRequiredUniform(outfit, sex)
    if type(outfit) ~= 'table' or type(outfit.components) ~= 'table' then
        return false, 'Invalid Police outfit.'
    end
    local rows = {}
    local loaded = pcall(function()
        rows = exports['cm-items']:GetClothingCatalogRows({
            gender = sex, shop = 'org_police', includeDisabled = true,
        }) or {}
    end)
    if not loaded then return false, 'Police clothing catalog is unavailable.' end

    local required = {
        { index = 11, label = 'outerwear' },
        { index = 4, label = 'pants' },
        { index = 6, label = 'shoes' },
    }
    local missing = {}
    for _, requirement in ipairs(required) do
        local selected = outfit.components[tostring(requirement.index)] or outfit.components[requirement.index]
        local drawable = selected and math.floor(tonumber(selected.drawable) or -1) or -1
        local texture = selected and math.floor(tonumber(selected.texture) or -1) or -1
        local approved = false
        for _, row in ipairs(rows) do
            if tostring(row.componentType or 'component') == 'component'
                and tonumber(row.componentIndex) == requirement.index
                and tonumber(row.drawableId) == drawable
                and math.max(0, tonumber(row.textureId) or 0) == texture then
                approved = true
                break
            end
        end
        if not approved then missing[#missing + 1] = requirement.label end
    end
    if #missing > 0 then
        return false, ('Select approved Police %s before starting duty.'):format(table.concat(missing, ', '))
    end
    return true
end

lib.callback.register('cm-police:server:wardrobeClosetData', function(src)
    local member, characterId, reason = wardrobeOfficer(src)
    if not member then return nil, reason end
    return { favorites = favoriteRows(characterId), maxSlots = Config.Wardrobe.MaxQuickSlots or 5 }
end)

-- The visual NPC closet previews individual catalog pieces directly on the
-- ped. Its Done button calls this contract with the resulting appearance.
-- The client payload is never trusted by itself: all three required uniform
-- components must exactly match server-owned org_police catalog rows and the
-- officer must still be physically beside the configured wardrobe NPC.
lib.callback.register('cm-police:server:finishWardrobeDuty', function(src, outfit, requestedSex)
    if not rateLimit(src, 'police_finish_wardrobe_duty', 1000) then return false, 'Please wait.' end
    local member, characterId, reason = wardrobeOfficer(src)
    if not member then return false, reason end
    local sex = requestedSex == 'female' and 'female' or 'male'
    local approved, approvalReason = approvedRequiredUniform(outfit, sex)
    if not approved then return false, approvalReason end
    local dutyOk, dutyMessage, cleanOutfit = PoliceBeginDutyWithOutfit(characterId, outfit, { source = 'wardrobe_custom' })
    if not dutyOk then return false, dutyMessage end
    local encoded = json.encode(cleanOutfit)
    if #encoded > 16000 then return false, 'Outfit data is too large.' end
    MySQL.insert.await([[INSERT INTO cm_police_active_favorite_outfit (character_id, slot, outfit) VALUES (?, NULL, ?)
        ON DUPLICATE KEY UPDATE slot = NULL, outfit = VALUES(outfit), updated_at = NOW()]], { characterId, encoded })
    log(characterId, 'wardrobe_custom_worn', {})
    return true, dutyMessage
end)

lib.callback.register('cm-police:server:saveWardrobeFavorite', function(src, name, outfit)
    local member, characterId, reason = wardrobeOfficer(src)
    if not member then return false, reason end
    if type(outfit) ~= 'table' or type(outfit.components) ~= 'table' or type(outfit.props) ~= 'table' then return false, 'Invalid outfit.' end
    local encoded = json.encode(outfit)
    if #encoded > 16000 then return false, 'Outfit data is too large.' end
    local maxSlots = Config.Wardrobe.MaxQuickSlots or 5
    local usedRows = MySQL.query.await('SELECT slot FROM cm_police_outfit_favorites WHERE character_id = ?', { characterId }) or {}
    local used = {}; for _, row in ipairs(usedRows) do used[tonumber(row.slot)] = true end
    local slot; for index = 1, maxSlots do if not used[index] then slot = index break end end
    if not slot then return false, ('All %d favorite slots are full. Remove one first.'):format(maxSlots) end
    name = tostring(name or ('Favorite %d'):format(slot)):gsub('[%c]+', ' '):sub(1, 32)
    MySQL.insert.await('INSERT INTO cm_police_outfit_favorites (character_id, slot, name, outfit) VALUES (?, ?, ?, ?)', { characterId, slot, name, encoded })
    log(characterId, 'wardrobe_favorite_added', { slot = slot, name = name })
    return true, ('Outfit added to favorite slot %d.'):format(slot), favoriteRows(characterId)
end)

lib.callback.register('cm-police:server:removeWardrobeFavorite', function(src, slot)
    local member, characterId, reason = wardrobeOfficer(src)
    if not member then return false, reason end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > (Config.Wardrobe.MaxQuickSlots or 5) then return false, 'Invalid favorite slot.' end
    MySQL.update.await('DELETE FROM cm_police_outfit_favorites WHERE character_id = ? AND slot = ?', { characterId, slot })
    MySQL.update.await('DELETE FROM cm_police_active_favorite_outfit WHERE character_id = ? AND slot = ?', { characterId, slot })
    log(characterId, 'wardrobe_favorite_removed', { slot = slot })
    return true, 'Favorite removed.', favoriteRows(characterId)
end)

lib.callback.register('cm-police:server:wearWardrobeFavorite', function(src, slot)
    local member, characterId, reason = wardrobeOfficer(src)
    if not member then return false, reason end
    slot = tonumber(slot)
    local row = slot and MySQL.single.await('SELECT name, outfit FROM cm_police_outfit_favorites WHERE character_id = ? AND slot = ? LIMIT 1', { characterId, slot })
    if not row then return false, 'That favorite slot is empty.' end
    local outfit = decode(row.outfit)
    local dutyOk, dutyMessage = PoliceBeginDutyWithOutfit(characterId, outfit, { source = 'wardrobe_favorite', slot = slot })
    if not dutyOk then return false, dutyMessage end
    MySQL.insert.await([[INSERT INTO cm_police_active_favorite_outfit (character_id, slot, outfit) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE slot = VALUES(slot), outfit = VALUES(outfit), updated_at = NOW()]], { characterId, slot, row.outfit })
    log(characterId, 'wardrobe_favorite_worn', { slot = slot, name = row.name })
    return true, dutyMessage, outfit
end)

-- Menu data for the NPC's PoliceQuickMenu (client/wardrobe.lua): this
-- officer's quick-slots (joined with preset name) + the full preset list
-- for their sex, used to populate the "assign a slot" submenu.
lib.callback.register('cm-police:server:wardrobeMenuData', function(src, sex)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) then return nil end
    sex = sex == 'female' and 'female' or 'male'

    local presetRows = MySQL.query.await('SELECT id, name FROM cm_police_outfit_presets WHERE sex = ? ORDER BY name ASC', { sex }) or {}
    local presets = {}
    for _, row in ipairs(presetRows) do
        presets[#presets + 1] = { id = tonumber(row.id), name = row.name }
    end

    local slotRows = MySQL.query.await([[
        SELECT s.slot, s.preset_id, p.name FROM cm_police_outfit_slots s
        JOIN cm_police_outfit_presets p ON p.id = s.preset_id
        WHERE s.character_id = ?
    ]], { characterId }) or {}
    local slotsByNumber = {}
    for _, row in ipairs(slotRows) do
        slotsByNumber[tonumber(row.slot)] = { presetId = tonumber(row.preset_id), presetName = row.name }
    end
    local slots = {}
    for slot = 1, (Config.Wardrobe.MaxQuickSlots or 5) do
        slots[slot] = slotsByNumber[slot] or false
    end

    return { presets = presets, slots = slots }
end)

lib.callback.register('cm-police:server:setWardrobeSlot', function(src, slot, presetId)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) then return false, 'You are not a Police member.' end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > (Config.Wardrobe.MaxQuickSlots or 5) then return false, 'Invalid slot.' end

    presetId = tonumber(presetId)
    if not presetId then
        MySQL.update.await('DELETE FROM cm_police_outfit_slots WHERE character_id = ? AND slot = ?', { characterId, slot })
        return true, 'Quick slot cleared.'
    end
    local preset = MySQL.single.await('SELECT id FROM cm_police_outfit_presets WHERE id = ?', { presetId })
    if not preset then return false, 'That clothing preset no longer exists.' end
    MySQL.insert.await('INSERT INTO cm_police_outfit_slots (character_id, slot, preset_id) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE preset_id = VALUES(preset_id)',
        { characterId, slot, presetId })
    return true, 'Quick slot updated.'
end)

-- Replaces the old choose_outfit action's upsert-and-return-outfit
-- behavior, but (a) requires standing at the NPC, (b) always returns the
-- outfit and starts duty when it contains all required uniform categories.
lib.callback.register('cm-police:server:wearOutfit', function(src, presetId, sex)
    if not rateLimit(src, 'police_wear_outfit', 800) then return false, 'Please wait.' end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) then return false, 'You are not a Police member.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not nearWardrobeNpc(ped) then return false, 'You must be at the wardrobe NPC to do this.' end

    sex = sex == 'female' and 'female' or 'male'
    presetId = tonumber(presetId)
    local preset = presetId and MySQL.single.await('SELECT id, outfit FROM cm_police_outfit_presets WHERE id = ? AND sex = ? LIMIT 1', { presetId, sex })
    if not preset then return false, 'That Police clothing preset is unavailable.' end
    local outfit = decode(preset.outfit)
    local dutyOk, dutyMessage = PoliceBeginDutyWithOutfit(characterId, outfit, { source = 'wardrobe_preset', presetId = presetId })
    if not dutyOk then return false, dutyMessage end

    MySQL.insert.await('INSERT INTO cm_police_member_outfit (character_id, preset_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE preset_id = VALUES(preset_id)', { characterId, presetId })
    MySQL.update.await('DELETE FROM cm_police_active_favorite_outfit WHERE character_id = ?', { characterId })
    log(characterId, 'outfit_worn', { presetId = presetId })
    return true, dutyMessage, { outfit = outfit }
end)

CreateThread(function()
    -- Same generic key/value table server/booking.lua's own CreateThread
    -- already creates (and server/impound.lua/server/barricades.lua
    -- duplicate for their own settings) -- IF NOT EXISTS makes running it
    -- from every file safe regardless of load order.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_settings (
        setting_key VARCHAR(64) NOT NULL,
        setting_value LONGTEXT NOT NULL,
        updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- No FOREIGN KEY here (unlike cm_police_member_outfit's own, created in
    -- the SAME thread/file as cm_police_outfit_presets) -- this table is
    -- created from a DIFFERENT file's CreateThread than the one that
    -- creates cm_police_outfit_presets, with no ordering guarantee between
    -- the two across files, so a real FK could fail to create depending on
    -- which resolves first. Matches this codebase's own dominant pattern
    -- (cm_police_bookings/citations/impounds/etc. also reference ids as
    -- plain columns, no real FK) -- a deleted preset just leaves a slot
    -- pointing nowhere, caught by wearOutfit's own existence check.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_outfit_slots (
        character_id VARCHAR(64) NOT NULL,
        slot TINYINT UNSIGNED NOT NULL,
        preset_id BIGINT UNSIGNED NOT NULL,
        PRIMARY KEY (character_id, slot)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_outfit_favorites (
        character_id VARCHAR(64) NOT NULL, slot TINYINT UNSIGNED NOT NULL, name VARCHAR(32) NOT NULL,
        outfit LONGTEXT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id, slot)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_active_favorite_outfit (
        character_id VARCHAR(64) NOT NULL, slot TINYINT UNSIGNED NULL, outfit LONGTEXT NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_active_favorite_outfit ADD COLUMN slot TINYINT UNSIGNED NULL AFTER character_id') end)
    local row = MySQL.single.await('SELECT setting_value FROM cm_police_settings WHERE setting_key = ? LIMIT 1', { 'wardrobe_npc' })
    if row then
        local decoded = decode(row.setting_value)
        if type(decoded.x) == 'number' then NpcLocation = decoded end
    end
    PoliceSchemaMarkReady('wardrobe')
end)
