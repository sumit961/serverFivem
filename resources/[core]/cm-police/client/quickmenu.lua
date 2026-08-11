-- cm-police quick actions menu (J key). Purely a faster input path onto
-- functions radar.lua/spikes.lua already expose globally and already
-- validate server-side -- this file adds no new gameplay logic of its own,
-- same reasoning as X's direct cuff/uncuff key in cuffs.lua.

local function notify(message, kind)
    PoliceNotify(message, kind)
end

-- Any real Police member can invoke the command, but an off-duty member is
-- directed to the wardrobe because clothing is now the only duty entry.
local function canUseQuickMenu()
    local state = LocalPlayer.state.cmPolice
    if type(state) == 'table' then return true, false end
    if GetResourceState('cm-law') == 'started' then
        TriggerEvent('cm-law:client:openQuickMenu')
        return false, true
    end
    return false, true
end

RegisterCommand('policequickmenu', function()
    local allowed = canUseQuickMenu()
    if not allowed then return end
    local state = LocalPlayer.state.cmPolice
    local permissions = state.permissions or {}
    local onDuty = state.onDuty == true
    local canRadarOrSpike = onDuty and (state.isLeader == true or permissions['police.radar'] == true or permissions['police.spike'] == true)
    local canBarricade = onDuty and (state.isLeader == true or permissions['police.barricade'] == true)
    local canClamp = onDuty and (state.isLeader == true or permissions['police.clamp'] == true)
    local canK9 = onDuty and (state.isLeader == true or permissions['police.k9'] == true)

    local options = {}

    if onDuty then
        options[#options + 1] = {
            title = 'Go Off Duty',
            description = 'End your shift',
            icon = 'right-from-bracket',
            onSelect = function()
                local ok, message = lib.callback.await('cm-police:server:toggleDuty', false, nil, sex())
                notify(message, ok and 'success' or 'error')
                if ok then TriggerEvent('cm-inventory:client:restoreEquippedClothing') end
            end,
        }
        options[#options + 1] = {
            title = (LocalPlayer.state.cmPolice.radioStatus == '10-6') and 'Status: 10-6 (Busy)' or 'Status: 10-8 (Available)',
            description = 'Toggle your radio status for other officers',
            icon = 'satellite-dish',
            onSelect = function()
                local nextStatus = (LocalPlayer.state.cmPolice.radioStatus == '10-6') and '10-8' or '10-6'
                local ok, message = lib.callback.await('cm-police:server:setRadioStatus', false, nextStatus)
                notify(message, ok and 'success' or 'error')
            end,
        }
        options[#options + 1] = {
            title = 'Request Backup',
            description = 'Alert all on-duty units to your location',
            icon = 'triangle-exclamation',
            onSelect = function()
                PoliceRequestBackup('normal', false)
            end,
        }
        options[#options + 1] = {
            title = 'Urgent Backup',
            description = 'Send a high-priority alert to all on-duty units',
            icon = 'tower-broadcast',
            onSelect = function()
                PoliceRequestBackup('urgent', true)
            end,
        }
        options[#options + 1] = {
            title = 'Panic Button',
            description = 'Emergency alert with a flashing GPS marker',
            icon = 'bell',
            onSelect = function()
                PoliceRequestBackup('panic', true)
            end,
        }
    else
        return notify('Wear a complete Police outfit at the wardrobe to start duty.', 'inform')
    end

    if canRadarOrSpike then
        options[#options + 1] = {
            title = IsPoliceRadarActive() and 'Speed Radar: ON' or 'Speed Radar: OFF',
            description = 'Toggle the handheld speed radar',
            icon = 'gauge-high',
            onSelect = function() PoliceToggleRadar() end,
        }
        options[#options + 1] = {
            title = 'Deploy Spike Strip',
            description = 'Preview a placement, then press E to drop it',
            icon = 'road-barrier',
            onSelect = function() PoliceDeploySpike() end,
        }
        options[#options + 1] = {
            title = 'Recall My Spike Strip',
            description = 'Pick up your currently deployed strip',
            icon = 'broom',
            -- Confirmed here (menu path) but not from /recallspikes -- that
            -- command stays an instant power-user shortcut, matching how
            -- /policecuffkey's X-key already bypasses menu confirmation.
            onSelect = function()
                if PoliceConfirm('Recall Spike Strip', 'Pick up your currently deployed spike strip?', 'Recall', 'Cancel') then
                    PoliceRecallSpikes()
                end
            end,
        }
    end

    if canBarricade then
        options[#options + 1] = {
            title = 'Deploy Barricade',
            description = 'Preview a placement, then press E to drop it',
            icon = 'road-barrier',
            onSelect = function() PoliceDeployBarricade() end,
        }
        options[#options + 1] = {
            title = 'Recall My Barricade(s)',
            description = 'Pick up your currently deployed barricades',
            icon = 'broom',
            onSelect = function()
                if PoliceConfirm('Recall Barricades', 'Pick up your currently deployed barricades?', 'Recall', 'Cancel') then
                    PoliceRecallBarricades()
                end
            end,
        }
    end

    if canClamp then
        options[#options + 1] = {
            title = 'Toggle Wheel Clamp',
            description = 'Clamp or unclamp the nearest vehicle',
            icon = 'lock',
            onSelect = function() PoliceToggleClamp() end,
        }
    end

    if canK9 then
        options[#options + 1] = {
            title = 'K9 Commands',
            description = PoliceIsK9Deployed() and 'Control your deployed K9' or 'Deploy and control a K9 companion',
            icon = 'dog',
            onSelect = function() PoliceK9Menu() end,
        }
    end

    PoliceQuickMenu('Police Quick Actions', options)
end, false)

RegisterNetEvent('cm-police:client:openLawQuickMenu', function(state)
    if type(state) ~= 'table' or state.onDuty ~= true then return end
    local permissions = type(state.permissions) == 'table' and state.permissions or {}
    local leader = state.isLeader == true
    local options = {
        { title = 'Go Off Duty', description = 'End your shift and restore personal clothing', icon = 'right-from-bracket',
          onSelect = function() TriggerEvent('cm-law:client:quickMenuOffDuty') end },
    }
    if leader or permissions['law.mdt'] == true then
        table.insert(options, 1, { title = 'Shared MDT', description = 'Open the cross-agency legal terminal', icon = 'laptop-file',
            onSelect = function() TriggerEvent('cm-law:client:openMdt') end })
    end
    if leader or permissions['law.receive_dispatch'] == true then
        options[#options + 1] = { title = 'Dispatch', description = 'Open shared legal dispatch', icon = 'tower-broadcast',
            onSelect = function() TriggerEvent('cm-law:client:openDispatch') end }
        options[#options + 1] = { title = 'Request Backup', description = 'Alert available legal units', icon = 'people-group',
            onSelect = function() TriggerEvent('cm-law:client:quickMenuAlert', 'backup') end }
        options[#options + 1] = { title = 'Panic Button', description = 'Send an urgent officer-in-distress alert', icon = 'triangle-exclamation',
            onSelect = function() TriggerEvent('cm-law:client:quickMenuAlert', 'panic') end }
    end
    if leader or permissions['law.spike'] == true then
        options[#options + 1] = { title = 'Deploy Spike Strip', description = 'Preview placement, then press E', icon = 'road-barrier', onSelect = PoliceDeploySpike }
        options[#options + 1] = { title = 'Recall My Spike Strip', description = 'Pick up your deployed strips', icon = 'broom',
            onSelect = function()
                if PoliceConfirm('Recall Spike Strips', 'Pick up your deployed spike strips?', 'Recall', 'Cancel') then PoliceRecallSpikes() end
            end }
    end
    if leader or permissions['law.barricade'] == true then
        options[#options + 1] = { title = 'Deploy Barricade', description = 'Preview placement, then press E', icon = 'road-barrier', onSelect = PoliceDeployBarricade }
        options[#options + 1] = { title = 'Recall My Barricades', description = 'Pick up your deployed barricades', icon = 'broom',
            onSelect = function()
                if PoliceConfirm('Recall Barricades', 'Pick up your deployed barricades?', 'Recall', 'Cancel') then PoliceRecallBarricades() end
            end }
    end
    PoliceQuickMenu((state.label or state.shortLabel or 'Legal Organization') .. ' Quick Actions', options)
end)
