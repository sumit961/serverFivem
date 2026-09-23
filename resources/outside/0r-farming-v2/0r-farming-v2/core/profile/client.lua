--[[ state ]]

Profile = {}

local playerProfile = {
    level = 0,
    exp = 0,
    nextLevelExp = 0,
    name = nil,
    source = -1,
}

--[[ functions ]]

Profile.get = function()
    return playerProfile
end

Profile.fetch = function()
    local response = lib.callback.await(_e("server:profile:get"), false)
    if not response then return false end
    playerProfile = response
    return playerProfile
end

Profile.updateUI = function()
    client.sendReactMessage("ui:setUserProfile", playerProfile)
end

--[[ events ]]

RegisterNetEvent(_e("client:profile:onUpdate"), function(newProfile)
    playerProfile.exp = newProfile.exp
    playerProfile.level = newProfile.level
    playerProfile.nextLevelExp = newProfile.nextLevelExp
    client.sendReactMessage("ui:setUserProfile", playerProfile)
end)
