-- cm-family | client/cl_gmenu.lua
-- Builds target-specific options inside cm-playerdata's extension G menu.
-- v1.2.1 adds public profiles, owner-only permission inspection, and confirmed
-- ownership transfer.

local PAGE = 'family'

local function pdStarted()
    return GetResourceState(Config.PlayerDataResource) == 'started'
end

local function registerPage()
    if not pdStarted() then return end
    pcall(function()
        exports[Config.PlayerDataResource]:RegisterInteractionPage({
            id = PAGE,
            label = 'Family',
            icon = 'family',
            order = 35,
            emptyLabel = 'No family actions available',
        })
    end)
end

local function clearOptions()
    if pdStarted() then
        pcall(function() exports[Config.PlayerDataResource]:ClearInteractionOptions(PAGE) end)
    end
end

local function add(id, label, icon, order)
    if not pdStarted() then return end
    pcall(function()
        exports[Config.PlayerDataResource]:RegisterInteractionOption(PAGE, {
            id = id,
            action = id,
            label = label,
            icon = icon or 'family',
            type = 'extension',
            order = order or 100,
            close = true,
        })
    end)
end

local function has(state, permission)
    return type(state) == 'table'
        and (state.isFounder == true
            or (type(state.permissions) == 'table' and state.permissions[permission] == true))
end

local function sameFamily(a, b)
    return type(a) == 'table' and type(b) == 'table'
        and tonumber(a.id) ~= nil and tonumber(a.id) == tonumber(b.id)
end

local function rebuild(targetServerId)
    clearOptions()
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end

    local mine = LocalPlayer.state.cmFamily
    local theirs = Player(targetServerId).state.cmFamily
    if mine == false then mine = nil end
    if theirs == false then theirs = nil end

    -- Family profile is public. A player does not need to be in the same family
    -- (or any family) to view another player's public family identity.
    if theirs then
        add('family_profile', 'View Family Profile', 'family', 10)
    end

    if not mine then return end

    if not theirs then
        if has(mine, 'family.invite') then
            add('family_invite', 'Invite to Family', 'family', 20)
        end
        return
    end

    if not sameFamily(mine, theirs) then return end

    -- Only the authoritative owner may inspect another member's effective
    -- permission list. This is also checked again on the server.
    if mine.isFounder == true then
        add('family_permissions', 'View Member Permissions', 'documents', 20)
    end

    if theirs.isFounder == true then return end

    local myTier = tonumber(mine.tier) or 0
    local targetTier = tonumber(theirs.tier) or 0
    local targetBelow = mine.isFounder == true or targetTier < myTier
    if not targetBelow then return end

    if has(mine, 'family.promote') then
        add('family_promote', 'Promote One Rank', 'up', 30)
    end
    if has(mine, 'family.demote') then
        add('family_demote', 'Demote One Rank', 'down', 40)
    end
    if has(mine, 'family.kick') then
        add('family_kick', 'Kick from Family', 'close', 50)
    end
    if mine.isFounder == true then
        add('family_transfer', 'Transfer Family Ownership', 'handshake', 60)
    end
end

local function showContext(id, title, options)
    if type(lib) ~= 'table' or type(lib.registerContext) ~= 'function' then return end
    lib.registerContext({ id = id, title = title, options = options })
    lib.showContext(id)
end

RegisterNetEvent('cm-family:client:showPublicFamilyProfile', function(profile)
    if type(profile) ~= 'table' then return end
    local tag = tostring(profile.familyTag or 'FAMILY')
    local title = ('[%s] %s'):format(tag, tostring(profile.familyName or 'Family'))
    local targetTitle = profile.targetTitle or profile.targetRank or 'Member'

    showContext('cm_family_public_profile', title, {
        {
            title = tostring(profile.targetName or 'Unknown member'),
            description = ('%s · Character ID %s'):format(tostring(targetTitle), tostring(profile.targetCid or '?')),
            icon = profile.targetIsFounder and 'crown' or 'user',
            iconColor = profile.color,
            disabled = true,
        },
        {
            title = 'Family owner',
            description = tostring(profile.founderName or 'Unknown'),
            icon = 'crown',
            iconColor = profile.color,
            disabled = true,
        },
        {
            title = 'Members',
            description = ('%s total · %s online'):format(
                tostring(profile.memberCount or 0), tostring(profile.onlineCount or 0)
            ),
            icon = 'users',
            disabled = true,
        },
        {
            title = 'Family house',
            description = profile.houseLabel and tostring(profile.houseLabel)
                or (profile.houseId and ('Property #' .. tostring(profile.houseId)) or 'No linked family house'),
            icon = 'house',
            disabled = true,
        },
    })
end)

RegisterNetEvent('cm-family:client:showMemberPermissions', function(data)
    if type(data) ~= 'table' then return end
    local options = {
        {
            title = tostring(data.targetName or 'Unknown member'),
            description = ('%s · Character ID %s'):format(
                tostring(data.targetTitle or data.targetRank or 'Member'),
                tostring(data.targetCid or '?')
            ),
            icon = data.targetIsFounder and 'crown' or 'user-shield',
            iconColor = data.color,
            disabled = true,
        }
    }

    local lastGroup
    for _, permission in ipairs(data.permissions or {}) do
        if permission.group ~= lastGroup then
            lastGroup = permission.group
            options[#options + 1] = {
                title = tostring(lastGroup or 'other'):upper(),
                icon = 'list',
                disabled = true,
            }
        end
        options[#options + 1] = {
            title = tostring(permission.label or permission.key),
            description = tostring(permission.key or ''),
            icon = permission.allowed == true and 'check' or 'xmark',
            iconColor = permission.allowed == true and '#4ade80' or '#fb7185',
            disabled = true,
        }
    end

    showContext('cm_family_member_permissions', 'Member Permissions', options)
end)

RegisterNetEvent('cm-family:client:confirmOwnershipTransfer', function(data)
    if type(data) ~= 'table' or not data.token then return end
    CreateThread(function()
        local result = lib.alertDialog({
            header = 'Transfer Family Ownership',
            content = ('Transfer **%s** to **%s** (CID %s)?\n\nYou will step down to the next-highest rank. This changes family bank, house, rank, and vehicle-management authority.'):format(
                tostring(data.familyName or 'the family'),
                tostring(data.targetName or 'this member'),
                tostring(data.targetCid or '?')
            ),
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Transfer Ownership',
                cancel = 'Cancel',
            },
        })

        if result == 'confirm' then
            TriggerServerEvent('cm-family:server:confirmOwnershipTransfer', {
                token = data.token,
                targetServerId = data.targetServerId,
            })
        else
            TriggerServerEvent('cm-family:server:cancelOwnershipTransfer', data.token)
        end
    end)
end)

RegisterNetEvent('cm-playerdata:client:interactionTargetChanged', rebuild)
AddEventHandler('cm-playerdata:client:interactionRegistryReady', function()
    registerPage()
    rebuild(nil)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= Config.PlayerDataResource and resourceName ~= GetCurrentResourceName() then return end
    Wait(300)
    registerPage()
    clearOptions()
end)
