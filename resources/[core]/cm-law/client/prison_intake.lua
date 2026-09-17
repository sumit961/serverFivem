local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end

local function draggedSuspect()
    local me, mySrc = PlayerId(), GetPlayerServerId(PlayerId())
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local src = GetPlayerServerId(player)
            local state = Player(src).state
            if state.cmCuffed == true and state.cmEscortedBy == mySrc then return src end
        end
    end
end

RegisterNetEvent('cm-law:client:sharedPrisonIntakePrompt', function(visible, name, role)
    if type(PoliceShowNpcInteraction) ~= 'function' then return end
    if visible then
        PoliceShowNpcInteraction('shared_prison_intake', name or 'Officer Daniels', role or 'Prison Intake Officer', 'building-shield')
    else
        PoliceHideNpcInteraction('shared_prison_intake')
    end
end)

RegisterNetEvent('cm-law:client:sharedPrisonIntake', function(npc)
    if not npc or not DoesEntityExist(npc) then return end
    local target = draggedSuspect()
    if not target then return notify('Drag a cuffed suspect to the shared prison intake officer first.', 'error') end
    local legal, police = LocalPlayer.state.cmLegalOrg, LocalPlayer.state.cmPolice
    local eventName, label
    if type(legal) == 'table' and legal.onDuty == true and legal.suspended ~= true then
        eventName, label = 'cm-law:client:bookingIntake', legal.shortLabel or legal.label or 'Legal Services'
    elseif type(police) == 'table' and police.onDuty == true and police.suspended ~= true then
        eventName, label = 'cm-police:client:bookingIntake', 'Police'
    else
        return notify('You must be on duty with booking permission to use prison intake.', 'error')
    end
    PoliceHideNpcInteraction('shared_prison_intake')
    local continue = function() TriggerEvent(eventName, target) end
    if type(PoliceOpenNpcDialogue) == 'function' then
        PoliceOpenNpcDialogue(npc, {
            owner = 'shared_prison_intake', name = 'Officer Daniels', role = 'Prison Intake Officer',
            quote = ('I can process this %s booking and transfer the suspect into the shared prison.'):format(label),
            continueLabel = 'Review and confirm booking',
        }, continue)
    else
        continue()
    end
end)
