local promises = {}

exports('GetPasswordHash', function(plainText)
    if not plainText then
        return
    end

    local promiseId
    repeat
        promiseId = math.random(1, 9999)
    until not promises[promiseId]

    local p = promise.new()
    promises[promiseId] = p

    TriggerEvent('bcrypt:GetPasswordHash', promiseId, plainText)

    Citizen.Await(p)
    promises[promiseId] = nil

    return p.value
end)

exports('VerifyPasswordHash', function(plainText, hash)
    if not plainText or not hash then
        return
    end

    local promiseId
    repeat
        promiseId = math.random(1, 9999)
    until not promises[promiseId]

    local p = promise.new()
    promises[promiseId] = p

    TriggerEvent('bcrypt:VerifyPasswordHash', promiseId, plainText, hash)

    Citizen.Await(p)
    promises[promiseId] = nil

    return p.value == "True" and true or false
end)

AddEventHandler('bcrypt:resolve', function(promiseId, value)
    local p = promises[promiseId]

    if not p then return end

    p:resolve(value)
end)