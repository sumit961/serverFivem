-- ============================================================
--  cm-house | sv_templates.lua   |  PHASE 1
--
--  A template is an interior layout walked ONCE and reused forever.
--  Selecting "Modern House L2" instantly gives a property its entry, exit,
--  weapon lockers and garage door -- the admin never places them again.
--
--  Garage capacity is NOT a number anyone types. It is the count of physical
--  slots that were walked to and placed. Seven saved coordinates means seven
--  cars, and there is no eighth.
-- ============================================================

InteriorTemplates = {}   -- [id] = tpl
GarageTemplates   = {}   -- [id] = tpl (with .slots)

local function jdec(v, fallback)
    if v == nil or v == '' then return fallback end
    if type(v) == 'table' then return v end
    local ok, out = pcall(json.decode, v)
    if not ok or out == nil then return fallback end
    return out
end

-- ------------------------------------------------------------
--  Load
-- ------------------------------------------------------------
function LoadTemplates()
    InteriorTemplates, GarageTemplates = {}, {}

    local irows = MySQL.query.await('SELECT * FROM cm_house_interior_templates WHERE enabled = 1') or {}
    for _, t in ipairs(irows) do
        t.id            = tonumber(t.id) or t.id
        t.entry         = jdec(t.entry)
        t.exit_point    = jdec(t.exit_point)
        -- garage_door / house_door are legacy: one door now serves both,
        -- so the column may exist on old rows but is never read.
        t.wardrobes     = jdec(t.wardrobes, {})
        t.weapon_storages = jdec(t.weapon_storages, {})
        if #t.weapon_storages == 0 and #t.wardrobes > 0 then
            t.weapon_storages = t.wardrobes
        end
        t.stashes       = jdec(t.stashes, {})
        t.allowed_types = jdec(t.allowed_types, {})
        t.signature     = t.signature or ''
        InteriorTemplates[t.id] = t
    end

    local grows = MySQL.query.await('SELECT * FROM cm_house_garage_templates WHERE enabled = 1') or {}
    for _, t in ipairs(grows) do
        t.id           = tonumber(t.id) or t.id
        t.capacity     = tonumber(t.capacity) or 0
        t.player_entry = jdec(t.player_entry)
        t.vehicle_exit = jdec(t.vehicle_exit)
        t.vehicle_exits = jdec(t.vehicle_exits, {})
        if #t.vehicle_exits == 0 and t.vehicle_exit then
            t.vehicle_exits = { t.vehicle_exit }
        end
        t.vehicle_exit = t.vehicle_exits[1] or t.vehicle_exit
        t.slots        = {}
        GarageTemplates[t.id] = t
    end

    local srows = MySQL.query.await('SELECT * FROM cm_house_garage_slots ORDER BY slot_index') or {}
    for _, s in ipairs(srows) do
        s.template_id = tonumber(s.template_id) or s.template_id
        s.slot_index  = tonumber(s.slot_index) or s.slot_index
        local g = GarageTemplates[s.template_id]
        if g then
            s.coords = jdec(s.coords)
            s.icon   = jdec(s.icon, nil)
            g.slots[s.slot_index] = s
        end
    end

    -- Capacity must equal the number of slots actually placed. If they ever
    -- disagree the slots win: they are physical, the number is just a claim.
    for _, g in pairs(GarageTemplates) do
        local n = 0
        for _ in pairs(g.slots) do n = n + 1 end
        if n ~= g.capacity then
            print(('[cm-house] ^3garage template "%s": capacity says %d but %d slots are placed. Using %d.^7')
                :format(g.label, g.capacity, n, n))
            g.capacity = n
            MySQL.update('UPDATE cm_house_garage_templates SET capacity = ? WHERE id = ?', { n, g.id })
        end
    end

    print(('[cm-house] %d interior templates, %d garage templates')
        :format(#irows, #grows))
end

-- ------------------------------------------------------------
--  Validation
-- ------------------------------------------------------------
local function validCoords(c, needHeading)
    if type(c) ~= 'table' then return false end
    if type(c.x) ~= 'number' or type(c.y) ~= 'number' or type(c.z) ~= 'number' then return false end
    if needHeading and type(c.h) ~= 'number' then return false end
    for _, k in ipairs({ 'x', 'y', 'z' }) do
        local v = c[k]
        if v ~= v or math.abs(v) > 10000.0 then return false end   -- NaN or off-map
    end
    return true
end
ValidCoords = validCoords


local function validCoordsList(list, needHeading, maxCount)
    local out = {}
    for _, c in ipairs(type(list) == 'table' and list or {}) do
        if validCoords(c, needHeading) then
            out[#out + 1] = c
            if maxCount and #out >= maxCount then break end
        end
    end
    return out
end

local function normalizeGarageExits(d)
    local cfg = Config.GarageTemplate or {}
    local exits = validCoordsList(d.vehicleExits or {}, true, tonumber(cfg.maxVehicleExits) or 8)
    if #exits == 0 and validCoords(d.vehicleExit, true) then exits[1] = d.vehicleExit end
    return exits
end

-- Rank-ready template ACL. Property creators can capture the layouts needed by
-- their wizard, while dedicated interior/garage ranks can manage only their
-- assigned template section without receiving full house-creation access.
local function canManageTemplate(src, kind)
    local scope = kind == 'garage' and 'garages' or 'interiors'
    return HasHouseStaffPermission(src, scope) == true
        or HasHouseStaffPermission(src, 'create') == true
end

local function normalizeTemplateSource(kind, ref)
    kind = tostring(kind or 'world'):lower()
    if kind ~= 'world' and kind ~= 'ipl' then
        return nil, nil, 'Source type must be world or IPL.'
    end

    ref = ref ~= nil and tostring(ref):gsub('^%s+', ''):gsub('%s+$', '') or nil
    if kind == 'ipl' and (not ref or ref == '') then
        return nil, nil, 'An IPL template requires the IPL name.'
    end
    if kind == 'world' then ref = nil end
    return kind, ref
end

-- ------------------------------------------------------------
--  Save an interior template
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:saveInteriorTemplate', function(src, d)
    if not canManageTemplate(src, 'interior') then return false, 'You cannot manage interior layouts.' end
    if type(d) ~= 'table' then return false, 'Malformed request.' end

    local label = tostring(d.label or ''):sub(1, 64)
    if label == '' then return false, 'Give the layout a name.' end

    -- The key is derived, not typed: the admin names the layout, and the
    -- signature is what makes it findable by the next property like it.
    local sig = tostring(d.signature or '')
    local key = (sig:gsub('|', '_') .. '_' .. label:lower():gsub('[^%w]', '_')):sub(1, 48)

    if not validCoords(d.entry, true) then return false, 'The entry point is missing.' end
    if not validCoords(d.exitPoint, true) then return false, 'The exit point is missing.' end

    -- There is no separate garage-door point any more. The single exit door
    -- offers both "Leave" and "Go to garage", so one coordinate serves both.

    local weaponStorages = {}
    for _, w in ipairs(d.weaponStorages or d.wardrobes or {}) do
        if validCoords(w, true) then weaponStorages[#weaponStorages + 1] = w end
    end

    -- This is a brand-new template, so stash metadata comes only from the
    -- submitted capture payload. Missing values receive safe defaults.
    local stashes = {}
    for _, s in ipairs(d.stashes or {}) do
        if validCoords(s, true) then
            stashes[#stashes + 1] = {
                x = s.x, y = s.y, z = s.z, h = s.h,
                label = tostring(s.label or (#stashes > 0 and ('Storage %d'):format(#stashes + 1) or 'Storage')):sub(1, 32),
                slots = math.max(1, math.min(100, tonumber(s.slots) or 30)),
            }
        end
    end

    -- Same signature + same name = the same layout. Let them rename instead
    -- of silently creating a duplicate.
    local dupe = MySQL.scalar.await(
        'SELECT id FROM cm_house_interior_templates WHERE signature = ? AND label = ?',
        { sig, label })
    if dupe then
        return false, ('A layout called "%s" already exists for this kind of property.'):format(label)
    end

    local sourceKind, sourceRef, sourceWhy = normalizeTemplateSource(d.sourceKind, d.sourceRef)
    if not sourceKind then return false, sourceWhy end

    local sql, params = BuildInsert('cm_house_interior_templates', {
        { 'key_name',      key },
        { 'label',         label },
        { 'signature',     sig },
        { 'source_kind',   sourceKind },
        { 'source_ref',    sourceRef },          -- nil -> column omitted
        { 'entry',         json.encode(d.entry) },
        { 'exit_point',    json.encode(d.exitPoint) },
        { 'wardrobes',     json.encode({}) },
        { 'weapon_storages', json.encode(weaponStorages) },
        { 'stashes',       json.encode(stashes) },
        { 'allowed_types', json.encode(d.allowedTypes or {}) },
        { 'created_by',    GetCid(src) },
    })
    local id = MySQL.insert.await(sql, params)
    if not id then return false, 'The database refused the insert.' end

    LoadTemplates()
    Audit(src, 'template_create', { kind = 'interior', id = id, key = key })

    return true, ('Template "%s" saved. %d weapon locker%s, %d general storage point%s.')
        :format(label, #weaponStorages, #weaponStorages == 1 and '' or 's',
                #stashes, #stashes == 1 and '' or 's'), id
end)

-- ------------------------------------------------------------
--  Save a garage template
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:saveGarageTemplate', function(src, d)
    if not canManageTemplate(src, 'garage') then return false, 'You cannot manage garage layouts.' end
    if type(d) ~= 'table' then return false, 'Malformed request.' end

    local label = tostring(d.label or ''):sub(1, 64)
    if label == '' then return false, 'Give the garage a name.' end
    if not validCoords(d.playerEntry, true) then return false, 'The player entry point is missing.' end

    local exits = normalizeGarageExits(d)
    if #exits == 0 then return false, 'Place at least one vehicle exit.' end

    local slots = validCoordsList(d.slots, true, tonumber(Config.GarageTemplate and Config.GarageTemplate.maxVehicleSlots) or 24)
    if #slots == 0 then
        return false, 'Place at least one vehicle slot -- a garage with no slots holds no cars.'
    end

    local key = (('g%d_'):format(#slots) .. label:lower():gsub('[^%w]', '_')):sub(1, 48)
    local dupe = MySQL.scalar.await(
        'SELECT id FROM cm_house_garage_templates WHERE capacity = ? AND label = ?',
        { #slots, label })
    if dupe then
        return false, ('A %d-car garage called "%s" already exists.'):format(#slots, label)
    end

    local sourceKind, sourceRef, sourceWhy = normalizeTemplateSource(d.sourceKind, d.sourceRef)
    if not sourceKind then return false, sourceWhy end

    local sql, params = BuildInsert('cm_house_garage_templates', {
        { 'key_name',     key },
        { 'label',        label },
        { 'source_kind',  sourceKind },
        { 'source_ref',   sourceRef },
        { 'player_entry', json.encode(d.playerEntry) },
        { 'vehicle_exit', json.encode(exits[1]) },
        { 'vehicle_exits', json.encode(exits) },
        { 'capacity',     #slots },
        { 'created_by',   GetCid(src) },
    })

    local tx = { { query = sql, values = params } }
    for i, slot in ipairs(slots) do
        local query
        local values
        if slot.icon ~= nil then
            query = [[
                INSERT INTO cm_house_garage_slots (template_id, slot_index, coords, icon)
                SELECT id, ?, ?, ?
                FROM cm_house_garage_templates
                WHERE key_name = ? AND version = 1
                LIMIT 1
            ]]
            values = { i, json.encode(slot), json.encode(slot.icon), key }
        else
            query = [[
                INSERT INTO cm_house_garage_slots (template_id, slot_index, coords)
                SELECT id, ?, ?
                FROM cm_house_garage_templates
                WHERE key_name = ? AND version = 1
                LIMIT 1
            ]]
            values = { i, json.encode(slot), key }
        end
        tx[#tx + 1] = { query = query, values = values }
    end

    local transactionOk = MySQL.transaction.await(tx)
    if not transactionOk then return false, 'The database refused the garage template transaction.' end

    local id = tonumber(MySQL.scalar.await(
        'SELECT id FROM cm_house_garage_templates WHERE key_name = ? AND version = 1 LIMIT 1', { key }))
    if not id then return false, 'The garage was committed but could not be reloaded.' end

    LoadTemplates()
    Audit(src, 'template_create', {
        kind = 'garage', id = id, key = key, slots = #slots, exits = #exits,
    })

    return true, ('Garage "%s" saved with %d slot%s and %d exit%s.')
        :format(label, #slots, #slots == 1 and '' or 's', #exits, #exits == 1 and '' or 's'), id
end)

-- ------------------------------------------------------------
--  Update (admin re-walk of an existing layout)
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:updateInteriorTemplate', function(src, id, d)
    if not canManageTemplate(src, 'interior') then return false, 'You cannot manage interior layouts.' end
    id = tonumber(id)
    local t = id and MySQL.single.await(
        'SELECT id, label, stashes, weapon_storages, wardrobes FROM cm_house_interior_templates WHERE id = ? LIMIT 1', { id })
    if not t then return false, 'That layout does not exist.' end
    if type(d) ~= 'table' then return false, 'Malformed request.' end

    if not validCoords(d.entry, true) then return false, 'The entry point is missing.' end
    if not validCoords(d.exitPoint, true) then return false, 'The exit point is missing.' end

    local weaponStorages = {}
    for _, w in ipairs(d.weaponStorages or d.wardrobes or {}) do
        if validCoords(w, true) then weaponStorages[#weaponStorages + 1] = w end
    end
    local existingStashes = jdec(t.stashes, {})
    local stashes = {}
    for index, s in ipairs(d.stashes or {}) do
        if validCoords(s, true) then
            local previous = type(existingStashes[index]) == 'table' and existingStashes[index] or {}
            stashes[#stashes + 1] = {
                x = s.x, y = s.y, z = s.z, h = s.h,
                -- Re-walking updates coordinates while keeping the original
                -- stash identity and capacity unless the admin explicitly
                -- supplied replacement values.
                label = tostring(s.label or previous.label or (#stashes > 0 and ('Storage %d'):format(#stashes + 1) or 'Storage')):sub(1, 32),
                slots = math.max(1, math.min(100, tonumber(s.slots) or tonumber(previous.slots) or 30)),
            }
        end
    end

    local affected = MySQL.update.await([[
        UPDATE cm_house_interior_templates
           SET entry = ?, exit_point = ?, wardrobes = ?, weapon_storages = ?, stashes = ?
         WHERE id = ?]], {
        json.encode(d.entry), json.encode(d.exitPoint),
        json.encode({}), json.encode(weaponStorages), json.encode(stashes), id,
    })
    if affected == nil then return false, 'The layout was not updated.' end

    LoadTemplates()
    Audit(src, 'template_update', { kind = 'interior', id = id })
    return true, ('Layout "%s" updated. Every property using it changed instantly.'):format(t.label)
end)

lib.callback.register('cm-house:server:updateGarageTemplate', function(src, id, d)
    if not canManageTemplate(src, 'garage') then return false, 'You cannot manage garage layouts.' end
    id = tonumber(id)
    local t = id and MySQL.single.await(
        'SELECT id, label, capacity FROM cm_house_garage_templates WHERE id = ? LIMIT 1', { id })
    if not t then return false, 'That garage does not exist.' end
    t.capacity = tonumber(t.capacity) or 0
    if type(d) ~= 'table' then return false, 'Malformed request.' end
    if not validCoords(d.playerEntry, true) then return false, 'The player entry point is missing.' end

    local exits = normalizeGarageExits(d)
    if #exits == 0 then return false, 'Place at least one vehicle exit.' end

    local slots = validCoordsList(d.slots, true, tonumber(Config.GarageTemplate and Config.GarageTemplate.maxVehicleSlots) or 24)
    if #slots == 0 then return false, 'Place at least one vehicle slot.' end

    if #slots ~= tonumber(t.capacity) and (tonumber(TemplateUsage('garage', id)) or 0) > 0 then
        return false, ('This garage is in use and must keep %d slots. You placed %d.')
            :format(tonumber(t.capacity), #slots)
    end

    local tx = {
        {
            query = [[
                UPDATE cm_house_garage_templates
                   SET player_entry = ?, vehicle_exit = ?, vehicle_exits = ?, capacity = ?
                 WHERE id = ?
            ]],
            values = {
                json.encode(d.playerEntry), json.encode(exits[1]), json.encode(exits), #slots, id,
            },
        },
        {
            query = 'DELETE FROM cm_house_garage_slots WHERE template_id = ?',
            values = { id },
        },
    }

    for i, slot in ipairs(slots) do
        local ssql, sparams = BuildInsert('cm_house_garage_slots', {
            { 'template_id', id },
            { 'slot_index',  i },
            { 'coords',      json.encode(slot) },
            { 'icon',        SqlJson(slot.icon) },
        })
        tx[#tx + 1] = { query = ssql, values = sparams }
    end

    local transactionOk = MySQL.transaction.await(tx)
    if not transactionOk then
        return false, 'The garage update failed. The old template was kept unchanged.'
    end

    LoadTemplates()
    Audit(src, 'template_update', {
        kind = 'garage', id = id, slots = #slots, exits = #exits,
    })
    return true, ('Garage "%s" updated with %d slot%s and %d exit%s.')
        :format(t.label, #slots, #slots == 1 and '' or 's', #exits, #exits == 1 and '' or 's')
end)

-- ------------------------------------------------------------
--  Read
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:getTemplates', function(src)
    local interiors, garages = {}, {}

    for id, t in pairs(InteriorTemplates) do
        interiors[#interiors + 1] = {
            id = id, key = t.key_name, label = t.label,
            weaponStorages = #(t.weapon_storages or {}), wardrobes = #(t.weapon_storages or {}), stashes = #t.stashes,
            allowedTypes = t.allowed_types,
        }
    end
    table.sort(interiors, function(a, b) return a.label < b.label end)

    for id, t in pairs(GarageTemplates) do
        garages[#garages + 1] = {
            id = id, key = t.key_name, label = t.label, capacity = t.capacity,
            exits = #(t.vehicle_exits or {}),
        }
    end
    table.sort(garages, function(a, b) return a.capacity < b.capacity end)

    return { interiors = interiors, garages = garages }
end)

--- How many properties use a template. Shown before an edit, and it blocks a
--- delete: pulling a template out from under a live house strands its owner.
function TemplateUsage(kind, id)
    local col = kind == 'garage' and 'garage_template_id' or 'interior_template_id'
    return MySQL.scalar.await(
        ('SELECT COUNT(*) FROM cm_houses WHERE %s = ?'):format(col), { id }) or 0
end

lib.callback.register('cm-house:server:deleteTemplate', function(src, kind, id)
    if kind ~= 'interior' and kind ~= 'garage' then return false, 'Unknown layout kind.' end
    if not canManageTemplate(src, kind) then return false, 'You cannot manage that layout type.' end

    local used = TemplateUsage(kind, id)
    if used > 0 then
        return false, ('%d propert%s still use this template. Used templates cannot be disabled or deleted.')
            :format(used, used == 1 and 'y uses' or 'ies use')
    end

    local tbl = kind == 'garage' and 'cm_house_garage_templates' or 'cm_house_interior_templates'
    MySQL.update.await(('UPDATE %s SET enabled = 0 WHERE id = ?'):format(tbl), { id })

    LoadTemplates()
    Audit(src, 'template_disable', { kind = kind, id = id })
    return true, 'Template disabled.'
end)

exports('GetInteriorTemplate', function(id) return InteriorTemplates[id] end)
exports('GetGarageTemplate',   function(id) return GarageTemplates[id] end)
