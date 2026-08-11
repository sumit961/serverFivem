-- ============================================================
--  cm-house | sv_access.lua   |  PHASE 1
--
--  ONE access check. Spec 16.12:
--    "Use a centralized CanAccessProperty action check instead of scattering
--     owner-only conditions throughout client/server files."
--
--  Every gate in this resource goes through CanAccessProperty(cid, houseId,
--  action). cm-family hooks in HERE through an explicit permission import,
--  rather than requiring every call site to be rewritten.
--
--  A visible client button is never authorization. The client asks; this decides.
-- ============================================================

-- Named permission keys, exactly as the spec lists them (16.4).
ACTIONS = {
    HOUSE_ENTER         = 'house.enter',
    HOUSE_LOCK          = 'house.lock',
    HOUSE_MANAGE_ACCESS = 'house.manage_access',
    HOUSE_SET_SPAWN     = 'house.set_spawn',
    HOUSE_SELL          = 'house.sell',
    HOUSE_VIEW_LOGS     = 'house.view_logs',

    WEAPON_STORAGE_USE      = 'weapon_storage.use',
    WEAPON_STORAGE_DEPOSIT  = 'weapon_storage.deposit',
    WEAPON_STORAGE_WITHDRAW = 'weapon_storage.withdraw',
    -- Backward-compatible constant; old integrations resolve to the secure locker.
    WARDROBE_USE            = 'weapon_storage.use',
    STORAGE_USE         = 'storage.use',

    GARAGE_ENTER        = 'garage.enter',
    GARAGE_VIEW         = 'garage.view',
    GARAGE_SPAWN_OWN    = 'garage.spawn_personal',
    GARAGE_SPAWN_FAMILY = 'garage.spawn_family',
    GARAGE_MANAGE_SLOTS = 'garage.manage_slots',

    HELIPAD_USE         = 'helipad.use',
}

-- Actions only the legal owner may ever take. No rank, no key, no family.
local OWNER_ONLY = {
    ['house.sell']           = true,
    ['house.manage_access']  = true,
}

-- What a plain key gets you. A key is not family membership: it opens the
-- door and lets you park your own car. It does not open the wardrobe.
local KEY_GRANTS = {
    ['house.enter']           = true,
    ['house.lock']            = true,
    ['garage.enter']          = true,
    ['garage.view']           = true,
    ['garage.spawn_personal'] = true,
}

-- A guest can walk in. Nothing else.
local GUEST_GRANTS = {
    ['house.enter'] = true,
}

-- ------------------------------------------------------------
--  Access records
-- ------------------------------------------------------------
Access = {}   -- [cid] = { [houseId] = { kind = 'key'|'guest', expires = ts|nil } }

function LoadAccess()
    Access = {}
    local rows = MySQL.query.await(
        'SELECT * FROM cm_house_access WHERE expires_at IS NULL OR expires_at > NOW()') or {}
    for _, r in ipairs(rows) do
        Access[r.cid] = Access[r.cid] or {}
        Access[r.cid][r.house_id] = { kind = r.kind, expires = r.expires_at }
    end
    print(('[cm-house] %d access grants'):format(#rows))
end

local function accessKind(cid, houseId)
    cid = tonumber(cid) or cid
    houseId = tonumber(houseId)
    local set = Access[cid] or Access[tostring(cid)]
    if not set then return nil end
    local rec = set[houseId] or set[tostring(houseId)]
    if not rec then return nil end
    return rec.kind
end

-- ------------------------------------------------------------
--  Family hook.
--
--  cm-house remains the authority for the property. cm-family supplies only
--  the membership/rank decision through an import. If cm-family is missing,
--  stopped, errors, or returns anything other than true, access fails closed.
-- ------------------------------------------------------------
local FAMILY_PERMISSION_MAP = {
    ['house.enter'] = 'door.enter',
    ['house.lock'] = 'door.lock',
    ['house.manage_access'] = 'keys.grant',
    ['house.set_spawn'] = 'door.enter',
    ['house.view_logs'] = 'house.view_logs',
    ['weapon_storage.use'] = 'weapon_storage.access',
    ['weapon_storage.deposit'] = 'weapon_storage.deposit',
    ['weapon_storage.withdraw'] = 'weapon_storage.withdraw',
    ['wardrobe.use'] = 'weapon_storage.access',
    ['storage.use'] = 'storage.access',
    ['garage.enter'] = 'garage.access',
    ['garage.view'] = 'garage.access',
    ['garage.spawn_personal'] = 'garage.store',
    ['garage.spawn_family'] = 'garage.take',
    ['garage.manage_slots'] = 'garage.manage_shared',
    ['helipad.use'] = 'helipad.use',
}


local BASIC_FAMILY_MEMBER_PERMISSIONS = {
    ['door.enter'] = true,
}

local function committedFamilyMembershipAllows(cid, house, permission)
    if not house or not house.id or not house.family_id then return false end
    if BASIC_FAMILY_MEMBER_PERMISSIONS[tostring(permission or '')] ~= true then return false end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT 1 AS allowed
            FROM cm_family_members member
            INNER JOIN cm_families family
                ON family.id = member.family_id
            INNER JOIN cm_houses property
                ON property.id = family.house_id
               AND property.family_id = family.id
            WHERE member.character_id = ?
              AND family.id = ?
              AND property.id = ?
            LIMIT 1
        ]], { tostring(cid), tonumber(house.family_id), tonumber(house.id) })
    end)
    return ok and row ~= nil
end

function GetFamilyPermissionForAction(action)
    action = tostring(action or '')
    return FAMILY_PERMISSION_MAP[action] or action
end
exports('GetFamilyPermissionForAction', GetFamilyPermissionForAction)

local function familyResource()
    return tostring(Config.Family and Config.Family.resource or 'cm-family')
end

local function familyAllows(cid, house, action)
    if not (Config.Family and Config.Family.enabled == true) then
        return false, 'Family-house access is disabled.'
    end
    if not house or not house.family_id then return false, 'This is not a family property.' end

    local resource = familyResource()
    if GetResourceState(resource) ~= 'started' then return false, 'The family service is unavailable.' end

    local permission = GetFamilyPermissionForAction(action)
    local exportName = tostring(Config.Family.permissionExport or 'HasHousePermission')

    -- Preferred import. Signature:
    -- HasHousePermission(characterId, familyId, houseId, permissionKey, internalAction)
    local ok, allowed = pcall(function()
        return exports[resource][exportName](
            cid, house.family_id, house.id, permission, action)
    end)
    if ok and allowed == true then return true end

    -- Compatibility import for an older cm-family implementation.
    local legacy = tostring(Config.Family.legacyPermissionExport or 'HasPermission')
    local okLegacy, legacyAllowed = pcall(function()
        return exports[resource][legacy](cid, house.family_id, permission)
    end)
    if okLegacy and legacyAllowed == true then return true end

    -- Cache/export compatibility must not lock a committed member out of basic
    -- family-house use. This fallback verifies the member, family and linked
    -- property together in the database; it never grants management powers.
    if committedFamilyMembershipAllows(cid, house, permission) then
        return true
    end

    -- v1.1.6+ diagnostic import. It does not authorize; it only turns a generic
    -- denial into a useful message for the player/server log.
    local diagnosticReason
    local okDiagnostic, diagnosticAllowed, reason = pcall(function()
        return exports[resource]:GetHousePermissionDecision(
            cid, house.family_id, house.id, permission, action)
    end)
    if okDiagnostic and diagnosticAllowed ~= true then diagnosticReason = reason end

    if not ok then return false, 'The family permission check failed safely.' end
    if diagnosticReason and tostring(diagnosticReason):match('rank_missing_permission:') then
        return false, ('Your family rank does not have %s.'):format(permission)
    end
    if diagnosticReason == 'not_the_active_family_house' then
        return false, 'This property is not linked as your family house.'
    end
    if diagnosticReason == 'not_a_family_member' then
        return false, 'Your family membership is not active.'
    end
    return false, 'Your family rank does not allow that.'
end

function CanFamilyAccessProperty(cid, houseId, action)
    cid = tonumber(cid) or cid
    houseId = tonumber(houseId)
    local house = houseId and Houses[houseId]
    if not house then return false, 'That property does not exist.' end
    if not house.family_id then return false, 'This is not a family property.' end
    local allowed, reason = familyAllows(cid, house, tostring(action or ACTIONS.HOUSE_ENTER))
    if allowed then return true end
    return false, reason or 'Your family rank does not allow that.'
end
exports('CanFamilyAccessProperty', CanFamilyAccessProperty)

-- ------------------------------------------------------------
--  THE gate
-- ------------------------------------------------------------
--- @param cid     integer  character id
--- @param houseId integer
--- @param action  string   one of ACTIONS
--- @param auditOverride boolean|nil  false for read-only menu capability checks
--- @return boolean allowed, string|nil reason
function CanAccessProperty(cid, houseId, action, auditOverride)
    cid = tonumber(cid) or cid
    houseId = tonumber(houseId)
    action = tostring(action or '')
    if not cid then return false, 'Your character is not loaded.' end
    if not houseId then return false, 'That property does not exist.' end

    local house = Houses[houseId]
    if not house then return false, 'That property does not exist.' end

    -- Draft properties are invisible to players.
    if house.status ~= 'published' and not house.__adminPreview then
        return false, 'That property is not available.'
    end

    local isOwner = house.owner_cid ~= nil and tonumber(house.owner_cid) == tonumber(cid)

    if OWNER_ONLY[action] then
        if isOwner then return true end
        return false, 'Only the owner can do that.'
    end

    if isOwner then return true end

    -- Family access is the only non-owner gameplay path. It is imported from
    -- cm-family and fails closed when that resource is unavailable.
    local familyAllowed, familyReason = familyAllows(cid, house, action)
    if familyAllowed then return true end

    -- Legacy key/guest records remain available for future invitation systems,
    -- but they do not silently open garages, wardrobes or storage by default.
    local kind = accessKind(cid, houseId)
    if Config.Access and Config.Access.allowKeys == true
        and kind == 'key' and KEY_GRANTS[action] then return true end
    if Config.Access and Config.Access.allowGuests == true
        and kind == 'guest' and GUEST_GRANTS[action] then return true end

    -- Staff use the protected admin/recovery APIs. They are not treated as the
    -- owner during ordinary gameplay unless this is deliberately enabled.
    local src = GetSrcByCid(cid)
    if Config.Access and Config.Access.allowStaffGameplayOverride == true
        and src and IsRealStaff(src) then
        if auditOverride ~= false then
            Audit(src, 'staff_gameplay_override', { houseId = houseId, action = action })
        end
        return true
    end

    return false, house.owner_cid == nil
        and 'This property must be purchased before it can be entered.'
        or (familyReason or 'Only the owner or an authorized family member can use this property.')
end
exports('CanAccessProperty', function(cid, houseId, action)
    return CanAccessProperty(cid, houseId, action)
end)

--- Convenience for a source rather than a cid.
function SrcCan(src, houseId, action)
    return CanAccessProperty(GetCid(src), houseId, action)
end

-- ------------------------------------------------------------
--  Grants
-- ------------------------------------------------------------
function GrantAccess(houseId, cid, kind, byCid, expiresAt)
    MySQL.insert.await([[
        INSERT INTO cm_house_access (house_id, cid, kind, granted_by, expires_at)
        VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE granted_by = VALUES(granted_by), expires_at = VALUES(expires_at)
    ]], { houseId, cid, kind, SqlNull(byCid), SqlNull(expiresAt) })

    Access[cid] = Access[cid] or {}
    Access[cid][houseId] = { kind = kind, expires = expiresAt }

    LogHouse(houseId, nil, byCid, 'access_grant', { to = cid, kind = kind })
end

function RevokeAccess(houseId, cid, byCid)
    MySQL.query.await('DELETE FROM cm_house_access WHERE house_id = ? AND cid = ?', { houseId, cid })
    if Access[cid] then Access[cid][houseId] = nil end
    LogHouse(houseId, nil, byCid, 'access_revoke', { from = cid })
end

exports('IsFamilyHouse', function(houseId)
    local h = Houses[tonumber(houseId)]
    return h ~= nil and h.family_id ~= nil
end)

-- ------------------------------------------------------------
--  Garage capacity
--  The DB trigger (004) is the hard floor. This is the friendly one: it gives
--  a readable error instead of an SQL exception, and it works even if the
--  trigger was never installed.
-- ------------------------------------------------------------
function GarageCapacity(houseId)
    houseId = tonumber(houseId)
    local h = houseId and Houses[houseId]
    if not h or not h.garage_template_id then return 0 end
    local g = GarageTemplates[h.garage_template_id]
    return g and g.capacity or 0
end

function ValidSlot(houseId, slotIndex)
    slotIndex = tonumber(slotIndex)
    if not slotIndex then return false, 'That slot does not exist.' end

    local cap = GarageCapacity(houseId)
    if cap == 0 then return false, 'This property has no garage.' end

    if slotIndex < 1 or slotIndex > cap then
        return false, ('This garage has %d slot%s.'):format(cap, cap == 1 and '' or 's')
    end
    return true
end

exports('GetGarageCapacity', GarageCapacity)
