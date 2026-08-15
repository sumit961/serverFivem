-- Neutral physical-key owner for every CM organization. Resource integrations
-- are deliberately soft: state bags decide routing before any event is sent.

local function organizationKind()
    local memberships = {
        { kind = 'police', state = LocalPlayer.state.cmPolice },
        { kind = 'law', state = LocalPlayer.state.cmLegalOrg },
        { kind = 'ems', state = LocalPlayer.state.cmEms },
    }
    for _, membership in ipairs(memberships) do
        if type(membership.state) == 'table' and membership.state.onDuty == true then
            return membership.kind
        end
    end
    for _, membership in ipairs(memberships) do
        if type(membership.state) == 'table' then return membership.kind end
    end
end

local function route(feature)
    local kind = organizationKind()
    if not kind then return end

    if feature == 'dashboard' then
        if kind == 'police' and GetResourceState('cm-police') == 'started' then TriggerEvent('cm-police:client:openDashboard')
        elseif kind == 'law' and GetResourceState('cm-law') == 'started' then TriggerEvent('cm-law:client:openDashboard')
        elseif kind == 'ems' and GetResourceState('cm-ems') == 'started' then TriggerEvent('cm-ems:client:openDashboard') end
    elseif feature == 'dispatch' then
        if kind == 'police' and GetResourceState('cm-police') == 'started' then TriggerEvent('cm-police:client:openDispatch')
        elseif kind == 'law' and GetResourceState('cm-law') == 'started' then TriggerEvent('cm-law:client:openDispatch')
        elseif kind == 'ems' and GetResourceState('cm-ems') == 'started' then ExecuteCommand('emsdispatchmenu') end
    elseif feature == 'records' then
        if kind == 'police' and GetResourceState('cm-police') == 'started' then TriggerEvent('cm-police:client:toggleMdt')
        elseif kind == 'law' and GetResourceState('cm-law') == 'started' then TriggerEvent('cm-law:client:openMdt')
        elseif kind == 'ems' and GetResourceState('cm-ems') == 'started' then TriggerEvent('cm-ems:client:openMedicalRecords') end
    elseif feature == 'quick' then
        if kind == 'police' and GetResourceState('cm-police') == 'started' then ExecuteCommand('policequickmenu')
        elseif kind == 'law' and GetResourceState('cm-law') == 'started' then TriggerEvent('cm-law:client:openQuickMenu')
        elseif kind == 'ems' and GetResourceState('cm-ems') == 'started' then TriggerEvent('cm-ems:client:openQuickMenu') end
    end
end

RegisterCommand('cmorgdashboard', function() route('dashboard') end, false)
RegisterKeyMapping('cmorgdashboard', 'Organization: Main dashboard', 'keyboard', 'F6')

RegisterCommand('cmorgdispatch', function() route('dispatch') end, false)
RegisterKeyMapping('cmorgdispatch', 'Organization: Dispatch', 'keyboard', 'F9')

RegisterCommand('cmorgmdt', function() route('records') end, false)
RegisterKeyMapping('cmorgmdt', 'Organization: MDT or records terminal', 'keyboard', 'TAB')

RegisterCommand('cmorgquickmenu', function() route('quick') end, false)
RegisterKeyMapping('cmorgquickmenu', 'Organization: Quick actions', 'keyboard', 'J')
