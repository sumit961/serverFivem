local lib = lib
local config = lib.load("core.personal_challenges.config")
local db = require "modules.mysql.server"
local Inventory = require "modules.inventory.server"

PersonalChallengesServer = {}
PersonalChallengesServer.playerChallenges = {
    -- [playerId] = { challengeId = challengeData, ... }
} -- cache for player challenges

-- Oyuncunun kişisel görevlerini veritabanından yükle
function PersonalChallengesServer.loadPlayerChallenges(src)
    local identifier = server.getPlayerIdentifier(src)
    if not identifier then return {} end

    local result = db.getPersonalChallenges(identifier)
    -- result can be nil or empty if player has no challenges in database

    local playerChallenges = {}

    -- Config"teki şablonları al
    for _, template in pairs(config.challengeTemplates) do
        local existingChallenge = nil

        -- Veritabanında bu challenge var mı kontrol et (sadece result varsa)
        if result then
            for _, dbChallenge in pairs(result) do
                if dbChallenge.challenge_id == template.id then
                    existingChallenge = dbChallenge
                    break
                end
            end
        end

        local challenge = lib.table.deepclone(template)
        challenge.currentLevel = 1

        if existingChallenge then
            -- Veritabanından yükle
            challenge.currentLevel = existingChallenge.current_level

            -- Hedefi mevcut seviyeye göre hesapla
            local objective = challenge.objective
            objective.target = PersonalChallengesServer.calculateTarget(objective.baseTarget,
                challenge.currentLevel,
                objective.scalingMultiplier)
            objective.progress = existingChallenge.progress or 0

            -- Ödülleri seviyeye göre hesapla
            challenge.reward.exp = math.floor(challenge.reward.exp *
                (config.rewardScaling.expMultiplier ^ (challenge.currentLevel - 1)))
            challenge.reward.money = math.floor(challenge.reward.money *
                (config.rewardScaling.moneyMultiplier ^ (challenge.currentLevel - 1)))
        else
            -- Yeni oyuncu veya challenge - default değerleri kullan
            local objective = challenge.objective
            objective.target = objective.baseTarget
            objective.progress = 0
        end

        playerChallenges[challenge.id] = challenge
    end

    PersonalChallengesServer.playerChallenges[src] = playerChallenges
    return playerChallenges
end

-- Hedef değerini seviyeye göre hesapla
function PersonalChallengesServer.calculateTarget(baseTarget, level, multiplier)
    return math.floor(baseTarget * (multiplier ^ (level - 1)))
end

-- Challenge"ı veritabanına kaydet
function PersonalChallengesServer.saveChallengeToDatabase(identifier, challenge)
    local progress = 0
    if challenge.objective then
        progress = challenge.objective.progress
    end
    local existingChallenge = db.getPersonalChallenge(identifier, challenge.id)
    if existingChallenge then
        db.updatePersonalChallenge(identifier, challenge.id, challenge.currentLevel, progress)
    else
        db.insertPersonalChallenge(
            identifier,
            challenge.id,
            challenge.currentLevel,
            progress
        )
    end
end

-- Ödül ver
function PersonalChallengesServer.giveReward(src, reward)
    if reward.money > 0 then
        if Config.CleanMoney.isItem then
            Inventory.giveItem(src, Config.CleanMoney.itemName, reward.money)
        else
            server.playerAddMoney(src, Config.CleanMoney.accountName, reward.money)
        end
    end

    if reward.exp > 0 then
        Profile.giveExp(src, reward.exp)
        Profile.update(src)
    end
end

-- Challenge"ın tamamlanıp tamamlanmadığını kontrol et
function PersonalChallengesServer.checkChallengeCompletion(src, challengeId)
    local playerChallenges = PersonalChallengesServer.playerChallenges[src]
    if not playerChallenges then return end

    local challenge = playerChallenges[challengeId]
    if not challenge then return end

    local objective = challenge.objective
    local allCompleted = objective.progress >= objective.target

    if allCompleted then
        -- Ödül ver
        PersonalChallengesServer.giveReward(src, challenge.reward)

        -- Client"a tamamlandığını bildir
        TriggerClientEvent(_e("client:personal_challenges:challengeCompleted"), src, {
            challengeId = challengeId,
            reward = challenge.reward,
            newLevel = challenge.currentLevel + 1
        })

        -- Challenge"ı bir sonraki seviyeye hazırla
        PersonalChallengesServer.prepareChallengeForNextLevel(src, challengeId)

        shared.debug("Challenge completed:", challengeId, "Level:", challenge.currentLevel)
    end
end

-- Challenge"ı bir sonraki seviyeye hazırla
function PersonalChallengesServer.prepareChallengeForNextLevel(src, challengeId)
    local playerChallenges = PersonalChallengesServer.playerChallenges[src]
    if not playerChallenges then return end

    local challenge = playerChallenges[challengeId]
    if not challenge then return end

    -- Seviyeyi artır
    challenge.currentLevel = challenge.currentLevel + 1

    -- Yeni hedefleri hesapla
    challenge.objective.target = PersonalChallengesServer.calculateTarget(
        challenge.objective.baseTarget,
        challenge.currentLevel,
        challenge.objective.scalingMultiplier
    )
    challenge.objective.progress = 0

    -- Yeni ödülleri hesapla
    local template = nil
    for _, temp in pairs(config.challengeTemplates) do
        if temp.id == challengeId then
            template = temp
            break
        end
    end

    if template then
        challenge.reward.exp = math.floor(template.reward.exp *
            (config.rewardScaling.expMultiplier ^ (challenge.currentLevel - 1)))
        challenge.reward.money = math.floor(template.reward.money *
            (config.rewardScaling.moneyMultiplier ^ (challenge.currentLevel - 1)))
    end

    -- Client"a yeni challenge"ı gönder
    TriggerClientEvent(_e("client:personal_challenges:challengeUpdated"), src, challenge)
end

-- Challenge ilerlemesini güncelle
function PersonalChallengesServer.updateChallengeProgress(source, challengeId, targetName, actionType)
    local playerChallenges = PersonalChallengesServer.playerChallenges[source]
    if not playerChallenges then return end

    local challenge = playerChallenges[challengeId]
    if not challenge then return end

    local amount = 1

    local objective = challenge.objective
    local oldProgress = objective.progress

    objective.progress = math.min(objective.progress + amount, objective.target)

    if objective.progress > oldProgress then
        TriggerClientEvent(_e("client:personal_challenges:progressUpdate"), source, {
            challengeId = challengeId,
            progress = objective.progress,
        })

        shared.debug("Challenge progress updated:", challengeId, objective.progress, "/", objective.target)
    end

    if objective.progress >= objective.target then
        PersonalChallengesServer.checkChallengeCompletion(source, challengeId)
    end
end

function PersonalChallengesServer.onFarmingActionTriggered(source, targetName, actionType)
    Citizen.CreateThread(function()
        local playerChallenges = PersonalChallengesServer.playerChallenges[source]
        if not playerChallenges then return end
        for challengeId, challenge in pairs(playerChallenges) do
            local objective = challenge.objective
            if objective.type == actionType then
                if objective.targetName == "any" or objective.targetName == targetName then
                    PersonalChallengesServer.updateChallengeProgress(source, challengeId, targetName, actionType)
                end
            end
        end
    end)
end

function PersonalChallengesServer.onPlayerUnloaded(src)
    if PersonalChallengesServer.playerChallenges[src] then
        local identifier = server.getPlayerIdentifier(src)
        if identifier then
            for _, challenge in pairs(PersonalChallengesServer.playerChallenges[src]) do
                if challenge.objective and
                    challenge.objective.progress and
                    challenge.objective.progress > 0
                then
                    PersonalChallengesServer.saveChallengeToDatabase(identifier, challenge)
                end
            end
        end
    end
    PersonalChallengesServer.playerChallenges[src] = nil
end

function PersonalChallengesServer.saveAllChallenges()
    for src, challenges in pairs(PersonalChallengesServer.playerChallenges) do
        local identifier = server.getPlayerIdentifier(src)
        if identifier then
            for _, challenge in pairs(challenges) do
                if challenge.objective and
                    challenge.objective.progress and
                    challenge.objective.progress > 0
                then
                    PersonalChallengesServer.saveChallengeToDatabase(identifier, challenge)
                end
            end
        end
    end
    shared.debug("All personal challenges saved to database.")
end

-- Client callbacks
lib.callback.register(_e("server:personal_challenges:getPlayerChallenges"), function(source)
    return PersonalChallengesServer.loadPlayerChallenges(source)
end)

lib.cron.new("*/5 * * * *", function()
    PersonalChallengesServer.saveAllChallenges()
end, { debug = Config.debug })
