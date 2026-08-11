while GetResourceState('ox_lib') ~= 'started' do
    Wait(100)
end

while true do
    local ok, result = pcall(function()
        return exports.ox_lib:hasLoaded()
    end)

    if ok and result == true then
        break
    end

    Wait(50)
end

while GetResourceState('p_bridge') ~= 'started' do
    Wait(100)
end

while true do
    local ok = pcall(function()
        return exports.p_bridge:getObject()
    end)

    if ok then
        break
    end

    Wait(50)
end
