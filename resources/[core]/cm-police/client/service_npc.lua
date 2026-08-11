local ServiceLocation
local ServicePed
local promptVisible = false

local function notify(message, kind) PoliceNotify(message, kind) end

local function spawnServiceNpc()
    if ServicePed and DoesEntityExist(ServicePed) then DeleteEntity(ServicePed) end
    ServicePed = nil
    if not ServiceLocation then return end
    local model = GetHashKey(Config.ServiceNpc.Model or 's_f_y_cop_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    ServicePed = CreatePed(4, model, ServiceLocation.x, ServiceLocation.y, ServiceLocation.z - 1.0, ServiceLocation.heading or 0.0, false, false)
    SetEntityInvincible(ServicePed, true)
    FreezeEntityPosition(ServicePed, true)
    SetBlockingOfNonTemporaryEvents(ServicePed, true)
    TaskStartScenarioInPlace(ServicePed, Config.ServiceNpc.IdleScenario or 'WORLD_HUMAN_CLIPBOARD', 0, true)
    pcall(SetFacialIdleAnimOverride, ServicePed, 'mood_normal_1', 0)
    SetModelAsNoLongerNeeded(model)
end

local function greeting()
    local settings = Config.ServiceNpc.Greetings or {}
    local wanted = 0
    pcall(function() wanted = exports[Config.PlayerDataResource]:GetWantedStars() end)
    if wanted > 0 then return settings.wanted or 'Remain calm. I can process your voluntary surrender.' end
    local police = LocalPlayer.state.cmPolice
    if type(police) == 'table' and police.onDuty == true then return settings.officer or 'Welcome back, officer.' end
    local hour = GetClockHours()
    if hour < 12 then return settings.morning or 'Good morning. How can I help you?' end
    if hour < 18 then return settings.afternoon or 'Good afternoon. How can I help you?' end
    return settings.evening or 'Good evening. How can I help you?'
end

local function requestAssistance()
    local ok, message = lib.callback.await('cm-police:server:requestNpcService', false)
    if ok and type(PoliceCinematicSound) == 'function' then PoliceCinematicSound('radio', ServicePed) end
    PoliceNpcDialogueRespond(ok and 'A unit has been notified.' or (message or 'No unit could be notified.'), ok and 'success' or 'error', PoliceCinematicResponseDuration())
    return false
end

local function surrender()
    local preview, reason = lib.callback.await('cm-police:server:surrenderPreview', false)
    if not preview then PoliceNpcDialogueRespond('You have no active warrants.', 'inform', PoliceCinematicResponseDuration()); return false end
    if not PoliceConfirm('Voluntary Surrender', ('Surrender for %d wanted star(s) and serve %d minutes?'):format(preview.stars, preview.minutes), 'Surrender', 'Cancel') then PoliceNpcDialogueRestoreChoices(); return false end
    local ok, message = lib.callback.await('cm-police:server:surrenderAtNpc', false)
    PoliceNpcDialogueRespond(ok and 'Your surrender has been accepted.' or (message or 'Your surrender could not be processed.'), ok and 'success' or 'error', PoliceCinematicResponseDuration())
    return false
end

local function surrenderWeapons()
    local preview, reason = lib.callback.await('cm-police:server:confiscationPreview', false)
    if not preview then PoliceNpcDialogueRespond(reason or 'The weapons check is unavailable.', 'error', PoliceCinematicResponseDuration()); return false end
    if preview.licensed then PoliceNpcDialogueRespond('Your firearms license is active. Nothing must be surrendered.', 'inform', PoliceCinematicResponseDuration()); return false end
    if preview.total < 1 then PoliceNpcDialogueRespond('No unlicensed firearms were found.', 'inform', PoliceCinematicResponseDuration()); return false end
    PoliceNpcDialogueRespond('Place your weapons on the counter.', 'inform'); Wait(1100)
    local list = table.concat(preview.weapons or {}, ', ')
    if #list > 240 then list = list:sub(1, 237) .. '...' end
    if not PoliceConfirm('Surrender Illegal Weapons', ('Permanently confiscate %d firearm item(s): %s?'):format(preview.total, list), 'Confiscate', 'Cancel') then PoliceNpcDialogueRestoreChoices(); return false end
    local ok, message = lib.callback.await('cm-police:server:confiscateIllegalWeapons', false, preview.token)
    PoliceNpcDialogueRespond(ok and 'Your weapons are now in Police custody.' or (message or 'The weapons could not be surrendered.'), ok and 'success' or 'error', PoliceCinematicResponseDuration())
    return false
end

CreateThread(function()
    ServiceLocation = lib.callback.await('cm-police:server:serviceNpcLocation', false)
    spawnServiceNpc()
    while true do
        local wait = 1000
        if ServiceLocation then
            local distance = #(GetEntityCoords(PlayerPedId()) - vector3(ServiceLocation.x, ServiceLocation.y, ServiceLocation.z))
            if distance <= (Config.ServiceNpc.DrawDistance or 18.0) then
                wait = 0
                PoliceDrawNpcName(ServiceLocation, Config.ServiceNpc.Name or 'Officer Morgan')
                if distance <= (Config.ServiceNpc.InteractDistance or 2.5) then
                    if not promptVisible then PoliceShowNpcInteraction('service_npc', Config.ServiceNpc.Name, Config.ServiceNpc.Role, 'shield-halved'); promptVisible = true end
                    if IsControlJustPressed(0, 38) then
                        PoliceHideNpcInteraction('service_npc'); promptVisible = false
                        PoliceOpenNpcDialogue(ServicePed, { owner = 'service_npc', name = Config.ServiceNpc.Name, role = Config.ServiceNpc.Role,
                            quote = greeting(),
                            continueLabel = 'Show me Police services', deferChoices = true, choices = {
                                { id = 'assistance', label = 'Request Police Assistance', description = 'Notify every on-duty officer that you need service here.' },
                                { id = 'surrender', label = 'Voluntary Surrender', description = 'Turn yourself in for your active wanted level.' },
                                { id = 'weapons', label = 'Surrender Illegal Weapons', description = 'Hand over firearms held without an active license.' },
                            } }, { assistance = requestAssistance, surrender = surrender, weapons = surrenderWeapons })
                    end
                elseif promptVisible then PoliceHideNpcInteraction('service_npc'); promptVisible = false end
            elseif promptVisible then PoliceHideNpcInteraction('service_npc'); promptVisible = false end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('cm-police:client:serviceNpcUpdated', function(location)
    ServiceLocation = type(location) == 'table' and location or nil
    if not ServiceLocation and promptVisible then PoliceHideNpcInteraction('service_npc'); promptVisible = false end
    spawnServiceNpc()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if promptVisible then PoliceHideNpcInteraction('service_npc') end
    if ServicePed and DoesEntityExist(ServicePed) then DeleteEntity(ServicePed) end
end)
