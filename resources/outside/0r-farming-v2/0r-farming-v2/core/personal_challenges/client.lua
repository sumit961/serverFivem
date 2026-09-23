local lib = lib
local Utils = require("modules.utils.client")

PersonalChallengesClient = {
    isLoaded = false,
    challenges = {},
}

-- UI"a challenge"ları gönder
function PersonalChallengesClient.sendToUI()
    shared.debug("Sending personal challenges to UI...")
    client.sendReactMessage("ui:setPersonalChallenges", PersonalChallengesClient.challenges)
end

function PersonalChallengesClient.loadPlayerChallenges()
    local challenges = lib.callback.await(_e("server:personal_challenges:getPlayerChallenges"), false)
    if challenges then
        PersonalChallengesClient.challenges = challenges
        shared.debug("Personal challenges loaded")
    end
end

function PersonalChallengesClient.init()
    shared.debug("Initializing Personal Challenges...")
    PersonalChallengesClient.loadPlayerChallenges()
    PersonalChallengesClient.isLoaded = true
    PersonalChallengesClient.sendToUI()
end

function PersonalChallengesClient.clear()
    PersonalChallengesClient.isLoaded = false
    PersonalChallengesClient.challenges = {}
end

-- Challenge ilerlemesi güncellendiğinde
RegisterNetEvent(_e("client:personal_challenges:progressUpdate"), function(data)
    local challenge = PersonalChallengesClient.challenges[data.challengeId]
    if challenge and challenge.objective then
        challenge.objective.progress = data.progress
        PersonalChallengesClient.sendToUI()
    end
end)

-- Challenge tamamlandığında
RegisterNetEvent(_e("client:personal_challenges:challengeCompleted"), function(data)
    local challenge = PersonalChallengesClient.challenges[data.challengeId]
    if challenge then
        PersonalChallengesClient.sendToUI()
        Utils.notify(locale("personal_challenges.challenge_completed", challenge.label, data.newLevel), "success", 5000)
    end
end)

-- Challenge güncellendiğinde (yeni seviye)
RegisterNetEvent(_e("client:personal_challenges:challengeUpdated"), function(updatedChallenge)
    PersonalChallengesClient.challenges[updatedChallenge.id] = updatedChallenge
    PersonalChallengesClient.sendToUI()

    Utils.notify(
        locale("personal_challenges.new_level", updatedChallenge.label, updatedChallenge.currentLevel),
        "info", 4000)
end)
