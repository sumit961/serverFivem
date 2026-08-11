-- ============================================================
--  cm-house | sv_create.lua   |  PHASE 1 (rewritten)
--
--  A property now stores ONLY its unique exterior coordinates and a pointer
--  to two reusable templates. The interior phase is gone: selecting a
--  template supplies the entry, exit, weapon lockers and garage door for free.
--
--  Spec: "Creating a second property with the same interior requires no
--         repeated entry, exit, weapon-locker or garage-door placement."
-- ============================================================

local function clampInt(v, min, max, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    v = math.floor(v)
    if v < min then return min end
    if v > max then return max end
    return v
end

-- Serialises the short number-allocation window. cm_houses also keeps its
-- unique house_number constraint as the final database-level guard.
local creatingHouse = false

-- ------------------------------------------------------------
--  Publish
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:createHouse', function(src, d)
    if not IsHouseAdmin(src) then return false, 'You cannot create properties.' end
    if type(d) ~= 'table' or type(d.features) ~= 'table' then
        return false, 'Malformed request.'
    end

    local f = d.features

    -- ---- type ----
    local houseType
    for _, t in ipairs(Config.HouseTypes) do
        if t.key == f.houseType then houseType = t.key break end
    end
    if not houseType then return false, 'Pick a property type.' end

    -- Apartments never get a helipad, and are never family houses.
    if houseType == 'apartment' and f.hasHelipad then
        return false, 'Apartments cannot have a helipad.'
    end

    -- ---- DERIVE, never trust ----
    -- The client showed a price. It does not get to set one: recompute the
    -- whole thing here from the features alone.
    local requestedGarageId = tonumber(f.garageTemplateId or d.garageTemplateId)
    local requestedGarage = requestedGarageId and GarageTemplates[requestedGarageId] or nil
    if requestedGarageId and not requestedGarage then
        return false, 'Select an existing garage template from cm-admin.'
    end
    local requestedCapacity = requestedGarage and tonumber(requestedGarage.capacity) or 0
    local derived = DeriveProperty(f, requestedCapacity)
    local sig = FeatureSignature(f)
    if derived.garageTemplateMeetsMinimum == false then
        return false, ('This property requires at least %d garage slot%s, but the selected template has %d.')
            :format(tonumber(derived.garageMinimum) or 0,
                (tonumber(derived.garageMinimum) or 0) == 1 and '' or 's', requestedCapacity)
    end

    -- ---- exterior ----
    if not ValidCoords(d.door, true) then return false, 'The front door is missing.' end

    local garageZone, vehicleExit, helipad

    if derived.garageCapacity > 0 then
        if not ValidCoords(d.garageZone, true) then
            return false, 'This property has a garage, so it needs a return zone.'
        end
        if not ValidCoords(d.vehicleExit, true) then
            return false, 'A garage needs an outside point for cars to appear at.'
        end
        garageZone  = d.garageZone
        vehicleExit = d.vehicleExit
    end

    if f.hasHelipad then
        if not ValidCoords(d.helipad, false) then
            return false, 'This property has a helipad, so place where it lands.'
        end
        helipad = d.helipad
    end

    -- ---- identity ----
    -- Players and admins identify properties as House #<number>. The client
    -- cannot choose either value; both are authoritative here.
    local label = 'House'

    -- ---- templates ----
    local interiorId = tonumber(d.interiorTemplateId)
    local interior   = interiorId and InteriorTemplates[interiorId]
    if not interior then return false, 'This property has no interior layout.' end

    -- The layout must belong to THIS kind of property, or a mansion could
    -- inherit a trailer's floor plan.
    if interior.signature ~= '' and interior.signature ~= sig then
        return false, 'That layout belongs to a different kind of property.'
    end

    local garageId, garage
    if derived.garageCapacity > 0 then
        garageId = requestedGarageId or tonumber(d.garageTemplateId)
        garage = garageId and GarageTemplates[garageId]
        if not garage then return false, 'This property has no garage layout.' end

        if not requestedGarage or garageId ~= requestedGarageId then
            return false, 'Select an existing garage template from the property creator.'
        end
        if garage.capacity ~= derived.garageCapacity then
            return false, ('That garage holds %d cars, but this property needs %d.')
                :format(garage.capacity, derived.garageCapacity)
        end
        -- No garage-door check any more: the single exit door serves both.
    end

    local familyEligible = (houseType ~= 'apartment') and 1 or 0
    local adminCid = GetCid(src)

    if creatingHouse then
        return false, 'Another house is being published. Please try again.'
    end
    creatingHouse = true

    local numberOk, number = pcall(function()
        return tostring(MySQL.scalar.await([[
            SELECT COALESCE(MAX(
                CASE WHEN house_number REGEXP '^[0-9]+$'
                    THEN CAST(house_number AS UNSIGNED)
                END
            ), 0) + 1
            FROM cm_houses
        ]]) or 1)
    end)
    if not numberOk or #number > 16 then
        creatingHouse = false
        return false, 'The next house number could not be allocated.'
    end

    -- Built column-by-column so a nil simply OMITS the column. A `false`
    -- would coerce to 0 on garage_template_id, and there is no template with
    -- id 0 -- which is exactly the foreign key error this replaces.
    local sql, params = BuildInsert('cm_houses', {
        { 'house_number',         number },
        { 'label',                label },
        { 'house_type',           houseType },

        { 'has_garden',           f.hasGarden and 1 or 0 },
        { 'has_pool',             f.hasPool and 1 or 0 },
        { 'has_helipad',          f.hasHelipad and 1 or 0 },
        { 'star_rating',          derived.stars },

        { 'interior_template_id', interiorId },
        { 'garage_template_id',   garageId },      -- nil -> column omitted

        { 'door_coords',          json.encode(d.door) },
        { 'garage_coords',        SqlJson(garageZone) },
        { 'helipad_coords',       SqlJson(helipad) },
        { 'vehicle_exit',         SqlJson(vehicleExit) },
        { 'photo_cam',            SqlJson(d.photoCam) },
        { 'image_url',            nil },

        { 'garage_slots',         derived.garageCapacity },
        { 'wardrobe_count',       #(interior.weapon_storages or interior.wardrobes or {}) },

        { 'price',                derived.price },
        { 'gov_value',            derived.govValue },
        { 'insurance',            derived.insurance },
        { 'daily_cost',           derived.dailyCost },

        { 'locked',               1 },
        { 'for_sale',             1 },
        { 'family_eligible',      familyEligible },
        { 'status',               'published' },
        { 'created_by',           adminCid },
    })

    local insertOk, houseId = pcall(MySQL.insert.await, sql, params)
    creatingHouse = false
    if not insertOk then return false, 'The database refused the insert.' end
    if not houseId then return false, 'The database refused the insert.' end

    -- The screenshot was captured before the database ID existed. Move the
    -- pending file into its permanent house_<id>.jpg filename now. A failed
    -- move does not corrupt ownership or garage rows; the house publishes with
    -- its stored camera framing and the admin can retake the photo.
    local imageUrl, photoWarning
    if d.photoToken and FinalizePendingHousePhoto then
        imageUrl, photoWarning = FinalizePendingHousePhoto(d.photoToken, src, houseId)
    end

    -- Pre-create the empty slot rows ATOMICALLY.
    --
    -- No `state` column: migration 006 dropped it. cm-vehicles alone owns
    -- whether a car is parked (`is_stored`), and a second opinion here is
    -- precisely how a vehicle ends up existing in two places at once. These
    -- rows are a pure SEATING CHART -- which slot holds which car, nothing more.
    -- A NULL vehicle_id is an empty space.
    --
    -- All slots insert in one transaction. The house insert has to happen first
    -- to obtain its auto-increment id, so if the slot transaction fails we roll
    -- back by deleting the just-created house rather than publishing a property
    -- with a partial garage.
    if derived.garageCapacity and derived.garageCapacity > 0 then
        local slotTx = {}
        for i = 1, derived.garageCapacity do
            slotTx[#slotTx + 1] = {
                query = 'INSERT INTO cm_house_vehicle_slots (house_id, slot_index) VALUES (?, ?)',
                values = { houseId, i },
            }
        end
        local okTx, committed = pcall(function() return MySQL.transaction.await(slotTx) end)
        if not okTx or committed == false then
            -- Roll back the orphaned house so it never publishes half-built.
            pcall(function()
                MySQL.query.await('DELETE FROM cm_house_vehicle_slots WHERE house_id = ?', { houseId })
                MySQL.query.await('DELETE FROM cm_houses WHERE id = ?', { houseId })
            end)
            if d.photoToken and DiscardPendingHousePhoto then
                pcall(function() DiscardPendingHousePhoto(d.photoToken) end)
            end
            return false, 'The garage slots could not be created; the property was not saved. Please try again.'
        end
    end

    local house = {
        id = houseId, house_number = number, label = label, house_type = houseType,
        has_garden = f.hasGarden, has_pool = f.hasPool, has_helipad = f.hasHelipad,
        star_rating = derived.stars,
        interior_template_id = interiorId, garage_template_id = garageId,
        door_coords = d.door, garage_coords = garageZone,
        helipad_coords = helipad, vehicle_exit = vehicleExit,
        photo_cam = d.photoCam,
        image_url = imageUrl,
        owner_cid = nil, family_id = nil,
        garage_slots = derived.garageCapacity,
        wardrobe_count = #(interior.weapon_storages or interior.wardrobes or {}),
        price = derived.price, gov_value = derived.govValue,
        insurance = derived.insurance, daily_cost = derived.dailyCost,
        paid_until = nil, locked = true, for_sale = true,
        family_eligible = familyEligible == 1,
        status = 'published',
    }
    Houses[houseId] = house

    LogHouse(houseId, nil, adminCid, 'house_create', {
        number = number, signature = sig, stars = derived.stars, price = derived.price,
    })
    Audit(src, 'house_create', { houseId = houseId, number = number, price = derived.price })

    TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(house))

    local publishedMessage = ('House #%s published. %d stars, $%s%s')
        :format(number, derived.stars, derived.price,
                derived.garageCapacity > 0
                    and (', ' .. derived.garageCapacity .. '-car garage') or '')
    if d.photoToken and not imageUrl then
        publishedMessage = publishedMessage .. ' Photo file could not be finalized; use Retake Photo in admin.'
        print(('[cm-house] pending photo finalize failed for house %s: %s')
            :format(tostring(houseId), tostring(photoWarning)))
    end
    return true, publishedMessage
end)

-- ------------------------------------------------------------
--  Client-safe payloads
-- ------------------------------------------------------------
function BuildClientHouse(h)
    return {
        id          = h.id,
        houseNumber = h.house_number,
        label       = h.label,
        houseType   = h.house_type,
        door        = h.door_coords,
        garage      = h.garage_coords,
        helipad     = h.helipad_coords,
        owned       = h.owner_cid ~= nil,
        familyId    = h.family_id,
        isFamilyHouse = h.family_id ~= nil,
        forSale     = h.owner_cid == nil
                      and (h.for_sale == true or Config.Purchase.autoListUnowned),
    }
end

lib.callback.register('cm-house:server:getAllHouses', function(src)
    local out = {}
    for _, h in pairs(Houses) do
        if h.status == 'published' then
            out[#out + 1] = BuildClientHouse(h)
        end
    end
    return out
end)

-- ============================================================
--  Placement cars
--
--  The car you drive into a garage space is a REAL, networked vehicle -- not
--  a client-side prop. It has to be: every access check in cm-vehicles
--  resolves a plate to a database row, and a car with no row reports
--  "Vehicle not found" and refuses to start.
--
--  cm-vehicles' admin registry gives us a car that exists in the world,
--  belongs to nobody, is drivable, and vanishes on restart. Nothing is
--  written to cm_owned_vehicles -- spawning is not giving.
-- ============================================================

local PlacementVehicles = {}

local function placementPlate(value)
    return tostring(value or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local function rememberPlacementVehicle(src, plate)
    plate = placementPlate(plate)
    if plate == '' then return end
    PlacementVehicles[src] = PlacementVehicles[src] or {}
    PlacementVehicles[src][plate] = true
end

local function forgetPlacementVehicle(src, plate)
    plate = placementPlate(plate)
    local set = PlacementVehicles[src]
    if not set or set[plate] ~= true then return false end
    set[plate] = nil
    if next(set) == nil then PlacementVehicles[src] = nil end
    return true
end

local function placementSpec(payload)
    payload = type(payload) == 'table' and payload or {}
    local coords = type(payload.coords) == 'table' and payload.coords or payload
    local kind = tostring(payload.kind or 'car'):lower()
    if kind ~= 'helicopter' then kind = 'car' end
    local configured = Config.PlacementVehicles or {}
    local model = kind == 'helicopter'
        and tostring(configured.helicopter or 'frogger')
        or tostring(configured.car or 'sultan')
    return coords, kind, model
end

lib.callback.register('cm-house:server:spawnPlacer', function(src, payload)
    local _, requestedKind = placementSpec(payload)
    local allowed = HasHouseStaffPermission(src, 'create') == true
        or (requestedKind == 'car' and HasHouseStaffPermission(src, 'garages') == true)
    if not allowed then return false, 'You cannot place vehicles for this layout.' end

    if GetResourceState('cm-vehicles') ~= 'started' then
        return false, 'cm-vehicles is not running, so placement vehicles cannot be created.'
    end

    local coords, kind, model = placementSpec(payload)
    if type(coords) ~= 'table' or tonumber(coords.x) == nil
        or tonumber(coords.y) == nil or tonumber(coords.z) == nil then
        return false, 'Bad coordinates.'
    end
    coords = {
        x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z),
        h = tonumber(coords.h or coords.w) or 0.0,
    }

    -- Do not create the car directly inside the player's collision capsule.
    -- A short forward offset also makes underground/MLO placement much more
    -- reliable because the model can settle before the client enters it.
    if kind == 'car' and payload.exact ~= true then
        local rad = math.rad(coords.h)
        coords.x = coords.x - math.sin(rad) * 3.5
        coords.y = coords.y + math.cos(rad) * 3.5
        coords.z = coords.z + 0.25
    elseif kind == 'helicopter' then
        coords.z = coords.z + 1.0
    end

    local called, res = pcall(function()
        return exports['cm-vehicles']:SpawnAdminVehicle(src, model, coords, {
            access   = 'owner',
            label    = kind == 'helicopter' and 'Helipad placement helicopter' or 'Garage placement car',
            engineOn = true,
            warp = true,
            placementKind = kind,
        })
    end)

    if not called then
        local err = tostring(res)
        if err:find('No such export') then
            if kind == 'car' then
                print('[cm-house] ^3cm-vehicles has no SpawnAdminVehicle export; using local nudge mode for garage slots.^7')
                return true, { fallback = true, kind = kind, model = model }
            end
            return false, 'A drivable placement helicopter requires the cm-vehicles SpawnAdminVehicle export.'
        end
        print(('[cm-house] ^1SpawnAdminVehicle threw: %s^7'):format(err))
        return false, 'The vehicle system errored. Check the server console.'
    end

    if type(res) ~= 'table' or not res.ok then
        return false, (type(res) == 'table' and res.error)
            or 'The vehicle system rejected the placement vehicle.'
    end
    if not res.netId then return false, 'The placement vehicle did not spawn.' end

    rememberPlacementVehicle(src, res.plate)
    return true, {
        plate = res.plate,
        netId = res.netId,
        kind = kind,
        model = model,
    }
end)

RegisterNetEvent('cm-house:server:deletePlacer', function(plate)
    local src = source
    if not forgetPlacementVehicle(src, plate) then return end
    if GetResourceState('cm-vehicles') ~= 'started' then return end

    pcall(function()
        exports['cm-vehicles']:DeleteAdminVehicle(plate)
    end)
end)

local function clearPlacementVehicles(src)
    local set = PlacementVehicles[src]
    PlacementVehicles[src] = nil
    if not set or GetResourceState('cm-vehicles') ~= 'started' then return end
    for plate in pairs(set) do
        pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(plate) end)
    end
end

AddEventHandler('playerDropped', function()
    clearPlacementVehicles(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(PlacementVehicles) do clearPlacementVehicles(src) end
end)
