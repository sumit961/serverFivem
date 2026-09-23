--[[ Dependencies ]]
local db = require "modules.mysql.server"

--[[ State ]]
local PlayerProfiles = {}
Profile = {}

--[[ Local Functions ]]

---@param userExp number
---@return number
local function getProfileLevel(userExp)
    local lastLevel = 1
    for lvl, reqExp in pairs(Config.Levels) do
        if userExp < reqExp then
            return math.max(1, lvl - 1)
        end
        lastLevel = math.max(lastLevel, lvl)
    end
    return lastLevel
end

---@param userExp number
---@return number
local function getNextLevelExp(userExp)
    local nextExp
    local maxExp = 0
    for _, reqExp in pairs(Config.Levels) do
        if userExp < reqExp and (not nextExp or reqExp < nextExp) then
            nextExp = reqExp
        end
        maxExp = math.max(maxExp, reqExp)
    end
    return nextExp or maxExp
end

---@param identifier string
---@return table?
local function getProfileByIdentifier(identifier)
    return PlayerProfiles[identifier]
end

---@param source number
---@return string
local function getIdentifier(source)
    return server.getPlayerIdentifier(source)
end

---@param source number
---@return table?
local function getProfileBySource(source)
    return getProfileByIdentifier(getIdentifier(source))
end

--[[ Public Profile API ]]

function Profile.loadDatabase()
    for _, profile in pairs(db.loadProfiles()) do
        profile.level = getProfileLevel(profile.exp)
        profile.nextLevelExp = getNextLevelExp(profile.exp)
        PlayerProfiles[profile.identifier] = profile
    end
    return true
end

function Profile.getByIdentifier(identifier)
    return getProfileByIdentifier(identifier)
end

function Profile.getBySource(source)
    return getProfileBySource(source)
end

function Profile.create(source)
    local identifier = getIdentifier(source)
    if PlayerProfiles[identifier] then
        lib.print.error(("Profile for %s already exists!"):format(identifier))
        return false
    end

    local name = server.getPlayerCharacterName(source)
    local profile = {
        level = 1,
        exp = 0,
        nextLevelExp = getNextLevelExp(0),
        name = name,
        source = source,
    }

    PlayerProfiles[identifier] = profile
    db.createPlayer(identifier, name)

    return profile
end

function Profile.giveExp(identifier, exp)
    local profile = type(identifier) == "number"
        and getProfileBySource(identifier)
        or getProfileByIdentifier(identifier)

    if not profile then return 0 end

    profile.exp = profile.exp + exp
    profile.level = getProfileLevel(profile.exp)
    profile.nextLevelExp = getNextLevelExp(profile.exp)

    return profile.exp
end

function Profile.getLevel(identifier)
    local profile = type(identifier) == "number"
        and getProfileBySource(identifier)
        or getProfileByIdentifier(identifier)

    return profile and profile.level or false
end

function Profile.update(source)
    local identifier = getIdentifier(source)
    local profile = PlayerProfiles[identifier]
    if not profile then return false end

    profile.source = source -- ensure current source
    TriggerClientEvent(_e("client:profile:onUpdate"), source, profile)
    db.updateProfile(identifier, profile)
    return true
end

--[[ Callbacks ]]

lib.callback.register(_e("server:profile:get"), function(source)
    if not server.load then
        while not server.load do Citizen.Wait(500) end
    end

    local profile = getProfileBySource(source)
    if not profile then
        profile = Profile.create(source)
    else
        profile.name = profile.name or server.getPlayerCharacterName(source)
        profile.source = source
    end

    return profile
end)
