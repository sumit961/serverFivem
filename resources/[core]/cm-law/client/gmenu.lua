-- cm-law G-menu integration. Ported from cm-police/client/gmenu.lua's
-- registration shape: cuffing/escort/vehicle transport/booking, plus
-- invite/promote/demote (server/main.lua's gMenuAction handler). No kick --
-- removing a member stays an F9 Staffing-tab-only action, unlike
-- cm-police's G-menu which offers police_kick too.

local PAGE = 'legal_org'
local SearchResult, SearchTarget

local function registerPage()
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    exports[Config.PlayerDataResource]:RegisterInteractionPage({ id = PAGE, label = 'Legal Org', icon = 'gavel', order = 36, emptyLabel = 'No Legal Org actions available' })
end

local function add(id, label, order)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, { id = id, action = id, label = label, icon = 'gavel', type = 'extension', order = order, close = true })
end

local function addSearchRow(id, label, description, order)
    exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
        id = id, label = label, description = description, icon = 'gavel', type = 'noop', order = order, close = false,
    })
end

local function listText(items)
    return type(items) == 'table' and #items > 0 and table.concat(items, ', ') or 'None found'
end

local function rebuild(targetServerId)
    if GetResourceState(Config.PlayerDataResource) ~= 'started' then return end
    exports[Config.PlayerDataResource]:ClearInteractionOptions(PAGE)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then SearchResult, SearchTarget = nil, nil; return end

    local mine = LocalPlayer.state.cmLegalOrg
    if mine == false or type(mine) ~= 'table' then return end
    if mine.suspended or mine.onDuty ~= true then return end
    local permissions = mine.permissions or {}
    local capabilities = mine.capabilities or {}
    if SearchResult and SearchTarget == targetServerId then
        addSearchRow('law_search_license', 'Firearms licence', SearchResult.firearmsLicensed
            and ('ACTIVE · ' .. tostring(SearchResult.firearmsLicenseNumber or 'number unavailable')) or 'NOT ACTIVE', 1)
        addSearchRow('law_search_licensed_weapons', 'Licensed weapons', listText(SearchResult.licensedWeapons), 2)
        addSearchRow('law_search_unlicensed_weapons', 'Unlicensed weapons', listText(SearchResult.unlicensedWeapons), 3)
        addSearchRow('law_search_licensed_ammo', 'Licensed ammunition', listText(SearchResult.licensedAmmunition), 4)
        addSearchRow('law_search_unlicensed_ammo', 'Unlicensed ammunition', listText(SearchResult.unlicensedAmmunition), 5)
        addSearchRow('law_search_illegal', 'Illegal items', listText(SearchResult.illegalItems), 6)
        if tonumber(SearchResult.confiscatableCount) and tonumber(SearchResult.confiscatableCount) > 0 then
            exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
                id = 'law_confiscate', label = 'Confiscate contraband', icon = 'gavel', type = 'clientEvent',
                event = 'cm-law:client:confiscatePlayer', order = 7, close = false,
            })
        end
        return
    end
    -- Decoupled on purpose: cuffing and membership management are separate
    -- capabilities (a manager isn't necessarily also cuff-authorized, and
    -- vice versa) -- only bail out entirely when NEITHER applies, so a
    -- manager without law.cuff still sees invite/promote/demote.
    local canCuff = capabilities.arrest ~= false and (mine.isLeader or permissions['law.cuff'] == true)
    local canSearch = capabilities.search ~= false and (mine.isLeader or permissions['law.search'] == true)
    local canManageMembers = mine.isLeader or permissions['law.manage_members'] == true
    if not canCuff and not canSearch and not canManageMembers then return end

    -- Cuffing/escort works on any nearby player, not just other org
    -- members, so no membership check on the target here.
    if (canCuff or canSearch) and not IsPedInAnyVehicle(PlayerPedId(), false) then
        local targetState = Player(targetServerId).state
        local targetCuffed = targetState.cmCuffed == true
        local targetEscortedBy = targetState.cmEscortedBy
        local mySrc = GetPlayerServerId(PlayerId())
        if not targetCuffed and canCuff then
            add('law_cuff', 'Cuff', 11)
        elseif targetCuffed then
            if canCuff then add('law_uncuff', 'Uncuff', 11) end
            if canSearch then
                exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
                    id = 'law_search', label = 'Search Player', icon = 'gavel', type = 'clientEvent',
                    event = 'cm-law:client:searchPlayer', order = 15, close = false,
                })
            end
            if canCuff and targetEscortedBy == mySrc then
                add('law_escort_release', 'Release', 12)
                add('law_put_in_vehicle', 'Put in Vehicle', 13)
                add('law_take_out_vehicle', 'Take Out of Vehicle', 14)
            elseif canCuff and not (type(targetEscortedBy) == 'number' and targetEscortedBy > 0) then
                add('law_escort_grab', 'Grab', 12)
            end
        end
    end

    -- Booking opens one charge-based intake form. The server resolves every
    -- charge id and calculates the sentence; the browser/client supplies no
    -- trusted labels or minutes.
    if canCuff and Player(targetServerId).state.cmCuffed == true then
        exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
            id = 'law_book_suspect', label = 'Book Suspect', icon = 'gavel', type = 'clientEvent',
            event = 'cm-law:client:bookingIntake', order = 20, close = true,
        })
    end

    -- Membership: invite/promote/demote only, no kick -- removing a member
    -- stays an F9 Staffing-tab-only action. A single permission
    -- (law.manage_members, same as canManage on the F9 side) gates all
    -- three here, rather than cm-police's three separate granular
    -- permissions, since the F9 tab itself only ever checks the one.
    if canManageMembers then
        local theirs = Player(targetServerId).state.cmLegalOrg
        if theirs == false then theirs = nil end
        if not theirs then
            add('law_invite', ('Invite to %s'):format(mine.shortLabel or 'Organization'), 30)
        elseif theirs.id == mine.id and theirs.isLeader ~= true and (tonumber(mine.tier) or 0) > (tonumber(theirs.tier) or 0) then
            add('law_promote', 'Promote Member', 31)
            add('law_demote', 'Demote Member', 32)
        end
    end
end

RegisterNetEvent('cm-law:client:bookingIntake', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local preview = lib.callback.await('cm-law:server:bookingPreview', false, targetServerId)
    if not preview or not preview.ok then
        return TriggerEvent('cm-hud:client:notify', preview and preview.error or 'Booking is unavailable.', 'error')
    end
    local options = {}
    for _, charge in ipairs(preview.charges or {}) do
        options[#options + 1] = { value = charge.id, label = ('%s (%d min)'):format(charge.label, charge.jailMinutes) }
    end
    local input = lib.inputDialog(('Book %s'):format(preview.suspectName or 'Suspect'), {
        { type = 'multi-select', label = 'Charges', description = ('Select up to %d charges'):format(preview.maxCharges or 10),
            options = options, required = true, searchable = true },
        { type = 'textarea', label = 'Arrest reason', description = 'Explain the circumstances of this arrest', required = true,
            min = 5, max = 500, autosize = true },
    })
    if not input then return end
    local chargeIds, reason = input[1], input[2]
    local total = 0
    local lookup = {}
    for _, charge in ipairs(preview.charges or {}) do lookup[charge.id] = charge end
    for _, id in ipairs(chargeIds or {}) do total = total + (lookup[id] and tonumber(lookup[id].jailMinutes) or 0) end
    local decision = lib.alertDialog({ header = 'Confirm booking', centered = true, cancel = true,
        content = ('Charges: %d\nSentence: %d minutes\nReason: %s'):format(#(chargeIds or {}), total, tostring(reason or '')),
        labels = { confirm = 'Confirm booking', cancel = 'Cancel' } })
    if decision ~= 'confirm' then return end
    local result = lib.callback.await('cm-law:server:bookSuspect', false, {
        targetServerId = targetServerId, chargeIds = chargeIds, reason = reason,
    })
    TriggerEvent('cm-hud:client:notify', result and (result.message or result.error) or 'Booking failed.', result and result.ok and 'success' or 'error')
end)

RegisterNetEvent('cm-law:client:searchPlayer', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local result, failure = lib.callback.await('cm-law:server:searchPlayer', false, targetServerId)
    if type(result) ~= 'table' then
        return TriggerEvent('cm-hud:client:notify', failure or 'Player search failed.', 'error')
    end
    SearchResult, SearchTarget = result, targetServerId
    rebuild(targetServerId)
    TriggerEvent('cm-playerdata:client:refreshInteractionMenu')
end)

RegisterNetEvent('cm-law:client:confiscatePlayer', function(targetServerId)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    local decision = lib.alertDialog({ header = 'Confirm confiscation',
        content = 'Move every unlicensed weapon, unlicensed ammunition, and illegal item found into your organization evidence storage?',
        centered = true, cancel = true, labels = { confirm = 'Confiscate evidence', cancel = 'Cancel' } })
    if decision ~= 'confirm' then return end
    local response = lib.callback.await('cm-law:server:confiscatePlayer', false, targetServerId)
    TriggerEvent('cm-hud:client:notify', response and (response.message or response.error) or 'Confiscation failed.',
        response and response.ok and 'success' or 'error')
    if response and response.result then
        SearchResult, SearchTarget = response.result, targetServerId
        rebuild(targetServerId)
        TriggerEvent('cm-playerdata:client:refreshInteractionMenu')
    end
end)

RegisterNetEvent('cm-playerdata:client:interactionTargetChanged', rebuild)
AddEventHandler('cm-playerdata:client:interactionRegistryReady', function() registerPage(); rebuild(nil) end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == Config.PlayerDataResource then Wait(300); registerPage(); rebuild(nil) end
end)
