Judgments = {}

lib.callback.register("p_mdt/server/judgments/issue", function(playerSource, data)
    local success = Editable:issueJudgment(playerSource, data)

    if success then
        local targetIds = {}
        for _, citizen in pairs(data.citizens) do
            targetIds[#targetIds + 1] = citizen.identifier
        end

        MySQL.insert([[
            INSERT INTO p_mdt_judgments (targets, charges, timestamp, officer)
            VALUES (?, ?, ?, ?)
        ]], {
            json.encode(targetIds),
            json.encode(data.charges),
            os.time(),
            json.encode({
                identifier = Bridge.Framework.getUniqueId(playerSource),
                name = Bridge.Framework.getPlayerName(playerSource),
            }),
        })

        Logs:new(playerSource, {
            category = "judgments",
            action = "issue",
            message = ("Issued judgment for targets %s"):format(table.concat(targetIds, ", ")),
        })
    end

    return success
end)

function Judgments.getCitizenJudgments(self, citizenId)
    local judgments = {}
    local index = 1
    local rows = MySQL.query.await([[
        SELECT * FROM p_mdt_judgments
        WHERE JSON_CONTAINS(targets, JSON_QUOTE(?))
    ]], { citizenId })

    for _, row in ipairs(rows) do
        local charges = json.decode(row.charges)
        for _, charge in pairs(charges) do
            judgments[index] = {
                id = row.id,
                title = charge.title,
                fine = charge.customFine,
                sentence = charge.customSentence,
                timestamp = row.timestamp,
                notes = row.notes,
                officer = json.decode(row.officer),
            }
            index = index + 1
        end
    end

    return judgments
end
