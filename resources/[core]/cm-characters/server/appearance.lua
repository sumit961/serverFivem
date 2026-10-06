-- cm-characters/server/appearance.lua


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

-- ClockMate clothing inventory starter support
local CM_NAKED_BASE = {
    male = {
        arms = 15, arms_2 = 0,
        pants_1 = 21, pants_2 = 0,
        shoes_1 = 34, shoes_2 = 0,
        tshirt_1 = 15, tshirt_2 = 0,
        torso_1 = 15, torso_2 = 0,
    },
    female = {
        arms = 15, arms_2 = 0,
        pants_1 = 15, pants_2 = 0,
        shoes_1 = 35, shoes_2 = 0,
        tshirt_1 = 14, tshirt_2 = 0,
        torso_1 = 15, torso_2 = 0,
    }
}

local function cmIsFemaleAppearance(appearance, char)
    if char and char.gender then
        local g = tostring(char.gender):lower()
        if g == 'female' or g == 'f' or g == '1' then return true end
        if g == 'male' or g == 'm' or g == '0' then return false end
    end
    local sex = appearance and appearance.sex
    if sex == 'female' or sex == 'f' or sex == 1 or sex == '1' then return true end
    if sex == 'male' or sex == 'm' or sex == 0 or sex == '0' then return false end
    return false
end

local function cmCopyTable(value)
    if type(value) ~= 'table' then return {} end
    local out = {}
    for k, v in pairs(value) do
        if type(v) == 'table' then
            out[k] = cmCopyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

-- ═══════════════════════════════════════════════════════════════════════
-- Appearance sanitization boundary.
--
-- Before this fix, appearanceData from the NUI/client was persisted almost
-- verbatim: saveCurrentAppearance did `for key, value in pairs(appearanceData)
-- do merged[key] = value end` (any key, any type, straight into the row that
-- gets json.encode'd), and saveAppearance's non-barber path did the same via
-- a raw cmCopyTable. A client could submit non-numeric strings, oversized
-- numbers, nested junk tables, or unknown keys and have them persisted as
-- the character's permanent appearance_json.
--
-- This is the ONE place appearance data is whitelisted/clamped before it can
-- reach persistence. Every known appearance field (see client/appearance.lua
-- InitSkinData/GetComponentData and client/main.lua DefaultSkin — this list
-- is the union of both) is range-checked; anything not listed here is
-- silently dropped rather than persisted. -1 and 255 are kept as valid
-- sentinels ("no prop"/"no overlay") because existing apply code checks for
-- them explicitly (e.g. `b1 == 255`, `_ears < 0`).
-- ═══════════════════════════════════════════════════════════════════════
local CM_APPEARANCE_FIELD_RANGES = {
    -- Head blend parents. Verified against client/appearance.lua GetMaxVals(),
    -- which queries this live from the actual ped model — mom max is 45, dad
    -- max is 44 (asymmetric on purpose, not a typo). No -1 "none" sentinel is
    -- used for these; InitSkinData defaults them to 21/0, never -1.
    mom = { 0, 45 }, dad = { 0, 44 },
    face_md_weight = { 0, 100 }, skin_md_weight = { 0, 100 },

    -- Face features. PHASE 4B CORRECTION: these were previously clamped to
    -- {-100, 100} on the assumption of a native -1.0..1.0 range stored *10.
    -- client/appearance.lua's GetMaxVals() — which queries the live ped
    -- natives — shows the actual valid range this codebase uses is 0-10
    -- (unidirectional, matching InitSkinData's default of 0 for every one of
    -- these fields), i.e. native 0.0..1.0 after the /10.0 in apply.lua. The
    -- old range was 10x too permissive and wrongly allowed negative values.
    nose_1 = { 0, 10 }, nose_2 = { 0, 10 }, nose_3 = { 0, 10 },
    nose_4 = { 0, 10 }, nose_5 = { 0, 10 }, nose_6 = { 0, 10 },
    cheeks_1 = { 0, 10 }, cheeks_2 = { 0, 10 }, cheeks_3 = { 0, 10 },
    lip_thickness = { 0, 10 },
    jaw_1 = { 0, 10 }, jaw_2 = { 0, 10 },
    chin_1 = { 0, 10 }, chin_2 = { 0, 10 }, chin_3 = { 0, 10 }, chin_4 = { 0, 10 },
    neck_thickness = { 0, 10 },
    eyebrows_5 = { 0, 10 }, eyebrows_6 = { 0, 10 },

    -- Overlay style indices. These are deliberately generous (-1..255) rather
    -- than the exact per-model count: GetMaxVals() computes the true ceiling
    -- at runtime via GetPedHeadOverlayNum(n), which differs between the male
    -- and female freemode models and cannot be hardcoded exactly here without
    -- risking rejecting a legitimate value on the model this ceiling was NOT
    -- measured against. Every real overlay count for these categories is
    -- well under 100 (GTA5 freemode overlays top out around 70-80 for the
    -- largest, makeup), so 255 never lets a genuinely out-of-range/garbage
    -- value through while never wrongly clamping a real one — see "Do not
    -- corrupt valid legacy characters." 255 doubles as the existing apply
    -- code's own "none" sentinel (e.g. `b1 == 255`).
    age_1 = { -1, 255 }, blemishes_1 = { -1, 255 }, makeup_1 = { -1, 255 },
    blush_1 = { -1, 255 }, complexion_1 = { -1, 255 }, sun_1 = { -1, 255 },
    lipstick_1 = { -1, 255 }, moles_1 = { -1, 255 }, beard_1 = { -1, 255 },
    chest_1 = { -1, 255 }, eyebrows_1 = { -1, 255 },
    -- Overlay opacity (native 0.0..1.0, stored *10 here)
    age_2 = { 0, 10 }, blemishes_2 = { 0, 10 }, makeup_2 = { 0, 10 },
    blush_2 = { 0, 10 }, complexion_2 = { 0, 10 }, sun_2 = { 0, 10 },
    lipstick_2 = { 0, 10 }, moles_2 = { 0, 10 }, beard_2 = { 0, 10 },
    chest_2 = { 0, 10 }, eyebrows_2 = { 0, 10 },
    -- Overlay colors (GTA overlay color palette)
    makeup_3 = { 0, 63 }, makeup_4 = { 0, 63 },
    lipstick_3 = { 0, 63 }, lipstick_4 = { 0, 63 },
    blush_3 = { 0, 63 }, beard_3 = { 0, 63 }, beard_4 = { 0, 63 },
    chest_3 = { 0, 63 }, eyebrows_3 = { 0, 63 }, eyebrows_4 = { 0, 63 },

    eye_color = { 0, 31 },

    -- Hair
    hair_1 = { 0, 255 }, hair_2 = { 0, 255 },
    hair_color_1 = { 0, 63 }, hair_color_2 = { 0, 63 },

    -- Props (-1 = none)
    ears_1 = { -1, 255 }, ears_2 = { 0, 255 },
    helmet_1 = { -1, 255 }, helmet_2 = { 0, 255 },
    glasses_1 = { -1, 255 }, glasses_2 = { 0, 255 },
    watches_1 = { -1, 255 }, watches_2 = { 0, 255 },
    bracelets_1 = { -1, 255 }, bracelets_2 = { 0, 255 },

    -- Clothing components (torso/pants/shoes/tshirt/arms are overwritten by
    -- cmMakeNakedAppearance below regardless, but are still range-checked
    -- here since barber mode and legacy readers may see this table first)
    tshirt_1 = { -1, 255 }, tshirt_2 = { 0, 255 },
    torso_1 = { -1, 255 }, torso_2 = { 0, 255 },
    arms = { -1, 255 }, arms_2 = { 0, 255 },
    decals_1 = { -1, 255 }, decals_2 = { 0, 255 },
    pants_1 = { -1, 255 }, pants_2 = { 0, 255 },
    shoes_1 = { -1, 255 }, shoes_2 = { 0, 255 },
    mask_1 = { -1, 255 }, mask_2 = { 0, 255 },
    bproof_1 = { -1, 255 }, bproof_2 = { 0, 255 },
    chain_1 = { -1, 255 }, chain_2 = { 0, 255 },
    bags_1 = { -1, 255 }, bags_2 = { 0, 255 },

    -- Legacy/unused-by-ApplySkin fields kept for forward compatibility —
    -- documented but dead per the appearance-system audit, never deleted
    -- silently (see AGENTS.md: don't destructively alter stored data).
    -- GetMaxVals() confirms eye_squint = 10 (same 0-10 family as the face
    -- feature fields above), even though nothing currently applies it.
    eye_squint = { 0, 10 },
    bodyb_1 = { -1, 255 }, bodyb_2 = { 0, 10 }, bodyb_3 = { -1, 255 }, bodyb_4 = { 0, 10 },
}

local function cmSanitizeAppearance(raw)
    raw = type(raw) == 'table' and raw or {}
    local clean = {}

    -- sex is handled separately: coerce to a strict 0/1, never trust a raw
    -- string/number straight through. Only emitted when the caller actually
    -- sent it — saveCurrentAppearance does a PARTIAL merge onto the existing
    -- saved appearance, so unconditionally defaulting sex to 0/male here
    -- would silently flip gender on every partial update that omits it.
    -- cmMakeNakedAppearance/cmIsFemaleAppearance re-derive this authoritatively
    -- from the character record for the full-save path regardless.
    if raw.sex ~= nil then
        local sexRaw = raw.sex
        if sexRaw == 1 or sexRaw == '1' or sexRaw == 'female' or sexRaw == 'f' then
            clean.sex = 1
        else
            clean.sex = 0
        end
    end

    for field, range in pairs(CM_APPEARANCE_FIELD_RANGES) do
        local value = tonumber(raw[field])
        if value ~= nil then
            value = math.floor(value + 0.5)
            if value < range[1] then value = range[1] end
            if value > range[2] then value = range[2] end
            clean[field] = value
        end
    end

    return clean
end

local function cmItemsCall(method, ...)
    if GetResourceState('cm-items') ~= 'started' then return nil end
    local args = { ... }

    local ok, result, extra = pcall(function()
        return exports['cm-items'][method](table.unpack(args))
    end)
    if ok and result ~= nil then return result, extra end

    ok, result, extra = pcall(function()
        return exports['cm-items'][method](exports['cm-items'], table.unpack(args))
    end)
    if ok and result ~= nil then return result, extra end

    return nil
end

local function cmFallbackClothingImage(gender, componentType, componentIndex, drawableId)
    gender = gender == 'female' and 'female' or 'male'
    local propPrefix = componentType == 'prop' and 'prop_' or ''
    local drawable = tonumber(drawableId)
    if not drawable or drawable < 0 then return 'nui://cm-items/ui/images/clothing.png' end
    return ('nui://cm-items/ui/images/clothing/%s_%s%s_%s.png'):format(gender, propPrefix, tostring(componentIndex), tostring(drawable))
end

local function cmBuildStarterClothingMeta(category, raw, opts)
    raw = type(raw) == 'table' and raw or {}
    opts = type(opts) == 'table' and opts or {}

    local built = cmItemsCall('BuildClothingMetadata', category, raw, opts)
    if type(built) == 'table' then
        built.equipped = true
        built.itemType = built.itemType or 'clothing'
        built.rarity = built.rarity or 'normal'
        built.label = built.label or opts.label
        return built
    end

    local component = category == 'torso' and 11 or category == 'shoes' and 6 or 4
    local meta = {
        categoryType = category,
        componentType = 'component',
        componentIndex = component,
        drawableId = tonumber(raw.drawableId) or 0,
        textureId = tonumber(raw.textureId) or 0,
        gender = opts.gender or 'male',
        label = opts.label or ('Starter ' .. category),
        description = opts.description or 'Starter clothing item',
        itemType = 'clothing',
        rarity = 'normal',
        equipped = true,
    }
    meta.image = cmFallbackClothingImage(meta.gender, meta.componentType, meta.componentIndex, meta.drawableId)
    meta.icon = meta.image

    if category == 'torso' then
        meta.arms = tonumber(raw.arms)
        meta.armsTexture = tonumber(raw.armsTexture) or 0
        meta.undershirt = tonumber(raw.undershirt)
        meta.undershirtTexture = tonumber(raw.undershirtTexture) or 0
    end

    return meta
end

local function cmGiveStarterClothes(src, appearance, char)
    if GetResourceState('cm-inventory') ~= 'started' then
        print('[CM-CHARACTERS] cm-inventory not started; starter clothes were not given.')
        return nil
    end

    appearance = type(appearance) == 'table' and appearance or {}
    local gender = cmIsFemaleAppearance(appearance, char) and 'female' or 'male'
    local naked = CM_NAKED_BASE[gender]

    -- Build starter clothing metadata through cm-items so image/metadata logic is shared
    -- by character creator, nv_cloth shop, and inventory.
    local torsoMeta = cmBuildStarterClothingMeta('torso', {
        drawableId = tonumber(appearance.torso_1) or naked.torso_1,
        textureId = tonumber(appearance.torso_2) or 0,
        gender = gender,
        arms = tonumber(appearance.arms) or naked.arms,
        armsTexture = tonumber(appearance.arms_2) or 0,
        undershirt = tonumber(appearance.tshirt_1) or naked.tshirt_1,
        undershirtTexture = tonumber(appearance.tshirt_2) or 0,
    }, {
        gender = gender,
        label = 'Starter Top',
        description = 'Clothing selected during character creation.',
    })

    local pantsMeta = cmBuildStarterClothingMeta('pants', {
        drawableId = tonumber(appearance.pants_1) or naked.pants_1,
        textureId = tonumber(appearance.pants_2) or 0,
        gender = gender,
    }, {
        gender = gender,
        label = 'Starter Pants',
        description = 'Clothing selected during character creation.',
    })

    local shoesMeta = cmBuildStarterClothingMeta('shoes', {
        drawableId = tonumber(appearance.shoes_1) or naked.shoes_1,
        textureId = tonumber(appearance.shoes_2) or 0,
        gender = gender,
    }, {
        gender = gender,
        label = 'Starter Shoes',
        description = 'Clothing selected during character creation.',
    })

    -- Sixth argument is the preferred inventory slot. This makes starter clothes appear equipped,
    -- not just sitting in the backpack/pocket. cm-inventory now preserves this 6th arg.
    local okTorso, torsoSlot = exports['cm-inventory']:AddItem(src, 'clothing_torso', 1, torsoMeta, 'starter_clothes_equipped', 'outerwear')
    local okPants, pantsSlot = exports['cm-inventory']:AddItem(src, 'clothing_pants', 1, pantsMeta, 'starter_clothes_equipped', 'pants')
    local okShoes, shoesSlot = exports['cm-inventory']:AddItem(src, 'clothing_shoes', 1, shoesMeta, 'starter_clothes_equipped', 'shoes')

    if not okTorso then print('[CM-CHARACTERS] Starter torso add failed: ' .. tostring(torsoSlot)) end
    if not okPants then print('[CM-CHARACTERS] Starter pants add failed: ' .. tostring(pantsSlot)) end
    if not okShoes then print('[CM-CHARACTERS] Starter shoes add failed: ' .. tostring(shoesSlot)) end

    local equipment = {}
    if okTorso and torsoSlot == 'outerwear' then
        equipment.outerwear = { item_name = 'clothing_torso', label = torsoMeta.label, metadata = torsoMeta }
    end
    if okPants and pantsSlot == 'pants' then
        equipment.pants = { item_name = 'clothing_pants', label = pantsMeta.label, metadata = pantsMeta }
    end
    if okShoes and shoesSlot == 'shoes' then
        equipment.shoes = { item_name = 'clothing_shoes', label = shoesMeta.label, metadata = shoesMeta }
    end

    return next(equipment) and equipment or nil
end

CMCharacters.GiveStarterClothes = cmGiveStarterClothes

local function cmMakeNakedAppearance(appearance, char)
    appearance = type(appearance) == 'table' and appearance or {}
    local isFemale = cmIsFemaleAppearance(appearance, char)
    appearance.sex = isFemale and 1 or 0
    local gender = isFemale and 'female' or 'male'
    for key, value in pairs(CM_NAKED_BASE[gender]) do
        appearance[key] = value
    end
    return appearance
end


local function failAppearanceSave(src, message)
    message = tostring(message or 'Failed to save appearance')
    TriggerClientEvent('cm-characters:client:error', src, message)
    TriggerClientEvent('cm-characters:client:appearanceSaved', src, false, { message = message })
end

RegisterNetEvent('cm-characters:server:saveAppearance', function(charId, appearanceData, requestedServiceMode)
    local src = source
    if CMCharacters.IsRateLimited(src, 'saveAppearance', 3, 30) then
        failAppearanceSave(src, 'Please wait before saving again.')
        return
    end

    if type(appearanceData) ~= 'table' then
        failAppearanceSave(src, 'Invalid appearance data')
        return
    end

    -- Never trust the NUI payload directly — whitelist/clamp before any of
    -- it is merged, copied, or persisted below.
    appearanceData = cmSanitizeAppearance(appearanceData)

    local serviceMode = tostring(requestedServiceMode or '')

    -- PHASE 4B lifecycle fix: for a brand-new character, no DB row exists yet
    -- (see server/creation.lua's PendingCharacterDrafts) — this is the exact
    -- moment it gets created, atomically, with its real appearance already
    -- known, instead of an empty row having existed since identity was
    -- submitted. Service modes (gender/surgery/barber) only ever operate on
    -- an existing active character, never a pending draft.
    local char, accountId, err
    local pendingDraft = serviceMode == '' and CMCharacters.PendingCharacterDrafts[src]
    if pendingDraft and tostring(pendingDraft.charId) == tostring(charId) then
        -- Insert with the same '{}' placeholder the old immediate-insert
        -- code always used. The unchanged logic further below (starter
        -- clothing grant + cmMakeNakedAppearance + the final UPDATE) sets
        -- the real appearance_json exactly once, identically to every other
        -- save — no need to compute/write it twice.
        char, accountId, err = CMCharacters.CommitPendingCharacterRow(src, charId, '{}')
        if not char then
            failAppearanceSave(src, err or 'Could not create character')
            return
        end
    else
        char, accountId, err = CMCharacters.GetOwnedCharacter(src, charId)
        if not char then
            failAppearanceSave(src, err or 'Character not found')
            return
        end
    end
    if serviceMode ~= '' then
        if serviceMode ~= 'gender' and serviceMode ~= 'surgery' and serviceMode ~= 'barber' then
            failAppearanceSave(src, 'Invalid appearance service.')
            return
        end
        local activeCharId = Player(src).state.charId or Player(src).state.characterId
        if not activeCharId or tostring(activeCharId) ~= tostring(char.id) then
            failAppearanceSave(src, 'Appearance services require your active character.')
            return
        end

        if serviceMode == 'barber' then
            local ped = GetPlayerPed(src)
            local pCoords = GetEntityCoords(ped)
            local closestShop = nil
            local closestDist = 999.0
            for _, shop in ipairs(Config.BarberShops or {}) do
                if shop.coords then
                    local dist = #(pCoords - shop.coords)
                    if dist < closestDist then
                        closestDist = dist
                        closestShop = shop
                    end
                end
            end
            if not closestShop or closestDist > 25.0 then
                failAppearanceSave(src, 'You are too far from a barber shop.')
                return
            end

            local shopId = closestShop.id or tostring(closestShop.name)

            if not (IsBarberSessionActive and IsBarberSessionActive(src, shopId)) then
                failAppearanceSave(src, 'Talk to the barber NPC before styling.')
                return
            end
            local row = GetBarberShopRow and GetBarberShopRow(shopId)
            if row and tonumber(row.stock or 0) <= 0 then
                failAppearanceSave(src, 'This barber shop is out of grooming supplies. Please ask the salon owner to restock.')
                return
            end

            local cost = GetBarberServiceCost and GetBarberServiceCost(shopId) or tonumber(Config.BarberCost or 100) or 100
            local paid = false
            if exports['cm-core']:RemoveMoney(src, 'cash', cost, 'barber_service') == true then
                paid = true
            elseif exports['cm-core']:RemoveMoney(src, 'bank', cost, 'barber_service') == true then
                paid = true
            end

            if not paid then
                failAppearanceSave(src, ('You need $%s in cash or bank to pay the barber.'):format(cost))
                return
            end

            if ProcessBarberServiceFee then
                ProcessBarberServiceFee(shopId, src)
            end

            -- One styling session per NPC visit; the player must talk to the
            -- barber again to start another.
            if ClearBarberSession then
                ClearBarberSession(src)
            end
        end
    end

    -- IMPORTANT:
    -- cm-inventory resolves owner from Player(src).state.charId.
    -- During first character creation this state may not exist yet, so set it BEFORE AddItem.
    CMCharacters.SetCharacterState(src, char)
    CMCharacters.SyncWithPlayerData(src, tostring(char.id), 'save_appearance')

    -- Give starter clothing items only the first time this character saves appearance.
    -- Otherwise every later SaveAppearance/equip would duplicate starter clothes.
    local alreadyHasAppearance = false
    if char.appearance_json and char.appearance_json ~= '' and char.appearance_json ~= '{}' and char.appearance_json ~= 'null' then
        alreadyHasAppearance = true
    end
    if serviceMode ~= '' and not alreadyHasAppearance then
        failAppearanceSave(src, 'Finish creating this character before using appearance services.')
        return
    end

    local finalAppearance = nil
    local starterEquipment = nil

    if serviceMode == 'barber' then
        local savedAppearance = {}
        if char.appearance_json and char.appearance_json ~= '' and char.appearance_json ~= '{}' and char.appearance_json ~= 'null' then
            local okDec, dec = pcall(json.decode, char.appearance_json)
            if okDec and type(dec) == 'table' then
                savedAppearance = dec
            end
        end

        -- Authoritative gender is immutable at the barber.
        local isFemale = cmIsFemaleAppearance(savedAppearance, char)
        savedAppearance.sex = isFemale and 1 or 0

        -- Merge only grooming and hair fields
        local groomingKeys = {
            'hair_1', 'hair_2', 'hair_color_1', 'hair_color_2',
            'eyebrows_1', 'eyebrows_2', 'eyebrows_3', 'eyebrows_4', 'eyebrows_5', 'eyebrows_6',
            'beard_1', 'beard_2', 'beard_3', 'beard_4',
            'chest_1', 'chest_2', 'chest_3',
        }
        for _, k in ipairs(groomingKeys) do
            if appearanceData[k] ~= nil then
                savedAppearance[k] = tonumber(appearanceData[k]) or 0
            end
        end

        -- Ensure eyebrow opacity is not 0 if an eyebrow style was selected
        if (tonumber(savedAppearance.eyebrows_1) or 0) >= 0 and (tonumber(savedAppearance.eyebrows_2) or 0) <= 0 then
            savedAppearance.eyebrows_2 = 10
        end
        if (tonumber(savedAppearance.eyebrows_3) or 0) > 0 and (savedAppearance.eyebrows_4 == nil or savedAppearance.eyebrows_4 == 0) then
            savedAppearance.eyebrows_4 = savedAppearance.eyebrows_3
        end
        if (tonumber(savedAppearance.beard_1) or 0) > 0 and (tonumber(savedAppearance.beard_2) or 0) <= 0 then
            savedAppearance.beard_2 = 10
        end
        if (tonumber(savedAppearance.beard_3) or 0) > 0 and (savedAppearance.beard_4 == nil or savedAppearance.beard_4 == 0) then
            savedAppearance.beard_4 = savedAppearance.beard_3
        end

        finalAppearance = savedAppearance
    else
        local creatorOutfit = cmCopyTable(appearanceData)
        if not alreadyHasAppearance then
            starterEquipment = cmGiveStarterClothes(src, creatorOutfit, char)
        end
        finalAppearance = cmMakeNakedAppearance(cmCopyTable(appearanceData), char)
    end

    local appearanceJson = json.encode(finalAppearance)

    local ok, result = pcall(function()
        CMCharacters.Query(
            'UPDATE characters SET appearance_json = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ?',
            { appearanceJson, tostring(char.id), accountId }
        )
    end)

    if not ok then
        print('[CM-CHARACTERS] ERROR saving appearance: ' .. tostring(result))
        failAppearanceSave(src, 'Failed to save appearance')
        return
    end

    print('[CM-CHARACTERS] Appearance saved for char ' .. tostring(char.id) .. (serviceMode ~= '' and (' (service: ' .. serviceMode .. ')') or ''))
    exports['cm-core']:CacheInvalidate('char:' .. tostring(char.id))

    -- Refresh state with saved character details.
    CMCharacters.SetCharacterState(src, char)
    CMCharacters.SyncWithPlayerData(src, tostring(char.id), 'appearance_saved')

    if serviceMode == 'barber' then
        TriggerClientEvent('cm-characters:client:applyBarberAppearance', src, finalAppearance)
    elseif alreadyHasAppearance then
        TriggerClientEvent('cm-characters:client:applyAppearance', src, finalAppearance)
    end

    -- Active-character hospital/barber services are edits, not character selection.
    -- Emitting characterLoaded here would reopen cm-spawn's selector.
    if serviceMode == '' then
        TriggerEvent('cm-core:characterLoaded', src, tostring(char.id))
    end

    if starterEquipment then
        TriggerClientEvent('cm-characters:client:equipStarterClothingSlots', src, starterEquipment)
    end

    if serviceMode ~= 'barber' then
        TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
        SetTimeout(1000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
        SetTimeout(3000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
    end

    -- Acknowledgement used by the client to close the creator only after the DB/inventory work finished.
    TriggerClientEvent('cm-characters:client:appearanceSaved', src, true, {
        charId = tostring(char.id),
        serviceMode = serviceMode ~= '' and serviceMode or nil,
        alreadyHadAppearance = alreadyHasAppearance,
        starterEquipment = starterEquipment ~= nil
    })
end)

RegisterNetEvent('cm-characters:server:saveCurrentAppearance', function(appearanceData)
    local src = source
    if CMCharacters.IsRateLimited(src, 'saveCurrentAppearance', 6, 60) then return end
    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        CMCharacters.Notify(src, 'No active character to save appearance.', 'error')
        return
    end
    if type(appearanceData) ~= 'table' then return end

    -- Never trust the NUI payload directly — whitelist/clamp before merging
    -- it into the persisted record.
    appearanceData = cmSanitizeAppearance(appearanceData)

    local char, accountId, err = CMCharacters.GetOwnedCharacter(src, charId)
    if not char then
        CMCharacters.Notify(src, err or 'Character not found.', 'error')
        return
    end

    local merged = {}
    local existingJson = char.appearance_json
    if existingJson and existingJson ~= '' and existingJson ~= 'null' then
        local ok, decoded = pcall(json.decode, existingJson)
        if ok and type(decoded) == 'table' then merged = decoded end
    end

    for key, value in pairs(appearanceData) do merged[key] = value end
    merged = cmMakeNakedAppearance(merged, char)

    CMCharacters.Query(
        'UPDATE characters SET appearance_json = ?, last_seen = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ?',
        { json.encode(merged), tostring(char.id), accountId }
    )
    exports['cm-core']:CacheInvalidate('char:' .. tostring(char.id))
end)

exports('SaveAppearance', function(src)
    src = tonumber(src)
    if not src then return false end
    TriggerClientEvent('cm-characters:client:requestCurrentAppearanceSave', src)
    return true
end)

RegisterNetEvent('cm-characters:server:debugGiveStarterClothes', function(appearanceData)
    local src = source
    if not (Config and Config.EnableDevCommands == true) then
        CMCharacters.Notify(src, 'Starter clothing debug tools are disabled in production.', 'error')
        return
    end
    if not CMCharacters.HasPermission(src, 'characters.debug.starterclothes') then
        CMCharacters.Notify(src, 'No permission to use starter clothing debug tools.', 'error')
        return
    end

    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        CMCharacters.Notify(src, 'No active character.', 'error')
        return
    end
    if type(appearanceData) ~= 'table' then return end

    local char = CMCharacters.GetOwnedCharacter(src, charId)
    if not char then
        CMCharacters.Notify(src, 'Character ownership check failed.', 'error')
        return
    end

    cmGiveStarterClothes(src, appearanceData)
    CMCharacters.LogAdmin(src, 'debug_give_starter_clothes', { char_id = tostring(charId) })
    CMCharacters.Notify(src, 'Starter clothing items added.', 'success')
end)

RegisterNetEvent('cm-characters:server:requestAppearanceData', function(requestId)
    local src = source
    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then
        TriggerClientEvent('cm-characters:client:receiveAppearanceData', src, requestId, nil)
        return
    end
    local char = CMCharacters.GetCharacterById(charId)
    if not char or not char.appearance_json then
        TriggerClientEvent('cm-characters:client:receiveAppearanceData', src, requestId, nil)
        return
    end
    local okDec, dec = pcall(json.decode, char.appearance_json)
    if okDec and type(dec) == 'table' then
        local isFemale = cmIsFemaleAppearance(dec, char)
        dec.sex = isFemale and 1 or 0
        TriggerClientEvent('cm-characters:client:receiveAppearanceData', src, requestId, dec)
    else
        TriggerClientEvent('cm-characters:client:receiveAppearanceData', src, requestId, nil)
    end
end)

RegisterNetEvent('cm-characters:server:requestAppearance', function()
    local src = source
    local charId = Player(src).state.charId or Player(src).state.characterId
    if not charId then return end
    local char = CMCharacters.GetCharacterById(charId)
    if not char or not char.appearance_json then return end
    local okDec, dec = pcall(json.decode, char.appearance_json)
    if okDec and type(dec) == 'table' then
        local isFemale = cmIsFemaleAppearance(dec, char)
        dec.sex = isFemale and 1 or 0
        TriggerClientEvent('cm-characters:client:updateAppearanceCache', src, dec)
        TriggerClientEvent('cm-characters:client:applyAppearance', src, dec)
    end
end)
