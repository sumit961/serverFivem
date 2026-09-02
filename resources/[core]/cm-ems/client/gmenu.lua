local PAGE = 'ems_org'

local function registerPage()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    exports[Config.PlayerDataResource]:RegisterInteractionPage({ id = PAGE, label = 'Organization', icon = 'briefcase-medical', order = 34, emptyLabel = 'No EMS actions available' })
end

local function add(id, label, order)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, { id = id, action = id, label = label, icon = 'briefcase-medical', type = 'extension', order = order, close = true })
end

local function addInvite(label)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
        id = 'ems_invite', action = 'ems_invite', label = label, icon = 'briefcase-medical', order = 10, close = true,
        type = 'clientEvent', event = 'cm-ems:client:confirmInvite',
    })
end

RegisterNetEvent('cm-ems:client:confirmInvite', function(targetServerId)
    local result = lib.alertDialog({
        header = 'EMS Invitation', content = 'Invite the selected nearby player to EMS?',
        centered = true, cancel = true, labels = { confirm = 'Send Invite', cancel = 'Cancel' },
    })
    if result == 'confirm' then TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, 'ems_invite', {}) end
end)

local function rebuild(targetServerId)
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    exports[Config.PlayerDataResource]:ClearInteractionOptions(PAGE)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local mine, theirs = LocalPlayer.state.cmEms, Player(targetServerId).state.cmEms
    if mine == false then mine = nil end
    if theirs == false then theirs = nil end
    if not mine then return end
    if mine.suspended == true then return end
    local permissions = mine.permissions or {}
    if mine.onDuty == true and (mine.isLeader or permissions['ems.treat_player']) then
        add('ems_stretcher_place', 'Place on Stretcher', 5)
        add('ems_stretcher_remove', 'Remove from Stretcher', 6)
        if (Config.Patch or {}).allowDirectAmbulanceLoad == true then
            local targetPlayer = GetPlayerFromServerId(targetServerId)
            local targetPed = targetPlayer ~= -1 and GetPlayerPed(targetPlayer) or 0
            if targetPed ~= 0 and IsPedInAnyVehicle(targetPed, false) then
                add('ems_ambulance_unload', 'Remove from Ambulance', 7)
            else
                add('ems_ambulance_load', 'Load into Ambulance', 7)
            end
        end
        add('ems_safe_treatment', 'Treat at Safe Area', 8)
    end
    -- Selling medicine works on any nearby player, not just other EMS staff,
    -- so this must be registered before the stranger early-return below.
    local medicineSales = Config.MedicineSales or {}
    if mine.onDuty == true and medicineSales.enabled ~= false
        and (mine.isLeader or permissions[tostring(medicineSales.permission or 'ems.sell_medicine')]) then
        for index, entry in ipairs(medicineSales.catalog or {}) do
            add(('ems_sell_%s'):format(tostring(entry.item)),
                ('Sell %s ($%d)'):format(tostring(entry.label or entry.item), math.floor(tonumber(entry.price) or 0)),
                11 + index)
        end
    end
    if not theirs then if mine.isLeader or permissions['ems.invite'] then addInvite('Invite to EMS') end; return end
    if theirs.isLeader or (tonumber(mine.tier) or 0) <= (tonumber(theirs.tier) or 0) then return end
    if mine.isLeader or permissions['ems.promote'] then add('ems_promote', 'Promote EMS Member', 20) end
    if mine.isLeader or permissions['ems.demote'] then add('ems_demote', 'Demote EMS Member', 30) end
    if mine.isLeader or permissions['ems.kick'] then add('ems_kick', 'Remove from EMS', 40) end
end

RegisterNetEvent('cm-playerdata:client:interactionTargetChanged', rebuild)
AddEventHandler('cm-playerdata:client:interactionRegistryReady', function() registerPage(); rebuild(nil) end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == Config.PlayerDataResource then Wait(300); registerPage(); rebuild(nil) end
end)
