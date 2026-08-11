if not Config.Tickets.enabled then
    return
end

Tickets = {
    records = {},
    pendingSigns = {},
}

MySQL.ready(function()
    MySQL.query(
        "CREATE TABLE IF NOT EXISTS `police_tickets` (`id` INT AUTO_INCREMENT PRIMARY KEY, `ticket_number` VARCHAR(20) NOT NULL, `citizen_name` VARCHAR(100) NOT NULL, `citizen_id` VARCHAR(50) NOT NULL, `vehicle_plate` VARCHAR(20) DEFAULT '', `vehicle_model` VARCHAR(50) DEFAULT '', `violations` LONGTEXT NOT NULL, `total_fine` INT NOT NULL DEFAULT 0, `total_points` INT NOT NULL DEFAULT 0, `location` VARCHAR(200) DEFAULT '', `notes` TEXT DEFAULT '', `status` VARCHAR(20) NOT NULL DEFAULT 'pending', `issued_by` VARCHAR(100) NOT NULL, `officer_id` VARCHAR(50) NOT NULL, `signed` TINYINT(1) NOT NULL DEFAULT 0, `signature` LONGTEXT DEFAULT NULL, `points_applied` TINYINT(1) NOT NULL DEFAULT 0, `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
        {},
        function()
            MySQL.query("ALTER TABLE `police_tickets` ADD COLUMN IF NOT EXISTS `signature` LONGTEXT DEFAULT NULL", {})
            MySQL.query("ALTER TABLE `police_tickets` ADD COLUMN IF NOT EXISTS `points_applied` TINYINT(1) NOT NULL DEFAULT 0", {})
            MySQL.query("CREATE TABLE IF NOT EXISTS `police_license_points` (`citizen_id` VARCHAR(50) PRIMARY KEY, `points` INT NOT NULL DEFAULT 0, `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)", {})
            local rows = MySQL.query.await("SELECT * FROM police_tickets ORDER BY id DESC")
            if rows then
                for i = 1, #rows do
                    local row = rows[i]
                    row.violations = json.decode(row.violations) or {}
                    Tickets.records[#Tickets.records + 1] = Tickets:formatRecord(row)
                end
            end
            Bridge.Debug(("[Tickets] Loaded %d ticket records"):format(#Tickets.records))
        end
    )
end)

function Tickets.formatRecord(self, row)
    return {
        id = tostring(row.id),
        ticketNumber = row.ticket_number,
        citizenName = row.citizen_name,
        citizenId = row.citizen_id,
        vehiclePlate = row.vehicle_plate or "",
        vehicleModel = row.vehicle_model or "",
        violations = row.violations,
        totalFine = row.total_fine,
        totalPoints = row.total_points,
        location = row.location or "",
        notes = row.notes or "",
        status = row.status,
        issuedBy = row.issued_by,
        signed = row.signed == true,
        signature = row.signature or nil,
        pointsApplied = row.points_applied == true,
        issuedAt = row.created_at and tostring(row.created_at) or tostring(os.time() * 1000),
    }
end

function Tickets.generateNumber(self)
    local year = os.date("%Y")
    local sequence = #self.records + 1
    return ("TK-%s-%04d"):format(year, sequence)
end

function Tickets.getCitizenPoints(self, citizenId)
    if not citizenId or citizenId == "" then
        return 0
    end
    local row = MySQL.single.await(
        "SELECT points FROM police_license_points WHERE citizen_id = ?",
        { citizenId }
    )
    return row and row.points or 0
end

function Tickets.findPlayerByCitizenId(self, citizenId)
    if not citizenId or citizenId == "" then
        return nil
    end
    for _, playerId in ipairs(GetPlayers()) do
        local serverId = tonumber(playerId)
        if serverId then
            local uniqueId = tostring(Bridge.Framework.getUniqueId(serverId, true))
            if uniqueId == tostring(citizenId) then
                return serverId
            end
        end
    end
    return nil
end

function Tickets.applyPoints(self, ticket, targetPlayerId)
    local pointsConfig = Config.Tickets.points
    if not pointsConfig or not pointsConfig.enabled then
        return
    end
    if ticket.pointsApplied or ticket.totalPoints <= 0 then
        return
    end
    ticket.pointsApplied = true
    MySQL.update("UPDATE police_tickets SET points_applied = 1 WHERE id = ?", { tonumber(ticket.id) })
    MySQL.query.await(
        "INSERT INTO police_license_points (citizen_id, points) VALUES (?, ?) ON DUPLICATE KEY UPDATE points = points + VALUES(points)",
        { ticket.citizenId, ticket.totalPoints }
    )
    local totalPoints = self:getCitizenPoints(ticket.citizenId)
    if not targetPlayerId then
        targetPlayerId = self:findPlayerByCitizenId(ticket.citizenId)
    end
    if totalPoints >= pointsConfig.suspendThreshold then
        if pointsConfig.resetOnSuspension then
            MySQL.update("UPDATE police_license_points SET points = 0 WHERE citizen_id = ?", { ticket.citizenId })
        end
        Config.Tickets.OnLicenseSuspended(targetPlayerId, ticket.citizenId, totalPoints)
        if targetPlayerId then
            Bridge.Notify.showNotify(
                targetPlayerId,
                locale("ticket_license_suspended", totalPoints),
                "error"
            )
        end
        Bridge.Logs.Send(
            targetPlayerId,
            "Tickets",
            ("License suspended for %s (%s) - reached %d/%d penalty points"):format(
                ticket.citizenName,
                ticket.citizenId,
                totalPoints,
                pointsConfig.suspendThreshold
            ),
            Config.Webhooks.tickets
        )
    elseif targetPlayerId then
        Bridge.Notify.showNotify(
            targetPlayerId,
            locale("ticket_points_added", ticket.totalPoints, totalPoints, pointsConfig.suspendThreshold),
            "warning"
        )
    end
end

lib.callback.register("p_policejob/server/tickets/getTickets", function(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return {}
    end
    return Tickets.records
end)

lib.callback.register("p_policejob/server/tickets/getNearbyPlayers", function(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return {}
    end
    local officerCoords = GetEntityCoords(GetPlayerPed(playerId))
    local nearbyPlayers = {}
    for _, rawPlayerId in ipairs(GetPlayers()) do
        local serverId = tonumber(rawPlayerId)
        if serverId and serverId ~= playerId then
            local targetPed = GetPlayerPed(serverId)
            if targetPed and targetPed ~= 0 then
                local distance = #(officerCoords - GetEntityCoords(targetPed))
                if distance <= Config.Tickets.maxDistance then
                    local citizenId = Bridge.Framework.getUniqueId(serverId, true)
                    nearbyPlayers[#nearbyPlayers + 1] = {
                        serverId = serverId,
                        name = Bridge.Framework.getPlayerName(serverId),
                        citizenId = citizenId,
                        dist = math.floor(distance),
                        points = Tickets:getCitizenPoints(citizenId),
                    }
                end
            end
        end
    end
    return nearbyPlayers
end)

function Tickets.create(self, data, officerId)
    if not data or not data.citizenName or not data.citizenId or not data.violations or #data.violations == 0 then
        return nil
    end
    local citizenId = data.citizenId
    local totalFine = 0
    local totalPoints = 0
    local resolvedViolations = {}
    local violationLookup = {}
    for _, violation in ipairs(Config.Tickets.violations) do
        violationLookup[violation.id] = violation
    end
    for _, selected in ipairs(data.violations) do
        local violation = violationLookup[selected.id]
        if violation then
            totalFine = totalFine + violation.fine
            totalPoints = totalPoints + violation.points
            resolvedViolations[#resolvedViolations + 1] = {
                id = violation.id,
                name = violation.name,
                fine = violation.fine,
                points = violation.points,
                category = violation.category,
            }
        end
    end
    if #resolvedViolations == 0 then
        return nil
    end
    if totalFine > Config.Tickets.maxFine then
        totalFine = Config.Tickets.maxFine
    end
    local ticketNumber = self:generateNumber()
    local issuedBy = data.issuedBy
    local officerUniqueId = data.officerId
    if officerId then
        if not issuedBy then
            issuedBy = Bridge.Framework.getPlayerName(officerId)
        end
        if not officerUniqueId then
            officerUniqueId = Bridge.Framework.getUniqueId(officerId, true)
        end
    end
    issuedBy = issuedBy or "System"
    officerUniqueId = officerUniqueId or "system"
    local insertId = MySQL.insert.await(
        "INSERT INTO police_tickets (ticket_number, citizen_name, citizen_id, vehicle_plate, vehicle_model, violations, total_fine, total_points, location, notes, status, issued_by, officer_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
            ticketNumber,
            data.citizenName,
            citizenId,
            data.vehiclePlate or "",
            data.vehicleModel or "",
            json.encode(resolvedViolations),
            totalFine,
            totalPoints,
            data.location or "",
            data.notes or "",
            "pending",
            issuedBy,
            officerUniqueId,
        }
    )
    if not insertId then
        return nil
    end
    local ticket = {
        id = tostring(insertId),
        ticketNumber = ticketNumber,
        citizenName = data.citizenName,
        citizenId = citizenId,
        vehiclePlate = data.vehiclePlate or "",
        vehicleModel = data.vehicleModel or "",
        violations = resolvedViolations,
        totalFine = totalFine,
        totalPoints = totalPoints,
        location = data.location or "",
        notes = data.notes or "",
        status = "pending",
        issuedBy = issuedBy,
        signed = false,
        pointsApplied = false,
        issuedAt = tostring(os.time() * 1000),
    }
    Tickets.records[#Tickets.records + 1] = ticket
    Bridge.Logs.Send(
        officerId,
        "Tickets",
        ("Issued ticket %s to %s - Fine: $%d"):format(ticketNumber, data.citizenName, totalFine),
        Config.Webhooks.tickets
    )
    return ticket
end

lib.callback.register("p_policejob/server/tickets/createTicket", function(playerId, data)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return nil
    end
    return Tickets:create(data, playerId)
end)

lib.callback.register("p_policejob/server/tickets/sendForSigning", function(playerId, data)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return false
    end
    if not data or not data.ticketId or not data.targetId then
        return false
    end
    local targetId = tonumber(data.targetId)
    if not targetId or targetId == 0 or not GetPlayerPed(targetId) then
        Bridge.Notify.showNotify(playerId, locale("player_offline"), "error")
        return false
    end
    local officerPed = GetPlayerPed(playerId)
    local targetPed = GetPlayerPed(targetId)
    if not officerPed or not targetPed then
        return false
    end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > Config.Tickets.maxDistance then
        Bridge.Notify.showNotify(playerId, locale("ticket_player_too_far"), "error")
        return false
    end
    local ticket = nil
    for i = 1, #Tickets.records do
        if Tickets.records[i].id == data.ticketId then
            ticket = Tickets.records[i]
            break
        end
    end
    if not ticket then
        return false
    end
    Tickets.pendingSigns[targetId] = {
        ticketId = data.ticketId,
        officerId = playerId,
        ticket = ticket,
        expires = os.time() + Config.Tickets.signTimeout,
    }
    TriggerClientEvent("p_policejob/client/tickets/requestSign", targetId, {
        ticketId = ticket.id,
        ticketNumber = ticket.ticketNumber,
        violations = ticket.violations,
        totalFine = ticket.totalFine,
        totalPoints = ticket.totalPoints,
        officerName = ticket.issuedBy,
        location = ticket.location,
        timeout = Config.Tickets.signTimeout,
    })
    Bridge.Notify.showNotify(playerId, locale("ticket_sent_for_signing"), "success")
    return true
end)

RegisterNetEvent("p_policejob/server/tickets/signTicket", function(data)
    local playerId = source
    if not data or not data.ticketId then
        return
    end
    local pending = Tickets.pendingSigns[playerId]
    if not pending or pending.ticketId ~= data.ticketId then
        return
    end
    for i = 1, #Tickets.records do
        local ticket = Tickets.records[i]
        if ticket.id == data.ticketId then
            ticket.signed = true
            ticket.status = "paid"
            ticket.signature = data.signature or nil
            MySQL.update(
                "UPDATE police_tickets SET signed = 1, status = 'paid', signature = ? WHERE id = ?",
                { data.signature or nil, tonumber(data.ticketId) }
            )
            Config.Tickets.OnPlayerFined(pending.officerId, playerId, ticket.totalFine)
            Tickets:applyPoints(ticket, playerId)
            TriggerClientEvent("p_policejob/client/tickets/onSigned", pending.officerId, {
                ticketId = data.ticketId,
                signature = data.signature or nil,
            })
            Bridge.Notify.showNotify(playerId, locale("ticket_signed", ticket.totalFine), "info")
            Bridge.Notify.showNotify(pending.officerId, locale("ticket_was_signed", ticket.ticketNumber), "success")
            Bridge.Logs.Send(
                playerId,
                "Tickets",
                ("Signed ticket %s - Fine: $%d applied"):format(ticket.ticketNumber, ticket.totalFine),
                Config.Webhooks.tickets
            )
            break
        end
    end
    Tickets.pendingSigns[playerId] = nil
end)

RegisterNetEvent("p_policejob/server/tickets/refuseTicket", function(data)
    local playerId = source
    if not data or not data.ticketId then
        return
    end
    local pending = Tickets.pendingSigns[playerId]
    if not pending or pending.ticketId ~= data.ticketId then
        return
    end
    for i = 1, #Tickets.records do
        local ticket = Tickets.records[i]
        if ticket.id == data.ticketId then
            ticket.status = "contested"
            MySQL.update("UPDATE police_tickets SET status = ? WHERE id = ?", { "contested", tonumber(data.ticketId) })
            Bridge.Notify.showNotify(playerId, locale("ticket_refused"), "warning")
            Bridge.Notify.showNotify(pending.officerId, locale("ticket_was_refused", ticket.ticketNumber), "error")
            Bridge.Logs.Send(
                playerId,
                "Tickets",
                ("Refused to sign ticket %s"):format(ticket.ticketNumber),
                Config.Webhooks.tickets
            )
            break
        end
    end
    Tickets.pendingSigns[playerId] = nil
end)

function Tickets.markPaid(self, ticketId, officerId)
    for i = 1, #self.records do
        local ticket = self.records[i]
        if ticket.id == tostring(ticketId) then
            ticket.status = "paid"
            MySQL.update("UPDATE police_tickets SET status = ? WHERE id = ?", { "paid", tonumber(ticketId) })
            self:applyPoints(ticket, nil)
            Bridge.Logs.Send(
                officerId,
                "Tickets",
                ("Marked ticket %s as paid"):format(ticket.ticketNumber),
                Config.Webhooks.tickets
            )
            return true
        end
    end
    return false
end

function Tickets.delete(self, ticketId, officerId)
    for i = #self.records, 1, -1 do
        local ticket = self.records[i]
        if ticket.id == tostring(ticketId) then
            local ticketNumber = ticket.ticketNumber
            table.remove(self.records, i)
            MySQL.query("DELETE FROM police_tickets WHERE id = ?", { tonumber(ticketId) })
            Bridge.Logs.Send(
                officerId,
                "Tickets",
                ("Deleted ticket %s"):format(ticketNumber),
                Config.Webhooks.tickets
            )
            return true
        end
    end
    return false
end

lib.callback.register("p_policejob/server/tickets/markPaid", function(playerId, ticketId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return false
    end
    return Tickets:markPaid(ticketId, playerId)
end)

lib.callback.register("p_policejob/server/tickets/deleteTicket", function(playerId, ticketId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return false
    end
    return Tickets:delete(ticketId, playerId)
end)

AddEventHandler("playerDropped", function()
    Tickets.pendingSigns[source] = nil
end)

exports("createTicket", function(data)
    return Tickets:create(data, nil)
end)

exports("getAllTickets", function()
    return Tickets.records
end)

exports("getTicket", function(ticketId)
    for i = 1, #Tickets.records do
        if Tickets.records[i].id == tostring(ticketId) then
            return Tickets.records[i]
        end
    end
    return nil
end)

exports("getPlayerTickets", function(citizenId)
    local playerTickets = {}
    for i = 1, #Tickets.records do
        if Tickets.records[i].citizenId == citizenId then
            playerTickets[#playerTickets + 1] = Tickets.records[i]
        end
    end
    return playerTickets
end)

exports("markTicketPaid", function(ticketId)
    return Tickets:markPaid(ticketId, nil)
end)

exports("deleteTicket", function(ticketId)
    return Tickets:delete(ticketId, nil)
end)

exports("getLicensePoints", function(citizenId)
    return Tickets:getCitizenPoints(citizenId)
end)
