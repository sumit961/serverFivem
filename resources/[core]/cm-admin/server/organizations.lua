-- cm-admin/server/organizations.lua
-- Centralized "Organizations" registry + cross-org policy settings.
--
-- THE POINT: cm-admin is never edited again for a new organization. Any
-- single-leader org resource self-registers at startup:
--
--   exports['cm-admin']:RegisterOrganization({
--       id = 'ems', label = 'Emergency Medical Services',
--       resource = 'cm-ems', icon = 'briefcase-medical',
--   })
--
-- ...and implements two plain exports of its own that cm-admin calls back
-- into (same "resource stays the authority on its own data" convention
-- already used by RegisterDevTool's launcher events):
--   exports('GetOrganizationSummary', function(orgId) return { leaderCid, leaderName, memberCount, onDutyCount } end)
--   exports('AdminAssignLeader', function(actorSrc, targetCid, orgId) return ok, message end)
-- Single-organization resources may ignore orgId; shared resources use it
-- to serve several independently registered organizations safely.
--
-- Organizations vanish with their resource: no stale rows, no admin edits.
--
-- Cross-org policy (allowMultiOrgMembership / allowSameLeaderAcrossOrgs) is
-- stored here as a simple key/value table (same shape as cm-ems's own
-- cm_ems_settings) and read by any org resource via GetOrgPolicySetting.
-- FindRivalMembership is the generalized replacement for what used to be a
-- hardcoded pairwise check between exactly two orgs: it asks every OTHER
-- registered, running organization whether a character is already a member,
-- honoring the policy settings, so a third/fourth org participates
-- automatically with zero code changes to the existing ones.

local organizations = {}   -- [id] = { id, label, resource, icon }
local orgOwner = {}        -- [id] = owning resource name
local PolicyCache = {}
local PolicyDefaults = {
    allowMultiOrgMembership = false,
    allowSameLeaderAcrossOrgs = false,
}
local policyLoaded = false

local function hasPerm(src, permission)
    local ok, allowed = pcall(function()
        return exports['cm-admin']:HasPermission(src, permission)
    end)
    return ok and allowed == true
end

local function log(src, action, data)
    data = type(data) == 'table' and data or {}
    data.category = data.category or 'orgs'
    TriggerEvent('cm-admin:server:addLog', src or 0, action, data)
end

local function notify(src, message, kind)
    if src and src > 0 then
        TriggerClientEvent('cm-admin:client:notify', src, message, kind or 'info')
    end
end

local function jenc(value)
    return json.encode(value or {})
end

local function jdec(value, fallback)
    if type(value) == 'table' then return value end
    if not value or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return (ok and decoded) or fallback
end

local function ensureOrgSchema()
    local ok = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_admin_org_policy (
            setting_key VARCHAR(64) NOT NULL,
            setting_value LONGTEXT NOT NULL,
            updated_by VARCHAR(64) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (setting_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
    end)
    if not ok and Config.QuietConsoleLogs ~= true then
        print('[CM-ADMIN:ORGS] Could not create cm_admin_org_policy (will retry lazily).')
    end
end

local function loadPolicyCache()
    if policyLoaded then return end
    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT setting_key, setting_value FROM cm_admin_org_policy')
    end)
    if ok and type(rows) == 'table' then
        for _, row in ipairs(rows) do
            local decoded = jdec(row.setting_value, {})
            PolicyCache[tostring(row.setting_key)] = decoded.value
        end
        policyLoaded = true
    end
end

local function getOrgPolicySetting(key)
    key = tostring(key or '')
    loadPolicyCache()
    if PolicyCache[key] ~= nil then return PolicyCache[key] end
    return PolicyDefaults[key]
end

local function setOrgPolicySetting(src, key, value)
    key = tostring(key or '')
    if PolicyDefaults[key] == nil then return false, 'Unknown setting.' end
    value = value == true
    loadPolicyCache()
    PolicyCache[key] = value
    local ok = pcall(function()
        MySQL.insert.await([[INSERT INTO cm_admin_org_policy (setting_key, setting_value, updated_by)
            VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
            { key, jenc({ value = value }), src and tostring(src) or 'system' })
    end)
    return ok
end

exports('GetOrgPolicySetting', getOrgPolicySetting)

-- The generalized cross-org membership check. requestingOrgId is the org
-- asking ("who am I, so I don't check myself"); returns nil when multi-org
-- membership is allowed, or the first membership found in any OTHER
-- registered+running org (including whether that membership is a leader
-- role), or nil if the character isn't in any other org.
local function findRivalMembership(requestingOrgId, characterId)
    if getOrgPolicySetting('allowMultiOrgMembership') == true then return nil end
    requestingOrgId = tostring(requestingOrgId or '')
    characterId = tostring(characterId or '')
    if characterId == '' then return nil end
    for id, org in pairs(organizations) do
        if id ~= requestingOrgId and GetResourceState(org.resource) == 'started' then
            -- org.id is additive: legacy single-organization resources ignore
            -- it, while a shared multi-organization resource uses it to keep
            -- memberships isolated.
            local ok, member = pcall(function() return exports[org.resource]:GetMember(characterId, org.id) end)
            if ok and type(member) == 'table' then
                return { orgId = id, orgLabel = org.label, resource = org.resource, isLeader = member.isLeader == true }
            end
        end
    end
    return nil
end

exports('FindRivalMembership', findRivalMembership)

local function validateOrg(org)
    if type(org) ~= 'table' then return false, 'organization must be a table' end
    if type(org.id) ~= 'string' or org.id == '' then return false, 'organization.id required' end
    if type(org.label) ~= 'string' or org.label == '' then return false, 'organization.label required' end
    if type(org.resource) ~= 'string' or org.resource == '' then return false, 'organization.resource required' end
    return true
end

local function registerOrganization(org)
    local ok, err = validateOrg(org)
    if not ok then
        if Config.QuietConsoleLogs ~= true then print(('[CM-ADMIN:ORGS] Rejected organization registration: %s'):format(err)) end
        return false
    end
    organizations[org.id] = {
        id = org.id, label = org.label, resource = org.resource, icon = org.icon,
        canRemoveLeader = org.canRemoveLeader == true,
        canManageFacilities = org.canManageFacilities == true,
    }
    orgOwner[org.id] = GetInvokingResource() or GetCurrentResourceName()
    if Config.QuietConsoleLogs ~= true then print(('[CM-ADMIN:ORGS] Registered organization "%s" (%s) from %s'):format(org.label, org.id, orgOwner[org.id])) end
    return true
end

local function unregisterOrganization(id)
    organizations[id] = nil
    orgOwner[id] = nil
end

exports('RegisterOrganization', registerOrganization)
exports('UnregisterOrganization', unregisterOrganization)

-- Organizations vanish with their resource: no stale rows, no admin edits.
AddEventHandler('onResourceStop', function(resourceName)
    for id, owner in pairs(orgOwner) do
        if owner == resourceName then unregisterOrganization(id) end
    end
end)

CMOrganizations = {}

function CMOrganizations.forAdminPayload(src)
    if not hasPerm(src, 'orgs.view') then return nil end
    local out = {}
    for id, org in pairs(organizations) do
        local running = GetResourceState(org.resource) == 'started'
        local summary = {}
        if running then
            local ok, result = pcall(function() return exports[org.resource]:GetOrganizationSummary(org.id) end)
            if ok and type(result) == 'table' then summary = result end
        end
        out[#out + 1] = {
            id = id, label = org.label, icon = org.icon, resource = org.resource, running = running,
            leaderCid = summary.leaderCid, leaderName = summary.leaderName,
            memberCount = tonumber(summary.memberCount) or 0, onDutyCount = tonumber(summary.onDutyCount) or 0,
            canRemoveLeader = org.canRemoveLeader == true,
            canManageFacilities = org.canManageFacilities == true,
        }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return {
        list = out,
        policy = {
            allowMultiOrgMembership = getOrgPolicySetting('allowMultiOrgMembership') == true,
            allowSameLeaderAcrossOrgs = getOrgPolicySetting('allowSameLeaderAcrossOrgs') == true,
        },
    }
end

function CMOrganizations.removeLeader(src, orgId)
    if not hasPerm(src, 'orgs.manage') then return false, 'No permission: orgs.manage' end
    local org = organizations[tostring(orgId or '')]
    if not org then return false, 'Unknown organization.' end
    if not org.canRemoveLeader then return false, 'This organization does not support leader removal.' end
    if GetResourceState(org.resource) ~= 'started' then return false, ('%s is not running.'):format(org.resource) end

    local ok, result, message = pcall(function()
        return exports[org.resource]:AdminRemoveLeader(src, org.id)
    end)
    if not ok then return false, 'Leader removal failed safely.' end
    if result == true then log(src, 'org_leader_removed', { orgId = org.id }) end
    return result == true, message
end

function CMOrganizations.setFacility(src, orgId, facilityType, reset)
    if not hasPerm(src, 'orgs.manage') then return false, 'No permission: orgs.manage' end
    local org = organizations[tostring(orgId or '')]
    if not org then return false, 'Unknown organization.' end
    if not org.canManageFacilities then return false, 'This organization does not support facility configuration.' end
    if GetResourceState(org.resource) ~= 'started' then return false, ('%s is not running.'):format(org.resource) end
    local ok, result, message = pcall(function()
        return exports[org.resource]:AdminSetFacility(src, org.id, facilityType, reset == true)
    end)
    if not ok then return false, 'Facility update failed safely.' end
    if result == true then log(src, reset == true and 'org_facility_reset' or 'org_facility_set', {
        orgId = org.id, facilityType = tostring(facilityType or '')
    }) end
    return result == true, message
end

function CMOrganizations.assignLeader(src, orgId, targetCid)
    if not hasPerm(src, 'orgs.manage') then return false, 'No permission: orgs.manage' end
    local org = organizations[tostring(orgId or '')]
    if not org then return false, 'Unknown organization.' end
    if GetResourceState(org.resource) ~= 'started' then return false, ('%s is not running.'):format(org.resource) end
    targetCid = tostring(targetCid or '')
    if targetCid == '' then return false, 'Character ID is required.' end
    local ok, result, message = pcall(function() return exports[org.resource]:AdminAssignLeader(src, targetCid, org.id) end)
    if not ok then return false, 'Leader assignment failed safely.' end
    if result == true then
        log(src, 'org_leader_assigned', { orgId = org.id, targetCid = targetCid })
    end
    return result == true, message
end

function CMOrganizations.savePolicy(src, payload)
    if not hasPerm(src, 'orgs.manage') then return false, 'No permission: orgs.manage' end
    payload = type(payload) == 'table' and payload or {}
    setOrgPolicySetting(src, 'allowMultiOrgMembership', payload.allowMultiOrgMembership == true)
    setOrgPolicySetting(src, 'allowSameLeaderAcrossOrgs', payload.allowSameLeaderAcrossOrgs == true)
    log(src, 'org_policy_saved', {
        allowMultiOrgMembership = payload.allowMultiOrgMembership == true,
        allowSameLeaderAcrossOrgs = payload.allowSameLeaderAcrossOrgs == true,
    })
    return true, 'Organization policy saved.'
end

CreateThread(function()
    ensureOrgSchema()
    loadPolicyCache()
end)
