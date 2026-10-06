-- Shared "Press [key]" interaction prompt. Each resource owns a claim;
-- hiding one resource's claim never clears another resource's claim.

local InteractClaims = {}
local visibleOwner
local visibleSignature
local claimSequence = 0
local InteractionSuppressions = {}
local SuppressionResources = {}

local function invokingResource()
    local ok, resource = pcall(GetInvokingResource)
    if ok and resource and tostring(resource) ~= '' then return tostring(resource) end
    return GetCurrentResourceName() or 'unknown'
end

local function signature(claim)
    return table.concat({
        tostring(claim.owner), tostring(claim.key), tostring(claim.label),
        tostring(claim.name), tostring(claim.role), tostring(claim.priority)
    }, '|')
end

local function chooseWinner()
    if visibleOwner and InteractClaims[visibleOwner] then
        local current = InteractClaims[visibleOwner]
        local winner = current
        for _, claim in pairs(InteractClaims) do
            if (tonumber(claim.priority) or 0) > (tonumber(winner.priority) or 0) then
                winner = claim
            end
        end
        return winner
    end

    local winner
    for _, claim in pairs(InteractClaims) do
        if not winner
            or (tonumber(claim.priority) or 0) > (tonumber(winner.priority) or 0)
            or ((tonumber(claim.priority) or 0) == (tonumber(winner.priority) or 0)
                and claim.sequence < winner.sequence)
        then
            winner = claim
        end
    end
    return winner
end

local function refreshVisibleClaim()
    local winner = next(InteractionSuppressions) and nil or chooseWinner()
    if not winner then
        if visibleOwner then
            SendNUIMessage({ action = 'cmInteract:hide', owner = visibleOwner })
        end
        visibleOwner, visibleSignature = nil, nil
        return
    end

    local nextSignature = signature(winner)
    if visibleOwner == winner.owner and visibleSignature == nextSignature then return end

    SendNUIMessage({
        action = 'cmInteract:show',
        owner = winner.owner,
        key = winner.key,
        label = winner.label,
        name = winner.name,
        role = winner.role,
        priority = winner.priority,
    })
    visibleOwner, visibleSignature = winner.owner, nextSignature
end

local function ShowInteract(options)
    options = type(options) == 'table' and options or {}
    local resource = invokingResource()
    local owner = options.owner and tostring(options.owner) or resource
    claimSequence = claimSequence + 1
    local existing = InteractClaims[owner]
    InteractClaims[owner] = {
        owner = owner,
        invokingResource = resource,
        key = tostring(options.key or 'E'),
        label = tostring(options.label or 'INTERACTION'),
        name = options.name and tostring(options.name) or nil,
        role = options.role and tostring(options.role) or nil,
        priority = math.max(-100, math.min(100, tonumber(options.priority) or 0)),
        sequence = existing and existing.sequence or claimSequence,
    }
    refreshVisibleClaim()
end

local function HideInteract(owner, force)
    if force then
        InteractClaims = {}
        visibleOwner, visibleSignature = nil, nil
        SendNUIMessage({ action = 'cmInteract:hide', force = true })
        return true
    end

    local resource = invokingResource()
    if owner ~= nil then
        owner = tostring(owner)
        local claim = InteractClaims[owner]
        if not claim or claim.invokingResource ~= resource then return false end
        InteractClaims[owner] = nil
    else
        -- Legacy HideInteract() means "hide my resource's claims", never
        -- "hide whichever resource currently wins".
        for claimOwner, claim in pairs(InteractClaims) do
            if claim.invokingResource == resource then InteractClaims[claimOwner] = nil end
        end
    end

    refreshVisibleClaim()
    return true
end

local function ForceHideInteract()
    return HideInteract(nil, true)
end

local function SetInteractSuppressed(owner, suppressed)
    if type(owner) == 'boolean' then
        suppressed = owner
        owner = nil
    end
    owner = tostring(owner or invokingResource())
    local resource = invokingResource()
    if suppressed == true then
        InteractionSuppressions[owner] = true
        SuppressionResources[owner] = resource
    else
        InteractionSuppressions[owner] = nil
        SuppressionResources[owner] = nil
    end
    refreshVisibleClaim()
end

exports('ShowInteract', ShowInteract)
exports('HideInteract', HideInteract)
exports('ForceHideInteract', ForceHideInteract)
exports('SetInteractSuppressed', SetInteractSuppressed)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        ForceHideInteract()
        return
    end

    local changed = false
    for owner, claim in pairs(InteractClaims) do
        if claim.invokingResource == resource then
            InteractClaims[owner] = nil
            changed = true
        end
    end
    for owner, sourceResource in pairs(SuppressionResources) do
        if sourceResource == resource then
            InteractionSuppressions[owner] = nil
            SuppressionResources[owner] = nil
            changed = true
        end
    end
    if changed then refreshVisibleClaim() end
end)
