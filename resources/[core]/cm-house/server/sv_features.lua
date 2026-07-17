-- ============================================================
--  cm-house | sv_features.lua
--
--  Features derive price and rating. Garage capacity is never typed and is
--  never inferred by the house wizard: it is exactly the number of physical
--  placement-car slots saved in the selected cm-admin garage template.
--
--  Loaded from the DB, not hardcoded, so the admin panel can retune it
--  in-game without a restart.
-- ============================================================

Pricing     = {}   -- [feature_key] = { price_add, star_add, garage_min }
GarageSizes = {}   -- [capacity]    = { label, price_add, selectable }

--- Seed the defaults if they are missing.
--- An older migration may have created the TABLES without the ROWS. In that
--- state the wizard receives an empty garage list and renders nothing but
--- "No garage" -- with no error to explain why. Repair it at boot rather than
--- leaving someone to discover it mid-build.
local function EnsureDefaults()
    MySQL.query.await([[
        INSERT IGNORE INTO cm_house_pricing (feature_key, label, price_add, star_add, garage_min)
        VALUES ('type_trailer','Trailer',40000,0,0),
               ('type_apartment','Apartment',120000,0,0),
               ('type_house','House',250000,1,0),
               ('type_villa','Villa',600000,2,0),
               ('type_mansion','Mansion',1200000,3,0),
               ('garden','Garden',80000,0,0),
               ('pool','Swimming pool',150000,0,0),
               ('helipad','Helipad',400000,0,0)
    ]])

    -- Prices an admin has customised are preserved; only the availability
    -- flag is repaired, since that is the part that breaks the wizard.
    MySQL.query.await([[
        INSERT INTO cm_house_garage_sizes (capacity, label, price_add, selectable)
        VALUES (1,'1 car',25000,1), (2,'2 cars',50000,1), (3,'3 cars',80000,1),
               (4,'4 cars',120000,1), (7,'7 cars',250000,1),
               (14,'14 cars',600000,0), (24,'24 cars',1200000,0)
        ON DUPLICATE KEY UPDATE selectable = VALUES(selectable)
    ]])
end

function LoadPricing()
    EnsureDefaults()
    Pricing, GarageSizes = {}, {}

    for _, r in ipairs(MySQL.query.await('SELECT * FROM cm_house_pricing') or {}) do
        Pricing[r.feature_key] = {
            label     = r.label,
            priceAdd  = r.price_add,
            starAdd   = r.star_add,
            garageMin = r.garage_min,
        }
    end

    for _, r in ipairs(MySQL.query.await('SELECT * FROM cm_house_garage_sizes ORDER BY capacity') or {}) do
        GarageSizes[r.capacity] = {
            label      = r.label,
            priceAdd   = r.price_add,
            selectable = DbBool(r.selectable),
        }
    end

    local nGarage = CountKeys(GarageSizes)
    local nSel = 0
    for _, g in pairs(GarageSizes) do
        if g.selectable then nSel = nSel + 1 end
    end

    print(('[cm-house] pricing: %d features, %d garage sizes (%d selectable)')
        :format(CountKeys(Pricing), nGarage, nSel))

    -- If nothing is selectable the wizard can only ever offer "No garage",
    -- and the admin has no way to tell why. Say it out loud.
    if nSel == 0 then
        print('[cm-house] ^1No selectable garage sizes. The wizard will only offer "No garage".^7')
        print('[cm-house] ^3Run: sql/005_features.sql^7')
    end
end

function CountKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ------------------------------------------------------------
--  The feature signature.
--  A stable, sorted string identifying "what kind of property is this".
--  Templates are keyed by it: same signature means the same interior, so the
--  second house of a kind never needs its interior walked again.
--
--    house + garden + pool  ->  "house|garden|pool"
-- ------------------------------------------------------------
function FeatureSignature(f)
    local parts = { f.houseType }
    if f.hasGarden  then parts[#parts + 1] = 'garden'  end
    if f.hasPool    then parts[#parts + 1] = 'pool'    end
    if f.hasHelipad then parts[#parts + 1] = 'helipad' end
    table.sort(parts, function(a, b)
        -- type always first, then alphabetical, so the key is deterministic.
        if a == f.houseType then return true end
        if b == f.houseType then return false end
        return a < b
    end)
    return table.concat(parts, '|')
end

-- ------------------------------------------------------------
--  Derive everything from the feature set.
-- ------------------------------------------------------------
--- @return table { garageCapacity, garageForced, stars, price, govValue, insurance, dailyCost }
function DeriveProperty(f, chosenGarage)
    local price = 0
    local stars = 0
    local minGarage = 0

    local typeKey = 'type_' .. tostring(f.houseType)
    local t = Pricing[typeKey]
    if t then
        price = price + t.priceAdd
        stars = stars + t.starAdd
        minGarage = math.max(minGarage, t.garageMin)
    end

    for key, on in pairs({ garden = f.hasGarden, pool = f.hasPool, helipad = f.hasHelipad }) do
        if on then
            local p = Pricing[key]
            if p then
                price = price + p.priceAdd
                stars = stars + p.starAdd
                minGarage = math.max(minGarage, p.garageMin)
            end
        end
    end

    -- Garage capacity comes only from the selected reusable garage template.
    -- A house never invents a capacity and never creates a layout during the
    -- property wizard.
    local forced = false
    local capacity = math.max(0, tonumber(chosenGarage) or 0)
    stars = math.max(1, math.min(5, stars))

    -- Configured minimums are validation rules only. They never invent a
    -- physical capacity that the selected template does not contain.
    local g = GarageSizes[capacity]
    if g then price = price + g.priceAdd end

    return {
        garageCapacity = capacity,
        garageForced   = forced,
        garageMinimum  = minGarage,
        garageTemplateMeetsMinimum = capacity >= minGarage,
        stars          = stars,
        price          = price,
        govValue       = math.floor(price * 0.8),
        insurance      = math.floor(price * 0.03),
        dailyCost      = math.floor(price * 0.001),
    }
end

--- What the UI may offer. 14 and 24 are upgrades bought later, never picked
--- at creation, so they are filtered out here rather than hidden client-side.
function SelectableGarages()
    local out = {}
    for cap, g in pairs(GarageSizes) do
        if g.selectable then
            out[#out + 1] = { capacity = cap, label = g.label, priceAdd = g.priceAdd }
        end
    end
    table.sort(out, function(a, b) return a.capacity < b.capacity end)
    return out
end

-- ------------------------------------------------------------
--  Template lookup by signature.
--  This is what removes /cmtemplate: the SECOND house of a kind finds the
--  first one's layout automatically and never asks the admin anything.
-- ------------------------------------------------------------
function FindInteriorTemplates(signature)
    local out = {}
    for id, t in pairs(InteriorTemplates) do
        -- An empty signature is a standalone universal layout created from
        -- /cmadminhouse. It is intentionally reusable by every property type.
        if tostring(t.signature or '') == '' or tostring(t.signature) == tostring(signature or '') then
            out[#out + 1] = {
                id = id, label = t.label,
                weaponStorages = #(t.weapon_storages or t.wardrobes or {}), wardrobes = #(t.weapon_storages or t.wardrobes or {}), stashes = #t.stashes,
            }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function FindGarageTemplates(capacity)
    local out = {}
    for id, t in pairs(GarageTemplates) do
        if t.capacity == capacity then
            out[#out + 1] = { id = id, label = t.label, capacity = t.capacity }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end


local function SelectableGarageTemplates()
    local out = {}
    for id, t in pairs(GarageTemplates or {}) do
        local priceRow = GarageSizes[tonumber(t.capacity) or 0]
        out[#out + 1] = {
            id = tonumber(id),
            label = tostring(t.label or ('Garage ' .. tostring(id))),
            capacity = tonumber(t.capacity) or 0,
            priceAdd = priceRow and tonumber(priceRow.priceAdd) or 0,
            exits = #(t.vehicle_exits or {}),
        }
    end
    table.sort(out, function(a, b)
        if a.capacity ~= b.capacity then return a.capacity < b.capacity end
        return a.label < b.label
    end)
    return out
end

-- ------------------------------------------------------------
--  What the wizard needs to know before it decides where to send you.
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:planProperty', function(src, f)
    if not IsHouseAdmin(src) then return nil end
    if type(f) ~= 'table' then return nil end

    local sig = FeatureSignature(f)
    local garageTemplateId = tonumber(f.garageTemplateId)
    local selectedGarage = garageTemplateId and GarageTemplates[garageTemplateId] or nil
    local selectedCapacity = selectedGarage and tonumber(selectedGarage.capacity) or 0
    local derived = DeriveProperty(f, selectedCapacity)

    local interiors = FindInteriorTemplates(sig)
    local garages = SelectableGarageTemplates()

    return {
        signature = sig,
        derived   = derived,
        interiors = interiors,   -- empty -> create one in cm-admin first
        garages   = garages,
        -- The house wizard never captures templates. It only selects an
        -- existing cm-admin template.
        selectedGarageTemplateId = selectedGarage and garageTemplateId or nil,
        needsInteriorWalk = false,
        needsGarageWalk = false,
    }
end)

lib.callback.register('cm-house:server:getFeatureOptions', function(src)
    if not IsHouseAdmin(src) then return nil end

    local types = {}
    for _, t in ipairs(Config.HouseTypes) do
        local p = Pricing['type_' .. t.key]
        types[#types + 1] = {
            key = t.key, label = t.label,
            priceAdd = p and p.priceAdd or 0,
            starAdd  = p and p.starAdd or 0,
        }
    end

    local feats = {}
    for _, k in ipairs({ 'garden', 'pool', 'helipad' }) do
        local p = Pricing[k]
        if p then
            feats[#feats + 1] = { key = k, label = p.label, priceAdd = p.priceAdd }
        end
    end

    return {
        types    = types,
        features = feats,
        garages  = SelectableGarageTemplates(),
    }
end)

exports('DeriveProperty',   DeriveProperty)
exports('FeatureSignature', FeatureSignature)

-- ------------------------------------------------------------
--  Live template lookups.
--  The wizard re-asks at each step rather than trusting the plan it captured
--  when the features were chosen. Another admin may have built the very layout
--  it is about to send this one off to rebuild.
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:interiorsFor', function(src, signature)
    if not IsHouseAdmin(src) then return nil end
    return FindInteriorTemplates(tostring(signature or ''))
end)

lib.callback.register('cm-house:server:garagesFor', function(src, capacity)
    if not IsHouseAdmin(src) then return nil end

    capacity = tonumber(capacity)
    if not capacity or capacity <= 0 then return {} end

    return FindGarageTemplates(capacity)
end)


--- Is this address free?
--- Checked at the FEATURES step, not at publish. Discovering "address 01 is
--- taken" after parking seven cars is a cruel way to find out.
lib.callback.register('cm-house:server:checkAddress', function(src, number)
    if not IsHouseAdmin(src) then return false, 'Not permitted.' end

    number = tostring(number or ''):gsub('%s+', '')
    if number == '' then return true end   -- not typed yet; publish will catch it

    if #number > 16 or not number:match('^[%w%-_]+$') then
        return false, 'The address must be 1-16 letters, numbers, - or _.'
    end

    if MySQL.scalar.await('SELECT id FROM cm_houses WHERE house_number = ?', { number }) then
        return false, ('Address %s is already taken.'):format(number)
    end

    return true
end)
