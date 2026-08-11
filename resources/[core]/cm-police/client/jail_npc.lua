local npc, location, refreshing
local promptVisible = false

function PoliceGetJailIntakePed()
    return npc and DoesEntityExist(npc) and npc or 0
end

local function deleteNpc()
    if promptVisible then PoliceHideNpcInteraction('jail_intake_npc'); promptVisible = false end
    if npc and DoesEntityExist(npc) then DeleteEntity(npc) end
    npc = nil
end

local function refresh()
    if refreshing then return end
    refreshing = true
    location = lib.callback.await('cm-police:server:jailNpcLocation', false)
    deleteNpc()
    if type(location) ~= 'table' then refreshing = false return end
    local model = `s_m_m_prisguard_01`
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(model) then refreshing = false return end
    npc = CreatePed(4, model, location.x, location.y, location.z - 1.0, location.heading or 0.0, false, true)
    if npc and npc ~= 0 and DoesEntityExist(npc) then
        FreezeEntityPosition(npc, true); SetEntityInvincible(npc, true); SetBlockingOfNonTemporaryEvents(npc, true)
    else
        npc = nil
    end
    SetModelAsNoLongerNeeded(model)
    refreshing = false
end

local function draggedSuspect()
    local mySrc = GetPlayerServerId(PlayerId())
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local src = GetPlayerServerId(playerId)
            local state = Player(src).state
            if state.cmCuffed == true and state.cmEscortedBy == mySrc then return src end
        end
    end
end

CreateThread(function()
    Wait(1500); refresh()
    local nextRecovery = GetGameTimer() + 10000
    while true do
        local wait = 1000
        if npc and DoesEntityExist(npc) then
            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(npc))
            local settings = Config.JailNpc or {}
            if distance <= (tonumber(settings.DrawDistance) or 6.0) then
                wait = 0
                PoliceDrawNpcName(location, settings.Name or 'Officer Daniels')
                if distance <= (tonumber(settings.InteractDistance) or 2.5) then
                    if not promptVisible then
                        PoliceShowNpcInteraction('jail_intake_npc', settings.Name or 'Officer Daniels',
                            settings.Role or 'Prison Intake Officer', 'building-shield')
                        promptVisible = true
                    end
                    if IsControlJustPressed(0, 38) then
                        local allowed, refusal = lib.callback.await('cm-police:server:restrictedNpcAccess', false, 'jail_intake_npc')
                        if allowed ~= true then
                            PoliceHideNpcInteraction('jail_intake_npc'); promptVisible = false
                            PoliceOpenNpcDialogue(npc, {
                                owner = 'jail_intake_npc',
                                name = settings.Name or 'Officer Daniels',
                                role = settings.Role or 'Prison Intake Officer',
                                quote = refusal or 'Intake is restricted to on-duty Police officers.',
                                continueLabel = 'Leave',
                            }, nil)
                            Wait(500)
                            goto continue_loop
                        end
                        local target = draggedSuspect()
                        if target then
                            PoliceHideNpcInteraction('jail_intake_npc'); promptVisible = false
                            PoliceOpenNpcDialogue(npc, {
                                owner = 'jail_intake_npc',
                                name = settings.Name or 'Officer Daniels',
                                role = settings.Role or 'Prison Intake Officer',
                                quote = 'I can process this suspect using their active MDT wanted stars and assigned sentence.',
                                continueLabel = 'Review and confirm booking',
                            }, function()
                                TriggerEvent('cm-police:client:bookingIntake', target)
                            end)
                        else PoliceNotify('Drag a cuffed suspect to the intake officer first.', 'error') end
                    end
                elseif promptVisible then PoliceHideNpcInteraction('jail_intake_npc'); promptVisible = false end
            elseif promptVisible then PoliceHideNpcInteraction('jail_intake_npc'); promptVisible = false end
        end
        if (not npc or not DoesEntityExist(npc)) and GetGameTimer() >= nextRecovery then
            nextRecovery = GetGameTimer() + 10000
            refresh()
        end
        ::continue_loop::
        Wait(wait)
    end
end)

RegisterNetEvent('cm-police:client:jailNpcUpdated', refresh)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then deleteNpc() end end)
