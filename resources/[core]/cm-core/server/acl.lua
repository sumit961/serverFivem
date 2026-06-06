CM.ACL = {Roles = {}, Permissions = {}}

exports('ACLRegisterDomain', function(domain, roles)
    CM.ACL.Roles[domain] = roles
end)

exports('ACLGetRole', function(src, domain)
    return Player(src).state['acl_' .. domain] or nil
end)

exports('ACLSetPermission', function(permission, domain, minRole)
    CM.ACL.Permissions[permission] = CM.ACL.Permissions[permission] or {}
    CM.ACL.Permissions[permission][domain] = minRole
end)

exports('ACLCheck', function(src, permission)
    local char = exports['cm-characters'] and exports['cm-characters']:GetCharacter(src)
    if not char then return false end
    for domain, roles in pairs(CM.ACL.Roles) do
        local playerRole = exports['cm-core']:ACLGetRole(src, domain)
        if playerRole then
            local roleLevel = roles[playerRole] or 0
            local required = CM.ACL.Permissions[permission] and CM.ACL.Permissions[permission][domain] or 999
            if roleLevel >= required then return true end
        end
    end
    return false
end)

exports('ACLRequire', function(src, permission)
    if not exports['cm-core']:ACLCheck(src, permission) then
        return false, 'insufficient_permissions'
    end
    return true
end)