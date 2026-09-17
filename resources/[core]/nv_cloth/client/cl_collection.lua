-- Stable clothing identity via GTA ped collections.
--
-- A drawable's global index is the position of its garment in the concatenated
-- list of every loaded apparel pack, so enabling, disabling or reordering any
-- pack renumbers every garment after it. Collections address a garment as
-- (collection name, index within that collection) instead: the collection is the
-- pack's <fullDlcName> and the local index is the number baked into the file
-- name (mp_m_freemode_01_test4^jbib_057_u.ydd -> collection
-- "mp_m_freemode_01_test4", local 57). Neither changes when a different pack is
-- added or removed, so that pair is what the catalog and inventory store; the
-- global index is resolved from it at equip time.
--
-- Base game garments report collection "" and local index == global index, so
-- the same pair works for vanilla clothing with no special case.

local hasCollections =
    GetPedCollectionNameFromDrawable ~= nil and
    GetPedCollectionLocalIndexFromDrawable ~= nil and
    GetPedDrawableGlobalIndexFromCollection ~= nil and
    GetPedCollectionNameFromProp ~= nil and
    GetPedCollectionLocalIndexFromProp ~= nil and
    GetPedPropGlobalIndexFromCollection ~= nil

local function isProp(componentType)
    return tostring(componentType or 'component'):lower() == 'prop'
end

-- Reads the stable identity of whatever currently sits at `global` on this ped.
-- Returns nil when collections are unavailable so callers keep using the raw
-- index rather than writing a half-populated row.
local function readCollection(ped, componentType, index, global)
    if not hasCollections then return nil end

    ped = ped or PlayerPedId()
    index = tonumber(index)
    global = tonumber(global)
    if not index or not global or global < 0 then return nil end

    local ok, collection, localIndex = pcall(function()
        if isProp(componentType) then
            return GetPedCollectionNameFromProp(ped, index, global),
                   GetPedCollectionLocalIndexFromProp(ped, index, global)
        end
        return GetPedCollectionNameFromDrawable(ped, index, global),
               GetPedCollectionLocalIndexFromDrawable(ped, index, global)
    end)

    if not ok then return nil end
    localIndex = tonumber(localIndex)
    if not localIndex or localIndex < 0 then return nil end

    -- "" is the real, valid collection name for base game clothing.
    return tostring(collection or ''), localIndex
end

-- Turns a stored (collection, localIndex) back into the global index this
-- client's loaded packs are currently using. `fallback` is the drawable index
-- recorded when the item was made: it is only correct while the pack set is
-- unchanged, so it is used strictly as a last resort.
local function resolveGlobal(ped, componentType, index, collection, localIndex, fallback)
    fallback = tonumber(fallback)
    localIndex = tonumber(localIndex)
    if not hasCollections or localIndex == nil or collection == nil then
        return fallback
    end

    ped = ped or PlayerPedId()
    index = tonumber(index)
    if not index then return fallback end

    local ok, global = pcall(function()
        if isProp(componentType) then
            return GetPedPropGlobalIndexFromCollection(ped, index, collection, localIndex)
        end
        return GetPedDrawableGlobalIndexFromCollection(ped, index, collection, localIndex)
    end)

    global = ok and tonumber(global) or nil
    -- -1 means this client has no pack providing that collection/local pair --
    -- the pack was removed, or never installed. Equipping `fallback` there would
    -- silently put an unrelated garment on the ped, which is the exact bug this
    -- module exists to stop, so report the miss instead.
    if not global or global < 0 then
        if collection ~= '' then return nil end
        return fallback
    end

    return global
end

NvClothCollection = {
    available = hasCollections,
    read = readCollection,
    resolve = resolveGlobal,
}

exports('ReadClothingCollection', function(componentType, index, global, ped)
    return readCollection(ped, componentType, index, global)
end)

exports('ResolveClothingDrawable', function(componentType, index, collection, localIndex, fallback, ped)
    return resolveGlobal(ped, componentType, index, collection, localIndex, fallback)
end)

exports('ClothingCollectionsAvailable', function()
    return hasCollections
end)

CreateThread(function()
    if not hasCollections then
        print('[nv_cloth] ped collection natives unavailable on this build; clothing identity falls back to raw drawable indexes and will drift when apparel packs change.')
    end
end)
