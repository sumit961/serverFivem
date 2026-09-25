-- cm-police shared object-placement helper (spike strips, barricades).
-- Position follows the CAMERA's current yaw (GetGameplayCamRot), not the
-- ped's body heading, at a distance clamped to PoliceConfig.Placement's
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
local placementAnimation = nil

function PoliceIsPlacing()
    return placing
end

local function loadAnimationDictionary(dictionary, timeoutMs)
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + (timeoutMs or 1500)
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dictionary)
end

function StartScenePlacementAnimation(kind)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return false end
    StopScenePlacementAnimation()
    -- Base-game handling animation; upper-body playback keeps movement and
    -- camera controls available while the preview follows the camera.
    local dictionary, clip = 'anim@heists@box_carry@', 'idle'
    if kind == 'spike' or kind == 'barricade' then
        dictionary, clip = 'anim@heists@box_carry@', 'idle'
    end
    if not loadAnimationDictionary(dictionary) then return false end
    TaskPlayAnim(ped, dictionary, clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
    placementAnimation = { ped = ped, dictionary = dictionary, clip = clip }
    return true
end

function StopScenePlacementAnimation()
    if placementAnimation then
        local ped = placementAnimation.ped
        if DoesEntityExist(ped) then
            StopAnimTask(ped, placementAnimation.dictionary, placementAnimation.clip, 2.0)
            ClearPedSecondaryTask(ped)
        end
        placementAnimation = nil
    end
end

local function playScenePlacementConfirmAnimation()
    local ped = PlayerPedId()
    StopScenePlacementAnimation()
    local dictionary, clip = 'pickup_object', 'pickup_low'
    if not loadAnimationDictionary(dictionary, 1200) then return 0 end
    TaskPlayAnim(ped, dictionary, clip, 4.0, -4.0, 900, 0, 0.0, false, false, false)
    return 700
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
    StopScenePlacementAnimation()
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
    StartScenePlacementAnimation(opts.animationKind or (#models > 1 and 'barricade' or 'spike'))
    previewModel = model
    local minDist = opts.minDistance or PoliceConfig.Placement.MinDistance or 1.0
    local maxDist = opts.maxDistance or PoliceConfig.Placement.MaxDistance or 5.0
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
            local activePed = PlayerPedId()
            if IsEntityDead(activePed) then
                endPlacement()
                if opts.onCancel then opts.onCancel('cancelled') end
                break
            end
            if not previewObject or not DoesEntityExist(previewObject) then
                placing = false
                StopScenePlacementAnimation()
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
                DisableControlAction(0, 25, true) -- INPUT_AIM
                DisableControlAction(0, 140, true) -- INPUT_MELEE_ATTACK_LIGHT
                DisableControlAction(0, 141, true) -- INPUT_MELEE_ATTACK_HEAVY
                DisableControlAction(0, 142, true) -- INPUT_MELEE_ATTACK_ALTERNATE
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

            PoliceShowHint(opts.hintText or (('SCENE PLACEMENT  ·  Mouse Position  ·  Hold LMB Rotate  ·  Scroll Distance%s  ·  ENTER Place  ·  BACKSPACE Cancel'):format(#models > 1 and '  ·  E/Q Type' or '')))

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
                local confirmWait = playScenePlacementConfirmAnimation()
                if confirmWait > 0 then Wait(confirmWait) end
                if opts.onConfirm then opts.onConfirm(finalCoords, finalHeading, finalModelName) end
                StopScenePlacementAnimation()
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
