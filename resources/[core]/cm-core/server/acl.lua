-- CM-Core ACL compatibility bridge.
-- Real staff/admin ranks, permissions, UI, and logs belong in cm-admin.

CM = CM or {}
CM.ACL = CM.ACL or { Roles = {}, Permissions = {} }

local function adminHasPermission(src, permission)
    if GetResourceState('cm-admin') ~= 'started' then return nil end
    local ok, result = pcall(function()
        return exports['cm-admin']:HasPermission(src, permission)
    end)
    if ok then return result end
    return nil
end

local function adminGetRole(src, domain)
    if GetResourceState('cm-admin') ~= 'started' then return nil end
    local ok, result = pcall(function()
        if exports['cm-admin'].GetRole then
            return exports['cm-admin']:GetRole(src, domain)
        end
        return nil
    end)
    if ok then return result end
    return nil
end

exports('ACLRegisterDomain', function(domain, roles)
    -- Legacy no-op registry so older resources do not crash.
    if type(domain) == 'string' and type(roles) == 'table' then
        CM.ACL.Roles[domain] = roles
        return true
    end
    return false
end)

exports('ACLGetRole', function(src, domain)
    local role = adminGetRole(tonumber(src), domain)
    if role then return role end

    local ok, stateRole = pcall(function()
        return Player(tonumber(src)).state['acl_' .. tostring(domain)]
    end)
    return ok and stateRole or nil
end)

exports('ACLSetPermission', function(permission, domain, minRole)
    -- Legacy registry only. Real permission nodes belong in cm-admin.
    if type(permission) ~= 'string' or type(domain) ~= 'string' then return false end
    CM.ACL.Permissions[permission] = CM.ACL.Permissions[permission] or {}
    CM.ACL.Permissions[permission][domain] = minRole
    return true
end)

exports('ACLCheck', function(src, permission)
    src = tonumber(src)
    if not src or type(permission) ~= 'string' then return false end

    local allowed = adminHasPermission(src, permission)
    if allowed ~= nil then return allowed == true end

    -- No cm-admin means no admin permission. This prevents accidental staff access from cm-core.
    return false
end)

exports('ACLRequire', function(src, permission)
    if not exports['cm-core']:ACLCheck(src, permission) then
        return false, 'insufficient_permissions'
    end
    return true
end)
