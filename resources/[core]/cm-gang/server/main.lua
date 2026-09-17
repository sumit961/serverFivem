exports('IsFixedGangId', function(gangId)
    return Config.IsFixedGangId(gangId)
end)

exports('GetFixedGangIds', function()
    local result = {}
    for index, gangId in ipairs(Config.GangIds) do
        result[index] = gangId
    end
    return result
end)
