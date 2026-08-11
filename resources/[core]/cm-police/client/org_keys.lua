-- One physical key contract for every configured organization. cm-police
-- owns these mappings so several resources never race on J/F7/TAB.

local function organizationKind()
    local memberships = {
        { kind = 'police', state = LocalPlayer.state.cmPolice },
        { kind = 'law', state = LocalPlayer.state.cmLegalOrg },
        { kind = 'ems', state = LocalPlayer.state.cmEms },
    }
    -- A stale secondary membership must not steal the shared key from the
    -- organization in which the player is currently serving.
    for _, membership in ipairs(memberships) do
        if type(membership.state) == 'table' and membership.state.onDuty == true then
            return membership.kind
        end
    end
    for _, membership in ipairs(memberships) do
        if type(membership.state) == 'table' then return membership.kind end
    end
    return nil
end

RegisterCommand('cmorgquickmenu', function()
    local kind = organizationKind()
    if kind == 'police' then ExecuteCommand('policequickmenu')
    elseif kind == 'law' then TriggerEvent('cm-law:client:openQuickMenu')
    elseif kind == 'ems' then TriggerEvent('cm-ems:client:openQuickMenu') end
end, false)
RegisterKeyMapping('cmorgquickmenu', 'Organization: Quick actions', 'keyboard', 'J')

RegisterCommand('cmorgdashboard', function()
    local kind = organizationKind()
    if kind == 'police' then TriggerEvent('cm-police:client:openDashboard')
    elseif kind == 'law' then TriggerEvent('cm-law:client:openDashboard')
    elseif kind == 'ems' then TriggerEvent('cm-ems:client:openDashboard') end
end, false)
RegisterKeyMapping('cmorgdashboard', 'Organization: Main dashboard', 'keyboard', 'F7')

RegisterCommand('cmorgmdt', function()
    local kind = organizationKind()
    if kind == 'police' then TriggerEvent('cm-police:client:toggleMdt')
    elseif kind == 'law' then TriggerEvent('cm-law:client:openMdt')
    elseif kind == 'ems' then TriggerEvent('cm-ems:client:openMedicalRecords') end
end, false)
RegisterKeyMapping('cmorgmdt', 'Organization: MDT or records terminal', 'keyboard', 'TAB')

RegisterCommand('cmorgdispatch', function()
    local kind = organizationKind()
    if kind == 'police' then TriggerEvent('cm-police:client:openDispatch')
    elseif kind == 'law' then TriggerEvent('cm-law:client:openDispatch')
    elseif kind == 'ems' then ExecuteCommand('emsdispatchmenu') end
end, false)
RegisterKeyMapping('cmorgdispatch', 'Organization: Dispatch', 'keyboard', 'F10')
