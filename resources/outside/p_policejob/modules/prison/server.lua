if not Config.Prison or not Config.Prison.Enabled then
    return
end

Prison = {
    sentences = {},
    cellAssignments = {},
    solitaryAssignments = {},
    Map = nil,
}

prisonJobCooldowns = {}
cellStashRegistered = {}

function getPlayerSource(player)
    return player.source or (player.PlayerData and player.PlayerData.source)
end

function computeRemainingSeconds(sentence)
    if sentence.releaseAt == 0 then
        return -1
    end
    return math.max(0, sentence.releaseAt - os.time())
end

function getSolitaryCoordsForSentence(sentence)
    if sentence.isSolitary and sentence.solitarySlot then
        local slots = Prison:getSolitarySlots()
        return slots[sentence.solitarySlot]
    end
    return nil
end

function buildRestorePayload(sentence)
    return {
        id = sentence.id,
        identifier = sentence.identifier,
        playerName = sentence.playerName,
        officerName = sentence.officerName,
        reason = sentence.reason,
        sentenceTime = sentence.sentenceTime,
        remaining = computeRemainingSeconds(sentence),
        cellId = sentence.cellId,
        isCommunityService = sentence.isCommunityService,
        solitaryCoords = getSolitaryCoordsForSentence(sentence),
    }
end

function restorePlayerPrisonState(sourceId, sentence, logContext)
    local remaining = computeRemainingSeconds(sentence)
    if remaining ~= -1 and remaining <= 0 then
        return
    end

    local payload = buildRestorePayload(sentence)

    if sentence.isCommunityService then
        Prison:setCommunityServiceBucket(sourceId, true)
        TriggerClientEvent("p_policejob/client/prison/communityService/enter", sourceId, payload)
    else
        TriggerClientEvent("p_policejob/client/prison/restoreState", sourceId, payload)
    end

    if logContext then
        Bridge.Debug(("[Prison] Restored prison state for player %d%s"):format(sourceId, logContext))
    end
end

function loadPrisonMap()
    local mapConfig = Config.PrisonMap
    local mapType = type(mapConfig)

    if mapType == "string" then
        return lib.load(("maps.prisons.%s"):format(mapConfig))
    end

    if mapType == "table" then
        return lib.load(("maps.prisons.%s"):format(mapConfig[1]))
    end

    return nil
end

Prison.Map = loadPrisonMap()

if type(Prison.Map) ~= "table" then
    lib.print.error("Failed to load prison map on server. Check Config.PrisonMap in config/shared.lua")
    return
end

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `p_policejob_prison_sentences` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `player_name` VARCHAR(100) NOT NULL,
            `officer_name` VARCHAR(100) DEFAULT NULL,
            `officer_id` INT DEFAULT NULL,
            `reason` TEXT,
            `sentence_time` INT NOT NULL DEFAULT 0,
            `remaining_time` INT NOT NULL DEFAULT 0,
            `cell_id` INT DEFAULT NULL,
            `is_community_service` TINYINT(1) DEFAULT 0,
            `is_solitary` TINYINT(1) DEFAULT 0,
            `solitary_until` INT DEFAULT 0,
            `status` ENUM('active','released','escaped') DEFAULT 'active',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            `released_at` TIMESTAMP NULL DEFAULT NULL,
            INDEX `idx_identifier` (`identifier`),
            INDEX `idx_status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `p_policejob_prison_jobs` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `job_id` VARCHAR(50) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `description` TEXT,
            `payment` INT DEFAULT 0,
            `duration` INT DEFAULT 30,
            `time_reduction` INT DEFAULT 0,
            `locations` LONGTEXT,
            `animation_dict` VARCHAR(100),
            `animation_clip` VARCHAR(100),
            `created_by` VARCHAR(60),
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    Wait(1000)
    Prison:loadActiveSentences()
    Wait(2000)
    Prison:restoreOnlinePlayers()
end)

function Prison.setCommunityServiceBucket(self, sourceId, isolate)
    local communityService = Config.Prison.CommunityService
    if not communityService or not communityService.isolatePlayer then
        return
    end

    if isolate then
        local bucketBase = communityService.bucketBase or 10000
        SetPlayerRoutingBucket(sourceId, bucketBase + sourceId)
    else
        SetPlayerRoutingBucket(sourceId, 0)
    end
end

function Prison.restoreOnlinePlayers(self)
    for identifier, sentence in pairs(self.sentences) do
        if sentence.status == "active" then
            local player = Bridge.Framework.getPlayerByUniqueId(identifier)
            local sourceId = player and getPlayerSource(player)

            if sourceId then
                restorePlayerPrisonState(sourceId, sentence, " on resource restart")
            end
        end
    end
end

function Prison.hasJobAccess(self, sourceId)
    local job = Bridge.Framework.getPlayerJob(sourceId)
    if not job then
        return false
    end
    return Config.Jobs[job.name] ~= nil
end

function Prison.findAvailableCell(self)
    if not Config.Prison.Cells.assignAutomatically then
        return nil
    end

    if not Prison.Map or not Prison.Map.cells then
        return nil
    end

    for _, cell in ipairs(Prison.Map.cells) do
        if not self.cellAssignments[cell.id] then
            return cell.id
        end
    end

    return nil
end

function Prison.assignCell(self, cellId, identifier)
    self.cellAssignments[cellId] = identifier
end

function Prison.freeCell(self, cellId)
    self.cellAssignments[cellId] = nil
end

function Prison.getSolitarySlots(self)
    local solitary = self.Map and self.Map.solitary
    if not solitary then
        return {}
    end
    if solitary.x then
        return { solitary }
    end
    return solitary
end

function Prison.findFreeSolitarySlot(self)
    local slots = self:getSolitarySlots()
    for slotIndex = 1, #slots do
        if not self.solitaryAssignments[slotIndex] then
            return slotIndex, slots[slotIndex]
        end
    end
    return nil
end

function Prison.freeSolitarySlot(self, sentence)
    if sentence.solitarySlot then
        self.solitaryAssignments[sentence.solitarySlot] = nil
        sentence.solitarySlot = nil
    end
end

function Prison.loadActiveSentences(self)
    local rows = MySQL.query.await(
        "SELECT * FROM `p_policejob_prison_sentences` WHERE `status` = ?",
        { "active" }
    )
    if not rows then
        return
    end

    local now = os.time()

    for _, row in ipairs(rows) do
        local releaseAt = 0
        if row.remaining_time > 0 then
            releaseAt = now + row.remaining_time
        end

        local sentence = {
            id = row.id,
            identifier = row.identifier,
            playerName = row.player_name,
            officerName = row.officer_name,
            reason = row.reason,
            sentenceTime = row.sentence_time,
            releaseAt = releaseAt,
            cellId = row.cell_id,
            isCommunityService = row.is_community_service == 1,
            isSolitary = row.is_solitary == 1,
            solitaryUntil = row.solitary_until,
            status = row.status,
        }

        self.sentences[row.identifier] = sentence

        if row.cell_id then
            self.cellAssignments[row.cell_id] = row.identifier
        end

        if sentence.isSolitary then
            local slotIndex = self:findFreeSolitarySlot()
            if slotIndex then
                sentence.solitarySlot = slotIndex
                self.solitaryAssignments[slotIndex] = row.identifier
            end
        end
    end

    Bridge.Debug(("[Prison] Loaded %d active sentences"):format(#rows))
end

function Prison.sendToJail(self, officerId, targetId, minutes, reason, isCommunityService, options)
    local identifier = Bridge.Framework.getUniqueId(targetId)
    if not identifier then
        return false
    end

    local existing = self.sentences[identifier]
    if existing and existing.status == "active" then
        Bridge.Notify.showNotify(officerId, locale("prison_already_jailed"), "error")
        return false
    end

    options = options or {}
    local isLifeSentence = options.lifeSentence == true
    local targetName = Bridge.Framework.getPlayerName(targetId)
    local officerName = Bridge.Framework.getPlayerName(officerId)
    local sentenceSeconds = isLifeSentence and 0 or (minutes * 60)

    local cellId = nil
    if options.cellId then
        local requestedCellId = tonumber(options.cellId)
        if requestedCellId and not self.cellAssignments[requestedCellId] then
            cellId = requestedCellId
        end
    end

    if not cellId then
        cellId = self:findAvailableCell()
    end

    local insertId = MySQL.insert.await(
        "INSERT INTO `p_policejob_prison_sentences` (`identifier`, `player_name`, `officer_name`, `officer_id`, `reason`, `sentence_time`, `remaining_time`, `cell_id`, `is_community_service`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
            identifier,
            targetName,
            officerName,
            officerId,
            reason,
            sentenceSeconds,
            sentenceSeconds,
            cellId,
            isCommunityService and 1 or 0,
        }
    )

    if not insertId then
        return false
    end

    local remaining = isLifeSentence and -1 or sentenceSeconds
    local releaseAt = isLifeSentence and 0 or (os.time() + sentenceSeconds)

    local sentence = {
        id = insertId,
        identifier = identifier,
        playerName = targetName,
        officerName = officerName,
        reason = reason,
        sentenceTime = sentenceSeconds,
        remaining = remaining,
        releaseAt = releaseAt,
        cellId = cellId,
        isCommunityService = isCommunityService,
        isLife = isLifeSentence,
        isSolitary = false,
        solitaryUntil = 0,
        status = "active",
    }

    self.sentences[identifier] = sentence

    if cellId then
        self:assignCell(cellId, identifier)
    end

    if isCommunityService then
        self:setCommunityServiceBucket(targetId, true)
        TriggerClientEvent("p_policejob/client/prison/communityService/enter", targetId, sentence)
    elseif Config.Prison.Mugshot.enabled then
        TriggerClientEvent("p_policejob/client/prison/mugshot", targetId, sentence)
    else
        TriggerClientEvent("p_policejob/client/prison/enter", targetId, sentence)
    end

    local playerState = Player(targetId).state
    if playerState.isCuffed then
        playerState:set("isCuffed", false, true)
        playerState:set("cuffType", "none", true)
    end
    if playerState.draggedBy then
        playerState:set("draggedBy", nil, true)
    end

    if Config.Prison.onPlayerJailed_Server then
        Config.Prison.onPlayerJailed_Server(officerId, targetId, sentence)
    end

    local destination = isCommunityService and "community service" or "prison"
    Bridge.Logs.Send(
        officerId,
        "Prison",
        ("Sent %s (ID: %d) to %s for %d minutes. Reason: %s"):format(targetName, targetId, destination, minutes, reason),
        Config.Webhooks.prison
    )
    Bridge.Notify.showNotify(officerId, locale("prison_player_sent", targetName), "success")
    return true
end

function Prison.releasePrisoner(self, identifier, officerId)
    local sentence = self.sentences[identifier]
    if not sentence then
        return false
    end

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `status` = ?, `remaining_time` = 0, `released_at` = NOW() WHERE `id` = ?",
        { "released", sentence.id }
    )

    if sentence.cellId then
        self:freeCell(sentence.cellId)
    end
    self:freeSolitarySlot(sentence)

    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
    local sourceId = player and getPlayerSource(player)

    if sourceId then
        if sentence.isCommunityService then
            self:setCommunityServiceBucket(sourceId, false)
            TriggerClientEvent("p_policejob/client/prison/communityService/release", sourceId)
        else
            TriggerClientEvent("p_policejob/client/prison/release", sourceId)
        end
    end

    self.sentences[identifier] = nil

    if officerId then
        Bridge.Logs.Send(
            officerId,
            "Prison",
            ("Released prisoner %s (ID: %s)"):format(sentence.playerName, identifier),
            Config.Webhooks.prison
        )
    end

    if Config.Prison.onPlayerReleased_Server then
        Config.Prison.onPlayerReleased_Server(identifier)
    end

    return true
end

function Prison.escapeJail(self, identifier)
    local sentence = self.sentences[identifier]
    if not sentence or sentence.status ~= "active" then
        return false
    end

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `status` = ?, `remaining_time` = 0, `released_at` = NOW() WHERE `id` = ?",
        { "escaped", sentence.id }
    )

    if sentence.cellId then
        self:freeCell(sentence.cellId)
    end
    self:freeSolitarySlot(sentence)
    self.sentences[identifier] = nil

    local sourceId = nil
    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
    if player then
        sourceId = getPlayerSource(player)
        if sourceId then
            if sentence.isCommunityService then
                self:setCommunityServiceBucket(sourceId, false)
            end
            TriggerClientEvent("p_policejob/client/prison/escaped", sourceId)
        end
    end

    if sourceId and Bridge.Dispatch and Bridge.Dispatch.SendAlert then
        local jobNames = {}
        for jobName in pairs(Config.Jobs) do
            jobNames[#jobNames + 1] = jobName
        end

        Bridge.Dispatch.SendAlert(sourceId, {
            title = locale("prison_escape_alert", sentence.playerName),
            code = "10-98",
            icon = "fa-solid fa-person-running",
            priority = "high",
            blip = { sprite = 188, scale = 1.2, color = 1 },
            job = jobNames,
        })
    end

    if Config.Prison.onPlayerEscaped_Server then
        Config.Prison.onPlayerEscaped_Server(sourceId, sentence)
    end

    if sourceId then
        Bridge.Logs.Send(
            sourceId,
            "Prison",
            ("Prisoner %s (%s) escaped from prison"):format(sentence.playerName, identifier),
            Config.Webhooks.prison
        )
    end

    return true
end

function Prison.reduceSentence(self, identifier, seconds)
    local sentence = self.sentences[identifier]
    if not sentence then
        return false
    end

    if sentence.releaseAt == 0 then
        return false
    end

    sentence.releaseAt = sentence.releaseAt - seconds
    local remaining = math.max(0, sentence.releaseAt - os.time())
    sentence.sentenceTime = math.max(remaining, (sentence.sentenceTime or 0) - seconds)

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `remaining_time` = ?, `sentence_time` = ? WHERE `id` = ?",
        { remaining, sentence.sentenceTime, sentence.id }
    )

    if remaining <= 0 then
        self:releasePrisoner(identifier)
        return true
    end

    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
    local sourceId = player and getPlayerSource(player)
    if sourceId then
        TriggerClientEvent("p_policejob/client/prison/updateSentence", sourceId, remaining, sentence.sentenceTime)
    end

    return true
end

function Prison.increaseSentence(self, identifier, seconds)
    local sentence = self.sentences[identifier]
    if not sentence then
        return false
    end

    if sentence.releaseAt == 0 then
        return false
    end

    sentence.releaseAt = sentence.releaseAt + seconds
    local remaining = math.max(0, sentence.releaseAt - os.time())
    sentence.sentenceTime = (sentence.sentenceTime or 0) + seconds

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `remaining_time` = ?, `sentence_time` = ? WHERE `id` = ?",
        { remaining, sentence.sentenceTime, sentence.id }
    )

    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
    local sourceId = player and getPlayerSource(player)
    if sourceId then
        TriggerClientEvent("p_policejob/client/prison/updateSentence", sourceId, remaining, sentence.sentenceTime)
        Bridge.Notify.showNotify(sourceId, locale("prison_sentence_increased"), "error")
    end

    return true
end

function Prison.sendToSolitary(self, identifier, minutes)
    local sentence = self.sentences[identifier]
    if not sentence or sentence.isSolitary then
        return false
    end

    local slotIndex, slotCoords = self:findFreeSolitarySlot()
    if not slotIndex then
        return false, "full"
    end

    local solitaryUntil = os.time() + (minutes * 60)
    sentence.isSolitary = true
    sentence.solitaryUntil = solitaryUntil
    sentence.solitarySlot = slotIndex
    self.solitaryAssignments[slotIndex] = identifier

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `is_solitary` = 1, `solitary_until` = ? WHERE `id` = ?",
        { solitaryUntil, sentence.id }
    )

    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
    local sourceId = player and getPlayerSource(player)
    if sourceId then
        TriggerClientEvent("p_policejob/client/prison/moveToSolitary", sourceId, slotCoords)
    end

    return true
end

function Prison.releaseFromSolitary(self, identifier)
    local sentence = self.sentences[identifier]
    if not sentence or not sentence.isSolitary then
        return false
    end

    sentence.isSolitary = false
    sentence.solitaryUntil = 0
    self:freeSolitarySlot(sentence)

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `is_solitary` = 0, `solitary_until` = 0 WHERE `id` = ?",
        { sentence.id }
    )

    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
    local sourceId = player and getPlayerSource(player)
    if sourceId and sentence.cellId then
        TriggerClientEvent("p_policejob/client/prison/moveToCell", sourceId, sentence.cellId)
    end

    return true
end

lib.callback.register("p_policejob/server/prison/getRemainingTime", function(sourceId)
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return 0
    end

    local sentence = Prison.sentences[identifier]
    if not sentence then
        return 0
    end

    if sentence.releaseAt == 0 then
        return -1
    end

    return math.max(0, sentence.releaseAt - os.time())
end)

lib.callback.register("p_policejob/server/prison/getAllPrisoners", function(sourceId)
    if not Prison:hasJobAccess(sourceId) then
        return {}
    end

    local prisoners = {}

    for identifier, sentence in pairs(Prison.sentences) do
        local isOnline = false
        local playerId = nil
        local player = Bridge.Framework.getPlayerByUniqueId(identifier)

        if player then
            playerId = getPlayerSource(player)
            isOnline = playerId ~= nil
        end

        prisoners[#prisoners + 1] = {
            id = sentence.id,
            identifier = identifier,
            playerName = sentence.playerName,
            officerName = sentence.officerName,
            reason = sentence.reason,
            sentenceTime = sentence.sentenceTime,
            remaining = computeRemainingSeconds(sentence),
            cellId = sentence.cellId,
            isCommunityService = sentence.isCommunityService,
            isSolitary = sentence.isSolitary,
            solitaryUntil = sentence.solitaryUntil,
            status = sentence.status,
            isOnline = isOnline,
            playerId = playerId,
        }
    end

    return prisoners
end)

RegisterNetEvent("p_policejob/server/prison/management/release", function(data)
    local officerId = source
    if not Prison:hasJobAccess(officerId) then
        return
    end
    if not data or not data.identifier then
        return
    end

    Prison:releasePrisoner(data.identifier, officerId)
    Bridge.Notify.showNotify(officerId, locale("prison_prisoner_released"), "success")
end)

RegisterNetEvent("p_policejob/server/prison/management/reduceSentence", function(data)
    local officerId = source
    if not Prison:hasJobAccess(officerId) then
        return
    end
    if not data or not data.identifier or not data.minutes then
        return
    end

    local seconds = math.max(0, tonumber(data.minutes) or 0) * 60
    Prison:reduceSentence(data.identifier, seconds)
    Bridge.Notify.showNotify(officerId, locale("prison_sentence_reduced"), "success")
    Bridge.Logs.Send(
        officerId,
        "Prison",
        ("Reduced sentence for %s by %d minutes"):format(data.identifier, data.minutes),
        Config.Webhooks.prison
    )
end)

RegisterNetEvent("p_policejob/server/prison/management/increaseSentence", function(data)
    local officerId = source
    if not Prison:hasJobAccess(officerId) then
        return
    end
    if not data or not data.identifier or not data.minutes then
        return
    end

    local seconds = math.max(0, tonumber(data.minutes) or 0) * 60
    Prison:increaseSentence(data.identifier, seconds)
    Bridge.Notify.showNotify(officerId, locale("prison_sentence_increased_by"), "success")
    Bridge.Logs.Send(
        officerId,
        "Prison",
        ("Increased sentence for %s by %d minutes"):format(data.identifier, data.minutes),
        Config.Webhooks.prison
    )
end)

RegisterNetEvent("p_policejob/server/prison/management/solitary", function(data)
    local officerId = source
    if not Prison:hasJobAccess(officerId) then
        return
    end
    if not data or not data.identifier then
        return
    end

    if data.release then
        Prison:releaseFromSolitary(data.identifier)
        Bridge.Notify.showNotify(officerId, locale("prison_solitary_released"), "success")
    else
        local maxTime = Config.Prison.Solitary.maxTime
        local minutes = math.max(1, math.min(maxTime, tonumber(data.minutes) or 15))
        local success, reason = Prison:sendToSolitary(data.identifier, minutes)

        if success then
            Bridge.Notify.showNotify(officerId, locale("prison_sent_to_solitary"), "success")
        elseif reason == "full" then
            Bridge.Notify.showNotify(officerId, locale("prison_solitary_full"), "error")
            return
        else
            return
        end
    end

    local action = data.release and "Released from" or "Sent to"
    Bridge.Logs.Send(
        officerId,
        "Prison",
        ("%s solitary for %s"):format(action, data.identifier),
        Config.Webhooks.prison
    )
end)

RegisterNetEvent("p_policejob/server/prison/management/moveToCell", function(data)
    local officerId = source
    if not Prison:hasJobAccess(officerId) then
        return
    end
    if not data or not data.identifier or not data.cellId then
        return
    end

    local sentence = Prison.sentences[data.identifier]
    if not sentence then
        return
    end

    if sentence.cellId then
        Prison:freeCell(sentence.cellId)
    end

    sentence.cellId = data.cellId
    Prison:assignCell(data.cellId, data.identifier)

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `cell_id` = ? WHERE `id` = ?",
        { data.cellId, sentence.id }
    )

    local player = Bridge.Framework.getPlayerByUniqueId(data.identifier)
    local sourceId = player and getPlayerSource(player)
    if sourceId then
        TriggerClientEvent("p_policejob/client/prison/moveToCell", sourceId, data.cellId)
    end
end)

RegisterNetEvent("p_policejob/server/prison/jobComplete", function(data)
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return
    end

    local sentence = Prison.sentences[identifier]
    if not sentence then
        return
    end
    if not data or not data.jobId then
        return
    end

    local defaultJobs = Config.Prison.PrisonJobs and Config.Prison.PrisonJobs.defaultJobs or {}
    local jobConfig = nil

    for _, job in ipairs(defaultJobs) do
        if job.id == data.jobId then
            jobConfig = job
            break
        end
    end

    if not jobConfig then
        return
    end

    local now = os.time()
    local cooldownKey = identifier .. ":" .. jobConfig.id
    local cooldownUntil = prisonJobCooldowns[cooldownKey]

    if cooldownUntil and now < cooldownUntil then
        Bridge.Notify.showNotify(sourceId, "This job is on cooldown.", "error")
        return
    end

    local duration = jobConfig.duration or 30
    prisonJobCooldowns[cooldownKey] = now + duration

    local stopsPerJob = tonumber(Config.Prison.PrisonJobs and Config.Prison.PrisonJobs.stopsPerJob) or 5
    if stopsPerJob < 1 then
        stopsPerJob = 1
    end

    local stopsCompleted = math.max(0, math.min(stopsPerJob, tonumber(data.stopsCompleted) or 0))
    if stopsCompleted <= 0 then
        return
    end

    local timeReduction = (tonumber(jobConfig.timeReduction) or 0) * stopsCompleted
    local payment = (tonumber(jobConfig.payment) or 0) * stopsCompleted

    if timeReduction > 0 then
        Prison:reduceSentence(identifier, timeReduction)
    end

    if payment > 0 then
        Bridge.Framework.removeMoney(sourceId, "cash", -payment)
    end
end)

RegisterNetEvent("p_policejob/server/prison/cellStash/open", function(cellId)
    local sourceId = source
    local cellStash = Config.Prison.CellStash

    if not cellStash or not cellStash.enabled then
        return
    end

    cellId = tonumber(cellId)
    if not cellId then
        return
    end

    local isValidCell = false
    if Prison.Map and Prison.Map.cells then
        for _, cell in ipairs(Prison.Map.cells) do
            if cell.id == cellId then
                isValidCell = true
                break
            end
        end
    end

    if not isValidCell then
        return
    end

    local identifier = Bridge.Framework.getUniqueId(sourceId)
    local sentence = identifier and Prison.sentences[identifier]
    if not sentence or sentence.status ~= "active" or sentence.cellId ~= cellId then
        return
    end

    local stashId = ("p_policejob_cell_%d"):format(cellId)
    if cellStashRegistered[stashId] then
        return
    end

    cellStashRegistered[stashId] = true

    if Bridge.Inventory.registerStash then
        Bridge.Inventory.registerStash(
            stashId,
            stashId,
            cellStash.slots or 2,
            cellStash.maxWeight or 8000
        )
    end
end)

RegisterNetEvent("p_policejob/server/prison/communityTaskComplete", function()
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return
    end

    local sentence = Prison.sentences[identifier]
    if not sentence or not sentence.isCommunityService then
        return
    end

    local tickRate = Config.Prison.Sentence.tickRate
    Prison:reduceSentence(identifier, tickRate)
end)

RegisterNetEvent("p_policejob/server/prison/management/releaseAllExpired", function()
    local officerId = source
    if not Prison:hasJobAccess(officerId) then
        return
    end

    local now = os.time()
    local expiredIdentifiers = {}

    for identifier, sentence in pairs(Prison.sentences) do
        if sentence.releaseAt > 0 and (sentence.releaseAt - now) <= 0 then
            expiredIdentifiers[#expiredIdentifiers + 1] = identifier
        end
    end

    for _, identifier in ipairs(expiredIdentifiers) do
        Prison:releasePrisoner(identifier, officerId)
    end

    Bridge.Notify.showNotify(
        officerId,
        ("Released %d expired sentence(s)."):format(#expiredIdentifiers),
        "success"
    )
end)

AddEventHandler("p_bridge/server/playerLoaded", function(sourceId)
    Wait(3000)

    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return
    end

    local sentence = Prison.sentences[identifier]
    if sentence and sentence.status == "active" then
        restorePlayerPrisonState(sourceId, sentence, "")
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for identifier, sentence in pairs(Prison.sentences) do
        if sentence.isCommunityService then
            local player = Bridge.Framework.getPlayerByUniqueId(identifier)
            local sourceId = player and getPlayerSource(player)
            if sourceId then
                SetPlayerRoutingBucket(sourceId, 0)
            end
        end
    end
end)

AddEventHandler("playerDropped", function()
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return
    end

    local sentence = Prison.sentences[identifier]
    if not sentence then
        return
    end

    local remaining = 0
    if sentence.releaseAt ~= 0 then
        remaining = math.max(0, sentence.releaseAt - os.time())
    end

    MySQL.update(
        "UPDATE `p_policejob_prison_sentences` SET `remaining_time` = ? WHERE `id` = ?",
        { remaining, sentence.id }
    )
end)

CreateThread(function()
    while true do
        if next(Prison.sentences) then
            break
        end

        Wait(5000)

        local countResult = MySQL.query.await(
            "SELECT COUNT(*) as cnt FROM `p_policejob_prison_sentences` WHERE `status` = ?",
            { "active" }
        )

        if countResult and countResult[1] and countResult[1].cnt == 0 then
            break
        end
    end

    while true do
        Wait(30000)

        local now = os.time()
        local expiredIdentifiers = {}
        local remainingUpdates = {}

        for identifier, sentence in pairs(Prison.sentences) do
            if sentence.releaseAt > 0 then
                local remaining = sentence.releaseAt - now
                if remaining <= 0 then
                    expiredIdentifiers[#expiredIdentifiers + 1] = identifier
                else
                    local player = Bridge.Framework.getPlayerByUniqueId(identifier)
                    local sourceId = player and getPlayerSource(player)
                    if sourceId then
                        TriggerClientEvent("p_policejob/client/prison/updateSentence", sourceId, remaining)
                    end

                    remainingUpdates[#remainingUpdates + 1] = {
                        remaining = remaining,
                        id = sentence.id,
                    }
                end
            end

            if sentence.isSolitary and sentence.solitaryUntil > 0 and now >= sentence.solitaryUntil then
                Prison:releaseFromSolitary(identifier)
            end
        end

        for _, identifier in ipairs(expiredIdentifiers) do
            Prison:releasePrisoner(identifier)
        end

        for _, update in ipairs(remainingUpdates) do
            MySQL.update(
                "UPDATE `p_policejob_prison_sentences` SET `remaining_time` = ? WHERE `id` = ?",
                { update.remaining, update.id }
            )
        end
    end
end)

exports("sendToJail", function(officerId, targetId, minutes, reason, isCommunityService)
    return Prison:sendToJail(officerId, targetId, minutes, reason, isCommunityService)
end)

exports("releasePrisoner", function(identifier)
    return Prison:releasePrisoner(identifier)
end)

exports("EscapeJail", function(playerRef)
    local identifier = playerRef
    if type(playerRef) == "number" then
        identifier = Bridge.Framework.getUniqueId(playerRef)
    end
    if not identifier then
        return false
    end
    return Prison:escapeJail(identifier)
end)

exports("reduceSentence", function(identifier, minutes)
    return Prison:reduceSentence(identifier, minutes * 60)
end)

exports("increaseSentence", function(identifier, minutes)
    return Prison:increaseSentence(identifier, minutes * 60)
end)

exports("isPlayerInPrison", function(sourceId)
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier then
        return false
    end
    return Prison.sentences[identifier] ~= nil
end)

exports("getAllPrisoners", function()
    return Prison.sentences
end)

exports("getPrisonerInfo", function(playerRef)
    local identifier = playerRef
    if type(playerRef) == "number" then
        identifier = Bridge.Framework.getUniqueId(playerRef)
    end
    if not identifier then
        return nil
    end
    return Prison.sentences[identifier]
end)

exports("getRemainingTime", function(playerRef)
    local identifier = playerRef
    if type(playerRef) == "number" then
        identifier = Bridge.Framework.getUniqueId(playerRef)
    end
    if not identifier then
        return 0
    end

    local sentence = Prison.sentences[identifier]
    if not sentence or sentence.status ~= "active" then
        return 0
    end

    if sentence.isLife then
        return -1
    end

    return math.max(0, (sentence.releaseAt or 0) - os.time())
end)

function formatSentenceRemaining(sentence)
    if sentence.isLife then
        return "LIFE"
    end

    local remaining = math.max(0, (sentence.releaseAt or 0) - os.time())
    return ("%dm"):format(math.ceil(remaining / 60))
end

function validateShopPurchase(sourceId, purchaseData, shopItems)
    if not purchaseData or not purchaseData.item or not purchaseData.price then
        return nil
    end

    local quantity = math.max(1, math.min(10, tonumber(purchaseData.quantity) or 1))
    local totalPrice = tonumber(purchaseData.price) * quantity
    local isValid = false

    for _, shopItem in ipairs(shopItems) do
        if shopItem.name == purchaseData.item and shopItem.price == tonumber(purchaseData.price) then
            isValid = true
            break
        end
    end

    if not isValid then
        return nil
    end

    local cash = Bridge.Framework.getMoney(sourceId, "cash")
    if totalPrice > cash then
        Bridge.Notify.showNotify(sourceId, ("Not enough money ($%d needed)"):format(totalPrice), "error")
        return nil
    end

    return quantity, totalPrice
end

function processShopPurchase(sourceId, purchaseData, shopItems)
    local quantity, totalPrice = validateShopPurchase(sourceId, purchaseData, shopItems)
    if not quantity then
        return
    end

    Bridge.Framework.removeMoney(sourceId, "cash", totalPrice)
    Bridge.Inventory.addItem(sourceId, purchaseData.item, quantity)
    Bridge.Notify.showNotify(sourceId, ("Purchased %dx %s"):format(quantity, purchaseData.item), "success")
end

if Config.Prison.Commands and Config.Prison.Commands.enabled then
    local commandRestricted = Config.Prison.Commands.restricted
    if commandRestricted == nil then
        commandRestricted = "group.admin"
    end

    if Config.Prison.Commands.jail and Config.Prison.Commands.jail.enabled then
        lib.addCommand(Config.Prison.Commands.jail.name or "jail", {
            help = "Send a player to jail",
            params = {
                { name = "id", type = "number", help = "Player server ID" },
                { name = "type", type = "string", help = "Sentence type: 'prison', 'community' or 'life'", optional = true },
                { name = "length", type = "number", help = "Sentence length in minutes (ignored for life)", optional = true },
                { name = "reason", type = "string", help = "Reason for jailing", optional = true },
            },
            restricted = commandRestricted,
        }, function(sourceId, args)
            local targetId = args.id
            local sentenceType = tostring(args.type or "prison"):lower()
            local length = args.length
            local reason = args.reason or "Admin action"

            if sentenceType ~= "prison" and sentenceType ~= "community" and sentenceType ~= "life" then
                return Bridge.Notify.showNotify(sourceId, "Invalid type. Use 'prison', 'community' or 'life'.", "error")
            end

            local isCommunityService = sentenceType == "community"
            local isLifeSentence = sentenceType == "life"

            if not isLifeSentence and (not length or length <= 0) then
                return Bridge.Notify.showNotify(sourceId, "You must provide a sentence length (minutes).", "error")
            end

            if not Bridge.Framework.getUniqueId(targetId) then
                return Bridge.Notify.showNotify(sourceId, locale("player_not_found"), "error")
            end

            Prison:sendToJail(
                sourceId,
                targetId,
                isLifeSentence and 0 or length,
                reason,
                isCommunityService,
                { lifeSentence = isLifeSentence }
            )
        end)
    end

    if Config.Prison.Commands.unjail and Config.Prison.Commands.unjail.enabled then
        lib.addCommand(Config.Prison.Commands.unjail.name or "unjail", {
            help = "Release a prisoner by their server ID",
            params = {
                { name = "id", type = "number", help = "Player server ID" },
            },
            restricted = commandRestricted,
        }, function(sourceId, args)
            local identifier = Bridge.Framework.getUniqueId(args.id)
            if not identifier then
                return Bridge.Notify.showNotify(sourceId, locale("player_not_found"), "error")
            end

            if Prison:releasePrisoner(identifier, sourceId) then
                Bridge.Notify.showNotify(sourceId, locale("prison_prisoner_released"), "success")
            else
                Bridge.Notify.showNotify(sourceId, locale("prison_inmate_not_found"), "error")
            end
        end)
    end

    if Config.Prison.Commands.jailtime and Config.Prison.Commands.jailtime.enabled then
        lib.addCommand(Config.Prison.Commands.jailtime.name or "jailtime", {
            help = "Show the remaining sentence for a player",
            params = {
                { name = "id", type = "number", help = "Player server ID (defaults to you)", optional = true },
            },
            restricted = commandRestricted,
        }, function(sourceId, args)
            local targetId = args.id or sourceId
            local identifier = Bridge.Framework.getUniqueId(targetId)
            local sentence = identifier and Prison.sentences[identifier]

            if not sentence or sentence.status ~= "active" then
                return Bridge.Notify.showNotify(sourceId, locale("prison_inmate_not_found"), "error")
            end

            local displayName = sentence.playerName or tostring(targetId)
            Bridge.Notify.showNotify(
                sourceId,
                ("%s: %s"):format(displayName, formatSentenceRemaining(sentence)),
                "inform"
            )
        end)
    end

    if Config.Prison.Commands.prisoners and Config.Prison.Commands.prisoners.enabled then
        lib.addCommand(Config.Prison.Commands.prisoners.name or "prisoners", {
            help = "List every currently jailed player",
            params = {},
            restricted = commandRestricted,
        }, function(sourceId)
            local lines = {}

            for _, sentence in pairs(Prison.sentences) do
                if sentence.status == "active" then
                    local sentenceType = sentence.isCommunityService and "community" or "prison"
                    lines[#lines + 1] = ("%s (%s) - %s"):format(
                        sentence.playerName or "?",
                        sentenceType,
                        formatSentenceRemaining(sentence)
                    )
                end
            end

            if #lines == 0 then
                return Bridge.Notify.showNotify(sourceId, "There are no prisoners right now.", "inform")
            end

            Bridge.Notify.showNotify(sourceId, table.concat(lines, "\n"), "inform")
        end)
    end
end

RegisterNetEvent("p_policejob/server/prison/commissary/buy", function(data)
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier or not Prison.sentences[identifier] then
        return
    end

    processShopPurchase(sourceId, data, Config.Prison.Commissary.items)
end)

RegisterNetEvent("p_policejob/server/prison/illegalshop/buy", function(data)
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier or not Prison.sentences[identifier] then
        return
    end

    processShopPurchase(sourceId, data, Config.Prison.IllegalShop.items)
end)

RegisterNetEvent("p_policejob/server/prison/npc_trade/buy", function(data)
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier or not Prison.sentences[identifier] then
        return
    end

    if not data or not data.item or not data.price then
        return
    end

    local quantity = math.max(1, math.min(10, tonumber(data.quantity) or 1))
    local totalPrice = tonumber(data.price) * quantity
    local isValid = false
    local npcIndex = data.npcIndex

    if npcIndex and Prison.Map and Prison.Map.npcs and Prison.Map.npcs[npcIndex] then
        local npc = Prison.Map.npcs[npcIndex]
        if npc.tradeItems then
            for _, tradeItem in ipairs(npc.tradeItems) do
                if tradeItem.name == data.item and tradeItem.price == tonumber(data.price) then
                    isValid = true
                    break
                end
            end
        end
    end

    if not isValid then
        return
    end

    local cash = Bridge.Framework.getMoney(sourceId, "cash")
    if totalPrice > cash then
        Bridge.Notify.showNotify(sourceId, ("Not enough money ($%d needed)"):format(totalPrice), "error")
        return
    end

    Bridge.Framework.removeMoney(sourceId, "cash", totalPrice)
    Bridge.Inventory.addItem(sourceId, data.item, quantity)
    Bridge.Notify.showNotify(sourceId, ("Purchased %dx %s"):format(quantity, data.item), "success")
end)

RegisterNetEvent("p_policejob/server/prison/npc_trade/execute", function(data)
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier or not Prison.sentences[identifier] then
        return
    end

    if not data or not data.npcIndex or not data.offeredItems or not data.requestedItem then
        return
    end

    local npc = Prison.Map and Prison.Map.npcs and Prison.Map.npcs[data.npcIndex]
    if not npc or not npc.tradeItems then
        return
    end

    local requestedTradeItem = nil
    for _, tradeItem in ipairs(npc.tradeItems) do
        if tradeItem.name == data.requestedItem then
            requestedTradeItem = tradeItem
            break
        end
    end

    if not requestedTradeItem then
        return
    end

    local offerValue = 0
    for _, offeredItem in ipairs(data.offeredItems) do
        local itemCount = Bridge.Inventory.getItemCount(sourceId, offeredItem.name)
        if itemCount < offeredItem.quantity then
            Bridge.Notify.showNotify(sourceId, "You don't have enough items", "error")
            return
        end
        offerValue = offerValue + (5 * offeredItem.quantity)
    end

    if offerValue < requestedTradeItem.price then
        Bridge.Notify.showNotify(sourceId, "Your offer is not valuable enough", "error")
        return
    end

    for _, offeredItem in ipairs(data.offeredItems) do
        Bridge.Inventory.removeItem(sourceId, offeredItem.name, offeredItem.quantity)
    end

    Bridge.Inventory.addItem(sourceId, requestedTradeItem.name, 1)
    Bridge.Notify.showNotify(
        sourceId,
        "Trade successful! You received " .. (requestedTradeItem.label or requestedTradeItem.name),
        "success"
    )
end)

lib.callback.register("p_policejob/server/prison/getTradeItems", function(sourceId)
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier or not Prison.sentences[identifier] then
        return {}
    end

    local items = Bridge.Inventory.getPlayerItems(sourceId)
    if not items then
        return {}
    end

    local tradeItems = {}
    for _, item in ipairs(items) do
        local count = item.count or item.amount or 0
        if count > 0 then
            tradeItems[#tradeItems + 1] = {
                name = item.name,
                label = item.label or item.name,
                count = count,
                value = 5,
            }
        end
    end

    return tradeItems
end)

RegisterNetEvent("p_policejob/server/prison/trade/send", function(data)
    local sourceId = source
    local identifier = Bridge.Framework.getUniqueId(sourceId)
    if not identifier or not Prison.sentences[identifier] then
        return
    end

    if not data or not data.targetId or not data.items then
        return
    end

    local targetId = tonumber(data.targetId)
    if not targetId or targetId < 1 then
        return
    end

    local targetIdentifier = Bridge.Framework.getUniqueId(targetId)
    if not targetIdentifier or not Prison.sentences[targetIdentifier] then
        Bridge.Notify.showNotify(sourceId, "That player is not in prison", "error")
        return
    end

    for _, item in ipairs(data.items) do
        local itemName = tostring(item.name)
        local quantity = math.max(1, math.min(100, tonumber(item.quantity) or 0))
        local itemCount = Bridge.Inventory.getItemCount(sourceId, itemName)

        if itemCount and quantity <= itemCount then
            Bridge.Inventory.removeItem(sourceId, itemName, quantity)
            Bridge.Inventory.addItem(targetId, itemName, quantity)
        end
    end

    Bridge.Notify.showNotify(sourceId, "Trade sent!", "success")
    Bridge.Notify.showNotify(targetId, "You received items from a trade", "info")
end)

lib.addCommand("jailself", {
    help = "Send yourself to jail (admin)",
    params = {
        { name = "time", type = "number", help = "Sentence time in minutes" },
        { name = "reason", type = "string", help = "Reason for jailing", optional = true },
    },
    restricted = "group.admin",
}, function(sourceId, args)
    local reason = args.reason or "Admin self-jail"

    if Prison:sendToJail(sourceId, sourceId, args.time, reason, false) then
        Bridge.Notify.showNotify(sourceId, locale("prison_player_sent", "yourself"), "success")
    end
end)

lib.addCommand("prisonmanagement", {
    help = "Open prison management panel",
    params = {},
    restricted = false,
}, function(sourceId)
    TriggerClientEvent("p_policejob/client/prison/openManagement", sourceId)
end)
