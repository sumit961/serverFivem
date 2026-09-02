local PAGE = 'police_org'
local SearchResult, SearchTarget

local function registerPage()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    exports[Config.PlayerDataResource]:RegisterInteractionPage({ id = PAGE, label = 'Organization', icon = 'shield-alt', order = 35, emptyLabel = 'No Police actions available' })
end

local function add(id, label, order)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, { id = id, action = id, label = label, icon = 'shield-alt', type = 'extension', order = order, close = true })
end

local function addSearchRow(id, label, description, order, icon)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
        id = id, label = label, description = description, icon = icon or 'shield-alt',
        type = 'noop', order = order, close = false,
    })
end

local function listText(items)
    if type(items) ~= 'table' or #items == 0 then return 'None found' end
    return table.concat(items, ', ')
end

RegisterNetEvent('cm-police:client:searchPlayer', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local result, failure = lib.callback.await('cm-police:server:searchPlayer', false, targetServerId)
    if type(result) ~= 'table' then return PoliceNotify(failure or 'Player search failed.', 'error') end
    SearchResult, SearchTarget = result, targetServerId
    rebuild(targetServerId)
    TriggerEvent('cm-playerdata:client:refreshInteractionMenu')
end)

-- Same underlying cm-playerdata extension-interaction dispatch as add()
-- above, but routed through 'clientEvent' first so this file gets a chance
-- to show PoliceConfirm before the server event fires -- matches the F7
-- dashboard's equivalent Remove/Demote buttons, which are already
-- confirm-gated (showConfirmOverlay in html/app.js).
local function addConfirm(id, label, order, confirmTitle, confirmMessage)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
        id = id, action = id, label = label, icon = 'shield-alt', order = order, close = true,
        type = 'clientEvent', event = 'cm-police:client:confirmExtensionInteraction',
        payload = { confirmTitle = confirmTitle, confirmMessage = confirmMessage },
    })
end

RegisterNetEvent('cm-police:client:confirmExtensionInteraction', function(targetServerId, action, payload)
    payload = type(payload) == 'table' and payload or {}
    if not PoliceConfirm(payload.confirmTitle or 'Confirm', payload.confirmMessage or 'Are you sure?', 'Confirm', 'Cancel') then return end
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, action, {})
end)

RegisterNetEvent('cm-police:client:bookingIntake', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local ok, preview = lib.callback.await('cm-police:server:bookingPreview', false, targetServerId)
    if ok ~= true or type(preview) ~= 'table' then
        return PoliceNotify(tostring(preview or 'Booking is not available.'), 'error')
    end
    if not PoliceConfirm('Confirm Prison Booking',
        ('Send this suspect to jail for %d minutes based on %d wanted star%s?\nReason: %s'):format(
            preview.minutes, preview.stars, preview.stars == 1 and '' or 's', tostring(preview.reason or 'Wanted')),
        'Confirm Booking', 'Cancel') then
        lib.callback.await('cm-police:server:cancelBookingReservation', false, preview.operationToken)
        return
    end
    local cinematicPlayed = PolicePlayBookingIntakeCinematic(targetServerId, preview) == true
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, 'police_book', {
        operationToken = preview.operationToken, cinematicPlayed = cinematicPlayed,
    })
end)

function rebuild(targetServerId)
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    exports[Config.PlayerDataResource]:ClearInteractionOptions(PAGE)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then SearchResult, SearchTarget = nil, nil; return end
    local mine, theirs = LocalPlayer.state.cmPolice, Player(targetServerId).state.cmPolice
    if mine == false then mine = nil end
    if theirs == false then theirs = nil end
    if not mine then return end
    if mine.suspended == true then return end
    local permissions = mine.permissions or {}
    if SearchResult and SearchTarget == targetServerId then
        addSearchRow('search_license', 'Firearms licence', SearchResult.firearmsLicensed and 'ACTIVE' or 'NOT ACTIVE', 1, 'license')
        addSearchRow('search_licensed_weapons', 'Licensed weapons', listText(SearchResult.licensedWeapons), 2, 'shield-alt')
        addSearchRow('search_unlicensed_weapons', 'Unlicensed weapons', listText(SearchResult.unlicensedWeapons), 3, 'shield-alt')
        addSearchRow('search_ammunition', 'Ammunition', listText(SearchResult.ammunition), 4, 'shield-alt')
        addSearchRow('search_illegal_items', 'Illegal items', listText(SearchResult.illegalItems), 5, 'shield-alt')
        return
    end
    -- Cuffing/escort works on any nearby player, not just other Police
    -- staff, so this must be registered before the stranger early-return
    -- below (same reasoning as EMS's stretcher/medicine-sale options).
    if mine.onDuty == true and not IsPedInAnyVehicle(PlayerPedId(), false)
        and (mine.isLeader or permissions['police.cuff']) then
        local targetState = Player(targetServerId).state
        local targetCuffed = targetState.cmCuffed == true
        local targetEscortedBy = targetState.cmEscortedBy
        local mySrc = GetPlayerServerId(PlayerId())
        if not targetCuffed then
            add('police_cuff', 'Cuff', 11)
        else
            add('police_uncuff', 'Uncuff', 11)
            exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
                id = 'police_search', label = 'Search Player', icon = 'shield-alt', type = 'clientEvent',
                event = 'cm-police:client:searchPlayer', order = 15, close = false,
            })
            if targetEscortedBy == mySrc then
                add('police_escort_release', 'Release', 12)
                add('police_put_in_vehicle', 'Put in Vehicle', 13)
                add('police_take_out_vehicle', 'Take Out of Vehicle', 14)
            elseif not (type(targetEscortedBy) == 'number' and targetEscortedBy > 0) then
                add('police_escort_grab', 'Grab', 12)
            end
        end
    end
    -- Booking -- same "works on any nearby player" reasoning as cuffing
    -- above, so it must also sit before the stranger early-return. Once
    -- booked, the suspect is handed to cm-prison (see server/booking.lua).
    -- Release is sentence/admin controlled, not a normal officer G-menu action.
    if mine.onDuty == true and (mine.isLeader or permissions['police.book']) then
        local targetState = Player(targetServerId).state
        if targetState.cmCuffed == true then
            exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
                id = 'police_book', action = 'police_book', label = 'Book by Wanted Stars', icon = 'shield-alt',
                type = 'clientEvent', event = 'cm-police:client:bookingIntake', order = 16, close = true,
            })
        end
    end
    if not theirs then
        if mine.isLeader or permissions['police.invite'] then
            addConfirm('police_invite', 'Invite to Police', 10, 'Police Invitation', 'Invite the selected nearby player to Police?')
        end
        return
    end
    if theirs.isLeader or (tonumber(mine.tier) or 0) <= (tonumber(theirs.tier) or 0) then return end
    if mine.isLeader or permissions['police.promote'] then add('police_promote', 'Promote Police Member', 20) end
    if mine.isLeader or permissions['police.demote'] then
        addConfirm('police_demote', 'Demote Police Member', 30, 'Demote Member', 'Demote this member to the next rank down?')
    end
    if mine.isLeader or permissions['police.kick'] then
        addConfirm('police_kick', 'Remove from Police', 40, 'Remove Member', 'Remove this member from Police? This cannot be undone.')
    end
end

RegisterNetEvent('cm-playerdata:client:interactionTargetChanged', rebuild)
AddEventHandler('cm-playerdata:client:interactionRegistryReady', function() registerPage(); rebuild(nil) end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == Config.PlayerDataResource then Wait(300); registerPage(); rebuild(nil) end
end)
