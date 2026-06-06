CM.Validation = {
    Rules = {
        username = {min = 3, max = 25, pattern = '^[A-Za-z0-9_]+$', message = 'Username must be 3-25 alphanumeric chars'},
        password = {min = 6, max = 100, message = 'Password must be at least 6 characters'},
        name = {min = 2, max = 20, pattern = '^[A-Za-z%-%s]+$', blocked = {}, message = 'Invalid name'},
        email = {pattern = '^[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+%.[A-Za-z]{2,}$', message = 'Invalid email'},
        slot = {type = 'number', min = 1, max = 3, message = 'Slot must be 1-3'},
        money = {type = 'number', min = 0, max = 999999999, message = 'Invalid money amount'},
    }
}

CreateThread(function()
    Wait(1000)
    local blocked = exports['cm-core']:GetConfig('Characters', 'blockedNames') or {}
    for _, name in ipairs(blocked) do CM.Validation.Rules.name.blocked[string.lower(name)] = true end
end)

exports('Validate', function(field, value, customRules)
    local rules = customRules or CM.Validation.Rules[field]
    if not rules then return false, 'Unknown field: ' .. tostring(field) end
    
    if rules.type and type(value) ~= rules.type then
        return false, rules.message or ('Expected ' .. rules.type)
    end
    
    if type(value) == 'string' then
        if rules.min and #value < rules.min then return false, rules.message end
        if rules.max and #value > rules.max then return false, rules.message end
        if rules.pattern and not string.match(value, rules.pattern) then return false, rules.message end
        if rules.blocked and rules.blocked[string.lower(value)] then return false, 'Name not allowed' end
    end
    
    if type(value) == 'number' then
        if rules.min and value < rules.min then return false, rules.message end
        if rules.max and value > rules.max then return false, rules.message end
    end
    
    return true, value
end)

exports('Sanitize', function(input)
    if type(input) ~= 'string' then return input end
    input = input:gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('%z', '')
    return input:match('^%s*(.-)%s*$')
end)