local config, npc, prompt = nil, nil, false
local function canUse()
    local legal = LocalPlayer and LocalPlayer.state and LocalPlayer.state.cmLegalOrg
    local police = LocalPlayer and LocalPlayer.state and LocalPlayer.state.cmPolice
    return (type(legal) == 'table' and legal.onDuty == true and legal.suspended ~= true)
        or (type(police) == 'table' and police.onDuty == true and police.suspended ~= true)
end
local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end
local function hidePrompt()
    if not prompt then return end
    prompt = false
    if GetResourceState('cm-law') == 'started' then
        TriggerEvent('cm-law:client:sharedPrisonIntakePrompt', false)
    end
end
local function deleteNpc()
    hidePrompt()
    if npc and DoesEntityExist(npc) then DeleteEntity(npc) end
    npc = nil
end
local function refresh()
    deleteNpc()
    config = lib.callback.await('cm-prison:server:configuration', false)
    local intake = config and config.intake
    if type(intake) ~= 'table' or not tonumber(intake.x) then return end
    local model = GetHashKey((PrisonConfig.Intake or {}).model or 's_m_m_prisguard_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(model) then return end
    npc = CreatePed(4, model, intake.x, intake.y, intake.z - 1.0, intake.heading or 0.0, false, true)
    if npc and npc ~= 0 and DoesEntityExist(npc) then
        FreezeEntityPosition(npc, true); SetEntityInvincible(npc, true); SetBlockingOfNonTemporaryEvents(npc, true)
    else npc = nil end
    SetModelAsNoLongerNeeded(model)
end
local function drawName(location)
    SetDrawOrigin(location.x, location.y, location.z + 1.15, 0)
    SetTextFont(4); SetTextScale(0.0, 0.31); SetTextCentre(true); SetTextOutline(); SetTextColour(255,255,255,245)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName((PrisonConfig.Intake or {}).name or 'Prison Intake Officer')
    EndTextCommandDisplayText(0.0, 0.0); ClearDrawOrigin()
end
local function interact()
    if GetResourceState('cm-law') == 'started' then
        TriggerEvent('cm-law:client:sharedPrisonIntake', npc)
    else notify('The legal booking system is unavailable.', 'error') end
end
CreateThread(function()
    Wait(1500); refresh()
    while true do
        local wait = 1000
        local intake = config and config.intake
        if npc and DoesEntityExist(npc) and type(intake) == 'table' then
            local distance = #(GetEntityCoords(PlayerPedId()) - vector3(intake.x, intake.y, intake.z))
            if distance <= (tonumber((PrisonConfig.Intake or {}).drawDistance) or 18.0) then
                wait = 0; drawName(intake)
                if canUse() and distance <= (tonumber((PrisonConfig.Intake or {}).interactDistance) or 2.5) then
                    if not prompt then prompt = true; TriggerEvent('cm-law:client:sharedPrisonIntakePrompt', true, (PrisonConfig.Intake or {}).name, (PrisonConfig.Intake or {}).role) end
                    if IsControlJustPressed(0, 38) then interact(); Wait(500) end
                else hidePrompt() end
            else hidePrompt() end
        else hidePrompt() end
        Wait(wait)
    end
end)
RegisterNetEvent('cm-prison:client:configurationUpdated', refresh)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then deleteNpc() end end)
