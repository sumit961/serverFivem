-- cm-gunstore/shared/util.lua
-- Small shared helper library. Everything here is exposed on a single `CMGun`
-- table so we do not leak dozens of globals into the shared script environment.
-- (Global lookups in Lua are slower than locals/table fields and pollute the
-- namespace of every other resource that shares this environment.)

CMGun = CMGun or {}

-- Normalize a raw string into a safe item name: lowercase, underscores, no
-- weird characters, capped length. Used on BOTH sides so the client and server
-- always agree on the canonical name of an item.
function CMGun.normalizeItemName(value)
    value = tostring(value or ''):lower():gsub('%s+', '_'):gsub('[^a-z0-9_%-%.]', '_'):gsub('_+', '_')
    value = value:gsub('^_+', ''):gsub('_+$', '')
    return value:sub(1, 80)
end

-- Coerce many truthy representations into 0/1 for tinyint columns / checkboxes.
function CMGun.boolInt(value)
    if value == true or value == 1 or value == '1' or value == 'true' or value == 'yes' or value == 'on' then
        return 1
    end
    return 0
end

-- Clamp+floor a numeric value with a sane fallback.
function CMGun.toInt(value, fallback, min, max)
    local n = math.floor(tonumber(value) or tonumber(fallback) or 0)
    if min ~= nil and n < min then n = min end
    if max ~= nil and n > max then n = max end
    return n
end

-- Friendly group label used by the store UI. Kept here so client and any
-- server-side preview share exactly one mapping.
CMGun.GroupLabels = {
    pistol     = 'Pistols',
    smg        = 'Submachine Guns',
    rifle      = 'Assault Rifles',
    shotgun    = 'Shotguns',
    sniper     = 'Sniper Rifles',
    machinegun = 'Machine Guns',
    mg         = 'Machine Guns',
    armor      = 'Armor',
    ammo       = 'Ammunition',
}

function CMGun.groupLabel(key)
    key = tostring(key or ''):lower()
    return CMGun.GroupLabels[key] or 'Pistols'
end

return CMGun
