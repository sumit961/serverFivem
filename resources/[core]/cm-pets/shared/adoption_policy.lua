CM_PETS = CM_PETS or {}
CM_PETS.Adoption = CM_PETS.Adoption or {}

local Adoption = CM_PETS.Adoption

local function finite(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function cleanText(value, maxLength, fallback)
    if value == nil then value = fallback end
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or #value > maxLength then return nil end
    return value
end

local function cleanId(value, maxLength)
    value = cleanText(value, maxLength)
    if not value or not value:match('^[%w_%-]+$') then return nil end
    return value:lower()
end

local function optionalInteger(value, min, max)
    if value == nil or tostring(value) == '' then return nil end
    value = finite(value)
    if not value or value % 1 ~= 0 or value < min or value > max then return nil end
    return value
end

function Adoption.NormalizeCenter(raw, existing, config)
    if type(raw) ~= 'table' then return nil, 'invalid_adoption_center' end
    config = config or {}
    local limits = config.Limits or {}
    local adoption = config.Adoption or {}
    local approvedModels = config.ApprovedNpcModels or {}

    local id = cleanId(raw.centerId or raw.center_id or (existing and existing.center_id), limits.CenterId or 32)
    local displayName = cleanText(raw.displayName or raw.display_name or (existing and existing.display_name), limits.CenterDisplayName or 64)
    local interactionLabel = cleanText(raw.interactionLabel or raw.interaction_label or (existing and existing.interaction_label), limits.CenterInteractionLabel or 64)
    local model = cleanId(raw.npcModel or raw.npc_model or (existing and existing.npc_model), limits.Model or 64)
    local enabled = raw.enabled
    if enabled == nil and existing then enabled = tonumber(existing.enabled) == 1 end
    enabled = enabled == true or tonumber(enabled) == 1

    local x = raw.x ~= nil and finite(raw.x) or (existing and finite(existing.x))
    local y = raw.y ~= nil and finite(raw.y) or (existing and finite(existing.y))
    local z = raw.z ~= nil and finite(raw.z) or (existing and finite(existing.z))
    local heading = raw.heading ~= nil and finite(raw.heading) or (existing and finite(existing.heading))
    local distance = raw.interactionDistance ~= nil and finite(raw.interactionDistance)
        or (raw.interaction_distance ~= nil and finite(raw.interaction_distance))
        or (existing and finite(existing.interaction_distance))
    local bucket = raw.routingBucket
    if bucket == nil then bucket = raw.routing_bucket end
    if bucket == nil and existing then bucket = existing.routing_bucket end

    if not id then return nil, 'invalid_center_id' end
    if displayName == nil then return nil, 'invalid_center_display_name' end
    if interactionLabel == nil then return nil, 'invalid_center_interaction_label' end
    if model ~= nil and not approvedModels[model] then return nil, 'npc_model_not_allowlisted' end
    if distance == nil then distance = 2.5 end
    if distance < (adoption.MinInteractionDistance or 1.0) or distance > (adoption.MaxInteractionDistance or 8.0) then
        return nil, 'invalid_interaction_distance'
    end
    if bucket ~= nil and tostring(bucket) ~= '' then
        bucket = optionalInteger(bucket, 0, adoption.MaxRoutingBucket or 2147483647)
        if bucket == nil then return nil, 'invalid_routing_bucket' end
    else
        bucket = nil
    end

    if enabled then
        if not model then return nil, 'enabled_center_requires_npc_model' end
        if not x or not y or not z then return nil, 'enabled_center_requires_coordinates' end
        heading = heading or 0.0
        if x < -8192.0 or x > 8192.0 or y < -8192.0 or y > 8192.0 or z < -2048.0 or z > 4096.0 then
            return nil, 'invalid_center_coordinates'
        end
        if heading < 0.0 or heading >= 360.0 then return nil, 'invalid_center_heading' end
    else
        -- A disabled center retains its identity and bounded descriptive
        -- fields but cannot retain an accidentally discoverable location.
        x, y, z, heading, bucket = nil, nil, nil, nil, nil
    end

    return {
        centerId = id,
        displayName = displayName,
        interactionLabel = interactionLabel,
        npcModel = model,
        enabled = enabled,
        x = x, y = y, z = z, heading = heading,
        interactionDistance = distance,
        routingBucket = bucket,
    }
end

function Adoption.CenterUsable(context, center)
    if type(context) ~= 'table' or context.loaded ~= true or context.alive ~= true or context.playerValid ~= true then
        return false, 'player_unavailable'
    end
    if type(center) ~= 'table' or center.enabled ~= true or not center.x or not center.y or not center.z then
        return false, 'adoption_center_unavailable'
    end
    if not finite(context.x) or not finite(context.y) or not finite(context.z)
        or not finite(center.x) or not finite(center.y) or not finite(center.z)
        or not finite(center.interactionDistance) then
        return false, 'adoption_center_unavailable'
    end
    if center.routingBucket ~= nil and tonumber(context.routingBucket) ~= tonumber(center.routingBucket) then
        return false, 'routing_bucket_mismatch'
    end
    local dx = context.x - center.x
    local dy = context.y - center.y
    local dz = context.z - center.z
    if (dx * dx + dy * dy + dz * dz) > (center.interactionDistance * center.interactionDistance) then
        return false, 'too_far_away'
    end
    return true
end

function Adoption.SessionTokenValid(expectedGeneration, expectedToken, generation, token)
    return tonumber(expectedGeneration) ~= nil and tonumber(expectedGeneration) == tonumber(generation)
        and type(expectedToken) == 'string' and expectedToken ~= '' and expectedToken == token
end

function Adoption.AdoptionDecision(context, center, petType, existing)
    local usable, reason = Adoption.CenterUsable(context, center)
    if not usable then return false, reason end
    if type(petType) ~= 'table' or tonumber(petType.enabled) ~= 1 or not petType.approvedModel then
        return false, 'pet_type_unavailable'
    end
    if existing then return false, 'already_owned' end
    return true
end

function Adoption.ShouldCleanup(state)
    return type(state) ~= 'table' or state.disconnected == true or state.dead == true
        or state.unloaded == true or state.resourceStopping == true
        or state.centerDisabled == true or state.invalidConfiguration == true
end
