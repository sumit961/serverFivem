-- Optimized Query table with constants and prepared statements
local Query = {
    SELECT_PROFILES = "SELECT * FROM `0resmon_farming_profiles`",
    UPDATE_PROFILE = "UPDATE `0resmon_farming_profiles` SET exp = ? WHERE identifier = ?",
    INSERT_PROFILE = "INSERT IGNORE INTO `0resmon_farming_profiles` (identifier) VALUES (?)",

    SELECT_PERSONAL_CHALLENGES = "SELECT * FROM `0resmon_farming_player_personal_challenges` WHERE identifier = ?",
    UPDATE_PERSONAL_CHALLENGE = [[
        UPDATE `0resmon_farming_player_personal_challenges`
        SET current_level = ?, progress = ?, updated_at = NOW()
        WHERE identifier = ? AND challenge_id = ?
    ]],
    INSERT_PERSONAL_CHALLENGE = [[
        INSERT INTO `0resmon_farming_player_personal_challenges`
        (identifier, challenge_id, current_level, progress, created_at)
        VALUES (?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
        current_level = VALUES(current_level),
        progress = VALUES(progress),
        updated_at = NOW()
    ]],
    SELECT_PERSONAL_CHALLENGE =
    "SELECT * FROM `0resmon_farming_player_personal_challenges` WHERE identifier = ? AND challenge_id = ? LIMIT 1"
}

-- Checking the existence of the database table, if it does not exist, it is created
Citizen.CreateThreadNow(function()
    Citizen.Wait(0)

    -- 0resmon_farming_profiles table should exist
    -- If it does not exist, create it
    local farmingProfilesSuccess, _ = pcall(MySQL.scalar.await,
        "SELECT 1 FROM `0resmon_farming_profiles`")
    if not farmingProfilesSuccess then
        MySQL.query([[CREATE TABLE `0resmon_farming_profiles` (
			`id` INT AUTO_INCREMENT PRIMARY KEY,
			`identifier` varchar(255) NOT NULL UNIQUE,
            `exp` INT DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
		)]])
        lib.print.info("Database Table `0resmon_farming_profiles` created !")
    end

    -- 0resmon_farming_player_personal_challenges table should exist
    -- If it does not exist, create it
    local personalChallengesSuccess, _ = pcall(MySQL.scalar.await,
        "SELECT 1 FROM `0resmon_farming_player_personal_challenges`")
    if not personalChallengesSuccess then
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS 0resmon_farming_player_personal_challenges (
            id INT AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(50) NOT NULL,
            challenge_id VARCHAR(50) NOT NULL,
            current_level INT DEFAULT 1,
            progress INT DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY unique_challenge (identifier, challenge_id)
        )]])

        lib.print.info("Database Table `0resmon_farming_player_personal_challenges` created !")
    end
end)

-- Database module
local db = {}

function db.loadProfiles()
    return MySQL.query.await(Query.SELECT_PROFILES)
end

---@param identifier string
---@param data Profile
function db.updateProfile(identifier, data)
    return MySQL.prepare(Query.UPDATE_PROFILE, { data.exp, identifier })
end

---@param identifier string
function db.createPlayer(identifier)
    return MySQL.insert(Query.INSERT_PROFILE, { identifier })
end

---@param identifier string
function db.getPersonalChallenges(identifier)
    return MySQL.query.await(Query.SELECT_PERSONAL_CHALLENGES, { identifier })
end

---@param identifier string
---@param challengeId string
---@param currentLevel number
---@param progress number
function db.updatePersonalChallenge(identifier, challengeId, currentLevel, progress)
    return MySQL.prepare(Query.UPDATE_PERSONAL_CHALLENGE, {
        currentLevel,
        progress,
        identifier,
        challengeId
    })
end

---@param identifier string
---@param challengeId string
---@param currentLevel number
---@param progress number
function db.insertPersonalChallenge(identifier, challengeId, currentLevel, progress)
    return MySQL.insert(Query.INSERT_PERSONAL_CHALLENGE, {
        identifier,
        challengeId,
        currentLevel,
        progress
    })
end

function db.getPersonalChallenge(identifier, challengeId)
    return MySQL.single.await(Query.SELECT_PERSONAL_CHALLENGE, { identifier, challengeId })
end

return db
