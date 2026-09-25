-- Shared tablet lifecycle for Law operational screens (MDT and Dispatch).
-- This helper owns only the tablet prop and animation; F6/Hub screens never
-- create a prop and therefore keep their existing presentation unchanged.
local tabletProp, tabletModel, tabletActive = nil, nil, false
local tabletDict, tabletAnim = nil, nil
local tabletAnimationCandidates = {
    { dict = 'amb@code_human_in_bus_passenger_idles@generic@tablet@idle_a', anim = 'idle_a' },
    { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@idle_a', anim = 'idle_a' },
    { dict = 'amb@world_human_seat_wall_tablet@male@base', anim = 'base' },
}

local function requestAsset(request, loaded, value, timeout)
    request(value)
    local deadline = GetGameTimer() + (timeout or 2500)
    while not loaded(value) and GetGameTimer() < deadline do Wait(0) end
    return loaded(value)
end

local function deleteTablet()
    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        SetEntityAsMissionEntity(tabletProp, true, true)
        DeleteObject(tabletProp)
        if DoesEntityExist(tabletProp) then DeleteEntity(tabletProp) end
    end
    tabletProp = nil
    if tabletModel then SetModelAsNoLongerNeeded(tabletModel); tabletModel = nil end
    tabletDict, tabletAnim = nil, nil
end

local function stopTablet()
    tabletActive = false
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then ClearPedSecondaryTask(ped) end
    deleteTablet()
end

function StopLawTablet()
    stopTablet()
end

function StartLawTablet()
    if tabletActive then return true end
    local ped = PlayerPedId()
    if ped == 0 or IsEntityDead(ped) then return false end

    local model = joaat('prop_cs_tablet')
    if not requestAsset(RequestModel, HasModelLoaded, model, 2500) then return false end
    local animation
    for _, candidate in ipairs(tabletAnimationCandidates) do
        if requestAsset(RequestAnimDict, HasAnimDictLoaded, candidate.dict, 900) then
            animation = candidate
            break
        end
    end
    if not animation then
        SetModelAsNoLongerNeeded(model)
        return false
    end

    tabletModel = model
    tabletDict, tabletAnim = animation.dict, animation.anim
    tabletProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    if not tabletProp or tabletProp == 0 then
        deleteTablet()
        return false
    end

    SetEntityAsMissionEntity(tabletProp, true, true)
    local hand = GetPedBoneIndex(ped, 60309)
    AttachEntityToEntity(tabletProp, ped, hand, 0.03, 0.002, -0.02, 10.0, 160.0, 0.0, true, true, false, true, 1, true)
    TaskPlayAnim(ped, tabletDict, tabletAnim, 3.0, -3.0, -1, 49, 0.0, false, false, false)
    tabletActive = true

    CreateThread(function()
        while tabletActive do
            Wait(500)
            local current = PlayerPedId()
            local legal, police = LocalPlayer.state.cmLegalOrg, LocalPlayer.state.cmPolice
            local onDuty = (type(legal) == 'table' and legal.onDuty == true and not legal.suspended)
                or (type(police) == 'table' and police.onDuty == true and not police.suspended)
            if current == 0 or IsEntityDead(current) or not onDuty then
                if type(CmLawMenuOpen) == 'function' and CmLawMenuOpen() then
                    CmLawCloseMenu()
                elseif type(IsPoliceMenuOpen) == 'function' and IsPoliceMenuOpen() then
                    TriggerEvent('cm-police:client:closeMenu')
                else
                    stopTablet()
                end
                break
            end
            if not tabletProp or not DoesEntityExist(tabletProp) then
                stopTablet()
                break
            end
            if not IsEntityPlayingAnim(current, tabletDict, tabletAnim, 3) then
                TaskPlayAnim(current, tabletDict, tabletAnim, 3.0, -3.0, -1, 49, 0.0, false, false, false)
            end
        end
    end)
    return true
end

RegisterNetEvent('cm-playerdata:client:characterUnloaded', stopTablet)
RegisterNetEvent('cm-playerdata:client:unloaded', stopTablet)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then stopTablet() end
end)
