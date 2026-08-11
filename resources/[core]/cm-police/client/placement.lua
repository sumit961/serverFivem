-- cm-police shared object-placement helper (spike strips, barricades).
-- Position follows the CAMERA's current yaw (GetGameplayCamRot), not the
-- ped's body heading, at a distance clamped to Config.Placement's
-- Min/MaxDistance -- panning the camera (mouse) continuously re-aims the
-- preview around the officer, and it can never drift arbitrarily far from
-- them. Holding left-click steals the mouse-look axes and applies them as
-- rotation instead of camera movement -- "grab and twist" -- releasing it
-- goes back to normal look-driven repositioning.

-- File-scoped (not local to PoliceBeginObjectPlacement) so the resource-stop
-- cleanup below can always reach whatever's in progress, and so PoliceIsPlacing()
-- gives every feature a single shared lock -- spikes and barricades can't
-- both be mid-placement at the same time.
local placing = false
local previewObject = nil
local previewModel = nil

function PoliceIsPlacing()
    return placing
end

-- Point at `distance` along the camera's current yaw from the ped's own
-- position -- recomputed every tick, so turning the camera (mouse) moves
-- this point around the officer in real time.
local function pointAtDistance(ped, distance)
    local coords = GetEntityCoords(ped)
    local rad = math.rad(GetGameplayCamRot(2).z)
    return vector3(coords.x - math.sin(rad) * distance, coords.y + math.cos(rad) * distance, coords.z)
end

local function releaseCurrentModel()
    if previewModel then SetModelAsNoLongerNeeded(previewModel); previewModel = nil end
end

local function endPlacement()
    placing = false
    if previewObject and DoesEntityExist(previewObject) then DeleteEntity(previewObject) end
    previewObject = nil
    releaseCurrentModel()
    PoliceHideHint()
end

-- opts = { model (single model name string) OR models (list of model name
--          strings, for E/Q cycling -- barricades only), startDistance,
--          minDistance, maxDistance, timeoutMs, hintText,
--          onConfirm(coords, heading, modelName), onCancel(reason),
--          onModelChange(index, modelName) }
-- Returns true if placement started, false if refused (already placing
-- somewhere else, the model list is empty, or the model failed to load).
function PoliceBeginObjectPlacement(opts)
    if placing then return false end
    local models = (type(opts.models) == 'table' and #opts.models > 0) and opts.models or (opts.model and { opts.model } or nil)
    if not models then return false end
    local modelIndex = 1
    local modelName = models[modelIndex]
    local model = joaat(modelName)
    RequestModel(model)
    local loadDeadline = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < loadDeadline do Wait(0) end
    if not HasModelLoaded(model) then
        if opts.onCancel then opts.onCancel('model_failed') end
        return false
    end

    placing = true
    previewModel = model
    local minDist = opts.minDistance or Config.Placement.MinDistance or 1.0
    local maxDist = opts.maxDistance or Config.Placement.MaxDistance or 5.0
    local distance = math.max(minDist, math.min(opts.startDistance or 3.0, maxDist))
    local ped = PlayerPedId()
    local pos = pointAtDistance(ped, distance)
    previewObject = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityAlpha(previewObject, 120, false)
    SetEntityCollision(previewObject, false, false)
    SetEntityInvincible(previewObject, true)
    SetEntityHeading(previewObject, GetEntityHeading(ped))

    local timeoutAt = GetGameTimer() + (opts.timeoutMs or 45000)

    -- E/Q cycling (barricades only -- spike strips only ever pass a single
    -- `opts.model`, so `models` has length 1 and this never triggers).
    -- Reloads the preview with the newly-selected model at the same spot.
    local function swapModel(delta)
        if #models <= 1 then return end
        local coords = GetEntityCoords(previewObject)
        local heading = GetEntityHeading(previewObject)
        modelIndex = ((modelIndex - 1 + delta) % #models) + 1
        modelName = models[modelIndex]
        local newModel = joaat(modelName)
        RequestModel(newModel)
        local deadline = GetGameTimer() + 2000
        while not HasModelLoaded(newModel) and GetGameTimer() < deadline do Wait(0) end
        if not HasModelLoaded(newModel) then
            PoliceNotify('That model failed to load.', 'error')
            return
        end
        if previewObject and DoesEntityExist(previewObject) then DeleteEntity(previewObject) end
        releaseCurrentModel()
        previewModel = newModel
        previewObject = CreateObject(newModel, coords.x, coords.y, coords.z, false, false, false)
        SetEntityAlpha(previewObject, 120, false)
        SetEntityCollision(previewObject, false, false)
        SetEntityInvincible(previewObject, true)
        SetEntityHeading(previewObject, heading)
        if opts.onModelChange then opts.onModelChange(modelIndex, modelName) end
    end

    CreateThread(function()
        while placing do
            Wait(0)
            if not previewObject or not DoesEntityExist(previewObject) then
                placing = false
                break
            end
            if GetGameTimer() >= timeoutAt then
                endPlacement()
                if opts.onCancel then opts.onCancel('timeout') end
                break
            end

            -- Scroll wheel adjusts distance from the officer, clamped so the
            -- preview can never drift arbitrarily far away.
            if IsControlJustPressed(0, 10) then distance = math.min(maxDist, distance + 0.25) end -- scroll up
            if IsControlJustPressed(0, 11) then distance = math.max(minDist, distance - 0.25) end -- scroll down

            if IsControlPressed(0, 24) then -- left-click held / INPUT_ATTACK
                -- Steal the mouse-look axes and the attack action itself for
                -- this frame -- rotate the preview instead of turning the
                -- camera or swinging a weapon.
                DisableControlAction(0, 1, true) -- INPUT_LOOK_LR
                DisableControlAction(0, 2, true) -- INPUT_LOOK_UD
                DisableControlAction(0, 24, true) -- INPUT_ATTACK
                -- Once a control is disabled for this frame, its value must
                -- be read back via GetDisabledControlNormal -- GetControlNormal
                -- reflects the (just-suppressed) enabled state and would
                -- read as 0 here.
                local lookX = GetDisabledControlNormal(0, 1)
                if lookX ~= 0.0 then
                    SetEntityHeading(previewObject, GetEntityHeading(previewObject) + lookX * 8.0)
                end
            else
                local pos2 = pointAtDistance(PlayerPedId(), distance)
                SetEntityCoordsNoOffset(previewObject, pos2.x, pos2.y, pos2.z, false, false, false)
            end
            PlaceObjectOnGroundProperly(previewObject)

            if #models > 1 then
                if IsControlJustPressed(0, 38) then swapModel(1) end -- E: next type
                if IsControlJustPressed(0, 44) then swapModel(-1) end -- Q: previous type
            end

            PoliceShowHint(opts.hintText or (('[Mouse] Move  ·  [Hold Click] Rotate  ·  [Scroll] Distance%s  ·  [Enter] Confirm  ·  [Backspace] Cancel'):format(#models > 1 and '  ·  [E/Q] Change type' or '')))

            if IsControlJustPressed(0, 18) then -- INPUT_ENTER
                local finalCoords = GetEntityCoords(previewObject)
                local finalHeading = GetEntityHeading(previewObject)
                local finalModelName = modelName
                -- Deliberately NOT endPlacement() here: that would release
                -- the model before onConfirm gets a chance to CreateObject
                -- the real, final object with that same hash -- the model
                -- must stay loaded until after onConfirm runs.
                placing = false
                if previewObject and DoesEntityExist(previewObject) then DeleteEntity(previewObject) end
                previewObject = nil
                PoliceHideHint()
                if opts.onConfirm then opts.onConfirm(finalCoords, finalHeading, finalModelName) end
                releaseCurrentModel()
                break
            elseif IsControlJustPressed(0, 194) then -- INPUT_FRONTEND_DELETE / Backspace
                endPlacement()
                if opts.onCancel then opts.onCancel('cancelled') end
                break
            end
        end
    end)

    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and placing then endPlacement() end
end)
