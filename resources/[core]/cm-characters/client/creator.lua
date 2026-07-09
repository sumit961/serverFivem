-- cm-characters/client/creator.lua


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

local display = false
local currentSlot = nil
local currentAccountId = nil
local isCreating = false

local function setCharacterFlowState(active)
    LocalPlayer.state:set('isInCharacterSelector', active == true, true)
    LocalPlayer.state:set('isInCharacterCreation', active == true, true)
    LocalPlayer.state:set('skipPositionSave', active == true, true)
    LocalPlayer.state:set('characterFullySpawned', active ~= true, true)
end

local function setHudVisible(visible)
    visible = visible == true
    LocalPlayer.state:set('cmHudHiddenByCharacters', not visible, true)

    if visible then
        TriggerEvent('cm-hud:client:showUiOnly', 'cm-characters-creator')
        TriggerEvent('cm-hud:client:setUiVisible', true, 'cm-characters-creator')
    else
        TriggerEvent('cm-hud:client:hideUiOnly', 'cm-characters-creator')
        TriggerEvent('cm-hud:client:setUiVisible', false, 'cm-characters-creator')
    end

    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetUiVisible(visible, 'cm-characters-creator') end)
        if visible then
            pcall(function() exports['cm-hud']:ShowUiOnly('cm-characters-creator') end)
        else
            pcall(function() exports['cm-hud']:HideUiOnly('cm-characters-creator') end)
        end
    end
end

local function preloadFreemodeModels()
    CreateThread(function()
        local models = { `mp_m_freemode_01`, `mp_f_freemode_01` }
        for _, model in ipairs(models) do
            RequestModel(model)
            local timeout = GetGameTimer() + 5000
            while not HasModelLoaded(model) and GetGameTimer() < timeout do
                RequestModel(model)
                Wait(0)
            end
        end
    end)
end

AddEventHandler('cm-characters:client:openCreator', function(slot, accountId)
    currentSlot = slot
    currentAccountId = accountId
    display = true
    isCreating = false
    TriggerEvent('cm-characters:client:setWorldLock', 'creator', true)
    setCharacterFlowState(true)
    setHudVisible(false)
    preloadFreemodeModels()
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showCreator',
        slot = slot
    })
    print('[CM-CHARACTERS] Creator opened for slot ' .. tostring(slot))
end)

RegisterNetEvent('cm-characters:client:createResult', function(success, data)
    print('[CM-CHARACTERS] createResult: success=' .. tostring(success) .. ' data=' .. tostring(data))
    isCreating = false
    
    if success then
        SendNUIMessage({action = 'hideCreator'})
        display = false
        SetNuiFocus(false, false)
        
        SendNUIMessage({ action = 'creationLoading', show = true, message = 'Preparing character creator...' })
        print('[CM-CHARACTERS] Opening appearance for charId=' .. tostring(data.charId))
        TriggerEvent('cm-characters:client:openAppearance', {
            charId = data.charId,
            slot = currentSlot,
            gender = data.gender,
            isNew = true
        })
    else
        -- Show error in creator form
        SendNUIMessage({
            action = 'error',
            message = tostring(data)
        })
        print('[CM-CHARACTERS] Creation failed: ' .. tostring(data))
    end
end)

RegisterNUICallback('createCharacter', function(data, cb)
    if isCreating then
        cb('ok')
        return
    end
    
    isCreating = true
    print('[CM-CHARACTERS] createCharacter: ' .. json.encode(data))
    
    TriggerServerEvent('cm-characters:server:create', currentAccountId, currentSlot, {
        firstName = data.firstName,
        lastName = data.lastName,
        dob = data.dob,
        gender = data.gender
    })
    
    cb('ok')
end)

RegisterNUICallback('closeCreator', function(data, cb)
    display = false
    -- Returning from creator goes back to selector, so keep NUI focus.
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showApp' })
    TriggerServerEvent('cm-characters:server:getSlots')
    cb('ok')
end)